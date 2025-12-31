<#
.SYNOPSIS
    Disk Space Monitor - Comprehensive disk space monitoring and alerting solution.

.DESCRIPTION
    This script provides comprehensive disk space monitoring capabilities including:
    - Multi-computer disk space monitoring
    - Warning and critical threshold alerts
    - Historical data tracking and trend analysis
    - Large file and folder detection
    - Cleanup recommendations
    - HTML/CSV reporting
    - Email notifications
    - Event log integration
    - Scheduled monitoring support

.PARAMETER ComputerName
    Target computer(s) to monitor. Defaults to localhost.

.PARAMETER WarningThreshold
    Disk usage percentage that triggers a warning. Default: 80

.PARAMETER CriticalThreshold
    Disk usage percentage that triggers a critical alert. Default: 90

.PARAMETER IncludeRemovable
    Include removable drives in monitoring.

.PARAMETER IncludeNetwork
    Include mapped network drives in monitoring.

.PARAMETER FindLargeFiles
    Scan for large files on drives exceeding threshold.

.PARAMETER LargeFileSize
    Minimum file size (in MB) to consider as "large". Default: 100

.PARAMETER TopFolders
    Number of largest folders to report. Default: 10

.PARAMETER OutputPath
    Path to save reports and historical data.

.PARAMETER HistoryDays
    Number of days to retain historical data. Default: 30

.PARAMETER SendEmail
    Enable email notifications for threshold breaches.

.PARAMETER SmtpServer
    SMTP server for email notifications.

.PARAMETER EmailTo
    Email recipient(s) for notifications.

.PARAMETER EmailFrom
    Email sender address.

.PARAMETER WriteEventLog
    Write alerts to Windows Event Log.

.PARAMETER Remediate
    Attempt automatic cleanup actions.

.EXAMPLE
    .\Disk-SpaceMonitor.ps1

.EXAMPLE
    .\Disk-SpaceMonitor.ps1 -ComputerName "Server01","Server02" -WarningThreshold 75 -CriticalThreshold 85

.EXAMPLE
    .\Disk-SpaceMonitor.ps1 -FindLargeFiles -OutputPath "C:\Reports" -SendEmail -SmtpServer "smtp.company.com"

.NOTES
    Author: System Administrator
    Version: 1.0.0
    Date: 2024
    Requires: PowerShell 5.1 or later
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias("CN", "Server", "Host")]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [ValidateRange(1, 99)]
    [int]$WarningThreshold = 80,

    [ValidateRange(1, 100)]
    [int]$CriticalThreshold = 90,

    [switch]$IncludeRemovable,

    [switch]$IncludeNetwork,

    [switch]$FindLargeFiles,

    [ValidateRange(1, 10000)]
    [int]$LargeFileSize = 100,

    [ValidateRange(1, 100)]
    [int]$TopFolders = 10,

    [string]$OutputPath,

    [ValidateRange(1, 365)]
    [int]$HistoryDays = 30,

    [switch]$SendEmail,

    [string]$SmtpServer,

    [string[]]$EmailTo,

    [string]$EmailFrom = "diskmonitor@$($env:USERDNSDOMAIN)",

    [switch]$WriteEventLog,

    [switch]$Remediate
)

#region Initialization
$ErrorActionPreference = "Continue"
$Script:Timestamp = Get-Date
$Script:ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:DiskResults = @()
$Script:Alerts = @()
$Script:LargeFiles = @()
$Script:LargeFolders = @()
$Script:CleanupRecommendations = @()

# Drive type mapping
$Script:DriveTypes = @{
    0 = "Unknown"
    1 = "No Root Directory"
    2 = "Removable Disk"
    3 = "Local Disk"
    4 = "Network Drive"
    5 = "Compact Disc"
    6 = "RAM Disk"
}

# Common cleanup locations
$Script:CleanupPaths = @(
    @{ Path = '$env:TEMP'; Description = "User Temp Files" },
    @{ Path = '$env:SystemRoot\Temp'; Description = "System Temp Files" },
    @{ Path = '$env:SystemRoot\SoftwareDistribution\Download'; Description = "Windows Update Cache" },
    @{ Path = '$env:LOCALAPPDATA\Microsoft\Windows\INetCache'; Description = "Internet Cache" },
    @{ Path = '$env:SystemRoot\Logs'; Description = "Windows Logs" },
    @{ Path = 'C:\$Recycle.Bin'; Description = "Recycle Bin" }
)

# Console colors
$Script:Colors = @{
    Header   = "Cyan"
    Success  = "Green"
    Warning  = "Yellow"
    Error    = "Red"
    Info     = "White"
    Muted    = "DarkGray"
}
#endregion

