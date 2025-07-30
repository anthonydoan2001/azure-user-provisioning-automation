# New-HybridUser.ps1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FirstName,
    
    [Parameter(Mandatory = $true)]
    [string]$LastName,
    
    [Parameter(Mandatory = $true)]
    [string]$Department,
    
    [Parameter(Mandatory = $true)]
    [string]$JobTitle,
    
    [Parameter(Mandatory = $false)]
    [string]$Manager,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "Main Office",
    
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\UserProvisioningProject\Logs\"
)

# Logging Function
function Write-ProvisioningLog {
    param([string]$Message, [string]$Level = "INFO")
    $LogFile = Join-Path $LogPath "provisioning-$(Get-Date -Format 'yyyy-MM-dd').log"
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}else{"Green"})
    
    # Ensure log directory exists
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    $LogEntry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Configuration Management
$ConfigPath = "C:\UserProvisioningProject\Config\settings.json"
$CredentialsPath = "C:\UserProvisioningProject\Config\credentials.json"

if (-not (Test-Path $ConfigPath) -or -not (Test-Path $CredentialsPath)) {
    Write-Host "Configuration files not found. Run 08-UpdateAzureConfig.ps1 first." -ForegroundColor Red
    exit 1
}

try {
    $Config = Get-Content $ConfigPath | ConvertFrom-Json
    $Credentials = Get-Content $CredentialsPath | ConvertFrom-Json
    
    # Load domain configuration
    $AzureDomain = $Credentials.AzureDomain
    $ADDomain = $Credentials.ADDomain
    
    if (-not $AzureDomain -or -not $ADDomain) {
        Write-Host "Domain configuration incomplete. Run 08-UpdateAzureConfig.ps1 to configure domains." -ForegroundColor Red
        exit 1
    }
    
    Write-ProvisioningLog "Loaded configuration - Azure Domain: $AzureDomain, AD Domain: $ADDomain"
    
} catch {
    Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Run 08-UpdateAzureConfig.ps1 to configure the system." -ForegroundColor Yellow
    exit 1
}

# User Account Generation
$SamAccountName = ($FirstName.Substring(0,1) + $LastName).ToLower()
$ADUserPrincipalName = "$SamAccountName@$ADDomain"
$AzureUserPrincipalName = "$SamAccountName@$AzureDomain"
$DisplayName = "$FirstName $LastName"
$EmailAddress = "$SamAccountName@$AzureDomain"

Write-Host "=== HYBRID USER PROVISIONING ===" -ForegroundColor Cyan
Write-ProvisioningLog "Starting hybrid user provisioning for: $DisplayName"

Write-Host "`nUSER DETAILS:" -ForegroundColor Cyan
Write-Host "  Display Name: $DisplayName" -ForegroundColor White
Write-Host "  Username: $SamAccountName" -ForegroundColor White
Write-Host "  AD UPN: $ADUserPrincipalName" -ForegroundColor White
Write-Host "  Azure UPN: $AzureUserPrincipalName" -ForegroundColor White
Write-Host "  Email: $EmailAddress" -ForegroundColor White
Write-Host "  Department: $Department" -ForegroundColor White
Write-Host "  Job Title: $JobTitle" -ForegroundColor White
Write-Host "  Manager: $Manager" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White

# Active Directory Availability Check
Write-Host "`n1. Checking Active Directory availability..." -ForegroundColor Yellow
$ADAvailable = $false
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    # Test Active Directory connection
    $ADDomain = Get-ADDomain -ErrorAction Stop
    $ADAvailable = $true
    Write-Host "   Active Directory available: $($ADDomain.DNSRoot)" -ForegroundColor Green
    Write-ProvisioningLog "Active Directory available: $($ADDomain.DNSRoot)"
}
catch {
    Write-Host "   Warning: Active Directory not available: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-ProvisioningLog "Active Directory not available: $($_.Exception.Message)" "WARNING"
}

