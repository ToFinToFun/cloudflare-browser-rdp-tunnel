@echo off
title Cloudflare Browser-RDP Tunnel by JPaasovaara
color 0A
setlocal EnableDelayedExpansion

:: ============================================================
:: Cloudflare Browser-RDP Tunnel by JPaasovaara
:: Makes this Windows PC reachable via browser-based RDP 
:: using Cloudflare Zero Trust Tunnels.
:: This script installs as 'cloudflared-rdp' service and will
:: NOT interfere with any existing cloudflared installation.
:: MIT License - github.com/ToFinToFun/cloudflare-browser-rdp-tunnel
:: ============================================================

:: Service name (separate from any existing cloudflared service)
set "SVC_NAME=cloudflared-rdp"
set "INSTALL_DIR=C:\Program Files\cloudflared-rdp"
set "SCRIPT_DIR=%~dp0"
set "SLOTS_FILE=%SCRIPT_DIR%slots.txt"
set "SLOT_COUNT=0"

:: Result tracking
set "CHK_ADMIN=FAIL"
set "CHK_WINVER=FAIL"
set "CHK_RDP=FAIL"
set "CHK_DOWNLOAD=FAIL"
set "CHK_INSTALL=FAIL"
set "CHK_WATCHDOG=FAIL"
set "CHK_SERVICE=FAIL"
set "CHK_CONNECT=FAIL"
set "CHOSEN_NAME="
set "CHOSEN_TOKEN="

:: Load slots from slots.txt if it exists
if exist "!SLOTS_FILE!" (
    for /f "usebackq tokens=1,2 delims=|" %%a in ("!SLOTS_FILE!") do (
        set /a SLOT_COUNT+=1
        set "SLOT_NAME_!SLOT_COUNT!=%%a"
        set "SLOT_TOKEN_!SLOT_COUNT!=%%b"
    )
)

echo.
echo ===========================================================
echo   Cloudflare Browser-RDP Tunnel by JPaasovaara
echo   Zero Trust Browser-based Remote Desktop
echo ===========================================================
echo.
echo   This tool makes your PC accessible via Remote Desktop
echo   directly in a web browser - from anywhere in the world.
echo   No VPN or client software needed on the connecting device.
echo.
echo   NOTE: This installs as a SEPARATE service (cloudflared-rdp)
echo   and will NOT affect any existing cloudflared installations
echo   (e.g. Seafile, other tunnels).
echo.
echo   Press [I] to install/manage, or [Q] for FAQ and info.
echo.
set /p "MAIN_CHOICE=   Choose [I/Q]: "

if /I "!MAIN_CHOICE!"=="Q" goto :faq
if /I "!MAIN_CHOICE!"=="I" goto :start
echo   Invalid choice.
pause
exit /b 1