#region Helper Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Header", "Muted")]
        [string]$Level = "Info",
        [switch]$NoNewline
    )
    
    $color = $Script:Colors[$Level]
    $prefix = switch ($Level) {
        "Success" { "[✓]" }
        "Warning" { "[!]" }
        "Error"   { "[✗]" }
        "Header"  { "[*]" }
        default   { "[i]" }
    }
    
    if ($Level -eq "Header") {
        Write-Host ""
        Write-Host "$prefix $Message" -ForegroundColor $color
        Write-Host ("=" * ($Message.Length + 4)) -ForegroundColor $color
    }
    else {
        $params = @{
            Object = "$prefix $Message"
            ForegroundColor = $color
            NoNewline = $NoNewline
        }
        Write-Host @params
    }
}

function Format-Size {
    param([double]$Bytes)
    
    $sizes = @("Bytes", "KB", "MB", "GB", "TB", "PB")
    $index = 0
    $size = $Bytes
    
    while ($size -ge 1024 -and $index -lt $sizes.Count - 1) {
        $size /= 1024
        $index++
    }
    
    return "{0:N2} {1}" -f $size, $sizes[$index]
}

function Get-DiskStatus {
    param([double]$UsagePercent)
    
    if ($UsagePercent -ge $CriticalThreshold) {
        return "Critical"
    }
    elseif ($UsagePercent -ge $WarningThreshold) {
        return "Warning"
    }
    else {
        return "Healthy"
    }
}

function Get-StatusColor {
    param([string]$Status)
    
    switch ($Status) {
        "Critical" { return "Red" }
        "Warning"  { return "Yellow" }
        "Healthy"  { return "Green" }
        default    { return "White" }
    }
}

function Test-RemoteAccess {
    param([string]$Computer)
    
    if ($Computer -eq $env:COMPUTERNAME -or $Computer -eq "localhost" -or $Computer -eq ".") {
        return $true
    }
    
    try {
        $result = Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction Stop
        return $result
    }
    catch {
        return $false
    }
}

function Write-EventLogEntry {
    param(
        [string]$Message,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$EntryType = "Information",
        [int]$EventId = 1000
    )
    
    if (-not $WriteEventLog) { return }
    
    $logName = "Application"
    $source = "DiskSpaceMonitor"
    
    try {
        # Create event source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            [System.Diagnostics.EventLog]::CreateEventSource($source, $logName)
        }
        
        Write-EventLog -LogName $logName -Source $source -EventId $EventId -EntryType $EntryType -Message $Message
    }
    catch {
        Write-Log "Failed to write to Event Log: $_" -Level Warning
    }
}
#endregion

#region Disk Monitoring Functions
function Get-DiskInformation {
    param([string]$Computer)
    
    Write-Log "Retrieving disk information from $Computer..." -Level Info
    
    try {
        # Build drive type filter
        $driveTypes = @(3)  # Always include local disks
        if ($IncludeRemovable) { $driveTypes += 2 }
        if ($IncludeNetwork) { $driveTypes += 4 }
        
        $filter = "DriveType=" + ($driveTypes -join " OR DriveType=")
        
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Computer -Filter $filter -ErrorAction Stop
        
        $diskInfo = @()
        
        foreach ($disk in $disks) {
            if ($disk.Size -eq 0 -or $null -eq $disk.Size) { continue }
            
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB = [math]::Round($totalGB - $freeGB, 2)
            $usagePercent = [math]::Round(($usedGB / $totalGB) * 100, 2)
            $freePercent = [math]::Round(100 - $usagePercent, 2)
            
            $status = Get-DiskStatus -UsagePercent $usagePercent
            
            $diskData = [PSCustomObject]@{
                Timestamp       = $Script:Timestamp
                ComputerName    = $Computer
                DriveLetter     = $disk.DeviceID
                VolumeName      = $disk.VolumeName
                DriveType       = $Script:DriveTypes[$disk.DriveType]
                FileSystem      = $disk.FileSystem
                TotalSizeGB     = $totalGB
                UsedSpaceGB     = $usedGB
                FreeSpaceGB     = $freeGB
                UsagePercent    = $usagePercent
                FreePercent     = $freePercent
                Status          = $status
                TotalSizeBytes  = $disk.Size
                FreeSpaceBytes  = $disk.FreeSpace
            }
            
            $diskInfo += $diskData
            $Script:DiskResults += $diskData
            
            # Create alert if threshold exceeded
            if ($status -ne "Healthy") {
                $alert = [PSCustomObject]@{
                    Timestamp    = $Script:Timestamp
                    ComputerName = $Computer
                    DriveLetter  = $disk.DeviceID
                    Status       = $status
                    UsagePercent = $usagePercent
                    FreeSpaceGB  = $freeGB
                    Message      = "$Computer - Drive $($disk.DeviceID) is at $usagePercent% capacity ($freeGB GB free)"
                }
                $Script:Alerts += $alert
            }
        }
        
        return $diskInfo
    }
    catch {
        Write-Log "Failed to retrieve disk information from $Computer : $_" -Level Error
        return $null
    }
}

