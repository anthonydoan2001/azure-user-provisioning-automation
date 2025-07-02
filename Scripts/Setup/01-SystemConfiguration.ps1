# 01-SystemConfiguration.ps1
# Initial system configuration for development environment

Write-Host "=== SYSTEM CONFIGURATION SCRIPT ===" -ForegroundColor Cyan
Write-Host "Configuring PowerShell execution policy..." -ForegroundColor Yellow

# Set execution policy to allow scripts
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Verify the change
$ExecutionPolicy = Get-ExecutionPolicy
Write-Host "✓ Execution Policy set to: $ExecutionPolicy" -ForegroundColor Green

# Install Chocolatey package manager
Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

try {
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    $ChocoVersion = choco --version
    Write-Host "✓ Chocolatey installed successfully: $ChocoVersion" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to install Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "✓ System configuration complete!" -ForegroundColor Green
Write-Host "Next: Run 02-InstallTools.ps1" -ForegroundColor Cyan