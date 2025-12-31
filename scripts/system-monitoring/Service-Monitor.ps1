<#
.SYNOPSIS
    Service Monitor - Comprehensive Windows service monitoring and management solution.

.DESCRIPTION
    This script provides comprehensive service monitoring capabilities including:
    - Multi-computer service monitoring
    - Automatic service restart on failure
    - Service dependency analysis
    - Service group profiles (Web, Database, etc.)
    - Performance metrics collection
    - Startup type validation
    - Service account auditing
    - Historical status tracking
    - HTML/CSV reporting
    - Email notifications
    - Event log integration
    - Slack/Teams webhook support

.PARAMETER ComputerName
    Target computer(s) to monitor. Defaults to localhost.

.PARAMETER ServiceName
    Specific service(s) to monitor by name.

.PARAMETER DisplayName
    Service(s) to monitor by display name (supports wildcards).

.PARAMETER Profile
    Predefined service profile to monitor (Critical, Web, Database, Exchange, SQL, Custom).

.PARAMETER ConfigFile
    Path to JSON configuration file with service definitions.

.PARAMETER AutoRestart
    Automatically restart stopped services that should be running.

.PARAMETER MaxRestartAttempts
    Maximum restart attempts per service. Default: 3

.PARAMETER RestartDelay
    Seconds to wait between restart attempts. Default: 30

.PARAMETER CheckDependencies
    Include service dependency analysis.

.PARAMETER IncludePerformance
    Collect service process performance metrics.

.PARAMETER OutputPath
    Path to save reports and logs.

.PARAMETER SendEmail
    Enable email notifications.

.PARAMETER SmtpServer
    SMTP server for email notifications.

.PARAMETER EmailTo
    Email recipient(s) for notifications.

.PARAMETER EmailFrom
    Email sender address.

.PARAMETER WebhookUrl
    Slack/Teams webhook URL for notifications.

.PARAMETER WriteEventLog
    Write alerts to Windows Event Log.

.PARAMETER ContinuousMonitor
    Run in continuous monitoring mode.

.PARAMETER MonitorInterval
    Seconds between checks in continuous mode. Default: 60

.EXAMPLE
    .\Service-Monitor.ps1 -ServiceName "Spooler","W32Time"

.EXAMPLE
    .\Service-Monitor.ps1 -Profile Web -AutoRestart -SendEmail

.EXAMPLE
    .\Service-Monitor.ps1 -ComputerName "Server01","Server02" -ConfigFile ".\services.json"

.NOTES
    Author: System Administrator
    Version: 1.0.0
    Date: 2024
    Requires: PowerShell 5.1 or later, Administrator privileges for restart capability
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "ByName")]
param(
    [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias("CN", "Server", "Host")]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(ParameterSetName = "ByName")]
    [Alias("Name")]
    [string[]]$ServiceName,

    [Parameter(ParameterSetName = "ByDisplayName")]
    [string[]]$DisplayName,

    [Parameter(ParameterSetName = "ByProfile")]
    [ValidateSet("Critical", "Web", "Database", "Exchange", "SQL", "AD", "FileServer", "All", "Custom")]
    [string]$Profile,

    [Parameter(ParameterSetName = "ByConfig")]
    [ValidateScript({ Test-Path $_ })]
    [string]$ConfigFile,

    [switch]$AutoRestart,

    [ValidateRange(1, 10)]
    [int]$MaxRestartAttempts = 3,

    [ValidateRange(5, 300)]
    [int]$RestartDelay = 30,

    [switch]$CheckDependencies,

    [switch]$IncludePerformance,

    [string]$OutputPath,

    [switch]$SendEmail,

    [string]$SmtpServer,

    [string[]]$EmailTo,

    [string]$EmailFrom = "servicemonitor@$($env:USERDNSDOMAIN)",

    [string]$WebhookUrl,

    [switch]$WriteEventLog,

    [switch]$ContinuousMonitor,

    [ValidateRange(10, 3600)]
    [int]$MonitorInterval = 60
)

#region Initialization
$ErrorActionPreference = "Continue"
$Script:Timestamp = Get-Date
$Script:ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:ServiceResults = @()
$Script:Alerts = @()
$Script:RestartAttempts = @{}
$Script:PerformanceData = @()
$Script:DependencyMap = @{}

# Service profiles - predefined service groups
$Script:ServiceProfiles = @{
    Critical = @(
        "EventLog", "RpcSs", "DcomLaunch", "LSM", "Schedule", "Winmgmt",
        "wuauserv", "BITS", "CryptSvc", "Dhcp", "Dnscache", "LanmanServer",
        "LanmanWorkstation", "Netlogon", "PlugPlay", "SamSs", "W32Time"
    )
    Web = @(
        "W3SVC", "WAS", "IISADMIN", "HTTP", "NetTcpPortSharing",
        "AspNet_state", "WMSvc"
    )
    Database = @(
        "MSSQLSERVER", "SQLSERVERAGENT", "MSSQLServerOLAPService",
        "SQLBrowser", "MSDTC", "SQLWriter"
    )
    SQL = @(
        "MSSQLSERVER", "SQLSERVERAGENT", "MSSQLServerOLAPService",
        "SQLBrowser", "MSDTC", "SQLWriter", "MSSQLFDLauncher",
        "SSASTELEMETRY", "SSISTELEMETRY", "SSRSTELEMETRY"
    )
    Exchange = @(
        "MSExchangeADTopology", "MSExchangeIS", "MSExchangeMailboxAssistants",
        "MSExchangeServiceHost", "MSExchangeTransport", "MSExchangeMailSubmission",
        "MSExchangeRPC", "MSExchangeAB", "MSExchangeUM"
    )
    AD = @(
        "NTDS", "Netlogon", "DNS", "DFSR", "KDC", "IsmServ", "Kdc",
        "W32Time", "CertSvc", "ADWS"
    )
    FileServer = @(
        "LanmanServer", "Browser", "DFSR", "Dfs", "SrmSvc", "NfsService",
        "fdPHost", "FDResPub"
    )
    All = @()  # Will monitor all services
}

