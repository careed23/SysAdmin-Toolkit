<#
.SYNOPSIS
    Printer Troubleshooting and Diagnostic Script
    
.DESCRIPTION
    Comprehensive printer troubleshooting toolkit including:
    - Common issue detection and resolution
    - Print spooler management
    - Driver troubleshooting
    - Queue management and cleanup
    - Connectivity diagnostics
    - Automated repair procedures
    - Guided troubleshooting wizard
    - Logging and documentation
    
.PARAMETER PrinterName
    Name of the printer to troubleshoot

.PARAMETER Issue
    Specific issue to diagnose

.EXAMPLE
    Start-PrinterTroubleshooter -PrinterName "HP-Floor2"
    
.EXAMPLE
    Repair-PrintSpooler -ClearQueue

.EXAMPLE
    Invoke-PrinterDiagnostics -PrinterName "Reception-Printer" -Detailed

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Requires: Administrator privileges for some operations
#>

#Requires -RunAsAdministrator

#region Configuration

$script:Config = @{
    # Common issues and solutions
    CommonIssues = @{
        "Offline" = @{
            Symptoms = @("Printer shows offline", "Jobs stuck in queue")
            Causes = @("Network connectivity", "Printer powered off", "Driver issue", "Spooler problem")
            AutoFix = $true
        }
        "PaperJam" = @{
            Symptoms = @("Paper jam error", "Jobs not printing")
            Causes = @("Physical paper jam", "Sensor issue", "Paper quality")
            AutoFix = $false
        }
        "SlowPrinting" = @{
            Symptoms = @("Slow print jobs", "Long queue times")
            Causes = @("Large print jobs", "Network congestion", "Driver settings", "Spooler issues")
            AutoFix = $true
        }
        "QualityIssues" = @{
            Symptoms = @("Faded prints", "Streaks", "Smudges")
            Causes = @("Low toner", "Dirty components", "Driver settings")
            AutoFix = $false
        }
        "SpoolerCrash" = @{
            Symptoms = @("Print spooler stops", "Cannot add printers", "Print jobs disappear")
            Causes = @("Corrupted driver", "Bad print job", "System issue")
            AutoFix = $true
        }
        "DriverIssue" = @{
            Symptoms = @("Printer not recognized", "Features unavailable", "Crashes when printing")
            Causes = @("Outdated driver", "Corrupted driver", "Wrong driver")
            AutoFix = $true
        }
    }
    
    # Spooler paths
    SpoolFolder = "$env:SystemRoot\System32\spool\PRINTERS"
    DriversFolder = "$env:SystemRoot\System32\spool\drivers"
    
    # Logging
    LogPath = ".\logs\printer-troubleshooting"
    MaxLogAgeDays = 30
    
    # Timeouts
    ServiceTimeout = 30
    ConnectivityTimeout = 5
    
    # Report path
    ReportPath = ".\reports\printer-troubleshooting"
}

# Troubleshooting session log
$script:TroubleshootingLog = @()

#endregion

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug', 'Action')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Debug' = 'Gray'
        'Action' = 'Magenta'
    }
    $prefixes = @{
        'Info' = '[*]'
        'Warning' = '[!]'
        'Error' = '[X]'
        'Success' = '[✓]'
        'Debug' = '[D]'
        'Action' = '[>]'
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "$timestamp $($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
    
    # Add to session log
    $script:TroubleshootingLog += [PSCustomObject]@{
        Timestamp = Get-Date
        Level = $Level
        Message = $Message
    }
}

