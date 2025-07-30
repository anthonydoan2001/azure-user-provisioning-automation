# New-HybridGroup.ps1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$Description,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Security", "Distribution")]
    [string]$GroupType = "Security",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Global", "Universal", "DomainLocal")]
    [string]$GroupScope = "Global",
    
    [Parameter(Mandatory = $false)]
    [string[]]$Members,
    
    [Parameter(Mandatory = $false)]
    [string]$Owner,
    
    
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
$CredentialsPath = "C:\UserProvisioningProject\Config\credentials.json"

if (-not (Test-Path $CredentialsPath)) {
    Write-Host "Configuration file not found. Run 08-UpdateAzureConfig.ps1 first." -ForegroundColor Red
    exit 1
}

try {
    $Credentials = Get-Content $CredentialsPath | ConvertFrom-Json
    $AzureDomain = $Credentials.AzureDomain
    $ADDomain = $Credentials.ADDomain
    
    if (-not $AzureDomain -or -not $ADDomain) {
        Write-Host "Domain configuration incomplete." -ForegroundColor Red
        exit 1
    }
    
    Write-ProvisioningLog "Loaded configuration - Azure Domain: $AzureDomain, AD Domain: $ADDomain"
    
} catch {
    Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "=== HYBRID GROUP PROVISIONING ===" -ForegroundColor Cyan
Write-ProvisioningLog "Starting hybrid group provisioning for: $GroupName"

Write-Host "`nGROUP DETAILS:" -ForegroundColor Cyan
Write-Host "  Group Name: $GroupName" -ForegroundColor White
Write-Host "  Description: $Description" -ForegroundColor White
Write-Host "  Type: $GroupType" -ForegroundColor White
Write-Host "  Scope: $GroupScope" -ForegroundColor White
if ($Owner) { Write-Host "  Owner: $Owner" -ForegroundColor White }
if ($Members) { Write-Host "  Members: $($Members -join ', ')" -ForegroundColor White }

# Active Directory Availability Check
Write-Host "`n1. Checking Active Directory availability..." -ForegroundColor Yellow
$ADAvailable = $false
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $ADDomainInfo = Get-ADDomain -ErrorAction Stop
    $ADAvailable = $true
    Write-Host "   Active Directory available: $($ADDomainInfo.DNSRoot)" -ForegroundColor Green
    Write-ProvisioningLog "Active Directory available: $($ADDomainInfo.DNSRoot)"
}
catch {
    Write-Host "   Warning: Active Directory not available: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-ProvisioningLog "Active Directory not available: $($_.Exception.Message)" "WARNING"
}