# Console formatting
$Script:Colors = @{
    Header   = "Cyan"
    Success  = "Green"
    Warning  = "Yellow"
    Error    = "Red"
    Info     = "White"
    Muted    = "DarkGray"
    Running  = "Green"
    Stopped  = "Red"
    Degraded = "Yellow"
}

# Status icons
$Script:StatusIcons = @{
    Running       = "[✓]"
    Stopped       = "[✗]"
    StartPending  = "[►]"
    StopPending   = "[■]"
    Paused        = "[║]"
    PausePending  = "[│]"
    ContinuePending = "[»]"
    Unknown       = "[?]"
}
#endregion

#region Helper Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Header", "Muted")]
        [string]$Level = "Info",
        [switch]$NoNewline,
        [switch]$NoTimestamp
    )
    
    $color = $Script:Colors[$Level]
    $prefix = switch ($Level) {
        "Success" { "[✓]" }
        "Warning" { "[!]" }
        "Error"   { "[✗]" }
        "Header"  { "[*]" }
        default   { "[i]" }
    }
    
    $timestamp = if (-not $NoTimestamp) { "$(Get-Date -Format 'HH:mm:ss') " } else { "" }
    
    if ($Level -eq "Header") {
        Write-Host ""
        Write-Host "$timestamp$prefix $Message" -ForegroundColor $color
        Write-Host ("=" * ($Message.Length + $timestamp.Length + 4)) -ForegroundColor $color
    }
    else {
        $params = @{
            Object = "$timestamp$prefix $Message"
            ForegroundColor = $color
            NoNewline = $NoNewline
        }
        Write-Host @params
    }
    
    # Log to file if output path specified
    if (-not [string]::IsNullOrEmpty($OutputPath)) {
        $logFile = Join-Path $OutputPath "ServiceMonitor.log"
        "$timestamp[$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    }
}

function Get-ServiceStatusColor {
    param([string]$Status)
    
    switch ($Status) {
        "Running"         { return $Script:Colors.Running }
        "Stopped"         { return $Script:Colors.Stopped }
        "StartPending"    { return $Script:Colors.Warning }
        "StopPending"     { return $Script:Colors.Warning }
        "Paused"          { return $Script:Colors.Warning }
        default           { return $Script:Colors.Muted }
    }
}

function Get-StatusIcon {
    param([string]$Status)
    
    if ($Script:StatusIcons.ContainsKey($Status)) {
        return $Script:StatusIcons[$Status]
    }
    return $Script:StatusIcons.Unknown
}

function Test-RemoteAccess {
    param([string]$Computer)
    
    if ($Computer -eq $env:COMPUTERNAME -or $Computer -eq "localhost" -or $Computer -eq ".") {
        return $true
    }
    
    try {
        return Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction Stop
    }
    catch {
        return $false
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-EventLogEntry {
    param(
        [string]$Message,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$EntryType = "Information",
        [int]$EventId = 2000
    )
    
    if (-not $WriteEventLog) { return }
    
    $logName = "Application"
    $source = "ServiceMonitor"
    
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            [System.Diagnostics.EventLog]::CreateEventSource($source, $logName)
        }
        
        Write-EventLog -LogName $logName -Source $source -EventId $EventId -EntryType $EntryType -Message $Message
    }
    catch {
        Write-Log "Failed to write to Event Log: $_" -Level Warning
    }
}

function Send-WebhookNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Color = "warning"
    )
    
    if ([string]::IsNullOrEmpty($WebhookUrl)) { return }
    
    try {
        # Detect webhook type (Slack vs Teams)
        if ($WebhookUrl -match "hooks.slack.com") {
            # Slack format
            $colorCode = switch ($Color) {
                "good"    { "good" }
                "warning" { "warning" }
                "danger"  { "danger" }
                default   { "#808080" }
            }
            
            $payload = @{
                attachments = @(
                    @{
                        fallback = "$Title - $Message"
                        color = $colorCode
                        title = $Title
                        text = $Message
                        ts = [int][double]::Parse((Get-Date -UFormat %s))
                    }
                )
            } | ConvertTo-Json -Depth 5
        }
        else {
            # Teams format
            $themeColor = switch ($Color) {
                "good"    { "28a745" }
                "warning" { "ffc107" }
                "danger"  { "dc3545" }
                default   { "808080" }
            }
            
            $payload = @{
                "@type" = "MessageCard"
                "@context" = "http://schema.org/extensions"
                themeColor = $themeColor
                summary = $Title
                sections = @(
                    @{
                        activityTitle = $Title
                        facts = @(
                            @{
                                name = "Details"
                                value = $Message
                            }
                            @{
                                name = "Time"
                                value = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                            }
                        )
                        markdown = $true
                    }
                )
            } | ConvertTo-Json -Depth 5
        }
        
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType "application/json" | Out-Null
        Write-Log "Webhook notification sent" -Level Success
    }
    catch {
        Write-Log "Failed to send webhook notification: $_" -Level Warning
    }
}

