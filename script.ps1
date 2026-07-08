<#
.SYNOPSIS
    Cloudflare Browser-RDP Tunnel by JPaasovaara
    Zero Trust Browser-based Remote Desktop

.DESCRIPTION
    Makes this Windows PC accessible via RDP directly in a web browser.
    No VPN or client software needed on the connecting device.
    Installs as a separate service (cloudflared-rdp) - does NOT affect
    any existing cloudflared installations.

    Features:
    - Azure AD / Entra ID detection and automatic fix suggestions
    - Power management presets to keep the PC awake and reachable
    - Auto-recovery watchdog (survives sleep, logout, crashes)
    - Works on any network (WiFi, ethernet, mobile hotspot)

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

# --- Power Management Constants ---
$SUB_BUTTONS      = '4f971e89-eebd-4455-a8de-9e59040e7347'
$LID_ACTION       = '5ca83367-6e45-459f-a27b-476b1d01c936'
$CONN_IN_STANDBY  = 'f15576e8-98b7-4186-b944-eafa664402d9'
$REG_EXPLORER_POL = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$PM_MARKER_FILE   = Join-Path $env:ProgramData 'RdpAvailability\preset.txt'

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
    "Power Management"    = "SKIP"
}

# ===================================================================
# FUNCTIONS - UI
# ===================================================================

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
    Write-Host "  3. A Cloudflare Zero Trust account (free)"
    Write-Host "  4. A configured tunnel with Browser Rendering: RDP"
    Write-Host ""
    Write-Host "  ---"
    Write-Host ""
    Write-Host "  SETUP STEPS (done once by admin):" -ForegroundColor Yellow
    Write-Host "  1. Create a Cloudflare account and add your domain"
    Write-Host "  2. Enable Zero Trust (free plan works)"
    Write-Host "  3. Create a tunnel (Networks > Tunnels)"
    Write-Host "  4. Add a public hostname with service: RDP"
    Write-Host "  5. Create an Access Application (type: self-hosted)"
    Write-Host "  6. Set Browser Rendering: RDP"
    Write-Host "  7. Create a policy (e.g. allow specific emails via OTP)"
    Write-Host "  8. Copy the tunnel token"
    Write-Host "  9. Run this script on the target PC"
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
    Write-Host "  POWER MANAGEMENT:" -ForegroundColor Yellow
    Write-Host "  After installation, you can configure power settings to"
    Write-Host "  keep the PC awake and reachable. Five presets available:"
    Write-Host "  MAX, High, Balanced (recommended), Low+, and Low (reset)."
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
    Write-Host "  - RDP uses Network Level Authentication (unless Azure AD)"
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

# ===================================================================
# FUNCTIONS - AZURE AD
# ===================================================================