# Azure AD Availability Check
Write-Host "`n2. Checking Azure AD availability..." -ForegroundColor Yellow
$AzureAvailable = $false
try {
    # Test connection using background job
    $ConnectionJob = Start-Job -ScriptBlock {
        param($TenantId, $ClientId, $ClientSecret)
        
        Import-Module Microsoft.Graph.Authentication -Force
        $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Cred -NoWelcome
        
        $Context = Get-MgContext
        Disconnect-MgGraph | Out-Null
        return $Context
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
}
catch {
    Write-Host "   Warning: Azure AD not available: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-ProvisioningLog "Azure AD not available: $($_.Exception.Message)" "WARNING"
}

# Service Availability Assessment
if (-not $ADAvailable -and -not $AzureAvailable) {
    Write-Host "   Neither Active Directory nor Azure AD are available" -ForegroundColor Red
    Write-ProvisioningLog "Neither AD nor Azure AD available - cannot provision group" "ERROR"
    exit 1
}

# Active Directory Group Creation
if ($ADAvailable) {
    Write-Host "`n4. Processing Active Directory group..." -ForegroundColor Yellow
        try {
            # Check if group already exists
            $ExistingGroup = $null
            try {
                $ExistingGroup = Get-ADGroup -Identity $GroupName -ErrorAction Stop
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                $ExistingGroup = $null
            }
            catch {
                Write-Host "   Warning: Error checking existing group: $($_.Exception.Message)" -ForegroundColor Yellow
                $ExistingGroup = $null
            }
            
            if ($ExistingGroup) {
                Write-Host "   Warning: AD group already exists: $GroupName" -ForegroundColor Yellow
                Write-ProvisioningLog "AD group already exists: $GroupName" "WARNING"
            } else {
                # Determine target OU
                $TargetOU = "OU=DevelopmentGroups,DC=contoso,DC=local"
                try {
                    Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop | Out-Null
                    Write-Host "   Using target OU: $TargetOU" -ForegroundColor Gray
                }
                catch {
                    $TargetOU = "CN=Users,DC=contoso,DC=local"
                    Write-Host "   Warning: Using default Users container (DevelopmentGroups OU not found)" -ForegroundColor Yellow
                    Write-ProvisioningLog "Using default Users container - DevelopmentGroups OU not found" "WARNING"
                }
                
                # Create group
                $GroupCategory = if ($GroupType -eq "Security") { "Security" } else { "Distribution" }
                
                New-ADGroup -Name $GroupName `
                           -Description $Description `
                           -GroupScope $GroupScope `
                           -GroupCategory $GroupCategory `
                           -Path $TargetOU
                
                Write-Host "   AD group created successfully: $GroupName" -ForegroundColor Green
                Write-ProvisioningLog "AD group created successfully: $GroupName"
                
                # Add initial members
                if ($Members) {
                    foreach ($Member in $Members) {
                        try {
                            # Extract username from email format
                            $Username = if ($Member -like "*@*") { 
                                ($Member -split "@")[0] 
                            } else { 
                                $Member 
                            }
                            
                            # Validate user exists in AD
                            $ADUser = Get-ADUser -Identity $Username -ErrorAction SilentlyContinue
                            if ($ADUser) {
                                Add-ADGroupMember -Identity $GroupName -Members $Username
                                Write-Host "   Added member: $Username" -ForegroundColor Green
                                Write-ProvisioningLog "Added member to AD group: $Username"
                            } else {
                                Write-Host "   Warning: User not found in AD: $Username" -ForegroundColor Yellow
                                Write-ProvisioningLog "User not found in AD: $Username" "WARNING"
                            }
                        }
                        catch {
                            Write-Host "   Warning: Failed to add member $Member`: $($_.Exception.Message)" -ForegroundColor Yellow
                            Write-ProvisioningLog "Failed to add member $Member`: $($_.Exception.Message)" "WARNING"
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "   Failed to create AD group: $($_.Exception.Message)" -ForegroundColor Red
            Write-ProvisioningLog "Failed to create AD group: $($_.Exception.Message)" "ERROR"
        }
} else {
    Write-Host "`n4. Active Directory group creation skipped (AD not available)" -ForegroundColor Yellow
}


# Azure AD Group Creation
if ($AzureAvailable) {
    Write-Host "`n5. Processing Azure AD group..." -ForegroundColor Yellow
        try {
            # Use job pattern for Azure operations
            $AzureGroupJob = Start-Job -ScriptBlock {
                param($TenantId, $ClientId, $ClientSecret, $GroupName, $Description, $GroupType, $Owner, $Members, $AzureDomain)
                
                Import-Module Microsoft.Graph.Authentication -Force
                Import-Module Microsoft.Graph.Groups -Force
                Import-Module Microsoft.Graph.Users -Force
                
                $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
                $Cred = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
                Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Cred -NoWelcome
                
                $Results = @{
                    Success = $false
                    Message = ""
                    GroupCreated = $false
                    GroupExists = $false
                    Warning = ""
                }
                
                try {
                    # Check if group exists
                    $ExistingGroup = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue
                    if ($ExistingGroup) {
                        $Results.GroupExists = $true
                        $Results.Message = "Group already exists"
                    } else {
                        # Azure AD Graph API limitation: Only security groups can be created
                        # Distribution groups must be created as security groups in Azure AD
                        if ($GroupType -eq "Distribution") {
                            $Results.Warning = "Azure AD limitation: Creating as Security group (Distribution groups not supported via Graph API)"
                        }
                        
                        # Create group - ALWAYS as security group for Azure AD
                        $GroupParams = @{
                            DisplayName = $GroupName
                            Description = $Description
                            MailEnabled = $false          # MUST be false for Graph API
                            SecurityEnabled = $true       # MUST be true for Graph API
                            MailNickname = $GroupName.Replace(" ", "").Replace("-", "").Replace("_", "").ToLower()
                        }
                        
                        $NewGroup = New-MgGroup @GroupParams
                        $Results.GroupCreated = $true
                        $Results.Message = "Group created successfully as Security group"
                        
                        # Set owner if specified
                        if ($Owner) {
                            Start-Sleep -Seconds 3  # Allow group creation to propagate
                            $OwnerUPN = if ($Owner -like "*@*") { $Owner } else { "$Owner@$AzureDomain" }
                            $OwnerUser = Get-MgUser -Filter "userPrincipalName eq '$OwnerUPN'" -ErrorAction SilentlyContinue
                            if ($OwnerUser) {
                                try {
                                    $OwnerRef = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($OwnerUser.Id)" }
                                    New-MgGroupOwner -GroupId $NewGroup.Id -BodyParameter $OwnerRef
                                    $Results.Message += " | Owner set: $OwnerUPN"
                                }
                                catch {
                                    $Results.Message += " | Owner set failed: $($_.Exception.Message)"
                                }
                            } else {
                                $Results.Message += " | Owner not found: $OwnerUPN"
                            }
                        }
                        
                        # Add members if specified
                        if ($Members) {
                            Start-Sleep -Seconds 3  # Allow group creation to propagate
                            foreach ($Member in $Members) {
                                try {
                                    $MemberUPN = if ($Member -like "*@*") { $Member } else { "$Member@$AzureDomain" }
                                    $MemberUser = Get-MgUser -Filter "userPrincipalName eq '$MemberUPN'" -ErrorAction SilentlyContinue
                                    if ($MemberUser) {
                                        $MemberRef = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($MemberUser.Id)" }
                                        New-MgGroupMember -GroupId $NewGroup.Id -BodyParameter $MemberRef
                                        $Results.Message += " | Member added: $MemberUPN"
                                    } else {
                                        $Results.Message += " | Member not found: $MemberUPN"
                                    }
                                }
                                catch {
                                    $Results.Message += " | Member add failed: $Member"
                                }
                            }
                        }
                    }
                    $Results.Success = $true
                }
                catch {
                    $Results.Success = $false
                    $Results.Message = $_.Exception.Message
                }
                
                Disconnect-MgGraph | Out-Null
                return $Results
                
            } -ArgumentList $Credentials.TenantId, $Credentials.ClientId, $Credentials.ClientSecret, $GroupName, $Description, $GroupType, $Owner, $Members, $AzureDomain
            
            $JobCompleted = Wait-Job -Job $AzureGroupJob -Timeout 60
            
            if ($JobCompleted) {
                $AzureResult = Receive-Job -Job $AzureGroupJob
                if ($AzureResult.Success) {
                    if ($AzureResult.Warning) {
                        Write-Host "   Warning: $($AzureResult.Warning)" -ForegroundColor Yellow
                        Write-ProvisioningLog $AzureResult.Warning "WARNING"
                    }
                    
                    if ($AzureResult.GroupExists) {
                        Write-Host "   Warning: Azure AD group already exists: $GroupName" -ForegroundColor Yellow
                        Write-ProvisioningLog "Azure AD group already exists: $GroupName" "WARNING"
                    } elseif ($AzureResult.GroupCreated) {
                        Write-Host "   Azure AD group created successfully: $GroupName" -ForegroundColor Green
                        Write-ProvisioningLog "Azure AD group created successfully: $GroupName"
                    }
                    Write-Host "   Details: $($AzureResult.Message)" -ForegroundColor Gray
                } else {
                    Write-Host "   Failed to create Azure AD group: $($AzureResult.Message)" -ForegroundColor Red
                    Write-ProvisioningLog "Failed to create Azure AD group: $($AzureResult.Message)" "ERROR"
                }
            } else {
                Write-Host "   Azure AD group creation timed out" -ForegroundColor Red
                Write-ProvisioningLog "Azure AD group creation timed out" "ERROR"
                Stop-Job -Job $AzureGroupJob -Force
            }
            
            Remove-Job -Job $AzureGroupJob -Force
        }
        catch {
            Write-Host "   Failed to create Azure AD group: $($_.Exception.Message)" -ForegroundColor Red
            Write-ProvisioningLog "Failed to create Azure AD group: $($_.Exception.Message)" "ERROR"
        }
} else {
    Write-Host "`n5. Azure AD group creation skipped (Azure AD not available)" -ForegroundColor Yellow
}

# Provisioning Summary
Write-Host "`n=== GROUP PROVISIONING SUMMARY ===" -ForegroundColor Cyan
Write-Host "Group Name: $GroupName" -ForegroundColor White
Write-Host "Description: $Description" -ForegroundColor White
Write-Host "Type: $GroupType" -ForegroundColor White
Write-Host "Scope: $GroupScope" -ForegroundColor White
Write-Host "AD Available: $(if($ADAvailable){'Yes'}else{'No'})" -ForegroundColor $(if($ADAvailable){'Green'}else{'Red'})
Write-Host "Azure Available: $(if($AzureAvailable){'Yes'}else{'No'})" -ForegroundColor $(if($AzureAvailable){'Green'}else{'Red'})
Write-Host "Mode: Live Run" -ForegroundColor Green

# Add Azure AD limitation note
if ($GroupType -eq "Distribution") {
    Write-Host "`nAZURE AD NOTE:" -ForegroundColor Yellow
    Write-Host "Distribution groups in Azure AD were created as Security groups due to Graph API limitations." -ForegroundColor White
    Write-Host "You can manually convert to mail-enabled distribution groups in the Azure AD admin center if needed." -ForegroundColor White
}
Write-Host "`nNEXT STEPS:" -ForegroundColor Green
Write-Host "1. Verify group creation with Get-ProvisioningStatus.ps1" -ForegroundColor White
Write-Host "2. Add additional members as needed" -ForegroundColor White
Write-Host "3. Configure group permissions and access" -ForegroundColor White
Write-Host "4. Document group purpose and ownership" -ForegroundColor White

Write-Host "`nHYBRID GROUP PROVISIONING COMPLETED" -ForegroundColor Green

Write-ProvisioningLog "Hybrid group provisioning completed for: $GroupName"