<#
.SYNOPSIS
    Active Directory Health Check Script
    
.DESCRIPTION
    Performs comprehensive health checks on Active Directory including:
    - Domain Controller connectivity and services
    - Replication status
    - DNS health
    - SYSVOL and NETLOGON share availability
    - FSMO role holders
    - Account lockouts and expiring passwords
    - Group Policy health
    
.PARAMETER DomainController
    Specific DC to check. If not specified, checks all DCs in the domain.
    
.PARAMETER ExportPath
    Path to export HTML report. Defaults to .\reports\

.PARAMETER SendEmail
    Switch to send email report

.PARAMETER EmailTo
    Email recipient(s) for the report

.PARAMETER CheckReplication
    Include replication health check (requires domain admin rights)

.PARAMETER CheckDNS
    Include DNS health check

.PARAMETER Detailed
    Generate detailed report with additional metrics

.EXAMPLE
    Start-ADHealthCheck
    Runs basic health check against all domain controllers
    
.EXAMPLE
    Start-ADHealthCheck -DomainController "DC01" -Detailed -ExportPath "C:\Reports"
    Runs detailed health check against DC01 and exports to specified path
    
.EXAMPLE
    Start-ADHealthCheck -SendEmail -EmailTo "admin@company.com"
    Runs health check and emails results

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Requires: ActiveDirectory module, appropriate AD permissions
#>

#Requires -Modules ActiveDirectory

#region Configuration
$script:Config = @{
    # Thresholds
    PasswordExpiryWarningDays = 14
    AccountLockoutThreshold = 5
    ReplicationLagWarningMinutes = 15
    DiskSpaceWarningPercent = 20
    EventLogHoursBack = 24
    
    # Services to check on DCs
    CriticalServices = @(
        'NTDS',           # Active Directory Domain Services
        'DNS',            # DNS Server
        'Netlogon',       # Net Logon
        'DFSR',           # DFS Replication
        'W32Time',        # Windows Time
        'KDC',            # Kerberos Key Distribution Center
        'ADWS'            # Active Directory Web Services
    )
    
    # Event IDs to watch for
    CriticalEventIDs = @{
        'Security' = @(4740, 4771, 4776)  # Lockouts, Kerberos failures
        'System' = @(1014, 7031, 7034)     # DNS, Service crashes
        'Directory Service' = @(1084, 1308, 2042)  # Replication issues
    }
    
    # Email settings (update as needed)
    SMTPServer = "smtp.company.com"
    EmailFrom = "adhealth@company.com"
}
#endregion

#region Helper Functions

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
    }
    $prefixes = @{
        'Info' = '[*]'
        'Warning' = '[!]'
        'Error' = '[X]'
        'Success' = '[✓]'
    }
    
    Write-Host "$timestamp $($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function Get-HealthStatus {
    param(
        [bool]$Condition,
        [string]$HealthyText = "Healthy",
        [string]$UnhealthyText = "Unhealthy"
    )
    
    if ($Condition) {
        return @{ Status = $HealthyText; IsHealthy = $true }
    } else {
        return @{ Status = $UnhealthyText; IsHealthy = $false }
    }
}

function Test-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Log "ActiveDirectory module not found. Please install RSAT tools." -Level Error
        return $false
    }
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Failed to import ActiveDirectory module: $_" -Level Error
        return $false
    }
}

#endregion

#region Domain Controller Checks

function Get-DomainControllerList {
    [CmdletBinding()]
    param(
        [string]$DomainController
    )
    
    try {
        if ($DomainController) {
            $dc = Get-ADDomainController -Identity $DomainController -ErrorAction Stop
            return @($dc)
        } else {
            $dcs = Get-ADDomainController -Filter * -ErrorAction Stop
            return $dcs
        }
    }
    catch {
        Write-Log "Failed to get domain controllers: $_" -Level Error
        return $null
    }
}

function Test-DCConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    $results = [PSCustomObject]@{
        ComputerName = $ComputerName
        Ping = $false
        PingLatency = $null
        WinRM = $false
        LDAP = $false
        RPC = $false
        SMB = $false
        OverallStatus = "Unknown"
    }
    
    # Ping test
    try {
        $ping = Test-Connection -ComputerName $ComputerName -Count 2 -Quiet -ErrorAction Stop
        $results.Ping = $ping
        if ($ping) {
            $pingResult = Test-Connection -ComputerName $ComputerName -Count 1 -ErrorAction SilentlyContinue
            $results.PingLatency = $pingResult.ResponseTime
        }
    }
    catch {
        $results.Ping = $false
    }
    
    # WinRM test
    try {
        $results.WinRM = Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null
        $results.WinRM = $true
    }
    catch {
        $results.WinRM = $false
    }
    
    # LDAP test (port 389)
    try {
        $ldapTest = New-Object System.Net.Sockets.TcpClient
        $ldapTest.Connect($ComputerName, 389)
        $results.LDAP = $ldapTest.Connected
        $ldapTest.Close()
    }
    catch {
        $results.LDAP = $false
    }
    
    # RPC test (port 135)
    try {
        $rpcTest = New-Object System.Net.Sockets.TcpClient
        $rpcTest.Connect($ComputerName, 135)
        $results.RPC = $rpcTest.Connected
        $rpcTest.Close()
    }
    catch {
        $results.RPC = $false
    }
    
    # SMB test (port 445)
    try {
        $smbTest = New-Object System.Net.Sockets.TcpClient
        $smbTest.Connect($ComputerName, 445)
        $results.SMB = $smbTest.Connected
        $smbTest.Close()
    }
    catch {
        $results.SMB = $false
    }
    
    # Overall status
    if ($results.Ping -and $results.LDAP -and $results.RPC) {
        $results.OverallStatus = "Healthy"
    } elseif ($results.Ping) {
        $results.OverallStatus = "Degraded"
    } else {
        $results.OverallStatus = "Offline"
    }
    
    return $results
}

