<#
.SYNOPSIS
    Comprehensive Network Diagnostics Script
    
.DESCRIPTION
    Performs extensive network diagnostics including:
    - Connectivity testing (ping, traceroute, port checks)
    - DNS resolution testing
    - Network adapter diagnostics
    - Bandwidth and latency analysis
    - Network path analysis
    - Common issue detection and recommendations
    
.PARAMETER Target
    Target hostname or IP address to test

.PARAMETER FullDiagnostics
    Run complete diagnostic suite

.PARAMETER TestPorts
    Specific ports to test connectivity

.PARAMETER ExportPath
    Path to export HTML report

.EXAMPLE
    Start-NetworkDiagnostics -Target "google.com"
    
.EXAMPLE
    Start-NetworkDiagnostics -Target "192.168.1.1" -FullDiagnostics -ExportPath "C:\Reports"

.EXAMPLE
    Test-PortConnectivity -Target "server01" -Ports 80,443,3389

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
#>

#region Configuration

$script:Config = @{
    # Common ports to test
    CommonPorts = @{
        HTTP = 80
        HTTPS = 443
        RDP = 3389
        SSH = 22
        SMB = 445
        DNS = 53
        LDAP = 389
        LDAPS = 636
        FTP = 21
        SMTP = 25
        IMAP = 143
        POP3 = 110
        MySQL = 3306
        MSSQL = 1433
        PostgreSQL = 5432
        WinRM = 5985
        WinRMHTTPS = 5986
    }
    
    # DNS servers for testing
    PublicDNSServers = @(
        @{ Name = "Google Primary"; IP = "8.8.8.8" }
        @{ Name = "Google Secondary"; IP = "8.8.4.4" }
        @{ Name = "Cloudflare"; IP = "1.1.1.1" }
        @{ Name = "OpenDNS"; IP = "208.67.222.222" }
        @{ Name = "Quad9"; IP = "9.9.9.9" }
    )
    
    # Test domains for DNS resolution
    TestDomains = @("google.com", "microsoft.com", "github.com")
    
    # Thresholds
    LatencyWarningMS = 100
    LatencyCriticalMS = 300
    PacketLossWarningPercent = 5
    PacketLossCriticalPercent = 20
    
    # Report settings
    DefaultReportPath = ".\reports\network"
}

#endregion

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
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
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "$timestamp $($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function Get-LatencyStatus {
    param([double]$Latency)
    
    if ($Latency -lt $script:Config.LatencyWarningMS) {
        return @{ Status = "Good"; Color = "Green" }
    } elseif ($Latency -lt $script:Config.LatencyCriticalMS) {
        return @{ Status = "Warning"; Color = "Yellow" }
    } else {
        return @{ Status = "Critical"; Color = "Red" }
    }
}

function Format-Bytes {
    param([long]$Bytes)
    
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else { return "$Bytes Bytes" }
}

#endregion

#region Basic Connectivity Tests

function Test-BasicConnectivity {
    <#
    .SYNOPSIS
        Tests basic network connectivity to a target
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [int]$Count = 4,
        
        [int]$TimeoutMS = 1000
    )
    
    $results = [PSCustomObject]@{
        Target = $Target
        Reachable = $false
        PacketsSent = $Count
        PacketsReceived = 0
        PacketLoss = 100
        MinLatency = $null
        MaxLatency = $null
        AvgLatency = $null
        Responses = @()
        Status = "Unknown"
    }
    
    Write-Log "Testing connectivity to $Target..." -Level Info
    
    try {
        $pingResults = @()
        
        for ($i = 1; $i -le $Count; $i++) {
            try {
                $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
                
                $pingResults += [PSCustomObject]@{
                    Sequence = $i
                    Success = $true
                    ResponseTime = $ping.ResponseTime
                    TTL = $ping.ResponseTimeToLive
                    Address = $ping.Address
                }
            }
            catch {
                $pingResults += [PSCustomObject]@{
                    Sequence = $i
                    Success = $false
                    ResponseTime = $null
                    TTL = $null
                    Address = $null
                }
            }
            
            # Small delay between pings
            if ($i -lt $Count) { Start-Sleep -Milliseconds 200 }
        }
        
        $results.Responses = $pingResults
        $successfulPings = $pingResults | Where-Object { $_.Success }
        $results.PacketsReceived = $successfulPings.Count
        $results.PacketLoss = [math]::Round((($Count - $successfulPings.Count) / $Count) * 100, 2)
        
        if ($successfulPings) {
            $results.Reachable = $true
            $latencies = $successfulPings.ResponseTime
            $results.MinLatency = ($latencies | Measure-Object -Minimum).Minimum
            $results.MaxLatency = ($latencies | Measure-Object -Maximum).Maximum
            $results.AvgLatency = [math]::Round(($latencies | Measure-Object -Average).Average, 2)
            
            $latencyStatus = Get-LatencyStatus -Latency $results.AvgLatency
            
            if ($results.PacketLoss -eq 0) {
                $results.Status = "Healthy"
            } elseif ($results.PacketLoss -lt $script:Config.PacketLossWarningPercent) {
                $results.Status = "Minor Packet Loss"
            } else {
                $results.Status = "Significant Packet Loss"
            }
        } else {
            $results.Status = "Unreachable"
        }
    }
    catch {
        $results.Status = "Error: $($_.Exception.Message)"
    }
    
    return $results
}

