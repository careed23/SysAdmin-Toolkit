<#
.SYNOPSIS
    Network Discovery and Mapping Script
    
.DESCRIPTION
    Comprehensive network discovery tool including:
    - IP range scanning and host discovery
    - Service detection and fingerprinting
    - Network device identification
    - MAC address vendor lookup
    - Active Directory computer discovery
    - Network topology mapping
    - Subnet analysis and documentation
    
.PARAMETER IPRange
    IP range to scan (e.g., "192.168.1.0/24" or "192.168.1.1-254")

.PARAMETER ScanType
    Type of scan: Quick, Standard, Full, Stealth

.PARAMETER ExportPath
    Path to export results

.EXAMPLE
    Start-NetworkDiscovery -IPRange "192.168.1.0/24"
    
.EXAMPLE
    Start-NetworkDiscovery -IPRange "10.0.0.1-50" -ScanType Full -ExportPath "C:\Reports"

.EXAMPLE
    Find-NetworkDevices -Subnet "192.168.1.0/24" -IdentifyVendors

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Note: Some features require administrator privileges
#>

#region Configuration

$script:Config = @{
    # Scan settings
    DefaultTimeout = 100  # milliseconds for ping
    PortScanTimeout = 500
    MaxConcurrentScans = 50
    
    # Common ports for service detection
    QuickScanPorts = @(22, 80, 443, 445, 3389)
    StandardScanPorts = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 993, 995, 1433, 3306, 3389, 5432, 5900, 8080)
    FullScanPorts = @(20, 21, 22, 23, 25, 53, 67, 68, 69, 80, 110, 111, 123, 135, 137, 138, 139, 143, 161, 162, 389, 443, 445, 465, 514, 587, 636, 993, 995, 1433, 1521, 2049, 3306, 3389, 5060, 5432, 5900, 5985, 5986, 6379, 8080, 8443, 9090, 27017)
    
    # Service signatures
    ServiceSignatures = @{
        21 = "FTP"
        22 = "SSH"
        23 = "Telnet"
        25 = "SMTP"
        53 = "DNS"
        67 = "DHCP Server"
        68 = "DHCP Client"
        69 = "TFTP"
        80 = "HTTP"
        110 = "POP3"
        111 = "RPC"
        123 = "NTP"
        135 = "RPC/DCOM"
        137 = "NetBIOS-NS"
        138 = "NetBIOS-DGM"
        139 = "NetBIOS-SSN"
        143 = "IMAP"
        161 = "SNMP"
        162 = "SNMP Trap"
        389 = "LDAP"
        443 = "HTTPS"
        445 = "SMB"
        465 = "SMTPS"
        514 = "Syslog"
        587 = "SMTP Submission"
        636 = "LDAPS"
        993 = "IMAPS"
        995 = "POP3S"
        1433 = "MSSQL"
        1521 = "Oracle"
        2049 = "NFS"
        3306 = "MySQL"
        3389 = "RDP"
        5060 = "SIP"
        5432 = "PostgreSQL"
        5900 = "VNC"
        5985 = "WinRM HTTP"
        5986 = "WinRM HTTPS"
        6379 = "Redis"
        8080 = "HTTP Proxy"
        8443 = "HTTPS Alt"
        9090 = "Web Console"
        27017 = "MongoDB"
    }
    
    # Device type signatures based on open ports
    DeviceSignatures = @{
        "Windows Server" = @(135, 139, 445, 3389, 5985)
        "Windows Client" = @(135, 139, 445, 3389)
        "Linux/Unix" = @(22)
        "Web Server" = @(80, 443)
        "Database Server" = @(1433, 3306, 5432, 1521)
        "Network Device" = @(22, 23, 161)
        "Printer" = @(515, 631, 9100)
        "Mail Server" = @(25, 110, 143, 465, 587, 993, 995)
        "Domain Controller" = @(53, 88, 389, 636, 445)
    }
    
    # Report settings
    DefaultReportPath = ".\reports\discovery"
    
    # MAC vendor API (free tier)
    MACVendorAPI = "https://api.macvendors.com/"
}

# MAC Vendor cache to avoid repeated API calls
$script:MACVendorCache = @{}

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

function Convert-CIDRToIPRange {
    <#
    .SYNOPSIS
        Converts CIDR notation to IP range
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CIDR
    )
    
    if ($CIDR -match "^(\d+\.\d+\.\d+\.\d+)/(\d+)$") {
        $networkAddress = $Matches[1]
        $prefixLength = [int]$Matches[2]
        
        $ipBytes = [System.Net.IPAddress]::Parse($networkAddress).GetAddressBytes()
        [Array]::Reverse($ipBytes)
        $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
        
        $maskInt = [uint32]::MaxValue -shl (32 - $prefixLength)
        $networkInt = $ipInt -band $maskInt
        $broadcastInt = $networkInt -bor (-bnot $maskInt)
        
        $startIP = $networkInt + 1
        $endIP = $broadcastInt - 1
        
        return @{
            NetworkAddress = $networkAddress
            PrefixLength = $prefixLength
            StartIP = $startIP
            EndIP = $endIP
            TotalHosts = $endIP - $startIP + 1
        }
    }
    
    return $null
}

function Convert-IntToIP {
    param([uint32]$Int)
    
    $bytes = [BitConverter]::GetBytes($Int)
    [Array]::Reverse($bytes)
    return [System.Net.IPAddress]::new($bytes).ToString()
}

