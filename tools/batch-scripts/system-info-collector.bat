@echo off
setlocal EnableDelayedExpansion
title Apex SysAdmin Toolkit - System Info Collector

:: -----------------------------------------------------------------------------
:: Apex System Info Collector (Windows)
:: Scope: CPU, RAM, Disk, Network, and Top Processes.
:: Usage: Run as Administrator
:: -----------------------------------------------------------------------------

cls
echo ===============================================================================
echo    APEX SYSTEM INFO COLLECTOR - %DATE% %TIME%
echo ===============================================================================
echo.

:: 1. OS & SYSTEM UPTIME
echo [SYSTEM DETAILS]
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Boot Time" /C:"Total Physical Memory"
echo.

:: 2. DISK USAGE (Free Space Check)
echo [DISK USAGE STATUS]
echo (Size and FreeSpace in Bytes)
wmic logicaldisk get Caption,VolumeName,Size,FreeSpace | findstr /v "Size" | findstr ":"
echo.

:: 3. NETWORK INTERFACES
echo [ACTIVE IP ADDRESSES]
ipconfig | findstr "IPv4"
echo.

:: 4. LISTENING PORTS (Quick Scan)
echo [TOP 10 LISTENING PORTS]
netstat -ano | findstr "LISTENING" | findstr "TCP"
:: Limiting output is hard in pure batch, showing all listening TCP
echo.

:: 5. TOP 5 MEMORY CONSUMING PROCESSES
:: Batch is bad at math/sorting. We call PowerShell for this specific heavy lifting.
echo [TOP 5 MEMORY HOGS]
powershell -NoProfile -Command "Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 | Format-Table Id,Name,@{Name='Memory(MB)';Expression={[math]::Round($_.WorkingSet / 1MB, 2)}} -AutoSize"

echo.
echo ===============================================================================
echo    REPORT COMPLETE
echo ===============================================================================
echo.
pause
Implementation Strategy
Hybrid Approach: While standard batch files are great for portability, they are terrible at sorting data (like finding the top 5 processes). This script uses a "Hybrid" technique where it calls powershell -Command just for that specific task. This gives you the speed of Batch with the power of PowerShell, without requiring a .ps1 execution policy change.

WMIC Filters: The wmic command used for disk space filters out empty variables to ensure the output is clean.

Quick Add Command
Run this in your terminal to append this script to your toolkit instantly:

Bash

cat << 'EOF' > SysAdmin-Toolkit/tools/system-info-collector.bat
@echo off
setlocal
echo [SYSTEM REPORT]
systeminfo | findstr /B /C:"OS Name" /C:"Total Physical Memory"
echo.
echo [DISK SPACE]
wmic logicaldisk get Caption,FreeSpace,Size
echo.
echo [TOP PROCESSES]
powershell "Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5"
pause
EOF
