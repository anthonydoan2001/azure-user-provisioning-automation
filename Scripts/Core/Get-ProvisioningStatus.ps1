# Get-ProvisioningStatus.ps1
# Check the status of user and group provisioning across both environments

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserIdentity,
    
    [Parameter(Mandatory = $false)]
    [string]$GroupIdentity,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowDetailedReport
)

Write-Host "=== PROVISIONING STATUS CHECK ===" -ForegroundColor Cyan

# Load configuration (same pattern as debug script)
Write-Host "Loading configuration..." -ForegroundColor Yellow
try {
    $CredentialsPath = "C:\UserProvisioningProject\Config\credentials.json"
    if (Test-Path $CredentialsPath) {
        $Credentials = Get-Content $CredentialsPath | ConvertFrom-Json
        Write-Host "✓ Configuration loaded" -ForegroundColor Green
    } else {
        Write-Host "✗ Configuration file not found" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ Configuration error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Get-UserStatus {
    param([string]$Identity)
    
    Write-Host "`n🔍 Checking user: $Identity" -ForegroundColor Yellow
    
    $UserStatus = [PSCustomObject]@{
        Identity = $Identity
        DisplayName = $null
        ADExists = $false
        ADEnabled = $null
        ADGroups = @()
        AzureExists = $false
        AzureEnabled = $null
        AzureGroups = @()
        SyncStatus = "Unknown"
        Issues = @()
    }
    
    # Check Active Directory (same as debug)
    Write-Host "  Checking Active Directory..." -ForegroundColor Gray
    try {
        Import-Module ActiveDirectory -Force -ErrorAction Stop
        $ADUser = Get-ADUser -Identity $Identity -Properties Enabled, MemberOf -ErrorAction SilentlyContinue
        
        if ($ADUser) {
            $UserStatus.ADExists = $true
            $UserStatus.ADEnabled = $ADUser.Enabled
            $UserStatus.DisplayName = $ADUser.Name
            
            # Get group memberships (simplified)
            if ($ADUser.MemberOf) {
                $UserStatus.ADGroups = $ADUser.MemberOf | ForEach-Object {
                    try {
                        (Get-ADGroup -Identity $_ -ErrorAction SilentlyContinue).Name
                    } catch { $null }
                } | Where-Object { $_ -ne $null }
            }
            Write-Host "    ✓ Found in AD: $($ADUser.Name)" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Not found in AD" -ForegroundColor Red
        }
    }
    catch {
        $UserStatus.Issues += "AD lookup failed"
        Write-Host "    ✗ AD lookup error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Check Azure AD (same pattern as debug)
    Write-Host "  Checking Azure AD..." -ForegroundColor Gray
    try {
        # Import modules
        Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop
        Import-Module Microsoft.Graph.Users -Force -ErrorAction Stop
        
        # Create credentials
        $SecureSecret = ConvertTo-SecureString $Credentials.ClientSecret -AsPlainText -Force
        $ClientSecretCredential = New-Object System.Management.Automation.PSCredential($Credentials.ClientId, $SecureSecret)
        
        # Connect using job pattern that worked
        $ConnectionJob = Start-Job -ScriptBlock {
            param($TenantId, $ClientId, $ClientSecret, $UserIdentity, $AzureDomain)
            
            Import-Module Microsoft.Graph.Authentication -Force
            Import-Module Microsoft.Graph.Users -Force
            
            $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $Cred = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
            
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Cred -NoWelcome
            
            # Look up user
            $UPN = "$UserIdentity@$AzureDomain"
            $AzureUser = Get-MgUser -Filter "userPrincipalName eq '$UPN'" -Property "displayName,accountEnabled" -ErrorAction SilentlyContinue
            
            $Result = @{
                Found = $false
                DisplayName = $null
                Enabled = $null
            }
            
            if ($AzureUser) {
                $Result.Found = $true
                $Result.DisplayName = $AzureUser.DisplayName
                $Result.Enabled = $AzureUser.AccountEnabled
            }
            
            Disconnect-MgGraph | Out-Null
            return $Result
            
        } -ArgumentList $Credentials.TenantId, $Credentials.ClientId, $Credentials.ClientSecret, $Identity, $Credentials.AzureDomain
        
        $JobCompleted = Wait-Job -Job $ConnectionJob -Timeout 30
        
        if ($JobCompleted) {
            $AzureResult = Receive-Job -Job $ConnectionJob
            if ($AzureResult.Found) {
                $UserStatus.AzureExists = $true
                $UserStatus.AzureEnabled = $AzureResult.Enabled
                if (-not $UserStatus.DisplayName) {
                    $UserStatus.DisplayName = $AzureResult.DisplayName
                }
                Write-Host "    ✓ Found in Azure AD: $($AzureResult.DisplayName)" -ForegroundColor Green
            } else {
                Write-Host "    ✗ Not found in Azure AD" -ForegroundColor Red
            }
        } else {
            Write-Host "    ✗ Azure AD lookup timed out" -ForegroundColor Red
            $UserStatus.Issues += "Azure AD lookup timeout"
            Stop-Job -Job $ConnectionJob -Force
        }
        
        Remove-Job -Job $ConnectionJob -Force
        
    }
    catch {
        $UserStatus.Issues += "Azure AD lookup failed"
        Write-Host "    ✗ Azure AD error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Determine sync status
    if ($UserStatus.ADExists -and $UserStatus.AzureExists) {
        $UserStatus.SyncStatus = "Synchronized"
        if ($UserStatus.ADEnabled -ne $UserStatus.AzureEnabled) {
            $UserStatus.Issues += "Enabled status mismatch"
        }
    } elseif ($UserStatus.ADExists -and -not $UserStatus.AzureExists) {
        $UserStatus.SyncStatus = "AD Only"
    } elseif (-not $UserStatus.ADExists -and $UserStatus.AzureExists) {
        $UserStatus.SyncStatus = "Azure Only"
    } else {
        $UserStatus.SyncStatus = "Not Found"
        $UserStatus.Issues += "User not found in either directory"
    }
    
    return $UserStatus
}
# Add this function to your Get-ProvisioningStatus.ps1 (after the Get-UserStatus function)

function Get-GroupStatus {
    param([string]$Identity)
    
    Write-Host "`n🔍 Checking group: $Identity" -ForegroundColor Yellow
    
    $GroupStatus = [PSCustomObject]@{
        Identity = $Identity
        DisplayName = $null
        ADExists = $false
        ADMemberCount = 0
        ADMembers = @()
        AzureExists = $false
        AzureMemberCount = 0
        AzureMembers = @()
        GroupType = $null
        SyncStatus = "Unknown"
        Issues = @()
    }
    
    # Check Active Directory
    Write-Host "  Checking Active Directory..." -ForegroundColor Gray
    try {
        Import-Module ActiveDirectory -Force -ErrorAction Stop
        $ADGroup = Get-ADGroup -Identity $Identity -Properties Members, GroupCategory, GroupScope -ErrorAction SilentlyContinue
        
        if ($ADGroup) {
            $GroupStatus.ADExists = $true
            $GroupStatus.ADMemberCount = $ADGroup.Members.Count
            $GroupStatus.DisplayName = $ADGroup.Name
            $GroupStatus.GroupType = "$($ADGroup.GroupCategory) ($($ADGroup.GroupScope))"
            
            # Get member names - IMPROVED VERSION
            if ($ADGroup.Members) {
                $GroupStatus.ADMembers = $ADGroup.Members | ForEach-Object {
                    try {
                        $Member = Get-ADObject -Identity $_ -Properties Name, ObjectClass -ErrorAction SilentlyContinue
                        if ($Member) { 
                            "$($Member.Name) ($($Member.ObjectClass))" 
                        } else { 
                            "Unknown Object" 
                        }
                    } catch { 
                        "Lookup Failed" 
                    }
                }
            }
            Write-Host "    ✓ Found in AD: $($ADGroup.Name) ($($ADGroup.Members.Count) members)" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Not found in AD" -ForegroundColor Red
        }
    }
    catch {
        $GroupStatus.Issues += "AD lookup failed"
        Write-Host "    ✗ AD lookup error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Check Azure AD - FIXED VERSION
    Write-Host "  Checking Azure AD..." -ForegroundColor Gray
    try {
        $AzureGroupJob = Start-Job -ScriptBlock {
            param($TenantId, $ClientId, $ClientSecret, $GroupName)
            
            Import-Module Microsoft.Graph.Authentication -Force
            Import-Module Microsoft.Graph.Groups -Force
            Import-Module Microsoft.Graph.Users -Force
            
            $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $Cred = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Cred -NoWelcome
            
            $Result = @{
                Found = $false
                DisplayName = $null
                MemberCount = 0
                Members = @()
                MemberDetails = @()
            }
            
            $AzureGroup = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue
            if ($AzureGroup) {
                $Result.Found = $true
                $Result.DisplayName = $AzureGroup.DisplayName
                
                # Get group members with better error handling
                try {
                    $Members = Get-MgGroupMember -GroupId $AzureGroup.Id -ErrorAction SilentlyContinue
                    $Result.MemberCount = $Members.Count
                    
                    # Process each member with type checking
                    foreach ($Member in $Members) {
                        try {
                            $MemberInfo = @{
                                Name = "Unknown"
                                Type = "Unknown"
                                Id = $Member.Id
                            }
                            
                            # Check what type of object this is
                            switch ($Member.'@odata.type') {
                                '#microsoft.graph.user' {
                                    $User = Get-MgUser -UserId $Member.Id -Property "displayName,userPrincipalName" -ErrorAction SilentlyContinue
                                    if ($User) {
                                        $MemberInfo.Name = $User.DisplayName
                                        $MemberInfo.Type = "User"
                                        $Result.Members += $User.DisplayName
                                    }
                                }
                                '#microsoft.graph.group' {
                                    $SubGroup = Get-MgGroup -GroupId $Member.Id -Property "displayName" -ErrorAction SilentlyContinue
                                    if ($SubGroup) {
                                        $MemberInfo.Name = $SubGroup.DisplayName
                                        $MemberInfo.Type = "Group"
                                        $Result.Members += "$($SubGroup.DisplayName) (Group)"
                                    }
                                }
                                '#microsoft.graph.servicePrincipal' {
                                    $MemberInfo.Name = "Service Principal"
                                    $MemberInfo.Type = "ServicePrincipal"
                                    $Result.Members += "Service Principal"
                                }
                                default {
                                    $MemberInfo.Name = "Unknown Object Type"
                                    $MemberInfo.Type = $Member.'@odata.type'
                                    $Result.Members += "Unknown: $($Member.'@odata.type')"
                                }
                            }
                            
                            $Result.MemberDetails += $MemberInfo
                        }
                        catch {
                            $Result.Members += "Member lookup failed"
                        }
                    }
                }
                catch {
                    $Result.Members += "Group member lookup failed"
                }
            }
            
            Disconnect-MgGraph | Out-Null
            return $Result
            
        } -ArgumentList $Credentials.TenantId, $Credentials.ClientId, $Credentials.ClientSecret, $Identity
        
        $JobCompleted = Wait-Job -Job $AzureGroupJob -Timeout 45
        
        if ($JobCompleted) {
            $AzureResult = Receive-Job -Job $AzureGroupJob
            if ($AzureResult.Found) {
                $GroupStatus.AzureExists = $true
                $GroupStatus.AzureMemberCount = $AzureResult.MemberCount
                $GroupStatus.AzureMembers = $AzureResult.Members
                if (-not $GroupStatus.DisplayName) {
                    $GroupStatus.DisplayName = $AzureResult.DisplayName
                }
                Write-Host "    ✓ Found in Azure AD: $($AzureResult.DisplayName) ($($AzureResult.MemberCount) members)" -ForegroundColor Green
                
                # Show member breakdown if detailed info available
                if ($AzureResult.MemberDetails -and $AzureResult.MemberDetails.Count -gt 0) {
                    $UserCount = ($AzureResult.MemberDetails | Where-Object { $_.Type -eq "User" }).Count
                    $GroupCount = ($AzureResult.MemberDetails | Where-Object { $_.Type -eq "Group" }).Count
                    $OtherCount = ($AzureResult.MemberDetails | Where-Object { $_.Type -notin @("User", "Group") }).Count
                    
                    if ($UserCount -gt 0) { Write-Host "      Users: $UserCount" -ForegroundColor Gray }
                    if ($GroupCount -gt 0) { Write-Host "      Nested Groups: $GroupCount" -ForegroundColor Gray }
                    if ($OtherCount -gt 0) { Write-Host "      Other Objects: $OtherCount" -ForegroundColor Gray }
                }
            } else {
                Write-Host "    ✗ Not found in Azure AD" -ForegroundColor Red
            }
        } else {
            Write-Host "    ✗ Azure AD lookup timed out" -ForegroundColor Red
            $GroupStatus.Issues += "Azure AD lookup timeout"
            Stop-Job -Job $AzureGroupJob -Force
        }
        
        Remove-Job -Job $AzureGroupJob -Force
        
    }
    catch {
        $GroupStatus.Issues += "Azure AD lookup failed"
        Write-Host "    ✗ Azure AD error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Determine sync status
    if ($GroupStatus.ADExists -and $GroupStatus.AzureExists) {
        $GroupStatus.SyncStatus = "Synchronized"
        if ($GroupStatus.ADMemberCount -ne $GroupStatus.AzureMemberCount) {
            $GroupStatus.Issues += "Member count mismatch (AD: $($GroupStatus.ADMemberCount), Azure: $($GroupStatus.AzureMemberCount))"
        }
    } elseif ($GroupStatus.ADExists -and -not $GroupStatus.AzureExists) {
        $GroupStatus.SyncStatus = "AD Only"
    } elseif (-not $GroupStatus.ADExists -and $GroupStatus.AzureExists) {
        $GroupStatus.SyncStatus = "Azure Only"
    } else {
        $GroupStatus.SyncStatus = "Not Found"
        $GroupStatus.Issues += "Group not found in either directory"
    }
    
    return $GroupStatus
}

function Show-GroupStatusReport {
    param([PSCustomObject]$GroupStatus)
    
    Write-Host "`n=== GROUP STATUS REPORT ===" -ForegroundColor Cyan
    Write-Host "Identity: $($GroupStatus.Identity)" -ForegroundColor White
    Write-Host "Display Name: $($GroupStatus.DisplayName)" -ForegroundColor White
    Write-Host "Sync Status: $($GroupStatus.SyncStatus)" -ForegroundColor $(
        switch ($GroupStatus.SyncStatus) {
            "Synchronized" { "Green" }
            "AD Only" { "Yellow" }
            "Azure Only" { "Yellow" }
            "Not Found" { "Red" }
            default { "Gray" }
        }
    )
    
    if ($GroupStatus.ADExists) {
        Write-Host "`n📁 ACTIVE DIRECTORY:" -ForegroundColor Blue
        Write-Host "  Type: $($GroupStatus.GroupType)" -ForegroundColor White
        Write-Host "  Members: $($GroupStatus.ADMemberCount)" -ForegroundColor White
        if ($GroupStatus.ADMembers.Count -gt 0) {
            Write-Host "  Member List: $($GroupStatus.ADMembers -join ', ')" -ForegroundColor White
        }
    }
    
    if ($GroupStatus.AzureExists) {
        Write-Host "`n☁️ AZURE AD:" -ForegroundColor Blue
        Write-Host "  Members: $($GroupStatus.AzureMemberCount)" -ForegroundColor White
        if ($GroupStatus.AzureMembers.Count -gt 0) {
            Write-Host "  Member List: $($GroupStatus.AzureMembers -join ', ')" -ForegroundColor White
        }
    }
    
    if ($GroupStatus.Issues.Count -gt 0) {
        Write-Host "`n⚠️ ISSUES:" -ForegroundColor Red
        $GroupStatus.Issues | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor Red
        }
    }
}
function Show-UserStatusReport {
    param([PSCustomObject]$UserStatus)
    
    Write-Host "`n=== USER STATUS REPORT ===" -ForegroundColor Cyan
    Write-Host "Identity: $($UserStatus.Identity)" -ForegroundColor White
    Write-Host "Display Name: $($UserStatus.DisplayName)" -ForegroundColor White
    Write-Host "Sync Status: $($UserStatus.SyncStatus)" -ForegroundColor $(
        switch ($UserStatus.SyncStatus) {
            "Synchronized" { "Green" }
            "AD Only" { "Yellow" }
            "Azure Only" { "Yellow" }
            "Not Found" { "Red" }
            default { "Gray" }
        }
    )
    
    if ($UserStatus.ADExists) {
        Write-Host "`n📁 ACTIVE DIRECTORY:" -ForegroundColor Blue
        Write-Host "  Enabled: $($UserStatus.ADEnabled)" -ForegroundColor White
        if ($UserStatus.ADGroups.Count -gt 0) {
            Write-Host "  Groups ($($UserStatus.ADGroups.Count)): $($UserStatus.ADGroups -join ', ')" -ForegroundColor White
        }
    }
    
    if ($UserStatus.AzureExists) {
        Write-Host "`n☁️ AZURE AD:" -ForegroundColor Blue
        Write-Host "  Enabled: $($UserStatus.AzureEnabled)" -ForegroundColor White
    }
    
    if ($UserStatus.Issues.Count -gt 0) {
        Write-Host "`n⚠️ ISSUES:" -ForegroundColor Red
        $UserStatus.Issues | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor Red
        }
    }
}

# Main execution
if ($UserIdentity) {
    $UserStatus = Get-UserStatus -Identity $UserIdentity
    Show-UserStatusReport -UserStatus $UserStatus
} elseif ($GroupIdentity) {
    $GroupStatus = Get-GroupStatus -Identity $GroupIdentity
    Show-GroupStatusReport -GroupStatus $GroupStatus
} else {
    Write-Host "`n📋 USAGE EXAMPLES:" -ForegroundColor Cyan
    Write-Host "Check user:   .\Scripts\Get-ProvisioningStatus.ps1 -UserIdentity 'athompson'" -ForegroundColor White
    Write-Host "Check group:  .\Scripts\Get-ProvisioningStatus.ps1 -GroupIdentity 'Frontend-Developers'" -ForegroundColor White
}

Write-Host "`n✅ STATUS CHECK COMPLETE!" -ForegroundColor Green