function Format-TimeSpan {
    param([TimeSpan]$TimeSpan)
    
    if ($TimeSpan.TotalDays -ge 1) {
        return "{0:N0}d {1:N0}h {2:N0}m" -f $TimeSpan.Days, $TimeSpan.Hours, $TimeSpan.Minutes
    }
    elseif ($TimeSpan.TotalHours -ge 1) {
        return "{0:N0}h {1:N0}m" -f $TimeSpan.Hours, $TimeSpan.Minutes
    }
    else {
        return "{0:N0}m {1:N0}s" -f $TimeSpan.Minutes, $TimeSpan.Seconds
    }
}
#endregion

#region Service Functions
function Get-TargetServices {
    param([string]$Computer)
    
    $targetServices = @()
    
    try {
        # Get all services from the computer
        $allServices = Get-Service -ComputerName $Computer -ErrorAction Stop
        
        switch ($PSCmdlet.ParameterSetName) {
            "ByName" {
                if ($ServiceName) {
                    $targetServices = $allServices | Where-Object { $ServiceName -contains $_.ServiceName }
                }
                else {
                    # Default to critical services if nothing specified
                    $targetServices = $allServices | Where-Object { $Script:ServiceProfiles.Critical -contains $_.ServiceName }
                }
            }
            "ByDisplayName" {
                foreach ($pattern in $DisplayName) {
                    $targetServices += $allServices | Where-Object { $_.DisplayName -like $pattern }
                }
            }
            "ByProfile" {
                if ($Profile -eq "All") {
                    $targetServices = $allServices
                }
                elseif ($Profile -eq "Custom") {
                    # Require config file for custom
                    Write-Log "Custom profile requires -ConfigFile parameter" -Level Warning
                    return $null
                }
                else {
                    $profileServices = $Script:ServiceProfiles[$Profile]
                    $targetServices = $allServices | Where-Object { $profileServices -contains $_.ServiceName }
                }
            }
            "ByConfig" {
                $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
                if ($config.Services) {
                    $targetServices = $allServices | Where-Object { $config.Services -contains $_.ServiceName }
                }
            }
            default {
                $targetServices = $allServices | Where-Object { $Script:ServiceProfiles.Critical -contains $_.ServiceName }
            }
        }
        
        return $targetServices | Sort-Object DisplayName
    }
    catch {
        Write-Log "Failed to get services from $Computer : $_" -Level Error
        return $null
    }
}

function Get-ServiceDetails {
    param(
        [string]$Computer,
        [string]$ServiceName
    )
    
    try {
        $wmiService = Get-CimInstance -ClassName Win32_Service -ComputerName $Computer -Filter "Name='$ServiceName'" -ErrorAction Stop
        
        return [PSCustomObject]@{
            ProcessId       = $wmiService.ProcessId
            StartMode       = $wmiService.StartMode
            StartName       = $wmiService.StartName
            PathName        = $wmiService.PathName
            Description     = $wmiService.Description
            DelayedAutoStart = $wmiService.DelayedAutoStart
            ExitCode        = $wmiService.ExitCode
            ServiceSpecificExitCode = $wmiService.ServiceSpecificExitCode
        }
    }
    catch {
        return $null
    }
}

function Get-ServicePerformance {
    param(
        [string]$Computer,
        [int]$ProcessId
    )
    
    if ($ProcessId -eq 0) { return $null }
    
    try {
        $process = Get-CimInstance -ClassName Win32_Process -ComputerName $Computer -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
        
        if ($null -eq $process) { return $null }
        
        $perfData = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -ComputerName $Computer -Filter "IDProcess=$ProcessId" -ErrorAction SilentlyContinue
        
        return [PSCustomObject]@{
            ProcessId         = $ProcessId
            ProcessName       = $process.Name
            WorkingSetMB      = [math]::Round($process.WorkingSetSize / 1MB, 2)
            PrivateBytesMB    = [math]::Round($process.PrivatePageCount / 1MB, 2)
            CPUPercent        = if ($perfData) { $perfData.PercentProcessorTime } else { 0 }
            ThreadCount       = $process.ThreadCount
            HandleCount       = $process.HandleCount
            CreationDate      = $process.CreationDate
        }
    }
    catch {
        return $null
    }
}

function Get-ServiceDependencies {
    param(
        [string]$Computer,
        [string]$ServiceName
    )
    
    try {
        $service = Get-Service -ComputerName $Computer -Name $ServiceName -ErrorAction Stop
        
        $dependencies = @{
            DependsOn = @()
            DependedOnBy = @()
        }
        
        # Services this service depends on
        foreach ($dep in $service.ServicesDependedOn) {
            $depService = Get-Service -ComputerName $Computer -Name $dep.ServiceName -ErrorAction SilentlyContinue
            $dependencies.DependsOn += [PSCustomObject]@{
                ServiceName = $dep.ServiceName
                DisplayName = $dep.DisplayName
                Status = $dep.Status
                IsRunning = ($dep.Status -eq "Running")
            }
        }
        
        # Services that depend on this service
        foreach ($dep in $service.DependentServices) {
            $dependencies.DependedOnBy += [PSCustomObject]@{
                ServiceName = $dep.ServiceName
                DisplayName = $dep.DisplayName
                Status = $dep.Status
                IsRunning = ($dep.Status -eq "Running")
            }
        }
        
        return $dependencies
    }
    catch {
        return $null
    }
}

