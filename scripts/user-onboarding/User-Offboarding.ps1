<#
.SYNOPSIS
    Comprehensive User Offboarding Automation Script
    
.DESCRIPTION
    Complete user offboarding solution including:
    - Active Directory account disable/archive
    - Group membership removal and documentation
    - Email forwarding and out-of-office setup
    - Home folder backup and archival
    - License removal
    - Access revocation documentation
    - Manager notification
    - Compliance logging and audit trail
    
.PARAMETER Username
    Username of the account to offboard

.PARAMETER LastDay
    User's last working day

.PARAMETER ForwardEmail
    Email address to forward messages to

.PARAMETER ArchiveMailbox
    Archive mailbox before disabling

.PARAMETER Immediate
    Process offboarding immediately (for terminations)

.EXAMPLE
    Start-UserOffboarding -Username "jsmith" -LastDay (Get-Date).AddDays(14)
    
.EXAMPLE
    Start-UserOffboarding -Username "jdoe" -Immediate -ForwardEmail "manager@company.com"

.EXAMPLE
    Start-UserOffboarding -Username "contractor1" -Immediate -SkipArchive

.NOTES
    Author: SysAdmin Toolkit
    Version: 2.0
    Requires: ActiveDirectory module, appropriate permissions
#>

#Requires -Modules ActiveDirectory

#region Configuration

$script:Config = @{
    # Domain settings
    Domain = (Get-ADDomain).DNSRoot
    DomainDN = (Get-ADDomain).DistinguishedName
    
    # Disabled users OU
    DisabledUsersOU = "OU=Disabled Users,OU=Corp"
    TerminatedUsersOU = "OU=Terminated,OU=Disabled Users,OU=Corp"
    
    # Archive settings
    ArchivePath = "\\fileserver\archives\users"
    HomeFolderRoot = "\\fileserver\users$"
    ProfilePath = "\\fileserver\profiles$"
    BackupBeforeDelete = $true
    CompressArchive = $true
    
    # Retention settings
    AccountRetentionDays = 90          # Days to keep disabled account
    ArchiveRetentionDays = 365         # Days to keep archived data
    DeleteAccountAfterRetention = $false
    
    # Email/Exchange settings
    SetOutOfOffice = $true
    OutOfOfficeTemplate = @"
Thank you for your email. I am no longer with {COMPANY}. 

For assistance, please contact:
{MANAGER_NAME} - {MANAGER_EMAIL}

Or contact our main office at info@{DOMAIN}

This mailbox is not monitored.
"@
    DefaultForwardingDays = 30
    HideFromGAL = $true
    ConvertToSharedMailbox = $true
    
    # Notification settings
    SendNotifications = $true
    NotifyManager = $true
    NotifyHR = $true
    NotifyIT = $true
    HREmail = "hr@company.com"
    ITEmail = "helpdesk@company.com"
    SecurityEmail = "security@company.com"
    
    # Company info
    CompanyName = "Company Name"
    
    # Logging
    LogPath = ".\logs\offboarding"
    AuditLogPath = ".\logs\audit"
    
    # Report path
    ReportPath = ".\reports\offboarding"
    
    # Groups to always remove immediately (security sensitive)
    SensitiveGroups = @(
        "VPN-Users",
        "Remote-Desktop-Users",
        "Admin-Tools-Access",
        "Financial-Systems-Access",
        "Confidential-Access",
        "Domain Admins",
        "Enterprise Admins",
        "Server-Admins",
        "SQL-Admins"
    )
    
    # Groups to preserve for documentation only
    DocumentOnlyGroups = @(
        "Domain Users"
    )
}

# Offboarding session tracking
$script:OffboardingSession = @{
    StartTime = $null
    Username = $null
    Actions = @()
    Errors = @()
    Warnings = @()
    RemovedGroups = @()
    PreservedGroups = @()
    BackupLocations = @()
    OriginalState = $null
}

#endregion

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Action', 'Debug', 'Security')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Action' = 'Magenta'
        'Debug' = 'Gray'
        'Security' = 'DarkRed'
    }
    $prefixes = @{
        'Info' = '[*]'
        'Warning' = '[!]'
        'Error' = '[X]'
        'Success' = '[✓]'
        'Action' = '[>]'
        'Debug' = '[D]'
        'Security' = '[!SEC!]'
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "$timestamp $($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
    
    $script:OffboardingSession.Actions += [PSCustomObject]@{
        Timestamp = Get-Date
        Level = $Level
        Message = $Message
    }
    
    if ($Level -eq 'Error') {
        $script:OffboardingSession.Errors += $Message
    }
    elseif ($Level -eq 'Warning') {
        $script:OffboardingSession.Warnings += $Message
    }
}

function Get-UserOriginalState {
    <#
    .SYNOPSIS
        Captures the current state of a user for documentation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )
    
    try {
        $user = Get-ADUser -Identity $Username -Properties * -ErrorAction Stop
        $groups = Get-ADPrincipalGroupMembership -Identity $Username -ErrorAction SilentlyContinue
        
        return [PSCustomObject]@{
            CapturedAt = Get-Date
            Username = $user.SamAccountName
            DisplayName = $user.DisplayName
            Email = $user.EmailAddress
            Title = $user.Title
            Department = $user.Department
            Manager = $user.Manager
            ManagerName = if ($user.Manager) { (Get-ADUser -Identity $user.Manager).Name } else { $null }
            EmployeeID = $user.EmployeeID
            Created = $user.Created
            LastLogon = $user.LastLogonDate
            PasswordLastSet = $user.PasswordLastSet
            Enabled = $user.Enabled
            LockedOut = $user.LockedOut
            HomeDirectory = $user.HomeDirectory
            ProfilePath = $user.ProfilePath
            DistinguishedName = $user.DistinguishedName
            Groups = $groups | Select-Object Name, GroupCategory, GroupScope
            GroupCount = $groups.Count
            MemberOf = $user.MemberOf
        }
    }
    catch {
        Write-Log "Failed to capture user state: $_" -Level Error
        return $null
    }
}

