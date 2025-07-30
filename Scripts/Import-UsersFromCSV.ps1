# Import-UsersFromCSV.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$CSVPath,
    
    [switch]$ContinueOnError
)

#Requires -Modules ActiveDirectory, Microsoft.Graph

Write-Host "=== BULK USER IMPORT FROM CSV ===" -ForegroundColor Cyan

# CSV File Validation
if (-not (Test-Path $CSVPath)) {
    Write-Host "Error: CSV file not found: $CSVPath" -ForegroundColor Red
    exit 1
}

# Configuration Management
$Settings = Get-Content "Config\settings.json" | ConvertFrom-Json
$Credentials = Get-Content "Config\credentials.json" | ConvertFrom-Json

# CSV Data Processing
try {
    $Users = Import-Csv -Path $CSVPath
    Write-Host "Success: Loaded $($Users.Count) users from CSV" -ForegroundColor Green
}
catch {
    Write-Host "Error: Failed to read CSV: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Column Validation
$RequiredColumns = @('FirstName', 'LastName', 'Department')
$CSVColumns = $Users[0].PSObject.Properties.Name
$MissingColumns = $RequiredColumns | Where-Object { $_ -notin $CSVColumns }

if ($MissingColumns) {
    Write-Host "Error: Missing required columns: $($MissingColumns -join ', ')" -ForegroundColor Red
    Write-Host "Required columns: $($RequiredColumns -join ', ')" -ForegroundColor Yellow
    exit 1
}

Write-Host "Success: CSV validation passed" -ForegroundColor Green

# Processing Counters
$SuccessCount = 0
$FailureCount = 0
$Results = @()

# Microsoft Graph Authentication
    try {
        $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
        $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
        Connect-MgGraph -TenantId $Credentials.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
        Write-Host "Success: Connected to Microsoft Graph" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

# Active Directory Module
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "Success: Active Directory module loaded" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to load Active Directory module: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

Write-Host "`nPROCESSING USERS..." -ForegroundColor Yellow

# User Processing Loop
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
    
    Write-Host "`nProcessing: $($CurrentUser.FirstName) $($CurrentUser.LastName)" -ForegroundColor White
    Write-Host "   Username: $($CurrentUser.Username)" -ForegroundColor Gray
    
    # Generate user credentials
    $OnPremEmail = "$($CurrentUser.Username)@contoso.local"
    $CloudEmail = "$($CurrentUser.Username)@anthonydoan0405gmail.onmicrosoft.com"
    $TempPassword = "TempPass$(Get-Random -Minimum 1000 -Maximum 9999)!"
    
    try {
        # Create Active Directory User
        Write-Host "   Creating AD user..." -ForegroundColor Gray
        
        # Validate user doesn't exist
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
        
        Write-Host "   Success: AD user created" -ForegroundColor Green
        
        # Create Azure AD User
        Write-Host "   Creating Azure AD user..." -ForegroundColor Gray
        
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
        Write-Host "   Success: Azure AD user created" -ForegroundColor Green
        
        # Group Membership Assignment
        Write-Host "   Adding to groups..." -ForegroundColor Gray
        $DeptGroup = "$($CurrentUser.Department)Team"
        try {
            Add-ADGroupMember -Identity $DeptGroup -Members $CurrentUser.Username -ErrorAction Stop
            Write-Host "   Success: Added to AD group: $DeptGroup" -ForegroundColor Green
        }
        catch {
            Write-Host "   Warning: AD group $DeptGroup not found" -ForegroundColor Yellow
        }
        
        $CurrentUser.Status = "Success"
        $CurrentUser.OnPremEmail = $OnPremEmail
        $CurrentUser.CloudEmail = $CloudEmail
        $CurrentUser.TempPassword = $TempPassword
        $CurrentUser.AzureObjectId = $NewAzureUser.Id
        
        $SuccessCount++
        Write-Host "   Success: User created successfully" -ForegroundColor Green
        
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $CurrentUser.Status = "Failed"
        $CurrentUser.Errors += $ErrorMessage
        $FailureCount++
        
        Write-Host "   Error: Failed: $ErrorMessage" -ForegroundColor Red
        
        if (-not $ContinueOnError) {
            Write-Host "`nWarning: Stopping on first error. Use -ContinueOnError to process remaining users." -ForegroundColor Yellow
            break
        }
    }
    
    $Results += $CurrentUser
}

# Microsoft Graph Disconnection
Disconnect-MgGraph -ErrorAction SilentlyContinue

# Report Generation
Write-Host "`nBULK IMPORT SUMMARY:" -ForegroundColor Cyan
Write-Host "Total Users: $($Users.Count)" -ForegroundColor White
Write-Host "Successful: $SuccessCount" -ForegroundColor Green
Write-Host "Failed: $FailureCount" -ForegroundColor Red

# Detailed Report Export
$ReportPath = "Data\BulkImport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$Results | ConvertTo-Json -Depth 3 | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`nDetailed report saved: $ReportPath" -ForegroundColor Gray

# CSV Report Export
$CSVReportPath = "Data\BulkImport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$Results | Select-Object FirstName, LastName, Username, Department, Status, OnPremEmail, CloudEmail, TempPassword | 
    Export-Csv -Path $CSVReportPath -NoTypeInformation
Write-Host "CSV report saved: $CSVReportPath" -ForegroundColor Gray

if ($FailureCount -gt 0) {
    Write-Host "`nWarning: Some users failed to create. Check the detailed report for errors." -ForegroundColor Yellow
}

Write-Host "`nBULK IMPORT COMPLETE" -ForegroundColor Green