function Show-DiskStatus {
    param([array]$DiskInfo)
    
    if ($null -eq $DiskInfo -or $DiskInfo.Count -eq 0) { return }
    
    foreach ($disk in $DiskInfo) {
        $statusColor = Get-StatusColor -Status $disk.Status
        $barLength = 40
        $filledLength = [math]::Round(($disk.UsagePercent / 100) * $barLength)
        $emptyLength = $barLength - $filledLength
        
        $progressBar = "[" + ("█" * $filledLength) + ("░" * $emptyLength) + "]"
        
        Write-Host ""
        Write-Host "  Drive: " -NoNewline -ForegroundColor White
        Write-Host "$($disk.DriveLetter)" -NoNewline -ForegroundColor Cyan
        if ($disk.VolumeName) {
            Write-Host " ($($disk.VolumeName))" -NoNewline -ForegroundColor DarkGray
        }
        Write-Host " - $($disk.DriveType)" -ForegroundColor DarkGray
        
        Write-Host "  $progressBar " -NoNewline -ForegroundColor $statusColor
        Write-Host "$($disk.UsagePercent)%" -NoNewline -ForegroundColor $statusColor
        Write-Host " used" -ForegroundColor DarkGray
        
        Write-Host "  Total: $($disk.TotalSizeGB) GB | " -NoNewline -ForegroundColor DarkGray
        Write-Host "Used: $($disk.UsedSpaceGB) GB | " -NoNewline -ForegroundColor DarkGray
        Write-Host "Free: $($disk.FreeSpaceGB) GB" -ForegroundColor DarkGray
        
        Write-Host "  Status: " -NoNewline -ForegroundColor DarkGray
        Write-Host $disk.Status -ForegroundColor $statusColor
    }
}

function Find-LargeFiles {
    param(
        [string]$Computer,
        [string]$DriveLetter
    )
    
    Write-Log "Scanning for large files on $Computer $DriveLetter (>$LargeFileSize MB)..." -Level Info
    
    try {
        $minSize = $LargeFileSize * 1MB
        $path = if ($Computer -eq $env:COMPUTERNAME) {
            "$DriveLetter\"
        }
        else {
            "\\$Computer\$($DriveLetter.Replace(':', '$'))\"
        }
        
        # Exclude certain system directories for performance
        $excludePaths = @(
            '*\Windows\WinSxS\*',
            '*\Windows\Installer\*',
            '*\$Recycle.Bin\*'
        )
        
        $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { 
                $_.Length -ge $minSize -and
                $excludePaths | ForEach-Object { $_.FullName -notlike $_ }
            } |
            Sort-Object Length -Descending |
            Select-Object -First 20
        
        foreach ($file in $files) {
            $Script:LargeFiles += [PSCustomObject]@{
                ComputerName = $Computer
                DriveLetter  = $DriveLetter
                FileName     = $file.Name
                FullPath     = $file.FullName
                SizeBytes    = $file.Length
                SizeFormatted = Format-Size -Bytes $file.Length
                LastModified = $file.LastWriteTime
                Extension    = $file.Extension
                Age          = ((Get-Date) - $file.LastWriteTime).Days
            }
        }
        
        Write-Log "Found $($files.Count) large files on $DriveLetter" -Level Success
    }
    catch {
        Write-Log "Error scanning for large files: $_" -Level Warning
    }
}

function Get-LargeFolders {
    param(
        [string]$Computer,
        [string]$DriveLetter
    )
    
    Write-Log "Analyzing folder sizes on $Computer $DriveLetter..." -Level Info
    
    try {
        $path = if ($Computer -eq $env:COMPUTERNAME) {
            "$DriveLetter\"
        }
        else {
            "\\$Computer\$($DriveLetter.Replace(':', '$'))\"
        }
        
        # Get top-level folders
        $folders = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^\$|^System Volume Information$' }
        
        $folderSizes = @()
        $totalFolders = $folders.Count
        $current = 0
        
        foreach ($folder in $folders) {
            $current++
            Write-Progress -Activity "Calculating folder sizes" -Status $folder.Name -PercentComplete (($current / $totalFolders) * 100)
            
            try {
                $size = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                
                if ($null -eq $size) { $size = 0 }
                
                $folderSizes += [PSCustomObject]@{
                    ComputerName  = $Computer
                    DriveLetter   = $DriveLetter
                    FolderName    = $folder.Name
                    FullPath      = $folder.FullName
                    SizeBytes     = $size
                    SizeFormatted = Format-Size -Bytes $size
                    ItemCount     = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
                }
            }
            catch {
                continue
            }
        }
        
        Write-Progress -Activity "Calculating folder sizes" -Completed
        
        $topFolders = $folderSizes | Sort-Object SizeBytes -Descending | Select-Object -First $TopFolders
        $Script:LargeFolders += $topFolders
        
        return $topFolders
    }
    catch {
        Write-Log "Error analyzing folders: $_" -Level Warning
    }
}

