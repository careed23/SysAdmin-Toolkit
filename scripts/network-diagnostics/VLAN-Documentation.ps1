<#
.SYNOPSIS
    VLAN Documentation and Analysis Script
    
.DESCRIPTION
    Comprehensive VLAN documentation tool including:
    - VLAN inventory and documentation
    - Switch VLAN configuration parsing
    - IP subnet to VLAN mapping
    - VLAN utilization analysis
    - Cross-reference with network devices
    - Automated documentation generation
    - VLAN compliance checking
    - Network segmentation analysis
    
.PARAMETER SwitchIP
    IP address of switch to query

.PARAMETER ConfigFile
    Path to switch configuration file

.PARAMETER ExportPath
    Path to export documentation

.EXAMPLE
    Get-VLANDocumentation -ConfigFile ".\switch-config.txt"
    
.EXAMPLE
    Start-VLANAudit -Subnet "192.168.0.0/16"

.EXAMPLE
    New-VLANDocumentation -VLANDatabase $vlans -ExportPath "C:\Docs"

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Note: Some features require SNMP access to switches or configuration files
#>

#region Configuration

$script:Config = @{
    # Standard VLAN ranges
    VLANRanges = @{
        Reserved = @(0, 1, 4095)
        Standard = @{ Min = 2; Max = 1001 }
        Extended = @{ Min = 1006; Max = 4094 }
        Reserved_Range = @{ Min = 1002; Max = 1005 }
    }
    
    # Common VLAN naming conventions
    CommonVLANTypes = @{
        1 = "Default/Native"
        10 = "Management"
        20 = "Servers"
        30 = "Workstations"
        40 = "VoIP"
        50 = "Printers"
        60 = "Wireless"
        70 = "Guest"
        80 = "Security/Cameras"
        90 = "IoT"
        100 = "DMZ"
        999 = "Parking/Unused"
    }
    
    # SNMP settings
    SNMPCommunity = "public"
    SNMPTimeout = 5000
    
    # Report settings
    DefaultReportPath = ".\reports\vlan"
    
    # Compliance rules
    ComplianceRules = @{
        RequireDescription = $true
        MaxVLANsPerSwitch = 100
        RequireGateway = $true
        NamingConvention = "^VLAN_\d{2,4}_[A-Za-z]+"  # Example: VLAN_10_Management
    }
}

# VLAN Database (can be populated from various sources)
$script:VLANDatabase = @()

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

function Convert-SubnetToCIDR {
    param(
        [string]$IPAddress,
        [string]$SubnetMask
    )
    
    # Convert subnet mask to prefix length
    $binaryMask = ([System.Net.IPAddress]::Parse($SubnetMask)).GetAddressBytes() | 
        ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }
    $prefixLength = ($binaryMask -join '').TrimEnd('0').Length
    
    return "$IPAddress/$prefixLength"
}

function Get-NetworkAddress {
    param(
        [string]$IPAddress,
        [int]$PrefixLength
    )
    
    $ipBytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
    
    $maskInt = [uint32]::MaxValue -shl (32 - $PrefixLength)
    $networkInt = $ipInt -band $maskInt
    
    $networkBytes = [BitConverter]::GetBytes($networkInt)
    [Array]::Reverse($networkBytes)
    
    return ([System.Net.IPAddress]::new($networkBytes)).ToString()
}

function Get-BroadcastAddress {
    param(
        [string]$IPAddress,
        [int]$PrefixLength
    )
    
    $ipBytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
    
    $maskInt = [uint32]::MaxValue -shl (32 - $PrefixLength)
    $broadcastInt = $ipInt -bor (-bnot $maskInt)
    
    $broadcastBytes = [BitConverter]::GetBytes($broadcastInt)
    [Array]::Reverse($broadcastBytes)
    
    return ([System.Net.IPAddress]::new($broadcastBytes)).ToString()
}

function Get-UsableHostCount {
    param([int]$PrefixLength)
    
    if ($PrefixLength -ge 31) {
        return [math]::Pow(2, (32 - $PrefixLength))
    }
    return [math]::Pow(2, (32 - $PrefixLength)) - 2
}

#endregion

#region VLAN Data Structure

function New-VLANEntry {
    <#
    .SYNOPSIS
        Creates a new VLAN documentation entry
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$VLANID,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$Description,
        
        [string]$Subnet,
        
        [int]$PrefixLength,
        
        [string]$Gateway,
        
        [string]$DHCPServer,
        
        [string]$DHCPScope,
        
        [ValidateSet('Active', 'Inactive', 'Reserved', 'Deprecated')]
        [string]$Status = 'Active',
        
        [string]$Purpose,
        
        [string]$Owner,
        
        [string]$Location,
        
        [string[]]$AssociatedSwitches,
        
        [string]$Notes
    )
    
    $vlan = [PSCustomObject]@{
        VLANID = $VLANID
        Name = $Name
        Description = $Description
        Subnet = $Subnet
        PrefixLength = $PrefixLength
        CIDR = if ($Subnet -and $PrefixLength) { "$Subnet/$PrefixLength" } else { $null }
        Gateway = $Gateway
        NetworkAddress = if ($Subnet -and $PrefixLength) { Get-NetworkAddress -IPAddress $Subnet -PrefixLength $PrefixLength } else { $null }
        BroadcastAddress = if ($Subnet -and $PrefixLength) { Get-BroadcastAddress -IPAddress $Subnet -PrefixLength $PrefixLength } else { $null }
        UsableHosts = if ($PrefixLength) { Get-UsableHostCount -PrefixLength $PrefixLength } else { $null }
        DHCPServer = $DHCPServer
        DHCPScope = $DHCPScope
        Status = $Status
        Purpose = $Purpose
        Owner = $Owner
        Location = $Location
        AssociatedSwitches = $AssociatedSwitches
        Notes = $Notes
        CreatedDate = Get-Date
        LastModified = Get-Date
        DocumentedBy = $env:USERNAME
    }
    
    return $vlan
}

