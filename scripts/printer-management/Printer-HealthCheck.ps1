<#
.SYNOPSIS
    Printer Health Check and Monitoring Script
    
.DESCRIPTION
    Comprehensive printer health monitoring including:
    - Printer status monitoring
    - Print queue analysis
    - Connectivity testing
    - Supply level monitoring (SNMP)
    - Print job statistics
    - Error detection and alerting
    - Performance metrics
    - HTML report generation
    
.PARAMETER PrintServer
    Print server to monitor

.PARAMETER PrinterName
    Specific printer to check

.PARAMETER ExportPath
    Path for HTML report

.EXAMPLE
    Start-PrinterHealthCheck -PrintServer "printserver01"
    
.EXAMPLE
    Get-PrinterStatus -PrinterName "HP-Floor2"

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Requires: Print Management features, SNMP for supply monitoring
#>

#region Configuration

$script:Config = @{
    # Monitoring thresholds
    QueueWarningThreshold = 10
    QueueCriticalThreshold = 25
    JobAgeWarningMinutes = 30
    JobAgeCriticalMinutes = 60
    
    # SNMP settings for supply monitoring
    SNMPCommunity = "public"
    SNMPTimeout = 5000
    
    # Supply level thresholds (percentage)
    SupplyWarningLevel = 20
    SupplyCriticalLevel = 10
    
    # SNMP OIDs for printer information
    SNMPOIDs = @{
        # Standard Printer MIB
        PrinterStatus = "1.3.6.1.2.1.25.3.5.1.1"
        PrinterErrors = "1.3.6.1.2.1.25.3.5.1.2"
        
        # Supplies
        TonerLevel = "1.3.6.1.2.1.43.11.1.1.9"
        TonerMaxLevel = "1.3.6.1.2.1.43.11.1.1.8"
        SupplyDescription = "1.3.6.1.2.1.43.11.1.1.6"
        
        # Page counts
        TotalPageCount = "1.3.6.1.2.1.43.10.2.1.4"
        
        # General info
        DeviceDescription = "1.3.6.1.2.1.25.3.2.1.3"
        SerialNumber = "1.3.6.1.2.1.43.5.1.1.17"
    }
    
    # Report settings
    ReportPath = ".\reports\printer-health"
    
    # Email settings (for alerting)
    SMTPServer = "smtp.company.com"
    AlertRecipients = @("admin@company.com")
    AlertFrom = "printermonitor@company.com"
}

#endregion

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Debug' = 'Gray'
    }
    $prefixes = @{
        'Info' = '[*]'
        'Warning' = '[!]'
        'Error' = '[X]'
        'Success' = '[✓]'
        'Debug' = '[D]'
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "$timestamp $($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function Get-PrinterStatusText {
    param([int]$StatusCode)
    
    $statusMap = @{
        0 = "Unknown"
        1 = "Other"
        2 = "Unknown"
        3 = "Idle"
        4 = "Printing"
        5 = "Warming Up"
        6 = "Stopped Printing"
        7 = "Offline"
    }
    
    if ($statusMap.ContainsKey($StatusCode)) {
        return $statusMap[$StatusCode]
    }
    return "Unknown ($StatusCode)"
}

function Get-DetailedPrinterStatus {
    param([int]$DetectedErrorState)
    
    $errors = @()
    
    if ($DetectedErrorState -band 1) { $errors += "Unknown" }
    if ($DetectedErrorState -band 2) { $errors += "Paper Low" }
    if ($DetectedErrorState -band 4) { $errors += "No Paper" }
    if ($DetectedErrorState -band 8) { $errors += "Toner Low" }
    if ($DetectedErrorState -band 16) { $errors += "No Toner" }
    if ($DetectedErrorState -band 32) { $errors += "Door Open" }
    if ($DetectedErrorState -band 64) { $errors += "Paper Jam" }
    if ($DetectedErrorState -band 128) { $errors += "Offline" }
    if ($DetectedErrorState -band 256) { $errors += "Service Requested" }
    if ($DetectedErrorState -band 512) { $errors += "Output Bin Full" }
    
    if ($errors.Count -eq 0) {
        return "No Errors"
    }
    
    return $errors -join ", "
}

#endregion

#region Status Monitoring

function Get-PrinterStatus {
    <#
    .SYNOPSIS
        Gets detailed status information for a printer
    
    .PARAMETER PrinterName
        Name of the printer
    
    .PARAMETER ComputerName
        Print server name
    
    .EXAMPLE
        Get-PrinterStatus -PrinterName "HP-Floor2"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName -ErrorAction Stop
        $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName |
            Where-Object { $_.Name -eq $PrinterName }
        
        # Get port information
        $port = Get-PrinterPort -Name $printer.PortName -ComputerName $ComputerName -ErrorAction SilentlyContinue
        
        # Get print jobs
        $jobs = Get-PrintJob -PrinterName $PrinterName -ComputerName $ComputerName -ErrorAction SilentlyContinue
        
        $status = [PSCustomObject]@{
            Name = $printer.Name
            ComputerName = $ComputerName
            ShareName = $printer.ShareName
            DriverName = $printer.DriverName
            PortName = $printer.PortName
            IPAddress = $port.PrinterHostAddress
            Location = $printer.Location
            Comment = $printer.Comment
            
            # Status
            PrinterStatus = Get-PrinterStatusText -StatusCode $wmiPrinter.PrinterStatus
            PrinterStatusCode = $wmiPrinter.PrinterStatus
            ExtendedPrinterStatus = $wmiPrinter.ExtendedPrinterStatus
            DetectedErrorState = $wmiPrinter.DetectedErrorState
            ErrorDescription = Get-DetailedPrinterStatus -DetectedErrorState $wmiPrinter.DetectedErrorState
            
            # Flags
            IsShared = $printer.Shared
            IsPublished = $printer.Published
            IsDefault = $wmiPrinter.Default
            WorkOffline = $wmiPrinter.WorkOffline
            
            # Queue
            JobCount = ($jobs | Measure-Object).Count
            QueuedJobs = $jobs
            
            # Connectivity
            IsOnline = $null
            ResponseTime = $null
            
            LastChecked = Get-Date
        }
        
        # Test connectivity if IP available
        if ($status.IPAddress) {
            $ping = Test-Connection -ComputerName $status.IPAddress -Count 1 -ErrorAction SilentlyContinue
            $status.IsOnline = $null -ne $ping
            $status.ResponseTime = if ($ping) { $ping.ResponseTime } else { $null }
        }
        
        return $status
    }
    catch {
        Write-Log "Failed to get printer status: $_" -Level Error
        return $null
    }
}

function Get-AllPrinterStatus {
    <#
    .SYNOPSIS
        Gets status for all printers on a server
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$ProblemsOnly
    )
    
    Write-Log "Getting status for all printers on $ComputerName..." -Level Info
    
    $printers = Get-Printer -ComputerName $ComputerName
    $results = @()
    
    foreach ($printer in $printers) {
        $status = Get-PrinterStatus -PrinterName $printer.Name -ComputerName $ComputerName
        
        if ($status) {
            # Add health assessment
            $status | Add-Member -NotePropertyName HealthStatus -NotePropertyValue "Healthy"
            $status | Add-Member -NotePropertyName Issues -NotePropertyValue @()
            
            $issues = @()
            
            # Check for problems
            if ($status.PrinterStatusCode -notin @(3, 4, 5)) {
                $issues += "Status: $($status.PrinterStatus)"
                $status.HealthStatus = "Warning"
            }
            
            if ($status.DetectedErrorState -gt 0 -and $status.
