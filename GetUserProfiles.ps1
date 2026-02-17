# ============================================================
# Windows 11 - User Profile & Local Account Enumeration Script
# ============================================================

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  WINDOWS 11 USER PROFILE & LOCAL ACCOUNT ENUMERATION" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME | Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan

# -----------------------------------------------------------
# SECTION 1: All User Profiles on the Machine
# -----------------------------------------------------------
Write-Host "`n[SECTION 1] USER PROFILES (from Registry)" -ForegroundColor Yellow
Write-Host "-" * 50

$profileList = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" |
    Where-Object { $_.PSChildName -match '^S-1-5-21' } |
    Select-Object @{Name="SID";Expression={$_.PSChildName}},
                  @{Name="ProfilePath";Expression={$_.ProfileImagePath}},
                  @{Name="Username";Expression={
                      try {
                          $objSID = New-Object System.Security.Principal.SecurityIdentifier($_.PSChildName)
                          $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
                          $objUser.Value
                      } catch { "Unknown (Orphaned Profile)" }
                  }},
                  @{Name="LastUsed";Expression={
                      if ($_.LocalProfileLoadTimeLow -and $_.LocalProfileLoadTimeHigh) {
                          $ft = ([Int64]$_.LocalProfileLoadTimeHigh -shl 32) -bor [UInt32]$_.LocalProfileLoadTimeLow
                          if ($ft -gt 0) { [DateTime]::FromFileTime($ft).ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
                      } else { "N/A" }
                  }}

if ($profileList) {
    $profileList | Format-Table -AutoSize -Wrap
    Write-Host "Total profiles found: $($profileList.Count)" -ForegroundColor Green
} else {
    Write-Host "No user profiles found." -ForegroundColor Red
}

# -----------------------------------------------------------
# SECTION 2: Local User Accounts
# -----------------------------------------------------------
Write-Host "`n[SECTION 2] LOCAL USER ACCOUNTS" -ForegroundColor Yellow
Write-Host "-" * 50

$localUsers = Get-LocalUser | Select-Object Name, Enabled, 
    @{Name="LastLogon";Expression={if($_.LastLogon){$_.LastLogon.ToString("yyyy-MM-dd HH:mm:ss")}else{"Never"}}},
    @{Name="PasswordLastSet";Expression={if($_.PasswordLastSet){$_.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss")}else{"N/A"}}},
    @{Name="PasswordExpires";Expression={if($_.PasswordExpires){$_.PasswordExpires.ToString("yyyy-MM-dd HH:mm:ss")}else{"Never"}}},
    Description

$localUsers | Format-Table -AutoSize -Wrap

# -----------------------------------------------------------
# SECTION 3: Admin vs Standard User Classification
# -----------------------------------------------------------
Write-Host "`n[SECTION 3] ACCESS LEVEL (Admin vs Standard)" -ForegroundColor Yellow
Write-Host "-" * 50

# Get members of the Administrators group
$adminMembers = @()
try {
    $adminGroup = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
    $adminMembers = $adminGroup | ForEach-Object { $_.Name }
} catch {
    Write-Host "Could not enumerate Administrators group: $_" -ForegroundColor Red
}

foreach ($user in Get-LocalUser) {
    $fullName = "$env:COMPUTERNAME\$($user.Name)"
    $isAdmin = $adminMembers | Where-Object { $_ -eq $fullName -or $_ -like "*\$($user.Name)" }
    
    $accessLevel = if ($isAdmin) { "ADMINISTRATOR" } else { "STANDARD USER" }
    $status = if ($user.Enabled) { "Enabled" } else { "Disabled" }
    $color = if ($isAdmin) { "Red" } else { "Green" }

    Write-Host ("  {0,-25} | {1,-15} | {2}" -f $user.Name, $accessLevel, $status) -ForegroundColor $color
}

# -----------------------------------------------------------
# SECTION 4: Local Group Memberships (Detailed)
# -----------------------------------------------------------
Write-Host "`n`n[SECTION 4] LOCAL GROUP MEMBERSHIPS" -ForegroundColor Yellow
Write-Host "-" * 50

foreach ($user in Get-LocalUser) {
    $groups = @()
    foreach ($group in Get-LocalGroup) {
        try {
            $members = Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue
            if ($members.Name -like "*\$($user.Name)") {
                $groups += $group.Name
            }
        } catch { }
    }
    $groupList = if ($groups.Count -gt 0) { $groups -join ", " } else { "None" }
    Write-Host ("  {0,-25} -> {1}" -f $user.Name, $groupList)
}

# -----------------------------------------------------------
# SECTION 5: Domain/Azure AD Accounts in Admin Group
# -----------------------------------------------------------
Write-Host "`n`n[SECTION 5] NON-LOCAL ACCOUNTS WITH ADMIN ACCESS" -ForegroundColor Yellow
Write-Host "-" * 50

try {
    $allAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
    $nonLocal = $allAdmins | Where-Object { $_.ObjectClass -ne "User" -or $_.PrincipalSource -ne "Local" }
    
    if ($nonLocal) {
        foreach ($member in $nonLocal) {
            Write-Host ("  {0,-35} | Type: {1} | Source: {2}" -f $member.Name, $member.ObjectClass, $member.PrincipalSource)
        }
    } else {
        Write-Host "  No domain/AzureAD accounts found in Administrators group." -ForegroundColor Gray
    }
} catch {
    Write-Host "  Could not query: $_" -ForegroundColor Red
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "  Scan Complete" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
