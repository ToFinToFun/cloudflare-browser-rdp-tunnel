#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cloudflare Browser-RDP Tunnel by JPaasovaara
    Zero Trust Browser-based Remote Desktop

.DESCRIPTION
    Makes this Windows PC accessible via RDP directly in a web browser.
    No VPN or client software needed on the connecting device.
    Installs as a separate service (cloudflared-rdp) - does NOT affect
    any existing cloudflared installations.

    Detects Azure AD/Entra ID joined devices and offers to fix common
    RDP compatibility issues interactively.

.LINK
    https://github.com/ToFinToFun/cloudflare-browser-rdp-tunnel
#>

$ErrorActionPreference = "Stop"

# --- Configuration ---
$SvcName     = "cloudflared-rdp"
$SvcDisplay  = "Cloudflare Browser-RDP Tunnel"
$InstallDir  = "C:\Program Files\cloudflared-rdp"
$ExePath     = "$InstallDir\cloudflared.exe"
$TokenFile   = "$InstallDir\token.txt"
$DownloadUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$SlotsFile   = Join-Path $ScriptDir "slots.txt"

# --- Results ---
$Results = [ordered]@{
    "Administrator"       = "FAIL"
    "Windows Edition"     = "FAIL"
    "Remote Desktop"      = "FAIL"
    "Azure AD Check"      = "SKIP"
    "Download"            = "FAIL"
    "Service Install"     = "FAIL"
    "Watchdog"            = "FAIL"
    "Service Start"       = "FAIL"
    "Connection Verify"   = "FAIL"
}

# --- Functions ---
function Show-Banner {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host "  Cloudflare Browser-RDP Tunnel by JPaasovaara" -ForegroundColor Green
    Write-Host "  Zero Trust Browser-based Remote Desktop" -ForegroundColor Green
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  This tool makes your PC accessible via Remote Desktop"
    Write-Host "  directly in a web browser - from anywhere in the world."
    Write-Host "  No VPN or client software needed on the connecting device."
    Write-Host ""
    Write-Host "  Installs as a SEPARATE service ($SvcName)"
    Write-Host "  Will NOT affect any existing cloudflared tunnels."
    Write-Host ""
}

function Show-FAQ {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host "  FAQ - How it works" -ForegroundColor Cyan
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  HOW DOES IT WORK?" -ForegroundColor Yellow
    Write-Host "  This installs 'cloudflared' as a hidden Windows service."
    Write-Host "  It creates an outbound tunnel to Cloudflare, making your"
    Write-Host "  PC's RDP port accessible via a secure HTTPS address."
    Write-Host ""
    Write-Host "  The tunnel is OUTBOUND only - no ports are opened."
    Write-Host "  Starts at boot, survives sleep/hibernate, auto-restarts."
    Write-Host ""
    Write-Host "  ---"
    Write-Host ""
    Write-Host "  WHAT DO I NEED?" -ForegroundColor Yellow
    Write-Host "  1. Windows 10/11 Pro, Enterprise, or Education"
    Write-Host "  2. A domain name with DNS managed by Cloudflare"
    Write-Host "  3. A free Cloudflare account (Zero Trust, free up to 50 users)"
    Write-Host "  4. A Tunnel Token (see below)"
    Write-Host ""
    Write-Host "  ---"
    Write-Host ""
    Write-Host "  HOW DO I GET A TUNNEL TOKEN?" -ForegroundColor Yellow
    Write-Host "  1. Go to: https://one.dash.cloudflare.com"
    Write-Host "  2. Navigate to: Networks > Tunnels"
    Write-Host "  3. Click 'Create a tunnel' > Select 'Cloudflared'"
    Write-Host "  4. Name your tunnel (e.g. 'My-Laptop')"
    Write-Host "  5. Copy the token (the long string after 'service install')"
    Write-Host "  6. Configure Public Hostname:"
    Write-Host "     - Subdomain: e.g. 'rdp'"
    Write-Host "     - Domain: your domain"
    Write-Host "     - Service Type: RDP"
    Write-Host "     - URL: localhost:3389"
    Write-Host "  7. Save the tunnel"
    Write-Host ""
    Write-Host "  Then protect with Access:"
    Write-Host "  8. Access > Applications > Add application"
    Write-Host "  9. Self-hosted, enter hostname, Browser Rendering: RDP"
    Write-Host "  10. Create policy: allow your email via OTP"
    Write-Host ""
    Write-Host "  ---"
    Write-Host ""
    Write-Host "  AZURE AD / ENTRA ID:" -ForegroundColor Yellow
    Write-Host "  If this PC is joined to Azure AD (Microsoft Entra ID),"
    Write-Host "  the script will detect it and offer fixes for common"
    Write-Host "  RDP compatibility issues. You will be asked before any"
    Write-Host "  changes are made."
    Write-Host ""
    Write-Host "  ---"
    Write-Host ""
    Write-Host "  LINKS:" -ForegroundColor Yellow
    Write-Host "  - Dashboard: https://one.dash.cloudflare.com"
    Write-Host "  - Add domain: https://dash.cloudflare.com"
    Write-Host "  - This project: https://github.com/ToFinToFun/cloudflare-browser-rdp-tunnel"
    Write-Host ""
    Write-Host "  IS IT FREE?" -ForegroundColor Yellow
    Write-Host "  Yes. You need a domain (~`$10/year) with DNS on Cloudflare (free)."
    Write-Host ""
    Write-Host "  IS IT SAFE?" -ForegroundColor Yellow
    Write-Host "  - Outbound only (no open ports)"
    Write-Host "  - Protected by Cloudflare Access (OTP/SSO)"
    Write-Host "  - RDP uses Network Level Authentication"
    Write-Host "  - Token only grants tunnel connection rights"
    Write-Host ""
    Write-Host "  SLOTS.TXT:" -ForegroundColor Yellow
    Write-Host "  Place a 'slots.txt' next to this script for a menu."
    Write-Host "  Format: hostname|token (one per line)"
    Write-Host ""
}