# Azure AD Availability Check
Write-Host "`n2. Checking Azure AD availability..." -ForegroundColor Yellow
$AzureAvailable = $false
$Credentials = $null
try {
    # Load configuration
    $ConfigPath = "C:\UserProvisioningProject\Config\settings.json"
    $CredentialsPath = "C:\UserProvisioningProject\Config\credentials.json"
    
    if ((Test-Path $ConfigPath) -and (Test-Path $CredentialsPath)) {
        $Credentials = Get-Content $CredentialsPath | ConvertFrom-Json
        
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        
        $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
        $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
        
        # Test connection using background job
        $ConnectionJob = Start-Job -ScriptBlock {
            param($TenantId, $ClientId, $ClientSecret)
            Import-Module Microsoft.Graph.Authentication
            $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $Cred = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Cred -NoWelcome
            return (Get-MgContext)
        } -ArgumentList $Credentials.TenantId, $Credentials.ClientId, $Credentials.ClientSecret
        
        $JobResult = Wait-Job -Job $ConnectionJob -Timeout 30
        if ($JobResult) {
            $Context = Receive-Job -Job $ConnectionJob
            if ($Context) {
                $AzureAvailable = $true
                Write-Host "   Azure AD available: $($Context.TenantId)" -ForegroundColor Green
                Write-ProvisioningLog "Azure AD available: $($Context.TenantId)"
            }
        } else {
            Stop-Job -Job $ConnectionJob
            Write-Host "   Warning: Azure AD connection timeout" -ForegroundColor Yellow
        }
        Remove-Job -Job $ConnectionJob -Force
    } else {
        Write-Host "   Warning: Azure AD credentials not configured" -ForegroundColor Yellow
        Write-ProvisioningLog "Azure AD credentials not configured" "WARNING"
    }
}
catch {
    Write-Host "   Warning: Azure AD not available: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-ProvisioningLog "Azure AD not available: $($_.Exception.Message)" "WARNING"
}

# Service Availability Assessment
Write-Host "`n3. Determining provisioning options..." -ForegroundColor Yellow
if (-not $ADAvailable -and -not $AzureAvailable) {
    Write-Host "   Neither Active Directory nor Azure AD are available" -ForegroundColor Red
    Write-Host "   Please complete the environment setup first." -ForegroundColor Yellow
    Write-ProvisioningLog "Neither AD nor Azure AD available - cannot provision user" "ERROR"
    exit 1
}