function Add-VLANToDatabase {
    <#
    .SYNOPSIS
        Adds a VLAN entry to the database
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$VLANEntry
    )
    
    process {
        # Check if VLAN already exists
        $existing = $script:VLANDatabase | Where-Object { $_.VLANID -eq $VLANEntry.VLANID }
        
        if ($existing) {
            Write-Log "VLAN $($VLANEntry.VLANID) already exists in database. Updating..." -Level Warning
            $script:VLANDatabase = $script:VLANDatabase | Where-Object { $_.VLANID -ne $VLANEntry.VLANID }
        }
        
        $script:VLANDatabase += $VLANEntry
        Write-Log "Added VLAN $($VLANEntry.VLANID) ($($VLANEntry.Name)) to database" -Level Success
    }
}

function Get-VLANDatabase {
    <#
    .SYNOPSIS
        Returns the current VLAN database
    #>
    [CmdletBinding()]
    param(
        [int]$VLANID,
        [string]$Name,
        [string]$Status
    )
    
    $results = $script:VLANDatabase
    
    if ($VLANID) {
        $results = $results | Where-Object { $_.VLANID -eq $VLANID }
    }
    
    if ($Name) {
        $results = $results | Where-Object { $_.Name -like "*$Name*" }
    }
    
    if ($Status) {
        $results = $results | Where-Object { $_.Status -eq $Status }
    }
    
    return $results | Sort-Object VLANID
}

#endregion

#region Configuration Parsing

function Import-CiscoVLANConfig {
    <#
    .SYNOPSIS
        Parses Cisco switch configuration to extract VLAN information
    
    .PARAMETER ConfigFile
        Path to switch configuration file
    
    .PARAMETER ConfigText
        Raw configuration text
    
    .EXAMPLE
        Import-CiscoVLANConfig -ConfigFile ".\switch-config.txt"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigFile,
        
        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [string]$ConfigText
    )
    
    if ($ConfigFile) {
        if (-not (Test-Path $ConfigFile)) {
            Write-Log "Configuration file not found: $ConfigFile" -Level Error
            return @()
        }
        $ConfigText = Get-Content -Path $ConfigFile -Raw
    }
    
    Write-Log "Parsing Cisco configuration..." -Level Info
    
    $vlans = @()
    $interfaces = @{}
    $currentVLAN = $null
    $currentInterface = $null
    
    $lines = $ConfigText -split "`n"
    
    foreach ($line in $lines) {
        $line = $line.Trim()
        
        # Parse VLAN definitions
        if ($line -match '^vlan\s+(\d+)$') {
            $currentVLAN = [PSCustomObject]@{
                VLANID = [int]$Matches[1]
                Name = $null
                State = 'Active'
            }
        }
        elseif ($currentVLAN -and $line -match '^\s*name\s+(.+)$') {
            $currentVLAN.Name = $Matches[1].Trim()
        }
        elseif ($currentVLAN -and $line -match '^\s*state\s+(active|suspend)') {
            $currentVLAN.State = $Matches[1]
        }
        elseif ($currentVLAN -and $line -match '^!|^vlan\s+\d+|^interface') {
            if ($currentVLAN.VLANID) {
                $vlans += $currentVLAN
            }
            $currentVLAN = $null
        }
        
        # Parse interface configurations for SVI (VLAN interfaces)
        if ($line -match '^interface\s+[Vv]lan\s*(\d+)') {
            $currentInterface = @{
                VLANID = [int]$Matches[1]
                IPAddress = $null
                SubnetMask = $null
                Description = $null
                Shutdown = $false
            }
        }
        elseif ($currentInterface) {
            if ($line -match '^\s*ip\s+address\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)') {
                $currentInterface.IPAddress = $Matches[1]
                $currentInterface.SubnetMask = $Matches[2]
            }
            elseif ($line -match '^\s*description\s+(.+)$') {
                $currentInterface.Description = $Matches[1].Trim()
            }
            elseif ($line -match '^\s*shutdown') {
                $currentInterface.Shutdown = $true
            }
            elseif ($line -match '^!|^interface') {
                if ($currentInterface.VLANID) {
                    $interfaces[$currentInterface.VLANID] = $currentInterface
                }
                $currentInterface = $null
            }
        }
        
        # Check for new interface start
        if ($line -match '^interface\s+[Vv]lan\s*(\d+)') {
            $currentInterface = @{
                VLANID = [int]$Matches[1]
                IPAddress = $null
                SubnetMask = $null
                Description = $null
                Shutdown = $false
            }
        }
    }
    
    # Process last entries
    if ($currentVLAN -and $currentVLAN.VLANID) {
        $vlans += $currentVLAN
    }
    if ($currentInterface -and $currentInterface.VLANID) {
        $interfaces[$currentInterface.VLANID] = $currentInterface
    }
    
    # Combine VLAN and interface information
    $results = foreach ($vlan in $vlans) {
        $interfaceInfo = $interfaces[$vlan.VLANID]
        
        $prefixLength = $null
        if ($interfaceInfo -and $interfaceInfo.SubnetMask) {
            $binaryMask = ([System.Net.IPAddress]::Parse($interfaceInfo.SubnetMask)).GetAddressBytes() | 
                ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }
            $prefixLength = ($binaryMask -join '').TrimEnd('0').Length
        }
        
        New-VLANEntry -VLANID $vlan.VLANID `
                      -Name $(if ($vlan.Name) { $vlan.Name } else { "VLAN$($vlan.VLANID)" }) `
                      -Description $(if ($interfaceInfo) { $interfaceInfo.Description } else { $null }) `
                      -Subnet $(if ($interfaceInfo) { $interfaceInfo.IPAddress } else { $null }) `
                      -PrefixLength $prefixLength `
                      -Gateway $(if ($interfaceInfo) { $interfaceInfo.IPAddress } else { $null }) `
                      -Status $(if ($vlan.State -eq 'Active' -and (-not $interfaceInfo -or -not $interfaceInfo.Shutdown)) { 'Active' } else { 'Inactive' })
    }
    
    Write-Log "Parsed $($results.Count) VLANs from configuration" -Level Success
    
    return $results
}

