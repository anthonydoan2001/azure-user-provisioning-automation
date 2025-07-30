# 04-InstallActiveDirectory.ps1

#Requires -RunAsAdministrator

Write-Host "=== ACTIVE DIRECTORY INSTALLATION ===" -ForegroundColor Cyan

# Check if AD DS is already installed
$ADFeature = Get-WindowsFeature -Name AD-Domain-Services

if ($ADFeature.InstallState -eq "Installed") {
    Write-Host "Success: AD-Domain-Services feature already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Active Directory Domain Services..." -ForegroundColor Yellow
    try {
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        Write-Host "Success: AD DS feature installed!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to install AD DS: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Check if server is already a domain controller
try {
    $Domain = Get-ADDomain -ErrorAction SilentlyContinue
    if ($Domain) {
        Write-Host "Success: Server is already a domain controller for: $($Domain.DNSRoot)" -ForegroundColor Green
        Write-Host "Skipping domain controller promotion." -ForegroundColor Yellow
        Write-Host "Next: Run 05-ConfigureActiveDirectory.ps1" -ForegroundColor Cyan
        exit 0
    }
}
catch {
    # Domain not found, proceed with promotion
    Write-Host "Server is not yet a domain controller, proceeding with promotion..." -ForegroundColor Yellow
}

Write-Host "`nPromoving server to Domain Controller..." -ForegroundColor Yellow
Write-Host "WARNING: SERVER WILL RESTART AUTOMATICALLY AFTER THIS STEP" -ForegroundColor Red
Write-Host "WARNING: Reconnect via RDP after restart and run 05-ConfigureActiveDirectory.ps1" -ForegroundColor Red

# Prompt for confirmation
$Confirm = Read-Host "`nContinue with domain controller promotion? (y/N)"
if ($Confirm -ne 'y' -and $Confirm -ne 'Y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

try {
    # Create the domain controller
    Install-ADDSForest `
        -DomainName "contoso.local" `
        -DomainNetbiosName "CONTOSO" `
        -SafeModeAdministratorPassword (ConvertTo-SecureString "SafeMode2025!" -AsPlainText -Force) `
        -InstallDns:$true `
        -Force
    
    # This point won't be reached as the server will restart
}
catch {
    Write-Host "Error: Failed to promote server to domain controller: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}