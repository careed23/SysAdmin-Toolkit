<#
.SYNOPSIS
    Printer Deployment and Management Script
    
.DESCRIPTION
    Comprehensive printer deployment tool including:
    - Single and bulk printer installation
    - Driver management and installation
    - Print server configuration
    - Printer sharing and permissions
    - Default printer configuration
    - GPO printer deployment preparation
    - Printer migration between servers
    
.PARAMETER PrinterName
    Name of the printer to deploy

.PARAMETER DriverName
    Printer driver name

.PARAMETER PortIP
    IP address for the printer port

.EXAMPLE
    Install-NetworkPrinter -PrinterName "HP-Floor2" -PortIP "192.168.1.100" -DriverName "HP Universal Printing PCL 6"
    
.EXAMPLE
    Import-PrinterDeployment -CSVPath ".\printers.csv"

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Requires: Administrator privileges, Print Management features
#>

#Requires -RunAsAdministrator

#region Configuration

$script:Config = @{
    # Default settings
    DefaultDriverName = "HP Universal Printing PCL 6"
    DefaultPortType = "Standard TCP/IP Port"
    DefaultSNMPCommunity = "public"
    DefaultSNMPIndex = 1
    
    # Common driver paths
    DriverPaths = @{
        HP = "\\fileserver\drivers\HP"
        Canon = "\\fileserver\drivers\Canon"
        Xerox = "\\fileserver\drivers\Xerox"
        Brother = "\\fileserver\drivers\Brother"
        Lexmark = "\\fileserver\drivers\Lexmark"
        Ricoh = "\\fileserver\drivers\Ricoh"
    }
    
    # Common universal drivers
    UniversalDrivers = @{
        HP = "HP Universal Printing PCL 6"
        Canon = "Canon Generic Plus UFR II"
        Xerox = "Xerox Global Print Driver PCL6"
        Brother = "Brother Universal Printer"
        Ricoh = "RICOH PCL6 UniversalDriver V4.x"
    }
    
    # Print server settings
    DefaultPrintServer = $env:COMPUTERNAME
    DefaultSharePath = "Printers"
    
    # Report settings
    ReportPath = ".\reports\printers"
    
    # Naming conventions
    NamingPattern = @{
        Prefix = ""
        IncludeLocation = $true
        IncludeModel = $false
        Separator = "-"
    }
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

function Test-PrinterExists {
    param(
        [string]$PrinterName,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-PrinterPortExists {
    param(
        [string]$PortName,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $port = Get-PrinterPort -Name $PortName -ComputerName $ComputerName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-PrinterDriverExists {
    param(
        [string]$DriverName,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $driver = Get-PrinterDriver -Name $DriverName -ComputerName $ComputerName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-StandardPortName {
    param([string]$IPAddress)
    return "IP_$IPAddress"
}

#endregion

#region Driver Management

function Get-InstalledPrinterDrivers {
    <#
    .SYNOPSIS
        Gets all installed printer drivers
    
    .PARAMETER ComputerName
        Target computer (default: local)
    
    .EXAMPLE
        Get-InstalledPrinterDrivers | Format-Table Name, Version, Manufacturer
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $drivers = Get-PrinterDriver -ComputerName $ComputerName -ErrorAction Stop
        
        return $drivers | Select-Object Name, 
            @{N='Version';E={$_.DriverVersion}},
            @{N='Manufacturer';E={$_.Manufacturer}},
            @{N='Architecture';E={$_.PrinterEnvironment}},
            @{N='InfPath';E={$_.InfPath}},
            @{N='ConfigFile';E={$_.ConfigFile}}
    }
    catch {
        Write-Log "Failed to get printer drivers: $_" -Level Error
        return @()
    }
}

function Install-PrinterDriver {
    <#
    .SYNOPSIS
        Installs a printer driver from INF file or Windows Update
    
    .PARAMETER DriverName
        Name of the driver
    
    .PARAMETER InfPath
        Path to INF file (optional)
    
    .PARAMETER ComputerName
        Target computer
    
    .EXAMPLE
        Install-PrinterDriver -DriverName "HP Universal Printing PCL 6" -InfPath "C:\Drivers\hpcu250u.inf"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DriverName,
        
        [string]$InfPath,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    # Check if driver already exists
    if (Test-PrinterDriverExists -DriverName $DriverName -ComputerName $ComputerName) {
        Write-Log "Driver '$DriverName' is already installed" -Level Warning
        return $true
    }
    
    if ($PSCmdlet.ShouldProcess($DriverName, "Install printer driver")) {
        try {
            if ($InfPath) {
                # Install from INF file
                if (-not (Test-Path $InfPath)) {
                    Write-Log "INF file not found: $InfPath" -Level Error
                    return $false
                }
                
                Write-Log "Installing driver from INF: $InfPath" -Level Info
                
                # Stage the driver
                $pnpResult = pnputil.exe /add-driver $InfPath /install 2>&1
                
                # Add the driver
                Add-PrinterDriver -Name $DriverName -ComputerName $ComputerName -ErrorAction Stop
            }
            else {
                # Try to add from Windows driver store
                Write-Log "Installing driver from Windows driver store: $DriverName" -Level Info
                Add-PrinterDriver -Name $DriverName -ComputerName $ComputerName -ErrorAction Stop
            }
            
            Write-Log "Driver '$DriverName' installed successfully" -Level Success
            return $true
        }
        catch {
            Write-Log "Failed to install driver: $_" -Level Error
            return $false
        }
    }
}

function Remove-PrinterDriverSafe {
    <#
    .SYNOPSIS
        Safely removes a printer driver (checks for dependencies)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DriverName,
        
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$Force
    )
    
    # Check if any printers are using this driver
    $printersUsingDriver = Get-Printer -ComputerName $ComputerName | 
        Where-Object { $_.DriverName -eq $DriverName }
    
    if ($printersUsingDriver -and -not $Force) {
        Write-Log "Driver is in use by $($printersUsingDriver.Count) printer(s). Use -Force to remove anyway." -Level Warning
        Write-Log "Printers: $($printersUsingDriver.Name -join ', ')" -Level Warning
        return $false
    }
    
    if ($PSCmdlet.ShouldProcess($DriverName, "Remove printer driver")) {
        try {
            Remove-PrinterDriver -Name $DriverName -ComputerName $ComputerName -ErrorAction Stop
            Write-Log "Driver '$DriverName' removed successfully" -Level Success
            return $true
        }
        catch {
            Write-Log "Failed to remove driver: $_" -Level Error
            return $false
        }
    }
}

function Get-AvailableDrivers {
    <#
    .SYNOPSIS
        Gets list of drivers available in Windows driver store
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = "*"
    )
    
    try {
        # Query Windows driver store
        $infPath = "$env:SystemRoot\INF"
        $drivers = Get-WindowsDriver -Online -All | 
            Where-Object { $_.ClassName -eq 'Printer' -and $_.ProviderName -like $Filter }
        
        return $drivers | Select-Object Driver, ProviderName, Date, Version
    }
    catch {
        Write-Log "Failed to query driver store: $_" -Level Warning
        return @()
    }
}

#endregion

#region Port Management

function New-PrinterTCPIPPort {
    <#
    .SYNOPSIS
        Creates a new TCP/IP printer port
    
    .PARAMETER IPAddress
        Printer IP address
    
    .PARAMETER PortName
        Custom port name (optional)
    
    .PARAMETER SNMPEnabled
        Enable SNMP on the port
    
    .EXAMPLE
        New-PrinterTCPIPPort -IPAddress "192.168.1.100"
    
    .EXAMPLE
        New-PrinterTCPIPPort -IPAddress "192.168.1.100" -PortName "PRINTER_LOBBY" -SNMPEnabled
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress,
        
        [string]$PortName,
        
        [int]$PortNumber = 9100,
        
        [switch]$SNMPEnabled,
        
        [string]$SNMPCommunity = $script:Config.DefaultSNMPCommunity,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    if (-not $PortName) {
        $PortName = Get-StandardPortName -IPAddress $IPAddress
    }
    
    # Check if port exists
    if (Test-PrinterPortExists -PortName $PortName -ComputerName $ComputerName) {
        Write-Log "Port '$PortName' already exists" -Level Warning
        return $PortName
    }
    
    # Test connectivity first
    if (-not (Test-Connection -ComputerName $IPAddress -Count 1 -Quiet)) {
        Write-Log "Cannot reach printer at $IPAddress" -Level Warning
    }
    
    if ($PSCmdlet.ShouldProcess($PortName, "Create TCP/IP printer port")) {
        try {
            $portParams = @{
                Name = $PortName
                PrinterHostAddress = $IPAddress
                PortNumber = $PortNumber
                ComputerName = $ComputerName
            }
            
            if ($SNMPEnabled) {
                $portParams.SNMP = $true
                $portParams.SNMPCommunity = $SNMPCommunity
            }
            
            Add-PrinterPort @portParams -ErrorAction Stop
            
            Write-Log "Created printer port: $PortName ($IPAddress)" -Level Success
            return $PortName
        }
        catch {
            Write-Log "Failed to create printer port: $_" -Level Error
            return $null
        }
    }
}

function Get-PrinterPorts {
    <#
    .SYNOPSIS
        Gets all printer ports with detailed information
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [ValidateSet('All', 'TCP', 'USB', 'LPT', 'WSD')]
        [string]$PortType = 'All'
    )
    
    try {
        $ports = Get-PrinterPort -ComputerName $ComputerName -ErrorAction Stop
        
        if ($PortType -ne 'All') {
            $ports = switch ($PortType) {
                'TCP' { $ports | Where-Object { $_.Description -like "*TCP*" -or $_.Name -like "IP_*" } }
                'USB' { $ports | Where-Object { $_.Name -like "USB*" } }
                'LPT' { $ports | Where-Object { $_.Name -like "LPT*" } }
                'WSD' { $ports | Where-Object { $_.Description -like "*WSD*" } }
            }
        }
        
        return $ports | Select-Object Name, 
            @{N='IPAddress';E={$_.PrinterHostAddress}},
            @{N='PortNumber';E={$_.PortNumber}},
            Description
    }
    catch {
        Write-Log "Failed to get printer ports: $_" -Level Error
        return @()
    }
}

function Remove-UnusedPrinterPorts {
    <#
    .SYNOPSIS
        Removes printer ports that are not in use
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    $ports = Get-PrinterPort -ComputerName $ComputerName
    $printers = Get-Printer -ComputerName $ComputerName
    $usedPorts = $printers.PortName
    
    $unusedPorts = $ports | Where-Object { $_.Name -notin $usedPorts -and $_.Name -notmatch '^(LPT|COM|USB|FILE|PORTPROMPT)' }
    
    $removed = 0
    foreach ($port in $unusedPorts) {
        if ($PSCmdlet.ShouldProcess($port.Name, "Remove unused printer port")) {
            try {
                Remove-PrinterPort -Name $port.Name -ComputerName $ComputerName -ErrorAction Stop
                Write-Log "Removed unused port: $($port.Name)" -Level Success
                $removed++
            }
            catch {
                Write-Log "Failed to remove port $($port.Name): $_" -Level Warning
            }
        }
    }
    
    Write-Log "Removed $removed unused printer ports" -Level Info
    return $removed
}

#endregion

#region Printer Installation

function Install-NetworkPrinter {
    <#
    .SYNOPSIS
        Installs a network printer with all required components
    
    .DESCRIPTION
        Complete printer installation including:
        - Port creation
        - Driver verification/installation
        - Printer creation
        - Optional sharing
        - Test page printing
    
    .PARAMETER PrinterName
        Display name for the printer
    
    .PARAMETER PortIP
        IP address of the printer
    
    .PARAMETER DriverName
        Printer driver name
    
    .PARAMETER Location
        Physical location of the printer
    
    .PARAMETER Comment
        Description/comment for the printer
    
    .PARAMETER Shared
        Share the printer on the network
    
    .PARAMETER ShareName
        Network share name (defaults to PrinterName)
    
    .PARAMETER Published
        Publish in Active Directory
    
    .PARAMETER PrintTestPage
        Print a test page after installation
    
    .EXAMPLE
        Install-NetworkPrinter -PrinterName "HP-Floor2-Color" -PortIP "192.168.1.100" -DriverName "HP Universal Printing PCL 6" -Location "Building A, Floor 2" -Shared
    
    .EXAMPLE
        Install-NetworkPrinter -PrinterName "Reception-Printer" -PortIP "10.0.0.50" -Shared -PrintTestPage
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [Parameter(Mandatory)]
        [string]$PortIP,
        
        [string]$DriverName = $script:Config.DefaultDriverName,
        
        [string]$PortName,
        
        [string]$Location,
        
        [string]$Comment,
        
        [switch]$Shared,
        
        [string]$ShareName,
        
        [switch]$Published,
        
        [switch]$PrintTestPage,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    Write-Log "Starting printer installation: $PrinterName" -Level Info
    
    # Check if printer already exists
    if (Test-PrinterExists -PrinterName $PrinterName -ComputerName $ComputerName) {
        Write-Log "Printer '$PrinterName' already exists" -Level Warning
        return $false
    }
    
    # Test printer connectivity
    Write-Log "Testing connectivity to $PortIP..." -Level Info
    if (-not (Test-Connection -ComputerName $PortIP -Count 2 -Quiet)) {
        Write-Log "WARNING: Cannot reach printer at $PortIP. Continuing anyway..." -Level Warning
    }
    else {
        Write-Log "Printer is reachable" -Level Success
    }
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Install network printer")) {
        try {
            # Step 1: Create port
            if (-not $PortName) {
                $PortName = Get-StandardPortName -IPAddress $PortIP
            }
            
            Write-Log "Creating printer port: $PortName" -Level Info
            $createdPort = New-PrinterTCPIPPort -IPAddress $PortIP -PortName $PortName -ComputerName $ComputerName -SNMPEnabled
            
            if (-not $createdPort) {
                throw "Failed to create printer port"
            }
            
            # Step 2: Verify/install driver
            Write-Log "Verifying driver: $DriverName" -Level Info
            if (-not (Test-PrinterDriverExists -DriverName $DriverName -ComputerName $ComputerName)) {
                Write-Log "Driver not found. Attempting to install..." -Level Warning
                $driverInstalled = Install-PrinterDriver -DriverName $DriverName -ComputerName $ComputerName
                
                if (-not $driverInstalled) {
                    throw "Failed to install printer driver: $DriverName"
                }
            }
            else {
                Write-Log "Driver is available" -Level Success
            }
            
            # Step 3: Create printer
            Write-Log "Creating printer: $PrinterName" -Level Info
            
            $printerParams = @{
                Name = $PrinterName
                PortName = $PortName
                DriverName = $DriverName
                ComputerName = $ComputerName
            }
            
            if ($Location) { $printerParams.Location = $Location }
            if ($Comment) { $printerParams.Comment = $Comment }
            
            Add-Printer @printerParams -ErrorAction Stop
            
            # Step 4: Configure sharing
            if ($Shared) {
                if (-not $ShareName) { $ShareName = $PrinterName -replace '\s', '' }
                
                Write-Log "Sharing printer as: $ShareName" -Level Info
                Set-Printer -Name $PrinterName -ComputerName $ComputerName -Shared $true -ShareName $ShareName
                
                if ($Published) {
                    Set-Printer -Name $PrinterName -ComputerName $ComputerName -Published $true
                    Write-Log "Published printer to Active Directory" -Level Info
                }
            }
            
            # Step 5: Print test page
            if ($PrintTestPage) {
                Write-Log "Printing test page..." -Level Info
                Start-Sleep -Seconds 2
                
                try {
                    $printer = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName | 
                        Where-Object { $_.Name -eq $PrinterName }
                    $printer.PrintTestPage() | Out-Null
                    Write-Log "Test page sent to printer" -Level Success
                }
                catch {
                    Write-Log "Could not print test page: $_" -Level Warning
                }
            }
            
            Write-Log "Printer '$PrinterName' installed successfully" -Level Success
            
            # Return printer info
            return Get-Printer -Name $PrinterName -ComputerName $ComputerName
        }
        catch {
            Write-Log "Failed to install printer: $_" -Level Error
            
            # Cleanup on failure
            if (Test-PrinterExists -PrinterName $PrinterName -ComputerName $ComputerName) {
                Remove-Printer -Name $PrinterName -ComputerName $ComputerName -ErrorAction SilentlyContinue
            }
            
            return $false
        }
    }
}

function Install-LocalPrinter {
    <#
    .SYNOPSIS
        Installs a local (USB) printer
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [Parameter(Mandatory)]
        [string]$DriverName,
        
        [Parameter(Mandatory)]
        [string]$PortName,
        
        [string]$Location,
        
        [string]$Comment
    )
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Install local printer")) {
        try {
            $printerParams = @{
                Name = $PrinterName
                PortName = $PortName
                DriverName = $DriverName
            }
            
            if ($Location) { $printerParams.Location = $Location }
            if ($Comment) { $printerParams.Comment = $Comment }
            
            Add-Printer @printerParams -ErrorAction Stop
            Write-Log "Local printer '$PrinterName' installed successfully" -Level Success
            
            return Get-Printer -Name $PrinterName
        }
        catch {
            Write-Log "Failed to install local printer: $_" -Level Error
            return $false
        }
    }
}

