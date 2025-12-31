# Active Directory User Management Toolkit
# Author: [Your Name]
# Description: Collection of PowerShell scripts for common AD administration tasks

#Requires -Modules ActiveDirectory

# ============================================================================
# Script 1: Create New AD User with Standard Configuration
# ============================================================================

function New-StandardADUser {
    <#
    .SYNOPSIS
        Creates a new Active Directory user with standard organizational settings
    .DESCRIPTION
        Creates AD user account with proper naming convention, organizational unit placement,
        and group memberships based on department
    .EXAMPLE
        New-StandardADUser -FirstName "John" -LastName "Doe" -Department "IT" -Title "Systems Administrator"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FirstName,
        
        [Parameter(Mandatory=$true)]
        [string]$LastName,
        
        [Parameter(Mandatory=$true)]
        [string]$Department,
        
        [Parameter(Mandatory=$true)]
        [string]$Title,
        
        [Parameter(Mandatory=$false)]
        [string]$OUPath = "OU=Users,DC=company,DC=com",
        
        [Parameter(Mandatory=$false)]
        [string]$Password = $null
    )
    
    try {
        # Generate username (first initial + last name)
        $Username = ($FirstName.Substring(0,1) + $LastName).ToLower()
        $DisplayName = "$FirstName $LastName"
        $Email = "$Username@company.com"
        
        # Generate secure password if not provided
        if ([string]::IsNullOrEmpty($Password)) {
            Add-Type -AssemblyName System.Web
            $Password = [System.Web.Security.Membership]::GeneratePassword(12,2)
        }
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        
        # Create the user
        New-ADUser -Name $DisplayName `
                   -GivenName $FirstName `
                   -Surname $LastName `
                   -SamAccountName $Username `
                   -UserPrincipalName "$Username@company.com" `
                   -EmailAddress $Email `
                   -Title $Title `
                   -Department $Department `
                   -Path $OUPath `
                   -AccountPassword $SecurePassword `
                   -Enabled $true `
                   -ChangePasswordAtLogon $true
        
        Write-Host "Successfully created user: $Username" -ForegroundColor Green
        Write-Host "Temporary Password: $Password" -ForegroundColor Yellow
        Write-Host "User must change password at next logon" -ForegroundColor Yellow
        
        # Add to department-specific groups
        $DeptGroup = "GRP_$Department"
        if (Get-ADGroup -Filter "Name -eq '$DeptGroup'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $DeptGroup -Members $Username
            Write-Host "Added to group: $DeptGroup" -ForegroundColor Green
        }
        
        return @{
            Username = $Username
            Password = $Password
            Email = $Email
            Success = $true
        }
    }
    catch {
        Write-Host "Error creating user: $_" -ForegroundColor Red
        return @{Success = $false; Error = $_.Exception.Message}
    }
}

# ============================================================================
# Script 2: Bulk User Creation from CSV
# ============================================================================

function Import-ADUsersFromCSV {
    <#
    .SYNOPSIS
        Creates multiple AD users from a CSV file
    .DESCRIPTION
        Reads CSV with columns: FirstName, LastName, Department, Title
        Creates users with standard configuration
    .EXAMPLE
        Import-ADUsersFromCSV -CSVPath "C:\users\newusers.csv"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CSVPath,
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath = "C:\Logs\AD_UserCreation.log"
    )
    
    if (-not (Test-Path $CSVPath)) {
        Write-Host "CSV file not found: $CSVPath" -ForegroundColor Red
        return
    }
    
    $Users = Import-Csv -Path $CSVPath
    $Results = @()
    
    foreach ($User in $Users) {
        Write-Host "`nProcessing: $($User.FirstName) $($User.LastName)" -ForegroundColor Cyan
        
        $Result = New-StandardADUser -FirstName $User.FirstName `
                                      -LastName $User.LastName `
                                      -Department $User.Department `
                                      -Title $User.Title
        
        $Results += [PSCustomObject]@{
            Name = "$($User.FirstName) $($User.LastName)"
            Username = $Result.Username
            Password = $Result.Password
            Success = $Result.Success
            Error = $Result.Error
        }
    }
    
    # Export results
    $Results | Export-Csv -Path $LogPath -NoTypeInformation
    Write-Host "`nResults exported to: $LogPath" -ForegroundColor Green
    
    return $Results
}

# ============================================================================
# Script 3: AD User Management - Disable/Enable/Remove
# ============================================================================