function Show-Checklist {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host "  INSTALLATION RESULTS" -ForegroundColor Green
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host ""
    foreach ($key in $Results.Keys) {
        $val = $Results[$key]
        if ($val -eq "OK") {
            Write-Host "  [OK]   $key" -ForegroundColor Green
        }
        elseif ($val -eq "SKIP") {
            Write-Host "  [--]   $key (not applicable)" -ForegroundColor Gray
        }
        else {
            Write-Host "  [FAIL] $key" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Green
}

function Test-AzureADJoined {
    <#
    .SYNOPSIS
        Detects if this PC is Azure AD (Entra ID) joined.
        Returns a hashtable with join status details.
    #>
    $result = @{
        IsAzureADJoined = $false
        IsHybridJoined  = $false
        JoinType        = "None"
        TenantName      = ""
        UserName        = ""
    }
    
    try {
        $dsreg = dsregcmd /status 2>$null
        if ($dsreg) {
            $azureAdJoined = ($dsreg | Select-String "AzureAdJoined\s*:\s*YES") -ne $null
            $domainJoined = ($dsreg | Select-String "DomainJoined\s*:\s*YES") -ne $null
            $tenantLine = $dsreg | Select-String "TenantName\s*:\s*(.+)"
            
            if ($azureAdJoined) {
                $result.IsAzureADJoined = $true
                if ($domainJoined) {
                    $result.IsHybridJoined = $true
                    $result.JoinType = "Hybrid Azure AD Joined"
                } else {
                    $result.JoinType = "Azure AD Joined (pure)"
                }
            }
            
            if ($tenantLine) {
                $result.TenantName = ($tenantLine -replace ".*:\s*", "").Trim()
            }
        }
    }
    catch {
        # dsregcmd not available - likely not Azure AD
    }
    
    # Also check current user
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $result.UserName = $currentUser
    
    return $result
}

function Test-NLAEnabled {
    $nla = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue
    return ($nla -and $nla.UserAuthentication -eq 1)
}

function Test-PKU2UEnabled {
    $pku2u = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Pku2u" -Name "AllowOnlineID" -ErrorAction SilentlyContinue
    return ($pku2u -and $pku2u.AllowOnlineID -eq 1)
}

function Show-AzureADDiagnostics {
    <#
    .SYNOPSIS
        Detects Azure AD RDP issues and offers interactive fixes.
        Returns $true if all checks pass or user fixed them.
    #>
    param(
        [hashtable]$AzureInfo
    )
    
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host "  AZURE AD / ENTRA ID DETECTED" -ForegroundColor Yellow
    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Join type:    $($AzureInfo.JoinType)" -ForegroundColor White
    if ($AzureInfo.TenantName) {
        Write-Host "  Tenant:       $($AzureInfo.TenantName)" -ForegroundColor White
    }
    Write-Host "  Current user: $($AzureInfo.UserName)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Azure AD devices have known compatibility issues with" -ForegroundColor White
    Write-Host "  browser-based RDP (Cloudflare, Apache Guacamole, etc.)" -ForegroundColor White
    Write-Host "  because these tools cannot perform PKU2U authentication." -ForegroundColor White
    Write-Host ""
    Write-Host "  The script will now check for common issues and offer" -ForegroundColor White
    Write-Host "  fixes. You will be asked before ANY change is made." -ForegroundColor White
    Write-Host ""
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
    
    $issuesFound = 0
    $issuesFixed = 0
    
    # ---------------------------------------------------------------
    # CHECK 1: NLA (Network Level Authentication)
    # ---------------------------------------------------------------
    Write-Host ""
    Write-Host "  CHECK 1: Network Level Authentication (NLA)" -ForegroundColor Cyan
    Write-Host ""
    
    $nlaEnabled = Test-NLAEnabled
    
    if ($nlaEnabled) {
        $issuesFound++
        Write-Host "  STATUS: NLA is ENABLED (blocking browser-based RDP)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  PROBLEM:" -ForegroundColor Yellow
        Write-Host "  NLA requires the connecting client to authenticate BEFORE"
        Write-Host "  the RDP session starts. Browser-based RDP clients (like"
        Write-Host "  Cloudflare's) cannot perform NLA with Azure AD credentials"
        Write-Host "  because they don't support PKU2U protocol."
        Write-Host ""
        Write-Host "  This is why you see 'Unable to connect to your remote desktop'"
        Write-Host "  even with correct username and password."
        Write-Host ""
        Write-Host "  FIX: Disable NLA (Network Level Authentication)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  WHAT THIS CHANGES:" -ForegroundColor White
        Write-Host "  - Registry: HKLM\...\RDP-Tcp\UserAuthentication = 0"
        Write-Host "  - RDP clients will authenticate AFTER connecting"
        Write-Host "    (credentials sent to Windows login screen directly)"
        Write-Host ""
        Write-Host "  RISK ASSESSMENT:" -ForegroundColor White
        Write-Host "  - LOW RISK in your setup. Your RDP port is NOT exposed to"
        Write-Host "    the internet. Access is only possible through Cloudflare"
        Write-Host "    Zero Trust (which already requires OTP authentication)."
        Write-Host "  - Without NLA, an attacker would need to pass Cloudflare"
        Write-Host "    Access first, then still know the Windows password."
        Write-Host "  - NLA mainly protects against brute-force on open RDP ports"
        Write-Host "    (port 3389 exposed to internet) - which does NOT apply here."
        Write-Host ""
        
        $fix1 = Read-Host "  Apply fix? Disable NLA [Y/N]"
        if ($fix1 -eq "Y" -or $fix1 -eq "y") {
            try {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
                Write-Host "  [OK] NLA disabled." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                Write-Host "  [X] Failed to disable NLA: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  [--] Skipped. NLA remains enabled." -ForegroundColor Yellow
            Write-Host "       Note: Browser RDP will likely NOT work with Azure AD." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  STATUS: NLA is already DISABLED (good for browser RDP)" -ForegroundColor Green
    }
    
    # ---------------------------------------------------------------
    # CHECK 2: PKU2U (online identity authentication)
    # ---------------------------------------------------------------
    Write-Host ""
    Write-Host "  CHECK 2: PKU2U Protocol (Azure AD authentication)" -ForegroundColor Cyan
    Write-Host ""
    
    $pku2uEnabled = Test-PKU2UEnabled
    
    if (-not $pku2uEnabled) {
        $issuesFound++
        Write-Host "  STATUS: PKU2U is DISABLED" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  PROBLEM:" -ForegroundColor Yellow
        Write-Host "  PKU2U is the protocol Windows uses to authenticate Azure AD"
        Write-Host "  users for RDP connections. Without it, Azure AD credentials"
        Write-Host "  may not be accepted even if NLA is disabled."
        Write-Host ""
        Write-Host "  FIX: Enable PKU2U protocol" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  WHAT THIS CHANGES:" -ForegroundColor White
        Write-Host "  - Registry: HKLM\SYSTEM\...\Lsa\Pku2u\AllowOnlineID = 1"
        Write-Host "  - Allows Windows to verify Azure AD identities for RDP"
        Write-Host ""
        Write-Host "  RISK ASSESSMENT:" -ForegroundColor White
        Write-Host "  - VERY LOW RISK. This is Microsoft's own recommended setting"
        Write-Host "    for Azure AD joined devices that need RDP."
        Write-Host "  - It only enables an authentication protocol - it does not"
        Write-Host "    open any ports or weaken any passwords."
        Write-Host ""
        
        $fix2 = Read-Host "  Apply fix? Enable PKU2U [Y/N]"
        if ($fix2 -eq "Y" -or $fix2 -eq "y") {
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Pku2u"
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }
                Set-ItemProperty -Path $regPath -Name "AllowOnlineID" -Value 1 -Type DWord -Force
                Write-Host "  [OK] PKU2U enabled." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                Write-Host "  [X] Failed to enable PKU2U: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  [--] Skipped. PKU2U remains disabled." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  STATUS: PKU2U is already ENABLED (good)" -ForegroundColor Green
    }
    
    # ---------------------------------------------------------------
    # CHECK 3: Remote Desktop Users group
    # ---------------------------------------------------------------
    Write-Host ""
    Write-Host "  CHECK 3: Remote Desktop Users group" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if Authenticated Users or the Azure AD user is in RDP group
    $rdpGroup = net localgroup "Remote Desktop Users" 2>$null
    $hasAuthUsers = $rdpGroup | Select-String "Authenticated Users"
    $hasNTAuthority = $rdpGroup | Select-String "NT AUTHORITY"
    
    # For Azure AD, check if the SID-based entries exist
    $currentSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $hasSidEntry = $rdpGroup | Select-String $currentSid
    
    # Show current members
    Write-Host "  Current Remote Desktop Users members:" -ForegroundColor White
    $memberLines = $rdpGroup | Where-Object { $_ -match "^\S" -and $_ -notmatch "^(The command|Members|---)" }
    if ($memberLines) {
        foreach ($m in $memberLines) {
            if ($m.Trim()) { Write-Host "    - $($m.Trim())" }
        }
    }
    else {
        Write-Host "    (none)" -ForegroundColor Yellow
    }
    Write-Host ""
    
    if (-not $hasAuthUsers) {
        $issuesFound++
        Write-Host "  STATUS: 'Authenticated Users' NOT in Remote Desktop Users" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  PROBLEM:" -ForegroundColor Yellow
        Write-Host "  On Azure AD joined devices, adding specific Azure AD users"
        Write-Host "  to the RDP group can be unreliable. Adding 'Authenticated"
        Write-Host "  Users' ensures anyone who can authenticate (with correct"
        Write-Host "  password) can use RDP."
        Write-Host ""
        Write-Host "  FIX: Add 'Authenticated Users' to Remote Desktop Users" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  WHAT THIS CHANGES:" -ForegroundColor White
        Write-Host "  - Adds 'Authenticated Users' to local 'Remote Desktop Users' group"
        Write-Host "  - Any user who knows the correct password can RDP in"
        Write-Host ""
        Write-Host "  RISK ASSESSMENT:" -ForegroundColor White
        Write-Host "  - LOW RISK in your setup. Access is gated by:"
        Write-Host "    1. Cloudflare Zero Trust (OTP email verification)"
        Write-Host "    2. Windows login password"
        Write-Host "  - This does NOT bypass any password requirement."
        Write-Host "  - It only ensures Azure AD users aren't blocked by group"
        Write-Host "    membership issues."
        Write-Host ""
        
        $fix3 = Read-Host "  Apply fix? Add 'Authenticated Users' to RDP group [Y/N]"
        if ($fix3 -eq "Y" -or $fix3 -eq "y") {
            try {
                net localgroup "Remote Desktop Users" "Authenticated Users" /add 2>$null
                Write-Host "  [OK] 'Authenticated Users' added to Remote Desktop Users." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                Write-Host "  [X] Failed: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  [--] Skipped." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  STATUS: 'Authenticated Users' is in the group (good)" -ForegroundColor Green
    }
    
    # ---------------------------------------------------------------
    # CHECK 4: CredSSP / Encryption Oracle Remediation
    # ---------------------------------------------------------------
    Write-Host ""
    Write-Host "  CHECK 4: CredSSP Encryption Oracle policy" -ForegroundColor Cyan
    Write-Host ""
    
    $credSSPPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters"
    $credSSP = Get-ItemProperty -Path $credSSPPath -Name "AllowEncryptionOracle" -ErrorAction SilentlyContinue
    
    if (-not $credSSP -or $credSSP.AllowEncryptionOracle -ne 2) {
        $issuesFound++
        Write-Host "  STATUS: CredSSP not set to 'Vulnerable' mode" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  PROBLEM:" -ForegroundColor Yellow
        Write-Host "  Some Azure AD + RDP combinations fail because of CredSSP"
        Write-Host "  encryption negotiation mismatches between the browser client"
        Write-Host "  and Windows. Setting this to 'Vulnerable' allows fallback."
        Write-Host ""
        Write-Host "  FIX: Set CredSSP AllowEncryptionOracle = 2 (Vulnerable)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  WHAT THIS CHANGES:" -ForegroundColor White
        Write-Host "  - Registry: ...\CredSSP\Parameters\AllowEncryptionOracle = 2"
        Write-Host "  - Allows older CredSSP protocol versions as fallback"
        Write-Host ""
        Write-Host "  RISK ASSESSMENT:" -ForegroundColor White
        Write-Host "  - MEDIUM-LOW RISK. This is a workaround for CVE-2018-0886."
        Write-Host "  - The vulnerability requires a man-in-the-middle position"
        Write-Host "    on the network between client and server."
        Write-Host "  - In your setup, the connection goes through Cloudflare's"
        Write-Host "    encrypted tunnel, making MITM practically impossible."
        Write-Host "  - Microsoft patched this in 2018; modern Windows is safe."
        Write-Host ""
        Write-Host "  NOTE: This fix is OPTIONAL. Try without it first." -ForegroundColor Gray
        Write-Host "        Only apply if RDP still fails after fixes 1-3." -ForegroundColor Gray
        Write-Host ""
        
        $fix4 = Read-Host "  Apply fix? Set CredSSP to Vulnerable mode [Y/N]"
        if ($fix4 -eq "Y" -or $fix4 -eq "y") {
            try {
                $parentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP"
                if (-not (Test-Path $parentPath)) {
                    New-Item -Path $parentPath -Force | Out-Null
                }
                if (-not (Test-Path $credSSPPath)) {
                    New-Item -Path $credSSPPath -Force | Out-Null
                }
                Set-ItemProperty -Path $credSSPPath -Name "AllowEncryptionOracle" -Value 2 -Type DWord -Force
                Write-Host "  [OK] CredSSP set to Vulnerable mode." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                Write-Host "  [X] Failed: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  [--] Skipped (recommended to try without this first)." -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  STATUS: CredSSP already set to Vulnerable mode (OK)" -ForegroundColor Green
    }
    
    # ---------------------------------------------------------------
    # SUMMARY
    # ---------------------------------------------------------------
    Write-Host ""
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($issuesFound -eq 0) {
        Write-Host "  All Azure AD checks passed! No issues found." -ForegroundColor Green
        $Results["Azure AD Check"] = "OK"
    }
    elseif ($issuesFixed -eq $issuesFound) {
        Write-Host "  All $issuesFound issue(s) fixed!" -ForegroundColor Green
        $Results["Azure AD Check"] = "OK"
    }
    elseif ($issuesFixed -gt 0) {
        Write-Host "  Fixed $issuesFixed of $issuesFound issue(s)." -ForegroundColor Yellow
        Write-Host "  Some issues remain - browser RDP may not work." -ForegroundColor Yellow
        $Results["Azure AD Check"] = "OK"
    }
    else {
        Write-Host "  $issuesFound issue(s) found but none fixed." -ForegroundColor Red
        Write-Host "  Browser RDP will likely NOT work with Azure AD." -ForegroundColor Red
        $Results["Azure AD Check"] = "FAIL"
    }
    
    Write-Host ""
    Write-Host "  LOGIN TIP FOR AZURE AD:" -ForegroundColor Cyan
    Write-Host "  When connecting via browser RDP, use this format:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Username: AzureAD\YourName" -ForegroundColor Green
    Write-Host "    (e.g. AzureAD\ElinaPaasovaara)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    OR: your-email@domain.com" -ForegroundColor Green
    Write-Host "    (e.g. elina@baik.nu)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Password: Your Microsoft account password" -ForegroundColor Green
    Write-Host "    (NOT your PIN - PINs don't work over RDP)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  To find your exact username, run 'whoami' in CMD." -ForegroundColor White
    Write-Host ""
}

# ===================================================================
# MAIN
# ===================================================================

Show-Banner

$mainChoice = Read-Host "  Press [I] to install/manage, [Q] for FAQ"
if ($mainChoice -eq "Q") {
    Show-FAQ
    $faqChoice = Read-Host "  Press [I] to install, [X] to exit"
    if ($faqChoice -ne "I") { exit 0 }
}
elseif ($mainChoice -ne "I") {
    Write-Host "  Invalid choice." -ForegroundColor Red
    pause; exit 1
}

# --- PRE-CHECK: Admin ---
Write-Host ""
Write-Host "[Pre-check] Verifying administrator privileges..." -ForegroundColor Cyan
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [X] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "      Right-click > Run with PowerShell (Admin)" -ForegroundColor Red
    pause; exit 1
}
Write-Host "  [OK] Administrator confirmed." -ForegroundColor Green
$Results["Administrator"] = "OK"

# --- PRE-CHECK: Windows Edition ---
Write-Host ""
Write-Host "[Pre-check] Verifying Windows edition (RDP support)..." -ForegroundColor Cyan
$edition = (Get-WindowsEdition -Online).Edition
if ($edition -match "Home|Core") {
    Write-Host "  [X] Windows Home detected ($edition)" -ForegroundColor Red
    Write-Host "      RDP requires Pro, Enterprise, or Education." -ForegroundColor Red
    pause; exit 1
}
Write-Host "  [OK] Windows edition: $edition" -ForegroundColor Green
$Results["Windows Edition"] = "OK"

# --- DETECT: Existing installation ---
Write-Host ""
Write-Host "[Detect] Checking for existing Browser-RDP installation..." -ForegroundColor Cyan
$existingSvc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue

if ($existingSvc) {
    Write-Host ""
    Write-Host "  A Browser-RDP tunnel is already installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [R] Reinstall / Change address"
    Write-Host "  [U] Uninstall completely"
    Write-Host "  [D] Run diagnostics only (Azure AD check)"
    Write-Host "  [Q] Quit - do nothing"
    Write-Host ""
    $existChoice = Read-Host "  Choose [R/U/D/Q]"
    
    if ($existChoice -eq "Q") { Write-Host "  Cancelled."; pause; exit 0 }
    
    if ($existChoice -eq "D" -or $existChoice -eq "d") {
        # Run Azure AD diagnostics only
        $azureInfo = Test-AzureADJoined
        if ($azureInfo.IsAzureADJoined) {
            Show-AzureADDiagnostics -AzureInfo $azureInfo
        }
        else {
            Write-Host ""
            Write-Host "  This PC is NOT Azure AD joined." -ForegroundColor Green
            Write-Host "  Azure AD fixes are not needed." -ForegroundColor Green
            Write-Host ""
            Write-Host "  If RDP still doesn't work, check:" -ForegroundColor White
            Write-Host "  - Is the tunnel service running? (services.msc > $SvcName)" -ForegroundColor White
            Write-Host "  - Is the correct username/password being used?" -ForegroundColor White
            Write-Host "  - Is the PC awake (not sleeping/hibernating)?" -ForegroundColor White
        }
        Write-Host ""
        pause; exit 0
    }
    
    if ($existChoice -eq "U" -or $existChoice -eq "R") {
        Write-Host "  Removing existing installation..." -ForegroundColor Yellow
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $SvcName | Out-Null
        Start-Sleep -Seconds 2
        if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "  [OK] Removed." -ForegroundColor Green
        if ($existChoice -eq "U") { pause; exit 0 }
    }
    else {
        Write-Host "  Invalid choice."; pause; exit 1
    }
}
else {
    Write-Host "  [i] No existing installation found. Proceeding..." -ForegroundColor Gray
}

# --- MENU: Choose address ---
Write-Host ""
$slots = @()
if (Test-Path $SlotsFile) {
    $lines = Get-Content $SlotsFile | Where-Object { $_ -match "\|" }
    foreach ($line in $lines) {
        $parts = $line.Split("|", 2)
        $slots += [PSCustomObject]@{ Name = $parts[0].Trim(); Token = $parts[1].Trim() }
    }
}

$ChosenName = ""
$ChosenToken = ""

if ($slots.Count -gt 0) {
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host "  Choose an address for this PC:" -ForegroundColor Green
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host ""
    for ($i = 0; $i -lt $slots.Count; $i++) {
        Write-Host "    [$($i+1)] $($slots[$i].Name)"
    }
    Write-Host ""
    Write-Host "    [C] Custom (enter your own token and address)"
    Write-Host "    [Q] Quit"
    Write-Host ""
    $slotChoice = Read-Host "  Choose [1-$($slots.Count), C, or Q]"
    
    if ($slotChoice -eq "Q") { exit 0 }
    if ($slotChoice -eq "C") {
        # Fall through to manual input below
    }
    elseif ($slotChoice -match "^\d+$") {
        $idx = [int]$slotChoice - 1
        if ($idx -ge 0 -and $idx -lt $slots.Count) {
            $ChosenName = $slots[$idx].Name
            $ChosenToken = $slots[$idx].Token
        }
        else {
            Write-Host "  Invalid choice." -ForegroundColor Red
            pause; exit 1
        }
    }
    else {
        Write-Host "  Invalid choice." -ForegroundColor Red
        pause; exit 1
    }
}

if (-not $ChosenToken) {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host "  Tunnel Configuration" -ForegroundColor Green
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Enter your Cloudflare Tunnel Token."
    Write-Host "  (Found in Zero Trust Dashboard > Networks > Tunnels)"
    Write-Host ""
    $ChosenToken = Read-Host "  Tunnel token"
    if (-not $ChosenToken) { Write-Host "  No token entered."; pause; exit 1 }
    Write-Host ""
    $ChosenName = Read-Host "  Public hostname (e.g. rdp.yourdomain.com)"
    if (-not $ChosenName) { Write-Host "  No hostname entered."; pause; exit 1 }
}

Write-Host ""
Write-Host "  Selected: $ChosenName" -ForegroundColor Green
Write-Host ""

# --- STEP 1: Enable RDP ---
Write-Host "[1/5] Enabling Remote Desktop..." -ForegroundColor Cyan
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
    # NLA will be handled by Azure AD check - set to enabled by default for non-Azure AD
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Force
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Remote Desktop enabled (NLA active)." -ForegroundColor Green
    $Results["Remote Desktop"] = "OK"
}
catch {
    Write-Host "  [X] Failed to enable RDP: $_" -ForegroundColor Red
}

# --- AZURE AD CHECK (after RDP enabled, before download) ---
Write-Host ""
Write-Host "[Azure AD] Checking device join status..." -ForegroundColor Cyan
$azureInfo = Test-AzureADJoined

if ($azureInfo.IsAzureADJoined) {
    Show-AzureADDiagnostics -AzureInfo $azureInfo
}
else {
    Write-Host "  [i] Not Azure AD joined - no special fixes needed." -ForegroundColor Gray
    $Results["Azure AD Check"] = "SKIP"
}

# --- STEP 2: Download cloudflared ---
Write-Host ""
Write-Host "[2/5] Downloading Cloudflared..." -ForegroundColor Cyan
try {
    if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($DownloadUrl, $ExePath)
    
    $fileSize = (Get-Item $ExePath).Length
    if ($fileSize -lt 1000000) { throw "Downloaded file too small ($fileSize bytes)" }
    
    Write-Host "  [OK] Cloudflared downloaded ($([math]::Round($fileSize/1MB, 1)) MB)." -ForegroundColor Green
    $Results["Download"] = "OK"
}
catch {
    Write-Host "  [X] Download failed: $_" -ForegroundColor Red
}

# --- STEP 3: Install service ---
Write-Host ""
Write-Host "[3/5] Installing as background service ($SvcName)..." -ForegroundColor Cyan
try {
    # Save token to file
    Set-Content -Path $TokenFile -Value $ChosenToken -NoNewline -Force
    
    # Create service with NSSM-style direct approach
    $binPath = "`"$ExePath`" tunnel run --token $ChosenToken"
    
    # Use New-Service (PowerShell native - no escaping issues)
    New-Service -Name $SvcName `
        -BinaryPathName $binPath `
        -DisplayName $SvcDisplay `
        -Description "Cloudflare Browser-RDP Tunnel - browser-based remote desktop via Zero Trust" `
        -StartupType Automatic `
        -ErrorAction Stop | Out-Null
    
    # Set delayed auto-start via registry (compatible with all PS versions)
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$SvcName" -Name "DelayedAutostart" -Value 1 -Type DWord -Force
    
    Write-Host "  [OK] Service installed as '$SvcName'." -ForegroundColor Green
    $Results["Service Install"] = "OK"
}
catch {
    Write-Host "  [X] Service installation failed: $_" -ForegroundColor Red
}

# --- STEP 4: Watchdog ---
Write-Host ""
Write-Host "[4/5] Configuring watchdog (auto-recovery)..." -ForegroundColor Cyan
try {
    # Recovery: restart after 10s, 10s, 30s - reset counter after 24h
    sc.exe failure $SvcName reset= 86400 actions= restart/10000/restart/10000/restart/30000 | Out-Null
    sc.exe failureflag $SvcName 1 | Out-Null
    Write-Host "  [OK] Watchdog configured (auto-restart on crash, sleep, logout)." -ForegroundColor Green
    $Results["Watchdog"] = "OK"
}
catch {
    Write-Host "  [X] Watchdog configuration failed: $_" -ForegroundColor Red
}

# --- STEP 5: Start service ---
Write-Host ""
Write-Host "[5/5] Starting service..." -ForegroundColor Cyan
if ($Results["Service Install"] -eq "OK") {
    try {
        Start-Service -Name $SvcName -ErrorAction Stop
        Start-Sleep -Seconds 5
        
        $svc = Get-Service -Name $SvcName
        if ($svc.Status -eq "Running") {
            Write-Host "  [OK] Service running." -ForegroundColor Green
            $Results["Service Start"] = "OK"
        }
        else {
            throw "Service status: $($svc.Status)"
        }
    }
    catch {
        Write-Host "  [X] Service failed to start: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "  [!] Skipped (service not installed)." -ForegroundColor Yellow
}

# --- VERIFY ---
Write-Host ""
Write-Host "[Verify] Checking tunnel stability (10 seconds)..." -ForegroundColor Cyan
if ($Results["Service Start"] -eq "OK") {
    Start-Sleep -Seconds 10
    $svc = Get-Service -Name $SvcName
    if ($svc.Status -eq "Running") {
        Write-Host "  [OK] Tunnel active and stable." -ForegroundColor Green
        $Results["Connection Verify"] = "OK"
    }
    else {
        Write-Host "  [!] Service stopped after starting. Check Event Viewer." -ForegroundColor Yellow
    }
}
else {
    Write-Host "  [!] Skipped." -ForegroundColor Yellow
}

# --- CHECKLIST ---
Show-Checklist

$failures = ($Results.Values | Where-Object { $_ -eq "FAIL" }).Count

if ($failures -eq 0) {
    Write-Host ""
    Write-Host "  SUCCESS! This PC is now reachable at:" -ForegroundColor Green
    Write-Host "  https://$ChosenName" -ForegroundColor Green
    Write-Host ""
    Write-Host "  The service:" -ForegroundColor White
    Write-Host "  - Runs invisibly in the background"
    Write-Host "  - Starts automatically at boot"
    Write-Host "  - Survives logout, sleep, hibernate, and lock screen"
    Write-Host "  - Auto-restarts on crash (within 10 seconds)"
    Write-Host "  - Works on any network (WiFi, ethernet, mobile hotspot)"
    Write-Host ""
    
    if ($azureInfo.IsAzureADJoined) {
        Write-Host "  AZURE AD LOGIN:" -ForegroundColor Cyan
        Write-Host "  Username: AzureAD\$($azureInfo.UserName.Split('\')[-1])" -ForegroundColor White
        Write-Host "  Password: Your Microsoft account password (NOT PIN)" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "  You can now close this window and delete this script."
}
else {
    Write-Host ""
    Write-Host "  $failures step(s) failed. See details above." -ForegroundColor Red
}

Write-Host ""
Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Cloudflare Browser-RDP Tunnel by JPaasovaara - MIT License" -ForegroundColor DarkGray
Write-Host "  https://github.com/ToFinToFun/cloudflare-browser-rdp-tunnel" -ForegroundColor DarkGray
Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
pause