function Convert-IPToInt {
    param([string]$IP)
    
    $bytes = [System.Net.IPAddress]::Parse($IP).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Get-IPRangeFromString {
    <#
    .SYNOPSIS
        Parses various IP range formats and returns array of IPs
    #>
    param(
        [Parameter(Mandatory)]
        [string]$IPRange
    )
    
    $ips = @()
    
    # CIDR notation (e.g., 192.168.1.0/24)
    if ($IPRange -match "^(\d+\.\d+\.\d+\.\d+)/(\d+)$") {
        $range = Convert-CIDRToIPRange -CIDR $IPRange
        for ($i = $range.StartIP; $i -le $range.EndIP; $i++) {
            $ips += Convert-IntToIP -Int $i
        }
    }
    # Range notation (e.g., 192.168.1.1-254)
    elseif ($IPRange -match "^(\d+\.\d+\.\d+)\.(\d+)-(\d+)$") {
        $baseIP = $Matches[1]
        $start = [int]$Matches[2]
        $end = [int]$Matches[3]
        
        for ($i = $start; $i -le $end; $i++) {
            $ips += "$baseIP.$i"
        }
    }
    # Full range notation (e.g., 192.168.1.1-192.168.1.254)
    elseif ($IPRange -match "^(\d+\.\d+\.\d+\.\d+)-(\d+\.\d+\.\d+\.\d+)$") {
        $startInt = Convert-IPToInt -IP $Matches[1]
        $endInt = Convert-IPToInt -IP $Matches[2]
        
        for ($i = $startInt; $i -le $endInt; $i++) {
            $ips += Convert-IntToIP -Int $i
        }
    }
    # Single IP
    elseif ($IPRange -match "^\d+\.\d+\.\d+\.\d+$") {
        $ips += $IPRange
    }
    else {
        Write-Log "Invalid IP range format: $IPRange" -Level Error
    }
    
    return $ips
}

function Test-TCPPort {
    param(
        [string]$IP,
        [int]$Port,
        [int]$Timeout = 500
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($IP, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)
        
        if ($wait) {
            try {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return $true
            }
            catch {
                return $false
            }
        }
        
        $tcpClient.Close()
        return $false
    }
    catch {
        return $false
    }
}

#endregion

#region Host Discovery

function Find-LiveHosts {
    <#
    .SYNOPSIS
        Discovers live hosts in an IP range using ICMP ping
    
    .PARAMETER IPRange
        IP range to scan
    
    .PARAMETER Timeout
        Ping timeout in milliseconds
    
    .PARAMETER ThrottleLimit
        Maximum concurrent pings
    
    .EXAMPLE
        Find-LiveHosts -IPRange "192.168.1.0/24"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPRange,
        
        [int]$Timeout = 100,
        
        [int]$ThrottleLimit = 100
    )
    
    $ips = Get-IPRangeFromString -IPRange $IPRange
    
    if (-not $ips) {
        Write-Log "No valid IPs to scan" -Level Error
        return @()
    }
    
    Write-Log "Scanning $($ips.Count) IP addresses..." -Level Info
    
    $liveHosts = @()
    $scannedCount = 0
    $startTime = Get-Date
    
    # Use runspaces for parallel scanning
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
    $runspacePool.Open()
    
    $jobs = @()
    
    $scriptBlock = {
        param($IP, $Timeout)
        
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $result = $ping.Send($IP, $Timeout)
            
            if ($result.Status -eq 'Success') {
                return @{
                    IP = $IP
                    Status = 'Up'
                    ResponseTime = $result.RoundtripTime
                    TTL = $result.Options.Ttl
                }
            }
        }
        catch {
            # Ignore errors
        }
        
        return $null
    }
    
    foreach ($ip in $ips) {
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($ip).AddArgument($Timeout)
        $powershell.RunspacePool = $runspacePool
        
        $jobs += @{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            IP = $ip
        }
    }
    
    # Collect results
    foreach ($job in $jobs) {
        $result = $job.PowerShell.EndInvoke($job.Handle)
        
        if ($result) {
            $liveHosts += [PSCustomObject]$result
        }
        
        $job.PowerShell.Dispose()
        $scannedCount++
        
        # Progress update every 50 hosts
        if ($scannedCount % 50 -eq 0) {
            $percent = [math]::Round(($scannedCount / $ips.Count) * 100)
            Write-Progress -Activity "Scanning Network" -Status "$scannedCount of $($ips.Count) IPs scanned" -PercentComplete $percent
        }
    }
    
    Write-Progress -Activity "Scanning Network" -Completed
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    $duration = (Get-Date) - $startTime
    Write-Log "Scan complete. Found $($liveHosts.Count) live hosts in $([math]::Round($duration.TotalSeconds, 2)) seconds" -Level Success
    
    return $liveHosts | Sort-Object { [Version]$_.IP }
}

function Find-LiveHostsARP {
    <#
    .SYNOPSIS
        Discovers hosts using ARP cache and requests (faster for local subnet)
    #>
    [CmdletBinding()]
    param(
        [string]$Subnet
    )
    
    Write-Log "Checking ARP cache and performing ARP discovery..." -Level Info
    
    $arpResults = @()
    
    # Get current ARP cache
    try {
        $arpCache = Get-NetNeighbor -State Reachable, Stale, Permanent -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -notmatch '^(169\.254|224\.|255\.)' }
        
        foreach ($entry in $arpCache) {
            $arpResults += [PSCustomObject]@{
                IPAddress = $entry.IPAddress
                MACAddress = $entry.LinkLayerAddress
                State = $entry.State
                InterfaceAlias = $entry.InterfaceAlias
            }
        }
    }
    catch {
        Write-Log "Could not retrieve ARP cache: $_" -Level Warning
    }
    
    return $arpResults
}

#endregion

#region Service Detection