function Get-CleanupRecommendations {
    param(
        [string]$Computer,
        [string]$DriveLetter
    )
    
    Write-Log "Generating cleanup recommendations for $Computer $DriveLetter..." -Level Info
    
    $recommendations = @()
    
    foreach ($location in $Script:CleanupPaths) {
        try {
            $expandedPath = $ExecutionContext.InvokeCommand.ExpandString($location.Path)
            
            # Adjust path for remote computers
            if ($Computer -ne $env:COMPUTERNAME) {
                $expandedPath = "\\$Computer\$($expandedPath.Replace(':', '$'))"
            }
            
            # Only check paths on the target drive
            if ($expandedPath -notlike "$DriveLetter*" -and $Computer -eq $env:COMPUTERNAME) {
                continue
            }
            
            if (Test-Path $expandedPath -ErrorAction SilentlyContinue) {
                $files = Get-ChildItem -Path $expandedPath -Recurse -File -ErrorAction SilentlyContinue
                $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
                $fileCount = $files.Count
                
                if ($totalSize -gt 0) {
                    $recommendations += [PSCustomObject]@{
                        ComputerName    = $Computer
                        DriveLetter     = $DriveLetter
                        Description     = $location.Description
                        Path            = $expandedPath
                        SizeBytes       = $totalSize
                        SizeFormatted   = Format-Size -Bytes $totalSize
                        FileCount       = $fileCount
                        CanAutoClean    = $true
                    }
                }
            }
        }
        catch {
            continue
        }
    }
    
    # Check for old user profiles (Windows only)
    if ($DriveLetter -eq "C:") {
        try {
            $profilePath = if ($Computer -eq $env:COMPUTERNAME) {
                "C:\Users"
            }
            else {
                "\\$Computer\C$\Users"
            }
            
            $oldProfiles = Get-ChildItem -Path $profilePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.Name -notmatch '^(Default|Public|Default User|All Users)$' -and
                    $_.LastWriteTime -lt (Get-Date).AddDays(-90)
                }
            
            foreach ($profile in $oldProfiles) {
                $size = (Get-ChildItem -Path $profile.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                
                if ($size -gt 100MB) {
                    $recommendations += [PSCustomObject]@{
                        ComputerName    = $Computer
                        DriveLetter     = $DriveLetter
                        Description     = "Old User Profile: $($profile.Name)"
                        Path            = $profile.FullName
                        SizeBytes       = $size
                        SizeFormatted   = Format-Size -Bytes $size
                        FileCount       = 0
                        CanAutoClean    = $false
                        LastAccess      = $profile.LastWriteTime
                    }
                }
            }
        }
        catch {
            # Ignore errors for profile enumeration
        }
    }
    
    # Check Windows.old folder
    $windowsOldPath = if ($Computer -eq $env:COMPUTERNAME) {
        "C:\Windows.old"
    }
    else {
        "\\$Computer\C$\Windows.old"
    }
    
    if (Test-Path $windowsOldPath -ErrorAction SilentlyContinue) {
        try {
            $size = (Get-ChildItem -Path $windowsOldPath -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            
            $recommendations += [PSCustomObject]@{
                ComputerName    = $Computer
                DriveLetter     = "C:"
                Description     = "Windows.old (Previous Installation)"
                Path            = $windowsOldPath
                SizeBytes       = $size
                SizeFormatted   = Format-Size -Bytes $size
                FileCount       = 0
                CanAutoClean    = $false
            }
        }
        catch {
            # Ignore errors
        }
    }
    
    $Script:CleanupRecommendations += $recommendations
    
    return $recommendations | Sort-Object SizeBytes -Descending
}

function Invoke-DiskCleanup {
    param([string]$Computer)
    
    if (-not $Remediate) { return }
    
    Write-Log "Initiating disk cleanup on $Computer..." -Level Header
    
    $cleanedSize = 0
    
    # Clean temp files
    $tempPaths = @(
        @{ Path = '$env:TEMP'; Description = "User Temp" },
        @{ Path = '$env:SystemRoot\Temp'; Description = "System Temp" }
    )
    
    foreach ($temp in $tempPaths) {
        $expandedPath = $ExecutionContext.InvokeCommand.ExpandString($temp.Path)
        
        if ($PSCmdlet.ShouldProcess($expandedPath, "Clean temporary files")) {
            try {
                $files = Get-ChildItem -Path $expandedPath -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
                
                $sizeToClean = ($files | Measure-Object -Property Length -Sum).Sum
                
                $files | Remove-Item -Force -ErrorAction SilentlyContinue
                
                $cleanedSize += $sizeToClean
                Write-Log "Cleaned $($temp.Description): $(Format-Size -Bytes $sizeToClean)" -Level Success
            }
            catch {
                Write-Log "Error cleaning $($temp.Description): $_" -Level Warning
            }
        }
    }
    
    # Clear Windows Update cache (requires admin)
    if ($PSCmdlet.ShouldProcess("Windows Update Cache", "Clear cache")) {
        try {
            $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $wuPath) {
                # Stop Windows Update service
                Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                
                $files = Get-ChildItem -Path $wuPath -Recurse -File -ErrorAction SilentlyContinue
                $sizeToClean = ($files | Measure-Object -Property Length -Sum).Sum
                
                Remove-Item -Path "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                
                # Restart Windows Update service
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
                
                $cleanedSize += $sizeToClean
                Write-Log "Cleaned Windows Update cache: $(Format-Size -Bytes $sizeToClean)" -Level Success
            }
        }
        catch {
            Write-Log "Error cleaning Windows Update cache: $_" -Level Warning
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }
    }
    
    # Empty Recycle Bin
    if ($PSCmdlet.ShouldProcess("Recycle Bin", "Empty")) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.NameSpace(0xa)
            $recycleBinSize = ($recycleBin.Items() | ForEach-Object { $recycleBin.GetDetailsOf($_, 2) })
            
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Log "Emptied Recycle Bin" -Level Success
        }
        catch {
            Write-Log "Error emptying Recycle Bin: $_" -Level Warning
        }
    }
    
    Write-Log "Total space recovered: $(Format-Size -Bytes $cleanedSize)" -Level Success
    
    return $cleanedSize
}
#endregion

