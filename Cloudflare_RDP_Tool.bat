@echo off
:: Launcher for Cloudflare Browser-RDP Tunnel installer
:: This runs the PowerShell script with admin privileges
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Cloudflare_RDP_Tool.ps1"
pause