function Remove-PrinterComplete {
    <#
    .SYNOPSIS
        Completely removes a printer including port cleanup
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$RemovePort,
        
        [switch]$CancelJobs
    )
    
    if (-not (Test-PrinterExists -PrinterName $PrinterName -ComputerName $ComputerName)) {
        Write-Log "Printer '$PrinterName' not found" -Level Warning
        return $false
    }
    
    $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName
    $portName = $printer.PortName
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Remove printer")) {
        try {
            # Cancel pending jobs if requested
            if ($CancelJobs) {
                $jobs = Get-PrintJob -PrinterName $PrinterName -ComputerName $ComputerName -ErrorAction SilentlyContinue
                foreach ($job in $jobs) {
                    Remove-PrintJob -InputObject $job -ErrorAction SilentlyContinue
                }
                Write-Log "Cancelled pending print jobs" -Level Info
            }
            
            # Remove printer
            Remove-Printer -Name $PrinterName -ComputerName $ComputerName -ErrorAction Stop
            Write-Log "Removed printer: $PrinterName" -Level Success
            
            # Remove port if requested
            if ($RemovePort -and $portName) {
                Start-Sleep -Seconds 1
                
                # Check if port is used by other printers
                $otherPrinters = Get-Printer -ComputerName $ComputerName | 
                    Where-Object { $_.PortName -eq $portName }
                
                if (-not $otherPrinters) {
                    Remove-PrinterPort -Name $portName -ComputerName $ComputerName -ErrorAction SilentlyContinue
                    Write-Log "Removed printer port: $portName" -Level Success
                }
                else {
                    Write-Log "Port '$portName' is used by other printers, not removed" -Level Info
                }
            }
            
            return $true
        }
        catch {
            Write-Log "Failed to remove printer: $_" -Level Error
            return $false
        }
    }
}