#region History and Trending
function Save-HistoricalData {
    param([string]$Path)
    
    if ([string]::IsNullOrEmpty($Path)) { return }
    
    $historyFile = Join-Path $Path "DiskSpace_History.csv"
    
    try {
        # Append current results to history
        if (Test-Path $historyFile) {
            $Script:DiskResults | Export-Csv -Path $historyFile -Append -NoTypeInformation
        }
        else {
            $Script:DiskResults | Export-Csv -Path $historyFile -NoTypeInformation
        }
        
        # Clean up old entries
        $history = Import-Csv -Path $historyFile
        $cutoffDate = (Get-Date).AddDays(-$HistoryDays)
        $history = $history | Where-Object { [DateTime]$_.Timestamp -ge $cutoffDate }
        $history | Export-Csv -Path $historyFile -NoTypeInformation
        
        Write-Log "Historical data saved to $historyFile" -Level Success
    }
    catch {
        Write-Log "Error saving historical data: $_" -Level Warning
    }
}

function Get-DiskTrend {
    param(
        [string]$Path,
        [string]$Computer,
        [string]$DriveLetter
    )
    
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    
    $historyFile = Join-Path $Path "DiskSpace_History.csv"
    
    if (-not (Test-Path $historyFile)) { return $null }
    
    try {
        $history = Import-Csv -Path $historyFile |
            Where-Object { $_.ComputerName -eq $Computer -and $_.DriveLetter -eq $DriveLetter } |
            Sort-Object { [DateTime]$_.Timestamp }
        
        if ($history.Count -lt 2) { return $null }
        
        $oldest = $history | Select-Object -First 1
        $newest = $history | Select-Object -Last 1
        
        $daysDiff = ([DateTime]$newest.Timestamp - [DateTime]$oldest.Timestamp).TotalDays
        if ($daysDiff -eq 0) { $daysDiff = 1 }
        
        $usedDiff = [double]$newest.UsedSpaceGB - [double]$oldest.UsedSpaceGB
        $dailyRate = $usedDiff / $daysDiff
        
        # Estimate days until full
        $freeSpace = [double]$newest.FreeSpaceGB
        $daysUntilFull = if ($dailyRate -gt 0) { [math]::Round($freeSpace / $dailyRate) } else { -1 }
        
        return [PSCustomObject]@{
            DailyGrowthGB   = [math]::Round($dailyRate, 2)
            WeeklyGrowthGB  = [math]::Round($dailyRate * 7, 2)
            MonthlyGrowthGB = [math]::Round($dailyRate * 30, 2)
            DaysUntilFull   = $daysUntilFull
            TrendDirection  = if ($dailyRate -gt 0) { "Increasing" } elseif ($dailyRate -lt 0) { "Decreasing" } else { "Stable" }
            DataPoints      = $history.Count
        }
    }
    catch {
        return $null
    }
}
#endregion

