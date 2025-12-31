@echo off
title Apex Network Stack Reset Tool
color 1f

:: -----------------------------------------------------------------------------
:: CHECK FOR ADMIN PRIVILEGES
:: -----------------------------------------------------------------------------
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [SUCCESS] Running as Administrator.
) else (
    echo [ERROR] This script must be run as Administrator.
    echo Right-click and select "Run as administrator".
    pause
    exit
)

echo.
echo ===============================================================================
echo   WARNING: THIS WILL RESET ALL NETWORK ADAPTERS AND REBOOT THE SYSTEM
echo ===============================================================================
echo.
echo Steps to be performed:
echo 1. Reset Winsock (Socket API)
echo 2. Reset TCP/IP Stack
echo 3. Release current IP
echo 4. Flush DNS Cache
echo 5. Renew IP Address
echo 6. Register DNS
echo.
pause

:: -----------------------------------------------------------------------------
:: EXECUTION
:: -----------------------------------------------------------------------------

echo.
echo [1/6] Resetting Winsock Catalog...
netsh winsock reset catalog

echo.
echo [2/6] Resetting TCP/IP Stack...
netsh int ip reset reset.log

echo.
echo [3/6] Releasing IP Address...
ipconfig /release

echo.
echo [4/6] Flushing DNS Cache...
ipconfig /flushdns

echo.
echo [5/6] Renewing IP Address...
ipconfig /renew

echo.
echo [6/6] Registering DNS...
ipconfig /registerdns

:: -----------------------------------------------------------------------------
:: COMPLETION
:: -----------------------------------------------------------------------------

echo.
echo ===============================================================================
echo   RESET COMPLETE - REBOOT REQUIRED
echo ===============================================================================
echo.
echo Windows requires a reboot for the Winsock reset to take effect.
set /p reboot="Would you like to reboot now? (y/n): "

if /i "%reboot%"=="y" (
    shutdown /r /t 0
) else (
    echo Please reboot manually as soon as possible.
    pause
)
Strategic Value
Efficiency: Instead of walking a user through opening CMD and typing netsh int ip reset (and dealing with typos), you send them this file. They double-click, hit "Y", and the problem is usually solved.

Standardization: It ensures no step is skipped. Often, admins forget winsock reset or registerdns. This script guarantees a full stack flush.

Quick Add Command
Run this in your terminal to create the file instantly:

Bash

cat << 'EOF' > SysAdmin-Toolkit/tools/network-reset.bat
@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Run as Admin.
    pause
    exit
)
echo Resetting Network Stack...
netsh winsock reset
netsh int ip reset
ipconfig /release
ipconfig /flushdns
ipconfig /renew
echo Done. Reboot required.
pause
EOF