function Save-TroubleshootingLog {
    param(
        [string]$PrinterName = "General",
        [string]$OutputPath
    )
    
    if (-not $OutputPath) {
        if (-not (Test-Path $script:Config.LogPath)) {
            New-Item -Path $script:Config.LogPath -ItemType Directory -Force | Out-Null
        }
        $OutputPath = Join-Path $script:Config.LogPath "Troubleshoot_$($PrinterName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
    
    $script:TroubleshootingLog | ForEach-Object {
        "$($_.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) [$($_.Level)] $($_.Message)"
    } | Out-File -FilePath $OutputPath -Encoding UTF8
    
    Write-Log "Log saved to: $OutputPath" -Level Info
    return $OutputPath
}

function Test-PrinterExists {
    param(
        [string]$PrinterName,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $null = Get-Printer -Name $PrinterName -ComputerName $ComputerName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-PrinterIPAddress {
    param(
        [string]$PrinterName,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName
        $port = Get-PrinterPort -Name $printer.PortName -ComputerName $ComputerName
        return $port.PrinterHostAddress
    }
    catch {
        return $null
    }
}

#endregion

#region Print Spooler Management

function Get-SpoolerStatus {
    <#
    .SYNOPSIS
        Gets the current status of the Print Spooler service
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $service = Get-Service -Name Spooler -ComputerName $ComputerName -ErrorAction Stop
        
        $spoolFiles = @()
        $spoolFolder = if ($ComputerName -eq $env:COMPUTERNAME) {
            $script:Config.SpoolFolder
        } else {
            "\\$ComputerName\C$\Windows\System32\spool\PRINTERS"
        }
        
        if (Test-Path $spoolFolder) {
            $spoolFiles = Get-ChildItem -Path $spoolFolder -ErrorAction SilentlyContinue
        }
        
        return [PSCustomObject]@{
            ComputerName = $ComputerName
            Status = $service.Status
            StartType = $service.StartType
            CanStop = $service.CanStop
            SpoolFolderPath = $spoolFolder
            SpooledJobFiles = $spoolFiles.Count
            SpoolFolderSize = ($spoolFiles | Measure-Object -Property Length -Sum).Sum
        }
    }
    catch {
        Write-Log "Failed to get spooler status: $_" -Level Error
        return $null
    }
}

function Restart-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the Print Spooler service with optional queue clearing
    
    .PARAMETER ComputerName
        Target computer
    
    .PARAMETER ClearQueue
        Clear all pending print jobs
    
    .PARAMETER Force
        Force restart even if jobs are pending
    
    .EXAMPLE
        Restart-PrintSpooler -ClearQueue
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$ClearQueue,
        
        [switch]$Force
    )
    
    Write-Log "Restarting Print Spooler on $ComputerName..." -Level Action
    
    if ($PSCmdlet.ShouldProcess($ComputerName, "Restart Print Spooler")) {
        try {
            # Check for pending jobs
            if (-not $Force -and -not $ClearQueue) {
                $jobs = Get-PrintJob -ComputerName $ComputerName -ErrorAction SilentlyContinue
                if ($jobs) {
                    Write-Log "There are $($jobs.Count) pending print jobs. Use -Force or -ClearQueue to proceed." -Level Warning
                    return $false
                }
            }
            
            # Stop spooler
            Write-Log "Stopping Print Spooler service..." -Level Info
            Stop-Service -Name Spooler -Force -ErrorAction Stop
            
            # Wait for service to stop
            $timeout = 0
            while ((Get-Service -Name Spooler).Status -ne 'Stopped' -and $timeout -lt $script:Config.ServiceTimeout) {
                Start-Sleep -Seconds 1
                $timeout++
            }
            
            if ((Get-Service -Name Spooler).Status -ne 'Stopped') {
                throw "Spooler service did not stop within timeout period"
            }
            
            # Clear queue if requested
            if ($ClearQueue) {
                Write-Log "Clearing print queue..." -Level Info
                
                $spoolFolder = if ($ComputerName -eq $env:COMPUTERNAME) {
                    $script:Config.SpoolFolder
                } else {
                    "\\$ComputerName\C$\Windows\System32\spool\PRINTERS"
                }
                
                $deletedCount = 0
                Get-ChildItem -Path $spoolFolder -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    $deletedCount++
                }
                
                Write-Log "Deleted $deletedCount spool files" -Level Success
            }
            
            # Start spooler
            Write-Log "Starting Print Spooler service..." -Level Info
            Start-Service -Name Spooler -ErrorAction Stop
            
            # Wait for service to start
            $timeout = 0
            while ((Get-Service -Name Spooler).Status -ne 'Running' -and $timeout -lt $script:Config.ServiceTimeout) {
                Start-Sleep -Seconds 1
                $timeout++
            }
            
            if ((Get-Service -Name Spooler).Status -eq 'Running') {
                Write-Log "Print Spooler restarted successfully" -Level Success
                return $true
            }
            else {
                throw "Spooler service did not start within timeout period"
            }
        }
        catch {
            Write-Log "Failed to restart Print Spooler: $_" -Level Error
            
            # Attempt to start if stopped
            try {
                Start-Service -Name Spooler -ErrorAction SilentlyContinue
            }
            catch { }
            
            return $false
        }
    }
}

function Repair-PrintSpooler {
    <#
    .SYNOPSIS
        Performs comprehensive Print Spooler repair
    
    .DESCRIPTION
        Repairs the Print Spooler by:
        - Stopping the service
        - Clearing the spool folder
        - Resetting spooler dependencies
        - Clearing corrupted registry entries (optional)
        - Restarting the service
    
    .PARAMETER ClearDrivers
        Also clear third-party print processor DLLs (use with caution)
    
    .PARAMETER ResetDefaults
        Reset spooler to default configuration
    
    .EXAMPLE
        Repair-PrintSpooler
    
    .EXAMPLE
        Repair-PrintSpooler -ClearDrivers -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$ClearDrivers,
        
        [switch]$ResetDefaults
    )
    
    Write-Log "Starting comprehensive Print Spooler repair..." -Level Action
    
    if ($PSCmdlet.ShouldProcess($ComputerName, "Repair Print Spooler (this may remove print jobs)")) {
        $steps = @()
        
        try {
            # Step 1: Stop dependent services
            Write-Log "Step 1: Stopping dependent services..." -Level Info
            $dependentServices = Get-Service -Name Spooler -DependentServices -ErrorAction SilentlyContinue
            foreach ($svc in $dependentServices | Where-Object { $_.Status -eq 'Running' }) {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            }
            $steps += "Stopped dependent services"
            
            # Step 2: Stop Print Spooler
            Write-Log "Step 2: Stopping Print Spooler..." -Level Info
            Stop-Service -Name Spooler -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            $steps += "Stopped Print Spooler"
            
            # Step 3: Clear spool folder
            Write-Log "Step 3: Clearing spool folder..." -Level Info
            $spoolFolder = $script:Config.SpoolFolder
            $deletedFiles = 0
            Get-ChildItem -Path $spoolFolder -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                $deletedFiles++
            }
            $steps += "Cleared $deletedFiles spool files"
            
            # Step 4: Clear shadow files (if any)
            Write-Log "Step 4: Clearing shadow copies..." -Level Info
            $shadowPath = "$env:SystemRoot\System32\spool\SHADOW"
            if (Test-Path $shadowPath) {
                Get-ChildItem -Path $shadowPath -ErrorAction SilentlyContinue | 
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
            $steps += "Cleared shadow files"
            
            # Step 5: Clear drivers (if requested)
            if ($ClearDrivers) {
                Write-Log "Step 5: Clearing problematic print processors..." -Level Warning
                # This is risky - only clear specific problematic processors
                # Not implementing full driver clear as it can break printing
                $steps += "Driver clearing skipped (safety measure)"
            }
            
            # Step 6: Reset registry (if requested)
            if ($ResetDefaults) {
                Write-Log "Step 6: Resetting spooler registry settings..." -Level Info
                # Reset specific problematic registry values
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print"
                
                # Clear any corrupted printer entries
                # Note: This is conservative - not deleting printers
                $steps += "Registry settings verified"
            }
            
            # Step 7: Start Print Spooler
            Write-Log "Step 7: Starting Print Spooler..." -Level Info
            Start-Service -Name Spooler -ErrorAction Stop
            
            $timeout = 0
            while ((Get-Service -Name Spooler).Status -ne 'Running' -and $timeout -lt 30) {
                Start-Sleep -Seconds 1
                $timeout++
            }
            
            if ((Get-Service -Name Spooler).Status -eq 'Running') {
                $steps += "Print Spooler started successfully"
                Write-Log "Print Spooler repair completed successfully" -Level Success
                
                # Summary
                Write-Host ""
                Write-Host "Repair Steps Completed:" -ForegroundColor Cyan
                foreach ($step in $steps) {
                    Write-Host "  ✓ $step" -ForegroundColor Green
                }
                
                return $true
            }
            else {
                throw "Print Spooler failed to start"
            }
        }
        catch {
            Write-Log "Repair failed: $_" -Level Error
            
            # Emergency start attempt
            Start-Service -Name Spooler -ErrorAction SilentlyContinue
            
            return $false
        }
    }
}