#region Report Generation
function New-HtmlReport {
    $statusSummary = @{
        Healthy  = ($Script:DiskResults | Where-Object { $_.Status -eq "Healthy" }).Count
        Warning  = ($Script:DiskResults | Where-Object { $_.Status -eq "Warning" }).Count
        Critical = ($Script:DiskResults | Where-Object { $_.Status -eq "Critical" }).Count
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
    <title>Disk Space Monitor Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #1a1a2e; color: #eee; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; border-radius: 15px; margin-bottom: 20px; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; }
        .status-badge { display: inline-block; padding: 8px 20px; border-radius: 20px; font-weight: bold; margin-top: 15px; background: $statusColor; color: white; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .card { background: #16213e; border-radius: 10px; padding: 20px; text-align: center; }
        .card h3 { color: #888; font-size: 0.9em; margin-bottom: 10px; }
        .card .value { font-size: 2.5em; font-weight: bold; }
        .card.healthy .value { color: #28a745; }
        .card.warning .value { color: #ffc107; }
        .card.critical .value { color: #dc3545; }
        .section { background: #16213e; border-radius: 10px; padding: 20px; margin-bottom: 20px; }
        .section h2 { color: #667eea; margin-bottom: 15px; border-bottom: 1px solid #333; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #0f3460; color: #fff; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #333; }
        tr:hover { background: #1f4068; }
        .status-healthy { color: #28a745; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        .status-critical { color: #dc3545; font-weight: bold; }
        .progress-bar { background: #333; border-radius: 10px; height: 20px; overflow: hidden; }
        .progress-fill { height: 100%; transition: width 0.3s; }
        .progress-healthy { background: linear-gradient(90deg, #28a745, #20c997); }
        .progress-warning { background: linear-gradient(90deg, #ffc107, #fd7e14); }
        .progress-critical { background: linear-gradient(90deg, #dc3545, #c82333); }
        .alert-box { padding: 15px; border-radius: 8px; margin-bottom: 10px; }
        .alert-warning { background: rgba(255, 193, 7, 0.2); border-left: 4px solid #ffc107; }
        .alert-critical { background: rgba(220, 53, 69, 0.2); border-left: 4px solid #dc3545; }
        .footer { text-align: center; padding: 20px; color: #666; }
        .trend-up { color: #dc3545; }
        .trend-down { color: #28a745; }
        .trend-stable { color: #ffc107; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>💾 Disk Space Monitor Report</h1>
            <p>Generated: $($Script:Timestamp.ToString("yyyy-MM-dd HH:mm:ss"))</p>
            <p>Computers Monitored: $($ComputerName -join ", ")</p>
            <span class="status-badge">Overall Status: $overallStatus</span>
        </div>
        
        <div class="summary-cards">
            <div class="card healthy">
                <h3>HEALTHY</h3>
                <div class="value">$($statusSummary.Healthy)</div>
            </div>
            <div class="card warning">
                <h3>WARNING</h3>
                <div class="value">$($statusSummary.Warning)</div>
            </div>
            <div class="card critical">
                <h3>CRITICAL</h3>
                <div class="value">$($statusSummary.Critical)</div>
            </div>
            <div class="card">
                <h3>TOTAL DRIVES</h3>
                <div class="value" style="color: #667eea;">$($Script:DiskResults.Count)</div>
            </div>
        </div>
"@

    # Alerts Section
    if ($Script:Alerts.Count -gt 0) {
        $html += @"
        <div class="section">
            <h2>⚠️ Active Alerts</h2>
"@
        foreach ($alert in $Script:Alerts) {
            $alertClass = if ($alert.Status -eq "Critical") { "alert-critical" } else { "alert-warning" }
            $html += @"
            <div class="alert-box $alertClass">
                <strong>$($alert.Status.ToUpper())</strong> - $($alert.Message)
            </div>
"@
        }
        $html += "</div>"
    }

    # Disk Status Table
    $html += @"
        <div class="section">
            <h2>📊 Disk Status Overview</h2>
            <table>
                <thead>
                    <tr>
                        <th>Computer</th>
                        <th>Drive</th>
                        <th>Volume</th>
                        <th>Total</th>
                        <th>Used</th>
                        <th>Free</th>
                        <th>Usage</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
"@
    
    foreach ($disk in $Script:DiskResults) {
        $progressClass = "progress-" + $disk.Status.ToLower()
        $statusClass = "status-" + $disk.Status.ToLower()
        
        $html += @"
                    <tr>
                        <td>$($disk.ComputerName)</td>
                        <td>$($disk.DriveLetter)</td>
                        <td>$($disk.VolumeName)</td>
                        <td>$($disk.TotalSizeGB) GB</td>
                        <td>$($disk.UsedSpaceGB) GB</td>
                        <td>$($disk.FreeSpaceGB) GB</td>
                        <td>
                            <div class="progress-bar">
                                <div class="progress-fill $progressClass" style="width: $($disk.UsagePercent)%;"></div>
                            </div>
                            <small>$($disk.UsagePercent)%</small>
                        </td>
                        <td class="$statusClass">$($disk.Status)</td>
                    </tr>
"@
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
"@

    # Large Files Section
    if ($Script:LargeFiles.Count -gt 0) {
        $html += @"
        <div class="section">
            <h2>📁 Large Files Detected</h2>
            <table>
                <thead>
                    <tr>
                        <th>Computer</th>
                        <th>Drive</th>
                        <th>File Name</th>
                        <th>Size</th>
                        <th>Age (Days)</th>
                        <th>Path</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($file in ($Script:LargeFiles | Select-Object -First 20)) {
            $html += @"
                    <tr>
                        <td>$($file.ComputerName)</td>
                        <td>$($file.DriveLetter)</td>
                        <td>$($file.FileName)</td>
                        <td>$($file.SizeFormatted)</td>
                        <td>$($file.Age)</td>
                        <td style="font-size: 0.85em;">$($file.FullPath)</td>
                    </tr>
"@
        }
        $html += "</tbody></table></div>"
    }

    # Cleanup Recommendations
    if ($Script:CleanupRecommendations.Count -gt 0) {
        $totalPotentialSavings = ($Script:CleanupRecommendations | Measure-Object -Property SizeBytes -Sum).Sum
        
        $html += @"
        <div class="section">
            <h2>🧹 Cleanup Recommendations</h2>
            <p style="margin-bottom: 15px;">Potential space savings: <strong>$(Format-Size -Bytes $totalPotentialSavings)</strong></p>
            <table>
                <thead>
                    <tr>
                        <th>Computer</th>
                        <th>Description</th>
                        <th>Size</th>
                        <th>Files</th>
                        <th>Path</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($rec in ($Script:CleanupRecommendations | Sort-Object SizeBytes -Descending)) {
            $html += @"
                    <tr>
                        <td>$($rec.ComputerName)</td>
                        <td>$($rec.Description)</td>
                        <td>$($rec.SizeFormatted)</td>
                        <td>$($rec.FileCount)</td>
                        <td style="font-size: 0.85em;">$($rec.Path)</td>
                    </tr>
"@
        }
        $html += "</tbody></table></div>"
    }

    # Footer
    $html += @"
        <div class="footer">
            <p>Disk Space Monitor v1.0.0 | Report generated by PowerShell</p>
            <p>Thresholds: Warning at ${WarningThreshold}% | Critical at ${CriticalThreshold}%</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

function Send-EmailNotification {
    if (-not $SendEmail) { return }
    
    if ([string]::IsNullOrEmpty($SmtpServer) -or $null -eq $EmailTo -or $EmailTo.Count -eq 0) {
        Write-Log "Email configuration incomplete. Skipping notification." -Level Warning
        return
    }
    
    $criticalCount = ($Script:Alerts | Where-Object { $_.Status -eq "Critical" }).Count
    $warningCount = ($Script:Alerts | Where-Object { $_.Status -eq "Warning" }).Count
    
    $priority = if ($criticalCount -gt 0) { "High" } else { "Normal" }
    $statusText = if ($criticalCount -gt 0) { "CRITICAL" } elseif ($warningCount -gt 0) { "WARNING" } else { "OK" }
    
    $subject = "[$statusText] Disk Space Alert - $($ComputerName -join ', ')"
    
    try {
        $htmlReport = New-HtmlReport
        
        $mailParams = @{
            From       = $EmailFrom
            To         = $EmailTo
            Subject    = $subject
            Body       = $htmlReport
            BodyAsHtml = $true
            SmtpServer = $SmtpServer
            Priority   = $priority
        }
        
        Send-MailMessage @mailParams
        Write-Log "Email notification sent to: $($EmailTo -join ', ')" -Level Success
    }
    catch {
        Write-Log "Failed to send email notification: $_" -Level Error
    }
}
#endregion

#region Main Execution
function Start-DiskMonitor {
    # Display header
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    DISK SPACE MONITOR v1.0.0                      ║" -ForegroundColor Cyan
    Write-Host "║                     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Warning Threshold: $WarningThreshold% | Critical Threshold: $CriticalThreshold%" -ForegroundColor DarkGray
    Write-Host "  Target Computers: $($ComputerName -join ', ')" -ForegroundColor DarkGray
    Write-Host ""
    
    # Process each computer
    foreach ($computer in $ComputerName) {
        Write-Log "Processing: $computer" -Level Header
        
        # Check connectivity
        if (-not (Test-RemoteAccess -Computer $computer)) {
            Write-Log "Cannot connect to $computer - skipping" -Level Error
            continue
        }
        
        # Get disk information
        $diskInfo = Get-DiskInformation -Computer $computer
        
        if ($null -eq $diskInfo) {
            Write-Log "No disk information retrieved from $computer" -Level Warning
            continue
        }
        
        # Display disk status
        Show-DiskStatus -DiskInfo $diskInfo
        
        # Process drives that exceed thresholds
        $problemDrives = $diskInfo | Where-Object { $_.Status -ne "Healthy" }
        
        foreach ($drive in $problemDrives) {
            Write-Host ""
            
            # Find large files if requested
            if ($FindLargeFiles) {
                Find-LargeFiles -Computer $computer -DriveLetter $drive.DriveLetter
            }
            
            # Get folder analysis
            Get-LargeFolders -Computer $computer -DriveLetter $drive.DriveLetter | Out-Null
            
            # Get cleanup recommendations
            Get-CleanupRecommendations -Computer $computer -DriveLetter $drive.DriveLetter | Out-Null
            
            # Show trend if history exists
            if (-not [string]::IsNullOrEmpty($OutputPath)) {
                $trend = Get-DiskTrend -Path $OutputPath -Computer $computer -DriveLetter $drive.DriveLetter
                if ($null -ne $trend -and $trend.DaysUntilFull -gt 0) {
                    Write-Host ""
                    Write-Log "Trend Analysis for $($drive.DriveLetter):" -Level Info
                    Write-Host "    Daily Growth: $($trend.DailyGrowthGB) GB" -ForegroundColor DarkGray
                    Write-Host "    Days Until Full: $($trend.DaysUntilFull)" -ForegroundColor $(if ($trend.DaysUntilFull -lt 30) { "Red" } elseif ($trend.DaysUntilFull -lt 90) { "Yellow" } else { "Green" })
                }
            }
            
            # Write to Event Log
            if ($drive.Status -eq "Critical") {
                Write-EventLogEntry -Message "Critical: Disk $($drive.DriveLetter) on $computer is at $($drive.UsagePercent)% capacity" `
                    -EntryType Error -EventId 1001
            }
            elseif ($drive.Status -eq "Warning") {
                Write-EventLogEntry -Message "Warning: Disk $($drive.DriveLetter) on $computer is at $($drive.UsagePercent)% capacity" `
                    -EntryType Warning -EventId 1002
            }
        }
        
        # Perform cleanup if requested
        if ($Remediate -and $problemDrives.Count -gt 0) {
            Invoke-DiskCleanup -Computer $computer
        }
    }
    
    # Display summary
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " MONITORING SUMMARY" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $healthyCount = ($Script:DiskResults | Where-Object { $_.Status -eq "Healthy" }).Count
    $warningCount = ($Script:DiskResults | Where-Object { $_.Status -eq "Warning" }).Count
    $criticalCount = ($Script:DiskResults | Where-Object { $_.Status -eq "Critical" }).Count
    
    Write-Host " Total Drives Monitored: $($Script:DiskResults.Count)" -ForegroundColor White
    Write-Host " Healthy: $healthyCount" -ForegroundColor Green
    Write-Host " Warning: $warningCount" -ForegroundColor Yellow
    Write-Host " Critical: $criticalCount" -ForegroundColor Red
    
    if ($Script:CleanupRecommendations.Count -gt 0) {
        $potentialSavings = ($Script:CleanupRecommendations | Measure-Object -Property SizeBytes -Sum).Sum
        Write-Host " Potential Space Savings: $(Format-Size -Bytes $potentialSavings)" -ForegroundColor Cyan
    }
    
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    # Save historical data and generate reports
    if (-not [string]::IsNullOrEmpty($OutputPath)) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Save history
        Save-HistoricalData -Path $OutputPath
        
        # Generate HTML report
        $reportFile = Join-Path $OutputPath "DiskSpace_$Script:ReportDate.html"
        $htmlReport = New-HtmlReport
        $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
        Write-Log "HTML Report: $reportFile" -Level Success
        
        # Generate CSV report
        $csvFile = Join-Path $OutputPath "DiskSpace_$Script:ReportDate.csv"
        $Script:DiskResults | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Log "CSV Report: $csvFile" -Level Success
        
        # Save large files report if any
        if ($Script:LargeFiles.Count -gt 0) {
            $largeFilesReport = Join-Path $OutputPath "LargeFiles_$Script:ReportDate.csv"
            $Script:LargeFiles | Export-Csv -Path $largeFilesReport -NoTypeInformation
            Write-Log "Large Files Report: $largeFilesReport" -Level Success
        }
        
        # Save cleanup recommendations if any
        if ($Script:CleanupRecommendations.Count -gt 0) {
            $cleanupReport = Join-Path $OutputPath "CleanupRecommendations_$Script:ReportDate.csv"
            $Script:CleanupRecommendations | Export-Csv -Path $cleanupReport -NoTypeInformation
            Write-Log "Cleanup Report: $cleanupReport" -Level Success
        }
    }
    
    # Send email notification if configured and there are alerts
    if ($SendEmail -and ($Script:Alerts.Count -gt 0 -or $Script:DiskResults.Count -gt 0)) {
        Send-EmailNotification
    }
    
    # Return results object
    return [PSCustomObject]@{
        Timestamp              = $Script:Timestamp
        ComputersMonitored     = $ComputerName
        TotalDrives            = $Script:DiskResults.Count
        HealthyDrives          = $healthyCount
        WarningDrives          = $warningCount
        CriticalDrives         = $criticalCount
        Alerts                 = $Script:Alerts
        DiskResults            = $Script:DiskResults
        LargeFiles             = $Script:LargeFiles
        LargeFolders           = $Script:LargeFolders
        CleanupRecommendations = $Script:CleanupRecommendations
    }
}

# Execute the monitor
Start-DiskMonitor
#endregion