function Test-PortConnectivity {
    <#
    .SYNOPSIS
        Tests TCP port connectivity to a target
    
    .PARAMETER Target
        Target hostname or IP
    
    .PARAMETER Ports
        Array of ports to test
    
    .PARAMETER TimeoutMS
        Timeout in milliseconds
    
    .EXAMPLE
        Test-PortConnectivity -Target "server01" -Ports 80,443,3389
    
    .EXAMPLE
        Test-PortConnectivity -Target "10.0.0.1" -Ports (Get-CommonPorts)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [Parameter(Mandatory)]
        [int[]]$Ports,
        
        [int]$TimeoutMS = 2000
    )
    
    $results = @()
    
    foreach ($port in $Ports) {
        $portName = ($script:Config.CommonPorts.GetEnumerator() | Where-Object { $_.Value -eq $port }).Name
        if (-not $portName) { $portName = "Unknown" }
        
        Write-Log "Testing port $port ($portName) on $Target..." -Level Info
        
        $result = [PSCustomObject]@{
            Target = $Target
            Port = $port
            Service = $portName
            Open = $false
            ResponseTime = $null
            Error = $null
        }
        
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($Target, $port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne($TimeoutMS, $false)
            
            if ($wait) {
                try {
                    $tcpClient.EndConnect($connect)
                    $result.Open = $true
                    $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                }
                catch {
                    $result.Error = "Connection refused"
                }
            } else {
                $result.Error = "Connection timed out"
            }
            
            $stopwatch.Stop()
            $tcpClient.Close()
        }
        catch {
            $result.Error = $_.Exception.Message
        }
        
        $results += $result
    }
    
    return $results
}

function Get-CommonPorts {
    <#
    .SYNOPSIS
        Returns array of common ports for testing
    #>
    return $script:Config.CommonPorts.Values | Sort-Object
}

function Test-CommonServices {
    <#
    .SYNOPSIS
        Tests connectivity to common service ports on a target
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [ValidateSet('All', 'Web', 'Database', 'RemoteAccess', 'Email', 'Directory')]
        [string]$ServiceCategory = 'All'
    )
    
    $portSets = @{
        'Web' = @(80, 443, 8080, 8443)
        'Database' = @(1433, 3306, 5432, 1521, 27017)
        'RemoteAccess' = @(22, 3389, 5985, 5986, 23)
        'Email' = @(25, 110, 143, 465, 587, 993, 995)
        'Directory' = @(389, 636, 88, 464)
        'All' = @(22, 25, 53, 80, 110, 143, 389, 443, 445, 636, 1433, 3306, 3389, 5432, 5985)
    }
    
    $ports = $portSets[$ServiceCategory]
    return Test-PortConnectivity -Target $Target -Ports $ports
}

#endregion

#region DNS Testing

function Test-DNSResolution {
    <#
    .SYNOPSIS
        Tests DNS resolution capabilities
    
    .PARAMETER Domain
        Domain to resolve
    
    .PARAMETER DNSServer
        Specific DNS server to query (optional)
    
    .PARAMETER RecordTypes
        Record types to query (A, AAAA, MX, NS, TXT, etc.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain,
        
        [string]$DNSServer,
        
        [ValidateSet('A', 'AAAA', 'MX', 'NS', 'TXT', 'CNAME', 'SOA', 'PTR', 'SRV')]
        [string[]]$RecordTypes = @('A', 'AAAA', 'MX', 'NS')
    )
    
    $results = [PSCustomObject]@{
        Domain = $Domain
        DNSServer = $DNSServer
        Queries = @()
        OverallSuccess = $false
        ResponseTime = $null
    }
    
    foreach ($recordType in $RecordTypes) {
        Write-Log "Querying $recordType record for $Domain..." -Level Info
        
        $query = [PSCustomObject]@{
            RecordType = $recordType
            Success = $false
            Results = @()
            ResponseTime = $null
            Error = $null
        }
        
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $params = @{
                Name = $Domain
                Type = $recordType
                ErrorAction = 'Stop'
            }
            
            if ($DNSServer) {
                $params.Server = $DNSServer
            }
            
            $dnsResult = Resolve-DnsName @params
            $stopwatch.Stop()
            
            $query.Success = $true
            $query.ResponseTime = $stopwatch.ElapsedMilliseconds
            $query.Results = $dnsResult | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Type = $_.Type
                    TTL = $_.TTL
                    Data = switch ($_.Type) {
                        'A' { $_.IPAddress }
                        'AAAA' { $_.IPAddress }
                        'MX' { "$($_.NameExchange) (Priority: $($_.Preference))" }
                        'NS' { $_.NameHost }
                        'TXT' { $_.Strings -join '; ' }
                        'CNAME' { $_.NameHost }
                        'SOA' { "$($_.PrimaryServer) ($($_.Administrator))" }
                        'SRV' { "$($_.NameTarget):$($_.Port) (Priority: $($_.Priority))" }
                        default { $_.ToString() }
                    }
                }
            }
        }
        catch {
            $query.Error = $_.Exception.Message
        }
        
        $results.Queries += $query
    }
    
    $results.OverallSuccess = ($results.Queries | Where-Object { $_.Success }).Count -gt 0
    $successfulQueries = $results.Queries | Where-Object { $_.Success }
    if ($successfulQueries) {
        $results.ResponseTime = [math]::Round(($successfulQueries.ResponseTime | Measure-Object -Average).Average, 2)
    }
    
    return $results
}