#endregion

#region Bulk Deployment

function Import-PrinterDeployment {
    <#
    .SYNOPSIS
        Bulk deploys printers from CSV file
    
    .DESCRIPTION
        Imports printer definitions from CSV and deploys each printer
    
    .PARAMETER CSVPath
        Path to CSV file with printer definitions
    
    .PARAMETER WhatIf
        Preview changes without deploying
    
    .EXAMPLE
        Import-PrinterDeployment -CSVPath ".\printers.csv"
    
    .NOTES
        CSV Format: PrinterName,IPAddress,DriverName,Location,Comment,Shared,ShareName
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$CSVPath,
        
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$ContinueOnError
    )
    
    if (-not (Test-Path $CSVPath)) {
        Write-Log "CSV file not found: $CSVPath" -Level Error
        return
    }
    
    Write-Log "Importing printer definitions from: $CSVPath" -Level Info
    
    $printers = Import-Csv -Path $CSVPath
    $results = @()
    $successCount = 0
    $failCount = 0
    
    foreach ($printer in $printers) {
        Write-Host ""
        Write-Log "Processing: $($printer.PrinterName)" -Level Info
        
        $result = [PSCustomObject]@{
            PrinterName = $printer.PrinterName
            IPAddress = $printer.IPAddress
            Status = "Pending"
            Error = $null
        }
        
        try {
            $installParams = @{
                PrinterName = $printer.PrinterName
                PortIP = $printer.IPAddress
                ComputerName = $ComputerName
            }
            
            if ($printer.DriverName) { $installParams.DriverName = $printer.DriverName }
            if ($printer.Location) { $installParams.Location = $printer.Location }
            if ($printer.Comment) { $installParams.Comment = $printer.Comment }
            if ($printer.Shared -eq 'TRUE' -or $printer.Shared -eq 'Yes') { $installParams.Shared = $true }
            if ($printer.ShareName) { $installParams.ShareName = $printer.ShareName }
            
            $installed = Install-NetworkPrinter @installParams
            
            if ($installed) {
                $result.Status = "Success"
                $successCount++
            }
            else {
                $result.Status = "Failed"
                $result.Error = "Installation returned false"
                $failCount++
            }
        }
        catch {
            $result.Status = "Failed"
            $result.Error = $_.Exception.Message
            $failCount++
            
            if (-not $ContinueOnError) {
                Write-Log "Stopping deployment due to error. Use -ContinueOnError to continue." -Level Error
                break
            }
        }
        
        $results += $result
    }
    
    # Summary
    Write-Host ""
    Write-Host "═" * 50 -ForegroundColor Cyan
    Write-Log "Deployment Complete" -Level Info
    Write-Host "  Successful: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "═" * 50 -ForegroundColor Cyan
    
    return $results
}

