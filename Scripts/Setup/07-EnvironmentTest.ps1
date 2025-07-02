# 07-EnvironmentTest.ps1
# Comprehensive environment test for development setup

Write-Host "=== DEVELOPMENT ENVIRONMENT TEST ===" -ForegroundColor Cyan

# Test PowerShell version
Write-Host "`n1. PowerShell Version:" -ForegroundColor Yellow
$PSVersion = $PSVersionTable.PSVersion
Write-Host "   Version: $PSVersion" -ForegroundColor White
if ($PSVersion.Major -ge 7) {
    Write-Host "   ✓ PowerShell 7+ detected" -ForegroundColor Green
} else {
    Write-Host "   ⚠ PowerShell 7+ recommended" -ForegroundColor Yellow
}

# Test installed modules
Write-Host "`n2. Testing PowerShell Modules:" -ForegroundColor Yellow
$RequiredModules = @('Az', 'Microsoft.Graph', 'ActiveDirectory', 'ImportExcel', 'Pester', 'ExchangeOnlineManagement')

foreach ($Module in $RequiredModules) {
    try {
        $ModuleInfo = Get-Module -Name $Module -ListAvailable | Select-Object -First 1
        if ($ModuleInfo) {
            Write-Host "   ✓ $Module v$($ModuleInfo.Version) - Available" -ForegroundColor Green
        } else {
            Write-Host "   ✗ $Module - Not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   ✗ $Module - Error checking" -ForegroundColor Red
    }
}

# Test Active Directory
Write-Host "`n3. Testing Active Directory:" -ForegroundColor Yellow
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $Domain = Get-ADDomain -ErrorAction Stop
    Write-Host "   ✓ Domain: $($Domain.DNSRoot)" -ForegroundColor Green
    
    $Users = Get-ADUser -Filter * -SearchBase "OU=DevelopmentUsers,DC=contoso,DC=local" -ErrorAction Stop
    Write-Host "   ✓ Found $($Users.Count) development users" -ForegroundColor Green
    
    $Groups = Get-ADGroup -Filter * -SearchBase "OU=DevelopmentGroups,DC=contoso,DC=local" -ErrorAction Stop
    Write-Host "   ✓ Found $($Groups.Count) development groups" -ForegroundColor Green
    
    # Test specific users
    $TestUsers = @('jdeveloper', 'jtester', 'badmin')
    foreach ($User in $TestUsers) {
        $UserObj = Get-ADUser -Identity $User -ErrorAction SilentlyContinue
        if ($UserObj) {
            Write-Host "   ✓ Test user found: $User" -ForegroundColor Green
        } else {
            Write-Host "   ✗ Test user missing: $User" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "   ✗ Active Directory - Connection failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test file system access
Write-Host "`n4. Testing Project Structure:" -ForegroundColor Yellow
$TestPaths = @(
    "C:\UserProvisioningProject",
    "C:\UserProvisioningProject\Scripts",
    "C:\UserProvisioningProject\Config",
    "C:\UserProvisioningProject\Logs",
    "C:\UserProvisioningProject\Config\settings.json"
)

foreach ($Path in $TestPaths) {
    if (Test-Path $Path) {
        Write-Host "   ✓ $Path - Accessible" -ForegroundColor Green
    } else {
        Write-Host "   ✗ $Path - Not found" -ForegroundColor Red
    }
}

# Test VS Code
Write-Host "`n5. Testing Visual Studio Code:" -ForegroundColor Yellow
try {
    $VSCodePath = Get-Command code -ErrorAction Stop
    Write-Host "   ✓ VS Code installed at: $($VSCodePath.Source)" -ForegroundColor Green
}
catch {
    Write-Host "   ✗ VS Code not found in PATH" -ForegroundColor Red
}

# Test Git
Write-Host "`n6. Testing Git:" -ForegroundColor Yellow
try {
    $GitVersion = git --version
    Write-Host "   ✓ Git installed: $GitVersion" -ForegroundColor Green
}
catch {
    Write-Host "   ✗ Git not found in PATH" -ForegroundColor Red
}

# Test network connectivity
Write-Host "`n7. Testing Network Connectivity:" -ForegroundColor Yellow
$TestSites = @('portal.azure.com', 'graph.microsoft.com', 'login.microsoftonline.com')

foreach ($Site in $TestSites) {
    try {
        $Result = Test-NetConnection -ComputerName $Site -Port 443 -InformationLevel Quiet
        if ($Result) {
            Write-Host "   ✓ $Site - Reachable" -ForegroundColor Green
        } else {
            Write-Host "   ✗ $Site - Not reachable" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   ✗ $Site - Connection test failed" -ForegroundColor Red
    }
}

Write-Host "`n=== ENVIRONMENT TEST COMPLETE ===" -ForegroundColor Cyan

# Generate summary
$TotalTests = 0
$PassedTests = 0

# You would implement proper test counting here
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Development environment setup verification complete!" -ForegroundColor Green
Write-Host "Review any red ✗ items above and resolve before proceeding." -ForegroundColor Yellow
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Configure Azure AD connection in Config\settings.json" -ForegroundColor White
Write-Host "2. Initialize Git repository" -ForegroundColor White
Write-Host "3. Create first automation scripts" -ForegroundColor White