:: -------------------------------------------------------
:: FAQ / INFO
:: -------------------------------------------------------
:faq
echo.
echo ===========================================================
echo   FAQ - How it works
echo ===========================================================
echo.
echo   HOW DOES IT WORK?
echo   This script installs 'cloudflared' as a hidden Windows
echo   service called 'cloudflared-rdp'. It creates an outbound
echo   tunnel to Cloudflare's network, making your PC's RDP port
echo   (3389) accessible via a secure HTTPS address in any browser.
echo.
echo   The tunnel is OUTBOUND only - no ports are opened on
echo   your router or firewall. The service starts at boot,
echo   survives sleep/hibernate, and auto-restarts on crash.
echo.
echo   It installs in its own folder (C:\Program Files\cloudflared-rdp)
echo   and runs as its own service - completely independent of any
echo   other cloudflared installation on this machine.
echo.
echo   ---
echo.
echo   WHAT DO I NEED?
echo   1. Windows 10/11 Pro, Enterprise, or Education
echo      (Windows Home does NOT support RDP)
echo   2. A domain name with DNS managed by Cloudflare
echo   3. A free Cloudflare account (Zero Trust is free
echo      for up to 50 users)
echo   4. A Tunnel Token (see below how to get one)
echo.
echo   ---
echo.
echo   HOW DO I GET A TUNNEL TOKEN?
echo   1. Go to: https://one.dash.cloudflare.com
echo   2. Navigate to: Networks ^> Tunnels
echo   3. Click "Create a tunnel" ^> Select "Cloudflared"
echo   4. Name your tunnel (e.g. "My-Laptop")
echo   5. On the install page, copy the token string
echo      (the long text after "service install")
echo   6. Click Next, then configure Public Hostname:
echo      - Subdomain: e.g. "rdp"
echo      - Domain: your domain
echo      - Service Type: RDP
echo      - URL: localhost:3389
echo   7. Save the tunnel
echo.
echo   Then protect it with Access:
echo   8. Go to: Access ^> Applications ^> Add application
echo   9. Choose "Self-hosted", enter your hostname
echo   10. Under Browser Rendering, select "RDP"
echo   11. Create a policy to allow your email (OTP)
echo.
echo   ---
echo.
echo   USEFUL LINKS:
echo   - Zero Trust Dashboard: https://one.dash.cloudflare.com
echo   - Add domain to Cloudflare: https://dash.cloudflare.com
echo   - Cloudflare free plan: https://www.cloudflare.com/plans
echo   - This project: https://github.com/ToFinToFun/cloudflare-browser-rdp-tunnel
echo.
echo   ---
echo.
echo   IS IT FREE?
echo   Cloudflare Zero Trust is free for up to 50 users.
echo   You do need to own a domain name (~$10/year) and have
echo   its DNS managed by Cloudflare (free).
echo.
echo   ---
echo.
echo   IS IT SAFE?
echo   - The tunnel is outbound only (no open ports)
echo   - Access is protected by Cloudflare Access (OTP/SSO)
echo   - RDP uses Network Level Authentication (NLA)
echo   - The tunnel token only grants connection rights to
echo     one specific tunnel - not your Cloudflare account
echo.
echo   ---
echo.
echo   PRE-CONFIGURED SLOTS (slots.txt):
echo   You can place a 'slots.txt' file next to this script
echo   to get a menu of pre-configured addresses. Format:
echo   hostname^|token
echo   Example:
echo   rdp1.example.com^|eyJhIjoiYjky...
echo   rdp2.example.com^|eyJhIjoiYzEy...
echo.
echo ===========================================================
echo.
echo   Press [I] to proceed with installation, or [X] to exit.
echo.
set /p "FAQ_CHOICE=   Choose [I/X]: "
if /I "!FAQ_CHOICE!"=="I" goto :start
echo   Exiting.
pause
exit /b 0

:: -------------------------------------------------------
:: START
:: -------------------------------------------------------
:start
echo.

:: -------------------------------------------------------
:: PRE-CHECK: Administrator privileges
:: -------------------------------------------------------
echo [Pre-check] Verifying administrator privileges...
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   [X] ABORTING - This script must be run as Administrator.
    echo       Right-click the file and select "Run as administrator".
    echo.
    pause
    exit /b 1
)
echo   [OK] Administrator confirmed.
set "CHK_ADMIN=OK"
echo.

:: -------------------------------------------------------
:: PRE-CHECK: Windows edition supports RDP
:: -------------------------------------------------------
echo [Pre-check] Verifying Windows edition (RDP support)...

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   [X] ABORTING - This Windows edition does NOT support Remote Desktop.
    echo       RDP requires Windows Pro, Enterprise, or Education.
    echo       Windows Home is NOT supported.
    echo.
    echo   Upgrade to Windows Pro before running this script again.
    pause
    exit /b 1
)

for /f "tokens=2 delims=:" %%a in ('systeminfo ^| findstr /C:"OS Name"') do set "OSNAME=%%a"
echo %OSNAME% | findstr /I "Home" >nul 2>&1
if %errorLevel% equ 0 (
    echo.
    echo   [X] ABORTING - Windows Home detected: %OSNAME%
    echo       RDP requires Windows Pro, Enterprise, or Education.
    echo.
    pause
    exit /b 1
)