function Test-DNSServers {
    <#
    .SYNOPSIS
        Tests multiple DNS servers for response time and reliability
    #>
    [CmdletBinding()]
    param(
        [string]$TestDomain = "google.com",
        
        [switch]$IncludePublicDNS,
        
        [string[]]$CustomDNSServers
    )
    
    $dnsServers = @()
    
    # Get configured DNS servers from network adapters
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
        foreach ($dns in $dnsConfig.ServerAddresses) {
            $dnsServers += @{ Name = "Local ($($adapter.Name))"; IP = $dns }
        }
    }
    
    # Add public DNS servers if requested
    if ($IncludePublicDNS) {
        $dnsServers += $script:Config.PublicDNSServers
    }
    
    # Add custom DNS servers
    if ($CustomDNSServers) {
        foreach ($dns in $CustomDNSServers) {
            $dnsServers += @{ Name = "Custom"; IP = $dns }
        }
    }
    
    $results = @()
    
    foreach ($dns in $dnsServers) {
        Write-Log "Testing DNS server $($dns.IP) ($($dns.Name))..." -Level Info
        
        $result = [PSCustomObject]@{
            Name = $dns.Name
            IPAddress = $dns.IP
            Reachable = $false
            ResponseTime = $null
            ResolutionSuccess = $false
            ResolvedIP = $null
            Error = $null
        }
        
        # Test if DNS server is reachable
        $pingResult = Test-Connection -ComputerName $dns.IP -Count 1 -Quiet
        $result.Reachable = $pingResult
        
        if ($pingResult) {
            try {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $resolution = Resolve-DnsName -Name $TestDomain -Server $dns.IP -Type A -ErrorAction Stop
                $stopwatch.Stop()
                
                $result.ResolutionSuccess = $true
                $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                $result.ResolvedIP = ($resolution | Where-Object { $_.Type -eq 'A' }).IPAddress -join ', '
            }
            catch {
                $result.Error = $_.Exception.Message
            }
        }
        
        $results += $result
    }
    
    return $results
}

function Test-DNSPropagation {
    <#
    .SYNOPSIS
        Tests DNS propagation across multiple DNS servers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain,
        
        [string]$ExpectedIP
    )
    
    Write-Log "Testing DNS propagation for $Domain..." -Level Info
    
    $results = @()
    
    foreach ($dns in $script:Config.PublicDNSServers) {
        try {
            $resolution = Resolve-DnsName -Name $Domain -Server $dns.IP -Type A -ErrorAction Stop
            $resolvedIP = ($resolution | Where-Object { $_.Type -eq 'A' }).IPAddress
            
            $results += [PSCustomObject]@{
                DNSServer = $dns.Name
                IPAddress = $dns.IP
                ResolvedIP = $resolvedIP -join ', '
                Matches = if ($ExpectedIP) { $resolvedIP -contains $ExpectedIP } else { $null }
                TTL = ($resolution | Select-Object -First 1).TTL
            }
        }
        catch {
            $results += [PSCustomObject]@{
                DNSServer = $dns.Name
                IPAddress = $dns.IP
                ResolvedIP = "Resolution Failed"
                Matches = $false
                TTL = $null
            }
        }
    }
    
    return $results
}

#endregion

#region Network Path Analysis

function Get-NetworkPath {
    <#
    .SYNOPSIS
        Performs traceroute with detailed hop analysis
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [int]$MaxHops = 30,
        
        [int]$TimeoutMS = 3000,
        
        [switch]$ResolveNames
    )
    
    Write-Log "Tracing route to $Target (max $MaxHops hops)..." -Level Info
    
    $results = [PSCustomObject]@{
        Target = $Target
        TargetIP = $null
        TotalHops = 0
        ReachesTarget = $false
        Hops = @()
        TotalTime = $null
    }
    
    # Resolve target to IP
    try {
        $targetResolution = Resolve-DnsName -Name $Target -Type A -ErrorAction Stop
        $results.TargetIP = ($targetResolution | Where-Object { $_.Type -eq 'A' }).IPAddress | Select-Object -First 1
    }
    catch {
        Write-Log "Could not resolve target hostname" -Level Warning
    }
    
    try {
        $trace = Test-NetConnection -ComputerName $Target -TraceRoute -WarningAction SilentlyContinue
        
        $hopNumber = 0
        foreach ($hop in $trace.TraceRoute) {
            $hopNumber++
            
            $hopInfo = [PSCustomObject]@{
                Hop = $hopNumber
                IPAddress = $hop
                HostName = $null
                ResponseTime = $null
                Status = "Unknown"
            }
            
            # Try to get response time
            if ($hop -ne "0.0.0.0" -and $hop -ne "*") {
                $pingResult = Test-Connection -ComputerName $hop -Count 1 -ErrorAction SilentlyContinue
                if ($pingResult) {
                    $hopInfo.ResponseTime = $pingResult.ResponseTime
                    $hopInfo.Status = "Responsive"
                }
                
                # Resolve hostname if requested
                if ($ResolveNames) {
                    try {
                        $hostEntry = [System.Net.Dns]::GetHostEntry($hop)
                        $hopInfo.HostName = $hostEntry.HostName
                    }
                    catch {
                        $hopInfo.HostName = $hop
                    }
                }
            } else {
                $hopInfo.Status = "No Response"
            }
            
            $results.Hops += $hopInfo
        }
        
        $results.TotalHops = $hopNumber
        $results.ReachesTarget = $trace.PingSucceeded
        
        # Calculate total time
        $responsiveHops = $results.Hops | Where-Object { $_.ResponseTime }
        if ($responsiveHops) {
            $results.TotalTime = ($responsiveHops.ResponseTime | Measure-Object -Sum).Sum
        }
    }
    catch {
        Write-Log "Traceroute failed: $_" -Level Error
    }
    
    return $results
}

function Compare-NetworkPaths {
    <#
    .SYNOPSIS
        Compares network paths between two targets to find divergence points
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target1,
        
        [Parameter(Mandatory)]
        [string]$Target2
    )
    
    Write-Log "Comparing network paths to $Target1 and $Target2..." -Level Info
    
    $path1 = Get-NetworkPath -Target $Target1
    $path2 = Get-NetworkPath -Target $Target2
    
    $comparison = [PSCustomObject]@{
        Target1 = $Target1
        Target2 = $Target2
        Path1Hops = $path1.TotalHops
        Path2Hops = $path2.TotalHops
        CommonHops = @()
        DivergencePoint = $null
        Path1Unique = @()
        Path2Unique = @()
    }
    
    # Find common and divergence points
    $minHops = [Math]::Min($path1.Hops.Count, $path2.Hops.Count)
    $divergenceFound = $false
    
    for ($i = 0; $i -lt $minHops; $i++) {
        if ($path1.Hops[$i].IPAddress -eq $path2.Hops[$i].IPAddress) {
            if (-not $divergenceFound) {
                $comparison.CommonHops += $path1.Hops[$i]
            }
        } else {
            if (-not $divergenceFound) {
                $comparison.DivergencePoint = $i + 1
                $divergenceFound = $true
            }
        }
    }
    
    if ($comparison.DivergencePoint) {
        $comparison.Path1Unique = $path1.Hops | Select-Object -Skip ($comparison.DivergencePoint - 1)
        $comparison.Path2Unique = $path2.Hops | Select-Object -Skip ($comparison.DivergencePoint - 1)
    }
    
    return $comparison
}