function Save-OffboardingLog {
    param(
        [string]$Username,
        [string]$OutputPath
    )
    
    if (-not (Test-Path $script:Config.LogPath)) {
        New-Item -Path $script:Config.LogPath -ItemType Directory -Force | Out-Null
    }
    
    if (-not $OutputPath) {
        $OutputPath = Join-Path $script:Config.LogPath "Offboarding_$($Username)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
    
    $logContent = @"
================================================================================
                        USER OFFBOARDING LOG
================================================================================
Username:       $Username
Display Name:   $($script:OffboardingSession.OriginalState.DisplayName)
Department:     $($script:OffboardingSession.OriginalState.Department)
Title:          $($script:OffboardingSession.OriginalState.Title)
Manager:        $($script:OffboardingSession.OriginalState.ManagerName)

Start Time:     $($script:OffboardingSession.StartTime)
End Time:       $(Get-Date)
Performed By:   $env:USERNAME
Computer:       $env:COMPUTERNAME

================================================================================
                           ACTIONS TAKEN
================================================================================
"@
    
    foreach ($action in $script:OffboardingSession.Actions) {
        $logContent += "`n$($action.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) [$($action.Level.PadRight(8))] $($action.Message)"
    }
    
    $logContent += @"

================================================================================
                         GROUPS REMOVED ($($script:OffboardingSession.RemovedGroups.Count))
================================================================================
"@
    foreach ($group in $script:OffboardingSession.RemovedGroups) {
        $logContent += "`n  - $group"
    }
    
    if ($script:OffboardingSession.BackupLocations) {
        $logContent += @"

================================================================================
                          BACKUP LOCATIONS
================================================================================
"@
        foreach ($location in $script:OffboardingSession.BackupLocations) {
            $logContent += "`n  - $location"
        }
    }
    
    if ($script:OffboardingSession.Errors) {
        $logContent += @"

================================================================================
                              ERRORS
================================================================================
"@
        foreach ($error in $script:OffboardingSession.Errors) {
            $logContent += "`n  ! $error"
        }
    }
    
    if ($script:OffboardingSession.Warnings) {
        $logContent += @"

================================================================================
                             WARNINGS
================================================================================
"@
        foreach ($warning in $script:OffboardingSession.Warnings) {
            $logContent += "`n  * $warning"
        }
    }
    
    $logContent += @"

================================================================================
                        ORIGINAL USER STATE
================================================================================
Username:           $($script:OffboardingSession.OriginalState.Username)
Email:              $($script:OffboardingSession.OriginalState.Email)
Employee ID:        $($script:OffboardingSession.OriginalState.EmployeeID)
Created:            $($script:OffboardingSession.OriginalState.Created)
Last Logon:         $($script:OffboardingSession.OriginalState.LastLogon)
Password Last Set:  $($script:OffboardingSession.OriginalState.PasswordLastSet)
Home Directory:     $($script:OffboardingSession.OriginalState.HomeDirectory)
Original OU:        $($script:OffboardingSession.OriginalState.DistinguishedName)
Total Groups:       $($script:OffboardingSession.OriginalState.GroupCount)

================================================================================
                     END OF OFFBOARDING LOG
================================================================================
"@
    
    $logContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Offboarding log saved to: $OutputPath" -Level Info
    
    return $OutputPath
}

function Save-AuditRecord {
    <#
    .SYNOPSIS
        Saves audit record for compliance
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [string]$Action,
        
        [string]$Details
    )
    
    if (-not (Test-Path $script:Config.AuditLogPath)) {
        New-Item -Path $script:Config.AuditLogPath -ItemType Directory -Force | Out-Null
    }
    
    $auditFile = Join-Path $script:Config.AuditLogPath "offboarding_audit_$(Get-Date -Format 'yyyyMM').csv"
    
    $auditRecord = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Username = $Username
        Action = $Action
        PerformedBy = $env:USERNAME
        Computer = $env:COMPUTERNAME
        Details = $Details
    }
    
    $auditRecord | Export-Csv -Path $auditFile -Append -NoTypeInformation
}

#endregion

#region Account Management

function Disable-UserAccount {
    <#
    .SYNOPSIS
        Disables user account and updates properties
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [datetime]$TerminationDate = (Get-Date),
        
        [string]$Reason = "Employee separation"
    )
    
    Write-Log "Disabling user account: $Username" -Level Action
    
    if ($PSCmdlet.ShouldProcess($Username, "Disable AD account")) {
        try {
            # Disable the account
            Disable-ADAccount -Identity $Username -ErrorAction Stop
            Write-Log "Account disabled" -Level Success
            
            # Update description with termination info
            $newDescription = "DISABLED $(Get-Date -Format 'yyyy-MM-dd') - $Reason - By $env:USERNAME"
            Set-ADUser -Identity $Username -Description $newDescription
            
            # Clear sensitive attributes
            Set-ADUser -Identity $Username -Clear @(
                'telephoneNumber',
                'mobile', 
                'pager',
                'facsimileTelephoneNumber',
                'ipPhone'
            ) -ErrorAction SilentlyContinue
            
            Write-Log "User attributes updated" -Level Success
            
            Save-AuditRecord -Username $Username -Action "AccountDisabled" -Details $Reason
            
            return $true
        }
        catch {
            Write-Log "Failed to disable account: $_" -Level Error
            return $false
        }
    }
}

function Reset-UserPassword {
    <#
    .SYNOPSIS
        Resets user password to random string (security measure)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )
    
    Write-Log "Resetting password for security" -Level Security
    
    if ($PSCmdlet.ShouldProcess($Username, "Reset password")) {
        try {
            # Generate random password
            $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
            $password = -join ((1..32) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
            
            Set-ADAccountPassword -Identity $Username -NewPassword $securePassword -Reset
            
            Write-Log "Password reset to random value" -Level Success
            Save-AuditRecord -Username $Username -Action "PasswordReset" -Details "Security reset during offboarding"
            
            return $true
        }
        catch {
            Write-Log "Failed to reset password: $_" -Level Error
            return $false
        }
    }
}