function Set-ADUserStatus {
    <#
    .SYNOPSIS
        Manages AD user account status (disable, enable, or remove)
    .EXAMPLE
        Set-ADUserStatus -Username "jdoe" -Action Disable
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Disable","Enable","Remove")]
        [string]$Action
    )
    
    try {
        $User = Get-ADUser -Identity $Username -ErrorAction Stop
        
        switch ($Action) {
            "Disable" {
                Disable-ADAccount -Identity $Username
                # Move to disabled OU
                $DisabledOU = "OU=Disabled,OU=Users,DC=company,DC=com"
                if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$DisabledOU'" -ErrorAction SilentlyContinue) {
                    Move-ADObject -Identity $User.DistinguishedName -TargetPath $DisabledOU
                }
                Write-Host "User $Username has been disabled and moved to Disabled OU" -ForegroundColor Yellow
            }
            "Enable" {
                Enable-ADAccount -Identity $Username
                Write-Host "User $Username has been enabled" -ForegroundColor Green
            }
            "Remove" {
                $Confirm = Read-Host "Are you sure you want to DELETE user $Username? (yes/no)"
                if ($Confirm -eq "yes") {
                    Remove-ADUser -Identity $Username -Confirm:$false
                    Write-Host "User $Username has been removed" -ForegroundColor Red
                } else {
                    Write-Host "Removal cancelled" -ForegroundColor Yellow
                }
            }
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# ============================================================================
# Script 4: AD Group Management
# ============================================================================

function Add-ADUserToGroups {
    <#
    .SYNOPSIS
        Adds a user to multiple AD groups
    .EXAMPLE
        Add-ADUserToGroups -Username "jdoe" -Groups @("GRP_IT","GRP_VPN_Access","GRP_Printers")
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string[]]$Groups
    )
    
    try {
        $User = Get-ADUser -Identity $Username -ErrorAction Stop
        
        foreach ($Group in $Groups) {
            try {
                Add-ADGroupMember -Identity $Group -Members $Username -ErrorAction Stop
                Write-Host "Added $Username to $Group" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to add to $Group : $_" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "User not found: $Username" -ForegroundColor Red
    }
}

function Get-ADUserGroupMembership {
    <#
    .SYNOPSIS
        Lists all groups a user belongs to
    .EXAMPLE
        Get-ADUserGroupMembership -Username "jdoe"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username
    )
    
    try {
        $Groups = Get-ADPrincipalGroupMembership -Identity $Username | Select-Object Name, GroupCategory
        
        Write-Host "`nGroup Memberships for $Username :" -ForegroundColor Cyan
        $Groups | Format-Table -AutoSize
        
        return $Groups
    }
    catch {
        Write-Host "Error retrieving group membership: $_" -ForegroundColor Red
    }
}

# ============================================================================
# Script 5: Password Reset
# ============================================================================

function Reset-ADUserPassword {
    <#
    .SYNOPSIS
        Resets user password and forces change at next logon
    .EXAMPLE
        Reset-ADUserPassword -Username "jdoe"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$false)]
        [string]$NewPassword = $null
    )
    
    try {
        # Generate secure password if not provided
        if ([string]::IsNullOrEmpty($NewPassword)) {
            Add-Type -AssemblyName System.Web
            $NewPassword = [System.Web.Security.Membership]::GeneratePassword(12,2)
        }
        
        $SecurePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
        
        Set-ADAccountPassword -Identity $Username -NewPassword $SecurePassword -Reset
        Set-ADUser -Identity $Username -ChangePasswordAtLogon $true
        
        Write-Host "`nPassword reset successful for: $Username" -ForegroundColor Green
        Write-Host "New temporary password: $NewPassword" -ForegroundColor Yellow
        Write-Host "User must change password at next logon" -ForegroundColor Yellow
        
        return $NewPassword
    }
    catch {
        Write-Host "Error resetting password: $_" -ForegroundColor Red
    }
}

# ============================================================================
# Script 6: User Account Information Report
# ============================================================================

function Get-ADUserReport {
    <#
    .SYNOPSIS
        Generates detailed report for an AD user
    .EXAMPLE
        Get-ADUserReport -Username "jdoe"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username
    )
    
    try {
        $User = Get-ADUser -Identity $Username -Properties * -ErrorAction Stop
        
        $Report = [PSCustomObject]@{
            Username = $User.SamAccountName
            DisplayName = $User.DisplayName
            Email = $User.EmailAddress
            Department = $User.Department
            Title = $User.Title
            Enabled = $User.Enabled
            LockedOut = $User.LockedOut
            PasswordExpired = $User.PasswordExpired
            PasswordLastSet = $User.PasswordLastSet
            LastLogon = [DateTime]::FromFileTime($User.LastLogon)
            Created = $User.Created
            Modified = $User.Modified
            OU = $User.DistinguishedName.Split(',',2)[1]
        }
        
        Write-Host "`nUser Account Report for: $Username" -ForegroundColor Cyan
        $Report | Format-List
        
        return $Report
    }
    catch {
        Write-Host "Error retrieving user information: $_" -ForegroundColor Red
    }
}

# ============================================================================
# Example Usage
# ============================================================================

<#
# Create a single user
New-StandardADUser -FirstName "John" -LastName "Doe" -Department "IT" -Title "Systems Administrator"

# Import multiple users from CSV
Import-ADUsersFromCSV -CSVPath "C:\users\newusers.csv"


# Disable a user account
Set-ADUserStatus -Username "jdoe" -Action Disable

# Add user to groups
Add-ADUserToGroups -Username "jdoe" -Groups @("GRP_IT","GRP_VPN_Access")

# View user's groups
Get-ADUserGroupMembership -Username "jdoe"

# Reset password
Reset-ADUserPassword -Username "jdoe"

# Get user report
Get-ADUserReport -Username "jdoe"
#>