# Active Directory User Creation
if ($ADAvailable) {
    Write-Host "`n4. Processing Active Directory user..." -ForegroundColor Yellow
        try {
            # Check if user already exists
            $ExistingUser = $null
            try {
                $ExistingUser = Get-ADUser -Identity $SamAccountName -ErrorAction Stop
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                # User doesn't exist - proceed with creation
                $ExistingUser = $null
            }
            catch {
                # Handle other errors
                Write-Host "   Warning: Error checking existing user: $($_.Exception.Message)" -ForegroundColor Yellow
                $ExistingUser = $null
            }
            
            if ($ExistingUser) {
                Write-Host "   Warning: AD user already exists: $SamAccountName" -ForegroundColor Yellow
                Write-ProvisioningLog "AD user already exists: $SamAccountName" "WARNING"
            } else {
                # Create Active Directory user
                $SecurePassword = ConvertTo-SecureString "TempPass123!" -AsPlainText -Force
                
                # Determine target organizational unit
                $TargetOU = "OU=DevelopmentUsers,DC=contoso,DC=local"
                try {
                    Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop | Out-Null
                    Write-Host "   Using target OU: $TargetOU" -ForegroundColor Gray
                }
                catch {
                    # Use default Users container
                    $TargetOU = "CN=Users,DC=contoso,DC=local"
                    Write-Host "   Warning: Using default Users container (DevelopmentUsers OU not found)" -ForegroundColor Yellow
                    Write-ProvisioningLog "Using default Users container - DevelopmentUsers OU not found" "WARNING"
                }
                
                # Configure user parameters
                $NewUserParams = @{
                    Name = $DisplayName
                    GivenName = $FirstName
                    Surname = $LastName
                    SamAccountName = $SamAccountName
                    UserPrincipalName = $ADUserPrincipalName  # Use AD domain
                    Path = $TargetOU
                    Department = $Department
                    Title = $JobTitle
                    EmailAddress = $EmailAddress
                    DisplayName = $DisplayName
                    Office = $Location
                    Enabled = $true
                    AccountPassword = $SecurePassword
                    ChangePasswordAtLogon = $true
                    Description = "Created by automation on $(Get-Date -Format 'yyyy-MM-dd')"
                }
                
                New-ADUser @NewUserParams
                
                Write-Host "   AD user created successfully: $SamAccountName" -ForegroundColor Green
                Write-ProvisioningLog "AD user created successfully: $SamAccountName"
                
                # Add to default groups
                $DefaultGroups = @("Domain Users")  # Initialize with Domain Users group
                
                # Add to DevelopmentTeam if available
                try {
                    $DevGroup = Get-ADGroup -Identity "DevelopmentTeam" -ErrorAction Stop
                    $DefaultGroups += "DevelopmentTeam"
                }
                catch {
                    Write-Host "   Warning: DevelopmentTeam group not found, skipping" -ForegroundColor Yellow
                }
                
                foreach ($GroupName in $DefaultGroups) {
                    try {
                        Add-ADGroupMember -Identity $GroupName -Members $SamAccountName -ErrorAction Stop
                        Write-Host "   Added to group: $GroupName" -ForegroundColor Green
                        Write-ProvisioningLog "Added user to group: $GroupName"
                    }
                    catch {
                        Write-Host "   Warning: Could not add to group $GroupName`: $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-ProvisioningLog "Failed to add to group $GroupName`: $($_.Exception.Message)" "WARNING"
                    }
                }
            }
        }
        catch {
            Write-Host "   Failed to create AD user: $($_.Exception.Message)" -ForegroundColor Red
            Write-ProvisioningLog "Failed to create AD user: $($_.Exception.Message)" "ERROR"
        }
} else {
    Write-Host "`n4. Active Directory user creation skipped (AD not available)" -ForegroundColor Yellow
}

# Azure AD User Creation
if ($AzureAvailable) {
    Write-Host "`n5. Processing Azure AD user..." -ForegroundColor Yellow
        try {
            # Connect to Azure AD
            Import-Module Microsoft.Graph.Users -Force
            $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
            $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
            Connect-MgGraph -TenantId $Credentials.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
            
            # Check if user already exists
            $ExistingAzureUser = Get-MgUser -Filter "userPrincipalName eq '$AzureUserPrincipalName'" -ErrorAction SilentlyContinue
            if ($ExistingAzureUser) {
                Write-Host "   Warning: Azure AD user already exists: $AzureUserPrincipalName" -ForegroundColor Yellow
                Write-ProvisioningLog "Azure AD user already exists: $AzureUserPrincipalName" "WARNING"
            } else {
                # Create Azure AD user account
                $PasswordProfile = @{
                    Password = "TempAzurePass123!"
                    ForceChangePasswordNextSignIn = $true
                }
                
                $UserParams = @{
                    DisplayName = $DisplayName
                    GivenName = $FirstName
                    Surname = $LastName
                    UserPrincipalName = $AzureUserPrincipalName  # Use verified Azure domain
                    MailNickname = $SamAccountName
                    AccountEnabled = $true
                    PasswordProfile = $PasswordProfile
                    JobTitle = $JobTitle
                    Department = $Department
                    OfficeLocation = $Location
                    CompanyName = "Contoso Corporation"
                    UsageLocation = "US"
                }
                
                $NewAzureUser = New-MgUser @UserParams
                Write-Host "   Azure AD user created successfully: $($NewAzureUser.UserPrincipalName)" -ForegroundColor Green
                Write-ProvisioningLog "Azure AD user created successfully: $($NewAzureUser.UserPrincipalName)"
            }
            
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Host "   Failed to create Azure AD user: $($_.Exception.Message)" -ForegroundColor Red
            Write-ProvisioningLog "Failed to create Azure AD user: $($_.Exception.Message)" "ERROR"
            try {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        }
} else {
    Write-Host "`n5. Azure AD user creation skipped (Azure AD not available)" -ForegroundColor Yellow
}

# Provisioning Summary
Write-Host "`n=== PROVISIONING SUMMARY ===" -ForegroundColor Cyan
Write-Host "User: $DisplayName" -ForegroundColor White
Write-Host "AD Available: $(if($ADAvailable){'Yes'}else{'No'})" -ForegroundColor $(if($ADAvailable){'Green'}else{'Red'})
Write-Host "Azure Available: $(if($AzureAvailable){'Yes'}else{'No'})" -ForegroundColor $(if($AzureAvailable){'Green'}else{'Red'})
Write-Host "Mode: Live Run" -ForegroundColor Green

Write-Host "`nNEXT STEPS:" -ForegroundColor Green
Write-Host "1. User credentials:" -ForegroundColor White
if ($ADAvailable) {
    Write-Host "   - AD Login: $SamAccountName" -ForegroundColor Gray
    Write-Host "   - AD Password: TempPass123! (must change on first login)" -ForegroundColor Gray
}
if ($AzureAvailable) {
    Write-Host "   - Azure Login: $AzureUserPrincipalName" -ForegroundColor Gray
    Write-Host "   - Azure Password: TempAzurePass123! (must change on first login)" -ForegroundColor Gray
}
Write-Host "2. Assign licenses in Azure AD admin center if needed" -ForegroundColor White
Write-Host "3. Add to additional groups as required" -ForegroundColor White
Write-Host "4. Run Get-ProvisioningStatus.ps1 to verify sync status" -ForegroundColor White

Write-Host "`nHYBRID USER PROVISIONING COMPLETED" -ForegroundColor Green

Write-ProvisioningLog "Hybrid user provisioning completed for: $DisplayName"