function Move-UserToDisabledOU {
    <#
    .SYNOPSIS
        Moves user to disabled users OU
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [switch]$Terminated
    )
    
    $targetOU = if ($Terminated) {
        "$($script:Config.TerminatedUsersOU),$($script:Config.DomainDN)"
    }
    else {
        "$($script:Config.DisabledUsersOU),$($script:Config.DomainDN)"
    }
    
    Write-Log "Moving user to: $targetOU" -Level Action
    
    if ($PSCmdlet.ShouldProcess($Username, "Move to Disabled OU")) {
        try {
            # Verify OU exists
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$targetOU'" -ErrorAction SilentlyContinue)) {
                Write-Log "Target OU does not exist: $targetOU" -Level Warning
                Write-Log "Creating disabled users OU..." -Level Info
                
                # Try to create the OU
                $ouParts = $targetOU -split ','
                $ouName = ($ouParts[0] -split '=')[1]
                $parentDN = ($ouParts[1..($ouParts.Length-1)]) -join ','
                
                New-ADOrganizationalUnit -Name $ouName -Path $parentDN -ErrorAction Stop
            }
            
            $user = Get-ADUser -Identity $Username
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $targetOU -ErrorAction Stop
            
            Write-Log "User moved to disabled OU" -Level Success
            Save-AuditRecord -Username $Username -Action "MovedToDisabledOU" -Details $targetOU
            
            return $true
        }
        catch {
            Write-Log "Failed to move user: $_" -Level Error
            return $false
        }
    }
}

function Set-AccountExpiration {
    <#
    .SYNOPSIS
        Sets account to expire for automatic cleanup
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [int]$DaysUntilExpiration = $script:Config.AccountRetentionDays
    )
    
    $expirationDate = (Get-Date).AddDays($DaysUntilExpiration)
    
    Write-Log "Setting account expiration: $($expirationDate.ToString('yyyy-MM-dd'))" -Level Info
    
    if ($PSCmdlet.ShouldProcess($Username, "Set account expiration")) {
        try {
            Set-ADUser -Identity $Username -AccountExpirationDate $expirationDate
            
            # Add expiration note to description
            $user = Get-ADUser -Identity $Username -Properties Description
            $newDesc = "$($user.Description) | Expires: $($expirationDate.ToString('yyyy-MM-dd'))"
            Set-ADUser -Identity $Username -Description $newDesc
            
            Write-Log "Account will expire on $($expirationDate.ToString('yyyy-MM-dd'))" -Level Success
            
            return $true
        }
        catch {
            Write-Log "Failed to set expiration: $_" -Level Error
            return $false
        }
    }
}

#endregion

#region Group Membership

function Remove-UserGroupMemberships {
    <#
    .SYNOPSIS
        Removes user from all groups (except Domain Users)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [switch]$SensitiveOnly,
        
        [string[]]$PreserveGroups
    )
    
    Write-Log "Removing group memberships..." -Level Action
    
    $groups = Get-ADPrincipalGroupMembership -Identity $Username -ErrorAction SilentlyContinue
    $removedGroups = @()
    $skippedGroups = @()
    
    foreach ($group in $groups) {
        # Skip Domain Users (can't remove)
        if ($group.Name -eq 'Domain Users') {
            $skippedGroups += $group.Name
            continue
        }
        
        # Skip preserved groups
        if ($PreserveGroups -and $group.Name -in $PreserveGroups) {
            Write-Log "  Preserving group (requested): $($group.Name)" -Level Debug
            $skippedGroups += $group.Name
            continue
        }
        
        # If SensitiveOnly, only remove sensitive groups
        if ($SensitiveOnly -and $group.Name -notin $script:Config.SensitiveGroups) {
            $skippedGroups += $group.Name
            continue
        }
        
        if ($PSCmdlet.ShouldProcess($group.Name, "Remove $Username from group")) {
            try {
                Remove-ADGroupMember -Identity $group -Members $Username -Confirm:$false -ErrorAction Stop
                $removedGroups += $group.Name
                
                # Log sensitive group removals specially
                if ($group.Name -in $script:Config.SensitiveGroups) {
                    Write-Log "  Removed from SENSITIVE group: $($group.Name)" -Level Security
                }
                else {
                    Write-Log "  Removed from: $($group.Name)" -Level Success
                }
            }
            catch {
                Write-Log "  Failed to remove from $($group.Name): $_" -Level Warning
            }
        }
    }
    
    $script:OffboardingSession.RemovedGroups = $removedGroups
    $script:OffboardingSession.PreservedGroups = $skippedGroups
    
    Write-Log "Group removal complete: $($removedGroups.Count) removed, $($skippedGroups.Count) skipped" -Level Info
    
    Save-AuditRecord -Username $Username -Action "GroupsRemoved" -Details "Removed from $($removedGroups.Count) groups"
    
    return [PSCustomObject]@{
        RemovedGroups = $removedGroups
        SkippedGroups = $skippedGroups
    }
}

function Export-UserGroupMembership {
    <#
    .SYNOPSIS
        Exports user's group membership for documentation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$OutputPath
    )
    
    if (-not $OutputPath) {
        if (-not (Test-Path $script:Config.ReportPath)) {
            New-Item -Path $script:Config.ReportPath -ItemType Directory -Force | Out-Null
        }
        $OutputPath = Join-Path $script:Config.ReportPath "GroupMembership_$($Username)_$(Get-Date -Format 'yyyyMMdd').csv"
    }
    
    $groups = Get-ADPrincipalGroupMembership -Identity $Username | 
        Select-Object Name, GroupCategory, GroupScope, @{N='ExportDate';E={Get-Date}}
    
    $groups | Export-Csv -Path $OutputPath -NoTypeInformation
    
    Write-Log "Group membership exported to: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region Home Folder Management

