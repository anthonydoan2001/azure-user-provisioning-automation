# 01-SystemConfiguration.ps1

Write-Host "=== SYSTEM CONFIGURATION SCRIPT ===" -ForegroundColor Cyan
Write-Host "Configuring PowerShell execution policy..." -ForegroundColor Yellow

# Configure PowerShell execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Verify execution policy configuration
$ExecutionPolicy = Get-ExecutionPolicy
Write-Host "Success: Execution Policy set to: $ExecutionPolicy" -ForegroundColor Green

# Package Manager Installation
Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

try {
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    $ChocoVersion = choco --version
    Write-Host "Success: Chocolatey installed successfully: $ChocoVersion" -ForegroundColor Green
}
catch {
    Write-Host "Error: Failed to install Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Success: System configuration complete!" -ForegroundColor Green
Write-Host "Next: Run 02-InstallTools.ps1" -ForegroundColor Cyan