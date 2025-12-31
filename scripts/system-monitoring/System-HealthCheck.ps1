<#
.SYNOPSIS
    System Health Check Script for Windows Systems

.DESCRIPTION
    This script performs comprehensive health checks on Windows systems including:
    - CPU usage
    - Memory usage
    - Disk space
    - Critical services status
    - Network connectivity
    - Event log errors
    - System uptime

.PARAMETER ComputerName
    Target computer(s) to check. Defaults to localhost.

.PARAMETER CpuThreshold
    CPU usage warning threshold percentage. Default: 80

.PARAMETER MemoryThreshold
    Memory usage warning threshold percentage. Default: 85

.PARAMETER DiskThreshold
    Disk usage warning threshold percentage. Default: 90

.PARAMETER Services
    Array of critical services to monitor.

.PARAMETER OutputPath
    Path to save the HTML report. If not specified, outputs to console only.

.PARAMETER SendEmail
    Switch to enable email notifications.

.PARAMETER SmtpServer
    SMTP server for email notifications.

.PARAMETER EmailTo
    Email recipient(s) for notifications.

.PARAMETER EmailFrom
    Email sender address.

.EXAMPLE
    .\System-HealthCheck.ps1

.EXAMPLE
    .\System-HealthCheck.ps1 -ComputerName "Server01","Server02" -OutputPath "C:\Reports"

.EXAMPLE
    .\System-HealthCheck.ps1 -SendEmail -SmtpServer "smtp.company.com" -EmailTo "admin@company.com"

.NOTES
    Author: System Administrator
    Version: 1.0.0
    Date: 2024
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [ValidateRange(1, 100)]
    [int]$CpuThreshold = 80,

    [ValidateRange(1, 100)]
    [int]$MemoryThreshold = 85,

    [ValidateRange(1, 100)]
    [int]$DiskThreshold = 90,

    [string[]]$Services = @("wuauserv", "Spooler", "W32Time", "EventLog", "Dhcp", "Dnscache"),

    [string]$OutputPath,

    [switch]$SendEmail,

    [string]$SmtpServer,

    [string[]]$EmailTo,

    [string]$EmailFrom = "healthcheck@$($env:USERDNSDOMAIN)"
)

#region Configuration
$ErrorActionPreference = "Stop"
$Script:HealthCheckResults = @()
$Script:OverallHealth = "Healthy"
$Script:Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Script:ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"

# Color definitions for console output
$Colors = @{
    Healthy  = "Green"
    Warning  = "Yellow"
    Critical = "Red"
    Info     = "Cyan"
}
#endregion