function Test-AzureADJoined {
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
    catch { }
    
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
    param([hashtable]$AzureInfo)
    
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
    
    # CHECK 1: NLA
    Write-Host ""
    Write-Host "  CHECK 1: Network Level Authentication (NLA)" -ForegroundColor Cyan
    Write-Host ""
    
    if (Test-NLAEnabled) {
        $issuesFound++
        Write-Host "  STATUS: NLA is ENABLED (blocking browser-based RDP)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  PROBLEM:" -ForegroundColor Yellow
        Write-Host "  NLA requires the connecting client to authenticate BEFORE"
        Write-Host "  the RDP session starts. Browser-based RDP clients cannot"
        Write-Host "  perform NLA with Azure AD credentials."
        Write-Host ""
        Write-Host "  FIX: Disable NLA (Network Level Authentication)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  WHAT THIS CHANGES:" -ForegroundColor White
        Write-Host "  - Registry: HKLM\...\RDP-Tcp\UserAuthentication = 0"
        Write-Host "  - RDP clients authenticate AFTER connecting"
        Write-Host ""
        Write-Host "  RISK: LOW - RDP port is NOT exposed to internet." -ForegroundColor White
        Write-Host "  Cloudflare Zero Trust (OTP) protects access." -ForegroundColor White
        Write-Host ""
        
        $fix = Read-Host "  Apply fix? Disable NLA [Y/N]"
        if ($fix -match '^[yY]') {
            try {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
                Write-Host "  [OK] NLA disabled." -ForegroundColor Green
                $issuesFixed++
            }
            catch { Write-Host "  [X] Failed: $_" -ForegroundColor Red }
        }
        else {
            Write-Host "  [--] Skipped. Browser RDP will likely NOT work." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  STATUS: NLA already DISABLED (good)" -ForegroundColor Green
    }
    
    # CHECK 2: PKU2U
    Write-Host ""
    Write-Host "  CHECK 2: PKU2U Protocol (Azure AD authentication)" -ForegroundColor Cyan
    Write-Host ""
    
    if (-not (Test-PKU2UEnabled)) {
        $issuesFound++
        Write-Host "  STATUS: PKU2U is DISABLED" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  PROBLEM:" -ForegroundColor Yellow
        Write-Host "  PKU2U is the protocol Windows uses to authenticate Azure AD"
        Write-Host "  users for RDP connections."
        Write-Host ""
        Write-Host "  FIX: Enable PKU2U protocol" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  WHAT THIS CHANGES:" -ForegroundColor White
        Write-Host "  - Registry: HKLM\SYSTEM\...\Lsa\Pku2u\AllowOnlineID = 1"
        Write-Host ""
        Write-Host "  RISK: VERY LOW - Microsoft's recommended setting." -ForegroundColor White
        Write-Host ""
        
        $fix = Read-Host "  Apply fix? Enable PKU2U [Y/N]"
        if ($fix -match '^[yY]') {
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Pku2u"
                if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                Set-ItemProperty -Path $regPath -Name "AllowOnlineID" -Value 1 -Type DWord -Force
                Write-Host "  [OK] PKU2U enabled." -ForegroundColor Green
                $issuesFixed++
            }
            catch { Write-Host "  [X] Failed: $_" -ForegroundColor Red }
        }
        else {
            Write-Host "  [--] Skipped." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  STATUS: PKU2U already ENABLED (good)" -ForegroundColor Green
    }
    
    # CHECK 3: Remote Desktop Users group (SID-based, language-independent)
    Write-Host ""
    Write-Host "  CHECK 3: Remote Desktop Users group" -ForegroundColor Cyan
    Write-Host ""
    
    $rdpGroupSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-555")
    $rdpGroupName = $rdpGroupSID.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    $authUsersSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")
    $authUsersName = $authUsersSID.Translate([System.Security.Principal.NTAccount]).Value
    # Get just the short name for net localgroup (without domain prefix)
    $authUsersShort = $authUsersName.Split('\')[-1]
    
    Write-Host "  Group: $rdpGroupName" -ForegroundColor Gray
    
    $rdpGroup = net localgroup "$rdpGroupName" 2>$null
    $hasAuthUsers = $rdpGroup | Select-String ([regex]::Escape($authUsersShort))
    
    if (-not $hasAuthUsers) {
        $issuesFound++
        Write-Host "  STATUS: '$authUsersShort' NOT in $rdpGroupName" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  FIX: Add '$authUsersShort' to $rdpGroupName" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  RISK: LOW - Password still required for RDP access." -ForegroundColor White
        Write-Host ""
        
        $fix = Read-Host "  Apply fix? [Y/N]"
        if ($fix -match '^[yY]') {
            try {
                # Use SID-based addition via PowerShell for language independence
                $group = [ADSI]"WinNT://./$rdpGroupName,group"
                $group.Add("WinNT://S-1-5-11")
                Write-Host "  [OK] '$authUsersShort' added to $rdpGroupName." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                # Fallback to net localgroup
                $netResult = net localgroup "$rdpGroupName" "$authUsersShort" /add 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] '$authUsersShort' added to $rdpGroupName." -ForegroundColor Green
                    $issuesFixed++
                }
                else {
                    Write-Host "  [X] Failed: $netResult" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "  [--] Skipped." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  STATUS: '$authUsersShort' is in the group (good)" -ForegroundColor Green
    }
    
    # CHECK 4: CredSSP (optional)
    Write-Host ""
    Write-Host "  CHECK 4: CredSSP Encryption Oracle (optional)" -ForegroundColor Cyan
    Write-Host ""
    
    $credSSPPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters"
    $credSSP = Get-ItemProperty -Path $credSSPPath -Name "AllowEncryptionOracle" -ErrorAction SilentlyContinue
    
    if (-not $credSSP -or $credSSP.AllowEncryptionOracle -ne 2) {
        $issuesFound++
        Write-Host "  STATUS: CredSSP not set to fallback mode" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  NOTE: This fix is OPTIONAL. Try without it first." -ForegroundColor Gray
        Write-Host "  Only apply if RDP still fails after fixes 1-3." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  FIX: Set CredSSP AllowEncryptionOracle = 2" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  RISK: MEDIUM-LOW - Allows older CredSSP as fallback." -ForegroundColor White
        Write-Host "  Connection goes through Cloudflare's encrypted tunnel." -ForegroundColor White
        Write-Host ""
        
        $fix = Read-Host "  Apply fix? [Y/N]"
        if ($fix -match '^[yY]') {
            try {
                $parentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP"
                if (-not (Test-Path $parentPath)) { New-Item -Path $parentPath -Force | Out-Null }
                if (-not (Test-Path $credSSPPath)) { New-Item -Path $credSSPPath -Force | Out-Null }
                Set-ItemProperty -Path $credSSPPath -Name "AllowEncryptionOracle" -Value 2 -Type DWord -Force
                Write-Host "  [OK] CredSSP set to fallback mode." -ForegroundColor Green
                $issuesFixed++
            }
            catch { Write-Host "  [X] Failed: $_" -ForegroundColor Red }
        }
        else {
            Write-Host "  [--] Skipped (recommended to try without)." -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  STATUS: CredSSP already configured (good)" -ForegroundColor Green
    }
    
    # SUMMARY
    Write-Host ""
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($issuesFound -eq 0) {
        Write-Host "  All Azure AD checks passed!" -ForegroundColor Green
        $Results["Azure AD Check"] = "OK"
    }
    elseif ($issuesFixed -eq $issuesFound) {
        Write-Host "  All $issuesFound issue(s) fixed!" -ForegroundColor Green
        $Results["Azure AD Check"] = "OK"
    }
    elseif ($issuesFixed -gt 0) {
        Write-Host "  Fixed $issuesFixed of $issuesFound issue(s)." -ForegroundColor Yellow
        $Results["Azure AD Check"] = "OK"
    }
    else {
        Write-Host "  $issuesFound issue(s) found but none fixed." -ForegroundColor Red
        $Results["Azure AD Check"] = "FAIL"
    }
    
    Write-Host ""
    Write-Host "  LOGIN TIP FOR AZURE AD:" -ForegroundColor Cyan
    Write-Host "  Username: AzureAD\YourName  (run 'whoami' to check)" -ForegroundColor White
    Write-Host "  Password: Microsoft account password (NOT PIN)" -ForegroundColor White
    Write-Host ""
}

# ===================================================================
# FUNCTIONS - POWER MANAGEMENT
# ===================================================================

function Test-ModernStandby {
    try {
        $lines = (powercfg /a) 2>$null
        foreach ($line in $lines) {
            if ($line -match '(?i)\b(not available|not been|inte tillg)') { break }
            if ($line -match '(?i)S0') { return $true }
        }
        return $false
    } catch { return $false }
}

function Test-IsLaptop {
    try {
        $chassis = (Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes
        $laptopTypes = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
        foreach ($c in $chassis) { if ($laptopTypes -contains $c) { return $true } }
        return [bool](Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
    } catch { return $false }
}

function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $null = & powercfg @Arguments 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Set-SleepTimeouts {
    param([int]$StandbyAC, [int]$StandbyDC, [int]$HibernateAC, [int]$HibernateDC)
    Invoke-PowerCfg @('-change', '-standby-timeout-ac',   "$StandbyAC")   | Out-Null
    Invoke-PowerCfg @('-change', '-standby-timeout-dc',   "$StandbyDC")   | Out-Null
    Invoke-PowerCfg @('-change', '-hibernate-timeout-ac', "$HibernateAC") | Out-Null
    Invoke-PowerCfg @('-change', '-hibernate-timeout-dc', "$HibernateDC") | Out-Null
}

function Set-LidAction {
    param([int]$AC, [int]$DC)
    Invoke-PowerCfg @('-setacvalueindex', 'SCHEME_CURRENT', $SUB_BUTTONS, $LID_ACTION, "$AC") | Out-Null
    Invoke-PowerCfg @('-setdcvalueindex', 'SCHEME_CURRENT', $SUB_BUTTONS, $LID_ACTION, "$DC") | Out-Null
}

function Set-StandbyNetwork {
    param([int]$AC, [int]$DC)
    Invoke-PowerCfg @('/setacvalueindex', 'scheme_current', 'sub_none', $CONN_IN_STANDBY, "$AC") | Out-Null
    Invoke-PowerCfg @('/setdcvalueindex', 'scheme_current', 'sub_none', $CONN_IN_STANDBY, "$DC") | Out-Null
}

function Disable-NicPowerSaving {
    try {
        Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {
            Disable-NetAdapterPowerManagement -Name $_.Name -NoRestart -ErrorAction SilentlyContinue
        }
        Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
            ForEach-Object {
                $iid = $_.InstanceName
                $isNic = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
                         Where-Object { $iid -like "$($_.InstanceId)*" }
                if ($isNic) {
                    $_.Enable = $false
                    Set-CimInstance -InputObject $_ -ErrorAction SilentlyContinue
                }
            }
        return $true
    } catch { return $false }
}

function Enable-NicPowerSaving {
    try {
        Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {
            Enable-NetAdapterPowerManagement -Name $_.Name -NoRestart -ErrorAction SilentlyContinue
        }
        Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
            ForEach-Object {
                $iid = $_.InstanceName
                $isNic = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
                         Where-Object { $iid -like "$($_.InstanceId)*" }
                if ($isNic) {
                    $_.Enable = $true
                    Set-CimInstance -InputObject $_ -ErrorAction SilentlyContinue
                }
            }
        return $true
    } catch { return $false }
}

function Hide-ShutdownButton {
    # NOTE: HKCU - only affects the current user, not system-wide
    if (-not (Test-Path $REG_EXPLORER_POL)) {
        New-Item -Path $REG_EXPLORER_POL -Force | Out-Null
    }
    Set-ItemProperty -Path $REG_EXPLORER_POL -Name 'NoClose' -Value 1 -Type DWord -Force
}

function Show-ShutdownButton {
    if (Test-Path $REG_EXPLORER_POL) {
        Remove-ItemProperty -Path $REG_EXPLORER_POL -Name 'NoClose' -ErrorAction SilentlyContinue
    }
}

function Save-PowerPreset {
    param([string]$Name)
    $dir = Split-Path $PM_MARKER_FILE -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Set-Content -Path $PM_MARKER_FILE -Value $Name -Force
}

function Get-PowerPreset {
    if (Test-Path $PM_MARKER_FILE) { return (Get-Content $PM_MARKER_FILE -First 1).Trim() }
    return $null
}

function Apply-PowerScheme {
    Invoke-PowerCfg @('-SetActive', 'SCHEME_CURRENT') | Out-Null
}

function Set-PresetMax {
    Write-Host "  -> Disabling sleep/hibernation (AC + battery)..."
    Set-SleepTimeouts -StandbyAC 0 -StandbyDC 0 -HibernateAC 0 -HibernateDC 0
    Write-Host "  -> Lid close: do nothing (AC + battery)..."
    Set-LidAction -AC 0 -DC 0
    Write-Host "  -> Network always on in standby (AC + battery)..."
    Set-StandbyNetwork -AC 1 -DC 1
    Write-Host "  -> Disabling NIC power saving..."
    Disable-NicPowerSaving | Out-Null
    Write-Host "  -> Hiding shutdown button in Start menu (current user only)..."
    Hide-ShutdownButton
    Apply-PowerScheme
    Save-PowerPreset 'Max'
}

function Set-PresetHigh {
    Write-Host "  -> Disabling sleep/hibernation (AC + battery)..."
    Set-SleepTimeouts -StandbyAC 0 -StandbyDC 0 -HibernateAC 0 -HibernateDC 0
    Write-Host "  -> Lid close: do nothing (AC + battery)..."
    Set-LidAction -AC 0 -DC 0
    Write-Host "  -> Network always on in standby (AC + battery)..."
    Set-StandbyNetwork -AC 1 -DC 1
    Write-Host "  -> Disabling NIC power saving..."
    Disable-NicPowerSaving | Out-Null
    Write-Host "  -> Ensuring shutdown button is visible..."
    Show-ShutdownButton
    Apply-PowerScheme
    Save-PowerPreset 'High'
}

function Set-PresetBalanced {
    Write-Host "  -> Never sleep on AC, 15 min on battery..."
    Set-SleepTimeouts -StandbyAC 0 -StandbyDC 15 -HibernateAC 0 -HibernateDC 0
    Write-Host "  -> Lid close: do nothing on AC, sleep on battery..."
    Set-LidAction -AC 0 -DC 1
    Write-Host "  -> Network in standby: on (AC), off (battery)..."
    Set-StandbyNetwork -AC 1 -DC 0
    Write-Host "  -> Disabling NIC power saving..."
    Disable-NicPowerSaving | Out-Null
    Write-Host "  -> Ensuring shutdown button is visible..."
    Show-ShutdownButton
    Apply-PowerScheme
    Save-PowerPreset 'Balanced'
}

function Set-PresetLowPlus {
    Write-Host "  -> Leaving sleep/lid settings unchanged..."
    Write-Host "  -> Network always on in standby (AC + battery)..."
    Set-StandbyNetwork -AC 1 -DC 1
    Write-Host "  -> Disabling NIC power saving..."
    Disable-NicPowerSaving | Out-Null
    Write-Host "  -> Ensuring shutdown button is visible..."
    Show-ShutdownButton
    Apply-PowerScheme
    Save-PowerPreset 'LowPlus'
}

function Set-PresetLow {
    Write-Host "  -> Restoring Windows default power schemes..."
    Invoke-PowerCfg @('-restoredefaultschemes') | Out-Null
    Write-Host "  -> Restoring NIC power saving..."
    Enable-NicPowerSaving | Out-Null
    Write-Host "  -> Ensuring shutdown button is visible..."
    Show-ShutdownButton
    Save-PowerPreset 'Low'
}

function Get-CurrentPowerState {
    <#
    .SYNOPSIS
        Reads the current power-related settings from the system.
        Returns a hashtable with boolean values for each setting.
    #>
    $state = @{
        NicPowerSaveOff    = $false
        NetworkInStandby   = $false
        SleepDisabledAC    = $false
        SleepDisabledDC    = $false
        LidDoNothingAC     = $false
        LidDoNothingDC     = $false
        HibernateDisabled  = $false
        ShutdownHidden     = $false
    }
    
    # Check NIC power saving (check if any physical adapter has power management enabled)
    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
        if ($adapters) {
            $anyPowerManaged = $false
            Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $iid = $_.InstanceName
                    $isNic = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
                             Where-Object { $iid -like "$($_.InstanceId)*" }
                    if ($isNic -and $_.Enable) { $anyPowerManaged = $true }
                }
            $state.NicPowerSaveOff = -not $anyPowerManaged
        }
    } catch { }
    
    # Check Connectivity in Standby
    try {
        $csOutput = powercfg /q SCHEME_CURRENT sub_none $CONN_IN_STANDBY 2>$null
        $acMatch = ($csOutput | Select-String 'Current AC Power Setting Index:\s+0x([0-9a-f]+)').Matches
        if ($acMatch.Count -gt 0) {
            $state.NetworkInStandby = ([Convert]::ToInt32($acMatch[0].Groups[1].Value, 16) -eq 1)
        }
    } catch { }
    
    # Check Sleep timeouts
    try {
        $sleepOutput = powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null
        $acMatch = ($sleepOutput | Select-String 'Current AC Power Setting Index:\s+0x([0-9a-f]+)').Matches
        $dcMatch = ($sleepOutput | Select-String 'Current DC Power Setting Index:\s+0x([0-9a-f]+)').Matches
        if ($acMatch.Count -gt 0) {
            $state.SleepDisabledAC = ([Convert]::ToInt32($acMatch[0].Groups[1].Value, 16) -eq 0)
        }
        if ($dcMatch.Count -gt 0) {
            $state.SleepDisabledDC = ([Convert]::ToInt32($dcMatch[0].Groups[1].Value, 16) -eq 0)
        }
    } catch { }
    
    # Check Lid action
    try {
        $lidOutput = powercfg /q SCHEME_CURRENT $SUB_BUTTONS $LID_ACTION 2>$null
        $acMatch = ($lidOutput | Select-String 'Current AC Power Setting Index:\s+0x([0-9a-f]+)').Matches
        $dcMatch = ($lidOutput | Select-String 'Current DC Power Setting Index:\s+0x([0-9a-f]+)').Matches
        if ($acMatch.Count -gt 0) {
            $state.LidDoNothingAC = ([Convert]::ToInt32($acMatch[0].Groups[1].Value, 16) -eq 0)
        }
        if ($dcMatch.Count -gt 0) {
            $state.LidDoNothingDC = ([Convert]::ToInt32($dcMatch[0].Groups[1].Value, 16) -eq 0)
        }
    } catch { }
    
    # Check Hibernate
    try {
        $hibOutput = powercfg /q SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 2>$null
        $acMatch = ($hibOutput | Select-String 'Current AC Power Setting Index:\s+0x([0-9a-f]+)').Matches
        if ($acMatch.Count -gt 0) {
            $state.HibernateDisabled = ([Convert]::ToInt32($acMatch[0].Groups[1].Value, 16) -eq 0)
        }
    } catch { }
    
    # Check shutdown button hidden
    try {
        $noClose = Get-ItemProperty -Path $REG_EXPLORER_POL -Name 'NoClose' -ErrorAction SilentlyContinue
        $state.ShutdownHidden = ($noClose -and $noClose.NoClose -eq 1)
    } catch { }
    
    return $state
}

function Show-PowerMatrix {
    <#
    .SYNOPSIS
        Displays a matrix showing current status vs all presets.
    #>
    param(
        [hashtable]$State,
        [bool]$ModernStandby,
        [bool]$IsLaptop
    )
    
    $marker = Get-PowerPreset
    
    Write-Host ""
    Write-Host "  YOUR PC" -ForegroundColor White
    Write-Host "    Type           : $(if ($IsLaptop) { 'Laptop' } else { 'Desktop' })"
    Write-Host "    Modern Standby : $(if ($ModernStandby) { 'Yes (S0)' } else { 'No (classic S3)' })"
    Write-Host "    Active preset  : $(if ($marker) { $marker } else { 'None (Windows default)' })"
    Write-Host ""
    
    # Column headers
    $col1 = 28  # Setting name width
    $col2 = 9   # Current width
    $col3 = 6   # Low+ width
    $col4 = 10  # Balanced width
    $col5 = 6   # High width
    $col6 = 5   # MAX width
    
    $header = "  {0,-$col1} {1,-$col2} {2,-$col3} {3,-$col4} {4,-$col5} {5,-$col6}" -f 'Setting', 'Current', 'Low+', 'Balanced', 'High', 'MAX'
    $divider = "  " + ("-" * ($col1 + $col2 + $col3 + $col4 + $col5 + $col6 + 5))
    
    Write-Host $header -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkGray
    
    # Helper to format check/cross/dash
    function Fmt-Cell { param([string]$Val) return $Val }
    
    # Row definitions: SettingName, CurrentBool, Low+, Balanced, High, MAX
    # Values: $true = required by preset, $false = not changed, $null = N/A
    $rows = @(
        @{
            Name = 'NIC power saving off'
            Current = $State.NicPowerSaveOff
            LowPlus = $true; Balanced = $true; High = $true; Max = $true
        },
        @{
            Name = 'Network alive in standby'
            Current = $State.NetworkInStandby
            LowPlus = $true; Balanced = $true; High = $true; Max = $true
            BalancedNote = '(AC)'
        },
        @{
            Name = 'Sleep disabled (AC)'
            Current = $State.SleepDisabledAC
            LowPlus = $false; Balanced = $true; High = $true; Max = $true
        },
        @{
            Name = 'Sleep disabled (battery)'
            Current = $State.SleepDisabledDC
            LowPlus = $false; Balanced = $false; High = $true; Max = $true
        },
        @{
            Name = 'Lid close = do nothing (AC)'
            Current = $State.LidDoNothingAC
            LowPlus = $false; Balanced = $true; High = $true; Max = $true
        },
        @{
            Name = 'Lid close = do nothing (bat)'
            Current = $State.LidDoNothingDC
            LowPlus = $false; Balanced = $false; High = $true; Max = $true
        },
        @{
            Name = 'Hibernate disabled'
            Current = $State.HibernateDisabled
            LowPlus = $false; Balanced = $true; High = $true; Max = $true
        },
        @{
            Name = 'Shutdown button hidden'
            Current = $State.ShutdownHidden
            LowPlus = $false; Balanced = $false; High = $false; Max = $true
        }
    )
    
    foreach ($row in $rows) {
        # Current column
        if ($row.Current) { $curTxt = [char]0x2713; $curColor = 'Green' }
        else { $curTxt = [char]0x2717; $curColor = 'Red' }
        
        # Preset columns
        $presetCols = @('LowPlus', 'Balanced', 'High', 'Max')
        $presetTxts = @()
        $presetColors = @()
        
        foreach ($p in $presetCols) {
            if ($row[$p] -eq $true) {
                # This preset requires this setting
                if ($row.Current) {
                    $presetTxts += [string][char]0x2713
                    $presetColors += 'Green'
                } else {
                    $presetTxts += [string][char]0x2713
                    $presetColors += 'Yellow'
                }
            } else {
                $presetTxts += '-'
                $presetColors += 'DarkGray'
            }
        }
        
        # Print row
        Write-Host -NoNewline ("  {0,-$col1} " -f $row.Name)
        Write-Host -NoNewline ("{0,-$col2} " -f $curTxt) -ForegroundColor $curColor
        Write-Host -NoNewline ("{0,-$col3} " -f $presetTxts[0]) -ForegroundColor $presetColors[0]
        Write-Host -NoNewline ("{0,-$col4} " -f $presetTxts[1]) -ForegroundColor $presetColors[1]
        Write-Host -NoNewline ("{0,-$col5} " -f $presetTxts[2]) -ForegroundColor $presetColors[2]
        Write-Host ("{0,-$col6}" -f $presetTxts[3]) -ForegroundColor $presetColors[3]
    }
    
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $([char]0x2713) = active/will be set   - = not changed by preset" -ForegroundColor Gray
    if (-not $IsLaptop) {
        Write-Host "  (Battery/lid settings shown but not relevant for desktops)" -ForegroundColor DarkGray
    }
    if (-not $ModernStandby) {
        Write-Host "  Low+ requires Modern Standby (S0) - NOT available on this PC" -ForegroundColor DarkGray
    }
    Write-Host ""
    
    # Risks section
    Write-Host "  RISKS:" -ForegroundColor Yellow
    Write-Host "    Low+     : Minimal. Only keeps network alive." -ForegroundColor Gray
    Write-Host "    Balanced : Battery drains faster on AC (no sleep). Normal on battery." -ForegroundColor Gray
    Write-Host "    High     : Battery will drain to zero if unplugged and forgotten." -ForegroundColor Gray
    Write-Host "    MAX      : Same as High + shutdown button hidden (HKCU, this user only)." -ForegroundColor Gray
    Write-Host ""
}

function Show-PowerManagement {
    <#
    .SYNOPSIS
        Interactive power management menu with status matrix.
        Can be called standalone or as part of install flow.
        Returns the chosen preset name or $null if skipped.
    #>
    param(
        [switch]$SetupStep  # If true, show compact version with skip option
    )
    
    $modernStandby = Test-ModernStandby
    $isLaptop = Test-IsLaptop
    $currentState = Get-CurrentPowerState
    
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host "  POWER MANAGEMENT - RDP Availability" -ForegroundColor Cyan
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  For reliable RDP access, the PC should stay awake and" -ForegroundColor White
    Write-Host "  keep its network connection active." -ForegroundColor White
    
    # Show the status matrix
    Show-PowerMatrix -State $currentState -ModernStandby $modernStandby -IsLaptop $isLaptop
    
    # Preset selection
    Write-Host "  Choose a preset to apply:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] MAX          - Maximum availability (never off, ever)" -ForegroundColor White
    Write-Host "  [2] High         - Always on, but shutdown button stays" -ForegroundColor White
    Write-Host "  [3] Balanced     - Always on when plugged in (RECOMMENDED)" -ForegroundColor Green
    if ($modernStandby) {
        Write-Host "  [4] Low+         - Network stays alive, sleep unchanged" -ForegroundColor White
    } else {
        Write-Host "  [4] Low+         - NOT AVAILABLE (requires Modern Standby)" -ForegroundColor DarkGray
    }
    Write-Host "  [5] Low (reset)  - Restore Windows defaults" -ForegroundColor White
    Write-Host ""
    
    if ($SetupStep) {
        Write-Host "  [Enter] Skip - make no changes" -ForegroundColor Gray
        Write-Host ""
    }
    else {
        Write-Host "  [Q] Back - make no changes" -ForegroundColor Gray
        Write-Host ""
    }
    
    do {
        if ($SetupStep) {
            $choice = Read-Host "  Choose [1-5, or Enter to skip]"
        }
        else {
            $choice = Read-Host "  Choose [1-5 or Q]"
        }
        
        # Handle skip/quit
        if ($SetupStep -and [string]::IsNullOrWhiteSpace($choice)) {
            Write-Host "  Skipped - no power changes made." -ForegroundColor Gray
            return $null
        }
        if (-not $SetupStep -and $choice -match '^[qQ]$') {
            Write-Host "  No changes made." -ForegroundColor Gray
            return $null
        }
        
        $valid = $choice -match '^[1-5]$'
        if (-not $valid) {
            Write-Host "  Invalid choice. Enter 1-5$(if ($SetupStep) { ' or press Enter to skip' } else { ' or Q' })." -ForegroundColor Yellow
        }
        if ($choice -eq '4' -and -not $modernStandby) {
            Write-Host ""
            Write-Host "  This PC does NOT support Modern Standby (S0)." -ForegroundColor Red
            Write-Host "  In classic S3 sleep, the NIC powers off completely." -ForegroundColor Yellow
            Write-Host "  Choose Balanced [3] or higher instead." -ForegroundColor Yellow
            Write-Host ""
            $valid = $false
        }
    } until ($valid)
    
    $names = @{ '1' = 'MAX'; '2' = 'High'; '3' = 'Balanced'; '4' = 'Low+'; '5' = 'Low (reset)' }
    
    Write-Host ""
    Write-Host "  Applying preset: $($names[$choice])" -ForegroundColor Cyan
    Write-Host ""
    
    switch ($choice) {
        '1' { Set-PresetMax }
        '2' { Set-PresetHigh }
        '3' { Set-PresetBalanced }
        '4' { Set-PresetLowPlus }
        '5' { Set-PresetLow }
    }
    
    Write-Host ""
    Write-Host "  [OK] Power preset '$($names[$choice])' applied." -ForegroundColor Green
    if ($choice -eq '1') {
        Write-Host "  NOTE: Log out and back in for shutdown button to hide." -ForegroundColor Yellow
    }
    Write-Host ""
    
    return $names[$choice]
}

function Reset-PowerToDefaults {
    <#
    .SYNOPSIS
        Resets power settings during uninstall. Asks user first.
    #>
    $marker = Get-PowerPreset
    if (-not $marker -or $marker -eq 'Low') {
        return  # Nothing to reset
    }
    
    Write-Host ""
    Write-Host "  Power management preset '$marker' is currently active." -ForegroundColor Yellow
    Write-Host ""
    $reset = Read-Host "  Reset power settings to Windows defaults? [Y/N]"
    if ($reset -match '^[yY]') {
        Write-Host ""
        Set-PresetLow
        Write-Host ""
        Write-Host "  [OK] Power settings restored to defaults." -ForegroundColor Green
    }
    else {
        Write-Host "  Power settings left unchanged." -ForegroundColor Gray
    }
}

# ===================================================================
# MAIN
# ===================================================================

Show-Banner

$mainChoice = Read-Host "  Press [I] to install/manage, [Q] for FAQ"
if ($mainChoice -match '^[qQ]$') {
    Show-FAQ
    $faqChoice = Read-Host "  Press [I] to install, [X] to exit"
    if ($faqChoice -ne "I") { exit 0 }
}
elseif ($mainChoice -notmatch '^[iI]$') {
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
    Write-Host "  [D] Run diagnostics (Azure AD check)"
    Write-Host "  [P] Power management settings"
    Write-Host "  [Q] Quit - do nothing"
    Write-Host ""
    $existChoice = Read-Host "  Choose [R/U/D/P/Q]"
    
    if ($existChoice -match '^[qQ]$') { Write-Host "  Cancelled."; pause; exit 0 }
    
    if ($existChoice -match '^[dD]$') {
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
    
    if ($existChoice -match '^[pP]$') {
        Show-PowerManagement
        pause; exit 0
    }
    
    if ($existChoice -match '^[uU]$') {
        Write-Host ""
        Write-Host "  Uninstalling Browser-RDP tunnel..." -ForegroundColor Yellow
        
        # Ask about power reset before removing service
        Reset-PowerToDefaults
        
        Write-Host ""
        Write-Host "  Removing service and files..." -ForegroundColor Yellow
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $SvcName | Out-Null
        Start-Sleep -Seconds 2
        if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "  [OK] Uninstalled." -ForegroundColor Green
        pause; exit 0
    }
    
    if ($existChoice -match '^[rR]$') {
        Write-Host "  Removing existing installation..." -ForegroundColor Yellow
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $SvcName | Out-Null
        Start-Sleep -Seconds 2
        if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "  [OK] Removed. Proceeding with reinstall..." -ForegroundColor Green
    }
    else {
        Write-Host "  Invalid choice." -ForegroundColor Red
        pause; exit 1
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
    
    if ($slotChoice -match '^[qQ]$') { exit 0 }
    if ($slotChoice -match '^[cC]$') {
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
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Force
    # Enable firewall rules (try both English and Swedish group names)
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Fjärrskrivbord" -ErrorAction SilentlyContinue
    # Also try by direct rule name as fallback
    Get-NetFirewallRule | Where-Object { $_.DisplayName -match "Remote Desktop|Fjärrskrivbord" } |
        Enable-NetFirewallRule -ErrorAction SilentlyContinue
    Write-Host "  [OK] Remote Desktop enabled (NLA active)." -ForegroundColor Green
    $Results["Remote Desktop"] = "OK"
}
catch {
    Write-Host "  [X] Failed to enable RDP: $_" -ForegroundColor Red
}

# --- AZURE AD CHECK ---
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
    Set-Content -Path $TokenFile -Value $ChosenToken -NoNewline -Force
    
    $binPath = "`"$ExePath`" tunnel run --token $ChosenToken"
    
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

# --- POWER MANAGEMENT (post-install step) ---
Write-Host ""
Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  OPTIONAL: Configure power management to keep this PC" -ForegroundColor Cyan
Write-Host "  awake and reachable for RDP connections." -ForegroundColor Cyan
Write-Host ""

$pmChoice = Read-Host "  Configure power settings now? [Y/N]"
if ($pmChoice -match '^[yY]') {
    $pmResult = Show-PowerManagement -SetupStep
    if ($pmResult) {
        $Results["Power Management"] = "OK"
    }
}
else {
    Write-Host "  Skipped. You can configure this later by running the script again." -ForegroundColor Gray
    Write-Host "  (Choose [P] from the manage menu)" -ForegroundColor Gray
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
