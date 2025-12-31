# 🖥️ System Monitoring Suite

A comprehensive collection of PowerShell scripts for monitoring Windows systems, designed for system administrators and IT professionals.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 📋 Table of Contents

- [Overview](#overview)
- [Scripts Included](#scripts-included)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Script Documentation](#script-documentation)
  - [System-HealthCheck.ps1](#system-healthcheckps1)
  - [Disk-SpaceMonitor.ps1](#disk-spacemonitords1)
  - [Service-Monitor.ps1](#service-monitorps1)
- [Configuration](#configuration)
- [Scheduling](#scheduling)
- [Notifications](#notifications)
- [Output & Reports](#output--reports)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

The System Monitoring Suite provides enterprise-grade monitoring capabilities for Windows environments. These scripts can be run manually, scheduled via Task Scheduler, or integrated into larger automation workflows.

### Key Features

|
 Feature 
|
 Description 
|
|
---------
|
-------------
|
|
 🔍 
**
Comprehensive Checks
**
|
 CPU, memory, disk, services, network, event logs 
|
|
 🖧 
**
Multi-Computer Support
**
|
 Monitor multiple servers from a single script 
|
|
 📊 
**
Beautiful Reports
**
|
 HTML reports with modern dark themes 
|
|
 📧 
**
Multiple Notifications
**
|
 Email, Slack, Microsoft Teams 
|
|
 🔄 
**
Auto-Remediation
**
|
 Automatic service restart, disk cleanup 
|
|
 📈 
**
Trend Analysis
**
|
 Historical data tracking and forecasting 
|
|
 📝 
**
Event Log Integration
**
|
 Write alerts to Windows Event Log 
|
|
 ⚙️ 
**
Highly Configurable
**
|
 Thresholds, profiles, and config files 
|

---

## Scripts Included

|
 Script 
|
 Purpose 
|
 Key Features 
|
|
--------
|
---------
|
--------------
|
|
`System-HealthCheck.ps1`
|
 Overall system health assessment 
|
 CPU, memory, disk, services, network, updates 
|
|
`Disk-SpaceMonitor.ps1`
|
 Disk space monitoring & management 
|
 Space tracking, large file detection, cleanup 
|
|
`Service-Monitor.ps1`
|
 Windows service monitoring 
|
 Status tracking, auto-restart, dependencies 
|

---

## Prerequisites

### System Requirements

- **Operating System**: Windows Server 2012 R2+ / Windows 8.1+
- **PowerShell**: Version 5.1 or later
- **Permissions**: Administrator privileges (required for some features)

### Required Modules

Most functionality uses built-in Windows capabilities. Optional modules:

```powershell
# For enhanced email functionality (optional)
Install-Module -Name Send-MailKitMessage -Scope CurrentUser

# For advanced HTML reports (optional)
Install-Module -Name PSWriteHTML -Scope CurrentUser
Remote Monitoring Requirements
For monitoring remote computers:

WinRM enabled on target computers
Appropriate firewall rules configured
Administrative credentials on target systems
powershell
# Enable WinRM on target computers
Enable-PSRemoting -Force

# Or via Group Policy for domain environments
# Computer Configuration > Administrative Templates > Windows Components > Windows Remote Management
Installation
Option 1: Clone Repository
bash
git clone https://github.com/yourusername/system-monitoring.git
cd system-monitoring
Option 2: Download Scripts
Download individual scripts directly and place them in your preferred location:

text
C:\Scripts\SystemMonitoring\
├── System-HealthCheck.ps1
├── Disk-SpaceMonitor.ps1
├── Service-Monitor.ps1
├── config\
│   └── services.json
└── reports\
Option 3: PowerShell Gallery (if published)
powershell
Install-Script -Name System-HealthCheck, Disk-SpaceMonitor, Service-Monitor
Set Execution Policy
powershell
# Allow script execution (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Or for current user only
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Quick Start
Basic Usage
powershell
# Run system health check on local machine
.\System-HealthCheck.ps1

# Check disk space with default thresholds
.\Disk-SpaceMonitor.ps1

# Monitor critical Windows services
.\Service-Monitor.ps1 -Profile Critical
Monitor Remote Servers
powershell
# Health check on multiple servers
.\System-HealthCheck.ps1 -ComputerName "Server01","Server02","Server03"

# Disk monitoring with reports
.\Disk-SpaceMonitor.ps1 -ComputerName "FileServer01" -OutputPath "C:\Reports"

# Service monitoring with auto-restart
.\Service-Monitor.ps1 -ComputerName "WebServer01" -Profile Web -AutoRestart
Script Documentation
System-HealthCheck.ps1
Performs comprehensive health checks on Windows systems.

Checks Performed
Check	Description	Default Threshold
CPU Usage	Current processor utilization	Warning: 80%
Memory Usage	RAM utilization	Warning: 85%
Disk Space	Storage capacity per volume	Warning: 90%
Services	Critical Windows services status	Auto-start services
Network	Connectivity to DNS/Gateway	Ping response
Event Logs	System/Application errors	<10 errors/24h
Updates	Pending Windows updates	<5 pending
Uptime	System uptime duration	Warning: >90 days
Parameters
Parameter	Type	Default	Description
-ComputerName	String[]	localhost	Target computer(s)
-CpuThreshold	Int	80	CPU warning threshold %
-MemoryThreshold	Int	85	Memory warning threshold %
-DiskThreshold	Int	90	Disk warning threshold %
-Services	String[]	(critical)	Services to monitor
-OutputPath	String	-	Report output directory
-SendEmail	Switch	-	Enable email notifications
-SmtpServer	String	-	SMTP server address
-EmailTo	String[]	-	Email recipients
-EmailFrom	String	auto	Sender email address
Examples
powershell
# Basic local check
.\System-HealthCheck.ps1

# Custom thresholds
.\System-HealthCheck.ps1 -CpuThreshold 70 -MemoryThreshold 80 -DiskThreshold 85

# Multiple servers with HTML report
.\System-HealthCheck.ps1 -ComputerName "DC01","DC02","FS01" -OutputPath "C:\Reports"

# With email notification
.\System-HealthCheck.ps1 -ComputerName "CriticalServer01" `
    -SendEmail -SmtpServer "smtp.company.com" `
    -EmailTo "it-team@company.com" -EmailFrom "monitoring@company.com"

# Custom service list
.\System-HealthCheck.ps1 -Services "W3SVC","MSSQLSERVER","CustomApp"
Output
text
╔════════════════════════════════════════════════════════════╗
║           SYSTEM HEALTH CHECK SCRIPT v1.0.0                ║
║              2024-01-15 14:30:00                           ║
╚════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Checking: SERVER01
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[i] Checking system uptime...
[✓] System uptime: 15 days, 4 hours, 32 minutes
[i] Checking CPU usage...
[✓] CPU Usage: 23.5% (Threshold: 80%)
[i] Checking memory usage...
[✓] Memory Usage: 67.2% (Threshold: 85%)
[i] Checking disk space...
[✓] Disk C: Usage: 72.3% (Threshold: 90%)
[!] Disk D: Usage: 91.5% (Threshold: 90%)
...

═══════════════════════════════════════════════════════════════
 HEALTH CHECK SUMMARY
═══════════════════════════════════════════════════════════════
 Total Checks: 24
 Healthy: 21
 Warnings: 2
 Critical: 1

 Overall Status: Warning
═══════════════════════════════════════════════════════════════
Disk-SpaceMonitor.ps1
Comprehensive disk space monitoring with cleanup recommendations.

Features
Feature	Description
Space Monitoring	Track usage across all drives
Large File Detection	Find files consuming excessive space
Folder Analysis	Identify largest directories
Cleanup Recommendations	Actionable suggestions for recovery
Auto-Cleanup	Optional automatic temp file cleanup
Trend Analysis	Track usage patterns over time
Capacity Forecasting	Predict when drives will fill
Parameters
Parameter	Type	Default	Description
-ComputerName	String[]	localhost	Target computer(s)
-WarningThreshold	Int	80	Warning threshold %
-CriticalThreshold	Int	90	Critical threshold %
-IncludeRemovable	Switch	-	Include removable drives
-IncludeNetwork	Switch	-	Include mapped drives
-FindLargeFiles	Switch	-	Scan for large files
-LargeFileSize	Int	100	Large file threshold (MB)
-TopFolders	Int	10	Number of folders to report
-OutputPath	String	-	Report output directory
-HistoryDays	Int	30	Days to retain history
-Remediate	Switch	-	Enable auto-cleanup
-SendEmail	Switch	-	Enable email notifications
-WriteEventLog	Switch	-	Write to Windows Event Log
Examples
powershell
# Basic monitoring
.\Disk-SpaceMonitor.ps1

# Custom thresholds
.\Disk-SpaceMonitor.ps1 -WarningThreshold 75 -CriticalThreshold 85

# Find large files and generate report
.\Disk-SpaceMonitor.ps1 -FindLargeFiles -LargeFileSize 500 -OutputPath "C:\Reports"

# Monitor file servers
.\Disk-SpaceMonitor.ps1 -ComputerName "FS01","FS02" `
    -WarningThreshold 70 -CriticalThreshold 80 `
    -FindLargeFiles -TopFolders 20

# With automatic cleanup (preview first)
.\Disk-SpaceMonitor.ps1 -Remediate -WhatIf

# Execute cleanup
.\Disk-SpaceMonitor.ps1 -Remediate

# Full monitoring with all features
.\Disk-SpaceMonitor.ps1 -ComputerName "Server01" `
    -FindLargeFiles -LargeFileSize 100 -TopFolders 15 `
    -OutputPath "C:\Reports\DiskMonitor" `
    -SendEmail -SmtpServer "smtp.company.com" -EmailTo "storage@company.com" `
    -WriteEventLog
Cleanup Locations
The script can identify and optionally clean:

Location	Description	Auto-Clean
User Temp	%TEMP%	✅ Yes
System Temp	%SystemRoot%\Temp	✅ Yes
Windows Update	SoftwareDistribution\Download	✅ Yes
Internet Cache	IE/Edge cache files	✅ Yes
Recycle Bin	Deleted files	✅ Yes
Windows.old	Previous installation	❌ Manual
Old Profiles	Inactive user profiles	❌ Manual
Service-Monitor.ps1
Advanced Windows service monitoring with auto-remediation.

Service Profiles
Pre-configured service groups for common scenarios:

Profile	Services Included
Critical	EventLog, RpcSs, Schedule, Winmgmt, wuauserv, BITS, etc.
Web	W3SVC, WAS, IISADMIN, HTTP, AspNet_state
SQL	MSSQLSERVER, SQLSERVERAGENT, SQLBrowser, MSDTC
Exchange	MSExchangeIS, MSExchangeTransport, MSExchangeRPC, etc.
AD	NTDS, Netlogon, DNS, DFSR, KDC, ADWS
FileServer	LanmanServer, DFSR, Dfs, SrmSvc
All	All services on the system
Parameters
Parameter	Type	Default	Description
-ComputerName	String[]	localhost	Target computer(s)
-ServiceName	String[]	-	Specific services by name
-DisplayName	String[]	-	Services by display name (wildcards)
-Profile	String	-	Service profile to use
-ConfigFile	String	-	JSON configuration file
-AutoRestart	Switch	-	Auto-restart failed services
-MaxRestartAttempts	Int	3	Max restart attempts
-RestartDelay	Int	30	Seconds between attempts
-CheckDependencies	Switch	-	Analyze dependencies
-IncludePerformance	Switch	-	Collect performance data
-ContinuousMonitor	Switch	-	Run continuously
-MonitorInterval	Int	60	Seconds between checks
-WebhookUrl	String	-	Slack/Teams webhook URL
Examples
powershell
# Monitor specific services
.\Service-Monitor.ps1 -ServiceName "Spooler","W32Time","BITS"

# Use a profile
.\Service-Monitor.ps1 -Profile Critical

# Web servers with auto-restart
.\Service-Monitor.ps1 -ComputerName "WEB01","WEB02" `
    -Profile Web -AutoRestart -MaxRestartAttempts 3

# SQL servers with dependencies
.\Service-Monitor.ps1 -ComputerName "SQL01","SQL02" `
    -Profile SQL -CheckDependencies -IncludePerformance

# Continuous monitoring
.\Service-Monitor.ps1 -Profile Critical `
    -ContinuousMonitor -MonitorInterval 120 `
    -AutoRestart -OutputPath "C:\Logs"

# With Slack notifications
.\Service-Monitor.ps1 -Profile Web -AutoRestart `
    -WebhookUrl "https://hooks.slack.com/services/REDACTED_BY_ADMIN

# With Teams notifications
.\Service-Monitor.ps1 -Profile Critical `
    -WebhookUrl "https://outlook.office.com/webhook/xxx"

# Using configuration file
.\Service-Monitor.ps1 -ConfigFile ".\config\services.json" -AutoRestart
Configuration File Format
Create services.json for custom service lists:

json
{
    "Services": [
        "W3SVC",
        "WAS",
        "MSSQLSERVER",
        "SQLAgent",
        "CustomAppService",
        "AnotherService"
    ],
    "Settings": {
        "AutoRestart": true,
        "MaxRestartAttempts": 3,
        "RestartDelay": 30,
        "CheckDependencies": true
    }
}
Configuration
Global Configuration File
Create config.json for shared settings across all scripts:

json
{
    "Email": {
        "SmtpServer": "smtp.company.com",
        "Port": 587,
        "UseSsl": true,
        "From": "monitoring@company.com",
        "To": ["it-team@company.com", "ops@company.com"],
        "Cc": ["manager@company.com"]
    },
    "Webhooks": {
        "Slack": "https://hooks.slack.com/services/REDACTED_BY_ADMIN
        "Teams": "https://outlook.office.com/webhook/xxx"
    },
    "Thresholds": {
        "Cpu": 80,
        "Memory": 85,
        "DiskWarning": 80,
        "DiskCritical": 90
    },
    "Reporting": {
        "OutputPath": "C:\\MonitoringReports",
        "RetentionDays": 30,
        "GenerateHtml": true,
        "GenerateCsv": true
    }
}
Environment Variables
Scripts can also use environment variables:

powershell
# Set environment variables
$env:MONITOR_SMTP_SERVER = "smtp.company.com"
$env:MONITOR_EMAIL_TO = "admin@company.com"
$env:MONITOR_OUTPUT_PATH = "C:\Reports"
$env:MONITOR_SLACK_WEBHOOK = "https://hooks.slack.com/..."
Scheduling
Task Scheduler Setup
Using PowerShell
powershell
# Create scheduled task for System Health Check (Daily at 6 AM)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -File `"C:\Scripts\System-HealthCheck.ps1`" -OutputPath `"C:\Reports`" -SendEmail -SmtpServer `"smtp.company.com`" -EmailTo `"admin@company.com`""

$trigger = New-ScheduledTaskTrigger -Daily -At 6:00AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName "System Health Check" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Daily system health monitoring"
powershell
# Create scheduled task for Disk Monitoring (Every 4 hours)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -File `"C:\Scripts\Disk-SpaceMonitor.ps1`" -WarningThreshold 75 -CriticalThreshold 85 -OutputPath `"C:\Reports`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration (New-TimeSpan -Days 365)

Register-ScheduledTask -TaskName "Disk Space Monitor" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
powershell
# Create scheduled task for Service Monitoring (Every 15 minutes)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -File `"C:\Scripts\Service-Monitor.ps1`" -Profile Critical -AutoRestart -OutputPath `"C:\Reports`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 365)

Register-ScheduledTask -TaskName "Service Monitor" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
Recommended Schedule
Script	Frequency	Time	Notes
System-HealthCheck.ps1	Daily	6:00 AM	Before business hours
Disk-SpaceMonitor.ps1	Every 4 hours	-	More frequent for file servers
Service-Monitor.ps1	Every 15 minutes	-	Or use continuous mode
Running as Windows Service
For continuous monitoring, consider using NSSM (Non-Sucking Service Manager):

batch
# Install NSSM
choco install nssm

# Create service for continuous service monitoring
nssm install ServiceMonitor "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
nssm set ServiceMonitor AppParameters "-ExecutionPolicy Bypass -NoProfile -File C:\Scripts\Service-Monitor.ps1 -Profile Critical -ContinuousMonitor -MonitorInterval 60 -AutoRestart"
nssm set ServiceMonitor AppDirectory "C:\Scripts"
nssm set ServiceMonitor DisplayName "PowerShell Service Monitor"
nssm set ServiceMonitor Description "Continuous Windows service monitoring"
nssm set ServiceMonitor Start SERVICE_AUTO_START

# Start the service
nssm start ServiceMonitor
Notifications
Email Configuration
powershell
# Basic email
.\System-HealthCheck.ps1 -SendEmail -SmtpServer "smtp.company.com" -EmailTo "admin@company.com"

# With authentication (modify script or use credential)
$cred = Get-Credential
.\System-HealthCheck.ps1 -SendEmail -SmtpServer "smtp.office365.com" -EmailTo "admin@company.com" -Credential $cred

# Multiple recipients
.\System-HealthCheck.ps1 -SendEmail -SmtpServer "smtp.company.com" -EmailTo "admin@company.com","ops@company.com","manager@company.com"
Slack Integration
powershell
# Get webhook URL from Slack App settings
$webhookUrl = "https://hooks.slack.com/services/REDACTED_BY_ADMIN

.\Service-Monitor.ps1 -Profile Critical -WebhookUrl $webhookUrl
Microsoft Teams Integration
powershell
# Get webhook URL from Teams channel connector
$webhookUrl = "https://outlook.office.com/webhook/xxx/IncomingWebhook/yyy/zzz"

.\Service-Monitor.ps1 -Profile Critical -WebhookUrl $webhookUrl
Output & Reports
Report Types
Type	Format	Description
HTML Report	.html	Visual dashboard with charts
CSV Export	.csv	Raw data for analysis
Log File	.log	Timestamped activity log
Event Log	Windows	Integrated Windows logging
Report Directory Structure
text
C:\Reports\
├── HealthCheck_20240115_060000.html
├── HealthCheck_20240115_060000.csv
├── DiskSpace_20240115_100000.html
├── DiskSpace_20240115_100000.csv
├── DiskSpace_History.csv
├── LargeFiles_20240115_100000.csv
├── CleanupRecommendations_20240115_100000.csv
├── ServiceMonitor_20240115_120000.html
├── ServiceMonitor_20240115_120000.csv
├── ServiceAlerts_20240115_120000.csv
├── ServicePerformance_20240115_120000.csv
└── ServiceMonitor.log
Sample HTML Report
Reports feature a modern dark theme with:

Summary cards with key metrics
Color-coded status indicators
Progress bars for usage visualization
Sortable data tables
Alert sections with severity highlighting
Responsive design for various screens
Troubleshooting
Common Issues
Script Won't Run
powershell
# Check execution policy
Get-ExecutionPolicy -List

# Set appropriate policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run with bypass
PowerShell.exe -ExecutionPolicy Bypass -File .\Script.ps1
Remote Computer Access Denied
powershell
# Enable WinRM on remote computer
Enable-PSRemoting -Force

# Check WinRM service
Get-Service WinRM

# Test connection
Test-WSMan -ComputerName RemoteServer

# Add to TrustedHosts if needed (non-domain)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "RemoteServer" -Force
Email Not Sending
powershell
# Test SMTP connection
Test-NetConnection -ComputerName smtp.company.com -Port 25

# Test with explicit credentials
Send-MailMessage -From "test@company.com" -To "admin@company.com" `
    -Subject "Test" -Body "Test email" `
    -SmtpServer "smtp.company.com" -Credential (Get-Credential)
Performance Issues
powershell
# Reduce scope
.\Disk-SpaceMonitor.ps1 -TopFolders 5  # Fewer folders
.\Service-Monitor.ps1 -Profile Critical  # Fewer services

# Skip expensive operations
.\Disk-SpaceMonitor.ps1  # Without -FindLargeFiles
.\Service-Monitor.ps1  # Without -IncludePerformance
Debug Mode
powershell
# Enable verbose output
$VerbosePreference = "Continue"
.\System-HealthCheck.ps1 -Verbose

# Enable debug output
$DebugPreference = "Continue"
.\System-HealthCheck.ps1 -Debug
Log Analysis
powershell
# View recent logs
Get-Content "C:\Reports\ServiceMonitor.log" -Tail 100

# Search for errors
Select-String -Path "C:\Reports\*.log" -Pattern "Error|Failed|Critical"

# Get alerts from CSV
Import-Csv "C:\Reports\ServiceAlerts_*.csv" | Where-Object Status -eq "Critical"
Contributing
We welcome contributions! Please follow these guidelines:

How to Contribute
Fork the repository
Create a feature branch (git checkout -b feature/AmazingFeature)
Commit your changes (git commit -m 'Add AmazingFeature')
Push to the branch (git push origin feature/AmazingFeature)
Open a Pull Request
Coding Standards
Follow PowerShell Best Practices
Include comment-based help for all functions
Add parameter validation
Include error handling
Write Pester tests for new features
Feature Requests
Open an issue with:

Clear description of the feature
Use case / business justification
Proposed implementation (if any)
License
This project is licensed under the MIT License - see the LICENSE file for details.

text
MIT License

Copyright (c) 2024 System Monitoring Suite

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
Acknowledgments
Microsoft PowerShell Team
Windows Server Documentation
Community contributors
Support
📧 Email: support@example.com
🐛 Issues: GitHub Issues
📖 Wiki: GitHub Wiki
Made with ❤️ by System Administrators, for System Administrators