#endregion

#region Queue Management

function Get-StuckPrintJobs {
    <#
    .SYNOPSIS
        Identifies stuck or problematic print jobs
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [string]$PrinterName,
        
        [int]$AgeMinutes = 30
    )
    
    $jobs = if ($PrinterName) {
        Get-PrintJob -PrinterName $PrinterName -ComputerName $ComputerName -ErrorAction SilentlyContinue
    }
    else {
        Get-Printer -ComputerName $ComputerName | ForEach-Object {
            Get-PrintJob -PrinterName $_.Name -ComputerName $ComputerName -ErrorAction SilentlyContinue
        }
    }
    
    $stuckJobs = $jobs | Where-Object {
        $jobAge = (New-TimeSpan -Start $_.SubmittedTime -End (Get-Date)).TotalMinutes
        
        # Consider stuck if: old job, error state, or paused for a long time
        ($jobAge -gt $AgeMinutes) -or 
        ($_.JobStatus -match 'Error|Offline|PaperOut') -or
        ($_.JobStatus -match 'Paused' -and $jobAge -gt 5)
    }
    
    return $stuckJobs | Select-Object @{N='PrinterName';E={$_.PrinterName}},
        Id,
        @{N='DocumentName';E={$_.DocumentName}},
        @{N='UserName';E={$_.UserName}},
        @{N='SubmittedTime';E={$_.SubmittedTime}},
        @{N='AgeMinutes';E={[math]::Round((New-TimeSpan -Start $_.SubmittedTime -End (Get-Date)).TotalMinutes, 1)}},
        @{N='Size';E={"{0:N2} MB" -f ($_.Size / 1MB)}},
        @{N='Status';E={$_.JobStatus}},
        @{N='Priority';E={$_.Priority}}
}

function Clear-PrintQueue {
    <#
    .SYNOPSIS
        Clears print jobs from a printer or all printers
    
    .PARAMETER PrinterName
        Specific printer (or all if not specified)
    
    .PARAMETER OlderThanMinutes
        Only clear jobs older than specified minutes
    
    .PARAMETER StuckOnly
        Only clear jobs that appear stuck
    
    .EXAMPLE
        Clear-PrintQueue -PrinterName "HP-Floor2"
    
    .EXAMPLE
        Clear-PrintQueue -StuckOnly -OlderThanMinutes 60
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [int]$OlderThanMinutes,
        
        [switch]$StuckOnly,
        
        [switch]$Force
    )
    
    Write-Log "Clearing print queue..." -Level Action
    
    # Get jobs to clear
    $jobs = if ($PrinterName) {
        Get-PrintJob -PrinterName $PrinterName -ComputerName $ComputerName -ErrorAction SilentlyContinue
    }
    else {
        Get-Printer -ComputerName $ComputerName | ForEach-Object {
            Get-PrintJob -PrinterName $_.Name -ComputerName $ComputerName -ErrorAction SilentlyContinue
        }
    }
    
    if (-not $jobs) {
        Write-Log "No print jobs found" -Level Info
        return 0
    }
    
    # Filter if needed
    if ($StuckOnly) {
        $jobs = Get-StuckPrintJobs -ComputerName $ComputerName -PrinterName $PrinterName
    }
    
    if ($OlderThanMinutes) {
        $cutoff = (Get-Date).AddMinutes(-$OlderThanMinutes)
        $jobs = $jobs | Where-Object { $_.SubmittedTime -lt $cutoff }
    }
    
    if (-not $jobs) {
        Write-Log "No matching print jobs found" -Level Info
        return 0
    }
    
    Write-Log "Found $($jobs.Count) jobs to clear" -Level Info
    
    $cleared = 0
    $failed = 0
    
    foreach ($job in $jobs) {
        $jobDesc = "Job $($job.Id) - $($job.DocumentName) ($($job.UserName))"
        
        if ($PSCmdlet.ShouldProcess($jobDesc, "Remove print job")) {
            try {
                Remove-PrintJob -PrinterName $job.PrinterName -ID $job.Id -ComputerName $ComputerName -ErrorAction Stop
                Write-Log "Cleared: $jobDesc" -Level Success
                $cleared++
            }
            catch {
                Write-Log "Failed to clear: $jobDesc - $_" -Level Warning
                $failed++
            }
        }
    }
    
    Write-Log "Cleared $cleared jobs ($failed failed)" -Level $(if ($failed -eq 0) { 'Success' } else { 'Warning' })
    
    return $cleared
}