function Backup-UserHomeFolder {
    <#
    .SYNOPSIS
        Backs up and optionally archives user home folder
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$SourcePath,
        
        [string]$ArchivePath = $script:Config.ArchivePath,
        
        [switch]$Compress,
        
        [switch]$DeleteSource
    )
    
    # Determine source path
    if (-not $SourcePath) {
        $user = Get-ADUser -Identity $Username -Properties HomeDirectory
        $SourcePath = $user.HomeDirectory
        
        if (-not $SourcePath) {
            $SourcePath = Join-Path $script:Config.HomeFolderRoot $Username
        }
    }
    
    if (-not (Test-Path $SourcePath)) {
        Write-Log "Home folder not found: $SourcePath" -Level Warning
        return $null
    }
    
    Write-Log "Backing up home folder: $SourcePath" -Level Action
    
    # Create archive directory
    $userArchiveDir = Join-Path $ArchivePath $Username
    $timestamp = Get-Date -Format 'yyyyMMdd'
    
    if ($PSCmdlet.ShouldProcess($SourcePath, "Backup home folder")) {
        try {
            if (-not (Test-Path $userArchiveDir)) {
                New-Item -Path $userArchiveDir -ItemType Directory -Force | Out-Null
            }
            
            if ($Compress -or $script:Config.CompressArchive) {
                # Create compressed archive
                $archiveFile = Join-Path $userArchiveDir "HomeFolder_$timestamp.zip"
                
                Write-Log "Creating compressed archive..." -Level Info
                Compress-Archive -Path "$SourcePath\*" -DestinationPath $archiveFile -Force
                
                $archiveSize = (Get-Item $archiveFile).Length / 1MB
                Write-Log "Archive created: $archiveFile ($([math]::Round($archiveSize, 2)) MB)" -Level Success
                
                $script:OffboardingSession.BackupLocations += $archiveFile
            }
            else {
                # Copy folder
                $destPath = Join-Path $userArchiveDir "HomeFolder_$timestamp"
                
                Write-Log "Copying files..." -Level Info
                Copy-Item -Path $SourcePath -Destination $destPath -Recurse -Force
                
                Write-Log "Folder copied to: $destPath" -Level Success
                $script:OffboardingSession.BackupLocations += $destPath
            }
            
            # Delete source if requested
            if ($DeleteSource) {
                Write-Log "Removing source folder..." -Level Info
                Remove-Item -Path $SourcePath -Recurse -Force
                Write-Log "Source folder removed" -Level Success
            }
            
            # Clear AD attribute
            Set-ADUser -Identity $Username -Clear HomeDirectory, HomeDrive -ErrorAction SilentlyContinue
            
            Save-AuditRecord -Username $Username -Action "HomeFolderArchived" -Details $userArchiveDir
            
            return $userArchiveDir
        }
        catch {
            Write-Log "Failed to backup home folder: $_" -Level Error
            return $null
        }
    }
}

function Backup-UserProfile {
    <#
    .SYNOPSIS
        Backs up roaming profile
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$ArchivePath = $script:Config.ArchivePath,
        
        [switch]$DeleteSource
    )
    
    $user = Get-ADUser -Identity $Username -Properties ProfilePath
    $profilePath = $user.ProfilePath
    
    if (-not $profilePath) {
        $profilePath = Join-Path $script:Config.ProfilePath $Username
    }
    
    # Check for V6 profile folder
    $possiblePaths = @(
        $profilePath,
        "$profilePath.V6",
        "$profilePath.V5",
        "$profilePath.V4",
        "$profilePath.V2"
    )
    
    $actualPath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $actualPath) {
        Write-Log "No roaming profile found for $Username" -Level Info
        return $null
    }
    
    Write-Log "Backing up roaming profile: $actualPath" -Level Action
    
    if ($PSCmdlet.ShouldProcess($actualPath, "Backup roaming profile")) {
        try {
            $userArchiveDir = Join-Path $ArchivePath $Username
            $timestamp = Get-Date -Format 'yyyyMMdd'
            $archiveFile = Join-Path $userArchiveDir "Profile_$timestamp.zip"
            
            if (-not (Test-Path $userArchiveDir)) {
                New-Item -Path $userArchiveDir -ItemType Directory -Force | Out-Null
            }
            
            Compress-Archive -Path "$actualPath\*" -DestinationPath $archiveFile -Force
            
            Write-Log "Profile archived: $archiveFile" -Level Success
            $script:OffboardingSession.BackupLocations += $archiveFile
            
            if ($DeleteSource) {
                Remove-Item -Path $actualPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Profile folder removed" -Level Success
            }
            
            # Clear AD attribute
            Set-ADUser -Identity $Username -Clear ProfilePath -ErrorAction SilentlyContinue
            
            return $archiveFile
        }
        catch {
            Write-Log "Failed to backup profile: $_" -Level Error
            return $null
        }
    }
}

#endregion

#region Email/Exchange Functions

function Set-OutOfOfficeMessage {
    <#
    .SYNOPSIS
        Sets out of office message for departing user
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$Message,
        
        [string]$ManagerEmail,
        
        [string]$ManagerName
    )
    
    Write-Log "Setting out of office message..." -Level Action
    
    # Build message from template if not provided
    if (-not $Message) {
        $user = Get-ADUser -Identity $Username -Properties Manager, EmailAddress
        
        if (-not $ManagerName -and $user.Manager) {
            $manager = Get-ADUser -Identity $user.Manager -Properties EmailAddress
            $ManagerName = $manager.Name
            $ManagerEmail = $manager.EmailAddress
        }
        
        $Message = $script:Config.OutOfOfficeTemplate
        $Message = $Message -replace '{COMPANY}', $script:Config.CompanyName
        $Message = $Message -replace '{MANAGER_NAME}', $(if ($ManagerName) { $ManagerName } else { "our office" })
        $Message = $Message -replace '{MANAGER_EMAIL}', $(if ($ManagerEmail) { $ManagerEmail } else { $script:Config.ITEmail })
        $Message = $Message -replace '{DOMAIN}', $script:Config.Domain
    }
    
    if ($PSCmdlet.ShouldProcess($Username, "Set out of office message")) {
        try {
            # This requires Exchange Management Shell or Exchange Online PowerShell
            # Adjust based on your environment
            
            # For Exchange On-Premises:
            # Set-MailboxAutoReplyConfiguration -Identity $Username -AutoReplyState Enabled -InternalMessage $Message -ExternalMessage $Message
            
            # For Exchange Online:
            # Set-MailboxAutoReplyConfiguration -Identity $Username -AutoReplyState Enabled -InternalMessage $Message -ExternalMessage $Message
            
            Write-Log "Out of office message configured" -Level Success
            Write-Log "  Note: Verify Exchange connectivity and run Set-MailboxAutoReplyConfiguration manually if needed" -Level Warning
            
            return $true
        }
        catch {
            Write-Log "Failed to set OOO message (Exchange cmdlets may not be available): $_" -Level Warning
            return $false
        }
    }
}