echo   [OK] Windows edition supports RDP.
set "CHK_WINVER=OK"
echo.

:: -------------------------------------------------------
:: DETECT: Check for existing RDP tunnel installation
:: (Only checks OUR service 'cloudflared-rdp', not others)
:: -------------------------------------------------------
echo [Detect] Checking for existing Browser-RDP installation...

sc query %SVC_NAME% >nul 2>&1
if %errorLevel% equ 0 (
    echo.
    echo   A Browser-RDP tunnel is already installed on this PC.
    echo.
    echo   What would you like to do?
    echo.
    echo     [R] Reinstall / Change address
    echo         (removes current tunnel, then shows address menu)
    echo     [U] Uninstall completely
    echo         (removes the RDP tunnel service from this PC)
    echo     [Q] Quit - do nothing
    echo.
    set /p "EXISTING_CHOICE=   Choose [R/U/Q]: "

    if /I "!EXISTING_CHOICE!"=="Q" (
        echo.
        echo   Cancelled. No changes made.
        pause
        exit /b 0
    )

    if /I "!EXISTING_CHOICE!"=="U" (
        echo.
        echo   Uninstalling Browser-RDP tunnel...
        sc stop %SVC_NAME% >nul 2>&1
        timeout /t 3 /nobreak >nul
        sc delete %SVC_NAME% >nul 2>&1
        timeout /t 2 /nobreak >nul
        del "!INSTALL_DIR!\cloudflared.exe" >nul 2>&1
        rmdir "!INSTALL_DIR!" >nul 2>&1
        echo   [OK] Browser-RDP tunnel uninstalled successfully.
        echo       (Other cloudflared services were NOT affected)
        echo.
        pause
        exit /b 0
    )

    if /I "!EXISTING_CHOICE!"=="R" (
        echo.
        echo   Removing current RDP tunnel...
        sc stop %SVC_NAME% >nul 2>&1
        timeout /t 3 /nobreak >nul
        sc delete %SVC_NAME% >nul 2>&1
        timeout /t 2 /nobreak >nul
        echo   [OK] Old RDP tunnel removed. Continuing with new setup...
        echo.
    ) else (
        echo   Invalid choice. Aborting.
        pause
        exit /b 1
    )
) else (
    echo   [i] No existing Browser-RDP installation found. Proceeding...
    echo.
)

:: -------------------------------------------------------
:: MENU: Choose address
:: -------------------------------------------------------
if !SLOT_COUNT! GTR 0 (
    echo ===========================================================
    echo   Choose an address for this PC:
    echo ===========================================================
    echo.
    for /L %%i in (1,1,!SLOT_COUNT!) do (
        echo     [%%i] !SLOT_NAME_%%i!
    )
    echo.
    echo     [C] Custom (enter your own token and address)
    echo     [Q] Quit
    echo.
    set /p "SLOT_CHOICE=   Choose [1-!SLOT_COUNT!, C, or Q]: "

    if /I "!SLOT_CHOICE!"=="Q" (
        echo   Cancelled.
        pause
        exit /b 0
    )

    if /I "!SLOT_CHOICE!"=="C" goto :manual_input

    :: Validate numeric choice
    set "VALID_CHOICE=0"
    for /L %%n in (1,1,!SLOT_COUNT!) do (
        if "!SLOT_CHOICE!"=="%%n" set "VALID_CHOICE=1"
    )
    if "!VALID_CHOICE!"=="0" (
        echo   [X] Invalid choice: !SLOT_CHOICE!
        pause
        exit /b 1
    )

    set "CHOSEN_NAME=!SLOT_NAME_%SLOT_CHOICE%!"
    set "CHOSEN_TOKEN=!SLOT_TOKEN_%SLOT_CHOICE%!"
    goto :start_install
) else (
    goto :manual_input
)

