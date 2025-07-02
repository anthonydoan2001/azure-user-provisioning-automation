# Test-LokkaSetup.ps1
Write-Host "=== LOKKA MCP SERVER SETUP VERIFICATION ===" -ForegroundColor Cyan

# Test 1: Check if Lokka is installed
Write-Host "`n1. Checking Lokka installation..." -ForegroundColor Yellow
try {
    $LokkaVersion = npx @merill/lokka --version 2>$null
    if ($LokkaVersion) {
        Write-Host "   ✅ Lokka installed: $LokkaVersion" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Lokka not found" -ForegroundColor Red
        Write-Host "   Run: npm install -g @merill/lokka" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "   ❌ Error checking Lokka: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: Load credentials
Write-Host "`n2. Loading credentials..." -ForegroundColor Yellow
try {
    $Credentials = Get-Content "C:\UserProvisioningProject\Config\credentials.json" | ConvertFrom-Json
    Write-Host "   ✅ Credentials loaded" -ForegroundColor Green
    Write-Host "   Tenant ID: $($Credentials.TenantId)" -ForegroundColor Gray
    Write-Host "   Client ID: $($Credentials.ClientId)" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ Could not load credentials" -ForegroundColor Red
    exit 1
}

# Test 3: Verify Graph API access still works
Write-Host "`n3. Verifying Graph API access..." -ForegroundColor Yellow
try {
    Import-Module Microsoft.Graph.Authentication
    $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
    $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
    Connect-MgGraph -TenantId $Credentials.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
    
    $Context = Get-MgContext
    if ($Context) {
        Write-Host "   ✅ Graph API access confirmed" -ForegroundColor Green
        Write-Host "   Scopes: $($Context.Scopes -join ', ')" -ForegroundColor Gray
    }
    Disconnect-MgGraph
} catch {
    Write-Host "   ❌ Graph API access failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Show Cursor configuration
Write-Host "`n4. Cursor configuration needed:" -ForegroundColor Yellow
Write-Host @"
{
  "mcpServers": {
    "Lokka-Microsoft": {
      "command": "npx",
      "args": ["-y", "@merill/lokka"],
      "env": {
        "TENANT_ID": "$($Credentials.TenantId)",
        "CLIENT_ID": "$($Credentials.ClientId)",
        "CLIENT_SECRET": "$($Credentials.ClientSecret)"
      }
    }
  }
}
"@ -ForegroundColor Gray

Write-Host "`n=== SETUP VERIFICATION COMPLETE ===" -ForegroundColor Cyan
Write-Host "✅ Lokka MCP Server ready for testing" -ForegroundColor Green
Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Update Cursor settings.json with the configuration above" -ForegroundColor White
Write-Host "2. Restart Cursor completely" -ForegroundColor White
Write-Host "3. Test with: 'Using Lokka tools, list users in our tenant'" -ForegroundColor White