function Test-DCServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    $serviceResults = @()
    
    foreach ($serviceName in $script:Config.CriticalServices) {
        try {
            $service = Get-Service -ComputerName $ComputerName -Name $serviceName -ErrorAction Stop
            
            $serviceResults += [PSCustomObject]@{
                ComputerName = $ComputerName
                ServiceName = $serviceName
                DisplayName = $service.DisplayName
                Status = $service.Status.ToString()
                StartType = $service.StartType.ToString()
                IsHealthy = ($service.Status -eq 'Running')
            }
        }
        catch {
            $serviceResults += [PSCustomObject]@{
                ComputerName = $ComputerName
                ServiceName = $serviceName
                DisplayName = $serviceName
                Status = "Not Found/Error"
                StartType = "Unknown"
                IsHealthy = $false
            }
        }
    }
    
    return $serviceResults
}

function Test-DCShares {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    $shareResults = @()
    $criticalShares = @('SYSVOL', 'NETLOGON')
    
    foreach ($share in $criticalShares) {
        $sharePath = "\\$ComputerName\$share"
        
        try {
            $accessible = Test-Path -Path $sharePath -ErrorAction Stop
            
            $shareResults += [PSCustomObject]@{
                ComputerName = $ComputerName
                ShareName = $share
                Path = $sharePath
                Accessible = $accessible
                IsHealthy = $accessible
            }
        }
        catch {
            $shareResults += [PSCustomObject]@{
                ComputerName = $ComputerName
                ShareName = $share
                Path = $sharePath
                Accessible = $false
                IsHealthy = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    return $shareResults
}

function Get-DCDiskSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    try {
        $disks = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $ComputerName -Filter "DriveType=3" -ErrorAction Stop
        
        $diskResults = foreach ($disk in $disks) {
            $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            
            [PSCustomObject]@{
                ComputerName = $ComputerName
                Drive = $disk.DeviceID
                SizeGB = [math]::Round($disk.Size / 1GB, 2)
                FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                FreePercent = $freePercent
                IsHealthy = ($freePercent -gt $script:Config.DiskSpaceWarningPercent)
            }
        }
        
        return $diskResults
    }
    catch {
        Write-Log "Failed to get disk space for $ComputerName : $_" -Level Warning
        return $null
    }
}

#endregion

#region Replication Checks

function Test-ADReplication {
    [CmdletBinding()]
    param()
    
    $replicationResults = @()
    
    try {
        # Get replication partner metadata
        $replInfo = Get-ADReplicationPartnerMetadata -Target * -ErrorAction Stop
        
        foreach ($partner in $replInfo) {
            $lastReplication = $partner.LastReplicationSuccess
            $lagMinutes = if ($lastReplication) { 
                (New-TimeSpan -Start $lastReplication -End (Get-Date)).TotalMinutes 
            } else { 
                9999 
            }
            
            $replicationResults += [PSCustomObject]@{
                SourceDC = $partner.Server
                PartnerDC = $partner.Partner
                Partition = ($partner.Partition -split ',')[0]
                LastReplication = $lastReplication
                LagMinutes = [math]::Round($lagMinutes, 2)
                LastResult = $partner.LastReplicationResult
                ConsecutiveFailures = $partner.ConsecutiveReplicationFailures
                IsHealthy = ($partner.LastReplicationResult -eq 0 -and $lagMinutes -lt $script:Config.ReplicationLagWarningMinutes)
            }
        }
    }
    catch {
        Write-Log "Failed to get replication status: $_" -Level Warning
    }
    
    # Also run repadmin for additional info
    try {
        $repadminOutput = repadmin /showrepl /csv 2>$null | ConvertFrom-Csv -ErrorAction SilentlyContinue
        
        if ($repadminOutput) {
            foreach ($entry in $repadminOutput | Where-Object { $_.'Number of Failures' -gt 0 }) {
                Write-Log "Replication failure detected: $($entry.'Source DC') -> $($entry.'Destination DC')" -Level Warning
            }
        }
    }
    catch {
        # Repadmin may not be available, continue silently
    }
    
    return $replicationResults
}

function Get-ReplicationSummary {
    [CmdletBinding()]
    param()
    
    try {
        $summary = repadmin /replsummary 2>$null
        return $summary -join "`n"
    }
    catch {
        return "Unable to retrieve replication summary"
    }
}

#endregion

#region DNS Checks

function Test-DNSHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    $dnsResults = [PSCustomObject]@{
        ComputerName = $ComputerName
        DNSServiceRunning = $false
        ForwardLookupZones = @()
        ReverseLookupZones = @()
        Forwarders = @()
        RecursionEnabled = $null
        SRVRecordsHealthy = $false
        Issues = @()
    }
    
    # Check DNS service
    try {
        $dnsService = Get-Service -ComputerName $ComputerName -Name DNS -ErrorAction Stop
        $dnsResults.DNSServiceRunning = ($dnsService.Status -eq 'Running')
    }
    catch {
        $dnsResults.Issues += "DNS service not accessible"
        return $dnsResults
    }
    
    if (-not $dnsResults.DNSServiceRunning) {
        $dnsResults.Issues += "DNS service is not running"
        return $dnsResults
    }
    
    # Check DNS zones
    try {
        $zones = Get-DnsServerZone -ComputerName $ComputerName -ErrorAction Stop
        $dnsResults.ForwardLookupZones = ($zones | Where-Object { -not $_.IsReverseLookupZone }).ZoneName
        $dnsResults.ReverseLookupZones = ($zones | Where-Object { $_.IsReverseLookupZone }).ZoneName
    }
    catch {
        $dnsResults.Issues += "Unable to query DNS zones: $_"
    }
    
    # Check forwarders
    try {
        $forwarders = Get-DnsServerForwarder -ComputerName $ComputerName -ErrorAction Stop
        $dnsResults.Forwarders = $forwarders.IPAddress.IPAddressToString
    }
    catch {
        # Forwarders may not be configured
    }
    
    # Test SRV records
    try {
        $domain = (Get-ADDomain).DNSRoot
        $srvRecords = @(
            "_ldap._tcp.dc._msdcs.$domain",
            "_kerberos._tcp.dc._msdcs.$domain",
            "_gc._tcp.$domain"
        )
        
        $srvHealthy = $true
        foreach ($srv in $srvRecords) {
            $result = Resolve-DnsName -Name $srv -Type SRV -Server $ComputerName -ErrorAction SilentlyContinue
            if (-not $result) {
                $srvHealthy = $false
                $dnsResults.Issues += "Missing SRV record: $srv"
            }
        }
        $dnsResults.SRVRecordsHealthy = $srvHealthy
    }
    catch {
        $dnsResults.Issues += "Unable to verify SRV records"
    }
    
    return $dnsResults
}

#endregion

#region FSMO Roles

function Get-FSMORoleHolders {
    [CmdletBinding()]
    param()
    
    $fsmoRoles = @()
    
    try {
        # Domain-level roles
        $domain = Get-ADDomain -ErrorAction Stop
        
        $fsmoRoles += [PSCustomObject]@{
            Role = "PDC Emulator"
            Holder = $domain.PDCEmulator
            Scope = "Domain"
            IsReachable = (Test-Connection -ComputerName ($domain.PDCEmulator -replace '\..*', '') -Count 1 -Quiet)
        }
        
        $fsmoRoles += [PSCustomObject]@{
            Role = "RID Master"
            Holder = $domain.RIDMaster
            Scope = "Domain"
            IsReachable = (Test-Connection -ComputerName ($domain.RIDMaster -replace '\..*', '') -Count 1 -Quiet)
        }
        
        $fsmoRoles += [PSCustomObject]@{
            Role = "Infrastructure Master"
            Holder = $domain.InfrastructureMaster
            Scope = "Domain"
            IsReachable = (Test-Connection -ComputerName ($domain.InfrastructureMaster -replace '\..*', '') -Count 1 -Quiet)
        }
        
        # Forest-level roles
        $forest = Get-ADForest -ErrorAction Stop
        
        $fsmoRoles += [PSCustomObject]@{
            Role = "Schema Master"
            Holder = $forest.SchemaMaster
            Scope = "Forest"
            IsReachable = (Test-Connection -ComputerName ($forest.SchemaMaster -replace '\..*', '') -Count 1 -Quiet)
        }
        
        $fsmoRoles += [PSCustomObject]@{
            Role = "Domain Naming Master"
            Holder = $forest.DomainNamingMaster
            Scope = "Forest"
            IsReachable = (Test-Connection -ComputerName ($forest.DomainNamingMaster -replace '\..*', '') -Count 1 -Quiet)
        }
    }
    catch {
        Write-Log "Failed to retrieve FSMO roles: $_" -Level Error
    }
    
    return $fsmoRoles
}

#endregion

#region Account Health

function Get-LockedOutAccounts {
    [CmdletBinding()]
    param(
        [int]$HoursBack = 24
    )
    
    try {
        $cutoffTime = (Get-Date).AddHours(-$HoursBack)
        
        $lockedAccounts = Search-ADAccount -LockedOut | 
            Get-ADUser -Properties LockedOut, LockoutTime, BadLogonCount, LastBadPasswordAttempt |
            Where-Object { $_.LockoutTime -gt $cutoffTime } |
            Select-Object @{N='Username';E={$_.SamAccountName}},
                         @{N='DisplayName';E={$_.Name}},
                         @{N='LockoutTime';E={[DateTime]::FromFileTime($_.LockoutTime)}},
                         BadLogonCount,
                         LastBadPasswordAttempt,
                         Enabled
        
        return $lockedAccounts
    }
    catch {
        Write-Log "Failed to get locked out accounts: $_" -Level Warning
        return @()
    }
}

function Get-ExpiringPasswords {
    [CmdletBinding()]
    param(
        [int]$DaysUntilExpiry = 14
    )
    
    try {
        $maxPwdAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days
        
        if ($maxPwdAge -eq 0) {
            Write-Log "Password expiration is not enforced" -Level Info
            return @()
        }
        
        $warningDate = (Get-Date).AddDays($DaysUntilExpiry)
        
        $expiringUsers = Get-ADUser -Filter {Enabled -eq $true -and PasswordNeverExpires -eq $false} -Properties PasswordLastSet, msDS-UserPasswordExpiryTimeComputed |
            Where-Object { 
                $expiryDate = [DateTime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed')
                $expiryDate -lt $warningDate -and $expiryDate -gt (Get-Date)
            } |
            Select-Object @{N='Username';E={$_.SamAccountName}},
                         @{N='DisplayName';E={$_.Name}},
                         @{N='PasswordLastSet';E={$_.PasswordLastSet}},
                         @{N='ExpiryDate';E={[DateTime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed')}},
                         @{N='DaysRemaining';E={([DateTime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed') - (Get-Date)).Days}}
        
        return $expiringUsers
    }
    catch {
        Write-Log "Failed to get expiring passwords: $_" -Level Warning
        return @()
    }
}

function Get-DisabledAccounts {
    [CmdletBinding()]
    param(
        [int]$InactiveDays = 90
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$InactiveDays)
        
        $disabledAccounts = Get-ADUser -Filter {Enabled -eq $false} -Properties WhenChanged, Description |
            Where-Object { $_.WhenChanged -lt $cutoffDate } |
            Select-Object @{N='Username';E={$_.SamAccountName}},
                         @{N='DisplayName';E={$_.Name}},
                         Description,
                         WhenChanged,
                         @{N='DaysSinceModified';E={(New-TimeSpan -Start $_.WhenChanged -End (Get-Date)).Days}}
        
        return $disabledAccounts
    }
    catch {
        Write-Log "Failed to get disabled accounts: $_" -Level Warning
        return @()
    }
}

function Get-StaleComputerAccounts {
    [CmdletBinding()]
    param(
        [int]$InactiveDays = 90
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$InactiveDays)
        
        $staleComputers = Get-ADComputer -Filter {LastLogonDate -lt $cutoffDate} -Properties LastLogonDate, OperatingSystem, Description |
            Select-Object Name,
                         @{N='OS';E={$_.OperatingSystem}},
                         LastLogonDate,
                         @{N='DaysInactive';E={(New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days}},
                         Description
        
        return $staleComputers
    }
    catch {
        Write-Log "Failed to get stale computer accounts: $_" -Level Warning
        return @()
    }
}

#endregion

#region Group Policy Checks

function Test-GroupPolicyHealth {
    [CmdletBinding()]
    param()
    
    $gpoResults = @()
    
    try {
        $allGPOs = Get-GPO -All -ErrorAction Stop
        
        foreach ($gpo in $allGPOs) {
            $gpoReport = Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction SilentlyContinue
            
            $linkCount = 0
            $hasSettings = $true
            
            if ($gpoReport) {
                $xml = [xml]$gpoReport
                $linkCount = ($xml.GPO.LinksTo | Measure-Object).Count
                
                # Check if GPO has any settings
                $computerSettings = $xml.GPO.Computer.ExtensionData
                $userSettings = $xml.GPO.User.ExtensionData
                $hasSettings = ($computerSettings -or $userSettings)
            }
            
            $gpoResults += [PSCustomObject]@{
                Name = $gpo.DisplayName
                Id = $gpo.Id
                Status = $gpo.GpoStatus
                CreationTime = $gpo.CreationTime
                ModificationTime = $gpo.ModificationTime
                LinkCount = $linkCount
                HasSettings = $hasSettings
                IsOrphaned = ($linkCount -eq 0)
                DaysSinceModified = (New-TimeSpan -Start $gpo.ModificationTime -End (Get-Date)).Days
            }
        }
    }
    catch {
        Write-Log "Failed to analyze Group Policy: $_" -Level Warning
    }
    
    return $gpoResults
}

function Test-SysvolReplication {
    [CmdletBinding()]
    param()
    
    $dcs = Get-ADDomainController -Filter *
    $results = @()
    
    foreach ($dc in $dcs) {
        $sysvolPath = "\\$($dc.HostName)\SYSVOL"
        
        try {
            $sysvolFiles = Get-ChildItem -Path $sysvolPath -Recurse -ErrorAction Stop | 
                Measure-Object -Property Length -Sum
            
            $results += [PSCustomObject]@{
                DomainController = $dc.HostName
                SysvolAccessible = $true
                FileCount = $sysvolFiles.Count
                TotalSizeMB = [math]::Round($sysvolFiles.Sum / 1MB, 2)
            }
        }
        catch {
            $results += [PSCustomObject]@{
                DomainController = $dc.HostName
                SysvolAccessible = $false
                FileCount = 0
                TotalSizeMB = 0
                Error = $_.Exception.Message
            }
        }
    }
    
    # Check for consistency
    $sizes = $results | Where-Object { $_.SysvolAccessible } | Select-Object -ExpandProperty TotalSizeMB
    if ($sizes.Count -gt 1) {
        $avgSize = ($sizes | Measure-Object -Average).Average
        foreach ($result in $results) {
            $result | Add-Member -NotePropertyName SizeVariance -NotePropertyValue ([math]::Abs($result.TotalSizeMB - $avgSize))
        }
    }
    
    return $results
}

#endregion

#region Event Log Analysis

function Get-CriticalADEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [int]$HoursBack = 24
    )
    
    $startTime = (Get-Date).AddHours(-$HoursBack)
    $criticalEvents = @()
    
    foreach ($logName in $script:Config.CriticalEventIDs.Keys) {
        $eventIDs = $script:Config.CriticalEventIDs[$logName]
        
        try {
            $events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
                LogName = $logName
                ID = $eventIDs
                StartTime = $startTime
            } -ErrorAction SilentlyContinue
            
            foreach ($event in $events) {
                $criticalEvents += [PSCustomObject]@{
                    ComputerName = $ComputerName
                    LogName = $logName
                    EventID = $event.Id
                    TimeCreated = $event.TimeCreated
                    Level = $event.LevelDisplayName
                    Message = ($event.Message -split "`n")[0]  # First line only
                }
            }
        }
        catch {
            # Log may not exist or be inaccessible
        }
    }
    
    return $criticalEvents | Sort-Object TimeCreated -Descending
}

#endregion

#region Time Sync Check

function Test-TimeSync {
    [CmdletBinding()]
    param()
    
    $timeResults = @()
    $dcs = Get-ADDomainController -Filter *
    $pdcEmulator = (Get-ADDomain).PDCEmulator
    
    foreach ($dc in $dcs) {
        try {
            # Get time from DC
            $dcTime = Invoke-Command -ComputerName $dc.HostName -ScriptBlock { Get-Date } -ErrorAction Stop
            $localTime = Get-Date
            $skewSeconds = [math]::Abs(($dcTime - $localTime).TotalSeconds)
            
            # Get W32Time configuration
            $w32tmConfig = Invoke-Command -ComputerName $dc.HostName -ScriptBlock {
                w32tm /query /status 2>$null
            } -ErrorAction SilentlyContinue
            
            $timeSource = if ($w32tmConfig) {
                ($w32tmConfig | Where-Object { $_ -match "Source:" }) -replace "Source:\s*", ""
            } else { "Unknown" }
            
            $timeResults += [PSCustomObject]@{
                DomainController = $dc.HostName
                IsPDCEmulator = ($dc.HostName -eq $pdcEmulator)
                CurrentTime = $dcTime
                SkewSeconds = [math]::Round($skewSeconds, 2)
                TimeSource = $timeSource
                IsHealthy = ($skewSeconds -lt 300)  # 5 minute threshold
            }
        }
        catch {
            $timeResults += [PSCustomObject]@{
                DomainController = $dc.HostName
                IsPDCEmulator = ($dc.HostName -eq $pdcEmulator)
                CurrentTime = $null
                SkewSeconds = $null
                TimeSource = "Unable to query"
                IsHealthy = $false
            }
        }
    }
    
    return $timeResults
}

#endregion

#region Report Generation

function New-HTMLReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData,
        
        [string]$OutputPath
    )
    
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $domain = (Get-ADDomain).DNSRoot
    
    # Calculate overall health
    $overallHealth = "Healthy"
    $healthIssues = @()
    
    # Check DC connectivity
    $offlineDCs = $ReportData.DCConnectivity | Where-Object { $_.OverallStatus -eq 'Offline' }
    if ($offlineDCs) {
        $overallHealth = "Critical"
        $healthIssues += "Offline Domain Controllers: $($offlineDCs.ComputerName -join ', ')"
    }
    
    # Check services
    $failedServices = $ReportData.Services | Where-Object { -not $_.IsHealthy }
    if ($failedServices) {
        $overallHealth = if ($overallHealth -ne "Critical") { "Warning" } else { $overallHealth }
        $healthIssues += "Failed Services: $($failedServices.Count)"
    }
    
    # Check replication
    $replIssues = $ReportData.Replication | Where-Object { -not $_.IsHealthy }
    if ($replIssues) {
        $overallHealth = if ($overallHealth -ne "Critical") { "Warning" } else { $overallHealth }
        $healthIssues += "Replication Issues: $($replIssues.Count)"
    }
    
    $healthColor = switch ($overallHealth) {
        "Healthy" { "#28a745" }
        "Warning" { "#ffc107" }
        "Critical" { "#dc3545" }
        default { "#6c757d" }
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Health Check Report - $domain</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #1a237e 0%, #283593 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 28px; }
        .header .subtitle { opacity: 0.8; margin-top: 5px; }
        .overall-health { display: inline-block; padding: 10px 20px; border-radius: 20px; background: $healthColor; color: white; font-weight: bold; margin-top: 15px; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { color: #1a237e; border-bottom: 2px solid #1a237e; padding-bottom: 10px; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; color: #333; }
        tr:hover { background: #f8f9fa; }
        .status-healthy { color: #28a745; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        .status-critical { color: #dc3545; font-weight: bold; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: bold; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .summary-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .summary-card .number { font-size: 36px; font-weight: bold; color: #1a237e; }
        .summary-card .label { color: #666; margin-top: 5px; }
        .issues-list { background: #fff3cd; border-radius: 8px; padding: 15px; margin-top: 15px; }
        .issues-list h4 { margin: 0 0 10px 0; color: #856404; }
        .issues-list ul { margin: 0; padding-left: 20px; }
        .footer { text-align: center; color: #666; margin-top: 30px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 Active Directory Health Check Report</h1>
            <div class="subtitle">Domain: $domain | Generated: $reportDate</div>
            <div class="overall-health">Overall Status: $overallHealth</div>
        </div>
"@

    # Summary Cards
    $totalDCs = ($ReportData.DCConnectivity | Measure-Object).Count
    $healthyDCs = ($ReportData.DCConnectivity | Where-Object { $_.OverallStatus -eq 'Healthy' } | Measure-Object).Count
    $lockedAccounts = ($ReportData.LockedAccounts | Measure-Object).Count
    $expiringPasswords = ($ReportData.ExpiringPasswords | Measure-Object).Count
    
    $html += @"
        <div class="summary-cards">
            <div class="summary-card">
                <div class="number">$healthyDCs / $totalDCs</div>
                <div class="label">Domain Controllers Healthy</div>
            </div>
            <div class="summary-card">
                <div class="number">$lockedAccounts</div>
                <div class="label">Locked Accounts</div>
            </div>
            <div class="summary-card">
                <div class="number">$expiringPasswords</div>
                <div class="label">Expiring Passwords</div>
            </div>
            <div class="summary-card">
                <div class="number">$(($ReportData.FSMO | Measure-Object).Count)</div>
                <div class="label">FSMO Roles Verified</div>
            </div>
        </div>
"@

    # Issues Summary
    if ($healthIssues) {
        $html += @"
        <div class="issues-list">
            <h4>⚠️ Issues Detected</h4>
            <ul>
                $(foreach ($issue in $healthIssues) { "<li>$issue</li>" })
            </ul>
        </div>
"@
    }

    # DC Connectivity Section
    $html += @"
        <div class="section">
            <h2>🖥️ Domain Controller Connectivity</h2>
            <table>
                <tr>
                    <th>Domain Controller</th>
                    <th>Ping</th>
                    <th>Latency (ms)</th>
                    <th>LDAP</th>
                    <th>RPC</th>
                    <th>SMB</th>
                    <th>Status</th>
                </tr>
"@
    
    foreach ($dc in $ReportData.DCConnectivity) {
        $statusClass = switch ($dc.OverallStatus) {
            "Healthy" { "status-healthy" }
            "Degraded" { "status-warning" }
            default { "status-critical" }
        }
        $pingIcon = if ($dc.Ping) { "✓" } else { "✗" }
        $ldapIcon = if ($dc.LDAP) { "✓" } else { "✗" }
        $rpcIcon = if ($dc.RPC) { "✓" } else { "✗" }
        $smbIcon = if ($dc.SMB) { "✓" } else { "✗" }
        
        $html += @"
                <tr>
                    <td>$($dc.ComputerName)</td>
                    <td>$pingIcon</td>
                    <td>$($dc.PingLatency)</td>
                    <td>$ldapIcon</td>
                    <td>$rpcIcon</td>
                    <td>$smbIcon</td>
                    <td class="$statusClass">$($dc.OverallStatus)</td>
                </tr>
"@
    }
    $html += "</table></div>"

    # Services Section
    $html += @"
        <div class="section">
            <h2>⚙️ Critical Services Status</h2>
            <table>
                <tr>
                    <th>Domain Controller</th>
                    <th>Service</th>
                    <th>Display Name</th>
                    <th>Status</th>
                </tr>
"@
    
    foreach ($svc in $ReportData.Services) {
        $badgeClass = if ($svc.IsHealthy) { "badge-success" } else { "badge-danger" }
        
        $html += @"
                <tr>
                    <td>$($svc.ComputerName)</td>
                    <td>$($svc.ServiceName)</td>
                    <td>$($svc.DisplayName)</td>
                    <td><span class="badge $badgeClass">$($svc.Status)</span></td>
                </tr>
"@
    }
    $html += "</table></div>"

    # FSMO Roles Section
    $html += @"
        <div class="section">
            <h2>👑 FSMO Role Holders</h2>
            <table>
                <tr>
                    <th>Role</th>
                    <th>Holder</th>
                    <th>Scope</th>
                    <th>Reachable</th>
                </tr>
"@
    
    foreach ($role in $ReportData.FSMO) {
        $reachableClass = if ($role.IsReachable) { "badge-success" } else { "badge-danger" }
        $reachableText = if ($role.IsReachable) { "Yes" } else { "No" }
        
        $html += @"
                <tr>
                    <td>$($role.Role)</td>
                    <td>$($role.Holder)</td>
                    <td>$($role.Scope)</td>
                    <td><span class="badge $reachableClass">$reachableText</span></td>
                </tr>
"@
    }
    $html += "</table></div>"

    # Replication Section (if available)
    if ($ReportData.Replication) {
        $html += @"
        <div class="section">
            <h2>🔄 Replication Status</h2>
            <table>
                <tr>
                    <th>Source DC</th>
                    <th>Partner DC</th>
                    <th>Partition</th>
                    <th>Last Replication</th>
                    <th>Lag (min)</th>
                    <th>Status</th>
                </tr>
"@
        
        foreach ($repl in $ReportData.Replication | Select-Object -First 20) {
            $statusClass = if ($repl.IsHealthy) { "badge-success" } else { "badge-danger" }
            $statusText = if ($repl.IsHealthy) { "Healthy" } else { "Issue" }
            
            $html += @"
                <tr>
                    <td>$($repl.SourceDC)</td>
                    <td>$($repl.PartnerDC)</td>
                    <td>$($repl.Partition)</td>
                    <td>$($repl.LastReplication)</td>
                    <td>$($repl.LagMinutes)</td>
                    <td><span class="badge $statusClass">$statusText</span></td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Locked Accounts Section
    if ($ReportData.LockedAccounts) {
        $html += @"
        <div class="section">
            <h2>🔐 Locked Out Accounts (Last 24 Hours)</h2>
            <table>
                <tr>
                    <th>Username</th>
                    <th>Display Name</th>
                    <th>Lockout Time</th>
                    <th>Bad Logon Count</th>
                </tr>
"@
        
        foreach ($account in $ReportData.LockedAccounts) {
            $html += @"
                <tr>
                    <td>$($account.Username)</td>
                    <td>$($account.DisplayName)</td>
                    <td>$($account.LockoutTime)</td>
                    <td>$($account.BadLogonCount)</td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Expiring Passwords Section
    if ($ReportData.ExpiringPasswords) {
        $html += @"
        <div class="section">
            <h2>⏰ Expiring Passwords (Next 14 Days)</h2>
            <table>
                <tr>
                    <th>Username</th>
                    <th>Display Name</th>
                    <th>Password Last Set</th>
                    <th>Expiry Date</th>
                    <th>Days Remaining</th>
                </tr>
"@
        
        foreach ($user in $ReportData.ExpiringPasswords | Sort-Object DaysRemaining) {
            $daysClass = if ($user.DaysRemaining -lt 3) { "status-critical" } elseif ($user.DaysRemaining -lt 7) { "status-warning" } else { "" }
            
            $html += @"
                <tr>
                    <td>$($user.Username)</td>
                    <td>$($user.DisplayName)</td>
                    <td>$($user.PasswordLastSet)</td>
                    <td>$($user.ExpiryDate)</td>
                    <td class="$daysClass">$($user.DaysRemaining)</td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Disk Space Section
    if ($ReportData.DiskSpace) {
        $html += @"
        <div class="section">
            <h2>💾 Domain Controller Disk Space</h2>
            <table>
                <tr>
                    <th>Domain Controller</th>
                    <th>Drive</th>
                    <th>Size (GB)</th>
                    <th>Free (GB)</th>
                    <th>Free %</th>
                    <th>Status</th>
                </tr>
"@
        
        foreach ($disk in $ReportData.DiskSpace) {
            $statusClass = if ($disk.IsHealthy) { "badge-success" } else { "badge-danger" }
            $statusText = if ($disk.IsHealthy) { "OK" } else { "Low" }
            
            $html += @"
                <tr>
                    <td>$($disk.ComputerName)</td>
                    <td>$($disk.Drive)</td>
                    <td>$($disk.SizeGB)</td>
                    <td>$($disk.FreeGB)</td>
                    <td>$($disk.FreePercent)%</td>
                    <td><span class="badge $statusClass">$statusText</span></td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Footer
    $html += @"
        <div class="footer">
            <p>Generated by SysAdmin Toolkit AD Health Check | © $(Get-Date -Format 'yyyy')</p>
            <p>Report completed in $($ReportData.ExecutionTime) seconds</p>
        </div>
    </div>
</body>
</html>
"@

    # Save report
    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "HTML report saved to: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region Email Functions

function Send-HealthReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportPath,
        
        [Parameter(Mandatory)]
        [string[]]$To,
        
        [string]$Subject = "AD Health Check Report - $(Get-Date -Format 'yyyy-MM-dd')"
    )
    
    try {
        $params = @{
            From = $script:Config.EmailFrom
            To = $To
            Subject = $Subject
            Body = "Please find the AD Health Check Report attached."
            Attachments = $ReportPath
            SmtpServer = $script:Config.SMTPServer
        }
        
        Send-MailMessage @params
        Write-Log "Report emailed to: $($To -join ', ')" -Level Success
    }
    catch {
        Write-Log "Failed to send email: $_" -Level Error
    }
}

#endregion

#region Main Function

function Start-ADHealthCheck {
    <#
    .SYNOPSIS
        Runs a comprehensive Active Directory health check
    
    .DESCRIPTION
        Performs multiple checks against AD infrastructure including DC health,
        services, replication, DNS, accounts, and generates a detailed report.
    
    .PARAMETER DomainController
        Specific DC to check (optional, checks all if not specified)
    
    .PARAMETER ExportPath
        Path for the HTML report (default: .\reports\)
    
    .PARAMETER CheckReplication
        Include replication health check
    
    .PARAMETER CheckDNS
        Include DNS health check
    
    .PARAMETER SendEmail
        Send report via email
    
    .PARAMETER EmailTo
        Email recipient(s)
    
    .PARAMETER Detailed
        Generate detailed report with additional checks
    
    .EXAMPLE
        Start-ADHealthCheck
    
    .EXAMPLE
        Start-ADHealthCheck -Detailed -CheckReplication -ExportPath "C:\Reports"
    #>
    [CmdletBinding()]
    param(
        [string]$DomainController,
        
        [string]$ExportPath = ".\reports",
        
        [switch]$CheckReplication,
        
        [switch]$CheckDNS,
        
        [switch]$SendEmail,
        
        [string[]]$EmailTo,
        
        [switch]$Detailed
    )
    
    $startTime = Get-Date
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          Active Directory Health Check                        ║" -ForegroundColor Cyan
    Write-Host "║          SysAdmin Toolkit v2.0                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Verify prerequisites
    if (-not (Test-ADModule)) {
        return
    }
    
    # Create export directory if needed
    if (-not (Test-Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }
    
    # Initialize report data
    $reportData = @{
        GeneratedAt = Get-Date
        Domain = (Get-ADDomain).DNSRoot
        DCConnectivity = @()
        Services = @()
        Shares = @()
        FSMO = @()
        Replication = @()
        DNS = @()
        LockedAccounts = @()
        ExpiringPasswords = @()
        DiskSpace = @()
        TimeSync = @()
        GPOHealth = @()
        CriticalEvents = @()
    }
    
    # Get domain controllers
    Write-Log "Getting domain controllers..." -Level Info
    $dcs = Get-DomainControllerList -DomainController $DomainController
    
    if (-not $dcs) {
        Write-Log "No domain controllers found!" -Level Error
        return
    }
    
    Write-Log "Found $($dcs.Count) domain controller(s)" -Level Success
    
    # Check each DC
    foreach ($dc in $dcs) {
        $dcName = $dc.HostName
        Write-Host ""
        Write-Log "Checking $dcName..." -Level Info
        
        # Connectivity
        Write-Log "  Testing connectivity..." -Level Info
        $connectivity = Test-DCConnectivity -ComputerName $dcName
        $reportData.DCConnectivity += $connectivity
        
        if ($connectivity.Ping) {
            # Services
            Write-Log "  Checking services..." -Level Info
            $services = Test-DCServices -ComputerName $dcName
            $reportData.Services += $services
            
            # Shares
            Write-Log "  Checking shares..." -Level Info
            $shares = Test-DCShares -ComputerName $dcName
            $reportData.Shares += $shares
            
            # Disk space
            if ($Detailed) {
                Write-Log "  Checking disk space..." -Level Info
                $diskSpace = Get-DCDiskSpace -ComputerName $dcName
                if ($diskSpace) {
                    $reportData.DiskSpace += $diskSpace
                }
            }
            
            # DNS check
            if ($CheckDNS) {
                Write-Log "  Checking DNS health..." -Level Info
                $dnsHealth = Test-DNSHealth -ComputerName $dcName
                $reportData.DNS += $dnsHealth
            }
            
            # Critical events
            if ($Detailed) {
                Write-Log "  Checking event logs..." -Level Info
                $events = Get-CriticalADEvents -ComputerName $dcName -HoursBack 24
                $reportData.CriticalEvents += $events
            }
        } else {
            Write-Log "  Skipping additional checks - DC not reachable" -Level Warning
        }
    }
    
    # FSMO roles
    Write-Host ""
    Write-Log "Checking FSMO role holders..." -Level Info
    $reportData.FSMO = Get-FSMORoleHolders
    
    # Replication
    if ($CheckReplication) {
        Write-Log "Checking replication status..." -Level Info
        $reportData.Replication = Test-ADReplication
    }
    
    # Account health
    Write-Log "Checking account health..." -Level Info
    $reportData.LockedAccounts = Get-LockedOutAccounts -HoursBack 24
    $reportData.ExpiringPasswords = Get-ExpiringPasswords -DaysUntilExpiry $script:Config.PasswordExpiryWarningDays
    
    # Time sync
    if ($Detailed) {
        Write-Log "Checking time synchronization..." -Level Info
        $reportData.TimeSync = Test-TimeSync
    }
    
    # GPO health
    if ($Detailed) {
        Write-Log "Checking Group Policy health..." -Level Info
        $reportData.GPOHealth = Test-GroupPolicyHealth
    }
    
    # Calculate execution time
    $endTime = Get-Date
    $reportData.ExecutionTime = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    
    # Generate report
    Write-Host ""
    Write-Log "Generating HTML report..." -Level Info
    $reportFileName = "ADHealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportPath = Join-Path $ExportPath $reportFileName
    $generatedReport = New-HTMLReport -ReportData $reportData -OutputPath $reportPath
    
    # Send email if requested
    if ($SendEmail -and $EmailTo) {
        Send-HealthReport -ReportPath $generatedReport -To $EmailTo
    }
    
    # Summary
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    Health Check Summary                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $healthyDCs = ($reportData.DCConnectivity | Where-Object { $_.OverallStatus -eq 'Healthy' }).Count
    $totalDCs = $reportData.DCConnectivity.Count
    $failedServices = ($reportData.Services | Where-Object { -not $_.IsHealthy }).Count
    
    Write-Host ""
    Write-Host "  Domain Controllers:    $healthyDCs / $totalDCs healthy" -ForegroundColor $(if ($healthyDCs -eq $totalDCs) { 'Green' } else { 'Yellow' })
    Write-Host "  Failed Services:       $failedServices" -ForegroundColor $(if ($failedServices -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Locked Accounts:       $($reportData.LockedAccounts.Count)" -ForegroundColor $(if ($reportData.LockedAccounts.Count -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  Expiring Passwords:    $($reportData.ExpiringPasswords.Count)" -ForegroundColor $(if ($reportData.ExpiringPasswords.Count -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host ""
    Write-Host "  Report saved to: $reportPath" -ForegroundColor Cyan
    Write-Host "  Execution time: $($reportData.ExecutionTime) seconds" -ForegroundColor Gray
    Write-Host ""
    
    # Open report in browser
    if (Test-Path $reportPath) {
        $openReport = Read-Host "Open report in browser? (Y/N)"
        if ($openReport -eq 'Y') {
            Start-Process $reportPath
        }
    }
    
    return $reportData
}

#endregion

#region Quick Functions

function Get-DCStatus {
    <#
    .SYNOPSIS
        Quick check of all domain controller status
    #>
    $dcs = Get-ADDomainController -Filter *
    
    foreach ($dc in $dcs) {
        $ping = Test-Connection -ComputerName $dc.HostName -Count 1 -Quiet
        $status = if ($ping) { "Online" } else { "Offline" }
        $color = if ($ping) { "Green" } else { "Red" }
        
        Write-Host "$($dc.HostName.PadRight(30)) [$status]" -ForegroundColor $color
    }
}

function Unlock-LockedAccounts {
    <#
    .SYNOPSIS
        Interactively unlock locked out accounts
    #>
    $locked = Search-ADAccount -LockedOut | Get-ADUser -Properties DisplayName
    
    if (-not $locked) {
        Write-Host "No locked accounts found." -ForegroundColor Green
        return
    }
    
    Write-Host "`nLocked Accounts:" -ForegroundColor Yellow
    $i = 1
    foreach ($user in $locked) {
        Write-Host "  $i. $($user.SamAccountName) - $($user.DisplayName)"
        $i++
    }
    
    $selection = Read-Host "`nEnter number to unlock (or 'all' to unlock all, 'q' to quit)"
    
    if ($selection -eq 'q') { return }
    
    if ($selection -eq 'all') {
        foreach ($user in $locked) {
            Unlock-ADAccount -Identity $user.SamAccountName
            Write-Host "Unlocked: $($user.SamAccountName)" -ForegroundColor Green
        }
    } else {
        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $locked.Count) {
            Unlock-ADAccount -Identity $locked[$index].SamAccountName
            Write-Host "Unlocked: $($locked[$index].SamAccountName)" -ForegroundColor Green
        }
    }
}

#endregion

# Export functions
Export-ModuleMember -Function Start-ADHealthCheck, Get-DCStatus, Unlock-LockedAccounts, 
    Test-DCConnectivity, Test-DCServices, Get-FSMORoleHolders, 
    Get-LockedOutAccounts, Get-ExpiringPasswords, Test-ADReplication

# Display available commands when script is loaded
Write-Host ""
Write-Host "AD Health Check Module Loaded" -ForegroundColor Green
Write-Host "Available commands:" -ForegroundColor Cyan
Write-Host "  Start-ADHealthCheck    - Run full health check"
Write-Host "  Get-DCStatus           - Quick DC status check"
Write-Host "  Unlock-LockedAccounts  - Interactive account unlock"
Write-Host ""