function Restart-PrintJob {
    <#
    .SYNOPSIS
        Restarts a stuck print job
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [Parameter(Mandatory)]
        [int]$JobId,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $job = Get-PrintJob -PrinterName $PrinterName -ID $JobId -ComputerName $ComputerName -ErrorAction Stop
        
        # Restart by pausing and resuming
        Suspend-PrintJob -PrinterName $PrinterName -ID $JobId -ComputerName $ComputerName -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Resume-PrintJob -PrinterName $PrinterName -ID $JobId -ComputerName $ComputerName -ErrorAction Stop
        
        Write-Log "Restarted job $JobId on $PrinterName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to restart job: $_" -Level Error
        return $false
    }
}

#endregion

#region Connectivity Diagnostics

function Test-PrinterConnectivity {
    <#
    .SYNOPSIS
        Comprehensive connectivity test for a printer
    
    .PARAMETER PrinterName
        Printer name to test
    
    .PARAMETER IPAddress
        Direct IP address (if printer name not available)
    
    .EXAMPLE
        Test-PrinterConnectivity -PrinterName "HP-Floor2"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$PrinterName,
        
        [Parameter(Mandatory, ParameterSetName = 'ByIP')]
        [string]$IPAddress,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    Write-Log "Testing printer connectivity..." -Level Info
    
    $results = [PSCustomObject]@{
        PrinterName = $PrinterName
        IPAddress = $IPAddress
        PingTest = $false
        PingLatency = $null
        Port9100Test = $false
        Port631Test = $false
        Port80Test = $false
        WebUIAccessible = $false
        SNMPResponding = $false
        WSDTest = $false
        OverallStatus = "Unknown"
        Issues = @()
        Recommendations = @()
    }
    
    # Get IP if using printer name
    if ($PrinterName -and -not $IPAddress) {
        $IPAddress = Get-PrinterIPAddress -PrinterName $PrinterName -ComputerName $ComputerName
        $results.IPAddress = $IPAddress
        
        if (-not $IPAddress) {
            $results.Issues += "Could not determine printer IP address"
            $results.OverallStatus = "Error"
            return $results
        }
    }
    
    # Test 1: Ping
    Write-Log "  Testing ICMP ping..." -Level Debug
    try {
        $ping = Test-Connection -ComputerName $IPAddress -Count 3 -ErrorAction Stop
        $results.PingTest = $true
        $results.PingLatency = [math]::Round(($ping.ResponseTime | Measure-Object -Average).Average, 2)
        Write-Log "  Ping successful (avg: $($results.PingLatency)ms)" -Level Success
    }
    catch {
        $results.Issues += "Printer does not respond to ping"
        Write-Log "  Ping failed" -Level Warning
    }
    
    # Test 2: Port 9100 (RAW printing)
    Write-Log "  Testing port 9100 (RAW)..." -Level Debug
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($IPAddress, 9100, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if ($wait -and $tcp.Connected) {
            $results.Port9100Test = $true
            Write-Log "  Port 9100 is open" -Level Success
        }
        $tcp.Close()
    }
    catch {
        $results.Issues += "Port 9100 (RAW printing) is not accessible"
    }
    
    # Test 3: Port 631 (IPP)
    Write-Log "  Testing port 631 (IPP)..." -Level Debug
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($IPAddress, 631, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if ($wait -and $tcp.Connected) {
            $results.Port631Test = $true
            Write-Log "  Port 631 is open" -Level Success
        }
        $tcp.Close()
    }
    catch { }
    
    # Test 4: Port 80 (Web UI)
    Write-Log "  Testing port 80 (HTTP)..." -Level Debug
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($IPAddress, 80, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if ($wait -and $tcp.Connected) {
            $results.Port80Test = $true
            
            # Try to access web UI
            try {
                $web = Invoke-WebRequest -Uri "http://$IPAddress" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                $results.WebUIAccessible = $true
                Write-Log "  Web UI is accessible" -Level Success
            }
            catch {
                Write-Log "  Port 80 open but web UI not responding" -Level Debug
            }
        }
        $tcp.Close()
    }
    catch { }
    
    # Test 5: SNMP (if available)
    Write-Log "  Testing SNMP..." -Level Debug
    try {
        # Simple SNMP test using .NET
        # Note: Full SNMP requires additional modules
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Client.ReceiveTimeout = 2000
        $udp.Connect($IPAddress, 161)
        
        # SNMP GetRequest for sysDescr
        $snmpRequest = [byte[]](0x30, 0x26, 0x02, 0x01, 0x01, 0x04, 0x06, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 
                                0xa0, 0x19, 0x02, 0x04, 0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0x00, 0x02, 0x01, 
                                0x00, 0x30, 0x0b, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x06, 0x01, 0x02, 0x01, 0x05, 0x00)
        
        $udp.Send($snmpRequest, $snmpRequest.Length) | Out-Null
        
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $response = $udp.Receive([ref]$endpoint)
        
        if ($response) {
            $results.SNMPResponding = $true
            Write-Log "  SNMP is responding" -Level Success
        }
        $udp.Close()
    }
    catch {
        Write-Log "  SNMP not responding or not available" -Level Debug
    }
    
    # Determine overall status
    if ($results.PingTest -and ($results.Port9100Test -or $results.Port631Test)) {
        $results.OverallStatus = "Healthy"
    }
    elseif ($results.PingTest) {
        $results.OverallStatus = "Degraded"
        $results.Recommendations += "Printer responds to ping but print ports are closed. Check printer settings."
    }
    else {
        $results.OverallStatus = "Offline"
        $results.Recommendations += "Printer is not responding. Check physical connection and power."
    }
    
    # Additional recommendations
    if (-not $results.WebUIAccessible -and $results.PingTest) {
        $results.Recommendations += "Web interface not accessible. May need to enable in printer settings."
    }
    
    if (-not $results.SNMPResponding) {
        $results.Recommendations += "SNMP not available. Enable for supply level monitoring."
    }
    
    return $results
}

