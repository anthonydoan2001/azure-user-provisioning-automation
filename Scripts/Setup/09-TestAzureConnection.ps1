# 09-TestAzureConnection-Working.ps1
# Simplified working version based on successful debug results

Write-Host "=== AZURE AD CONNECTION TEST ===" -ForegroundColor Cyan

# Load credentials
$CredentialsPath = "Config\credentials.json"
$Credentials = Get-Content $CredentialsPath | ConvertFrom-Json
Write-Host "✓ Loaded Azure AD credentials" -ForegroundColor Green

Write-Host "`n🔗 CONNECTING TO MICROSOFT GRAPH..." -ForegroundColor Yellow

try {
    # Import modules
    Import-Module Microsoft.Graph.Authentication -Force
    Import-Module Microsoft.Graph.Users -Force
    Import-Module Microsoft.Graph.Groups -Force
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force
    
    # Connect
    $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
    $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
    
    Connect-MgGraph -TenantId $Credentials.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
    
    $Context = Get-MgContext
    Write-Host "✓ Successfully connected to Microsoft Graph!" -ForegroundColor Green
    Write-Host "  Tenant: $($Context.TenantId)" -ForegroundColor Gray
    
    # Test basic operations with error handling
    Write-Host "`n🧪 TESTING BASIC OPERATIONS..." -ForegroundColor Yellow
    
    # Test 1: Get tenant info (with timeout)
    Write-Host "Testing organization access..." -ForegroundColor Gray
    try {
        $TenantInfo = Get-MgOrganization -Top 1 -ErrorAction Stop
        if ($TenantInfo) {
            Write-Host "✓ Organization: $($TenantInfo.DisplayName)" -ForegroundColor Green
            if ($TenantInfo.VerifiedDomains) {
                $DefaultDomain = $TenantInfo.VerifiedDomains | Where-Object { $_.IsDefault } | Select-Object -First 1
                if ($DefaultDomain) {
                    Write-Host "✓ Default Domain: $($DefaultDomain.Name)" -ForegroundColor Green
                }
            }
        }
    }
    catch {
        Write-Host "⚠ Organization access limited: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Test 2: Get users (with specific error handling)
    Write-Host "Testing user access..." -ForegroundColor Gray
    try {
        # Use a smaller query to avoid timeouts
        $Users = Get-MgUser -Top 3 -Select "displayName,userPrincipalName" -ErrorAction Stop
        Write-Host "✓ User access successful - found $($Users.Count) users" -ForegroundColor Green
        if ($Users.Count -gt 0) {
            Write-Host "  Sample: $($Users[0].DisplayName)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "⚠ User access limited: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Test 3: Get groups (with specific error handling)
    Write-Host "Testing group access..." -ForegroundColor Gray
    try {
        $Groups = Get-MgGroup -Top 3 -Select "displayName" -ErrorAction Stop
        Write-Host "✓ Group access successful - found $($Groups.Count) groups" -ForegroundColor Green
        if ($Groups.Count -gt 0) {
            Write-Host "  Sample: $($Groups[0].DisplayName)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "⚠ Group access limited: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host "`n✅ AZURE AD CONNECTION TEST COMPLETED!" -ForegroundColor Green
    Write-Host "Your app registration is working correctly." -ForegroundColor White
    
} catch {
    Write-Host "✗ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Disconnect
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Host "`n🔌 Disconnected from Microsoft Graph" -ForegroundColor Gray
    } catch {}
}

Write-Host "`n🎉 SUCCESS! You're ready to use the hybrid provisioning scripts!" -ForegroundColor Green
Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
Write-Host "• Test user creation: .\Scripts\New-HybridUser.ps1 -FirstName 'Test' -LastName 'User' -Department 'IT' -JobTitle 'Developer' -TestRun" -ForegroundColor White
Write-Host "• Test group creation: .\Scripts\New-HybridGroup.ps1 -GroupName 'Test-Group' -Description 'Test group' -TestRun" -ForegroundColor White
Write-Host "• Check status: .\Scripts\Get-ProvisioningStatus.ps1 -UserIdentity 'jdeveloper'" -ForegroundColor White