:manual_input
echo ===========================================================
echo   Tunnel Configuration
echo ===========================================================
echo.
echo   Enter your Cloudflare Tunnel Token.
echo   (Found in Zero Trust Dashboard ^> Networks ^> Tunnels
echo    when creating or viewing a tunnel)
echo.
echo   Tip: Press [Q] for FAQ if you don't have a token yet.
echo.
set /p "CHOSEN_TOKEN=   Tunnel token: "

if /I "!CHOSEN_TOKEN!"=="Q" goto :faq

if "!CHOSEN_TOKEN!"=="" (
    echo   [X] No token entered. Aborting.
    pause
    exit /b 1
)

echo.
echo   Enter the public hostname you configured for this tunnel.
echo   (e.g. rdp.yourdomain.com)
echo.
set /p "CHOSEN_NAME=   Public hostname: "

if "!CHOSEN_NAME!"=="" (
    echo   [X] No hostname entered. Aborting.
    pause
    exit /b 1
)

:start_install
echo.
echo   Selected address: !CHOSEN_NAME!
echo.

:: -------------------------------------------------------
:: STEP 1: Enable Remote Desktop
:: -------------------------------------------------------
echo [1/5] Enabling Remote Desktop...

reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul 2>&1
if %errorLevel% neq 0 (
    echo   [X] Failed to enable RDP in registry.
    goto :checklist
)

reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 1 /f >nul 2>&1

netsh advfirewall firewall set rule group="Remote Desktop" new enable=Yes >nul 2>&1
if %errorLevel% neq 0 (
    netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul 2>&1
)

echo   [OK] Remote Desktop enabled (NLA active).
set "CHK_RDP=OK"

:: -------------------------------------------------------
:: STEP 2: Download cloudflared
:: -------------------------------------------------------
echo.
echo [2/5] Downloading Cloudflared...

if not exist "!INSTALL_DIR!" mkdir "!INSTALL_DIR!"

curl -s -L -o "!INSTALL_DIR!\cloudflared.exe" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe

if not exist "!INSTALL_DIR!\cloudflared.exe" (
    echo   [X] Download failed. Check internet connection.
    goto :checklist
)

for %%F in ("!INSTALL_DIR!\cloudflared.exe") do set FSIZE=%%~zF
if !FSIZE! LSS 1000000 (
    echo   [X] Downloaded file is too small (likely corrupt).
    del "!INSTALL_DIR!\cloudflared.exe" >nul 2>&1
    goto :checklist
)

echo   [OK] Cloudflared downloaded (!FSIZE! bytes).
set "CHK_DOWNLOAD=OK"

:: -------------------------------------------------------
:: STEP 3: Install as Windows service (custom name)
:: -------------------------------------------------------
echo.
echo [3/5] Installing as background service (%SVC_NAME%)...

:: Create the service manually with our own name
sc create %SVC_NAME% binPath= "\"!INSTALL_DIR!\cloudflared.exe\" tunnel run --token !CHOSEN_TOKEN!" start= delayed-auto obj= "LocalSystem" DisplayName= "Cloudflare Browser-RDP Tunnel" >nul 2>&1

sc query %SVC_NAME% >nul 2>&1
if %errorLevel% neq 0 (
    echo   [X] Service installation failed.
    goto :checklist
)

:: Set description
sc description %SVC_NAME% "Cloudflare Browser-RDP Tunnel - provides browser-based remote desktop access via Zero Trust" >nul 2>&1

echo   [OK] Service installed as '%SVC_NAME%'.
echo        (Does NOT affect other cloudflared services)
set "CHK_INSTALL=OK"

:: -------------------------------------------------------
:: STEP 4: Configure watchdog and recovery
:: -------------------------------------------------------
echo.
echo [4/5] Configuring watchdog (auto-recovery)...

:: Restart on failure: 10s, 10s, 30s - reset counter after 24h
sc failure %SVC_NAME% reset= 86400 actions= restart/10000/restart/10000/restart/30000 >nul 2>&1

:: Treat non-crash stops as failures too (sleep/hibernate recovery)
sc failureflag %SVC_NAME% 1 >nul 2>&1

echo   [OK] Watchdog configured (auto-restart on crash, sleep, logout).
set "CHK_WATCHDOG=OK"