#endregion

#region Network Adapter Diagnostics

function Get-NetworkAdapterDiagnostics {
    <#
    .SYNOPSIS
        Gets detailed information about network adapters
    #>
    [CmdletBinding()]
    param(
        [switch]$ActiveOnly
    )
    
    $adapters = Get-NetAdapter
    
    if ($ActiveOnly) {
        $adapters = $adapters | Where-Object { $_.Status -eq 'Up' }
    }
    
    $results = @()
    
    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
        $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
        
        $adapterInfo = [PSCustomObject]@{
            Name = $adapter.Name
            Description = $adapter.InterfaceDescription
            Status = $adapter.Status
            LinkSpeed = $adapter.LinkSpeed
            MacAddress = $adapter.MacAddress
            MediaType = $adapter.MediaType
            IPv4Address = ($ipConfig | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.PrefixOrigin -ne 'WellKnown' }).IPAddress -join ', '
            IPv4Subnet = ($ipConfig | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.PrefixOrigin -ne 'WellKnown' }).PrefixLength
            IPv6Address = ($ipConfig | Where-Object { $_.AddressFamily -eq 'IPv6' -and $_.PrefixOrigin -ne 'WellKnown' }).IPAddress | Select-Object -First 1
            Gateway = $gateway.NextHop
            DNSServers = ($dnsServers | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses -join ', '
            BytesSent = if ($stats) { Format-Bytes $stats.SentBytes } else { "N/A" }
            BytesReceived = if ($stats) { Format-Bytes $stats.ReceivedBytes } else { "N/A" }
            PacketsSent = if ($stats) { $stats.SentUnicastPackets } else { "N/A" }
            PacketsReceived = if ($stats) { $stats.ReceivedUnicastPackets } else { "N/A" }
            Errors = if ($stats) { $stats.OutboundPacketErrors + $stats.InboundPacketErrors } else { "N/A" }
        }
        
        $results += $adapterInfo
    }
    
    return $results
}

function Test-NetworkAdapterHealth {
    <#
    .SYNOPSIS
        Checks network adapter health and identifies potential issues
    #>
    [CmdletBinding()]
    param()
    
    $adapters = Get-NetworkAdapterDiagnostics -ActiveOnly
    $issues = @()
    
    foreach ($adapter in $adapters) {
        Write-Log "Checking adapter: $($adapter.Name)..." -Level Info
        
        # Check for missing IP
        if (-not $adapter.IPv4Address) {
            $issues += [PSCustomObject]@{
                Adapter = $adapter.Name
                Issue = "No IPv4 Address"
                Severity = "Critical"
                Recommendation = "Check DHCP server or configure static IP"
            }
        }
        
        # Check for missing gateway
        if (-not $adapter.Gateway) {
            $issues += [PSCustomObject]@{
                Adapter = $adapter.Name
                Issue = "No Default Gateway"
                Severity = "Critical"
                Recommendation = "Configure default gateway for internet access"
            }
        }
        
        # Check for missing DNS
        if (-not $adapter.DNSServers) {
            $issues += [PSCustomObject]@{
                Adapter = $adapter.Name
                Issue = "No DNS Servers Configured"
                Severity = "High"
                Recommendation = "Configure DNS servers for name resolution"
            }
        }
        
        # Check for errors
        if ($adapter.Errors -ne "N/A" -and $adapter.Errors -gt 0) {
            $issues += [PSCustomObject]@{
                Adapter = $adapter.Name
                Issue = "Packet Errors Detected ($($adapter.Errors))"
                Severity = "Warning"
                Recommendation = "Check cable, switch port, or driver"
            }
        }
        
        # Check link speed (if unusually low)
        if ($adapter.LinkSpeed -match "(\d+)\s*(Mbps|Gbps)") {
            $speed = [int]$Matches[1]
            $unit = $Matches[2]
            
            if ($unit -eq "Mbps" -and $speed -lt 100) {
                $issues += [PSCustomObject]@{
                    Adapter = $adapter.Name
                    Issue = "Low Link Speed ($($adapter.LinkSpeed))"
                    Severity = "Warning"
                    Recommendation = "Check cable quality and switch port settings"
                }
            }
        }
    }
    
    return @{
        Adapters = $adapters
        Issues = $issues
        HealthStatus = if ($issues | Where-Object { $_.Severity -eq "Critical" }) { "Critical" }
                      elseif ($issues | Where-Object { $_.Severity -eq "High" }) { "Warning" }
                      elseif ($issues) { "Minor Issues" }
                      else { "Healthy" }
    }
}

function Reset-NetworkAdapter {
    <#
    .SYNOPSIS
        Resets a network adapter (disable/enable)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AdapterName
    )
    
    if ($PSCmdlet.ShouldProcess($AdapterName, "Reset network adapter")) {
        Write-Log "Resetting adapter: $AdapterName" -Level Info
        
        try {
            Disable-NetAdapter -Name $AdapterName -Confirm:$false
            Start-Sleep -Seconds 2
            Enable-NetAdapter -Name $AdapterName -Confirm:$false
            Start-Sleep -Seconds 3
            
            $adapter = Get-NetAdapter -Name $AdapterName
            
            if ($adapter.Status -eq 'Up') {
                Write-Log "Adapter reset successful" -Level Success
                return $true
            } else {
                Write-Log "Adapter did not come back up" -Level Warning
                return $false
            }
        }
        catch {
            Write-Log "Failed to reset adapter: $_" -Level Error
            return $false
        }
    }
}