function Test-ServiceHealth {
    param([PSCustomObject]$ServiceInfo)
    
    $health = "Healthy"
    $issues = @()
    
    # Check if service is running (for Auto/Manual start types)
    if ($ServiceInfo.Status -ne "Running") {
        if ($ServiceInfo.StartMode -eq "Auto" -or $ServiceInfo.StartMode -eq "Automatic") {
            $health = "Critical"
            $issues += "Auto-start service is not running"
        }
        elseif ($ServiceInfo.StartMode -eq "Manual") {
            $health = "Warning"
            $issues += "Manual service is stopped"
        }
    }
    
    # Check for high memory usage (if performance data available)
    if ($ServiceInfo.Performance -and $ServiceInfo.Performance.WorkingSetMB -gt 1024) {
        if ($health -ne "Critical") { $health = "Warning" }
        $issues += "High memory usage: $($ServiceInfo.Performance.WorkingSetMB) MB"
    }
    
    # Check for high CPU usage
    if ($ServiceInfo.Performance -and $ServiceInfo.Performance.CPUPercent -gt 80) {
        if ($health -ne "Critical") { $health = "Warning" }
        $issues += "High CPU usage: $($ServiceInfo.Performance.CPUPercent)%"
    }
    
    # Check for dependency issues
    if ($ServiceInfo.Dependencies) {
        $stoppedDeps = $ServiceInfo.Dependencies.DependsOn | Where-Object { -not $_.IsRunning }
        if ($stoppedDeps) {
            $health = "Warning"
            $issues += "Dependency not running: $($stoppedDeps.ServiceName -join ', ')"
        }
    }
    
    return [PSCustomObject]@{
        Health = $health
        Issues = $issues
    }
}

function Restart-FailedService {
    param(
        [string]$Computer,
        [string]$ServiceName,
        [string]$DisplayName
    )
    
    if (-not $AutoRestart) { return $false }
    
    # Check restart attempts
    $attemptKey = "$Computer`:$ServiceName"
    if (-not $Script:RestartAttempts.ContainsKey($attemptKey)) {
        $Script:RestartAttempts[$attemptKey] = @{
            Count = 0
            LastAttempt = $null
        }
    }
    
    # Reset counter if last attempt was more than 1 hour ago
    if ($Script:RestartAttempts[$attemptKey].LastAttempt -and 
        ((Get-Date) - $Script:RestartAttempts[$attemptKey].LastAttempt).TotalHours -gt 1) {
        $Script:RestartAttempts[$attemptKey].Count = 0
    }
    
    # Check if max attempts reached
    if ($Script:RestartAttempts[$attemptKey].Count -ge $MaxRestartAttempts) {
        Write-Log "Max restart attempts ($MaxRestartAttempts) reached for $DisplayName on $Computer" -Level Warning
        return $false
    }
    
    $Script:RestartAttempts[$attemptKey].Count++
    $Script:RestartAttempts[$attemptKey].LastAttempt = Get-Date
    $attempt = $Script:RestartAttempts[$attemptKey].Count
    
    Write-Log "Attempting to restart $DisplayName on $Computer (Attempt $attempt/$MaxRestartAttempts)..." -Level Warning
    
    if ($PSCmdlet.ShouldProcess("$DisplayName on $Computer", "Restart Service")) {
        try {
            # Start the service
            if ($Computer -eq $env:COMPUTERNAME) {
                Start-Service -Name $ServiceName -ErrorAction Stop
            }
            else {
                Get-Service -ComputerName $Computer -Name $ServiceName | Start-Service -ErrorAction Stop
            }
            
            # Wait for service to start
            $timeout = 60
            $elapsed = 0
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $svc = Get-Service -ComputerName $Computer -Name $ServiceName -ErrorAction SilentlyContinue
            } while ($svc.Status -ne "Running" -and $elapsed -lt $timeout)
            
            if ($svc.Status -eq "Running") {
                Write-Log "Successfully restarted $DisplayName on $Computer" -Level Success
                
                # Create alert
                $Script:Alerts += [PSCustomObject]@{
                    Timestamp = Get-Date
                    Computer = $Computer
                    Service = $DisplayName
                    Type = "Restart"
                    Status = "Success"
                    Message = "Service was automatically restarted (Attempt $attempt)"
                }
                
                # Send notification
                Send-WebhookNotification -Title "Service Restarted" `
                    -Message "$DisplayName on $Computer was automatically restarted" -Color "good"
                
                Write-EventLogEntry -Message "Service '$DisplayName' on $Computer was automatically restarted" `
                    -EntryType Information -EventId 2001
                
                return $true
            }
            else {
                throw "Service did not start within timeout period"
            }
        }
        catch {
            Write-Log "Failed to restart $DisplayName on $Computer : $_" -Level Error
            
            $Script:Alerts += [PSCustomObject]@{
                Timestamp = Get-Date
                Computer = $Computer
                Service = $DisplayName
                Type = "Restart"
                Status = "Failed"
                Message = "Restart attempt $attempt failed: $_"
            }
            
            Send-WebhookNotification -Title "Service Restart Failed" `
                -Message "Failed to restart $DisplayName on $Computer : $_" -Color "danger"
            
            Write-EventLogEntry -Message "Failed to restart service '$DisplayName' on $Computer : $_" `
                -EntryType Error -EventId 2002
            
            return $false
        }
    }
    
    return $false
}