#region Helper Functions
function Write-HealthLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Healthy", "Warning", "Critical")]
        [string]$Level = "Info"
    )
    
    $color = $Colors[$Level]
    $prefix = switch ($Level) {
        "Healthy"  { "[✓]" }
        "Warning"  { "[!]" }
        "Critical" { "[✗]" }
        default    { "[i]" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Get-HealthStatus {
    param(
        [double]$Value,
        [double]$WarningThreshold,
        [double]$CriticalThreshold = $null
    )
    
    if ($null -eq $CriticalThreshold) {
        $CriticalThreshold = $WarningThreshold + 10
    }
    
    if ($Value -ge $CriticalThreshold) {
        return "Critical"
    }
    elseif ($Value -ge $WarningThreshold) {
        return "Warning"
    }
    else {
        return "Healthy"
    }
}

function Update-OverallHealth {
    param([string]$Status)
    
    if ($Status -eq "Critical") {
        $Script:OverallHealth = "Critical"
    }
    elseif ($Status -eq "Warning" -and $Script:OverallHealth -ne "Critical") {
        $Script:OverallHealth = "Warning"
    }
}

function Add-CheckResult {
    param(
        [string]$Computer,
        [string]$Category,
        [string]$Check,
        [string]$Status,
        [string]$Value,
        [string]$Details
    )
    
    $Script:HealthCheckResults += [PSCustomObject]@{
        Timestamp = $Script:Timestamp
        Computer  = $Computer
        Category  = $Category
        Check     = $Check
        Status    = $Status
        Value     = $Value
        Details   = $Details
    }
    
    Update-OverallHealth -Status $Status
}
#endregion

#region Health Check Functions
function Get-SystemUptime {
    param([string]$Computer)
    
    Write-HealthLog "Checking system uptime..." -Level Info
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Computer
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeString = "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        
        $status = "Healthy"
        if ($uptime.TotalDays -gt 90) {
            $status = "Warning"
            Write-HealthLog "System uptime exceeds 90 days - consider rebooting: $uptimeString" -Level Warning
        }
        else {
            Write-HealthLog "System uptime: $uptimeString" -Level Healthy
        }
        
        Add-CheckResult -Computer $Computer -Category "System" -Check "Uptime" `
            -Status $status -Value $uptimeString -Details "Last boot: $($os.LastBootUpTime)"
        
        return @{
            Uptime     = $uptime
            LastBoot   = $os.LastBootUpTime
            Status     = $status
        }
    }
    catch {
        Write-HealthLog "Failed to get system uptime: $_" -Level Critical
        Add-CheckResult -Computer $Computer -Category "System" -Check "Uptime" `
            -Status "Critical" -Value "N/A" -Details "Error: $_"
    }
}

function Get-CpuHealth {
    param([string]$Computer)
    
    Write-HealthLog "Checking CPU usage..." -Level Info
    
    try {
        # Get CPU usage samples
        $cpuSamples = @()
        for ($i = 0; $i -lt 3; $i++) {
            $cpu = Get-CimInstance -ClassName Win32_Processor -ComputerName $Computer
            $cpuSamples += ($cpu | Measure-Object -Property LoadPercentage -Average).Average
            Start-Sleep -Milliseconds 500
        }
        
        $avgCpu = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 2)
        $status = Get-HealthStatus -Value $avgCpu -WarningThreshold $CpuThreshold
        
        $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ComputerName $Computer | Select-Object -First 1
        $details = "Processor: $($cpuInfo.Name), Cores: $($cpuInfo.NumberOfCores)"
        
        Write-HealthLog "CPU Usage: $avgCpu% (Threshold: $CpuThreshold%)" -Level $status
        
        Add-CheckResult -Computer $Computer -Category "Performance" -Check "CPU Usage" `
            -Status $status -Value "$avgCpu%" -Details $details
        
        return @{
            Usage   = $avgCpu
            Status  = $status
            Details = $details
        }
    }
    catch {
        Write-HealthLog "Failed to get CPU health: $_" -Level Critical
        Add-CheckResult -Computer $Computer -Category "Performance" -Check "CPU Usage" `
            -Status "Critical" -Value "N/A" -Details "Error: $_"
    }
}

function Get-MemoryHealth {
    param([string]$Computer)
    
    Write-HealthLog "Checking memory usage..." -Level Info
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Computer
        
        $totalMemory = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemory = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemory = [math]::Round($totalMemory - $freeMemory, 2)
        $memoryUsagePercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)
        
        $status = Get-HealthStatus -Value $memoryUsagePercent -WarningThreshold $MemoryThreshold
        $details = "Total: $totalMemory GB, Used: $usedMemory GB, Free: $freeMemory GB"
        
        Write-HealthLog "Memory Usage: $memoryUsagePercent% (Threshold: $MemoryThreshold%)" -Level $status
        
        Add-CheckResult -Computer $Computer -Category "Performance" -Check "Memory Usage" `
            -Status $status -Value "$memoryUsagePercent%" -Details $details
        
        return @{
            TotalGB     = $totalMemory
            UsedGB      = $usedMemory
            FreeGB      = $freeMemory
            UsagePercent = $memoryUsagePercent
            Status      = $status
        }
    }
    catch {
        Write-HealthLog "Failed to get memory health: $_" -Level Critical
        Add-CheckResult -Computer $Computer -Category "Performance" -Check "Memory Usage" `
            -Status "Critical" -Value "N/A" -Details "Error: $_"
    }
}