#endregion

#region Bandwidth and Latency Analysis

function Test-NetworkLatency {
    <#
    .SYNOPSIS
        Performs extended latency testing with statistics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [int]$Count = 20,
        
        [int]$IntervalMS = 500
    )
    
    Write-Log "Testing latency to $Target ($Count samples)..." -Level Info
    
    $samples = @()
    
    for ($i = 1; $i -le $Count; $i++) {
        Write-Progress -Activity "Testing Latency" -Status "Sample $i of $Count" -PercentComplete (($i / $Count) * 100)
        
        try {
            $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
            $samples += [PSCustomObject]@{
                Sequence = $i
                Time = Get-Date
                ResponseTime = $ping.ResponseTime
                Success = $true
            }
        }
        catch {
            $samples += [PSCustomObject]@{
                Sequence = $i
                Time = Get-Date
                ResponseTime = $null
                Success = $false
            }
        }
        
        if ($i -lt $Count) {
            Start-Sleep -Milliseconds $IntervalMS
        }
    }
    
    Write-Progress -Activity "Testing Latency" -Completed
    
    $successfulSamples = $samples | Where-Object { $_.Success }
    
    $results = [PSCustomObject]@{
        Target = $Target
        TotalSamples = $Count
        SuccessfulSamples = $successfulSamples.Count
        PacketLoss = [math]::Round((($Count - $successfulSamples.Count) / $Count) * 100, 2)
        MinLatency = $null
        MaxLatency = $null
        AvgLatency = $null
        MedianLatency = $null
        Jitter = $null
        Percentile95 = $null
        Samples = $samples
    }
    
    if ($successfulSamples) {
        $latencies = $successfulSamples.ResponseTime | Sort-Object
        
        $results.MinLatency = $latencies | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
        $results.MaxLatency = $latencies | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        $results.AvgLatency = [math]::Round(($latencies | Measure-Object -Average | Select-Object -ExpandProperty Average), 2)
        
        # Median
        $mid = [math]::Floor($latencies.Count / 2)
        if ($latencies.Count % 2 -eq 0) {
            $results.MedianLatency = ($latencies[$mid - 1] + $latencies[$mid]) / 2
        } else {
            $results.MedianLatency = $latencies[$mid]
        }
        
        # Jitter (average difference between consecutive samples)
        $diffs = @()
        for ($i = 1; $i -lt $latencies.Count; $i++) {
            $diffs += [math]::Abs($latencies[$i] - $latencies[$i-1])
        }
        if ($diffs) {
            $results.Jitter = [math]::Round(($diffs | Measure-Object -Average).Average, 2)
        }
        
        # 95th percentile
        $p95Index = [math]::Floor($latencies.Count * 0.95)
        $results.Percentile95 = $latencies[$p95Index]
    }
    
    return $results
}

function Test-BandwidthEstimate {
    <#
    .SYNOPSIS
        Estimates available bandwidth using file download test
    #>
    [CmdletBinding()]
    param(
        [string]$TestUrl = "http://speedtest.tele2.net/1MB.zip",
        
        [int]$TestFileSizeBytes = 1048576
    )
    
    Write-Log "Estimating bandwidth..." -Level Info
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($TestUrl, $tempFile)
        
        $stopwatch.Stop()
        
        $actualSize = (Get-Item $tempFile).Length
        $seconds = $stopwatch.Elapsed.TotalSeconds
        $bitsPerSecond = ($actualSize * 8) / $seconds
        $megabitsPerSecond = [math]::Round($bitsPerSecond / 1000000, 2)
        
        Write-Log "Download speed: $megabitsPerSecond Mbps" -Level Success
        
        return [PSCustomObject]@{
            TestUrl = $TestUrl
            FileSize = Format-Bytes $actualSize
            Duration = [math]::Round($seconds, 2)
            SpeedBps = $bitsPerSecond
            SpeedMbps = $megabitsPerSecond
            Status = "Success"
        }
    }
    catch {
        Write-Log "Bandwidth test failed: $_" -Level Error
        
        return [PSCustomObject]@{
            TestUrl = $TestUrl
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

#endregion

#region Internet Connectivity

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
        Comprehensive internet connectivity test
    #>
    [CmdletBinding()]
    param()
    
    Write-Log "Testing internet connectivity..." -Level Info
    
    $results = [PSCustomObject]@{
        Timestamp = Get-Date
        HasInternet = $false
        PublicIP = $null
        DNSWorking = $false
        HTTPWorking = $false
        HTTPSWorking = $false
        Tests = @()
    }
    
    # Test basic connectivity
    $pingTest = Test-BasicConnectivity -Target "8.8.8.8" -Count 2
    $results.Tests += [PSCustomObject]@{
        Test = "ICMP to Google DNS"
        Success = $pingTest.Reachable
        Details = "Latency: $($pingTest.AvgLatency)ms"
    }
    
    # Test DNS resolution
    try {
        $dnsTest = Resolve-DnsName -Name "google.com" -Type A -ErrorAction Stop
        $results.DNSWorking = $true
        $results.Tests += [PSCustomObject]@{
            Test = "DNS Resolution"
            Success = $true
            Details = "Resolved google.com to $($dnsTest.IPAddress -join ', ')"
        }
    }
    catch {
        $results.Tests += [PSCustomObject]@{
            Test = "DNS Resolution"
            Success = $false
            Details = $_.Exception.Message
        }
    }
    
    # Test HTTP
    try {
        $httpTest = Invoke-WebRequest -Uri "http://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $results.HTTPWorking = $true
        $results.Tests += [PSCustomObject]@{
            Test = "HTTP Connection"
            Success = $true
            Details = "Status: $($httpTest.StatusCode)"
        }
    }
    catch {
        $results.Tests += [PSCustomObject]@{
            Test = "HTTP Connection"
            Success = $false
            Details = $_.Exception.Message
        }
    }
    
    # Test HTTPS
    try {
        $httpsTest = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $results.HTTPSWorking = $true
        $results.Tests += [PSCustomObject]@{
            Test = "HTTPS Connection"
            Success = $true
            Details = "Status: $($httpsTest.StatusCode)"
        }
    }
    catch {
        $results.Tests += [PSCustomObject]@{
            Test = "HTTPS Connection"
            Success = $false
            Details = $_.Exception.Message
        }
    }
    
    # Get public IP
    try {
        $publicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5).Content
        $results.PublicIP = $publicIP
        $results.Tests += [PSCustomObject]@{
            Test = "Public IP Detection"
            Success = $true
            Details = "Public IP: $publicIP"
        }
    }
    catch {
        $results.Tests += [PSCustomObject]@{
            Test = "Public IP Detection"
            Success = $false
            Details = "Could not determine public IP"
        }
    }
    
    # Determine overall internet status
    $results.HasInternet = $pingTest.Reachable -and ($results.HTTPWorking -or $results.HTTPSWorking)
    
    return $results
}

