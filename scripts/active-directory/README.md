<#
.SYNOPSIS
    Active Directory Group Management Script
    
.DESCRIPTION
    Comprehensive AD group management including:
    - Create, modify, and delete groups
    - Bulk group membership management
    - Group membership auditing and reporting
    - Nested group analysis
    - Group cleanup and maintenance
    
.NOTES
    Author: SysAdmin Toolkit
    Version: 1.0
    Requires: ActiveDirectory module
#>

#Requires -Modules ActiveDirectory

#region Configuration

$script:Config = @{
    # Default settings
    DefaultGroupScope = "Global"
    DefaultGroupCategory = "Security"
    DefaultOU = "OU=Groups,DC=domain,DC=com"  # Update for your environment
    
    # Naming conventions
    SecurityGroupPrefix = "SEC_"
    DistributionGroupPrefix = "DL_"
    
    # Audit settings
    ReportPath = ".\reports\groups"
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
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

function Test-GroupExists {
    param([string]$GroupName)
    
    try {
        $null = Get-ADGroup -Identity $GroupName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region Group Creation

function New-StandardADGroup {
    <#
    .SYNOPSIS
        Creates a new AD group following naming conventions
    
    .PARAMETER GroupName
        Name of the group
    
    .PARAMETER Description
        Group description
    
    .PARAMETER GroupScope
        Scope: DomainLocal, Global, or Universal
    
    .PARAMETER GroupCategory
        Category: Security or Distribution
    
    .PARAMETER Path
        OU path for the group
    
    .PARAMETER ManagedBy
        User or group that manages this group
    
    .PARAMETER Members
        Initial members to add
    
    .EXAMPLE
        New-StandardADGroup -GroupName "IT-Support" -Description "IT Support Team" -GroupCategory Security
    
    .EXAMPLE
        New-StandardADGroup -GroupName "Marketing-DL" -Description "Marketing Distribution List" -GroupCategory Distribution
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,
        
        [Parameter(Mandatory)]
        [string]
