# 05-ConfigureActiveDirectory.ps1

#Requires -RunAsAdministrator

Write-Host "=== ACTIVE DIRECTORY CONFIGURATION ===" -ForegroundColor Cyan
Write-Host "Configuring Active Directory structure..." -ForegroundColor Yellow

try {
    # Import Active Directory module
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Success: Active Directory module loaded" -ForegroundColor Green
    
    # Verify domain
    $Domain = Get-ADDomain
    Write-Host "Success: Connected to domain: $($Domain.DNSRoot)" -ForegroundColor Green
}
catch {
    Write-Host "Error: Failed to connect to Active Directory: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure the server restarted properly after domain promotion." -ForegroundColor Yellow
    exit 1
}

# Create Organizational Units
Write-Host "`nCreating Organizational Units..." -ForegroundColor Yellow
$OUs = @(
    @{Name="DevelopmentUsers"; Description="Development team user accounts"},
    @{Name="DevelopmentGroups"; Description="Development team security groups"},
    @{Name="TestEnvironment"; Description="Test user accounts"},
    @{Name="ServiceAccounts"; Description="Service account users"},
    @{Name="Workstations"; Description="Development workstation computers"}
)

foreach ($OU in $OUs) {
    try {
        New-ADOrganizationalUnit -Name $OU.Name -Path "DC=contoso,DC=local" -Description $OU.Description -ErrorAction SilentlyContinue
        Write-Host "Success: Created OU: $($OU.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: OU $($OU.Name) may already exist" -ForegroundColor Yellow
    }
}

# Create test users for development
Write-Host "`nCreating test users..." -ForegroundColor Yellow
$TestUsers = @(
    @{Name="John Developer"; SamAccount="jdeveloper"; Email="jdeveloper@contoso.local"; Dept="IT"; Title="Senior Developer"},
    @{Name="Jane Tester"; SamAccount="jtester"; Email="jtester@contoso.local"; Dept="QA"; Title="QA Analyst"},
    @{Name="Bob Admin"; SamAccount="badmin"; Email="badmin@contoso.local"; Dept="IT"; Title="System Administrator"},
    @{Name="Alice Manager"; SamAccount="amanager"; Email="amanager@contoso.local"; Dept="Management"; Title="Project Manager"},
    @{Name="Dave Support"; SamAccount="dsupport"; Email="dsupport@contoso.local"; Dept="Support"; Title="Help Desk Technician"}
)

foreach ($User in $TestUsers) {
    try {
        New-ADUser -Name $User.Name `
                   -GivenName $User.Name.Split(' ')[0] `
                   -Surname $User.Name.Split(' ')[1] `
                   -SamAccountName $User.SamAccount `
                   -UserPrincipalName $User.Email `
                   -Path "OU=DevelopmentUsers,DC=contoso,DC=local" `
                   -Department $User.Dept `
                   -Title $User.Title `
                   -Enabled $true `
                   -AccountPassword (ConvertTo-SecureString "DevPass123!" -AsPlainText -Force) `
                   -ChangePasswordAtLogon $false `
                   -Description "Test user created by automation script"
        
        Write-Host "Success: Created user: $($User.Name) ($($User.SamAccount))" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to create user: $($User.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create test groups
Write-Host "`nCreating security groups..." -ForegroundColor Yellow
$TestGroups = @(
    @{Name="DevelopmentTeam"; Description="Development team members"},
    @{Name="QATeam"; Description="Quality assurance team"},
    @{Name="ITAdmins"; Description="IT administrators"},
    @{Name="ProjectManagers"; Description="Project management team"}
)

foreach ($Group in $TestGroups) {
    try {
        New-ADGroup -Name $Group.Name `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Path "OU=DevelopmentGroups,DC=contoso,DC=local" `
                    -Description $Group.Description
        Write-Host "Success: Created group: $($Group.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to create group: $($Group.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Add users to appropriate groups
Write-Host "`nAdding users to groups..." -ForegroundColor Yellow
$GroupMemberships = @(
    @{User="jdeveloper"; Group="DevelopmentTeam"},
    @{User="jtester"; Group="QATeam"},
    @{User="badmin"; Group="ITAdmins"},
    @{User="amanager"; Group="ProjectManagers"}
)

foreach ($Membership in $GroupMemberships) {
    try {
        Add-ADGroupMember -Identity $Membership.Group -Members $Membership.User
        Write-Host "Success: Added $($Membership.User) to $($Membership.Group)" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to add $($Membership.User) to $($Membership.Group)" -ForegroundColor Red
    }
}

Write-Host "`nSuccess: Active Directory configuration complete!" -ForegroundColor Green
Write-Host "Next: Run 06-CreateProjectStructure.ps1" -ForegroundColor Cyan

# Display summary
Write-Host "`n=== ACTIVE DIRECTORY SUMMARY ===" -ForegroundColor Cyan
$UserCount = (Get-ADUser -Filter * -SearchBase "OU=DevelopmentUsers,DC=contoso,DC=local").Count
$GroupCount = (Get-ADGroup -Filter * -SearchBase "OU=DevelopmentGroups,DC=contoso,DC=local").Count
Write-Host "Domain: contoso.local" -ForegroundColor White
Write-Host "Users created: $UserCount" -ForegroundColor White
Write-Host "Groups created: $GroupCount" -ForegroundColor White
Write-Host "Default password: DevPass123!" -ForegroundColor White