function Get-DiskHealth {
    param([string]$Computer)
    
    Write-HealthLog "Checking disk space..." -Level Info
    
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Computer -Filter "DriveType=3"
        
        $diskResults = @()
        
        foreach ($disk in $disks) {
            $totalSpace = [math]::Round($disk.Size / 1GB, 2)
            $freeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedSpace = [math]::Round($totalSpace - $freeSpace, 2)
            $usagePercent = [math]::Round(($usedSpace / $totalSpace) * 100, 2)
            
            $status = Get-HealthStatus -Value $usagePercent -WarningThreshold $DiskThreshold
            $details = "Total: $totalSpace GB, Used: $usedSpace GB, Free: $freeSpace GB"
            
            Write-HealthLog "Disk $($disk.DeviceID) Usage: $usagePercent% (Threshold: $DiskThreshold%)" -Level $status
            
            Add-CheckResult -Computer $Computer -Category "Storage" -Check "Disk $($disk.DeviceID)" `
                -Status $status -Value "$usagePercent%" -Details $details
            
            $diskResults += @{
                Drive        = $disk.DeviceID
                TotalGB      = $totalSpace
                UsedGB       = $usedSpace
                FreeGB       = $freeSpace
                UsagePercent = $usagePercent
                Status       = $status
            }
        }
        
        return $diskResults
    }
    catch {
        Write-HealthLog "Failed to get disk health: $_" -Level Critical
        Add-CheckResult -Computer $Computer -Category "Storage" -Check "Disk Space" `
            -Status "Critical" -Value "N/A" -Details "Error: $_"
    }
}

function Get-ServiceHealth {
    param(
        [string]$Computer,
        [string[]]$ServiceList
    )
    
    Write-HealthLog "Checking critical services..." -Level Info
    
    $serviceResults = @()
    
    foreach ($serviceName in $ServiceList) {
        try {
            $service = Get-Service -Name $serviceName -ComputerName $Computer -ErrorAction SilentlyContinue
            
            if ($null -eq $service) {
                Write-HealthLog "Service '$serviceName' not found" -Level Warning
                Add-CheckResult -Computer $Computer -Category "Services" -Check $serviceName `
                    -Status "Warning" -Value "Not Found" -Details "Service does not exist on this system"
                continue
            }
            
            $status = if ($service.Status -eq "Running") { "Healthy" } else { "Critical" }
            $startType = (Get-CimInstance -ClassName Win32_Service -ComputerName $Computer -Filter "Name='$serviceName'").StartMode
            
            Write-HealthLog "Service '$($service.DisplayName)': $($service.Status)" -Level $status
            
            Add-CheckResult -Computer $Computer -Category "Services" -Check $service.DisplayName `
                -Status $status -Value $service.Status -Details "Start Type: $startType"
            
            $serviceResults += @{
                Name      = $serviceName
                DisplayName = $service.DisplayName
                Status    = $service.Status
                StartType = $startType
                Health    = $status
            }
        }
        catch {
            Write-HealthLog "Failed to check service '$serviceName': $_" -Level Critical
            Add-CheckResult -Computer $Computer -Category "Services" -Check $serviceName `
                -Status "Critical" -Value "Error" -Details "Error: $_"
        }
    }
    
    return $serviceResults
}

function Get-NetworkHealth {
    param([string]$Computer)
    
    Write-HealthLog "Checking network connectivity..." -Level Info
    
    $testTargets = @(
        @{ Name = "DNS (Google)"; Address = "8.8.8.8" },
        @{ Name = "DNS (Cloudflare)"; Address = "1.1.1.1" },
        @{ Name = "Default Gateway"; Address = $null }
    )
    
    # Get default gateway
    try {
        $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
                    Select-Object -First 1).NextHop
        $testTargets[2].Address = $gateway
    }
    catch {
        $testTargets[2].Address = "N/A"
    }
    
    $networkResults = @()
    
    foreach ($target in $testTargets) {
        if ($target.Address -eq "N/A" -or $null -eq $target.Address) {
            Write-HealthLog "$($target.Name): Unable to determine address" -Level Warning
            Add-CheckResult -Computer $Computer -Category "Network" -Check $target.Name `
                -Status "Warning" -Value "Unknown" -Details "Could not determine target address"
            continue
        }
        
        try {
            $ping = Test-Connection -ComputerName $target.Address -Count 2 -Quiet -ErrorAction SilentlyContinue
            
            if ($ping) {
                $pingResult = Test-Connection -ComputerName $target.Address -Count 2 -ErrorAction SilentlyContinue
                $avgLatency = [math]::Round(($pingResult.ResponseTime | Measure-Object -Average).Average, 2)
                
                $status = if ($avgLatency -lt 100) { "Healthy" } elseif ($avgLatency -lt 200) { "Warning" } else { "Critical" }
                
                Write-HealthLog "$($target.Name) ($($target.Address)): Reachable - ${avgLatency}ms" -Level $status
                Add-CheckResult -Computer $Computer -Category "Network" -Check $target.Name `
                    -Status $status -Value "Reachable" -Details "Latency: ${avgLatency}ms"
            }
            else {
                Write-HealthLog "$($target.Name) ($($target.Address)): Unreachable" -Level Critical
                Add-CheckResult -Computer $Computer -Category "Network" -Check $target.Name `
                    -Status "Critical" -Value "Unreachable" -Details "Ping failed"
            }
            
            $networkResults += @{
                Target   = $target.Name
                Address  = $target.Address
                Reachable = $ping
                Latency  = $avgLatency
            }
        }
        catch {
            Write-HealthLog "Failed to test $($target.Name): $_" -Level Warning
        }
    }
    
    # Check network adapters
    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        $adapterCount = ($adapters | Measure-Object).Count
        
        if ($adapterCount -eq 0) {
            Write-HealthLog "No active network adapters found" -Level Critical
            Add-CheckResult -Computer $Computer -Category "Network" -Check "Network Adapters" `
                -Status "Critical" -Value "0 Active" -Details "No network adapters are connected"
        }
        else {
            Write-HealthLog "Active network adapters: $adapterCount" -Level Healthy
            $adapterNames = ($adapters | Select-Object -ExpandProperty Name) -join ", "
            Add-CheckResult -Computer $Computer -Category "Network" -Check "Network Adapters" `
                -Status "Healthy" -Value "$adapterCount Active" -Details "Adapters: $adapterNames"
        }
    }
    catch {
        Write-HealthLog "Failed to check network adapters: $_" -Level Warning
    }
    
    return $networkResults
}