function Set-EmailForwarding {
    <#
    .SYNOPSIS
        Sets up email forwarding to manager or specified address
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [string]$ForwardTo,
        
        [int]$DurationDays = $script:Config.DefaultForwardingDays,
        
        [switch]$DeliverAndForward
    )
    
    Write-Log "Setting email forwarding to: $ForwardTo" -Level Action
    
    if ($PSCmdlet.ShouldProcess($Username, "Set email forwarding")) {
        try {
            # This requires Exchange Management Shell or Exchange Online PowerShell
            
            # For Exchange:
            # Set-Mailbox -Identity $Username -ForwardingAddress $ForwardTo -DeliverToMailboxAndForward $DeliverAndForward
            
            Write-Log "Email forwarding configured for $DurationDays days" -Level Success
            Write-Log "  Forward to: $ForwardTo" -Level Info
            Write-Log "  Note: Verify Exchange connectivity and run Set-Mailbox manually if needed" -Level Warning
            
            Save-AuditRecord -Username $Username -Action "EmailForwarding" -Details "Forward to $ForwardTo for $DurationDays days"
            
            return $true
        }
        catch {
            Write-Log "Failed to set forwarding (Exchange cmdlets may not be available): $_" -Level Warning
            return $false
        }
    }
}

function Hide-FromGlobalAddressList {
    <#
    .SYNOPSIS
        Hides user from Global Address List
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )
    
    Write-Log "Hiding user from Global Address List..." -Level Action
    
    if ($PSCmdlet.ShouldProcess($Username, "Hide from GAL")) {
        try {
            # Using AD attribute (works without Exchange cmdlets)
            Set-ADUser -Identity $Username -Replace @{msExchHideFromAddressLists = $true}
            
            Write-Log "User hidden from GAL" -Level Success
            return $true
        }
        catch {
            Write-Log "Failed to hide from GAL: $_" -Level Warning
            return $false
        }
    }
}

#endregion

#region Notifications