#endregion

#region Report Generation

function New-NetworkDiagnosticsReport {
    <#
    .SYNOPSIS
        Generates HTML report from network diagnostics results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DiagnosticsData,
        
        [string]$OutputPath
    )
    
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $hostname = $env:COMPUTERNAME
    
    # Determine overall status
    $overallStatus = "Healthy"
    if ($DiagnosticsData.AdapterHealth.HealthStatus -eq "Critical" -or 
        -not $DiagnosticsData.InternetConnectivity.HasInternet) {
        $overallStatus = "Critical"
    } elseif ($DiagnosticsData.AdapterHealth.HealthStatus -eq "Warning" -or
              $DiagnosticsData.Latency.PacketLoss -gt 5) {
        $overallStatus = "Warning"
    }
    
    $statusColor = switch ($overallStatus) {
        "Healthy" { "#28a745" }
        "Warning" { "#ffc107" }
        "Critical" { "#dc3545" }
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Diagnostics Report - $hostname</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #2196F3 0%, #1976D2 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 28px; }
        .overall-status { display: inline-block; padding: 10px 20px; border-radius: 20px; background: $statusColor; color: white; font-weight: bold; margin-top: 15px; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { color: #1976D2; border-bottom: 2px solid #1976D2; padding-bottom: 10px; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: bold; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; }
        .stat-card { background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center; }
        .stat-value { font-size: 24px; font-weight: bold; color: #1976D2; }
        .stat-label { color: #666; font-size: 14px; }
        .issue-item { padding: 10px; margin: 5px 0; border-radius: 4px; }
        .issue-critical { background: #f8d7da; border-left: 4px solid #dc3545; }
        .issue-warning { background: #fff3cd; border-left: 4px solid #ffc107; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Network Diagnostics Report</h1>
            <div>Host: $hostname | Generated: $reportDate</div>
            <div class="overall-status">Overall Status: $overallStatus</div>
        </div>
"@

    # Internet Connectivity Section
    if ($DiagnosticsData.InternetConnectivity) {
        $inet = $DiagnosticsData.InternetConnectivity
        $inetStatus = if ($inet.HasInternet) { "badge-success" } else { "badge-danger" }
        $inetText = if ($inet.HasInternet) { "Connected" } else { "Disconnected" }
        
        $html += @"
        <div class="section">
            <h2>🌍 Internet Connectivity</h2>
            <p>Public IP: <strong>$($inet.PublicIP)</strong> | Status: <span class="badge $inetStatus">$inetText</span></p>
            <table>
                <tr><th>Test</th><th>Result</th><th>Details</th></tr>
"@
        foreach ($test in $inet.Tests) {
            $resultClass = if ($test.Success) { "badge-success" } else { "badge-danger" }
            $resultText = if ($test.Success) { "Pass" } else { "Fail" }
            $html += "<tr><td>$($test.Test)</td><td><span class='badge $resultClass'>$resultText</span></td><td>$($test.Details)</td></tr>"
        }
        $html += "</table></div>"
    }

    # Latency Statistics Section
    if ($DiagnosticsData.Latency) {
        $lat = $DiagnosticsData.Latency
        $html += @"
        <div class="section">
            <h2>📊 Latency Analysis - $($lat.Target)</h2>
            <div class="stats-grid">
                <div class="stat-card"><div class="stat-value">$($lat.AvgLatency)ms</div><div class="stat-label">Average</div></div>
                <div class="stat-card"><div class="stat-value">$($lat.MinLatency)ms</div><div class="stat-label">Minimum</div></div>
                <div class="stat-card"><div class="stat-value">$($lat.MaxLatency)ms</div><div class="stat-label">Maximum</div></div>
                <div class="stat-card"><div class="stat-value">$($lat.Jitter)ms</div><div class="stat-label">Jitter</div></div>
                <div class="stat-card"><div class="stat-value">$($lat.PacketLoss)%</div><div class="stat-label">Packet Loss</div></div>
                <div class="stat-card"><div class="stat-value">$($lat.Percentile95)ms</div><div class="stat-label">95th Percentile</div></div>
            </div>
        </div>
"@
    }

    # Network Adapters Section
    if ($DiagnosticsData.AdapterHealth) {
        $html += @"
        <div class="section">
            <h2>🔌 Network Adapters</h2>
            <table>
                <tr><th>Name</th><th>Status</th><th>Speed</th><th>IPv4</th><th>Gateway</th><th>DNS</th></tr>
"@
        foreach ($adapter in $DiagnosticsData.AdapterHealth.Adapters) {
            $statusClass = if ($adapter.Status -eq 'Up') { "badge-success" } else { "badge-danger" }
            $html += @"
                <tr>
                    <td>$($adapter.Name)</td>
                    <td><span class="badge $statusClass">$($adapter.Status)</span></td>
                    <td>$($adapter.LinkSpeed)</td>
                    <td>$($adapter.IPv4Address)</td>
                    <td>$($adapter.Gateway)</td>
                    <td>$($adapter.DNSServers)</td>
                </tr>
"@
        }
        $html += "</table>"
        
        # Issues
        if ($DiagnosticsData.AdapterHealth.Issues) {
            $html += "<h3>⚠️ Detected Issues</h3>"
            foreach ($issue in $DiagnosticsData.AdapterHealth.Issues) {
                $issueClass = if ($issue.Severity -eq "Critical") { "issue-critical" } else { "issue-warning" }
                $html += "<div class='issue-item $issueClass'><strong>$($issue.Adapter):</strong> $($issue.Issue)<br><em>$($issue.Recommendation)</em></div>"
            }
        }
        $html += "</div>"
    }

    # DNS Servers Section
    if ($DiagnosticsData.DNSServers) {
        $html += @"
        <div class="section">
            <h2>🔍 DNS Server Performance</h2>
            <table>
                <tr><th>Server</th><th>IP</th><th>Reachable</th><th>Response Time</th><th>Resolution</th></tr>
"@
        foreach ($dns in $DiagnosticsData.DNSServers) {
            $reachClass = if ($dns.Reachable) { "badge-success" } else { "badge-danger" }
            $resolveClass = if ($dns.ResolutionSuccess) { "badge-success" } else { "badge-danger" }
            $html += @"
                <tr>
                    <td>$($dns.Name)</td>
                    <td>$($dns.IPAddress)</td>
                    <td><span class="badge $reachClass">$(if ($dns.Reachable) { 'Yes' } else { 'No' })</span></td>
                    <td>$($dns.ResponseTime)ms</td>
                    <td><span class="badge $resolveClass">$(if ($dns.ResolutionSuccess) { 'Pass' } else { 'Fail' })</span></td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Port Scan Results
    if ($DiagnosticsData.PortScan) {
        $html += @"
        <div class="section">
            <h2>🔓 Port Connectivity - $($DiagnosticsData.PortScan[0].Target)</h2>
            <table>
                <tr><th>Port</th><th>Service</th><th>Status</th><th>Response Time</th></tr>
"@
        foreach ($port in $DiagnosticsData.PortScan) {
            $portClass = if ($port.Open) { "badge-success" } else { "badge-danger" }
            $portStatus = if ($port.Open) { "Open" } else { "Closed" }
            $html += @"
                <tr>
                    <td>$($port.Port)</td>
                    <td>$($port.Service)</td>
                    <td><span class="badge $portClass">$portStatus</span></td>
                    <td>$(if ($port.ResponseTime) { "$($port.ResponseTime)ms" } else { $port.Error })</td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Traceroute Section
    if ($DiagnosticsData.Traceroute) {
        $trace = $DiagnosticsData.Traceroute
        $html += @"
        <div class="section">
            <h2>🛤️ Network Path to $($trace.Target)</h2>
            <p>Total Hops: $($trace.TotalHops) | Reaches Target: $(if ($trace.ReachesTarget) { 'Yes' } else { 'No' })</p>
            <table>
                <tr><th>Hop</th><th>IP Address</th><th>Hostname</th><th>Response Time</th><th>Status</th></tr>
"@
        foreach ($hop in $trace.Hops) {
            $statusClass = if ($hop.Status -eq "Responsive") { "badge-success" } else { "badge-warning" }
            $html += @"
                <tr>
                    <td>$($hop.Hop)</td>
                    <td>$($hop.IPAddress)</td>
                    <td>$($hop.HostName)</td>
                    <td>$(if ($hop.ResponseTime) { "$($hop.ResponseTime)ms" } else { "N/A" })</td>
                    <td><span class="badge $statusClass">$($hop.Status)</span></td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Footer
    $html += @"
        <div style="text-align: center; color: #666; margin-top: 30px; font-size: 12px;">
            <p>Generated by SysAdmin Toolkit Network Diagnostics | © $(Get-Date -Format 'yyyy')</p>
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

#region Main Function

function Start-NetworkDiagnostics {
    <#
    .SYNOPSIS
        Runs comprehensive network diagnostics
    
    .DESCRIPTION
        Performs multiple network tests and generates a detailed report
    
    .PARAMETER Target
        Primary target for connectivity tests
    
    .PARAMETER FullDiagnostics
        Run all available tests
    
    .PARAMETER TestPorts
        Additional ports to test on target
    
    .PARAMETER ExportPath
        Path for HTML report
    
    .PARAMETER LatencySamples
        Number of latency samples to collect
    
    .EXAMPLE
        Start-NetworkDiagnostics -Target "google.com"
    
    .EXAMPLE
        Start-NetworkDiagnostics -Target "192.168.1.1" -FullDiagnostics
    #>
    [CmdletBinding()]
    param(
        [string]$Target = "google.com",
        
        [switch]$FullDiagnostics,
        
        [int[]]$TestPorts,
        
        [string]$ExportPath = $script:Config.DefaultReportPath,
        
        [int]$LatencySamples = 10
    )
    
    $startTime = Get-Date
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              Network Diagnostics Suite                         ║" -ForegroundColor Cyan
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Create export directory
    if (-not (Test-Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }
    
    # Initialize results
    $diagnosticsData = @{
        Timestamp = Get-Date
        Target = $Target
        InternetConnectivity = $null
        BasicConnectivity = $null
        Latency = $null
        AdapterHealth = $null
        DNSServers = $null
        PortScan = $null
        Traceroute = $null
    }
    
    # Test 1: Internet Connectivity
    Write-Host ""
    Write-Log "Testing internet connectivity..." -Level Info
    $diagnosticsData.InternetConnectivity = Test-InternetConnectivity
    
    $inetStatus = if ($diagnosticsData.InternetConnectivity.HasInternet) { "Connected" } else { "Disconnected" }
    $inetColor = if ($diagnosticsData.InternetConnectivity.HasInternet) { "Green" } else { "Red" }
    Write-Host "  Internet: " -NoNewline
    Write-Host $inetStatus -ForegroundColor $inetColor
    
    # Test 2: Basic Connectivity to Target
    Write-Host ""
    Write-Log "Testing connectivity to $Target..." -Level Info
    $diagnosticsData.BasicConnectivity = Test-BasicConnectivity -Target $Target
    
    Write-Host "  Reachable: " -NoNewline
    $reachColor = if ($diagnosticsData.BasicConnectivity.Reachable) { "Green" } else { "Red" }
    Write-Host $diagnosticsData.BasicConnectivity.Reachable -ForegroundColor $reachColor
    
    if ($diagnosticsData.BasicConnectivity.Reachable) {
        Write-Host "  Avg Latency: $($diagnosticsData.BasicConnectivity.AvgLatency)ms"
        Write-Host "  Packet Loss: $($diagnosticsData.BasicConnectivity.PacketLoss)%"
    }
    
    # Test 3: Network Adapter Health
    Write-Host ""
    Write-Log "Checking network adapters..." -Level Info
    $diagnosticsData.AdapterHealth = Test-NetworkAdapterHealth
    
    Write-Host "  Adapter Status: " -NoNewline
    $healthColor = switch ($diagnosticsData.AdapterHealth.HealthStatus) {
        "Healthy" { "Green" }
        "Warning" { "Yellow" }
        default { "Red" }
    }
    Write-Host $diagnosticsData.AdapterHealth.HealthStatus -ForegroundColor $healthColor
    
    # Test 4: DNS Servers
    Write-Host ""
    Write-Log "Testing DNS servers..." -Level Info
    $diagnosticsData.DNSServers = Test-DNSServers -IncludePublicDNS
    
    $workingDNS = ($diagnosticsData.DNSServers | Where-Object { $_.ResolutionSuccess }).Count
    Write-Host "  Working DNS Servers: $workingDNS / $($diagnosticsData.DNSServers.Count)"
    
    # Test 5: Extended Latency Analysis
    if ($FullDiagnostics -or $LatencySamples -gt 4) {
        Write-Host ""
        Write-Log "Performing extended latency analysis..." -Level Info
        $diagnosticsData.Latency = Test-NetworkLatency -Target $Target -Count $LatencySamples
        
        Write-Host "  Avg: $($diagnosticsData.Latency.AvgLatency)ms | Jitter: $($diagnosticsData.Latency.Jitter)ms | Loss: $($diagnosticsData.Latency.PacketLoss)%"
    }
    
    # Test 6: Port Scanning
    if ($TestPorts -or $FullDiagnostics) {
        Write-Host ""
        Write-Log "Testing port connectivity..." -Level Info
        
        $portsToTest = if ($TestPorts) { $TestPorts } else { @(80, 443, 22, 3389) }
        $diagnosticsData.PortScan = Test-PortConnectivity -Target $Target -Ports $portsToTest
        
        $openPorts = ($diagnosticsData.PortScan | Where-Object { $_.Open }).Count
        Write-Host "  Open Ports: $openPorts / $($diagnosticsData.PortScan.Count)"
    }
    
    # Test 7: Traceroute
    if ($FullDiagnostics) {
        Write-Host ""
        Write-Log "Tracing network path..." -Level Info
        $diagnosticsData.Traceroute = Get-NetworkPath -Target $Target -ResolveNames
        
        Write-Host "  Hops: $($diagnosticsData.Traceroute.TotalHops) | Reaches Target: $($diagnosticsData.Traceroute.ReachesTarget)"
    }
    
    # Generate Report
    Write-Host ""
    Write-Log "Generating report..." -Level Info
    
    $reportFileName = "NetworkDiag_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportPath = Join-Path $ExportPath $reportFileName
    
    $generatedReport = New-NetworkDiagnosticsReport -DiagnosticsData $diagnosticsData -OutputPath $reportPath
    
    # Summary
    $endTime = Get-Date
    $duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    Diagnostics Summary                         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $inetIcon = if ($diagnosticsData.InternetConnectivity.HasInternet) { "✓" } else { "✗" }
    $targetIcon = if ($diagnosticsData.BasicConnectivity.Reachable) { "✓" } else { "✗" }
    
    Write-Host "  [$inetIcon] Internet Connectivity"
    Write-Host "  [$targetIcon] Target Reachability ($Target)"
    Write-Host "  [*] Network Adapters: $($diagnosticsData.AdapterHealth.HealthStatus)"
    Write-Host "  [*] DNS Servers: $workingDNS operational"
    Write-Host ""
    Write-Host "  Report: $reportPath" -ForegroundColor Cyan
    Write-Host "  Duration: $duration seconds" -ForegroundColor Gray
    Write-Host ""
    
    # Open report
    $openReport = Read-Host "Open report in browser? (Y/N)"
    if ($openReport -eq 'Y') {
        Start-Process $reportPath
    }
    
    return $diagnosticsData
}

#endregion

#region Quick Functions

function Test-QuickConnectivity {
    <#
    .SYNOPSIS
        Quick connectivity test to common targets
    #>
    param(
        [string[]]$Targets = @("8.8.8.8", "1.1.1.1", "google.com", "microsoft.com")
    )
    
    Write-Host "`nQuick Connectivity Test" -ForegroundColor Cyan
    Write-Host "─" * 50
    
    foreach ($target in $Targets) {
        $result =