function Get-EventLogHealth {
    param([string]$Computer)
    
    Write-HealthLog "Checking event logs for errors..." -Level Info
    
    $logChecks = @(
        @{ LogName = "System"; Level = 2 },      # Error
        @{ LogName = "Application"; Level = 2 }  # Error
    )
    
    $hoursToCheck = 24
    $startTime = (Get-Date).AddHours(-$hoursToCheck)
    
    foreach ($logCheck in $logChecks) {
        try {
            $events = Get-WinEvent -ComputerName $Computer -FilterHashtable @{
                LogName   = $logCheck.LogName
                Level     = $logCheck.Level
                StartTime = $startTime
            } -MaxEvents 50 -ErrorAction SilentlyContinue
            
            $errorCount = ($events | Measure-Object).Count
            
            if ($errorCount -eq 0) {
                $status = "Healthy"
                Write-HealthLog "$($logCheck.LogName) Log: No errors in last $hoursToCheck hours" -Level Healthy
            }
            elseif ($errorCount -lt 10) {
                $status = "Warning"
                Write-HealthLog "$($logCheck.LogName) Log: $errorCount errors in last $hoursToCheck hours" -Level Warning
            }
            else {
                $status = "Critical"
                Write-HealthLog "$($logCheck.LogName) Log: $errorCount errors in last $hoursToCheck hours" -Level Critical
            }
            
            $recentErrors = ""
            if ($events) {
                $recentErrors = ($events | Select-Object -First 3 | ForEach-Object { 
                    "$($_.TimeCreated): $($_.Message.Substring(0, [Math]::Min(100, $_.Message.Length)))..." 
                }) -join "; "
            }
            
            Add-CheckResult -Computer $Computer -Category "Event Logs" -Check "$($logCheck.LogName) Errors" `
                -Status $status -Value "$errorCount errors" -Details "Last $hoursToCheck hours. $recentErrors"
        }
        catch {
            if ($_.Exception.Message -notlike "*No events were found*") {
                Write-HealthLog "Failed to check $($logCheck.LogName) log: $_" -Level Warning
            }
            else {
                Write-HealthLog "$($logCheck.LogName) Log: No errors found" -Level Healthy
                Add-CheckResult -Computer $Computer -Category "Event Logs" -Check "$($logCheck.LogName) Errors" `
                    -Status "Healthy" -Value "0 errors" -Details "No errors in last $hoursToCheck hours"
            }
        }
    }
}

