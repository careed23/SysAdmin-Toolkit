# 🌐 Network Diagnostics Scripts

A comprehensive suite of PowerShell scripts for network troubleshooting, discovery, and documentation. These tools help system administrators diagnose connectivity issues, discover network devices, and maintain accurate VLAN documentation.

## 📁 Scripts in This Directory

|
 Script 
|
 Description 
|
|
--------
|
-------------
|
|
`Network-Diagnostics.ps1`
|
 Comprehensive network connectivity testing and troubleshooting 
|
|
`Network-Discovery.ps1`
|
 Network scanning, host discovery, and device identification 
|
|
`VLAN-Documentation.ps1`
|
 VLAN inventory, analysis, and documentation generation 
|

---

## 🔧 Network-Diagnostics.ps1

### Overview
A complete network diagnostics toolkit for testing connectivity, analyzing latency, checking DNS resolution, and identifying network issues.

### Features
- ✅ Basic connectivity testing (ping, latency, packet loss)
- ✅ TCP port connectivity scanning
- ✅ DNS resolution and server testing
- ✅ Network path analysis (traceroute)
- ✅ Network adapter diagnostics and health checks
- ✅ Internet connectivity verification
- ✅ Bandwidth estimation
- ✅ Automated HTML report generation

### Quick Start

