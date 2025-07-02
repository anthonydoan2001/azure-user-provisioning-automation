# Import-UsersFromCSV.ps1
# Bulk create users from CSV file

param(
    [Parameter(Mandatory=$true)]
    [string]$CSVPath,
    
    [switch]$WhatIf,
    [switch]$ContinueOnError
)

#Requires -Modules ActiveDirectory, Microsoft.Graph

Write-Host "=== BULK USER IMPORT FROM CSV ===" -ForegroundColor Cyan

# Validate CSV file exists
if (-not (Test-Path $CSVPath)) {
    Write-Host "❌ CSV file not found: $CSVPath" -ForegroundColor Red
    exit 1
}

# Load configuration
$Settings = Get-Content "Config\settings.json" | ConvertFrom-Json
$Credentials = Get-Content "Config\credentials.json" | ConvertFrom-Json

# Read and validate CSV
try {
    $Users = Import-Csv -Path $CSVPath
    Write-Host "✅ Loaded $($Users.Count) users from CSV" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to read CSV: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Validate required columns
$RequiredColumns = @('FirstName', 'LastName', 'Department')
$CSVColumns = $Users[0].PSObject.Properties.Name
$MissingColumns = $RequiredColumns | Where-Object { $_ -notin $CSVColumns }

if ($MissingColumns) {
    Write-Host "❌ Missing required columns: $($MissingColumns -join ', ')" -ForegroundColor Red
    Write-Host "Required columns: $($RequiredColumns -join ', ')" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ CSV validation passed" -ForegroundColor Green

# Initialize counters
$SuccessCount = 0
$FailureCount = 0
$Results = @()

# Connect to Microsoft Graph once
if (-not $WhatIf) {
    try {
        $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
        $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
        Connect-MgGraph -TenantId $Credentials.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
        Write-Host "✅ Connected to Microsoft Graph" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Import Active Directory module
if (-not $WhatIf) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "✅ Active Directory module loaded" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to load Active Directory module: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n🔄 PROCESSING USERS..." -ForegroundColor Yellow

# Process each user
foreach ($User in $Users) {
    $CurrentUser = @{
        FirstName = $User.FirstName.Trim()
        LastName = $User.LastName.Trim()
        Department = $User.Department.Trim()
        JobTitle = if ($User.JobTitle) { $User.JobTitle.Trim() } else { "Employee" }
        Manager = if ($User.Manager) { $User.Manager.Trim() } else { "" }
        Username = ($User.FirstName.Substring(0,1) + $User.LastName).ToLower().Trim()
        Status = "Processing"
        Errors = @()
    }
    
    Write-Host "`n👤 Processing: $($CurrentUser.FirstName) $($CurrentUser.LastName)" -ForegroundColor White
    Write-Host "   Username: $($CurrentUser.Username)" -ForegroundColor Gray
    
    if ($WhatIf) {
        Write-Host "   🔍 WHAT-IF: Would create user $($CurrentUser.Username)" -ForegroundColor Magenta
        $CurrentUser.Status = "WhatIf"
        $Results += $CurrentUser
        continue
    }
    
    # Generate credentials
    $OnPremEmail = "$($CurrentUser.Username)@contoso.local"
    $CloudEmail = "$($CurrentUser.Username)@anthonydoan0405gmail.onmicrosoft.com"
    $TempPassword = "TempPass$(Get-Random -Minimum 1000 -Maximum 9999)!"
    
    try {
        # Step 1: Create Active Directory User
        Write-Host "   📁 Creating AD user..." -ForegroundColor Gray
        
        # Check if user already exists
        $ExistingADUser = Get-ADUser -Filter "SamAccountName -eq '$($CurrentUser.Username)'" -ErrorAction SilentlyContinue
        if ($ExistingADUser) {
            throw "User already exists in Active Directory"
        }
        
        New-ADUser -Name "$($CurrentUser.FirstName) $($CurrentUser.LastName)" `
                   -GivenName $CurrentUser.FirstName `
                   -Surname $CurrentUser.LastName `
                   -SamAccountName $CurrentUser.Username `
                   -UserPrincipalName $OnPremEmail `
                   -Path $Settings.ActiveDirectory.DefaultOU `
                   -Department $CurrentUser.Department `
                   -Title $CurrentUser.JobTitle `
                   -EmailAddress $OnPremEmail `
                   -Enabled $true `
                   -AccountPassword (ConvertTo-SecureString $TempPassword -AsPlainText -Force) `
                   -ChangePasswordAtLogon $true
        
        Write-Host "   ✅ AD user created" -ForegroundColor Green
        
        # Step 2: Create Azure AD User
        Write-Host "   ☁️ Creating Azure AD user..." -ForegroundColor Gray
        
        $AzureUser = @{
            DisplayName = "$($CurrentUser.FirstName) $($CurrentUser.LastName)"
            GivenName = $CurrentUser.FirstName
            Surname = $CurrentUser.LastName
            UserPrincipalName = $CloudEmail
            MailNickname = $CurrentUser.Username
            Department = $CurrentUser.Department
            JobTitle = $CurrentUser.JobTitle
            AccountEnabled = $true
            PasswordProfile = @{
                ForceChangePasswordNextSignIn = $true
                Password = $TempPassword
            }
        }
        
        $NewAzureUser = New-MgUser -BodyParameter $AzureUser
        Write-Host "   ✅ Azure AD user created" -ForegroundColor Green
        
        # Step 3: Add to groups
        Write-Host "   👥 Adding to groups..." -ForegroundColor Gray
        $DeptGroup = "$($CurrentUser.Department)Team"
        try {
            Add-ADGroupMember -Identity $DeptGroup -Members $CurrentUser.Username -ErrorAction Stop
            Write-Host "   ✅ Added to AD group: $DeptGroup" -ForegroundColor Green
        }
        catch {
            Write-Host "   ⚠️ AD group $DeptGroup not found" -ForegroundColor Yellow
        }
        
        $CurrentUser.Status = "Success"
        $CurrentUser.OnPremEmail = $OnPremEmail
        $CurrentUser.CloudEmail = $CloudEmail
        $CurrentUser.TempPassword = $TempPassword
        $CurrentUser.AzureObjectId = $NewAzureUser.Id
        
        $SuccessCount++
        Write-Host "   ✅ User created successfully" -ForegroundColor Green
        
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $CurrentUser.Status = "Failed"
        $CurrentUser.Errors += $ErrorMessage
        $FailureCount++
        
        Write-Host "   ❌ Failed: $ErrorMessage" -ForegroundColor Red
        
        if (-not $ContinueOnError) {
            Write-Host "`n⚠️ Stopping on first error. Use -ContinueOnError to process remaining users." -ForegroundColor Yellow
            break
        }
    }
    
    $Results += $CurrentUser
}

# Disconnect from Graph
if (-not $WhatIf) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}

# Generate report
Write-Host "`n📊 BULK IMPORT SUMMARY:" -ForegroundColor Cyan
Write-Host "Total Users: $($Users.Count)" -ForegroundColor White
Write-Host "Successful: $SuccessCount" -ForegroundColor Green
Write-Host "Failed: $FailureCount" -ForegroundColor Red

if ($WhatIf) {
    Write-Host "Mode: WHAT-IF (no changes made)" -ForegroundColor Magenta
}

# Save detailed report
$ReportPath = "Data\BulkImport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$Results | ConvertTo-Json -Depth 3 | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`n💾 Detailed report saved: $ReportPath" -ForegroundColor Gray

# Save CSV report for easy viewing
$CSVReportPath = "Data\BulkImport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$Results | Select-Object FirstName, LastName, Username, Department, Status, OnPremEmail, CloudEmail, TempPassword | 
    Export-Csv -Path $CSVReportPath -NoTypeInformation
Write-Host "💾 CSV report saved: $CSVReportPath" -ForegroundColor Gray

if ($FailureCount -gt 0 -and -not $WhatIf) {
    Write-Host "`n⚠️ Some users failed to create. Check the detailed report for errors." -ForegroundColor Yellow
}

Write-Host "`n✅ BULK IMPORT COMPLETE!" -ForegroundColor Green