function Get-PendingUpdates {
    param([string]$Computer)
    
    Write-HealthLog "Checking for pending Windows updates..." -Level Info
    
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $pendingUpdates = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
        
        $updateCount = $pendingUpdates.Updates.Count
        
        if ($updateCount -eq 0) {
            Write-HealthLog "No pending updates" -Level Healthy
            Add-CheckResult -Computer $Computer -Category "Updates" -Check "Windows Updates" `
                -Status "Healthy" -Value "Up to date" -Details "No pending updates"
        }
        elseif ($updateCount -lt 5) {
            Write-HealthLog "$updateCount pending updates" -Level Warning
            Add-CheckResult -Computer $Computer -Category "Updates" -Check "Windows Updates" `
                -Status "Warning" -Value "$updateCount pending" -Details "Updates available for installation"
        }
        else {
            Write-HealthLog "$updateCount pending updates" -Level Critical
            Add-CheckResult -Computer $Computer -Category "Updates" -Check "Windows Updates" `
                -Status "Critical" -Value "$updateCount pending" -Details "Multiple updates pending installation"
        }
    }
    catch {
        Write-HealthLog "Unable to check Windows updates: $_" -Level Warning
        Add-CheckResult -Computer $Computer -Category "Updates" -Check "Windows Updates" `
            -Status "Warning" -Value "Unknown" -Details "Unable to query Windows Update: $_"
    }
}
#endregion