```powershell
# Load the script
. .\Network-Diagnostics.ps1

# Run basic diagnostics against a target
Start-NetworkDiagnostics -Target "google.com"

# Run full diagnostics with all tests
Start-NetworkDiagnostics -Target "192.168.1.1" -FullDiagnostics

# Run diagnostics with custom port testing
Start-NetworkDiagnostics -Target "server01" -TestPorts 80,443,3389,5985
Available Functions
Main Functions
Function	Description
Start-NetworkDiagnostics	Run comprehensive network diagnostics
Test-BasicConnectivity	Test ping connectivity to a target
Test-PortConnectivity	Test TCP port accessibility
Test-InternetConnectivity	Verify internet access
DNS Functions
Function	Description
Test-DNSResolution	Query DNS records for a domain
Test-DNSServers	Test multiple DNS server performance
Test-DNSPropagation	Check DNS propagation across servers
Analysis Functions
Function	Description
Get-NetworkPath	Trace network route to destination
Test-NetworkLatency	Extended latency analysis with statistics
Test-BandwidthEstimate	Estimate available bandwidth
Adapter Functions
Function	Description
Get-NetworkAdapterDiagnostics	Get detailed adapter information
Test-NetworkAdapterHealth	Check for adapter issues
Reset-NetworkAdapter	Reset a network adapter
Examples
powershell
# Test connectivity with detailed results
$results = Test-BasicConnectivity -Target "10.0.0.1" -Count 10
$results | Format-List

# Check specific ports on a server
Test-PortConnectivity -Target "fileserver" -Ports 445,139,3389

# Test all common service ports
Test-CommonServices -Target "webserver01" -ServiceCategory Web

# Analyze DNS performance
Test-DNSServers -IncludePublicDNS | Format-Table

# Extended latency test with statistics
$latency = Test-NetworkLatency -Target "8.8.8.8" -Count 50
Write-Host "Average: $($latency.AvgLatency)ms, Jitter: $($latency.Jitter)ms"

# Trace route with hostname resolution
Get-NetworkPath -Target "microsoft.com" -ResolveNames

# Check internet connectivity
$inet = Test-InternetConnectivity
if ($inet.HasInternet) {
    Write-Host "Connected - Public IP: $($inet.PublicIP)"
}
Report Output
The script generates detailed HTML reports including:

Internet connectivity status
Latency statistics and graphs
Network adapter information
DNS server performance
Port scan results
Traceroute visualization

🔍 Network-Discovery.ps1
Overview
A powerful network discovery tool for scanning IP ranges, identifying devices, detecting services, and mapping network infrastructure.

Features
✅ Fast parallel IP range scanning
✅ Service detection and fingerprinting
✅ MAC address vendor lookup
✅ Device type identification
✅ Active Directory computer discovery
✅ Specialized scans (printers, web servers)
✅ Network topology mapping
✅ CSV and HTML export
Quick Start
powershell
# Load the script
. .\Network-Discovery.ps1

# Quick scan of a subnet
Get-QuickScan -Subnet "192.168.1.0/24"

# Full network discovery
Start-NetworkDiscovery -IPRange "192.168.1.0/24"

# Discovery with vendor identification and AD integration
Start-NetworkDiscovery -IPRange "10.0.0.0/24" -ScanType Full -IncludeAD -IdentifyVendors
Available Functions
Main Functions
Function	Description
Start-NetworkDiscovery	Run comprehensive network discovery
Find-LiveHosts	Discover live hosts via ICMP ping
Find-NetworkDevices	Full device discovery with service detection
Specialized Discovery
Function	Description
Find-Printers	Discover network printers
Find-WebServers	Find web servers and get page titles
Find-ADComputers	Query AD for computer objects
Find-DomainControllers	Locate domain controllers
Service Detection
Function	Description
Get-HostServices	Scan host for open ports/services
Get-ServiceBanner	Grab service banners for fingerprinting
Identify-DeviceType	Determine device type from characteristics
Utility Functions
Function	Description
Get-LocalNetworkInfo	Get local network configuration
Get-SubnetInfo	Calculate subnet details from CIDR
Get-LocalMACAddresses	Get MAC addresses from ARP cache
Get-MACVendor	Lookup vendor from MAC address
Scan Types
Type	Description	Use Case
Quick	Ping + common ports (22,80,443,445,3389)	Fast overview
Standard	Ping + 20 common ports	Normal discovery
Full	Ping + 40+ ports + deep analysis	Complete audit
Examples
powershell
# Quick ping sweep
$hosts = Find-LiveHosts -IPRange "192.168.1.0/24"
Write-Host "Found $($hosts.Count) live hosts"

# Discover all devices with vendor lookup
$devices = Find-NetworkDevices -Subnet "192.168.1.0/24" -IdentifyVendors
$devices | Format-Table IPAddress, Hostname, DeviceType, Vendor

# Find all printers on the network
$printers = Find-Printers -Subnet "192.168.1.0/24"
$printers | Format-Table IPAddress, Hostname, Protocol

# Find web servers and get their titles
$webServers = Find-WebServers -Subnet "10.0.0.0/24" -GetTitles
$webServers | Format-Table IPAddress, URLs, Titles

# Get AD computers with online status
$adComputers = Find-ADComputers -OnlineOnly
$adComputers | Where-Object { $_.Online } | Format-Table Name, IPv4Address, OperatingSystem

# Create a simple network map
Get-NetworkMap -Subnet "192.168.1.0/24"

# Export device inventory to CSV
Export-DeviceInventory -Subnet "192.168.1.0/24" -OutputPath ".\inventory.csv"
IP Range Formats
The scripts support multiple IP range formats:

powershell
# CIDR notation
Start-NetworkDiscovery -IPRange "192.168.1.0/24"

# Last octet range
Start-NetworkDiscovery -IPRange "192.168.1.1-254"

# Full IP range
Start-NetworkDiscovery -IPRange "192.168.1.1-192.168.1.100"

# Single IP
Start-NetworkDiscovery -IPRange "192.168.1.1"

📋 VLAN-Documentation.ps1
Overview
A comprehensive VLAN documentation and analysis tool for maintaining accurate network segmentation records, ensuring compliance, and generating professional documentation.

Features
✅ Parse Cisco and HP switch configurations
✅ Import/export VLAN data from CSV
✅ VLAN compliance checking
✅ Subnet utilization analysis
✅ DHCP scope integration
✅ Unused VLAN identification
✅ Professional HTML documentation
✅ Subnet calculator functions
Quick Start
powershell
# Load the script
. .\VLAN-Documentation.ps1

# Import VLANs from switch configuration
$vlans = Import-CiscoVLANConfig -ConfigFile ".\switch-config.txt"

# Add VLANs to database
$vlans | Add-VLANToDatabase

# Run full audit
Start-VLANAudit -ConfigFile ".\switch.cfg" -ConfigType Cisco

# Generate documentation
New-VLANDocumentation -OutputPath ".\reports" -IncludeCompliance
Available Functions
Import/Export Functions
Function	Description
Import-CiscoVLANConfig	Parse Cisco IOS configuration
Import-HPVLANConfig	Parse HP/Aruba configuration
Import-VLANFromCSV	Import from CSV file
Export-VLANToCSV	Export database to CSV
VLAN Management
Function	Description
New-VLANEntry	Create a new VLAN entry
Add-VLANToDatabase	Add VLAN to the database
Get-VLANDatabase	Query VLAN database
Analysis Functions
Function	Description
Test-VLANCompliance	Check against compliance rules
Get-VLANUtilization	Analyze subnet usage
Find-UnusedVLANs	Identify potentially unused VLANs
Get-VLANSummary	Generate summary statistics
DHCP Integration
Function	Description
Get-DHCPScopeInfo	Query DHCP server for scopes
Update-VLANWithDHCP	Match VLANs with DHCP scopes
Documentation
Function	Description
New-VLANDocumentation	Generate HTML documentation
Start-VLANAudit	Run complete audit and generate reports
Examples
powershell
# Create VLAN entries manually
$vlan = New-VLANEntry -VLANID 10 `
                      -Name "Management" `
                      -Description "Network Management VLAN" `
                      -Subnet "10.0.10.0" `
                      -PrefixLength 24 `
                      -Gateway "10.0.10.1" `
                      -Status "Active" `
                      -Purpose "Infrastructure management"
                      
