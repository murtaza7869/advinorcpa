#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a local Windows user account and adds it to the local Administrators group.

.DESCRIPTION
    Designed for RMM deployment (SYSTEM context). Configures a new local user with
    specified credentials and grants local administrator privileges.

.NOTES
    - Run as SYSTEM or Administrator
    - Tested on Windows 10/11 and Windows Server 2016+
    - Exit codes: 0 = Success, 1 = Fatal error, 2 = User already exists (non-fatal)
#>

# ============================================================
#  CONFIGURATION — Edit these values before deploying
# ============================================================

$Username    = "AdminUser"           # Local username to create
$Password    = "Ch@ngeMe123!"        # Password (meet complexity requirements)
$FullName    = "Local Admin Account" # Display name (optional)
$Description = "Created via RMM"     # Account description (optional)
$NeverExpire = $true                 # $true = password never expires

# ============================================================
#  LOGGING
# ============================================================

$LogFile = "C:\Windows\Temp\Create-LocalAdminUser.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Output $entry
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ============================================================
#  MAIN
# ============================================================

Write-Log "=== Create-LocalAdminUser started ==="
Write-Log "Target username: $Username"

# --- Validate inputs ---
if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    Write-Log "Username or Password is empty. Aborting." "ERROR"
    exit 1
}

# --- Check if user already exists ---
$existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

if ($existingUser) {
    Write-Log "User '$Username' already exists. Skipping creation." "WARN"
    # Still ensure group membership below (idempotent behaviour)
} else {
    try {
        $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

        $newUserParams = @{
            Name        = $Username
            Password    = $securePassword
            FullName    = $FullName
            Description = $Description
            ErrorAction = "Stop"
        }

        if ($NeverExpire) {
            $newUserParams["PasswordNeverExpires"] = $true
        }

        New-LocalUser @newUserParams | Out-Null
        Write-Log "User '$Username' created successfully."
    }
    catch {
        Write-Log "Failed to create user '$Username': $_" "ERROR"
        exit 1
    }
}

# --- Add to local Administrators group ---
try {
    # Get the built-in Administrators group by well-known SID (locale-safe)
    $adminGroupSID = [System.Security.Principal.SecurityIdentifier]"S-1-5-32-544"
    $adminGroup    = Get-LocalGroup | Where-Object { $_.SID -eq $adminGroupSID }

    if (-not $adminGroup) {
        Write-Log "Could not resolve local Administrators group by SID." "ERROR"
        exit 1
    }

    # Check if already a member
    $members = Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction SilentlyContinue
    $isMember = $members | Where-Object { $_.Name -like "*\$Username" -or $_.Name -eq $Username }

    if ($isMember) {
        Write-Log "User '$Username' is already a member of '$($adminGroup.Name)'. No change needed."
    } else {
        Add-LocalGroupMember -Group $adminGroup.Name -Member $Username -ErrorAction Stop
        Write-Log "User '$Username' added to '$($adminGroup.Name)' successfully."
    }
}
catch {
    Write-Log "Failed to add '$Username' to Administrators group: $_" "ERROR"
    exit 1
}

# --- Verify ---
try {
    $verify = Get-LocalGroupMember -Group $adminGroup.Name | Where-Object { $_.Name -like "*\$Username" -or $_.Name -eq $Username }
    if ($verify) {
        Write-Log "Verification passed: '$Username' is confirmed in '$($adminGroup.Name)'."
    } else {
        Write-Log "Verification FAILED: '$Username' not found in '$($adminGroup.Name)' after add." "WARN"
    }
}
catch {
    Write-Log "Verification check error: $_" "WARN"
}

Write-Log "=== Create-LocalAdminUser completed successfully. Exiting 0. ==="
exit 0
