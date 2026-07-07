@echo off
title Cloudflare RDP Tool
color 0A
setlocal EnableDelayedExpansion

:: ============================================================
:: Cloudflare RDP Tool
:: Makes this Windows PC reachable via browser-based RDP 
:: using Cloudflare Zero Trust Tunnels.
:: ============================================================

set "CHK_ADMIN=FAIL"
set "CHK_WINVER=FAIL"
set "CHK_RDP=FAIL"
set "CHK_DOWNLOAD=FAIL"
set "CHK_INSTALL=FAIL"
set "CHK_WATCHDOG=FAIL"
set "CHK_SERVICE=FAIL"
set "CHK_CONNECT=FAIL"
set "INSTALL_DIR=C:\Program Files\cloudflared"

echo.
echo ===========================================================
echo   Cloudflare RDP Tool - Installer
echo   Zero Trust Browser-based Remote Desktop
echo ===========================================================
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
:: DETECT: Check for existing installation
:: -------------------------------------------------------
echo [Detect] Checking for existing Cloudflared installation...

sc query cloudflared >nul 2>&1
if %errorLevel% equ 0 (
    echo.
    echo   An existing Cloudflared tunnel is already installed on this PC.
    echo.
    echo   What would you like to do?
    echo.
    echo     [S] Switch to a different tunnel (reinstall)
    echo     [U] Uninstall completely (remove tunnel service)
    echo     [Q] Quit (do nothing)
    echo.
    set /p "EXISTING_CHOICE=   Choose [S/U/Q]: "

    if /I "!EXISTING_CHOICE!"=="Q" (
        echo.
        echo   Cancelled. No changes made.
        pause
        exit /b 0
    )

    if /I "!EXISTING_CHOICE!"=="U" (
        echo.
        echo   Uninstalling Cloudflared...
        sc stop cloudflared >nul 2>&1
        timeout /t 3 /nobreak >nul
        "!INSTALL_DIR!\cloudflared.exe" service uninstall >nul 2>&1
        timeout /t 2 /nobreak >nul
        del "!INSTALL_DIR!\cloudflared.exe" >nul 2>&1
        rmdir "!INSTALL_DIR!" >nul 2>&1
        echo   [OK] Cloudflared uninstalled successfully.
        echo.
        pause
        exit /b 0
    )

    if /I "!EXISTING_CHOICE!"=="S" (
        echo.
        echo   Removing existing installation first...
        sc stop cloudflared >nul 2>&1
        timeout /t 3 /nobreak >nul
        "!INSTALL_DIR!\cloudflared.exe" service uninstall >nul 2>&1
        timeout /t 2 /nobreak >nul
        echo   [OK] Old installation removed. Continuing with new setup...
        echo.
    ) else (
        echo   Invalid choice. Aborting.
        pause
        exit /b 1
    )
) else (
    echo   [i] No existing installation found. Proceeding...
    echo.
)

:: -------------------------------------------------------
:: INPUT: Token and Address
:: -------------------------------------------------------
echo ===========================================================
echo   Tunnel Configuration
echo ===========================================================
echo.
echo   Please enter your Cloudflare Tunnel Token.
echo   (You can find this in the Zero Trust Dashboard when 
echo   creating a new tunnel)
echo.
set /p "CHOSEN_TOKEN=   Tunnel token: "
echo.
echo   Please enter the public hostname you configured for this tunnel.
echo   (e.g. rdp.yourdomain.com)
echo.
set /p "CHOSEN_NAME=   Public Hostname: "
echo.

if "!CHOSEN_TOKEN!"=="" (
    echo   [X] No token entered. Aborting.
    pause
    exit /b 1
)
if "!CHOSEN_NAME!"=="" (
    echo   [X] No hostname entered. Aborting.
    pause
    exit /b 1
)

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
:: STEP 3: Install as Windows service
:: -------------------------------------------------------
echo.
echo [3/5] Installing as background service...

"!INSTALL_DIR!\cloudflared.exe" service install !CHOSEN_TOKEN!

sc query cloudflared >nul 2>&1
if %errorLevel% neq 0 (
    echo   [X] Service installation failed.
    goto :checklist
)

echo   [OK] Service installed.
set "CHK_INSTALL=OK"

:: -------------------------------------------------------
:: STEP 4: Configure watchdog and recovery
:: -------------------------------------------------------
echo.
echo [4/5] Configuring watchdog (auto-recovery)...

:: Delayed auto-start (waits for network stack)
sc config cloudflared start= delayed-auto >nul 2>&1

:: Restart on failure: 10s, 10s, 30s - reset counter after 24h
sc failure cloudflared reset= 86400 actions= restart/10000/restart/10000/restart/30000 >nul 2>&1

:: Treat non-crash stops as failures too (sleep/hibernate recovery)
sc failureflag cloudflared 1 >nul 2>&1

echo   [OK] Watchdog configured (auto-restart on crash, sleep, logout).
set "CHK_WATCHDOG=OK"

:: -------------------------------------------------------
:: STEP 5: Start the service
:: -------------------------------------------------------
echo.
echo [5/5] Starting service...

sc start cloudflared >nul 2>&1
timeout /t 5 /nobreak >nul

sc query cloudflared | findstr "RUNNING" >nul 2>&1
if %errorLevel% neq 0 (
    echo   [!] Service did not start immediately. Retrying...
    timeout /t 5 /nobreak >nul
    sc start cloudflared >nul 2>&1
    timeout /t 5 /nobreak >nul
    sc query cloudflared | findstr "RUNNING" >nul 2>&1
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

sc query cloudflared | findstr "RUNNING" >nul 2>&1
if %errorLevel% equ 0 (
    timeout /t 3 /nobreak >nul
    sc query cloudflared | findstr "RUNNING" >nul 2>&1
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
echo   [%CHK_INSTALL%] Windows service installed
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
    echo   You can now close this window.
    echo.
) else (
    echo.
    echo   [!] %FAILURES% step(s) failed. See details above.
    echo.
)

echo ===========================================================
echo.
pause
exit /b %FAILURES%