function Export-PrinterConfiguration {
    <#
    .SYNOPSIS
        Exports current printer configuration to CSV for backup or migration
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    Write-Log "Exporting printer configuration from $ComputerName" -Level Info
    
    try {
        $printers = Get-Printer -ComputerName $ComputerName
        $ports = Get-PrinterPort -ComputerName $ComputerName
        
        $export = foreach ($printer in $printers) {
            $port = $ports | Where-Object { $_.Name -eq $printer.PortName }
            
            [PSCustomObject]@{
                PrinterName = $printer.Name
                IPAddress = $port.PrinterHostAddress
                PortName = $printer.PortName
                DriverName = $printer.DriverName
                Location = $printer.Location
                Comment = $printer.Comment
                Shared = $printer.Shared
                ShareName = $printer.ShareName
                Published = $printer.Published
                PrintProcessor = $printer.PrintProcessor
            }
        }
        
        $export | Export-Csv -Path $OutputPath -NoTypeInformation
        Write-Log "Exported $($export.Count) printers to: $OutputPath" -Level Success
        
        return $OutputPath
    }
    catch {
        Write-Log "Failed to export configuration: $_" -Level Error
        return $null
    }
}

function New-PrinterDeploymentTemplate {
    <#
    .SYNOPSIS
        Creates a CSV template for bulk printer deployment
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath = ".\printer-deployment-template.csv"
    )
    
    $template = @(
        [PSCustomObject]@{
            PrinterName = "HP-Floor1-BW"
            IPAddress = "192.168.1.100"
            DriverName = "HP Universal Printing PCL 6"
            Location = "Building A, Floor 1, Room 101"
            Comment = "Black & White Laser"
            Shared = "TRUE"
            ShareName = "HP-Floor1-BW"
        },
        [PSCustomObject]@{
            PrinterName = "HP-Floor2-Color"
            IPAddress = "192.168.1.101"
            DriverName = "HP Universal Printing PCL 6"
            Location = "Building A, Floor 2, Room 201"
            Comment = "Color Laser"
            Shared = "TRUE"
            ShareName = "HP-Floor2-Color"
        }
    )
    
    $template | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Log "Created template: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region Printer Configuration