function Get-HostServices {
    <#
    .SYNOPSIS
        Scans a host for open ports and identifies services
    
    .PARAMETER IP
        Target IP address
    
    .PARAMETER Ports
        Ports to scan
    
    .PARAMETER Timeout
        Connection timeout in milliseconds
    
    .EXAMPLE
        Get-HostServices -IP "192.168.1.1" -Ports @(22, 80, 443, 3389)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IP,
        
        [int[]]$Ports = $script:Config.StandardScanPorts,
        
        [int]$Timeout = 500
    )
    
    $services = @()
    
    foreach ($port in $Ports) {
        $isOpen = Test-TCPPort -IP $IP -Port $port -Timeout $Timeout
        
        if ($isOpen) {
            $serviceName = if ($script:Config.ServiceSignatures.ContainsKey($port)) {
                $script:Config.ServiceSignatures[$port]
            } else {
                "Unknown"
            }
            
            $services += [PSCustomObject]@{
                Port = $port
                State = "Open"
                Service = $serviceName
                Protocol = "TCP"
            }
        }
    }
    
    return $services
}

function Get-ServiceBanner {
    <#
    .SYNOPSIS
        Attempts to grab service banner for fingerprinting
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IP,
        
        [Parameter(Mandatory)]
        [int]$Port,
        
        [int]$Timeout = 2000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = $Timeout
        $tcpClient.SendTimeout = $Timeout
        
        $connect = $tcpClient.BeginConnect($IP, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)
        
        if ($wait -and $tcpClient.Connected) {
            $tcpClient.EndConnect($connect)
            $stream = $tcpClient.GetStream()
            $stream.ReadTimeout = $Timeout
            
            # Send a probe for certain services
            $probe = switch ($Port) {
                80 { "HEAD / HTTP/1.0`r`n`r`n" }
                443 { $null }  # HTTPS needs SSL handling
                21 { $null }   # FTP sends banner automatically
                22 { $null }   # SSH sends banner automatically
                25 { $null }   # SMTP sends banner automatically
                default { $null }
            }
            
            if ($probe) {
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($probe)
                $stream.Write($bytes, 0, $bytes.Length)
            }
            
            # Read response
            Start-Sleep -Milliseconds 500
            
            if ($stream.DataAvailable) {
                $buffer = New-Object byte[] 1024
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                $banner = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
                
                $tcpClient.Close()
                return $banner.Trim()
            }
        }
        
        $tcpClient.Close()
    }
    catch {
        # Ignore errors
    }
    
    return $null
}

function Identify-DeviceType {
    <#
    .SYNOPSIS
        Attempts to identify device type based on open ports and other characteristics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int[]]$OpenPorts,
        
        [string]$Hostname,
        
        [int]$TTL
    )
    
    $scores = @{}
    
    foreach ($deviceType in $script:Config.DeviceSignatures.Keys) {
        $signaturePorts = $script:Config.DeviceSignatures[$deviceType]
        $matchCount = ($signaturePorts | Where-Object { $_ -in $OpenPorts }).Count
        $score = $matchCount / $signaturePorts.Count
        
        if ($score -gt 0) {
            $scores[$deviceType] = $score
        }
    }
    
    # TTL-based OS detection
    $osGuess = switch ($TTL) {
        { $_ -le 64 } { "Linux/Unix" }
        { $_ -le 128 } { "Windows" }
        { $_ -le 255 } { "Network Device" }
        default { "Unknown" }
    }
    
    # Get best match
    $bestMatch = $scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    
    if ($bestMatch -and $bestMatch.Value -ge 0.5) {
        return $bestMatch.Name
    } elseif ($osGuess) {
        return $osGuess
    }
    
    return "Unknown"
}

#endregion

#region MAC Address Lookup

function Get-MACVendor {
    <#
    .SYNOPSIS
        Looks up MAC address vendor using API
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MACAddress
    )
    
    # Normalize MAC address
    $normalizedMAC = $MACAddress -replace '[:-]', '' -replace '(.{2})(?=.)', '$1:'
    $prefix = ($normalizedMAC -split ':')[0..2] -join ':'
    
    # Check cache first
    if ($script:MACVendorCache.ContainsKey($prefix)) {
        return $script:MACVendorCache[$prefix]
    }
    
    try {
        $vendor = Invoke-RestMethod -Uri "$($script:Config.MACVendorAPI)$prefix" -TimeoutSec 5 -ErrorAction Stop
        $script:MACVendorCache[$prefix] = $vendor
        return $vendor
    }
    catch {
        # API rate limiting or not found
        return "Unknown"
    }
}

function Get-LocalMACAddresses {
    <#
    .SYNOPSIS
        Gets MAC addresses from local ARP cache with vendor lookup
    #>
    [CmdletBinding()]
    param(
        [switch]$ResolveVendors
    )
    
    $arpEntries = Get-NetNeighbor -State Reachable, Stale, Permanent -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' }
    
    $results = @()
    
    foreach ($entry in $arpEntries) {
        $result = [PSCustomObject]@{
            IPAddress = $entry.IPAddress
            MACAddress = $entry.LinkLayerAddress
            Vendor = "Not Resolved"
            State = $entry.State
            Interface = $entry.InterfaceAlias
        }
        
        if ($ResolveVendors) {
            $result.Vendor = Get-MACVendor -MACAddress $entry.LinkLayerAddress
            Start-Sleep -Milliseconds 500  # Rate limiting
        }
        
        $results += $result
    }
    
    return $results
}

#endregion

#region Network Information