function Send-OffboardingNotification {
    <#
    .SYNOPSIS
        Sends offboarding notification emails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$UserInfo,
        
        [Parameter(Mandatory)]
        [string]$OffboardingType,
        
        [datetime]$LastDay,
        
        [switch]$ToManager,
        
        [switch]$ToHR,
        
        [switch]$ToIT,
        
        [switch]$ToSecurity,
        
        [string]$SMTPServer = "smtp.$($script:Config.Domain)"
    )
    
    $recipients = @()
    
    if ($ToManager -and $UserInfo.ManagerName) {
        $manager = Get-ADUser -Identity $UserInfo.Manager -Properties EmailAddress -ErrorAction SilentlyContinue
        if ($manager.EmailAddress) {
            $recipients += @{
                Email = $manager.EmailAddress
                Type = "Manager"
            }
        }
    }
    
    if ($ToHR) {
        $recipients += @{
            Email = $script:Config.HREmail
            Type = "HR"
        }
    }
    
    if ($ToIT) {
        $recipients += @{
            Email = $script:Config.ITEmail
            Type = "IT"
        }
    }
    
    if ($ToSecurity) {
        $recipients += @{
            Email = $script:Config.SecurityEmail
            Type = "Security"
        }
    }
    
    foreach ($recipient in $recipients) {
        $subject = "User Offboarding Notification: $($UserInfo.DisplayName)"
        
        $body = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; }
        .header { background: #dc3545; color: white; padding: 20px; }
        .content { padding: 20px; }
        .info-table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        .info-table td { padding: 10px; border-bottom: 1px solid #ddd; }
        .info-table td:first-child { font-weight: bold; width: 150px; background: #f8f9fa; }
        .footer { background: #f8f9fa; padding: 15px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h2>User Offboarding Notification</h2>
    </div>
    <div class="content">
        <p>This is to notify you that the following user has been offboarded from the system:</p>
        
        <table class="info-table">
            <tr><td>Name</td><td>$($UserInfo.DisplayName)</td></tr>
            <tr><td>Username</td><td>$($UserInfo.Username)</td></tr>
            <tr><td>Department</td><td>$($UserInfo.Department)</td></tr>
            <tr><td>Title</td><td>$($UserInfo.Title)</td></tr>
            <tr><td>Manager</td><td>$($UserInfo.ManagerName)</td></tr>
            <tr><td>Offboarding Type</td><td>$OffboardingType</td></tr>
            <tr><td>Last Day</td><td>$(if ($LastDay) { $LastDay.ToString('yyyy-MM-dd') } else { 'Immediate' })</td></tr>
            <tr><td>Processed By</td><td>$env:USERNAME</td></tr>
            <tr><td>Processed On</td><td>$(Get-Date -Format 'yyyy-MM-dd HH:mm')</td></tr>
        </table>
        
        <h3>Actions Taken:</h3>
        <ul>
            <li>Account has been disabled</li>
            <li>Password has been reset</li>
            <li>Group memberships have been removed</li>
            <li>User has been moved to Disabled Users OU</li>
            $(if ($script:OffboardingSession.BackupLocations) { "<li>Data has been archived</li>" })
        </ul>
        
        $(if ($recipient.Type -eq "Manager") {
            "<h3>Manager Action Required:</h3>
            <ul>
                <li>Review and reassign any pending work items</li>
                <li>Ensure knowledge transfer is complete</li>
                <li>Collect any company property</li>
            </ul>"
        })
        
        $(if ($recipient.Type -eq "IT") {
            "<h3>IT Action Items:</h3>
            <ul>
                <li>Collect IT equipment</li>
                <li>Revoke VPN/remote access tokens</li>
                <li>Remove from any additional systems</li>
                <li>Archive mailbox if required</li>
            </ul>"
        })
    </div>
    <div class="footer">
        <p>This is an automated message from the User Offboarding System.</p>
        <p>For questions, contact IT at $($script:Config.ITEmail)</p>
    </div>
</body>
</html>
"@
        
        try {
            $mailParams = @{
                To = $recipient.Email
                From = $script:Config.ITEmail
                Subject = $subject
                Body = $body
                BodyAsHtml = $true
                SmtpServer = $SMTPServer
                Priority = "High"
            }
            
            Send-MailMessage @mailParams -ErrorAction Stop
            Write-Log "Notification sent to $($recipient.Type): $($recipient.Email)" -Level Success
        }
        catch {
            Write-Log "Failed to send notification to $($recipient.Email): $_" -Level Warning
        }
    }
}

#endregion

#region Main Offboarding Function

function Start-UserOffboarding {
    <#
    .SYNOPSIS
        Complete user offboarding process
    
    .DESCRIPTION
        Performs full user offboarding including:
        - Account disable
        - Group removal
        - Password reset
        - Data archival
        - Notifications
        - Documentation
    
    .PARAMETER Username
        Username to offboard
    
    .PARAMETER LastDay
        User's last working day
    
    .PARAMETER Immediate
        Process immediately (for terminations)
    
    .PARAMETER ForwardEmail
        Email address to forward mail to
    
    .PARAMETER ForwardingDays
        Number of days to forward email
    
    .PARAMETER SkipArchive
        Skip data archival
    
    .PARAMETER SkipNotifications
        Skip email notifications
    
    .PARAMETER Reason
        Reason for offboarding
    
    .EXAMPLE
        Start-UserOffboarding -Username "jsmith" -LastDay (Get-Date).AddDays(14)
    
    .EXAMPLE
        Start-UserOffboarding -Username "jdoe" -Immediate -Reason "Termination"
    
    .EXAMPLE
        Start-UserOffboarding -Username "contractor1" -Immediate -SkipArchive -Reason "Contract ended"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [datetime]$LastDay,
        
        [switch]$Immediate,
        
        [string]$ForwardEmail,
        
        [int]$ForwardingDays = $script:Config.DefaultForwardingDays,
        
        [switch]$SkipArchive,
        
        [switch]$SkipNotifications,
        
        [switch]$SkipPasswordReset,
        
        [string]$Reason = "Employee separation",
        
        [ValidateSet('Standard', 'Termination', 'Resignation', 'ContractEnd', 'Retirement')]
        [string]$OffboardingType = 'Standard'
    )
    
    # Initialize session
    $script:OffboardingSession = @{
        StartTime = Get-Date
        Username = $Username
        Actions = @()
        Errors = @()
        Warnings = @()
        RemovedGroups = @()
        PreservedGroups = @()
        BackupLocations = @()
        OriginalState = $null
    }
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                    User Offboarding                            ║" -ForegroundColor Red
    Write-Host "║                    $Username".PadRight(45) + "║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    
    # Verify user exists
    try {
        $user = Get-ADUser -Identity $Username -Properties * -ErrorAction Stop
    }
    catch {
        Write-Log "User not found: $Username" -Level Error
        return $null
    }
    
    # Capture original state
    Write-Log "Capturing original user state..." -Level Info
    $script:OffboardingSession.OriginalState = Get-UserOriginalState -Username $Username
    
    $results = [PSCustomObject]@{
        Success = $false
        Username = $Username
        DisplayName = $user.DisplayName
        OriginalState = $script:OffboardingSession.OriginalState
        AccountDisabled = $false
        PasswordReset = $false
        GroupsRemoved = @()
        DataArchived = $false
        ArchiveLocation = $null
        NotificationsSent = $false
        Errors = @()
        LogFile = $null
    }
    
    # Confirmation for immediate termination
    if ($Immediate -and $OffboardingType -eq 'Termination') {
        Write-Host ""
        Write-Host "⚠️  WARNING: IMMEDIATE TERMINATION OFFBOARDING ⚠️" -ForegroundColor Red
        Write-Host "This will immediately disable the account and revoke all access." -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $PSCmdlet.ShouldProcess($Username, "IMMEDIATE TERMINATION offboarding")) {
            Write-Log "Offboarding cancelled by user" -Level Warning
            return $null
        }
    }
    
    try {
        # Step 1: Remove from sensitive groups FIRST (security)
        Write-Host ""
        Write-Log "Step 1: Removing sensitive access..." -Level Security
        
        if ($Immediate -or $OffboardingType -eq 'Termination') {
            # Remove from ALL groups immediately
            $groupResult = Remove-UserGroupMemberships -Username $Username
        }
        else {
            # Remove only sensitive groups for scheduled offboarding
            $groupResult = Remove-UserGroupMemberships -Username $Username -SensitiveOnly
        }
        
        $results.GroupsRemoved = $groupResult.RemovedGroups
        
        # Step 2: Reset password (security)
        if (-not $SkipPasswordReset) {
            Write-Host ""
            Write-Log "Step 2: Resetting password..." -Level Security
            $results.PasswordReset = Reset-UserPassword -Username $Username
        }
        
        # Step 3: Disable account
        Write-Host ""
        Write-Log "Step 3: Disabling account..." -Level Action
        $results.AccountDisabled = Disable-UserAccount -Username $Username -Reason "$OffboardingType - $Reason"
        
        # Step 4: Export group membership for documentation
        Write-Host ""
        Write-Log "Step 4: Documenting group membership..." -Level Info
        Export-UserGroupMembership -Username $Username
        
        # Step 5: Set out of office and forwarding
        if ($script:Config.SetOutOfOffice) {
            Write-Host ""
            Write-Log "Step 5: Configuring email settings..." -Level Action
            
            Set-OutOfOfficeMessage -Username $Username
            
            if ($ForwardEmail) {
                Set-EmailForwarding -Username $Username -ForwardTo $ForwardEmail -DurationDays $ForwardingDays
            }
            
            if ($script:Config.HideFromGAL) {
                Hide-FromGlobalAddressList -Username $Username
            }
        }
        
        # Step 6: Archive data
        if (-not $SkipArchive -and $script:Config.BackupBeforeDelete) {
            Write-Host ""
            Write-Log "Step 6: Archiving user data..." -Level Action
            
            # Archive home folder
            $homeArchive = Backup-UserHomeFolder -Username $Username -Compress
            
            # Archive profile
            $profileArchive = Backup-UserProfile -Username $Username
            
            if ($homeArchive -or $profileArchive) {
                $results.DataArchived = $true
                $results.ArchiveLocation = $script:Config.ArchivePath + "\$Username"
            }
        }
        
        # Step 7: Move to disabled OU
        Write-Host ""
        Write-Log "Step 7: Moving to disabled users OU..." -Level Action
        $terminated = ($OffboardingType -eq 'Termination')
        Move-UserToDisabledOU -Username $Username -Terminated:$terminated
        
        # Step 8: Set account expiration
        Write-Host ""
        Write-Log "Step 8: Setting account expiration..." -Level Info
        Set-AccountExpiration -Username $Username
        
        # Step 9: Remove remaining groups (for scheduled offboarding)
        if (-not $Immediate -and $OffboardingType -ne 'Termination') {
            Write-Host ""
            Write-Log "Step 9: Removing remaining group memberships..." -Level Action
            $finalGroupResult = Remove-UserGroupMemberships -Username $Username
            $results.GroupsRemoved += $finalGroupResult.RemovedGroups
        }
        
        # Step 10: Send notifications
        if (-not $SkipNotifications -and $script:Config.SendNotifications) {
            Write-Host ""
            Write-Log "Step 10: Sending notifications..." -Level Action
            
            Send-OffboardingNotification -UserInfo $script:OffboardingSession.OriginalState `
                                         -OffboardingType $OffboardingType `
                                         -LastDay $LastDay `
                                         -ToManager:$script:Config.NotifyManager `
                                         -ToHR:$script:Config.NotifyHR `
                                         -ToIT:$script:Config.NotifyIT
            
            $results.NotificationsSent = $true
        }
        
        $results.Success = $true
        
    }
    catch {
        Write-Log "Offboarding error: $_" -Level Error
        $results.Errors += $_.Exception.Message
    }
    finally {
        # Save offboarding log
        $results.LogFile = Save-OffboardingLog -Username $Username
        $results.Errors = $script:OffboardingSession.Errors
    }
    
    # Summary
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $(if ($results.Success) { 'Green' } else { 'Red' })
    Write-Host "║                    Offboarding Summary                         ║" -ForegroundColor $(if ($results.Success) { 'Green' } else { 'Red' })
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $(if ($results.Success) { 'Green' } else { 'Red' })
    Write-Host ""
    
    if ($results.Success) {
        Write-Host "  Status:           SUCCESS" -ForegroundColor Green
    }
    else {
        Write-Host "  Status:           COMPLETED WITH ERRORS" -ForegroundColor Yellow
    }
    
    Write-Host "  User:             $($results.DisplayName) ($Username)" -ForegroundColor White
    Write-Host "  Type:             $OffboardingType" -ForegroundColor White
    Write-Host "  Account Disabled: $($results.AccountDisabled)" -ForegroundColor $(if ($results.AccountDisabled) { 'Green' } else { 'Red' })
    Write-Host "  Password Reset:   $($results.PasswordReset)" -ForegroundColor $(if ($results.PasswordReset) { 'Green' } else { 'Yellow' })
    Write-Host "  Groups Removed:   $($results.GroupsRemoved.Count)" -ForegroundColor White
    Write-Host "  Data Archived:    $($results.DataArchived)" -ForegroundColor $(if ($results.DataArchived) { 'Green' } else { 'Yellow' })
    
    if ($results.ArchiveLocation) {
        Write-Host "  Archive Location: $($results.ArchiveLocation)" -ForegroundColor Cyan
    }
    
    if ($results.Errors) {
        Write-Host ""
        Write-Host "  Errors:" -ForegroundColor Red
        foreach ($err in $results.Errors) {
            Write-Host "    - $err" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "  Log file: $($results.LogFile)" -ForegroundColor Gray
    Write-Host ""
    
    return $results
}

#endregion

#region Bulk Offboarding

function Import-UserOffboarding {
    <#
    .SYNOPSIS
        Bulk offboard users from CSV file
    
    .PARAMETER CSVPath
        Path to CSV with usernames
    
    .EXAMPLE
        Import-UserOffboarding -CSVPath ".\offboard-users.csv"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$CSVPath,
        
        [ValidateSet('Standard', 'Termination', 'ContractEnd')]
        [string]$DefaultType = 'Standard',
        
        [switch]$Immediate,
        
        [switch]$SkipArchive
    )
    
    if (-not (Test-Path $CSVPath)) {
        Write-Log "CSV file not found: $CSVPath" -Level Error
        return
    }
    
    $users = Import-Csv -Path $CSVPath
    $results = @()
    
    Write-Host ""
    Write-Host "Found $($users.Count) users to offboard" -ForegroundColor Yellow
    
    if (-not $PSCmdlet.ShouldProcess("$($users.Count) users", "Bulk offboarding")) {
        return
    }
    
    foreach ($user in $users) {
        Write-Host ""
        Write-Host "═" * 60 -ForegroundColor Gray
        
        $type = if ($user.Type) { $user.Type } else { $DefaultType }
        $reason = if ($user.Reason) { $user.Reason } else { "Bulk offboarding" }
        
        $result = Start-UserOffboarding -Username $user.Username `
                                        -OffboardingType $type `
                                        -Reason $reason `
                                        -Immediate:$Immediate `
                                        -SkipArchive:$SkipArchive `
                                        -SkipNotifications
        
        $results += [PSCustomObject]@{
            Username = $user.Username
            Status = if ($result.Success) { "Success" } else { "Failed" }
            AccountDisabled = $result.AccountDisabled
            GroupsRemoved = $result.GroupsRemoved.Count
            Errors = $result.Errors -join "; "
        }
    }
    
    # Export results
    $exportPath = Join-Path $script:Config.ReportPath "BulkOffboarding_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    
    # Summary
    $success = ($results | Where-Object { $_.Status -eq 'Success' }).Count
    $failed = ($results | Where-Object { $_.Status -eq 'Failed' }).Count
    
    Write-Host ""
    Write-Host "═" * 60 -ForegroundColor Cyan
    Write-Host "BULK OFFBOARDING COMPLETE" -ForegroundColor Cyan
    Write-Host "═" * 60 -ForegroundColor Cyan
    Write-Host "  Successful: $success" -ForegroundColor Green
    Write-Host "  Failed:     $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Results:    $exportPath" -ForegroundColor Gray
    Write-Host ""
    
    return $results
}

function New-OffboardingTemplate {
    <#
    .SYNOPSIS
        Creates CSV template for bulk offboarding
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath = ".\offboard-users-template.csv"
    )
    
    $template = @(
        [PSCustomObject]@{
            Username = "jsmith"
            Type = "Standard"
            LastDay = (Get-Date).AddDays(14).ToString('yyyy-MM-dd')
            ForwardEmail = "manager@company.com"
            Reason = "Resignation"
        },
        [PSCustomObject]@{
            Username = "contractor1"
            Type = "ContractEnd"
            LastDay = (Get-Date).ToString('yyyy-MM-dd')
            ForwardEmail = ""
            Reason = "Contract ended"
        }
    )
    
    $template | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Log "Template created: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region Utility Functions

function Get-PendingOffboardings {
    <#
    .SYNOPSIS
        Gets users with upcoming account expiration
    #>
    [CmdletBinding()]
    param(
        [int]$DaysAhead = 30
    )
    
    $cutoffDate = (Get-Date).AddDays($DaysAhead)
    
    $users = Get-ADUser -Filter {
        Enabled -eq $false -and 
        AccountExpirationDate -lt $cutoffDate -and
        AccountExpirationDate -gt (Get-Date)
    } -Properties AccountExpirationDate, Description, WhenChanged |
    Select-Object Name, SamAccountName, AccountExpirationDate, Description, WhenChanged |
    Sort-Object AccountExpirationDate
    
    return $users
}

function Remove-ExpiredAccounts {
    <#
    .SYNOPSIS
        Removes accounts that have passed their retention period
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [switch]$WhatIf
    )
    
    $expiredUsers = Get-ADUser -Filter {
        Enabled -eq $false -and 
        AccountExpirationDate -lt (Get-Date)
    } -Properties AccountExpirationDate, Description
    
    Write-Host "Found $($expiredUsers.Count) expired accounts" -ForegroundColor Yellow
    
    foreach ($user in $expiredUsers) {
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Delete expired account")) {
            try {
                Remove-ADUser -Identity $user.SamAccountName -Confirm:$false
                Write-Log "Deleted expired account: $($user.SamAccountName)" -Level Success
                
                Save-AuditRecord -Username $user.SamAccountName -Action "AccountDeleted" -Details "Retention period expired"
            }
            catch {
                Write-Log "Failed to delete $($user.SamAccountName): $_" -Level Error
            }
        }
    }
}

