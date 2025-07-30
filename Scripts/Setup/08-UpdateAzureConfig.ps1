# 08-UpdateAzureConfig.ps1
# Configure Azure AD connection and domain settings

Write-Host "=== AZURE AD CONFIGURATION ===" -ForegroundColor Cyan

# Ensure Config directory exists
if (-not (Test-Path "Config")) {
    New-Item -Path "Config" -ItemType Directory -Force | Out-Null
}

Write-Host "`nAZURE AD APP REGISTRATION SETUP" -ForegroundColor Yellow
Write-Host "You need to create an App Registration in Azure AD first:" -ForegroundColor White
Write-Host "1. Go to Azure Portal > Azure Active Directory > App registrations" -ForegroundColor Gray
Write-Host "2. Click 'New registration'" -ForegroundColor Gray
Write-Host "3. Name: 'UserProvisioningAutomation'" -ForegroundColor Gray
Write-Host "4. Supported account types: 'Accounts in this organizational directory only'" -ForegroundColor Gray
Write-Host "5. Redirect URI: Leave blank" -ForegroundColor Gray
Write-Host "6. Click 'Register'" -ForegroundColor Gray
Write-Host "7. Go to 'Certificates & secrets' > 'New client secret'" -ForegroundColor Gray
Write-Host "8. Go to 'API permissions' > Add the required permissions" -ForegroundColor Gray

Write-Host "`nREQUIRED API PERMISSIONS:" -ForegroundColor Yellow
Write-Host "Microsoft Graph (Application permissions):" -ForegroundColor White
Write-Host "- User.ReadWrite.All" -ForegroundColor Gray
Write-Host "- Group.ReadWrite.All" -ForegroundColor Gray
Write-Host "- Organization.Read.All" -ForegroundColor Gray
Write-Host "- Directory.ReadWrite.All" -ForegroundColor Gray
Write-Host "Then click 'Grant admin consent for [Your Organization]'" -ForegroundColor White

Write-Host "`nENTER YOUR AZURE AD DETAILS:" -ForegroundColor Yellow

# Get Azure AD configuration
$TenantId = Read-Host "Enter your Tenant ID"
$ClientId = Read-Host "Enter your Client ID (Application ID)"
$ClientSecret = Read-Host "Enter your Client Secret" -AsSecureString

# Get domain information
Write-Host "`nDOMAIN CONFIGURATION:" -ForegroundColor Yellow
Write-Host "Checking your verified domains..." -ForegroundColor Gray

try {
    # Connect to get domain info
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
    
    # Convert SecureString to plain text for connection
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
    $PlainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    $TempSecure = ConvertTo-SecureString $PlainSecret -AsPlainText -Force
    $TempCred = New-Object System.Management.Automation.PSCredential($ClientId, $TempSecure)
    
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $TempCred -NoWelcome
    
    $Org = Get-MgOrganization
    $VerifiedDomains = $Org.VerifiedDomains
    
    Write-Host "Found verified domains:" -ForegroundColor Green
    $DomainList = @()
    $DefaultDomain = $null
    
    for ($i = 0; $i -lt $VerifiedDomains.Count; $i++) {
        $Domain = $VerifiedDomains[$i]
        $Status = if ($Domain.IsDefault) { "(Default)" } else { "" }
        Write-Host "  [$i] $($Domain.Name) $Status" -ForegroundColor White
        $DomainList += $Domain.Name
        if ($Domain.IsDefault) {
            $DefaultDomain = $Domain.Name
        }
    }
    
    # Let user choose domain or use default
    $DomainChoice = Read-Host "`nSelect domain number (or press Enter for default: $DefaultDomain)"
    if ([string]::IsNullOrWhiteSpace($DomainChoice)) {
        $SelectedDomain = $DefaultDomain
    } else {
        $SelectedDomain = $DomainList[[int]$DomainChoice]
    }
    
    Write-Host "Selected domain: $SelectedDomain" -ForegroundColor Green
    
    Disconnect-MgGraph | Out-Null
    
} catch {
    Write-Host "⚠ Could not retrieve domains automatically: $($_.Exception.Message)" -ForegroundColor Yellow
    $SelectedDomain = Read-Host "Enter your Azure AD domain manually (e.g., yourdomain.onmicrosoft.com)"
}

# Get Active Directory domain
Write-Host "`n🏢 ACTIVE DIRECTORY DOMAIN:" -ForegroundColor Yellow
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $ADDomain = (Get-ADDomain).DNSRoot
    Write-Host "Detected AD domain: $ADDomain" -ForegroundColor Green
    $UseDetectedAD = Read-Host "Use this domain? (Y/n)"
    if ($UseDetectedAD.ToUpper() -eq "N") {
        $ADDomain = Read-Host "Enter your AD domain"
    }
} catch {
    Write-Host "⚠ Could not detect AD domain" -ForegroundColor Yellow
    $ADDomain = Read-Host "Enter your AD domain (e.g., contoso.local)"
}