function Get-SubnetInfo {
    <#
    .SYNOPSIS
        Gets detailed information about a subnet
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CIDR
    )
    
    $range = Convert-CIDRToIPRange -CIDR $CIDR
    
    if (-not $range) {
        Write-Log "Invalid CIDR notation" -Level Error
        return $null
    }
    
    $networkInt = $range.StartIP - 1
    $broadcastInt = $range.EndIP + 1
    
    $info = [PSCustomObject]@{
        CIDR = $CIDR
        NetworkAddress = Convert-IntToIP -Int $networkInt
        BroadcastAddress = Convert-IntToIP -Int $broadcastInt
        FirstUsableIP = Convert-IntToIP -Int $range.StartIP
        LastUsableIP = Convert-IntToIP -Int $range.EndIP
        SubnetMask = Get-SubnetMask -PrefixLength $range.PrefixLength
        TotalHosts = $range.TotalHosts
        PrefixLength = $range.PrefixLength
    }
    
    return $info
}

function Get-SubnetMask {
    param([int]$PrefixLength)
    
    $maskInt = [uint32]::MaxValue -shl (32 - $PrefixLength)
    return Convert-IntToIP -Int $maskInt
}

function Get-LocalNetworkInfo {
    <#
    .SYNOPSIS
        Gets information about local network configuration
    #>
    [CmdletBinding()]
    param()
    
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    $results = @()
    
    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -ne 'WellKnown' }
        
        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        
        $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        
        foreach ($ip in $ipConfig) {
            $cidr = "$($ip.IPAddress)/$($ip.PrefixLength)"
            $subnetInfo = Get-SubnetInfo -CIDR $cidr
            
            $results += [PSCustomObject]@{
                AdapterName = $adapter.Name
                Description = $adapter.InterfaceDescription
                IPAddress = $ip.IPAddress
                PrefixLength = $ip.PrefixLength
                SubnetMask = $subnetInfo.SubnetMask
                NetworkAddress = $subnetInfo.NetworkAddress
                BroadcastAddress = $subnetInfo.BroadcastAddress
                Gateway = $gateway.NextHop
                DNSServers = $dnsServers.ServerAddresses -join ', '
                MACAddress = $adapter.MacAddress
                LinkSpeed = $adapter.LinkSpeed
                UsableHosts = $subnetInfo.TotalHosts
            }
        }
    }
    
    return $results
}

#endregion

#region Active Directory Discovery

function Find-ADComputers {
    <#
    .SYNOPSIS
        Discovers computers from Active Directory
    
    .PARAMETER SearchBase
        OU to search (optional)
    
    .PARAMETER Filter
        AD filter (optional)
    
    .PARAMETER OnlineOnly
        Only return computers that respond to ping
    
    .EXAMPLE
        Find-ADComputers -OnlineOnly
    
    .EXAMPLE
        Find-ADComputers -SearchBase "OU=Servers,DC=domain,DC=com"
    #>
    [CmdletBinding()]
    param(
        [string]$SearchBase,
        
        [string]$Filter = "*",
        
        [switch]$OnlineOnly,
        
        [switch]$IncludeServices
    )
    
    # Check for AD module
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Log "ActiveDirectory module not available" -Level Warning
        return @()
    }
    
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    
    Write-Log "Querying Active Directory for computers..." -Level Info
    
    $params = @{
        Filter = "Name -like '$Filter'"
        Properties = @('Name', 'DNSHostName', 'IPv4Address', 'OperatingSystem', 'OperatingSystemVersion', 
                      'LastLogonDate', 'Created', 'Description', 'Enabled', 'DistinguishedName')
    }
    
    if ($SearchBase) {
        $params.SearchBase = $SearchBase
    }
    
    try {
        $computers = Get-ADComputer @params
    }
    catch {
        Write-Log "Failed to query AD: $_" -Level Error
        return @()
    }
    
    Write-Log "Found $($computers.Count) computers in AD" -Level Info
    
    $results = @()
    $count = 0
    
    foreach ($computer in $computers) {
        $count++
        Write-Progress -Activity "Processing AD Computers" -Status "$count of $($computers.Count)" -PercentComplete (($count / $computers.Count) * 100)
        
        $result = [PSCustomObject]@{
            Name = $computer.Name
            DNSHostName = $computer.DNSHostName
            IPv4Address = $computer.IPv4Address
            OperatingSystem = $computer.OperatingSystem
            OSVersion = $computer.OperatingSystemVersion
            LastLogon = $computer.LastLogonDate
            Created = $computer.Created
            Description = $computer.Description
            Enabled = $computer.Enabled
            OU = ($computer.DistinguishedName -split ',', 2)[1]
            Online = $null
            ResponseTime = $null
            OpenPorts = @()
        }
        
        # Check if online
        if ($OnlineOnly -or $IncludeServices) {
            if ($computer.DNSHostName -or $computer.IPv4Address) {
                $target = if ($computer.IPv4Address) { $computer.IPv4Address } else { $computer.DNSHostName }
                
                $pingResult = Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue
                $result.Online = $pingResult
                
                if ($pingResult -and $IncludeServices) {
                    $services = Get-HostServices -IP $target -Ports $script:Config.QuickScanPorts -Timeout 200
                    $result.OpenPorts = $services.Port
                }
            }
        }
        
        if (-not $OnlineOnly -or $result.Online) {
            $results += $result
        }
    }
    
    Write-Progress -Activity "Processing AD Computers" -Completed
    
    return $results
}

function Find-ADServers {
    <#
    .SYNOPSIS
        Finds servers in AD by OS type
    #>
    [CmdletBinding()]
    param()
    
    $servers = Find-ADComputers -Filter "*" | 
        Where-Object { $_.OperatingSystem -like "*Server*" }
    
    return $servers
}