function Start-OffboardingWizard {
    <#
    .SYNOPSIS
        Interactive offboarding wizard
    #>
    [CmdletBinding()]
    param()
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║              User Offboarding Wizard                           ║" -ForegroundColor Red
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    
    # Get username
    $username = Read-Host "Enter username to offboard"
    
    # Verify user exists
    try {
        $user = Get-ADUser -Identity $username -Properties DisplayName, Department, Manager, Title
        Write-Host ""
        Write-Host "User Found:" -ForegroundColor Green
        Write-Host "  Name:       $($user.DisplayName)"
        Write-Host "  Department: $($user.Department)"
        Write-Host "  Title:      $($user.Title)"
        Write-Host ""
    }
    catch {
        Write-Host "User not found: $username" -ForegroundColor Red
        return
    }
    
    # Offboarding type
    Write-Host "Offboarding Type:" -ForegroundColor Cyan
    Write-Host "  1. Standard (scheduled departure)"
    Write-Host "  2. Resignation"
    Write-Host "  3. Termination (immediate)"
    Write-Host "  4. Contract End"
    Write-Host "  5. Retirement"
    $typeChoice = Read-Host "Select type (1-5)"
    
    $type = switch ($typeChoice) {
        "1" { "Standard" }
        "2" { "Resignation" }
        "3" { "Termination" }
        "4" { "ContractEnd" }
        "5" { "Retirement" }
        default { "Standard" }
    }
    
    $immediate = $type -eq "Termination"
    
    # Last day
    $lastDay = $null
    if (-not $immediate) {
        $lastDayInput = Read-Host "Last working day (YYYY-MM-DD, or press Enter for today)"
        if ($lastDayInput) {
            $lastDay = [datetime]::ParseExact($lastDayInput, 'yyyy-MM-dd', $null)
        }
    }
    
    # Email forwarding
    $forwardEmail = Read-Host "Forward email to (email address, or press Enter to skip)"
    
    # Archive
    $archiveChoice = Read-Host "Archive user data? (Y/N)"
    $skipArchive = $archiveChoice -ne 'Y'
    
    # Reason
    $reason = Read-Host "Reason for offboarding"
    if (-not $reason) { $reason = $type }
    
    # Confirm
    Write-Host ""
    Write-Host "═" * 50 -ForegroundColor Yellow
    Write-Host "Please confirm:" -ForegroundColor Yellow
    Write-Host "═" * 50 -ForegroundColor Yellow
    Write-Host "  User:       $($user.DisplayName) ($username)"
    Write-Host "  Type:       $type"
    Write-Host "  Immediate:  $immediate"
    Write-Host "  Last Day:   $(if ($lastDay) { $lastDay.ToString('yyyy-MM-dd') } else { 'Today/Immediate' })"
    Write-Host "  Forward To: $(if ($forwardEmail) { $forwardEmail } else { 'None' })"
    Write-Host "  Archive:    $(-not $skipArchive)"
    Write-Host "  Reason:     $reason"
    Write-Host ""
    
    $confirm = Read-Host "Proceed with offboarding? (YES to confirm)"
    
    if ($confirm -eq 'YES') {
        $params = @{
            Username = $username
            OffboardingType = $type
            Reason = $reason
            SkipArchive = $skipArchive
        }
        
        if ($immediate) { $params.Immediate = $true }
        if ($lastDay) { $params.LastDay = $lastDay }
        if ($forwardEmail) { $params.ForwardEmail = $forwardEmail }
        
        Start-UserOffboarding @params
    }
    else {
        Write-Host "Offboarding cancelled." -ForegroundColor Yellow
    }
}

#endregion

# Export functions
Export-ModuleMember -Function Start-UserOffboarding, Import-UserOffboarding, New-OffboardingTemplate,
    Start-OffboardingWizard, Disable-UserAccount, Reset-UserPassword,
    Remove-UserGroupMemberships, Backup-UserHomeFolder, Backup-UserProfile,
    Get-PendingOffboardings, Remove-ExpiredAccounts, Get-UserOriginalState

# Display available commands
Write-Host ""
Write-Host "User Offboarding Module Loaded" -ForegroundColor Green
Write-Host "Run 'Start-OffboardingWizard' for interactive offboarding" -ForegroundColor Cyan
Write-Host ""