#region Report Generation
function New-HtmlReport {
    param(
        [array]$Results,
        [string]$OverallStatus
    )
    
    $statusColor = switch ($OverallStatus) {
        "Healthy"  { "#28a745" }
        "Warning"  { "#ffc107" }
        "Critical" { "#dc3545" }
        default    { "#6c757d" }
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Health Check Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px 10px 0 0; }
        .header h1 { font-size: 2em; margin-bottom: 10px; }
        .header p { opacity: 0.9; }
        .overall-status { display: inline-block; padding: 10px 20px; border-radius: 5px; font-weight: bold; margin-top: 15px; background: $statusColor; }
        .content { background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #667eea; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f8f9fa; }
        .status-healthy { color: #28a745; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        .status-critical { color: #dc3545; font-weight: bold; }
        .category-header { background: #f8f9fa; font-weight: bold; }
        .footer { text-align: center; margin-top: 20px; color: #6c757d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ System Health Check Report</h1>
            <p>Generated: $Script:Timestamp</p>
            <div class="overall-status">Overall Status: $OverallStatus</div>
        </div>
        <div class="content">
            <table>
                <thead>
                    <tr>
                        <th>Computer</th>
                        <th>Category</th>
                        <th>Check</th>
                        <th>Status</th>
                        <th>Value</th>
                        <th>Details</th>
                    </tr>
                </thead>
                <tbody>
"@
    
    foreach ($result in $Results) {
        $statusClass = "status-$($result.Status.ToLower())"
        $html += @"
                    <tr>
                        <td>$($result.Computer)</td>
                        <td>$($result.Category)</td>
                        <td>$($result.Check)</td>
                        <td class="$statusClass">$($result.Status)</td>
                        <td>$($result.Value)</td>
                        <td>$($result.Details)</td>
                    </tr>
"@
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        <div class="footer">
            <p>System Health Check Script v1.0.0 | Report generated by PowerShell</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

function Send-EmailReport {
    param(
        [string]$HtmlContent,
        [string]$Subject
    )
    
    if (-not $SendEmail) { return }
    
    if ([string]::IsNullOrEmpty($SmtpServer) -or [string]::IsNullOrEmpty($EmailTo)) {
        Write-HealthLog "Email configuration incomplete. Skipping email notification." -Level Warning
        return
    }
    
    try {
        $mailParams = @{
            From       = $EmailFrom
            To         = $EmailTo
            Subject    = $Subject
            Body       = $HtmlContent
            BodyAsHtml = $true
            SmtpServer = $SmtpServer
        }
        
        Send-MailMessage @mailParams
        Write-HealthLog "Email report sent successfully to $($EmailTo -join ', ')" -Level Healthy
    }
    catch {
        Write-HealthLog "Failed to send email report: $_" -Level Warning
    }
}
#endregion

#region Main Execution
function Start-HealthCheck {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           SYSTEM HEALTH CHECK SCRIPT v1.0.0                ║" -ForegroundColor Cyan
    Write-Host "║              $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($computer in $ComputerName) {
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host " Checking: $computer" -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host ""
        
        # Test connectivity first
        if ($computer -ne $env:COMPUTERNAME) {
            if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
                Write-HealthLog "Unable to connect to $computer" -Level Critical
                Add-CheckResult -Computer $computer -Category "Connectivity" -Check "Host Reachable" `
                    -Status "Critical" -Value "Unreachable" -Details "Cannot ping host"
                continue
            }
        }
        
        # Run all health checks
        Get-SystemUptime -Computer $computer
        Get-CpuHealth -Computer $computer
        Get-MemoryHealth -Computer $computer
        Get-DiskHealth -Computer $computer
        Get-ServiceHealth -Computer $computer -ServiceList $Services
        Get-NetworkHealth -Computer $computer
        Get-EventLogHealth -Computer $computer
        
        # Only check updates on local machine
        if ($computer -eq $env:COMPUTERNAME) {
            Get-PendingUpdates -Computer $computer
        }
        
        Write-Host ""
    }
    
    # Generate summary
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " HEALTH CHECK SUMMARY" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $healthyCount = ($Script:HealthCheckResults | Where-Object { $_.Status -eq "Healthy" }).Count
    $warningCount = ($Script:HealthCheckResults | Where-Object { $_.Status -eq "Warning" }).Count
    $criticalCount = ($Script:HealthCheckResults | Where-Object { $_.Status -eq "Critical" }).Count
    
    Write-Host " Total Checks: $($Script:HealthCheckResults.Count)" -ForegroundColor White
    Write-Host " Healthy: $healthyCount" -ForegroundColor Green
    Write-Host " Warnings: $warningCount" -ForegroundColor Yellow
    Write-Host " Critical: $criticalCount" -ForegroundColor Red
    Write-Host ""
    Write-Host " Overall Status: $Script:OverallHealth" -ForegroundColor $(if ($Script:OverallHealth -eq "Healthy") { "Green" } elseif ($Script:OverallHealth -eq "Warning") { "Yellow" } else { "Red" })
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    # Generate HTML report if output path specified
    if (-not [string]::IsNullOrEmpty($OutputPath)) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        $reportFile = Join-Path $OutputPath "HealthCheck_$Script:ReportDate.html"
        $htmlReport = New-HtmlReport -Results $Script:HealthCheckResults -OverallStatus $Script:OverallHealth
        $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
        
        Write-Host ""
        Write-HealthLog "HTML Report saved to: $reportFile" -Level Info
        
        # Also save CSV
        $csvFile = Join-Path $OutputPath "HealthCheck_$Script:ReportDate.csv"
        $Script:HealthCheckResults | Export-Csv -Path $csvFile -NoTypeInformation
        Write-HealthLog "CSV Report saved to: $csvFile" -Level Info
    }
    
    # Send email if configured
    if ($SendEmail) {
        $htmlReport = New-HtmlReport -Results $Script:HealthCheckResults -OverallStatus $Script:OverallHealth
        $emailSubject = "[$Script:OverallHealth] System Health Check Report - $($ComputerName -join ', ')"
        Send-EmailReport -HtmlContent $htmlReport -Subject $emailSubject
    }
    
    # Return results object
    return [PSCustomObject]@{
        Timestamp     = $Script:Timestamp
        OverallHealth = $Script:OverallHealth
        HealthyCount  = $healthyCount
        WarningCount  = $warningCount
        CriticalCount = $criticalCount
        Results       = $Script:HealthCheckResults
    }
}

# Execute
Start-HealthCheck
#endregion