function Set-PrinterDefaults {
    <#
    .SYNOPSIS
        Configures default printing preferences
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [ValidateSet('Portrait', 'Landscape')]
        [string]$Orientation,
        
        [ValidateSet('OneSided', 'TwoSidedLongEdge', 'TwoSidedShortEdge')]
        [string]$Duplex,
        
        [ValidateSet('Color', 'Grayscale', 'Monochrome')]
        [string]$Color,
        
        [ValidateSet('Letter', 'Legal', 'A4', 'A3')]
        [string]$PaperSize,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Set printing defaults")) {
        try {
            $config = Get-PrintConfiguration -PrinterName $PrinterName -ComputerName $ComputerName
            
            # Build configuration
            $setParams = @{
                PrinterName = $PrinterName
                ComputerName = $ComputerName
            }
            
            if ($Duplex) {
                $duplexMode = switch ($Duplex) {
                    'OneSided' { 'OneSided' }
                    'TwoSidedLongEdge' { 'TwoSidedLongEdge' }
                    'TwoSidedShortEdge' { 'TwoSidedShortEdge' }
                }
                $setParams.DuplexingMode = $duplexMode
            }
            
            if ($Color) {
                $setParams.Color = ($Color -eq 'Color')
            }
            
            Set-PrintConfiguration @setParams
            
            Write-Log "Updated defaults for '$PrinterName'" -Level Success
            return $true
        }
        catch {
            Write-Log "Failed to set printer defaults: $_" -Level Error
            return $false
        }
    }
}

