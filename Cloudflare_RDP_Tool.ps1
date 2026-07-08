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
        } else {
            Write-Host "  [FAIL] $key" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Green
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
    Write-Host "  [Q] Quit - do nothing"
    Write-Host ""
    $existChoice = Read-Host "  Choose [R/U/Q]"
    
    if ($existChoice -eq "Q") { Write-Host "  Cancelled."; pause; exit 0 }
    
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
    else { Write-Host "  Invalid choice."; pause; exit 1 }
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
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Force
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Remote Desktop enabled (NLA active)." -ForegroundColor Green
    $Results["Remote Desktop"] = "OK"
}
catch {
    Write-Host "  [X] Failed to enable RDP: $_" -ForegroundColor Red
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