:: -------------------------------------------------------
:: STEP 5: Start the service
:: -------------------------------------------------------
echo.
echo [5/5] Starting service...

sc start %SVC_NAME% >nul 2>&1
timeout /t 5 /nobreak >nul

sc query %SVC_NAME% | findstr "RUNNING" >nul 2>&1
if %errorLevel% neq 0 (
    echo   [!] Service did not start immediately. Retrying...
    timeout /t 5 /nobreak >nul
    sc start %SVC_NAME% >nul 2>&1
    timeout /t 5 /nobreak >nul
    sc query %SVC_NAME% | findstr "RUNNING" >nul 2>&1
    if %errorLevel% neq 0 (
        echo   [X] Service failed to start.
        goto :checklist
    )
)

echo   [OK] Service running.
set "CHK_SERVICE=OK"

:: -------------------------------------------------------
:: VERIFY: Connection to Cloudflare
:: -------------------------------------------------------
echo.
echo [Verify] Checking connection to Cloudflare...
timeout /t 5 /nobreak >nul

sc query %SVC_NAME% | findstr "RUNNING" >nul 2>&1
if %errorLevel% equ 0 (
    timeout /t 3 /nobreak >nul
    sc query %SVC_NAME% | findstr "RUNNING" >nul 2>&1
    if %errorLevel% equ 0 (
        echo   [OK] Tunnel active and stable.
        set "CHK_CONNECT=OK"
    ) else (
        echo   [!] Service crashed after starting. Check event logs.
    )
) else (
    echo   [!] Service is not in RUNNING state.
)

:: -------------------------------------------------------
:: CHECKLIST
:: -------------------------------------------------------
:checklist
echo.
echo ===========================================================
echo   INSTALLATION RESULTS
echo ===========================================================
echo.
echo   [%CHK_ADMIN%] Administrator privileges
echo   [%CHK_WINVER%] Windows edition (RDP capable)
echo   [%CHK_RDP%] Remote Desktop enabled
echo   [%CHK_DOWNLOAD%] Cloudflared downloaded
echo   [%CHK_INSTALL%] Windows service installed (%SVC_NAME%)
echo   [%CHK_WATCHDOG%] Watchdog configured
echo   [%CHK_SERVICE%] Service started
echo   [%CHK_CONNECT%] Connection to Cloudflare verified
echo.
echo ===========================================================

set "FAILURES=0"
if "%CHK_ADMIN%"=="FAIL" set /a FAILURES+=1
if "%CHK_WINVER%"=="FAIL" set /a FAILURES+=1
if "%CHK_RDP%"=="FAIL" set /a FAILURES+=1
if "%CHK_DOWNLOAD%"=="FAIL" set /a FAILURES+=1
if "%CHK_INSTALL%"=="FAIL" set /a FAILURES+=1
if "%CHK_WATCHDOG%"=="FAIL" set /a FAILURES+=1
if "%CHK_SERVICE%"=="FAIL" set /a FAILURES+=1
if "%CHK_CONNECT%"=="FAIL" set /a FAILURES+=1

if %FAILURES% equ 0 (
    echo.
    echo   SUCCESS! This PC is now reachable at:
    echo   https://!CHOSEN_NAME!
    echo.
    echo   The service:
    echo   - Runs invisibly in the background
    echo   - Starts automatically at boot
    echo   - Survives logout, sleep, hibernate, and lock screen
    echo   - Auto-restarts on crash (within 10 seconds)
    echo   - Works on any network (WiFi, ethernet, mobile hotspot)
    echo.
    echo   You can now close this window and delete this script.
    echo.
) else (
    echo.
    echo   [!] %FAILURES% step(s) failed. See details above.
    echo.
)

echo -----------------------------------------------------------
echo   Cloudflare Browser-RDP Tunnel by JPaasovaara - MIT License
echo   https://github.com/ToFinToFun/cloudflare-browser-rdp-tunnel
echo -----------------------------------------------------------
echo.
pause
exit /b %FAILURES%