function Find-DomainControllers {
    <#
    .SYNOPSIS
        Finds all domain controllers
    #>
    [CmdletBinding()]
    param(
        [switch]$TestConnectivity
    )
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        $dcs = Get-ADDomainController -Filter *
        
        $results = foreach ($dc in $dcs) {
            $result = [PSCustomObject]@{
                Name = $dc.Name
                HostName = $dc.HostName
                IPv4Address = $dc.IPv4Address
                Site = $dc.Site
                IsGlobalCatalog = $dc.IsGlobalCatalog
                IsReadOnly = $dc.IsReadOnly
                OperatingSystem = $dc.OperatingSystem
                Online = $null
                ResponseTime = $null
            }
            
            if ($TestConnectivity) {
                $ping = Test-Connection -ComputerName $dc.HostName -Count 1 -ErrorAction SilentlyContinue
                $result.Online = $null -ne $ping
                $result.ResponseTime = $ping.ResponseTime
            }
            
            $result
        }
        
        return $results
    }
    catch {
        Write-Log "Failed to get domain controllers: $_" -Level Error
        return @()
    }
}

#endregion

#region Network Device Discovery

function Find-NetworkDevices {
    <#
    .SYNOPSIS
        Discovers network devices (routers, switches, printers, etc.)
    
    .PARAMETER Subnet
        Subnet to scan
    
    .PARAMETER IdentifyVendors
        Lookup MAC address vendors
    
    .EXAMPLE
        Find-NetworkDevices -Subnet "192.168.1.0/24" -IdentifyVendors
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subnet,
        
        [switch]$IdentifyVendors,
        
        [switch]$DeepScan
    )
    
    Write-Log "Starting network device discovery on $Subnet..." -Level Info
    
    # Find live hosts
    $liveHosts = Find-LiveHosts -IPRange $Subnet -Timeout 150
    
    if (-not $liveHosts) {
        Write-Log "No live hosts found" -Level Warning
        return @()
    }
    
    Write-Log "Scanning $($liveHosts.Count) live hosts for services..." -Level Info
    
    $devices = @()
    $count = 0
    
    foreach ($host in $liveHosts) {
        $count++
        Write-Progress -Activity "Scanning Devices" -Status "$count of $($liveHosts.Count): $($host.IP)" -PercentComplete (($count / $liveHosts.Count) * 100)
        
        $device = [PSCustomObject]@{
            IPAddress = $host.IP
            Hostname = $null
            MACAddress = $null
            Vendor = $null
            DeviceType = "Unknown"
            TTL = $host.TTL
            ResponseTime = $host.ResponseTime
            OpenPorts = @()
            Services = @()
            LastSeen = Get-Date
        }
        
        # Try to resolve hostname
        try {
            $dns = Resolve-DnsName -Name $host.IP -Type PTR -ErrorAction Stop
            $device.Hostname = $dns.NameHost
        }
        catch {
            # Try NetBIOS
            try {
                $nbtstat = nbtstat -A $host.IP 2>$null
                if ($nbtstat) {
                    $match = $nbtstat | Select-String -Pattern "^\s+(\S+)\s+<00>\s+UNIQUE" | Select-Object -First 1
                    if ($match) {
                        $device.Hostname = $match.Matches.Groups[1].Value
                    }
                }
            }
            catch { }
        }
        
        # Get MAC address from ARP
        try {
            $arp = Get-NetNeighbor -IPAddress $host.IP -ErrorAction SilentlyContinue
            if ($arp) {
                $device.MACAddress = $arp.LinkLayerAddress
                
                if ($IdentifyVendors -and $device.MACAddress) {
                    $device.Vendor = Get-MACVendor -MACAddress $device.MACAddress
                    Start-Sleep -Milliseconds 300  # Rate limiting
                }
            }
        }
        catch { }
        
        # Scan for services
        $ports = if ($DeepScan) { $script:Config.StandardScanPorts } else { $script:Config.QuickScanPorts }
        $services = Get-HostServices -IP $host.IP -Ports $ports -Timeout 300
        
        $device.OpenPorts = $services.Port
        $device.Services = $services
        
        # Identify device type
        $device.DeviceType = Identify-DeviceType -OpenPorts $device.OpenPorts -Hostname $device.Hostname -TTL $device.TTL
        
        $devices += $device
    }
    
    Write-Progress -Activity "Scanning Devices" -Completed
    
    return $devices
}

function Find-Printers {
    <#
    .SYNOPSIS
        Discovers network printers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subnet
    )
    
    Write-Log "Scanning for network printers..." -Level Info
    
    $liveHosts = Find-LiveHosts -IPRange $Subnet -Timeout 150
    $printers = @()
    
    $printerPorts = @(515, 631, 9100, 80, 443)
    
    foreach ($host in $liveHosts) {
        $openPorts = @()
        
        foreach ($port in $printerPorts) {
            if (Test-TCPPort -IP $host.IP -Port $port -Timeout 300) {
                $openPorts += $port
            }
        }
        
        # If printer ports are open
        if ($openPorts -contains 9100 -or $openPorts -contains 515 -or $openPorts -contains 631) {
            $printer = [PSCustomObject]@{
                IPAddress = $host.IP
                Hostname = $null
                OpenPorts = $openPorts
                HasWebInterface = ($openPorts -contains 80 -or $openPorts -contains 443)
                Protocol = @()
            }
            
            if (9100 -in $openPorts) { $printer.Protocol += "RAW/JetDirect" }
            if (515 -in $openPorts) { $printer.Protocol += "LPD" }
            if (631 -in $openPorts) { $printer.Protocol += "IPP" }
            
            # Try to resolve hostname
            try {
                $dns = Resolve-DnsName -Name $host.IP -Type PTR -ErrorAction Stop
                $printer.Hostname = $dns.NameHost
            }
            catch { }
            
            $printers += $printer
        }
    }
    
    Write-Log "Found $($printers.Count) network printers" -Level Success
    
    return $printers
}