function Get-ServiceStatus {
    param([string]$Computer)
    
    Write-Log "Analyzing services on $Computer..." -Level Info
    
    $services = Get-TargetServices -Computer $Computer
    
    if ($null -eq $services -or $services.Count -eq 0) {
        Write-Log "No target services found on $Computer" -Level Warning
        return @()
    }
    
    $results = @()
    $total = $services.Count
    $current = 0
    
    foreach ($service in $services) {
        $current++
        Write-Progress -Activity "Checking services on $Computer" -Status $service.DisplayName -PercentComplete (($current / $total) * 100)
        
        # Get detailed service information
        $details = Get-ServiceDetails -Computer $Computer -ServiceName $service.ServiceName
        
        # Get performance data if requested
        $perfData = $null
        if ($IncludePerformance -and $details -and $details.ProcessId -gt 0) {
            $perfData = Get-ServicePerformance -Computer $Computer -ProcessId $details.ProcessId
            if ($perfData) {
                $Script:PerformanceData += [PSCustomObject]@{
                    Timestamp = $Script:Timestamp
                    Computer = $Computer
                    ServiceName = $service.ServiceName
                    DisplayName = $service.DisplayName
                    ProcessId = $perfData.ProcessId
                    WorkingSetMB = $perfData.WorkingSetMB
                    CPUPercent = $perfData.CPUPercent
                    ThreadCount = $perfData.ThreadCount
                    HandleCount = $perfData.HandleCount
                }
            }
        }
        
        # Get dependencies if requested
        $dependencies = $null
        if ($CheckDependencies) {
            $dependencies = Get-ServiceDependencies -Computer $Computer -ServiceName $service.ServiceName
            $Script:DependencyMap["$Computer`:$($service.ServiceName)"] = $dependencies
        }
        
        # Build service info object
        $serviceInfo = [PSCustomObject]@{
            Timestamp       = $Script:Timestamp
            ComputerName    = $Computer
            ServiceName     = $service.ServiceName
            DisplayName     = $service.DisplayName
            Status          = $service.Status.ToString()
            StartMode       = if ($details) { $details.StartMode } else { "Unknown" }
            StartName       = if ($details) { $details.StartName } else { "Unknown" }
            ProcessId       = if ($details) { $details.ProcessId } else { 0 }
            PathName        = if ($details) { $details.PathName } else { "" }
            Dependencies    = $dependencies
            Performance     = $perfData
            Health          = $null
            Issues          = @()
        }
        
        # Evaluate health
        $healthCheck = Test-ServiceHealth -ServiceInfo $serviceInfo
        $serviceInfo.Health = $healthCheck.Health
        $serviceInfo.Issues = $healthCheck.Issues
        
        $results += $serviceInfo
        $Script:ServiceResults += $serviceInfo
        
        # Create alert for critical issues
        if ($healthCheck.Health -eq "Critical") {
            $Script:Alerts += [PSCustomObject]@{
                Timestamp = Get-Date
                Computer = $Computer
                Service = $service.DisplayName
                Type = "Status"
                Status = "Critical"
                Message = "Service is not running. Issues: $($healthCheck.Issues -join '; ')"
            }
            
            # Attempt restart if enabled
            if ($AutoRestart -and $details.StartMode -in @("Auto", "Automatic")) {
                Restart-FailedService -Computer $Computer -ServiceName $service.ServiceName -DisplayName $service.DisplayName
            }
        }
    }
    
    Write-Progress -Activity "Checking services on $Computer" -Completed
    
    return $results
}

function Show-ServiceStatus {
    param([array]$Services)
    
    if ($null -eq $Services -or $Services.Count -eq 0) { return }
    
    $grouped = $Services | Group-Object Health | Sort-Object { 
        switch ($_.Name) { "Critical" { 0 } "Warning" { 1 } "Healthy" { 2 } default { 3 } }
    }
    
    foreach ($group in $grouped) {
        $headerColor = switch ($group.Name) {
            "Critical" { "Red" }
            "Warning"  { "Yellow" }
            "Healthy"  { "Green" }
            default    { "White" }
        }
        
        Write-Host ""
        Write-Host "  $($group.Name.ToUpper()) ($($group.Count))" -ForegroundColor $headerColor
        Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
        
        foreach ($service in $group.Group) {
            $icon = Get-StatusIcon -Status $service.Status
            $statusColor = Get-ServiceStatusColor -Status $service.Status
            
            Write-Host "  $icon " -NoNewline -ForegroundColor $statusColor
            Write-Host "$($service.DisplayName)" -NoNewline -ForegroundColor White
            Write-Host " [$($service.Status)]" -NoNewline -ForegroundColor $statusColor
            Write-Host " ($($service.StartMode))" -ForegroundColor DarkGray
            
            if ($service.Issues.Count -gt 0) {
                foreach ($issue in $service.Issues) {
                    Write-Host "      └─ $issue" -ForegroundColor DarkGray
                }
            }
            
            if ($IncludePerformance -and $service.Performance) {
                $perf = $service.Performance
                Write-Host "      └─ Memory: $($perf.WorkingSetMB) MB | CPU: $($perf.CPUPercent)% | Threads: $($perf.ThreadCount)" -ForegroundColor DarkGray
            }
        }
    }
}
#endregion