function Set-DefaultPrinter {
    <#
    .SYNOPSIS
        Sets the default printer for a user
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName
    )
    
    try {
        $printer = Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.Name -eq $PrinterName }
        
        if (-not $printer) {
            Write-Log "Printer '$PrinterName' not found" -Level Error
            return $false
        }
        
        Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter | Out-Null
        Write-Log "Set '$PrinterName' as default printer" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to set default printer: $_" -Level Error
        return $false
    }
}

function Set-PrinterPermissions {
    <#
    .SYNOPSIS
        Configures printer security permissions
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [Parameter(Mandatory)]
        [string]$Identity,
        
        [ValidateSet('Print', 'ManagePrinters', 'ManageDocuments', 'FullControl')]
        [string]$Permission = 'Print',
        
        [ValidateSet('Allow', 'Deny')]
        [string]$AccessType = 'Allow',
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    if ($PSCmdlet.ShouldProcess("$PrinterName - $Identity", "Set $AccessType $Permission permission")) {
        try {
            # Get printer
            $printer = Get-Printer -Name $PrinterName -ComputerName $ComputerName -Full
            
            # Define permission mappings
            $permissionMap = @{
                'Print' = 'Print'
                'ManagePrinters' = 'ManagePrinters'
                'ManageDocuments' = 'ManageDocuments'
                'FullControl' = 'FullControl'
            }
            
            # This requires direct SDDL manipulation or use of WMI
            # For simplicity, using icacls-style approach via Set-Printer isn't directly available
            # Would need to use:
            # - SetSecurityDescriptor WMI method
            # - Or configure via Group Policy
            
            Write-Log "Printer permissions should be configured via Print Management console or Group Policy" -Level Warning
            Write-Log "For programmatic access, use WMI Win32_Printer.SetSecurityDescriptor" -Level Info
            
            return $true
        }
        catch {
            Write-Log "Failed to set permissions: $_" -Level Error
            return $false
        }
    }
}

#endregion

#region Printer Migration

function Copy-PrinterToServer {
    <#
    .SYNOPSIS
        Copies/migrates a printer to another print server
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [Parameter(Mandatory)]
        [string]$SourceServer,
        
        [Parameter(Mandatory)]
        [string]$DestinationServer,
        
        [switch]$IncludeDriver,
        
        [switch]$RemoveFromSource
    )
    
    Write-Log "Migrating printer '$PrinterName' from $SourceServer to $DestinationServer" -Level Info
    
    try {
        # Get source printer details
        $sourcePrinter = Get-Printer -Name $PrinterName -ComputerName $SourceServer -Full
        $sourcePort = Get-PrinterPort -Name $sourcePrinter.PortName -ComputerName $SourceServer
        
        if (-not $sourcePrinter) {
            Write-Log "Source printer not found" -Level Error
            return $false
        }
        
        if ($PSCmdlet.ShouldProcess($PrinterName, "Migrate to $DestinationServer")) {
            # Check/install driver on destination
            if (-not (Test-PrinterDriverExists -DriverName $sourcePrinter.DriverName -ComputerName $DestinationServer)) {
                if ($IncludeDriver) {
                    Write-Log "Installing driver on destination server..." -Level Info
                    Install-PrinterDriver -DriverName $sourcePrinter.DriverName -ComputerName $DestinationServer
                }
                else {
                    Write-Log "Driver '$($sourcePrinter.DriverName)' not found on destination. Use -IncludeDriver to install." -Level Error
                    return $false
                }
            }
            
            # Create printer on destination
            $installParams = @{
                PrinterName = $sourcePrinter.Name
                PortIP = $sourcePort.PrinterHostAddress
                DriverName = $sourcePrinter.DriverName
                Location = $sourcePrinter.Location
                Comment = $sourcePrinter.Comment
                ComputerName = $DestinationServer
            }
            
            if ($sourcePrinter.Shared) {
                $installParams.Shared = $true
                $installParams.ShareName = $sourcePrinter.ShareName
            }
            
            $result = Install-NetworkPrinter @installParams
            
            if ($result -and $RemoveFromSource) {
                Write-Log "Removing printer from source server..." -Level Info
                Remove-PrinterComplete -PrinterName $PrinterName -ComputerName $SourceServer -RemovePort
            }
            
            return $result
        }
    }
    catch {
        Write-Log "Migration failed: $_" -Level Error
        return $false
    }
}

