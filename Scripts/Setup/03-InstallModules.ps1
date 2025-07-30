# 03-InstallModules.ps1 - UPDATED VERSION
# Install required PowerShell modules for Azure and AD automation

#Requires -RunAsAdministrator

Write-Host "=== POWERSHELL MODULES INSTALLATION ===" -ForegroundColor Cyan
Write-Host "This script must be run in PowerShell 7 as Administrator" -ForegroundColor Yellow

# Verify we're running PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Error: This script requires PowerShell 7. Please run in pwsh.exe" -ForegroundColor Red
    exit 1
}

# Array of modules to install from PowerShell Gallery
$PSGalleryModules = @(
    @{Name="Az"; Description="Azure PowerShell modules"},
    @{Name="Microsoft.Graph"; Description="Microsoft Graph API"},
    @{Name="ExchangeOnlineManagement"; Description="Exchange Online"},
    @{Name="ImportExcel"; Description="Excel file handling"},
    @{Name="Pester"; Description="Testing framework"}
)

Write-Host "Installing PowerShell Gallery modules..." -ForegroundColor Cyan
Write-Host "This will take 5-10 minutes..." -ForegroundColor Yellow

foreach ($Module in $PSGalleryModules) {
    Write-Host "`nInstalling $($Module.Name) ($($Module.Description))..." -ForegroundColor Yellow
    try {
        Install-Module -Name $Module.Name -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
        
        # Verify installation
        $InstalledModule = Get-Module -Name $Module.Name -ListAvailable | Select-Object -First 1
        Write-Host "Success: $($Module.Name) v$($InstalledModule.Version) installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to install $($Module.Name)" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Install ActiveDirectory module via Windows Feature
Write-Host "`nInstalling ActiveDirectory module via Windows Feature..." -ForegroundColor Yellow
try {
    # Check if already installed
    $ADFeature = Get-WindowsFeature -Name AD-Domain-Services
    
    if ($ADFeature.InstallState -eq "Installed") {
        Write-Host "Success: AD-Domain-Services already installed" -ForegroundColor Green
    } else {
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        Write-Host "Success: AD-Domain-Services installed successfully" -ForegroundColor Green
    }
    
    # Verify ActiveDirectory module is available
    $ADModule = Get-Module -Name ActiveDirectory -ListAvailable
    if ($ADModule) {
        Write-Host "Success: ActiveDirectory PowerShell module is available" -ForegroundColor Green
    } else {
        Write-Host "Warning: ActiveDirectory module will be available after domain controller promotion" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: Failed to install ActiveDirectory feature" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nSuccess: Module installation complete!" -ForegroundColor Green
Write-Host "Next: Run 04-InstallActiveDirectory.ps1" -ForegroundColor Cyan

# Create module verification script
$VerificationScript = @'
# Verify installed modules
Write-Host "=== MODULE VERIFICATION ===" -ForegroundColor Cyan

# PowerShell Gallery modules
$PSGalleryModules = @('Az', 'Microsoft.Graph', 'ImportExcel', 'Pester', 'ExchangeOnlineManagement')

foreach ($Module in $PSGalleryModules) {
    try {
        Import-Module $Module -ErrorAction Stop
        $ModuleInfo = Get-Module $Module
        Write-Host "Success: $Module v$($ModuleInfo.Version) - Available" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $Module - Not available" -ForegroundColor Red
    }
}

# ActiveDirectory module (Windows Feature)
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $ADModule = Get-Module ActiveDirectory
    Write-Host "Success: ActiveDirectory v$($ADModule.Version) - Available" -ForegroundColor Green
}
catch {
    Write-Host "Warning: ActiveDirectory - Will be available after domain controller setup" -ForegroundColor Yellow
}
'@

$VerificationScript | Out-File -FilePath "Scripts\Verify-Modules.ps1" -Encoding UTF8
Write-Host "Created verification script: Scripts\Verify-Modules.ps1" -ForegroundColor Green