#region Report Generation
function New-HtmlReport {
    $statusSummary = @{
        Running  = ($Script:ServiceResults | Where-Object { $_.Status -eq "Running" }).Count
        Stopped  = ($Script:ServiceResults | Where-Object { $_.Status -eq "Stopped" }).Count
        Other    = ($Script:ServiceResults | Where-Object { $_.Status -notin @("Running", "Stopped") }).Count
        Healthy  = ($Script:ServiceResults | Where-Object { $_.Health -eq "Healthy" }).Count
        Warning  = ($Script:ServiceResults | Where-Object { $_.Health -eq "Warning" }).Count
        Critical = ($Script:ServiceResults | Where-Object { $_.Health -eq "Critical" }).Count
    }
    
    $overallStatus = if ($statusSummary.Critical -gt 0) { "Critical" }
                     elseif ($statusSummary.Warning -gt 0) { "Warning" }
                     else { "Healthy" }
    
    $statusColor = switch ($overallStatus) {
        "Critical" { "#dc3545" }
        "Warning"  { "#ffc107" }
        default    { "#28a745" }
    }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Service Monitor Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0d1117; color: #c9d1d9; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #238636 0%, #1f6feb 100%); padding: 30px; border-radius: 15px; margin-bottom: 20px; color: white; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; }
        .status-badge { display: inline-block; padding: 8px 20px; border-radius: 20px; font-weight: bold; margin-top: 15px; background: $statusColor; color: white; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .stat-card { background: #161b22; border: 1px solid #30363d; border-radius: 10px; padding: 20px; text-align: center; }
        .stat-card h3 { color: #8b949e; font-size: 0.8em; margin-bottom: 8px; text-transform: uppercase; }
        .stat-card .value { font-size: 2.5em; font-weight: bold; }
        .stat-card.running .value { color: #238636; }
        .stat-card.stopped .value { color: #f85149; }
        .stat-card.warning .value { color: #d29922; }
        .stat-card.critical .value { color: #f85149; }
        .stat-card.healthy .value { color: #238636; }
        .section { background: #161b22; border: 1px solid #30363d; border-radius: 10px; padding: 20px; margin-bottom: 20px; }
        .section h2 { color: #58a6ff; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid #30363d; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #21262d; color: #c9d1d9; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 12px; border-bottom: 1px solid #30363d; }
        tr:hover { background: #1f2428; }
        .status-running { color: #238636; }
        .status-stopped { color: #f85149; }
        .status-paused { color: #d29922; }
        .health-healthy { background: #238636; color: white; padding: 4px 8px; border-radius: 4px; font-size: 0.85em; }
        .health-warning { background: #d29922; color: black; padding: 4px 8px; border-radius: 4px; font-size: 0.85em; }
        .health-critical { background: #f85149; color: white; padding: 4px 8px; border-radius: 4px; font-size: 0.85em; }
        .alert-box { padding: 15px; border-radius: 8px; margin-bottom: 10px; border-left: 4px solid; }
        .alert-critical { background: rgba(248, 81, 73, 0.1); border-color: #f85149; }
        .alert-warning { background: rgba(210, 153, 34, 0.1); border-color: #d29922; }
        .alert-success { background: rgba(35, 134, 54, 0.1); border-color: #238636; }
        .issues-list { font-size: 0.85em; color: #8b949e; margin-top: 5px; }
        .footer { text-align: center; padding: 20px; color: #8b949e; }
        .perf-bar { height: 8px; background: #30363d; border-radius: 4px; overflow: hidden; }
        .perf-fill { height: 100%; background: #238636; }
        .perf-fill.warning { background: #d29922; }
        .perf-fill.critical { background: #f85149; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚙️ Service Monitor Report</h1>
            <p>Generated: $($Script:Timestamp.ToString("yyyy-MM-dd HH:mm:ss"))</p>
            <p>Computers: $($ComputerName -join ", ")</p>
            <span class="status-badge">Overall: $overallStatus</span>
        </div>
        
        <div class="grid">
            <div class="stat-card running">
                <h3>Running</h3>
                <div class="value">$($statusSummary.Running)</div>
            </div>
            <div class="stat-card stopped">
                <h3>Stopped</h3>
                <div class="value">$($statusSummary.Stopped)</div>
            </div>
            <div class="stat-card healthy">
                <h3>Healthy</h3>
                <div class="value">$($statusSummary.Healthy)</div>
            </div>
            <div class="stat-card warning">
                <h3>Warning</h3>
                <div class="value">$($statusSummary.Warning)</div>
            </div>
            <div class="stat-card critical">
                <h3>Critical</h3>
                <div class="value">$($statusSummary.Critical)</div>
            </div>
            <div class="stat-card">
                <h3>Total</h3>
                <div class="value" style="color: #58a6ff;">$($Script:ServiceResults.Count)</div>
            </div>
        </div>
"@

    # Alerts Section
    if ($Script:Alerts.Count -gt 0) {
        $html += @"
        <div class="section">
            <h2>🚨 Alerts & Events</h2>
"@
        foreach ($alert in $Script:Alerts | Sort-Object Timestamp -Descending | Select-Object -First 20) {
            $alertClass = switch ($alert.Status) {
                "Critical" { "alert-critical" }
                "Failed"   { "alert-critical" }
                "Success"  { "alert-success" }
                default    { "alert-warning" }
            }
            $html += @"
            <div class="alert-box $alertClass">
                <strong>$($alert.Type) - $($alert.Status)</strong><br>
                <small>$($alert.Timestamp.ToString("HH:mm:ss")) | $($alert.Computer) | $($alert.Service)</small><br>
                $($alert.Message)
            </div>
"@
        }
        $html += "</div>"
    }

    # Services Table
    $html += @"
        <div class="section">
            <h2>📋 Service Status Details</h2>
            <table>
                <thead>
                    <tr>
                        <th>Computer</th>
                        <th>Service</th>
                        <th>Status</th>
                        <th>Start Mode</th>
                        <th>Account</th>
                        <th>Health</th>
                        <th>Issues</th>
                    </tr>
                </thead>
                <tbody>
"@
    
    foreach ($svc in ($Script:ServiceResults | Sort-Object @{E={switch($_.Health){"Critical"{0}"Warning"{1}default{2}}}}, DisplayName)) {
        $statusClass = "status-$($svc.Status.ToLower())"
        $healthClass = "health-$($svc.Health.ToLower())"
        $issuesText = if ($svc.Issues.Count -gt 0) { $svc.Issues -join "<br>" } else { "-" }
        
        $html += @"
                    <tr>
                        <td>$($svc.ComputerName)</td>
                        <td><strong>$($svc.DisplayName)</strong><br><small style="color:#8b949e;">$($svc.ServiceName)</small></td>
                        <td class="$statusClass"><strong>$($svc.Status)</strong></td>
                        <td>$($svc.StartMode)</td>
                        <td style="font-size:0.85em;">$($svc.StartName)</td>
                        <td><span class="$healthClass">$($svc.Health)</span></td>
                        <td class="issues-list">$issuesText</td>
                    </tr>
"@
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
"@

    # Performance Section
    if ($Script:PerformanceData.Count -gt 0) {
        $html += @"
        <div class="section">
            <h2>📊 Service Performance</h2>
            <table>
                <thead>
                    <tr>
                        <th>Computer</th>
                        <th>Service</th>
                        <th>PID</th>
                        <th>Memory (MB)</th>
                        <th>CPU %</th>
                        <th>Threads</th>
                        <th>Handles</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($perf in ($Script:PerformanceData | Sort-Object WorkingSetMB -Descending)) {
            $memClass = if ($perf.WorkingSetMB -gt 1024) { "critical" } elseif ($perf.WorkingSetMB -gt 512) { "warning" } else { "" }
            $cpuClass = if ($perf.CPUPercent -gt 80) { "critical" } elseif ($perf.CPUPercent -gt 50) { "warning" } else { "" }
            
            $html += @"
                    <tr>
                        <td>$($perf.Computer)</td>
                        <td>$($perf.DisplayName)</td>
                        <td>$($perf.ProcessId)</td>
                        <td>
                            <div class="perf-bar"><div class="perf-fill $memClass" style="width: $([math]::Min($perf.WorkingSetMB / 20, 100))%;"></div></div>
                            $($perf.WorkingSetMB)
                        </td>
                        <td>
                            <div class="perf-bar"><div class="perf-fill $cpuClass" style="width: $($perf.CPUPercent)%;"></div></div>
                            $($perf.CPUPercent)%
                        </td>
                        <td>$($perf.ThreadCount)</td>
                        <td>$($perf.HandleCount)</td>
                    </tr>
"@
        }
        $html += "</tbody></table></div>"
    }

    # Footer
    $html += @"
        <div class="footer">
            <p>Service Monitor v1.0.0 | Generated by PowerShell</p>
            <p>Auto-Restart: $(if($AutoRestart){"Enabled"}else{"Disabled"}) | 
               Dependencies: $(if($CheckDependencies){"Checked"}else{"Skipped"}) |
               Performance: $(if($IncludePerformance){"Collected"}else{"Skipped"})</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

function Send-EmailReport {
    if (-not $SendEmail) { return }
    
    if ([string]::IsNullOrEmpty($SmtpServer) -or $null -eq $EmailTo) {
        Write-Log "Email configuration incomplete" -Level Warning
        return
    }
    
    $criticalCount = ($Script:ServiceResults | Where-Object { $_.Health -eq "Critical" }).Count
    $warningCount = ($Script:ServiceResults | Where-Object { $_.Health -eq "Warning" }).Count
    
    $statusText = if ($criticalCount -gt 0) { "CRITICAL" } elseif ($warningCount -gt 0) { "WARNING" } else { "OK" }
    $priority = if ($criticalCount -gt 0) { "High" } else { "Normal" }
    
    $subject = "[$statusText] Service Monitor - $($ComputerName -join ', ') - $criticalCount Critical, $warningCount Warning"
    
    try {
        $htmlReport = New-HtmlReport
        
        Send-MailMessage -From $EmailFrom -To $EmailTo -Subject $subject `
            -Body $htmlReport -BodyAsHtml -SmtpServer $SmtpServer -Priority $priority
        
        Write-Log "Email report sent to: $($EmailTo -join ', ')" -Level Success
    }
    catch {
        Write-Log "Failed to send email: $_" -Level Error
    }
}

function Export-Reports {
    if ([string]::IsNullOrEmpty($OutputPath)) { return }
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    
    # HTML Report
    $htmlFile = Join-Path $OutputPath "ServiceMonitor_$Script:ReportDate.html"
    New-HtmlReport | Out-File -FilePath $htmlFile -Encoding UTF8
    Write-Log "HTML Report: $htmlFile" -Level Success
    
    # CSV Report
    $csvFile = Join-Path $OutputPath "ServiceMonitor_$Script:ReportDate.csv"
    $Script:ServiceResults | Select-Object Timestamp, ComputerName, ServiceName, DisplayName, Status, StartMode, StartName, Health, @{N='Issues';E={$_.Issues -join '; '}} |
        Export-Csv -Path $csvFile -NoTypeInformation
    Write-Log "CSV Report: $csvFile" -Level Success
    
    # Alerts CSV
    if ($Script:Alerts.Count -gt 0) {
        $alertsFile = Join-Path $OutputPath "ServiceAlerts_$Script:ReportDate.csv"
        $Script:Alerts | Export-Csv -Path $alertsFile -NoTypeInformation
        Write-Log "Alerts Report: $alertsFile" -Level Success
    }
    
    # Performance CSV
    if ($Script:PerformanceData.Count -gt 0) {
        $perfFile = Join-Path $OutputPath "ServicePerformance_$Script:ReportDate.csv"
        $Script:PerformanceData | Export-Csv -Path $perfFile -NoTypeInformation
        Write-Log "Performance Report: $perfFile" -Level Success
    }
}
#endregion

#region Main Execution
function Start-ServiceMonitor {
    param([switch]$SingleRun)
    
    # Display header
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    SERVICE MONITOR v1.0.0                         ║" -ForegroundColor Cyan
    Write-Host "║                     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Check admin rights if auto-restart enabled
    if ($AutoRestart -and -not (Test-IsAdmin)) {
        Write-Log "Auto-restart requires administrator privileges" -Level Warning
    }
    
    # Display configuration
    Write-Host "  Configuration:" -ForegroundColor DarkGray
    Write-Host "  ├─ Targets: $($ComputerName -join ', ')" -ForegroundColor DarkGray
    Write-Host "  ├─ Profile: $(if($Profile){$Profile}else{'Custom/Default'})" -ForegroundColor DarkGray
    Write-Host "  ├─ Auto-Restart: $AutoRestart" -ForegroundColor DarkGray
    Write-Host "  ├─ Check Dependencies: $CheckDependencies" -ForegroundColor DarkGray
    Write-Host "  └─ Include Performance: $IncludePerformance" -ForegroundColor DarkGray
    Write-Host ""
    
    # Process each computer
    foreach ($computer in $ComputerName) {
        Write-Log "Processing: $computer" -Level Header
        
        # Check connectivity
        if (-not (Test-RemoteAccess -Computer $computer)) {
            Write-Log "Cannot connect to $computer - skipping" -Level Error
            $Script:Alerts += [PSCustomObject]@{
                Timestamp = Get-Date
                Computer = $computer
                Service = "N/A"
                Type = "Connection"
                Status = "Critical"
                Message = "Cannot connect to remote computer"
            }
            continue
        }
        
        # Get service status
        $services = Get-ServiceStatus -Computer $computer
        
        # Display results
        Show-ServiceStatus -Services $services
    }
    
    # Summary
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " MONITORING SUMMARY" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $running = ($Script:ServiceResults | Where-Object { $_.Status -eq "Running" }).Count
    $stopped = ($Script:ServiceResults | Where-Object { $_.Status -eq "Stopped" }).Count
    $healthy = ($Script:ServiceResults | Where-Object { $_.Health -eq "Healthy" }).Count
    $warning = ($Script:ServiceResults | Where-Object { $_.Health -eq "Warning" }).Count
    $critical = ($Script:ServiceResults | Where-Object { $_.Health -eq "Critical" }).Count
    
    Write-Host " Total Services: $($Script:ServiceResults.Count)" -ForegroundColor White
    Write-Host " Running: $running | Stopped: $stopped" -ForegroundColor White
    Write-Host " Health: " -NoNewline -ForegroundColor White
    Write-Host "$healthy Healthy" -NoNewline -ForegroundColor Green
    Write-Host " | " -NoNewline -ForegroundColor White
    Write-Host "$warning Warning" -NoNewline -ForegroundColor Yellow
    Write-Host " | " -NoNewline -ForegroundColor White
    Write-Host "$critical Critical" -ForegroundColor Red
    Write-Host " Alerts Generated: $($Script:Alerts.Count)" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    # Export reports
    Export-Reports
    
    # Send notifications
    if ($SendEmail -and ($Script:Alerts.Count -gt 0 -or -not $SingleRun)) {
        Send-EmailReport
    }
    
    # Send webhook summary
    if (-not [string]::IsNullOrEmpty($WebhookUrl)) {
        $webhookColor = if ($critical -gt 0) { "danger" } elseif ($warning -gt 0) { "warning" } else { "good" }
        Send-WebhookNotification -Title "Service Monitor Summary" `
            -Message "Computers: $($ComputerName -join ', ')`nTotal: $($Script:ServiceResults.Count) | Running: $running | Stopped: $stopped`nHealthy: $healthy | Warning: $warning | Critical: $critical" `
            -Color $webhookColor
    }
    
    # Return results object
    return [PSCustomObject]@{
        Timestamp        = $Script:Timestamp
        Computers        = $ComputerName
        TotalServices    = $Script:ServiceResults.Count
        Running          = $running
        Stopped          = $stopped
        Healthy          = $healthy
        Warning          = $warning
        Critical         = $critical
        Alerts           = $Script:Alerts
        ServiceResults   = $Script:ServiceResults
        PerformanceData  = $Script:PerformanceData
    }
}

# Main execution
if ($ContinuousMonitor) {
    Write-Log "Starting continuous monitoring (Interval: ${MonitorInterval}s). Press Ctrl+C to stop." -Level Header
    
    $iteration = 0
    while ($true) {
        $iteration++
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host " Monitoring Iteration #$iteration - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        
        # Reset results for each iteration
        $Script:Timestamp = Get-Date
        $Script:ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"
        $Script:ServiceResults = @()
        $Script:Alerts = @()
        $Script:PerformanceData = @()
        
        Start-ServiceMonitor -SingleRun
        
        Write-Host ""
        Write-Host "Next check in $MonitorInterval seconds... (Press Ctrl+C to stop)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $MonitorInterval
    }
}
else {
    Start-ServiceMonitor
}
#endregion