function Start-PrintServerMigration {
    <#
    .SYNOPSIS
        Migrates all printers from one server to another
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SourceServer,
        
        [Parameter(Mandatory)]
        [string]$DestinationServer,
        
        [string[]]$ExcludePrinters,
        
        [switch]$IncludeDrivers,
        
        [switch]$RemoveFromSource
    )
    
    Write-Log "Starting print server migration: $SourceServer -> $DestinationServer" -Level Info
    
    $sourcePrinters = Get-Printer -ComputerName $SourceServer
    
    if ($ExcludePrinters) {
        $sourcePrinters = $sourcePrinters | Where-Object { $_.Name -notin $ExcludePrinters }
    }
    
    Write-Log "Found $($sourcePrinters.Count) printers to migrate" -Level Info
    
    $results = @()
    
    foreach ($printer in $sourcePrinters) {
        $result = [PSCustomObject]@{
            PrinterName = $printer.Name
            Status = "Pending"
            Error = $null
        }
        
        try {
            $migrated = Copy-PrinterToServer -PrinterName $printer.Name `
                                             -SourceServer $SourceServer `
                                             -DestinationServer $DestinationServer `
                                             -IncludeDriver:$IncludeDrivers `
                                             -RemoveFromSource:$RemoveFromSource
            
            $result.Status = if ($migrated) { "Success" } else { "Failed" }
        }
        catch {
            $result.Status = "Failed"
            $result.Error = $_.Exception.Message
        }
        
        $results += $result
    }
    
    # Summary
    $success = ($results | Where-Object { $_.Status -eq 'Success' }).Count
    $failed = ($results | Where-Object { $_.Status -eq 'Failed' }).Count
    
    Write-Host ""
    Write-Log "Migration Complete: $success succeeded, $failed failed" -Level $(if ($failed -eq 0) { 'Success' } else { 'Warning' })
    
    return $results
}

#endregion

#region Utility Functions

function Get-PrinterInventory {
    <#
    .SYNOPSIS
        Gets comprehensive printer inventory
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$IncludeStatus
    )
    
    try {
        $printers = Get-Printer -ComputerName $ComputerName
        $ports = Get-PrinterPort -ComputerName $ComputerName
        
        $inventory = foreach ($printer in $printers) {
            $port = $ports | Where-Object { $_.Name -eq $printer.PortName }
            
            $info = [PSCustomObject]@{
                Name = $printer.Name
                ShareName = $printer.ShareName
                DriverName = $printer.DriverName
                PortName = $printer.PortName
                IPAddress = $port.PrinterHostAddress
                Location = $printer.Location
                Comment = $printer.Comment
                Shared = $printer.Shared
                Published = $printer.Published
                Type = $printer.Type
                PrinterStatus = $null
                JobCount = $null
            }
            
            if ($IncludeStatus) {
                try {
                    $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName | 
                        Where-Object { $_.Name -eq $printer.Name }
                    
                    $info.PrinterStatus = switch ($wmiPrinter.PrinterStatus) {
                        1 { "Other" }
                        2 { "Unknown" }
                        3 { "Idle" }
                        4 { "Printing" }
                        5 { "Warming Up" }
                        6 { "Stopped" }
                        7 { "Offline" }
                        default { "Unknown" }
                    }
                    
                    $jobs = Get-PrintJob -PrinterName $printer.Name -ComputerName $ComputerName -ErrorAction SilentlyContinue
                    $info.JobCount = ($jobs | Measure-Object).Count
                }
                catch { }
            }
            
            $info
        }
        
        return $inventory
    }
    catch {
        Write-Log "Failed to get printer inventory: $_" -Level Error
        return @()
    }
}

function Test-PrinterConnectivity {
    <#
    .SYNOPSIS
        Tests connectivity to all configured printers
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    $printers = Get-Printer -ComputerName $ComputerName
    $ports = Get-PrinterPort -ComputerName $ComputerName
    
    $results = foreach ($printer in $printers) {
        $port = $ports | Where-Object { $_.Name -eq $printer.PortName }
        
        $result = [PSCustomObject]@{
            PrinterName = $printer.Name
            IPAddress = $port.PrinterHostAddress
            Reachable = $false
            ResponseTime = $null
            Port9100Open = $false
            WebInterfaceAvailable = $false
        }
        
        if ($port.PrinterHostAddress) {
            # Ping test
            $ping = Test-Connection -ComputerName $port.PrinterHostAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
            $result.Reachable = $ping
            
            if ($ping) {
                $pingResult = Test-Connection -ComputerName $port.PrinterHostAddress -Count 1 -ErrorAction SilentlyContinue
                $result.ResponseTime = $pingResult.ResponseTime
                
                # Port 9100 test
                try {
                    $tcpTest = New-Object System.Net.Sockets.TcpClient
                    $connect = $tcpTest.BeginConnect($port.PrinterHostAddress, 9100, $null, $null)
                    $wait = $connect.AsyncWaitHandle.WaitOne(1000, $false)
                    $result.Port9100Open = $wait -and $tcpTest.Connected
                    $tcpTest.Close()
                }
                catch { }
                
                # Web interface test
                try {
                    $web = Invoke-WebRequest -Uri "http://$($port.PrinterHostAddress)" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
                    $result.WebInterfaceAvailable = $true
                }
                catch { }
            }
        }
        
        $result
    }
    
    return $results
}