$vlan | Add-VLANToDatabase

# Import from Cisco config
$vlans = Import-CiscoVLANConfig -ConfigFile ".\configs\core-switch.cfg"
$vlans | ForEach-Object { Add-VLANToDatabase -VLANEntry $_ }

# Query the database
Get-VLANDatabase -Status Active | Format-Table VLANID, Name, CIDR, Gateway

# Run compliance check
$compliance = Test-VLANCompliance
$compliance | Where-Object { -not $_.Compliant } | Format-Table VLANID, Name, Issues

# Find unused VLANs
$unused = Find-UnusedVLANs
$unused | Format-Table VLANID, Name, Reasons, Recommendation

# Get summary statistics
$summary = Get-VLANSummary
Write-Host "Total VLANs: $($summary.TotalVLANs)"
Write-Host "Active: $($summary.ActiveVLANs)"
Write-Host "Total IP Space: $($summary.TotalIPSpace)"

# Generate full documentation
Start-VLANAudit -ConfigFile ".\switch.cfg" `
                -ConfigType Cisco `
                -DHCPServer "dhcp01.domain.com" `
                -ExportPath ".\reports" `
                -OrganizationName "Contoso Corp"
CSV Format
For importing VLANs via CSV, use the following columns:

csv
VLANID,Name,Description,Subnet,PrefixLength,Gateway,DHCPServer,DHCPScope,Status,Purpose,Owner,Location,Notes
10,Management,Network Management,10.0.10.0,24,10.0.10.1,dhcp01,10.0.10.0,Active,Infrastructure,Network Team,HQ,Core infrastructure
20,Servers,Server VLAN,10.0.20.0,24,10.0.20.1,dhcp01,10.0.20.0,Active,Server infrastructure,Server Team,DC1,Production servers
Compliance Rules
The script checks for:

Missing descriptions/purpose
VLANs without gateways
Naming convention compliance
Reserved VLAN ID usage
Overlapping subnets
Missing DHCP documentation

📊 Generated Reports
All scripts can generate professional HTML reports that include:

Network Diagnostics Report
Internet connectivity status
Latency statistics with min/max/avg/jitter
DNS server performance comparison
Port scan results
Network path visualization
Adapter health status
Network Discovery Report
Summary statistics (device counts by type)
Local network configuration
Complete device inventory
Service summary
AD computer listing (if enabled)
Domain controller status
VLAN Documentation
Summary statistics
Complete VLAN inventory with expandable details
Compliance report
Subnet quick reference
Print-friendly formatting