# Create credentials object with domains
$CredentialsObject = @{
    TenantId = $TenantId
    ClientId = $ClientId
    ClientSecret = $PlainSecret
    AzureDomain = $SelectedDomain
    ADDomain = $ADDomain
    ConfiguredDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

# Save credentials
try {
    $CredentialsObject | ConvertTo-Json | Out-File -FilePath "Config\credentials.json" -Encoding UTF8
    Write-Host "`n✅ Configuration saved to Config\credentials.json" -ForegroundColor Green
    
} catch {
    Write-Host "Failed to save credentials: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Update or create settings.json with proper structure
Write-Host "Updating settings.json..." -ForegroundColor Gray
try {
    $SettingsPath = "Config\settings.json"
    
    # Create a proper settings structure
    $Settings = @{
        Environment = "Development"
        ActiveDirectory = @{
            Server = "localhost"
            Domain = $ADDomain
            DefaultOU = "OU=DevelopmentUsers,DC=$(($ADDomain -split '\.')[0]),DC=$(($ADDomain -split '\.')[1])"
            TestOU = "OU=TestEnvironment,DC=$(($ADDomain -split '\.')[0]),DC=$(($ADDomain -split '\.')[1])"
            GroupsOU = "OU=DevelopmentGroups,DC=$(($ADDomain -split '\.')[0]),DC=$(($ADDomain -split '\.')[1])"
            ServiceAccountsOU = "OU=ServiceAccounts,DC=$(($ADDomain -split '\.')[0]),DC=$(($ADDomain -split '\.')[1])"
        }
        AzureAD = @{
            TenantId = $TenantId
            ClientId = $ClientId
            Domain = $SelectedDomain
            Environment = "Development"
        }
        Development = @{
            LogPath = "C:\UserProvisioningProject\Logs\"
            LogLevel = "Verbose"
            TestMode = $true
            BackupPath = "C:\UserProvisioningProject\Backups\"
            ExportPath = "C:\UserProvisioningProject\Data\Export\"
        }
        VMSettings = @{
            AutoShutdown = "20:00"
            TimeZone = "Central Standard Time"
            ProjectPath = "C:\UserProvisioningProject"
        }
        Automation = @{
            UsernameFormat = "{first_initial}{last_name}"
            EmailDomain = $SelectedDomain
            DefaultPassword = "TempPass123!"
            PasswordChangeRequired = $true
            DefaultGroups = @("AllEmployees")
        }
        Domains = @{
            ActiveDirectory = $ADDomain
            AzureAD = $SelectedDomain
            Email = $SelectedDomain
        }
    }
    
    $Settings | ConvertTo-Json -Depth 4 | Out-File -FilePath $SettingsPath -Encoding UTF8
    Write-Host "✅ Updated settings.json with domain information" -ForegroundColor Green
    
} catch {
    Write-Host "⚠ Warning: Could not update settings.json: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "This won't affect the main functionality." -ForegroundColor Gray
}

Write-Host "`n🧪 TESTING CONNECTION..." -ForegroundColor Yellow
try {
    $TestSecure = ConvertTo-SecureString $CredentialsObject.ClientSecret -AsPlainText -Force
    $TestCred = New-Object System.Management.Automation.PSCredential($ClientId, $TestSecure)
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $TestCred -NoWelcome
    
    $Context = Get-MgContext
    if ($Context) {
        Write-Host "✅ CONNECTION SUCCESSFUL!" -ForegroundColor Green
        Write-Host "  Tenant: $($Context.TenantId)" -ForegroundColor Gray
        Write-Host "  Azure Domain: $SelectedDomain" -ForegroundColor Gray
        Write-Host "  AD Domain: $ADDomain" -ForegroundColor Gray
    }
    
    Disconnect-MgGraph | Out-Null
} catch {
    Write-Host "⚠ Connection test failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Please verify your credentials and permissions" -ForegroundColor Yellow
}

# Clear sensitive variables
$PlainSecret = $null
$ClientSecret = $null
$BSTR = $null

Write-Host "`n🔒 SECURITY NOTE:" -ForegroundColor Yellow
Write-Host "- Your credentials are stored in Config\credentials.json" -ForegroundColor White
Write-Host "- This file is excluded from Git via .gitignore" -ForegroundColor White
Write-Host "- Keep this file secure and never share it" -ForegroundColor White

Write-Host "`n📋 CONFIGURATION SUMMARY:" -ForegroundColor Cyan
Write-Host "- Azure AD Domain: $SelectedDomain" -ForegroundColor White
Write-Host "- Active Directory Domain: $ADDomain" -ForegroundColor White
Write-Host "- Tenant ID: $TenantId" -ForegroundColor White
Write-Host "- Client ID: $ClientId" -ForegroundColor White

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Green
Write-Host "- Run: .\Scripts\09-TestAzureConnection.ps1" -ForegroundColor Cyan
Write-Host "- Test user creation: .\Scripts\New-HybridUser.ps1 -FirstName 'Test' -LastName 'User' -Department 'IT' -JobTitle 'Developer' -TestRun" -ForegroundColor Cyan

Write-Host "`n✅ AZURE AD CONFIGURATION COMPLETE!" -ForegroundColor Green