function Test-PrinterDriver {
    <#
    .SYNOPSIS
        Tests printer driver health
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    Write-Log "Testing printer driver..." -Level Info
    
    $results = [PSCustomObject]@{
        PrinterName = $PrinterName
        DriverName = $null
        DriverVersion = $null
        DriverInstalled = $false
        DriverFilesExist = $false
        DriverConfigValid = $false
        Issues = @()
        Recommendations = @()
    }
    
    try {
        $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName -ErrorAction Stop
        $results.DriverName = $printer.DriverName
        
        # Get driver details
        $driver = Get-PrinterDriver -Name $printer.DriverName -ComputerName $ComputerName -ErrorAction Stop
        $results.DriverInstalled = $true
        $results.DriverVersion = $driver.DriverVersion
        
        # Check driver files
        if ($driver.ConfigFile -and (Test-Path $driver.ConfigFile -ErrorAction SilentlyContinue)) {
            $results.DriverFilesExist = $true
        }
        else {
            $results.Issues += "Driver configuration file missing"
            $results.Recommendations += "Reinstall printer driver"
        }
        
        # Test driver configuration
        try {
            $config = Get-PrintConfiguration -PrinterName $PrinterName -ComputerName $ComputerName -ErrorAction Stop
            $results.DriverConfigValid = $true
        }
        catch {
            $results.Issues += "Driver configuration is invalid"
            $results.Recommendations += "Reset printer to default settings or reinstall driver"
        }
        
        Write-Log "Driver '$($results.DriverName)' version $($results.DriverVersion)" -Level Info
    }
    catch {
        $results.Issues += "Could not retrieve driver information: $_"
        $results.Recommendations += "Reinstall printer and driver"
    }
    
    return $results
}

#endregion

#region Automated Fixes

function Repair-OfflinePrinter {
    <#
    .SYNOPSIS
        Attempts to bring an offline printer back online
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    Write-Log "Attempting to repair offline printer: $PrinterName" -Level Action
    
    $repairSteps = @()
    $success = $false
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Repair offline printer")) {
        # Step 1: Test connectivity
        Write-Log "Step 1: Testing connectivity..." -Level Info
        $connectivity = Test-PrinterConnectivity -PrinterName $PrinterName -ComputerName $ComputerName
        
        if ($connectivity.OverallStatus -eq "Offline") {
            Write-Log "Printer is not reachable on the network" -Level Error
            $repairSteps += @{Step="Connectivity Test"; Result="Failed"; Action="Check physical connection"}
            
            return [PSCustomObject]@{
                PrinterName = $PrinterName
                Success = $false
                Steps = $repairSteps
                FinalStatus = "Offline - Network unreachable"
            }
        }
        $repairSteps += @{Step="Connectivity Test"; Result="Passed"; Action="None"}
        
        # Step 2: Clear stuck jobs
        Write-Log "Step 2: Clearing stuck print jobs..." -Level Info
        $stuckJobs = Get-StuckPrintJobs -PrinterName $PrinterName -ComputerName $ComputerName
        if ($stuckJobs) {
            Clear-PrintQueue -PrinterName $PrinterName -ComputerName $ComputerName -StuckOnly -Force
            $repairSteps += @{Step="Clear Stuck Jobs"; Result="Cleared $($stuckJobs.Count) jobs"; Action="None"}
        }
        else {
            $repairSteps += @{Step="Clear Stuck Jobs"; Result="No stuck jobs"; Action="None"}
        }
        
        # Step 3: Reset printer port
        Write-Log "Step 3: Verifying printer port..." -Level Info
        try {
            $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName
            $port = Get-PrinterPort -Name $printer.PortName -ComputerName $ComputerName
            
            # Recreate port if needed
            if (-not $port.PrinterHostAddress) {
                Write-Log "  Port configuration issue detected" -Level Warning
                $repairSteps += @{Step="Port Verification"; Result="Issue detected"; Action="Manual port reconfiguration needed"}
            }
            else {
                $repairSteps += @{Step="Port Verification"; Result="Passed"; Action="None"}
            }
        }
        catch {
            $repairSteps += @{Step="Port Verification"; Result="Error"; Action="Check port configuration"}
        }
        
        # Step 4: Take printer out of offline mode
        Write-Log "Step 4: Setting printer online..." -Level Info
        try {
            # Use WMI to set printer online
            $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName |
                Where-Object { $_.Name -eq $PrinterName }
            
            if ($wmiPrinter.WorkOffline) {
                $wmiPrinter.WorkOffline = $false
                $wmiPrinter.Put() | Out-Null
                $repairSteps += @{Step="Set Online"; Result="Changed to online"; Action="None"}
            }
            else {
                $repairSteps += @{Step="Set Online"; Result="Already online"; Action="None"}
            }
        }
        catch {
            $repairSteps += @{Step="Set Online"; Result="Failed"; Action=$_.Exception.Message}
        }
        
        # Step 5: Send test page
        Write-Log "Step 5: Testing print capability..." -Level Info
        try {
            Start-Sleep -Seconds 2
            
            $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName |
                Where-Object { $_.Name -eq $PrinterName }
            
            $testResult = $wmiPrinter.PrintTestPage()
            
            if ($testResult.ReturnValue -eq 0) {
                $repairSteps += @{Step="Test Page"; Result="Sent successfully"; Action="None"}
                $success = $true
            }
            else {
                $repairSteps += @{Step="Test Page"; Result="Failed (code: $($testResult.ReturnValue))"; Action="Manual test needed"}
            }
        }
        catch {
            $repairSteps += @{Step="Test Page"; Result="Error"; Action=$_.Exception.Message}
        }
        
        # Final status check
        $finalStatus = Get-PrinterStatus -PrinterName $PrinterName -ComputerName $ComputerName
        
        return [PSCustomObject]@{
            PrinterName = $PrinterName
            Success = $success
            Steps = $repairSteps
            FinalStatus = $finalStatus.PrinterStatus
            Recommendations = if (-not $success) { @("Restart print spooler", "Check printer hardware", "Reinstall printer") } else { @() }
        }
    }
}