🚀 Common Use Cases
Troubleshooting Connectivity Issues
powershell
# Full diagnostic when a user can't reach a server
Start-NetworkDiagnostics -Target "fileserver.domain.com" -FullDiagnostics

# Check if specific ports are accessible
Test-PortConnectivity -Target "appserver" -Ports 80,443,8080,1433

# Verify DNS is working correctly
Test-DNSServers -IncludePublicDNS | Where-Object { -not $_.ResolutionSuccess }
Network Inventory
powershell
# Full network discovery for documentation
Start-NetworkDiscovery -IPRange "10.0.0.0/24" -ScanType Full -IncludeAD -IdentifyVendors

# Find all devices and export to CSV
$devices = Find-NetworkDevices -Subnet "192.168.1.0/24" -IdentifyVendors
$devices | Export-Csv ".\network-inventory.csv" -NoTypeInformation
VLAN Documentation
powershell
# Initial documentation from switch config
Start-VLANAudit -ConfigFile ".\configs\core-sw01.cfg" -ConfigType Cisco -ExportPath ".\docs"

# Update documentation with DHCP info
Update-VLANWithDHCP -DHCPServer "dhcp01.domain.com"
New-VLANDocumentation -IncludeCompliance -OutputPath ".\docs"
Pre-Migration Assessment
powershell
# Document current state before migration
$discovery = Start-NetworkDiscovery -IPRange "10.0.0.0/16" -ScanType Full -IncludeAD
Start-VLANAudit -ConfigFile ".\all-switches.cfg" -ExportPath ".\pre-migration"

⚙️ Configuration
Network-Diagnostics.ps1
powershell
# Modify default settings in the script's $script:Config section
$script:Config = @{
    LatencyWarningMS = 100        # Warning threshold for latency
    LatencyCriticalMS = 300       # Critical threshold for latency
    PacketLossWarningPercent = 5  # Warning threshold for packet loss
    DefaultReportPath = ".\reports\network"
}
Network-Discovery.ps1
powershell
$script:Config = @{
    DefaultTimeout = 100          # Ping timeout in ms
    MaxConcurrentScans = 50       # Parallel scan threads
    PortScanTimeout = 500         # Port scan timeout in ms
    DefaultReportPath = ".\reports\discovery"
}
VLAN-Documentation.ps1
powershell
$script:Config = @{
    DefaultReportPath = ".\reports\vlan"
    ComplianceRules = @{
        RequireDescription = $true
        RequireGateway = $true
        NamingConvention = "^VLAN_\d{2,4}_[A-Za-z]+"
    }
}

📋 Requirements
PowerShell: Version 5.1 or higher (PowerShell 7+ recommended)
Permissions: Administrator rights for some functions (adapter reset, SNMP queries)
Modules:
ActiveDirectory module (optional, for AD discovery)
DhcpServer module (optional, for DHCP integration)
Network Access: Appropriate firewall rules for scanning

⚠️ Important Notes
Network Scanning: Always obtain proper authorization before scanning networks you don't own
Performance: Large subnet scans can generate significant network traffic
Rate Limiting: MAC vendor lookups are rate-limited to avoid API throttling
Firewall: Scans may be affected by firewalls blocking ICMP or specific ports
Accuracy: Device identification is based on heuristics and may not always be accurate

🔗 Related Scripts
../active-directory/ - AD management scripts
../printer-management/ - Printer deployment and troubleshooting
../system-monitoring/ - System health monitoring

📝 Version History
Version	Date	Changes
2.0	2024-01-15	Added parallel scanning, HTML reports, VLAN documentation
1.5	2023-09-01	Added AD integration, MAC vendor lookup
1.0	2023-06-01	Initial release

🤝 Contributing
Contributions are welcome! Please:

Test all changes thoroughly
Update documentation
Follow existing code style
Add examples for new functions