function Import-HPVLANConfig {
    <#
    .SYNOPSIS
        Parses HP/Aruba switch configuration for VLAN information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFile
    )
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Log "Configuration file not found: $ConfigFile" -Level Error
        return @()
    }
    
    Write-Log "Parsing HP/Aruba configuration..." -Level Info
    
    $content = Get-Content -Path $ConfigFile -Raw
    $vlans = @()
    
    # HP format: vlan 10
    #            name "Management"
    #            untagged 1-24
    #            tagged 25-26
    
    $vlanBlocks = [regex]::Matches($content, 'vlan\s+(\d+)\s*\n((?:(?!\nvlan\s+\d).)*)' , 'Singleline')
    
    foreach ($block in $vlanBlocks) {
        $vlanID = [int]$block.Groups[1].Value
        $config = $block.Groups[2].Value
        
        $name = if ($config -match 'name\s+"?([^"\n]+)"?') { $Matches[1].Trim() } else { "VLAN$vlanID" }
        $ipMatch = [regex]::Match($config, 'ip\s+address\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)')
        
        $subnet = $null
        $prefixLength = $null
        
        if ($ipMatch.Success) {
            $subnet = $ipMatch.Groups[1].Value
            $mask = $ipMatch.Groups[2].Value
            $binaryMask = ([System.Net.IPAddress]::Parse($mask)).GetAddressBytes() | 
                ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }
            $prefixLength = ($binaryMask -join '').TrimEnd('0').Length
        }
        
        $vlans += New-VLANEntry -VLANID $vlanID `
                                -Name $name `
                                -Subnet $subnet `
                                -PrefixLength $prefixLength `
                                -Gateway $subnet `
                                -Status 'Active'
    }
    
    Write-Log "Parsed $($vlans.Count) VLANs from HP configuration" -Level Success
    
    return $vlans
}

function Import-VLANFromCSV {
    <#
    .SYNOPSIS
        Imports VLAN data from CSV file
    
    .PARAMETER CSVPath
        Path to CSV file
    
    .EXAMPLE
        Import-VLANFromCSV -CSVPath ".\vlans.csv"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CSVPath
    )
    
    if (-not (Test-Path $CSVPath)) {
        Write-Log "CSV file not found: $CSVPath" -Level Error
        return @()
    }
    
    Write-Log "Importing VLANs from CSV..." -Level Info
    
    $csvData = Import-Csv -Path $CSVPath
    $vlans = @()
    
    foreach ($row in $csvData) {
        $vlan = New-VLANEntry -VLANID ([int]$row.VLANID) `
                              -Name $row.Name `
                              -Description $row.Description `
                              -Subnet $row.Subnet `
                              -PrefixLength $(if ($row.PrefixLength) { [int]$row.PrefixLength } else { $null }) `
                              -Gateway $row.Gateway `
                              -DHCPServer $row.DHCPServer `
                              -DHCPScope $row.DHCPScope `
                              -Status $(if ($row.Status) { $row.Status } else { 'Active' }) `
                              -Purpose $row.Purpose `
                              -Owner $row.Owner `
                              -Location $row.Location `
                              -Notes $row.Notes
        
        $vlans += $vlan
    }
    
    Write-Log "Imported $($vlans.Count) VLANs from CSV" -Level Success
    
    return $vlans
}

function Export-VLANToCSV {
    <#
    .SYNOPSIS
        Exports VLAN database to CSV
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [PSCustomObject[]]$VLANData
    )
    
    if (-not $VLANData) {
        $VLANData = $script:VLANDatabase
    }
    
    $VLANData | Select-Object VLANID, Name, Description, CIDR, Subnet, PrefixLength, Gateway,
        UsableHosts, DHCPServer, DHCPScope, Status, Purpose, Owner, Location, Notes,
        @{N='AssociatedSwitches';E={$_.AssociatedSwitches -join ';'}},
        CreatedDate, LastModified, DocumentedBy |
        Export-Csv -Path $OutputPath -NoTypeInformation
    
    Write-Log "Exported $($VLANData.Count) VLANs to: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region VLAN Analysis

function Test-VLANCompliance {
    <#
    .SYNOPSIS
        Checks VLAN configuration against compliance rules
    
    .PARAMETER VLANData
        VLAN entries to check
    
    .EXAMPLE
        Test-VLANCompliance -VLANData $vlans
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$VLANData
    )
    
    if (-not $VLANData) {
        $VLANData = $script:VLANDatabase
    }
    
    Write-Log "Running VLAN compliance check..." -Level Info
    
    $complianceResults = @()
    
    foreach ($vlan in $VLANData) {
        $issues = @()
        $warnings = @()
        
        # Check for description
        if ($script:Config.ComplianceRules.RequireDescription) {
            if (-not $vlan.Description -and -not $vlan.Purpose) {
                $issues += "Missing description/purpose"
            }
        }
        
        # Check for gateway (active VLANs)
        if ($script:Config.ComplianceRules.RequireGateway) {
            if ($vlan.Status -eq 'Active' -and -not $vlan.Gateway -and $vlan.Subnet) {
                $warnings += "No gateway configured for routed VLAN"
            }
        }
        
        # Check naming convention
        if ($script:Config.ComplianceRules.NamingConvention) {
            if ($vlan.Name -notmatch $script:Config.ComplianceRules.NamingConvention) {
                $warnings += "Name doesn't match naming convention"
            }
        }
        
        # Check for reserved VLANs
        if ($vlan.VLANID -in $script:Config.VLANRanges.Reserved) {
            $warnings += "Using reserved VLAN ID"
        }
        
        # Check for overlapping subnets
        $otherVLANs = $VLANData | Where-Object { $_.VLANID -ne $vlan.VLANID -and $_.Subnet }
        if ($vlan.Subnet) {
            foreach ($other in $otherVLANs) {
                if ($other.NetworkAddress -eq $vlan.NetworkAddress) {
                    $issues += "Subnet overlap with VLAN $($other.VLANID)"
                }
            }
        }
        
        # Check for subnet without DHCP (if expected)
        if ($vlan.Subnet -and -not $vlan.DHCPServer -and $vlan.Status -eq 'Active') {
            $warnings += "No DHCP server documented for active VLAN"
        }
        
        $complianceResults += [PSCustomObject]@{
            VLANID = $vlan.VLANID
            Name = $vlan.Name
            Status = $vlan.Status
            IssueCount = $issues.Count
            WarningCount = $warnings.Count
            Issues = $issues
            Warnings = $warnings
            Compliant = ($issues.Count -eq 0)
        }
    }
    
    # Summary
    $compliantCount = ($complianceResults | Where-Object { $_.Compliant }).Count
    $totalCount = $complianceResults.Count
    
    Write-Log "Compliance Check Complete: $compliantCount / $totalCount VLANs compliant" -Level $(if ($compliantCount -eq $totalCount) { 'Success' } else { 'Warning' })
    
    return $complianceResults
}

function Get-VLANUtilization {
    <#
    .SYNOPSIS
        Analyzes VLAN subnet utilization
    
    .PARAMETER VLANData
        VLAN entries to analyze
    
    .PARAMETER ScanForHosts
        Actually scan subnets for live hosts
    
    .EXAMPLE
        Get-VLANUtilization -VLANData $vlans -ScanForHosts
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$VLANData,
        
        [switch]$ScanForHosts
    )
    
    if (-not $VLANData) {
        $VLANData = $script:VLANDatabase
    }
    
    Write-Log "Analyzing VLAN utilization..." -Level Info
    
    $utilizationResults = @()
    
    foreach ($vlan in $VLANData | Where-Object { $_.Subnet -and $_.PrefixLength }) {
        $result = [PSCustomObject]@{
            VLANID = $vlan.VLANID
            Name = $vlan.Name
            CIDR = $vlan.CIDR
            UsableHosts = $vlan.UsableHosts
            DiscoveredHosts = 0
            UtilizationPercent = 0
            Status = $vlan.Status
            DHCPEnabled = [bool]$vlan.DHCPServer
        }
        
        if ($ScanForHosts -and $vlan.Status -eq 'Active') {
            Write-Log "  Scanning VLAN $($vlan.VLANID) ($($vlan.CIDR))..." -Level Debug
            
            try {
                # Quick ping sweep (limited to first 254 hosts for efficiency)
                $maxHosts = [math]::Min($vlan.UsableHosts, 254)
                $networkInt = [BitConverter]::ToUInt32(([System.Net.IPAddress]::Parse($vlan.NetworkAddress).GetAddressBytes() | ForEach-Object { $_ })[3..0], 0)
                
                $liveCount = 0
                $scannedCount = 0
                
                for ($i = 1; $i -le $maxHosts; $i++) {
                    $hostInt = $networkInt + $i
                    $hostBytes = [BitConverter]::GetBytes($hostInt)
                    [Array]::Reverse($hostBytes)
                    $hostIP = ([System.Net.IPAddress]::new($hostBytes)).ToString()
                    
                    if (Test-Connection -ComputerName $hostIP -Count 1 -Quiet -TimeoutSeconds 1) {
                        $liveCount++
                    }
                    
                    $scannedCount++
                    
                    # Progress for large subnets
                    if ($scannedCount % 50 -eq 0) {
                        Write-Progress -Activity "Scanning VLAN $($vlan.VLANID)" -Status "$scannedCount / $maxHosts" -PercentComplete (($scannedCount / $maxHosts) * 100)
                    }
                }
                
                Write-Progress -Activity "Scanning VLAN $($vlan.VLANID)" -Completed
                
                $result.DiscoveredHosts = $liveCount
                $result.UtilizationPercent = [math]::Round(($liveCount / $vlan.UsableHosts) * 100, 2)
            }
            catch {
                Write-Log "  Error scanning VLAN $($vlan.VLANID): $_" -Level Warning
            }
        }
        
        $utilizationResults += $result
    }
    
    return $utilizationResults
}

function Find-UnusedVLANs {
    <#
    .SYNOPSIS
        Identifies potentially unused VLANs
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$VLANData,
        
        [int]$InactiveDays = 90
    )
    
    if (-not $VLANData) {
        $VLANData = $script:VLANDatabase
    }
    
    $unused = @()
    
    foreach ($vlan in $VLANData) {
        $isUnused = $false
        $reason = @()
        
        # No subnet defined
        if (-not $vlan.Subnet) {
            $isUnused = $true
            $reason += "No subnet assigned"
        }
        
        # Status inactive or deprecated
        if ($vlan.Status -in @('Inactive', 'Deprecated')) {
            $isUnused = $true
            $reason += "Status: $($vlan.Status)"
        }
        
        # Parking VLAN
        if ($vlan.Name -match 'parking|unused|disabled') {
            $isUnused = $true
            $reason += "Naming indicates unused"
        }
        
        # Reserved VLAN range
        if ($vlan.VLANID -ge 1002 -and $vlan.VLANID -le 1005) {
            $isUnused = $true
            $reason += "Reserved VLAN range"
        }
        
        if ($isUnused) {
            $unused += [PSCustomObject]@{
                VLANID = $vlan.VLANID
                Name = $vlan.Name
                Status = $vlan.Status
                Subnet = $vlan.Subnet
                Reasons = $reason -join '; '
                Recommendation = "Review for decommissioning"
            }
        }
    }
    
    return $unused
}

function Get-VLANSummary {
    <#
    .SYNOPSIS
        Generates a summary of VLAN statistics
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$VLANData
    )
    
    if (-not $VLANData) {
        $VLANData = $script:VLANDatabase
    }
    
    $summary = [PSCustomObject]@{
        TotalVLANs = $VLANData.Count
        ActiveVLANs = ($VLANData | Where-Object { $_.Status -eq 'Active' }).Count
        InactiveVLANs = ($VLANData | Where-Object { $_.Status -eq 'Inactive' }).Count
        DeprecatedVLANs = ($VLANData | Where-Object { $_.Status -eq 'Deprecated' }).Count
        ReservedVLANs = ($VLANData | Where-Object { $_.Status -eq 'Reserved' }).Count
        
        WithSubnet = ($VLANData | Where-Object { $_.Subnet }).Count
        WithoutSubnet = ($VLANData | Where-Object { -not $_.Subnet }).Count
        
        WithDHCP = ($VLANData | Where-Object { $_.DHCPServer }).Count
        WithoutDHCP = ($VLANData | Where-Object { -not $_.DHCPServer -and $_.Subnet }).Count
        
        TotalIPSpace = ($VLANData | Where-Object { $_.UsableHosts } | Measure-Object -Property UsableHosts -Sum).Sum
        
        VLANsByStatus = $VLANData | Group-Object Status | Select-Object Name, Count
        VLANsByPurpose = $VLANData | Where-Object { $_.Purpose } | Group-Object Purpose | Select-Object Name, Count
        
        SmallestSubnet = ($VLANData | Where-Object { $_.PrefixLength } | Sort-Object PrefixLength -Descending | Select-Object -First 1)
        LargestSubnet = ($VLANData | Where-Object { $_.PrefixLength } | Sort-Object PrefixLength | Select-Object -First 1)
    }
    
    return $summary
}

#endregion

#region DHCP Integration

function Get-DHCPScopeInfo {
    <#
    .SYNOPSIS
        Gets DHCP scope information and maps to VLANs
    
    .PARAMETER DHCPServer
        DHCP server to query
    
    .EXAMPLE
        Get-DHCPScopeInfo -DHCPServer "dhcp01.domain.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DHCPServer
    )
    
    Write-Log "Querying DHCP server: $DHCPServer" -Level Info
    
    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $DHCPServer -ErrorAction Stop
        
        $scopeInfo = foreach ($scope in $scopes) {
            $stats = Get-DhcpServerv4ScopeStatistics -ComputerName $DHCPServer -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            
            [PSCustomObject]@{
                ScopeID = $scope.ScopeId
                Name = $scope.Name
                Description = $scope.Description
                StartRange = $scope.StartRange
                EndRange = $scope.EndRange
                SubnetMask = $scope.SubnetMask
                State = $scope.State
                LeaseDuration = $scope.LeaseDuration
                AddressesFree = $stats.AddressesFree
                AddressesInUse = $stats.AddressesInUse
                PercentInUse = $stats.PercentageInUse
                ReservedAddresses = $stats.ReservedAddress
            }
        }
        
        return $scopeInfo
    }
    catch {
        Write-Log "Failed to query DHCP server: $_" -Level Error
        return @()
    }
}

function Update-VLANWithDHCP {
    <#
    .SYNOPSIS
        Updates VLAN entries with DHCP scope information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DHCPServer
    )
    
    $scopes = Get-DHCPScopeInfo -DHCPServer $DHCPServer
    
    if (-not $scopes) {
        return
    }
    
    foreach ($vlan in $script:VLANDatabase | Where-Object { $_.NetworkAddress }) {
        $matchingScope = $scopes | Where-Object { 
            $_.ScopeID.ToString() -eq $vlan.NetworkAddress 
        }
        
        if ($matchingScope) {
            $vlan.DHCPServer = $DHCPServer
            $vlan.DHCPScope = $matchingScope.ScopeID
            Write-Log "Matched VLAN $($vlan.VLANID) with DHCP scope $($matchingScope.ScopeID)" -Level Success
        }
    }
}

#endregion

#region Report Generation

function New-VLANDocumentation {
    <#
    .SYNOPSIS
        Generates comprehensive VLAN documentation in HTML format
    
    .PARAMETER VLANData
        VLAN entries to document
    
    .PARAMETER OutputPath
        Path for HTML report
    
    .PARAMETER IncludeCompliance
        Include compliance check results
    
    .PARAMETER IncludeUtilization
        Include utilization analysis
    
    .EXAMPLE
        New-VLANDocumentation -VLANData $vlans -OutputPath ".\reports"
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$VLANData,
        
        [string]$OutputPath = $script:Config.DefaultReportPath,
        
        [switch]$IncludeCompliance,
        
        [switch]$IncludeUtilization,
        
        [string]$OrganizationName = "Organization"
    )
    
    if (-not $VLANData) {
        $VLANData = $script:VLANDatabase
    }
    
    if (-not $VLANData) {
        Write-Log "No VLAN data to document" -Level Error
        return
    }
    
    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Generating VLAN documentation..." -Level Info
    
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $summary = Get-VLANSummary -VLANData $VLANData
    
    $complianceResults = $null
    if ($IncludeCompliance) {
        $complianceResults = Test-VLANCompliance -VLANData $VLANData
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>VLAN Documentation - $OrganizationName</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background: #f0f2f5; }
        .container { max-width: 1400px; margin: 0 auto; }
        
        .header { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; 
            padding: 40px; 
            border-radius: 12px; 
            margin-bottom: 25px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 { margin: 0; font-size: 32px; font-weight: 600; }
        .header .subtitle { opacity: 0.9; margin-top: 8px; font-size: 16px; }
        
        .stats-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-bottom: 25px; 
        }
        .stat-card { 
            background: white; 
            padding: 25px; 
            border-radius: 12px; 
            text-align: center;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .stat-card:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
        .stat-value { font-size: 36px; font-weight: 700; color: #667eea; }
        .stat-label { color: #64748b; margin-top: 8px; font-size: 14px; }
        
        .section { 
            background: white; 
            border-radius: 12px; 
            padding: 25px; 
            margin-bottom: 25px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }
        .section h2 { 
            color: #1e293b; 
            border-bottom: 3px solid #667eea; 
            padding-bottom: 12px; 
            margin-top: 0;
            font-size: 20px;
        }
        
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th { 
            background: #f8fafc; 
            padding: 14px 12px; 
            text-align: left; 
            font-weight: 600; 
            color: #475569;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        td { 
            padding: 14px 12px; 
            border-bottom: 1px solid #e2e8f0;
            font-size: 14px;
        }
        tr:hover { background: #f8fafc; }
        
        .badge { 
            display: inline-block; 
            padding: 4px 12px; 
            border-radius: 20px; 
            font-size: 12px; 
            font-weight: 600;
        }
        .badge-active { background: #dcfce7; color: #166534; }
        .badge-inactive { background: #fef3c7; color: #92400e; }
        .badge-deprecated { background: #fee2e2; color: #991b1b; }
        .badge-reserved { background: #e0e7ff; color: #3730a3; }
        
        .vlan-id { 
            font-weight: 700; 
            color: #667eea;
            font-size: 16px;
        }
        .subnet { 
            font-family: 'Consolas', monospace; 
            background: #f1f5f9; 
            padding: 4px 8px; 
            border-radius: 4px;
            font-size: 13px;
        }
        
        .compliance-pass { color: #16a34a; }
        .compliance-fail { color: #dc2626; }
        
        .toc { 
            background: #f8fafc; 
            padding: 20px; 
            border-radius: 8px; 
            margin-bottom: 25px;
        }
        .toc h3 { margin-top: 0; color: #475569; }
        .toc ul { margin: 0; padding-left: 20px; }
        .toc li { margin: 8px 0; }
        .toc a { color: #667eea; text-decoration: none; }
        .toc a:hover { text-decoration: underline; }
        
        .detail-row { background: #fafafa; }
        .detail-cell { padding: 20px !important; }
        .detail-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
        .detail-item { }
        .detail-label { font-size: 12px; color: #64748b; margin-bottom: 4px; }
        .detail-value { font-weight: 500; color: #1e293b; }
        
        .print-only { display: none; }
        @media print {
            body { background: white; }
            .section { box-shadow: none; border: 1px solid #ddd; page-break-inside: avoid; }
            .print-only { display: block; }
            .no-print { display: none; }
        }
        
        .footer { 
            text-align: center; 
            color: #64748b; 
            margin-top: 40px; 
            padding: 20px;
            font-size: 13px;
        }
    </style>
    <script>
        function toggleDetails(id) {
            var row = document.getElementById(id);
            row.style.display = row.style.display === 'none' ? 'table-row' : 'none';
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📋 VLAN Documentation</h1>
            <div class="subtitle">$OrganizationName | Generated: $reportDate</div>
        </div>
        
        <div class="toc no-print">
            <h3>📑 Table of Contents</h3>
            <ul>
                <li><a href="#summary">Summary Statistics</a></li>
                <li><a href="#inventory">VLAN Inventory</a></li>
                $(if ($IncludeCompliance) { '<li><a href="#compliance">Compliance Report</a></li>' })
                <li><a href="#subnets">Subnet Reference</a></li>
            </ul>
        </div>

        <div class="stats-grid" id="summary">
            <div class="stat-card">
                <div class="stat-value">$($summary.TotalVLANs)</div>
                <div class="stat-label">Total VLANs</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($summary.ActiveVLANs)</div>
                <div class="stat-label">Active VLANs</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($summary.WithSubnet)</div>
                <div class="stat-label">With Subnets</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($summary.WithDHCP)</div>
                <div class="stat-label">DHCP Enabled</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$('{0:N0}' -f $summary.TotalIPSpace)</div>
                <div class="stat-label">Total IP Space</div>
            </div>
        </div>

        <div class="section" id="inventory">
            <h2>🏷️ VLAN Inventory</h2>
            <table>
                <thead>
                    <tr>
                        <th>VLAN ID</th>
                        <th>Name</th>
                        <th>Subnet / CIDR</th>
                        <th>Gateway</th>
                        <th>Usable IPs</th>
                        <th>Status</th>
                        <th>Purpose</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($vlan in $VLANData | Sort-Object VLANID) {
        $statusClass = switch ($vlan.Status) {
            'Active' { 'badge-active' }
            'Inactive' { 'badge-inactive' }
            'Deprecated' { 'badge-deprecated' }
            'Reserved' { 'badge-reserved' }
            default { 'badge-inactive' }
        }
        
        $subnet = if ($vlan.CIDR) { "<span class='subnet'>$($vlan.CIDR)</span>" } else { "-" }
        $gateway = if ($vlan.Gateway) { $vlan.Gateway } else { "-" }
        $usable = if ($vlan.UsableHosts) { "{0:N0}" -f $vlan.UsableHosts } else { "-" }
        $purpose = if ($vlan.Purpose) { $vlan.Purpose } else { $vlan.Description }
        
        $html += @"
                    <tr onclick="toggleDetails('details-$($vlan.VLANID)')" style="cursor: pointer;">
                        <td><span class="vlan-id">$($vlan.VLANID)</span></td>
                        <td><strong>$($vlan.Name)</strong></td>
                        <td>$subnet</td>
                        <td>$gateway</td>
                        <td>$usable</td>
                        <td><span class="badge $statusClass">$($vlan.Status)</span></td>
                        <td>$purpose</td>
                    </tr>
                    <tr id="details-$($vlan.VLANID)" class="detail-row" style="display: none;">
                        <td colspan="7" class="detail-cell">
                            <div class="detail-grid">
                                <div class="detail-item">
                                    <div class="detail-label">Network Address</div>
                                    <div class="detail-value">$(if ($vlan.NetworkAddress) { $vlan.NetworkAddress } else { '-' })</div>
                                </div>
                                <div class="detail-item">
                                    <div class="detail-label">Broadcast Address</div>
                                    <div class="detail-value">$(if ($vlan.BroadcastAddress) { $vlan.BroadcastAddress } else { '-' })</div>
                                </div>
                                <div class="detail-item">
                                    <div class="detail-label">DHCP Server</div>
                                    <div class="detail-value">$(if ($vlan.DHCPServer) { $vlan.DHCPServer } else { '-' })</div>
                                </div>
                                <div class="detail-item">
                                    <div class="detail-label">Owner</div>
                                    <div class="detail-value">$(if ($vlan.Owner) { $vlan.Owner } else { '-' })</div>
                                </div>
                                <div class="detail-item">
                                    <div class="detail-label">Location</div>
                                    <div class="detail-value">$(if ($vlan.Location) { $vlan.Location } else { '-' })</div>
                                </div>
                                <div class="detail-item">
                                    <div class="detail-label">Last Modified</div>
                                    <div class="detail-value">$(if ($vlan.LastModified) { $vlan.LastModified.ToString('yyyy-MM-dd') } else { '-' })</div>
                                </div>
                            </div>
                            $(if ($vlan.Notes) { "<div style='margin-top: 15px;'><div class='detail-label'>Notes</div><div class='detail-value'>$($vlan.Notes)</div></div>" })
                        </td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>
"@

    # Compliance Section
    if ($IncludeCompliance -and $complianceResults) {
        $compliantCount = ($complianceResults | Where-Object { $_.Compliant }).Count
        $totalCount = $complianceResults.Count
        $compliancePercent = [math]::Round(($compliantCount / $totalCount) * 100)
        
        $html += @"
        <div class="section" id="compliance">
            <h2>✅ Compliance Report</h2>
            <p style="font-size: 18px; margin-bottom: 20px;">
                Overall Compliance: <strong>$compliantCount / $totalCount</strong> VLANs 
                (<span class="$(if ($compliancePercent -ge 80) { 'compliance-pass' } else { 'compliance-fail' })">$compliancePercent%</span>)
            </p>
            <table>
                <thead>
                    <tr>
                        <th>VLAN ID</th>
                        <th>Name</th>
                        <th>Status</th>
                        <th>Issues</th>
                        <th>Warnings</th>
                        <th>Compliant</th>
                    </tr>
                </thead>
                <tbody>
"@
        
        foreach ($result in $complianceResults | Sort-Object Compliant, VLANID) {
            $complianceIcon = if ($result.Compliant) { "✓" } else { "✗" }
            $complianceClass = if ($result.Compliant) { "compliance-pass" } else { "compliance-fail" }
            
            $issuesText = if ($result.Issues) { $result.Issues -join "<br>" } else { "-" }
            $warningsText = if ($result.Warnings) { $result.Warnings -join "<br>" } else { "-" }
            
            $html += @"
                    <tr>
                        <td><span class="vlan-id">$($result.VLANID)</span></td>
                        <td>$($result.Name)</td>
                        <td>$($result.Status)</td>
                        <td style="color: #dc2626;">$issuesText</td>
                        <td style="color: #d97706;">$warningsText</td>
                        <td class="$complianceClass" style="font-size: 18px;">$complianceIcon</td>
                    </tr>
"@
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
"@
    }

    # Subnet Reference Section
    $html += @"
        <div class="section" id="subnets">
            <h2>🌐 Subnet Quick Reference</h2>
            <table>
                <thead>
                    <tr>
                        <th>VLAN</th>
                        <th>Network</th>
                        <th>First IP</th>
                        <th>Last IP</th>
                        <th>Broadcast</th>
                        <th>Mask</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($vlan in $VLANData | Where-Object { $_.Subnet } | Sort-Object VLANID) {
        $firstIP = $vlan.NetworkAddress -replace '\.\d+$', '.' + (([int]($vlan.NetworkAddress -split '\.')[-1]) + 1)
        $lastIP = $vlan.BroadcastAddress -replace '\.\d+$', '.' + (([int]($vlan.BroadcastAddress -split '\.')[-1]) - 1)
        $mask = "/$($vlan.PrefixLength)"
        
        $html += @"
                    <tr>
                        <td><span class="vlan-id">$($vlan.VLANID)</span> - $($vlan.Name)</td>
                        <td><span class="subnet">$($vlan.NetworkAddress)</span></td>
                        <td>$firstIP</td>
                        <td>$lastIP</td>
                        <td>$($vlan.BroadcastAddress)</td>
                        <td>$mask</td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>

        <div class="footer">
            <p>Generated by SysAdmin Toolkit VLAN Documentation | $reportDate</p>
            <p>Document Version: 1.0 | Classification: Internal Use</p>
        </div>
    </div>
</body>
</html>
"@

    # Save report
    $reportFileName = "VLAN_Documentation_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportPath = Join-Path $OutputPath $reportFileName
    
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    
    Write-Log "Documentation saved to: $reportPath" -Level Success
    
    return $reportPath
}

#endregion

#region Main Functions

function Start-VLANAudit {
    <#
    .SYNOPSIS
        Performs a comprehensive VLAN audit
    
    .DESCRIPTION
        Audits VLAN configuration including compliance, utilization, and documentation
    
    .PARAMETER ConfigFile
        Switch configuration file to parse
    
    .PARAMETER ConfigType
        Type of configuration (Cisco, HP, Generic)
    
    .PARAMETER DHCPServer
        DHCP server to query for scope information
    
    .PARAMETER ScanSubnets
        Scan subnets for utilization
    
    .PARAMETER ExportPath
        Path for reports
    
    .EXAMPLE
        Start-VLANAudit -ConfigFile ".\switch.cfg" -ConfigType Cisco
    
    .EXAMPLE
        Start-VLANAudit -ConfigFile ".\config.txt" -DHCPServer "dhcp01" -ScanSubnets
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        
        [ValidateSet('Cisco', 'HP', 'Generic', 'CSV')]
        [string]$ConfigType = 'Cisco',
        
        [string]$DHCPServer,
        
        [switch]$ScanSubnets,
        
        [string]$ExportPath = $script:Config.DefaultReportPath,
        
        [string]$OrganizationName = "Network"
    )
    
    $startTime = Get-Date
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║              VLAN Documentation & Audit Tool                   ║" -ForegroundColor Magenta
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    
    # Create export directory
    if (-not (Test-Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }
    
    # Import VLAN data
    if ($ConfigFile) {
        Write-Log "Importing VLAN configuration..." -Level Info
        
        $vlans = switch ($ConfigType) {
            'Cisco' { Import-CiscoVLANConfig -ConfigFile $ConfigFile }
            'HP' { Import-HPVLANConfig -ConfigFile $ConfigFile }
            'CSV' { Import-VLANFromCSV -CSVPath $ConfigFile }
            default { 
                Write-Log "Unsupported configuration type" -Level Error
                return
            }
        }
        
        if ($vlans) {
            foreach ($vlan in $vlans) {
                Add-VLANToDatabase -VLANEntry $vlan
            }
        }
    }
    
    if (-not $script:VLANDatabase) {
        Write-Log "No VLAN data available. Please import a configuration or CSV file." -Level Error
        return
    }
    
    # Query DHCP if specified
    if ($DHCPServer) {
        Write-Host ""
        Write-Log "Querying DHCP server..." -Level Info
        Update-VLANWithDHCP -DHCPServer $DHCPServer
    }
    
    # Get summary
    Write-Host ""
    Write-Log "Generating summary..." -Level Info
    $summary = Get-VLANSummary
    
    # Compliance check
    Write-Host ""
    Write-Log "Running compliance check..." -Level Info
    $compliance = Test-VLANCompliance
    
    # Utilization (if requested)
    $utilization = $null
    if ($ScanSubnets) {
        Write-Host ""
        Write-Log "Scanning subnet utilization..." -Level Info
        $utilization = Get-VLANUtilization -ScanForHosts
    }
    
    # Find unused VLANs
    Write-Host ""
    Write-Log "Identifying unused VLANs..." -Level Info
    $unused = Find-UnusedVLANs
    
    # Generate documentation
    Write-Host ""
    Write-Log "Generating documentation..." -Level Info
    $reportPath = New-VLANDocumentation -VLANData $script:VLANDatabase `
                                        -OutputPath $ExportPath `
                                        -IncludeCompliance `
                                        -OrganizationName $OrganizationName
    
    # Export to CSV as well
    $csvPath = Join-Path $ExportPath "VLAN_Export_$(Get-Date -Format 'yyyyMMdd').csv"
    Export-VLANToCSV -OutputPath $csvPath
    
    # Summary output
    $endTime = Get-Date
    $duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║                      Audit Summary                             ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Total VLANs:           $($summary.TotalVLANs)" -ForegroundColor White
    Write-Host "  Active VLANs:          $($summary.ActiveVLANs)" -ForegroundColor Green
    Write-Host "  Inactive/Deprecated:   $($summary.InactiveVLANs + $summary.DeprecatedVLANs)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  With Subnets:          $($summary.WithSubnet)" -ForegroundColor Cyan
    Write-Host "  With DHCP:             $($summary.WithDHCP)" -ForegroundColor Cyan
    Write-Host "  Total IP Space:        $('{0:N0}' -f $summary.TotalIPSpace) addresses" -ForegroundColor Cyan
    Write-Host ""
    
    $compliantCount = ($compliance | Where-Object { $_.Compliant }).Count
    $complianceColor = if ($compliantCount -eq $compliance.Count) { 'Green' } else { 'Yellow' }
    Write-Host "  Compliance:            $compliantCount / $($compliance.Count) compliant" -ForegroundColor $complianceColor
    Write-Host "  Unused VLANs:          $($unused.Count)" -ForegroundColor $(if ($unused.Count -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host ""
    Write-Host "  HTML Report:           $reportPath" -ForegroundColor Gray
    Write-Host "  CSV Export:            $csvPath" -ForegroundColor Gray
    Write-Host "  Duration:              $duration seconds" -ForegroundColor Gray
    Write-Host ""
    
    # Open report
    $openReport = Read-Host "Open documentation in browser? (Y/N)"
    if ($openReport -eq 'Y') {
        Start-Process $reportPath
    }
    
    return @{
        Summary = $summary
        Compliance = $compliance
        Utilization = $utilization
        