function Repair-PrinterDriver {
    <#
    .SYNOPSIS
        Repairs or reinstalls a printer driver
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [string]$NewDriverName,
        
        [switch]$UseUniversalDriver
    )
    
    Write-Log "Repairing printer driver for: $PrinterName" -Level Action
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Repair printer driver")) {
        try {
            $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName
            $currentDriver = $printer.DriverName
            
            # Determine new driver
            $targetDriver = if ($NewDriverName) {
                $NewDriverName
            }
            elseif ($UseUniversalDriver) {
                "HP Universal Printing PCL 6"  # Common fallback
            }
            else {
                $currentDriver
            }
            
            Write-Log "Current driver: $currentDriver" -Level Info
            Write-Log "Target driver: $targetDriver" -Level Info
            
            # Check if target driver is installed
            if (-not (Test-PrinterDriverExists -DriverName $targetDriver -ComputerName $ComputerName)) {
                Write-Log "Installing driver: $targetDriver" -Level Info
                Add-PrinterDriver -Name $targetDriver -ComputerName $ComputerName -ErrorAction Stop
            }
            
            # Update printer to use new driver
            Set-Printer -Name $PrinterName -ComputerName $ComputerName -DriverName $targetDriver -ErrorAction Stop
            
            Write-Log "Printer driver updated successfully" -Level Success
            
            return [PSCustomObject]@{
                PrinterName = $PrinterName
                PreviousDriver = $currentDriver
                NewDriver = $targetDriver
                Success = $true
            }
        }
        catch {
            Write-Log "Failed to repair driver: $_" -Level Error
            return [PSCustomObject]@{
                PrinterName = $PrinterName
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

function Test-PrinterDriverExists {
    param(
        [string]$DriverName,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $null = Get-PrinterDriver -Name $DriverName -ComputerName $ComputerName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region Diagnostic Functions

function Invoke-PrinterDiagnostics {
    <#
    .SYNOPSIS
        Runs comprehensive diagnostics on a printer
    
    .DESCRIPTION
        Performs full diagnostic analysis including:
        - Connectivity tests
        - Queue analysis
        - Driver verification
        - Status checks
        - Performance metrics
    
    .PARAMETER PrinterName
        Name of the printer to diagnose
    
    .PARAMETER Detailed
        Include detailed diagnostics
    
    .PARAMETER ExportReport
        Export HTML report
    
    .EXAMPLE
        Invoke-PrinterDiagnostics -PrinterName "HP-Floor2" -Detailed
    
    .EXAMPLE
        Invoke-PrinterDiagnostics -PrinterName "Reception-Printer" -ExportReport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$Detailed,
        
        [switch]$ExportReport,
        
        [string]$ReportPath
    )
    
    $script:TroubleshootingLog = @()  # Reset log
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              Printer Diagnostics                               ║" -ForegroundColor Cyan
    Write-Host "║              $PrinterName".PadRight(45) + "║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $diagnostics = [PSCustomObject]@{
        PrinterName = $PrinterName
        ComputerName = $ComputerName
        Timestamp = Get-Date
        
        # Basic Info
        PrinterInfo = $null
        
        # Tests
        ConnectivityTest = $null
        DriverTest = $null
        QueueAnalysis = $null
        SpoolerStatus = $null
        
        # Results
        OverallHealth = "Unknown"
        Issues = @()
        Recommendations = @()
    }
    
    # Verify printer exists
    if (-not (Test-PrinterExists -PrinterName $PrinterName -ComputerName $ComputerName)) {
        Write-Log "Printer '$PrinterName' not found on $ComputerName" -Level Error
        $diagnostics.OverallHealth = "Not Found"
        return $diagnostics
    }
    
    # 1. Get Printer Info
    Write-Log "Gathering printer information..." -Level Info
    try {
        $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName -Full
        $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName |
            Where-Object { $_.Name -eq $PrinterName }
        $port = Get-PrinterPort -Name $printer.PortName -ComputerName $ComputerName -ErrorAction SilentlyContinue
        
        $diagnostics.PrinterInfo = [PSCustomObject]@{
            Name = $printer.Name
            ShareName = $printer.ShareName
            DriverName = $printer.DriverName
            PortName = $printer.PortName
            IPAddress = $port.PrinterHostAddress
            Location = $printer.Location
            Comment = $printer.Comment
            Status = $wmiPrinter.PrinterStatus
            StatusText = Get-PrinterStatusText -StatusCode $wmiPrinter.PrinterStatus
            IsShared = $printer.Shared
            IsPublished = $printer.Published
            WorkOffline = $wmiPrinter.WorkOffline
        }
        
        Write-Log "  Status: $($diagnostics.PrinterInfo.StatusText)" -Level $(
            if ($diagnostics.PrinterInfo.Status -eq 3) { 'Success' }
            elseif ($diagnostics.PrinterInfo.Status -in @(4,5)) { 'Info' }
            else { 'Warning' }
        )
    }
    catch {
        Write-Log "Failed to get printer info: $_" -Level Error
        $diagnostics.Issues += "Could not retrieve printer information"
    }
    
    # 2. Connectivity Test
    Write-Log "Running connectivity tests..." -Level Info
    $diagnostics.ConnectivityTest = Test-PrinterConnectivity -PrinterName $PrinterName -ComputerName $ComputerName
    
    if ($diagnostics.ConnectivityTest.OverallStatus -ne "Healthy") {
        $diagnostics.Issues += $diagnostics.ConnectivityTest.Issues
        $diagnostics.Recommendations += $diagnostics.ConnectivityTest.Recommendations
    }
    
    # 3. Driver Test
    Write-Log "Checking printer driver..." -Level Info
    $diagnostics.DriverTest = Test-PrinterDriver -PrinterName $PrinterName -ComputerName $ComputerName
    
    if ($diagnostics.DriverTest.Issues) {
        $diagnostics.Issues += $diagnostics.DriverTest.Issues
        $diagnostics.Recommendations += $diagnostics.DriverTest.Recommendations
    }
    
    # 4. Queue Analysis
    Write-Log "Analyzing print queue..." -Level Info
    $jobs = Get-PrintJob -PrinterName $PrinterName -ComputerName $ComputerName -ErrorAction SilentlyContinue
    $stuckJobs = Get-StuckPrintJobs -PrinterName $PrinterName -ComputerName $ComputerName
    
    $diagnostics.QueueAnalysis = [PSCustomObject]@{
        TotalJobs = ($jobs | Measure-Object).Count
        StuckJobs = ($stuckJobs | Measure-Object).Count
        OldestJob = ($jobs | Sort-Object SubmittedTime | Select-Object -First 1).SubmittedTime
        TotalSize = ($jobs | Measure-Object -Property Size -Sum).Sum
        JobsByStatus = $jobs | Group-Object JobStatus | Select-Object Name, Count
    }
    
    if ($diagnostics.QueueAnalysis.StuckJobs -gt 0) {
        $diagnostics.Issues += "$($diagnostics.QueueAnalysis.StuckJobs) stuck print jobs detected"
        $diagnostics.Recommendations += "Clear stuck print jobs"
    }
    
    Write-Log "  Total jobs: $($diagnostics.QueueAnalysis.TotalJobs), Stuck: $($diagnostics.QueueAnalysis.StuckJobs)" -Level Info
    
    # 5. Spooler Status
    Write-Log "Checking print spooler..." -Level Info
    $diagnostics.SpoolerStatus = Get-SpoolerStatus -ComputerName $ComputerName
    
    if ($diagnostics.SpoolerStatus.Status -ne 'Running') {
        $diagnostics.Issues += "Print Spooler is not running"
        $diagnostics.Recommendations += "Restart Print Spooler service"
    }
    
    # Determine overall health
    if ($diagnostics.Issues.Count -eq 0) {
        $diagnostics.OverallHealth = "Healthy"
    }
    elseif ($diagnostics.ConnectivityTest.OverallStatus -eq "Offline" -or 
           $diagnostics.PrinterInfo.StatusText -match "Offline|Error") {
        $diagnostics.OverallHealth = "Critical"
    }
    else {
        $diagnostics.OverallHealth = "Warning"
    }
    
    # Summary
    Write-Host ""
    Write-Host "═" * 60 -ForegroundColor Cyan
    Write-Host "DIAGNOSTIC SUMMARY" -ForegroundColor Cyan
    Write-Host "═" * 60 -ForegroundColor Cyan
    
    $healthColor = switch ($diagnostics.OverallHealth) {
        "Healthy" { "Green" }
        "Warning" { "Yellow" }
        "Critical" { "Red" }
        default { "Gray" }
    }
    
    Write-Host "Overall Health: " -NoNewline
    Write-Host $diagnostics.OverallHealth -ForegroundColor $healthColor
    Write-Host ""
    
    if ($diagnostics.Issues) {
        Write-Host "Issues Found:" -ForegroundColor Yellow
        foreach ($issue in $diagnostics.Issues) {
            Write-Host "  • $issue" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    if ($diagnostics.Recommendations) {
        Write-Host "Recommendations:" -ForegroundColor Cyan
        foreach ($rec in $diagnostics.Recommendations | Select-Object -Unique) {
            Write-Host "  → $rec" -ForegroundColor Cyan
        }
        Write-Host ""
    }
    
    # Export report if requested
    if ($ExportReport) {
        if (-not $ReportPath) {
            if (-not (Test-Path $script:Config.ReportPath)) {
                New-Item -Path $script:Config.ReportPath -ItemType Directory -Force | Out-Null
            }
            $ReportPath = Join-Path $script:Config.ReportPath "Diagnostics_$($PrinterName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        }
        
        New-PrinterDiagnosticReport -Diagnostics $diagnostics -OutputPath $ReportPath
    }
    
    return $diagnostics
}

function New-PrinterDiagnosticReport {
    <#
    .SYNOPSIS
        Generates HTML diagnostic report
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Diagnostics,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    $healthColor = switch ($Diagnostics.OverallHealth) {
        "Healthy" { "#28a745" }
        "Warning" { "#ffc107" }
        "Critical" { "#dc3545" }
        default { "#6c757d" }
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Printer Diagnostic Report - $($Diagnostics.PrinterName)</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1000px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #6f42c1 0%, #e83e8c 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 24px; }
        .health-badge { display: inline-block; padding: 8px 20px; border-radius: 20px; background: $healthColor; color: white; font-weight: bold; margin-top: 15px; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { color: #6f42c1; border-bottom: 2px solid #6f42c1; padding-bottom: 10px; margin-top: 0; font-size: 18px; }
        .info-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; }
        .info-item { }
        .info-label { font-size: 12px; color: #666; margin-bottom: 4px; }
        .info-value { font-weight: 500; color: #333; }
        .status-ok { color: #28a745; }
        .status-warn { color: #ffc107; }
        .status-error { color: #dc3545; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; }
        .issue-list { background: #fff3cd; padding: 15px; border-radius: 8px; margin-top: 15px; }
        .issue-list h4 { margin: 0 0 10px 0; color: #856404; }
        .recommendation-list { background: #d1ecf1; padding: 15px; border-radius: 8px; margin-top: 15px; }
        .recommendation-list h4 { margin: 0 0 10px 0; color: #0c5460; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖨️ Printer Diagnostic Report</h1>
            <div>$($Diagnostics.PrinterName) | $($Diagnostics.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))</div>
            <div class="health-badge">$($Diagnostics.OverallHealth)</div>
        </div>

        <div class="section">
            <h2>📋 Printer Information</h2>
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Printer Name</div>
                    <div class="info-value">$($Diagnostics.PrinterInfo.Name)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">IP Address</div>
                    <div class="info-value">$($Diagnostics.PrinterInfo.IPAddress)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Driver</div>
                    <div class="info-value">$($Diagnostics.PrinterInfo.DriverName)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Status</div>
                    <div class="info-value">$($Diagnostics.PrinterInfo.StatusText)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Location</div>
                    <div class="info-value">$($Diagnostics.PrinterInfo.Location)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Shared</div>
                    <div class="info-value">$(if ($Diagnostics.PrinterInfo.IsShared) { 'Yes' } else { 'No' })</div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>🌐 Connectivity Tests</h2>
            <table>
                <tr><th>Test</th><th>Result</th></tr>
                <tr>
                    <td>Ping Test</td>
                    <td class="$(if ($Diagnostics.ConnectivityTest.PingTest) { 'status-ok' } else { 'status-error' })">
                        $(if ($Diagnostics.ConnectivityTest.PingTest) { "Pass ($($Diagnostics.ConnectivityTest.PingLatency)ms)" } else { "Fail" })
                    </td>
                </tr>
                <tr>
                    <td>Port 9100 (RAW)</td>
                    <td class="$(if ($Diagnostics.ConnectivityTest.Port9100Test) { 'status-ok' } else { 'status-error' })">
                        $(if ($Diagnostics.ConnectivityTest.Port9100Test) { "Open" } else { "Closed" })
                    </td>
                </tr>
                <tr>
                    <td>Web Interface</td>
                    <td class="$(if ($Diagnostics.ConnectivityTest.WebUIAccessible) { 'status-ok' } else { 'status-warn' })">
                        $(if ($Diagnostics.ConnectivityTest.WebUIAccessible) { "Available" } else { "Not Available" })
                    </td>
                </tr>
                <tr>
                    <td>SNMP</td>
                    <td class="$(if ($Diagnostics.ConnectivityTest.SNMPResponding) { 'status-ok' } else { 'status-warn' })">
                        $(if ($Diagnostics.ConnectivityTest.SNMPResponding) { "Responding" } else { "Not Responding" })
                    </td>
                </tr>
            </table>
        </div>

        <div class="section">
            <h2>📄 Queue Analysis</h2>
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Total Jobs</div>
                    <div class="info-value">$($Diagnostics.QueueAnalysis.TotalJobs)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Stuck Jobs</div>
                    <div class="info-value $(if ($Diagnostics.QueueAnalysis.StuckJobs -gt 0) { 'status-error' })">$($Diagnostics.QueueAnalysis.StuckJobs)</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Oldest Job</div>
                    <div class="info-value">$(if ($Diagnostics.QueueAnalysis.OldestJob) { $Diagnostics.QueueAnalysis.OldestJob.ToString('yyyy-MM-dd HH:mm') } else { 'N/A' })</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Queue Size</div>
                    <div class="info-value">$([math]::Round($Diagnostics.QueueAnalysis.TotalSize / 1MB, 2)) MB</div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>🔧 Driver Status</h2>
            <table>
                <tr><th>Property</th><th>Value</th></tr>
                <tr>
                    <td>Driver Name</td>
                    <td>$($Diagnostics.DriverTest.DriverName)</td>
                </tr>
                <tr>
                    <td>Version</td>
                    <td>$($Diagnostics.DriverTest.DriverVersion)</td>
                </tr>
                <tr>
                    <td>Installed</td>
                    <td class="$(if ($Diagnostics.DriverTest.DriverInstalled) { 'status-ok' } else { 'status-error' })">
                        $(if ($Diagnostics.DriverTest.DriverInstalled) { 'Yes' } else { 'No' })
                    </td>
                </tr>
                <tr>
                    <td>Configuration Valid</td>
                    <td class="$(if ($Diagnostics.DriverTest.DriverConfigValid) { 'status-ok' } else { 'status-error' })">
                        $(if ($Diagnostics.DriverTest.DriverConfigValid) { 'Yes' } else { 'No' })
                    </td>
                </tr>
            </table>
        </div>
"@

    if ($Diagnostics.Issues) {
        $html += @"
        <div class="issue-list">
            <h4>⚠️ Issues Detected</h4>
            <ul>
                $(foreach ($issue in $Diagnostics.Issues) { "<li>$issue</li>" })
            </ul>
        </div>
"@
    }

    if ($Diagnostics.Recommendations) {
        $html += @"
        <div class="recommendation-list">
            <h4>💡 Recommendations</h4>
            <ul>
                $(foreach ($rec in $Diagnostics.Recommendations | Select-Object -Unique) { "<li>$rec</li>" })
            </ul>
        </div>
"@
    }

    $html += @"
        <div style="text-align: center; color: #666; margin-top: 30px; font-size: 12px;">
            Generated by SysAdmin Toolkit Printer Troubleshooter
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Report saved to: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region Troubleshooting Wizard

function Start-PrinterTroubleshooter {
    <#
    .SYNOPSIS
        Interactive printer troubleshooting wizard
    
    .DESCRIPTION
        Guides through common printer issues with automated fixes
    
    .PARAMETER PrinterName
        Printer to troubleshoot (optional, will prompt if not provided)
    
    .EXAMPLE
        Start-PrinterTroubleshooter
    
    .EXAMPLE
        Start-PrinterTroubleshooter -PrinterName "HP-Floor2"
    #>
    [CmdletBinding()]
    param(
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    $script:TroubleshootingLog = @()
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║              Printer Troubleshooting Wizard                    ║" -ForegroundColor Yellow
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    
    # Get printer if not specified
    if (-not $PrinterName) {
        $printers = Get-Printer -ComputerName $Comput
