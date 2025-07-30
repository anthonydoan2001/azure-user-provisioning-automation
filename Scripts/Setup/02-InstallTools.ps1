# 02-InstallTools.ps1

Write-Host "=== DEVELOPMENT TOOLS INSTALLATION ===" -ForegroundColor Cyan

# Development Tools Configuration
$Tools = @(
    @{Name="PowerShell 7"; Package="powershell-core"},
    @{Name="Visual Studio Code"; Package="vscode"},
    @{Name="Git"; Package="git"}
)

foreach ($Tool in $Tools) {
    Write-Host "Installing $($Tool.Name)..." -ForegroundColor Yellow
    try {
        choco install $($Tool.Package) -y
        Write-Host "Success: $($Tool.Name) installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to install $($Tool.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

# Environment Variable Refresh
Write-Host "Refreshing environment variables..." -ForegroundColor Yellow
refreshenv

# Installation Verification
try {
    $PS7Version = pwsh --version
    Write-Host "Success: PowerShell 7 version: $PS7Version" -ForegroundColor Green
}
catch {
    Write-Host "Error: PowerShell 7 not found in PATH" -ForegroundColor Red
}

Write-Host "Success: Development tools installation complete!" -ForegroundColor Green
Write-Host "Next: Open VS Code and install PowerShell extension, then run 03-InstallModules.ps1" -ForegroundColor Cyan