function Find-WebServers {
    <#
    .SYNOPSIS
        Discovers web servers on the network
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subnet,
        
        [switch]$GetTitles
    )
    
    Write-Log "Scanning for web servers..." -Level Info
    
    $liveHosts = Find-LiveHosts -IPRange $Subnet -Timeout 150
    $webServers = @()
    
    $webPorts = @(80, 443, 8080, 8443, 8000, 8888)
    
    $count = 0
    foreach ($host in $liveHosts) {
        $count++
        Write-Progress -Activity "Scanning for Web Servers" -Status "$count of $($liveHosts.Count)" -PercentComplete (($count / $liveHosts.Count) * 100)
        
        $openWebPorts = @()
        
        foreach ($port in $webPorts) {
            if (Test-TCPPort -IP $host.IP -Port $port -Timeout 300) {
                $openWebPorts += $port
            }
        }
        
        if ($openWebPorts) {
            $webServer = [PSCustomObject]@{
                IPAddress = $host.IP
                Hostname = $null
                OpenPorts = $openWebPorts
                URLs = @()
                Titles = @()
            }
            
            # Build URLs
            foreach ($port in $openWebPorts) {
                $protocol = if ($port -in @(443, 8443)) { "https" } else { "http" }
                $url = if ($port -in @(80, 443)) { 
                    "$protocol`://$($host.IP)" 
                } else { 
                    "$protocol`://$($host.IP):$port" 
                }
                $webServer.URLs += $url
                
                # Try to get page title
                if ($GetTitles) {
                    try {
                        $response = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                        if ($response.Content -match '<title>([^<]+)</title>') {
                            $webServer.Titles += $Matches[1].Trim()
                        }
                    }
                    catch { }
                }
            }
            
            # Resolve hostname
            try {
                $dns = Resolve-DnsName -Name $host.IP -Type PTR -ErrorAction Stop
                $webServer.Hostname = $dns.NameHost
            }
            catch { }
            
            $webServers += $webServer
        }
    }
    
    Write-Progress -Activity "Scanning for Web Servers" -Completed
    Write-Log "Found $($webServers.Count) web servers" -Level Success
    
    return $webServers
}

#endregion

#region Report Generation