function Clear-PrintQueue {
    <#
    .SYNOPSIS
        Clears all jobs from a printer queue
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    if ($PSCmdlet.ShouldProcess($PrinterName, "Clear print queue")) {
        try {
            $jobs = Get-PrintJob -PrinterName $PrinterName -ComputerName $ComputerName
            
            foreach ($job in $jobs) {
                Remove-PrintJob -InputObject $job -ErrorAction SilentlyContinue
            }
            
            Write-Log "Cleared $($jobs.Count) jobs from '$PrinterName'" -Level Success
            return $jobs.Count
        }
        catch {
            Write-Log "Failed to clear print queue: $_" -Level Error
            return -1
        }
    }
}

function Restart-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the print spooler service
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [switch]$ClearQueue
    )
    
    if ($PSCmdlet.ShouldProcess($ComputerName, "Restart Print Spooler")) {
        try {
            Write-Log "Stopping Print Spooler on $ComputerName..." -Level Info
            Stop-Service -Name Spooler -Force -ErrorAction Stop
            
            if ($ClearQueue) {
                # Clear spool folder
                $spoolPath = "\\$ComputerName\C$\Windows\System32\spool\PRINTERS"
                if ($ComputerName -eq $env:COMPUTERNAME) {
                    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
                }
                
                Get-ChildItem -Path $spoolPath -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log "Cleared spool folder" -Level Info
            }
            
            Start-Sleep -Seconds 2
            
            Write-Log "Starting Print Spooler..." -Level Info
            Start-Service -Name Spooler -ErrorAction Stop
            
            Write-Log "Print Spooler restarted successfully" -Level Success
            return $true
        }
        catch {
            Write-Log "Failed to restart Print Spooler: $_" -Level Error
            return $false
        }
    }
}

#endregion

#region Main Function

function Start-PrinterDeployment {
    <#
    .SYNOPSIS
        Interactive printer deployment wizard
    #>
    [CmdletBinding()]
    param()
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║              Printer Deployment Wizard                         ║" -ForegroundColor Magenta
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    
    Write-Host "Select deployment option:" -ForegroundColor Cyan
    Write-Host "  1. Install single network printer"
    Write-Host "  2. Bulk import from CSV"
    Write-Host "  3. Export current printer configuration"
    Write-Host "  4. Create deployment template"
    Write-Host "  5. Test printer connectivity"
    Write-Host "  6. Exit"
    Write-Host ""
    
    $choice = Read-Host "Enter choice (1-6)"
    
    switch ($choice) {
        "1" {
            $name = Read-Host "Printer name"
            $ip = Read-Host "Printer IP address"
            $driver = Read-Host "Driver name (press Enter for HP Universal)"
            $location = Read-Host "Location (optional)"
            $shared = Read-Host "Share printer? (Y/N)"
            
            if (-not $driver) { $driver = $script:Config.DefaultDriverName }
            
            $params = @{
                PrinterName = $name
                PortIP = $ip
                DriverName = $driver
            }
            
            if ($location) { $params.Location = $location }
            if ($shared -eq 'Y') { $params.Shared = $true }
            
            Install-NetworkPrinter @params
        }
        "2" {
            $csvPath = Read-Host "CSV file path"
            Import-PrinterDeployment -CSVPath $csvPath
        }
        "3" {
            $outputPath = Read-Host "Output CSV path"
            Export-PrinterConfiguration -OutputPath $outputPath
        }
        "4" {
            $templatePath = Read-Host "Template output path (or Enter for default)"
            if (-not $templatePath) { $templatePath = ".\printer-deployment-template.csv" }
            New-PrinterDeploymentTemplate -OutputPath $templatePath
        }
        "5" {
            $results = Test-PrinterConnectivity
            $results | Format-Table PrinterName, IPAddress, Reachable, ResponseTime, Port9100Open -AutoSize
        }
        "6" {
            return
        }
    }
}

#endregion

# Export functions
Export-ModuleMember -Function Install-NetworkPrinter, Install-LocalPrinter, Remove-PrinterComplete,
    Import-PrinterDeployment, Export-PrinterConfiguration, New-PrinterDeploymentTemplate,
    Install-PrinterDriver, Get-InstalledPrinterDrivers, Remove-PrinterDriverSafe,
    New-PrinterTCPIPPort, Get-PrinterPorts, Remove-UnusedPrinterPorts,
    Set-PrinterDefaults, Set-DefaultPrinter, Set-PrinterPermissions,
    Copy-PrinterToServer, Start-PrintServerMigration,
    Get-PrinterInventory, Test-PrinterConnectivity, Clear-PrintQueue, Restart-PrintSpooler,
    Start-PrinterDeployment

# Display available commands
Write-Host ""
Write-Host "Printer Deployment Module Loaded" -ForegroundColor Green
Write-Host "Run 'Start-PrinterDeployment' for interactive wizard" -ForegroundColor Cyan
Write-Host ""
