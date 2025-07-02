# 06-CreateProjectStructure.ps1
# Create configuration files and project structure

Write-Host "=== PROJECT STRUCTURE CONFIGURATION ===" -ForegroundColor Cyan

# Ensure we're in the correct directory
Set-Location "C:\UserProvisioningProject"

# Create settings.json configuration
Write-Host "Creating configuration files..." -ForegroundColor Yellow

$Settings = @{
    Environment = "Development"
    ActiveDirectory = @{
        Server = "localhost"
        Domain = "contoso.local"
        DefaultOU = "OU=DevelopmentUsers,DC=contoso,DC=local"
        TestOU = "OU=TestEnvironment,DC=contoso,DC=local"
        GroupsOU = "OU=DevelopmentGroups,DC=contoso,DC=local"
    }
    AzureAD = @{
        TenantId = "YOUR-TENANT-ID-HERE"
        ClientId = "YOUR-CLIENT-ID-HERE"
        Environment = "Development"
    }
    Development = @{
        LogPath = "C:\UserProvisioningProject\Logs\"
        LogLevel = "Verbose"
        TestMode = $true
        BackupPath = "C:\UserProvisioningProject\Backups\"
    }
    VMSettings = @{
        AutoShutdown = "20:00"
        TimeZone = "Central Standard Time"
        ProjectPath = "C:\UserProvisioningProject"
    }
}

try {
    $Settings | ConvertTo-Json -Depth 3 | Out-File -FilePath "Config\settings.json" -Encoding UTF8
    Write-Host "✓ Configuration file created: Config\settings.json" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to create configuration file: $($_.Exception.Message)" -ForegroundColor Red
}

# Create .gitignore file
$GitIgnore = @'
# Sensitive files
Config/credentials.json
Config/secrets.json
*.secret
*.key
*password*

# Logs
Logs/*.log
Logs/*.txt

# Temporary files
Temp/
*.tmp

# Backup files
Backups/

# OS files
.DS_Store
Thumbs.db
desktop.ini

# PowerShell profiles
profile.ps1

# Azure credentials
.azure/
'@

try {
    $GitIgnore | Out-File -FilePath ".gitignore" -Encoding UTF8
    Write-Host "✓ Git ignore file created: .gitignore" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to create .gitignore file: $($_.Exception.Message)" -ForegroundColor Red
}

# Create README.md
$ReadMe = @'
# User Provisioning Automation Project

This project contains PowerShell scripts and tools for automating user provisioning between on-premises Active Directory and Azure AD (Microsoft Entra ID).

## Project Structure

- **Config/**: Configuration files and settings
- **Scripts/**: PowerShell automation scripts
- **Modules/**: Custom PowerShell modules
- **Data/**: Input data files (CSV, Excel)
- **Logs/**: Application and script logs
- **Tests/**: Pester test files
- **Documentation/**: Project documentation
- **Templates/**: User and group templates
- **Backups/**: Backup files

## Environment

- **Development Environment**: Windows Server 2022 on Azure
- **Active Directory Domain**: contoso.local
- **PowerShell Version**: 7.x
- **IDE**: Visual Studio Code with PowerShell extension

## Getting Started

1. Run setup scripts in order:
   - `Scripts\01-SystemConfiguration.ps1`
   - `Scripts\02-InstallTools.ps1`
   - `Scripts\03-InstallModules.ps1`
   - `Scripts\04-InstallActiveDirectory.ps1`
   - `Scripts\05-ConfigureActiveDirectory.ps1`
   - `Scripts\06-CreateProjectStructure.ps1`
   - `Scripts\07-EnvironmentTest.ps1`

2. Configure Azure AD connection in `Config\settings.json`

3. Run environment test: `.\Scripts\07-EnvironmentTest.ps1`

## Test Credentials

### Active Directory Users
- **Username**: jdeveloper | **Password**: DevPass123!
- **Username**: jtester | **Password**: DevPass123!  
- **Username**: badmin | **Password**: DevPass123!

### Domain Admin
- **Username**: CONTOSO\azureadmin | **Password**: DevServer2025!#

## Auto-Shutdown

VM is configured to auto-shutdown at 8:00 PM Central Time to save costs.
'@

try {
    $ReadMe | Out-File -FilePath "README.md" -Encoding UTF8
    Write-Host "✓ README file created: README.md" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to create README file: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n✓ Project structure configuration complete!" -ForegroundColor Green
Write-Host "Next: Run 07-EnvironmentTest.ps1" -ForegroundColor Cyan