function New-NetworkDiscoveryReport {
    <#
    .SYNOPSIS
        Generates HTML report from network discovery results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DiscoveryData,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Discovery Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #4CAF50 0%, #2E7D32 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 28px; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { color: #2E7D32; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; font-size: 14px; }
        th { background: #f8f9fa; font-weight: 600; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 10px; font-size: 11px; font-weight: bold; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-info { background: #d1ecf1; color: #0c5460; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .stat-card { background: white; padding: 20px; border-radius: 8px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat-value { font-size: 32px; font-weight: bold; color: #2E7D32; }
        .stat-label { color: #666; margin-top: 5px; }
        .port-list { display: flex; flex-wrap: wrap; gap: 5px; }
        .port-badge { background: #e3f2fd; color: #1565c0; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
        .device-type { font-weight: bold; }
        .device-windows { color: #0078d4; }
        .device-linux { color: #ff6600; }
        .device-network { color: #666; }
        .device-printer { color: #9c27b0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Network Discovery Report</h1>
            <div>Scan Target: $($DiscoveryData.ScanTarget) | Generated: $reportDate</div>
        </div>
"@

    # Summary Statistics
    $totalDevices = $DiscoveryData.Devices.Count
    $windowsDevices = ($DiscoveryData.Devices | Where-Object { $_.DeviceType -like "*Windows*" }).Count
    $linuxDevices = ($DiscoveryData.Devices | Where-Object { $_.DeviceType -eq "Linux/Unix" }).Count
    $networkDevices = ($DiscoveryData.Devices | Where-Object { $_.DeviceType -eq "Network Device" }).Count
    $webServers = ($DiscoveryData.Devices | Where-Object { $_.OpenPorts -contains 80 -or $_.OpenPorts -contains 443 }).Count
    
    $html += @"
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value">$totalDevices</div>
                <div class="stat-label">Total Devices</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$windowsDevices</div>
                <div class="stat-label">Windows Systems</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$linuxDevices</div>
                <div class="stat-label">Linux/Unix Systems</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$networkDevices</div>
                <div class="stat-label">Network Devices</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$webServers</div>
                <div class="stat-label">Web Servers</div>
            </div>
        </div>
"@

    # Network Information
    if ($DiscoveryData.NetworkInfo) {
        $html += @"
        <div class="section">
            <h2>📡 Local Network Configuration</h2>
            <table>
                <tr><th>Adapter</th><th>IP Address</th><th>Subnet</th><th>Gateway</th><th>DNS</th></tr>
"@
        foreach ($net in $DiscoveryData.NetworkInfo) {
            $html += "<tr><td>$($net.AdapterName)</td><td>$($net.IPAddress)/$($net.PrefixLength)</td><td>$($net.SubnetMask)</td><td>$($net.Gateway)</td><td>$($net.DNSServers)</td></tr>"
        }
        $html += "</table></div>"
    }

    # Discovered Devices
    if ($DiscoveryData.Devices) {
        $html += @"
        <div class="section">
            <h2>💻 Discovered Devices</h2>
            <table>
                <tr><th>IP Address</th><th>Hostname</th><th>Device Type</th><th>MAC Address</th><th>Vendor</th><th>Open Ports</th><th>Response Time</th></tr>
"@
        foreach ($device in $DiscoveryData.Devices | Sort-Object { [Version]$_.IPAddress }) {
            $typeClass = switch -Wildcard ($device.DeviceType) {
                "*Windows*" { "device-windows" }
                "Linux/Unix" { "device-linux" }
                "Network Device" { "device-network" }
                "*Printer*" { "device-printer" }
                default { "" }
            }
            
            $portBadges = ($device.OpenPorts | ForEach-Object { "<span class='port-badge'>$_</span>" }) -join ''
            
            $html += @"
                <tr>
                    <td>$($device.IPAddress)</td>
                    <td>$($device.Hostname)</td>
                    <td><span class="device-type $typeClass">$($device.DeviceType)</span></td>
                    <td>$($device.MACAddress)</td>
                    <td>$($device.Vendor)</td>
                    <td><div class="port-list">$portBadges</div></td>
                    <td>$($device.ResponseTime)ms</td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # AD Computers (if available)
    if ($DiscoveryData.ADComputers) {
        $html += @"
        <div class="section">
            <h2>🏢 Active Directory Computers</h2>
            <table>
                <tr><th>Name</th><th>IP Address</th><th>Operating System</th><th>Last Logon</th><th>Status</th></tr>
"@
        foreach ($computer in $DiscoveryData.ADComputers | Sort-Object Name) {
            $statusBadge = if ($computer.Online -eq $true) { 
                "<span class='badge badge-success'>Online</span>" 
            } elseif ($computer.Online -eq $false) { 
                "<span class='badge badge-warning'>Offline</span>" 
            } else { 
                "<span class='badge badge-info'>Unknown</span>" 
            }
            
            $html += @"
                <tr>
                    <td>$($computer.Name)</td>
                    <td>$($computer.IPv4Address)</td>
                    <td>$($computer.OperatingSystem)</td>
                    <td>$($computer.LastLogon)</td>
                    <td>$statusBadge</td>
                </tr>
"@
        }
        $html += "</table></div>"
    }

    # Domain Controllers (if available)
    if ($DiscoveryData.DomainControllers) {
        $html += @"
        <div class="section">
            <h2>🏰 Domain Controllers</h2>
            <table>
                <tr><th>Name</th><th>IP Address</th><th>Site</th><th>Global Catalog</th><th>Operating System</th></tr>
"@
        foreach ($dc in $DiscoveryData.DomainControllers) {
            $gcBadge = if ($dc.IsGlobalCatalog) { "<span class='badge badge-success'>Yes</span>" } else { "<span class='badge badge-info'>No</span>" }
            
            $html += "<tr><td>$($dc.Name)</td><td>$($dc.IPv4Address)</td><td>$($dc.Site)</td><td>$gcBadge</td><td>$($dc.OperatingSystem)</td></tr>"
        }
        $html += "</table></div>"
    }

    # Service Summary
    if ($DiscoveryData.Devices) {
        $serviceSummary = @{}
        foreach ($device in $DiscoveryData.Devices) {
            foreach ($port in $device.OpenPorts) {
                $serviceName = if ($script:Config.ServiceSignatures.ContainsKey($port)) { 
                    $script:Config.ServiceSignatures[$port] 
                } else { 
                    "Port $port" 
                }
                
                if (-not $serviceSummary.ContainsKey($serviceName)) {
                    $serviceSummary[$serviceName] = 0
                }
                $serviceSummary[$serviceName]++
            }
        }
        
        if ($serviceSummary.Count -gt 0) {
            $html += @"
        <div class="section">
            <h2>📊 Service Summary</h2>
            <table>
                <tr><th>Service</th><th>Count</th><th>Hosts</th></tr>
"@
            foreach ($service in $serviceSummary.GetEnumerator() | Sort-Object Value -Descending) {
                $html += "<tr><td>$($service.Name)</td><td>$($service.Value)</td><td>"
                
                $port = ($script:Config.ServiceSignatures.GetEnumerator() | Where-Object { $_.Value -eq $service.Name }).Name
                if ($port) {
                    $hosts = ($DiscoveryData.Devices | Where-Object { $_.OpenPorts -contains $port }).IPAddress -join ', '
                    $html += $hosts
                }
                
                $html += "</td></tr>"
            }
            $html += "</table></div>"
        }
    }

    # Footer
    $html += @"
        <div style="text-align: center; color: #666; margin-top: 30px; font-size: 12px;">
            <p>Generated by SysAdmin Toolkit Network Discovery | Scan Duration: $($DiscoveryData.ScanDuration) seconds</p>
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

function Start-NetworkDiscovery {
    <#
    .SYNOPSIS
        Runs comprehensive network discovery
    
    .DESCRIPTION
        Discovers and documents all devices on a network segment
    
    .PARAMETER IPRange
        IP range to scan (CIDR or range notation)
    
    .PARAMETER ScanType
        Quick, Standard, or Full scan
    
    .PARAMETER IncludeAD
        Include Active Directory computer discovery
    
    .PARAMETER IdentifyVendors
        Lookup MAC address vendors
    
    .PARAMETER ExportPath
        Path for HTML report
    
    .EXAMPLE
        Start-NetworkDiscovery -IPRange "192.168.1.0/24"
    
    .EXAMPLE
        Start-NetworkDiscovery -IPRange "10.0.0.0/24" -ScanType Full -IncludeAD -IdentifyVendors
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPRange,
        
        [ValidateSet('Quick', 'Standard', 'Full')]
        [string]$ScanType = 'Standard',
        
        [switch]$IncludeAD,
        
        [switch]$IdentifyVendors,
        
        [string]$ExportPath = $script:Config.DefaultReportPath
    )
    
    $startTime = Get-Date
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              Network Discovery Scanner                         ║" -ForegroundColor Green
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Target: $IPRange" -ForegroundColor Cyan
    Write-Host "  Scan Type: $ScanType" -ForegroundColor Cyan
    Write-Host ""
    
    # Create export directory
    if (-not (Test-Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }
    
    # Initialize results
    $discoveryData = @{
        ScanTarget = $IPRange
        ScanType = $ScanType
        StartTime = $startTime
        NetworkInfo = $null
        Devices = @()
        ADComputers = @()
        DomainControllers = @()
        ScanDuration = $null
    }
    
    # Get local network info
    Write-Log "Gathering local network information..." -Level Info
    $discoveryData.NetworkInfo = Get-LocalNetworkInfo
    
    # Run network device discovery
    Write-Host ""
    Write-Log "Starting device discovery..." -Level Info
    $deepScan = ($ScanType -eq 'Full')
    $discoveryData.Devices = Find-NetworkDevices -Subnet $IPRange -IdentifyVendors:$IdentifyVendors -DeepScan:$deepScan
    
    # AD Discovery
    if ($IncludeAD) {
        Write-Host ""
        Write-Log "Querying Active Directory..." -Level Info
        
        try {
            $discoveryData.ADComputers = Find-ADComputers -OnlineOnly:$false
            $discoveryData.DomainControllers = Find-DomainControllers -TestConnectivity
        }
        catch {
            Write-Log "AD discovery failed: $_" -Level Warning
        }
    }
    
    # Calculate duration
    $endTime = Get-Date
    $discoveryData.ScanDuration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    
    # Generate report
    Write-Host ""
    Write-Log "Generating report..." -Level Info
    
    $reportFileName = "NetworkDiscovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportPath = Join-Path $ExportPath $reportFileName
    
    $generatedReport = New-NetworkDiscoveryReport -DiscoveryData $discoveryData -OutputPath $reportPath
    
    # Summary
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    Discovery Summary                           ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "  Total Devices Found:   $($discoveryData.Devices.Count)" -ForegroundColor White
    
    # Device type breakdown
    $deviceTypes = $discoveryData.Devices | Group-Object DeviceType
    foreach ($type in $deviceTypes | Sort-Object Count -Descending) {
        Write-Host "    - $($type.Name): $($type.Count)" -ForegroundColor Gray
    }
    
    if ($IncludeAD) {
        Write-Host ""
        Write-Host "  AD Computers:          $($discoveryData.ADComputers.Count)" -ForegroundColor White
        Write-Host "  Domain Controllers:    $($discoveryData.DomainControllers.Count)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "  Report: $reportPath" -ForegroundColor Cyan
    Write-Host "  Scan Duration: $($discoveryData.ScanDuration) seconds" -ForegroundColor Gray
    Write-Host ""
    
    # Open report
    $openReport = Read-Host "Open report in browser? (Y/N)"
    if ($openReport -eq 'Y') {
        Start-Process $reportPath
    }
    
    return $discoveryData
}

#endregion

#region Quick Functions

function Get-QuickScan {
    <#
    .SYNOPSIS
        Quick scan of common local subnets
    #>
    param(
        [string]$Subnet
    )
    
    if (-not $Subnet) {
        # Auto-detect local subnet
        $localNet = Get-LocalNetworkInfo | Select-Object -First 1
        if ($localNet) {
            $Subnet = "$($localNet.NetworkAddress)/$($localNet.PrefixLength)"
        } else {
            Write-Log "Could not detect local network" -Level Error
            return
        }
    }
    
    Write-Host "Quick scanning $Subnet..." -ForegroundColor Cyan
    $hosts = Find-LiveHosts -IPRange $Subnet -Timeout 100
    
    Write-Host "`nLive Hosts:" -ForegroundColor Green
    $hosts | Format-Table IP, ResponseTime, TTL -AutoSize
    
    return $hosts
}

function Get-NetworkMap {
    <#
    .SYNOPSIS
        Creates a simple text-based network map
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Subnet
    )
    
    $devices = Find-NetworkDevices -Subnet $Subnet
    
    Write-Host "`n===== Network Map: $Subnet =====" -ForegroundColor Cyan
    Write-Host ""
    
    $grouped = $devices | Group-Object DeviceType
    
    foreach ($group in $grouped | Sort-Object Name) {
        Write-Host "[$($group.Name)]" -ForegroundColor Yellow
        foreach ($device in $group.Group | Sort-Object { [Version]$_.IPAddress }) {
            $name = if ($device.Hostname) { $device.Hostname } else { "Unknown" }
            $ports = if ($device.OpenPorts) { "Ports: $($device.OpenPorts -join ',')" } else { "" }
            Write-Host "  ├── $($device.IPAddress.PadRight(15)) $($name.PadRight(30)) $ports" -ForegroundColor White
        }
        Write-Host ""
    }
}

function Export-DeviceInventory {
    <#
    .SYNOPSIS
        Exports discovered devices to CSV
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Subnet,
        
        [string]$OutputPath = ".\device-inventory.csv"
    )
    
    $devices = Find-NetworkDevices -Subnet $Subnet -IdentifyVendors
    
    $devices | Select-Object IPAddress, Hostname, DeviceType, MACAddress, Vendor, 
        @{N='OpenPorts';E={$_.OpenPorts -join ';'}}, ResponseTime, LastSeen |
        Export-Csv -Path $OutputPath -NoTypeInformation
    
    Write-Log "Inventory exported to: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

# Export functions
Export-ModuleMember -Function Start-NetworkDiscovery, Find-LiveHosts, Find-NetworkDevices,
    Find-ADComputers, Find-DomainControllers, Find-Printers, Find-WebServers,
    Get-HostServices, Get-LocalNetworkInfo, Get-SubnetInfo, Get-QuickScan,
    Get-NetworkMap, Export-DeviceInventory, Get-LocalMACAddresses

# Display available commands
Write-Host ""
Write-Host "Network Discovery Module Loaded" -ForegroundColor Green
Write-Host "Available commands:" -ForegroundColor Cyan
Write-Host "  Start-NetworkDiscovery  - Full network discovery scan"
Write-Host "  Get-QuickScan           - Quick ping sweep"
Write-Host "  Find-Network
