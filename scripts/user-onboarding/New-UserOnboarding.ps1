<#
.SYNOPSIS
    Comprehensive User Onboarding Automation Script
    
.DESCRIPTION
    Complete user onboarding solution including:
    - Active Directory user creation
    - Email/Microsoft 365 provisioning
    - Group membership assignment
    - Home folder and profile creation
    - Security permissions configuration
    - Welcome email generation
    - Hardware/software request initiation
    - Documentation and audit logging
    
.PARAMETER FirstName
    User's first name

.PARAMETER LastName
    User's last name

.PARAMETER Department
    Department the user belongs to

.PARAMETER Title
    Job title

.PARAMETER Manager
    Manager's username or DN

.PARAMETER Template
    Onboarding template to use

.EXAMPLE
    New-UserOnboarding -FirstName "John" -LastName "Smith" -Department "IT" -Title "Systems Administrator"
    
.EXAMPLE
    Import-UserOnboarding -CSVPath ".\new-hires.csv"

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
    
    # Default OU paths (customize for your environment)
    OUPaths = @{
        Users = "OU=Users,OU=Corp"
        IT = "OU=IT,OU=Users,OU=Corp"
        HR = "OU=HR,OU=Users,OU=Corp"
        Finance = "OU=Finance,OU=Users,OU=Corp"
        Sales = "OU=Sales,OU=Users,OU=Corp"
        Marketing = "OU=Marketing,OU=Users,OU=Corp"
        Operations = "OU=Operations,OU=Users,OU=Corp"
        Engineering = "OU=Engineering,OU=Users,OU=Corp"
        Executive = "OU=Executive,OU=Users,OU=Corp"
        Contractors = "OU=Contractors,OU=Users,OU=Corp"
    }
    
    # Username format: FirstInitialLastName, FirstName.LastName, etc.
    UsernameFormat = "FirstInitialLastName"  # Options: FirstInitialLastName, FirstName.LastName, FirstNameLastInitial
    
    # Email domain
    EmailDomain = "company.com"
    
    # Password settings
    PasswordLength = 16
    RequirePasswordChange = $true
    
    # Home folder settings
    HomeFolderRoot = "\\fileserver\users$"
    CreateHomeFolder = $true
    HomeFolderQuotaMB = 5120  # 5GB
    
    # Profile settings
    ProfilePath = "\\fileserver\profiles$"
    CreateRoamingProfile = $false
    
    # Default groups for all users
    DefaultGroups = @(
        "Domain Users",
        "All-Staff",
        "WiFi-Users"
    )
    
    # Department-specific groups
    DepartmentGroups = @{
        IT = @("IT-Staff", "VPN-Users", "Admin-Tools-Access")
        HR = @("HR-Staff", "Confidential-Access")
        Finance = @("Finance-Staff", "Financial-Systems-Access")
        Sales = @("Sales-Staff", "CRM-Users")
        Marketing = @("Marketing-Staff", "Social-Media-Access")
        Operations = @("Operations-Staff")
        Engineering = @("Engineering-Staff", "Dev-Tools-Access", "VPN-Users")
        Executive = @("Executive-Staff", "All-Access")
        Contractors = @("Contractor-Access")
    }
    
    # License groups for M365 (if using group-based licensing)
    LicenseGroups = @{
        Standard = "M365-E3-License"
        Premium = "M365-E5-License"
        BasicOnly = "M365-F3-License"
    }
    
    # Welcome email settings
    SendWelcomeEmail = $true
    WelcomeEmailTemplate = ".\templates\welcome-email.html"
    ITSupportEmail = "helpdesk@company.com"
    HREmail = "hr@company.com"
    
    # Logging
    LogPath = ".\logs\onboarding"
    AuditLogPath = ".\logs\audit"
    
    # Ticket system integration (customize as needed)
    CreateTicket = $false
    TicketSystemAPI = "https://tickets.company.com/api"
    
    # Report path
    ReportPath = ".\reports\onboarding"
}

# Onboarding templates for different user types
$script:OnboardingTemplates = @{
    Standard = @{
        AccountExpires = $null
        PasswordNeverExpires = $false
        HomeFolder = $true
        Groups = @()
        LicenseType = "Standard"
        VPNAccess = $false
    }
    Contractor = @{
        AccountExpires = (Get-Date).AddDays(90)
        PasswordNeverExpires = $false
        HomeFolder = $false
        Groups = @("Contractor-Access")
        LicenseType = "BasicOnly"
        VPNAccess = $false
    }
    Executive = @{
        AccountExpires = $null
        PasswordNeverExpires = $false
        HomeFolder = $true
        Groups = @("Executive-Staff", "VPN-Users")
        LicenseType = "Premium"
        VPNAccess = $true
    }
    Intern = @{
        AccountExpires = (Get-Date).AddDays(120)
        PasswordNeverExpires = $false
        HomeFolder = $false
        Groups = @("Intern-Access")
        LicenseType = "BasicOnly"
        VPNAccess = $false
    }
    ITAdmin = @{
        AccountExpires = $null
        PasswordNeverExpires = $false
        HomeFolder = $true
        Groups = @("IT-Staff", "VPN-Users", "Admin-Tools-Access", "Server-Admins")
        LicenseType = "Premium"
        VPNAccess = $true
    }
}

# Session tracking
$script:OnboardingSession = @{
    StartTime = $null
    User = $null
    Actions = @()
    Errors = @()
    Warnings = @()
}

#endregion

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Action', 'Debug')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Action' = 'Magenta'
        'Debug' = 'Gray'
    }
    $prefixes = @{
        'Info' = '[*]'
        'Warning' = '[!]'
        'Error' = '[X]'
        'Success' = '[✓]'
        'Action' = '[>]'
        'Debug' = '[D]'
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "$timestamp $($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
    
    # Add to session log
    $script:OnboardingSession.Actions += [PSCustomObject]@{
        Timestamp = Get-Date
        Level = $Level
        Message = $Message
    }
    
    if ($Level -eq 'Error') {
        $script:OnboardingSession.Errors += $Message
    }
    elseif ($Level -eq 'Warning') {
        $script:OnboardingSession.Warnings += $Message
    }
}

function Save-OnboardingLog {
    param(
        [string]$Username,
        [string]$OutputPath
    )
    
    if (-not (Test-Path $script:Config.LogPath)) {
        New-Item -Path $script:Config.LogPath -ItemType Directory -Force | Out-Null
    }
    
    if (-not $OutputPath) {
        $OutputPath = Join-Path $script:Config.LogPath "Onboarding_$($Username)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
    
    $logContent = @"
========================================
USER ONBOARDING LOG
========================================
Username: $Username
Start Time: $($script:OnboardingSession.StartTime)
End Time: $(Get-Date)
Performed By: $env:USERNAME
Computer: $env:COMPUTERNAME

ACTIONS TAKEN:
----------------------------------------
"@
    
    foreach ($action in $script:OnboardingSession.Actions) {
        $logContent += "`n$($action.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) [$($action.Level)] $($action.Message)"
    }
    
    if ($script:OnboardingSession.Errors) {
        $logContent += "`n`nERRORS:`n----------------------------------------"
        foreach ($error in $script:OnboardingSession.Errors) {
            $logContent += "`n- $error"
        }
    }
    
    if ($script:OnboardingSession.Warnings) {
        $logContent += "`n`nWARNINGS:`n----------------------------------------"
        foreach ($warning in $script:OnboardingSession.Warnings) {
            $logContent += "`n- $warning"
        }
    }
    
    $logContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Onboarding log saved to: $OutputPath" -Level Info
    
    return $OutputPath
}

function New-SecurePassword {
    param(
        [int]$Length = 16,
        [switch]$ExcludeAmbiguous
    )
    
    $lowercase = 'abcdefghijkmnopqrstuvwxyz'
    $uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $numbers = '23456789'
    $special = '!@#$%&*?'
    
    if (-not $ExcludeAmbiguous) {
        $lowercase += 'l'
        $uppercase += 'IO'
        $numbers += '01'
    }
    
    $allChars = $lowercase + $uppercase + $numbers + $special
    
    # Ensure at least one of each type
    $password = @(
        $lowercase[(Get-Random -Maximum $lowercase.Length)]
        $uppercase[(Get-Random -Maximum $uppercase.Length)]
        $numbers[(Get-Random -Maximum $numbers.Length)]
        $special[(Get-Random -Maximum $special.Length)]
    )
    
    # Fill remaining length
    for ($i = 4; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle
    $password = ($password | Sort-Object { Get-Random }) -join ''
    
    return $password
}

function Get-NextAvailableUsername {
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$Format = $script:Config.UsernameFormat
    )
    
    $firstName = $FirstName.Trim() -replace '[^a-zA-Z]', ''
    $lastName = $LastName.Trim() -replace '[^a-zA-Z]', ''
    
    $baseUsername = switch ($Format) {
        "FirstInitialLastName" { 
            "$($firstName.Substring(0,1).ToLower())$($lastName.ToLower())"
        }
        "FirstName.LastName" { 
            "$($firstName.ToLower()).$($lastName.ToLower())"
        }
        "FirstNameLastInitial" { 
            "$($firstName.ToLower())$($lastName.Substring(0,1).ToLower())"
        }
        default { 
            "$($firstName.Substring(0,1).ToLower())$($lastName.ToLower())"
        }
    }
    
    # Truncate if too long (SAMAccountName max is 20 chars)
    if ($baseUsername.Length -gt 20) {
        $baseUsername = $baseUsername.Substring(0, 20)
    }
    
    $username = $baseUsername
    $counter = 1
    
    # Check if username exists, append number if needed
    while (Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue) {
        $suffix = $counter.ToString()
        $maxBase = 20 - $suffix.Length
        
        if ($baseUsername.Length -gt $maxBase) {
            $username = $baseUsername.Substring(0, $maxBase) + $suffix
        }
        else {
            $username = $baseUsername + $suffix
        }
        
        $counter++
        
        if ($counter -gt 99) {
            throw "Could not generate unique username for $FirstName $LastName"
        }
    }
    
    return $username
}

function Get-UserOU {
    param(
        [string]$Department,
        [string]$UserType = "Standard"
    )
    
    $baseDN = $script:Config.DomainDN
    
    # Check for contractor/special types first
    if ($UserType -eq "Contractor") {
        $ouPath = $script:Config.OUPaths["Contractors"]
    }
    elseif ($script:Config.OUPaths.ContainsKey($Department)) {
        $ouPath = $script:Config.OUPaths[$Department]
    }
    else {
        $ouPath = $script:Config.OUPaths["Users"]
    }
    
    return "$ouPath,$baseDN"
}

#endregion

#region User Creation

function New-ADUserAccount {
    <#
    .SYNOPSIS
        Creates a new Active Directory user account
    
    .PARAMETER FirstName
        User's first name
    
    .PARAMETER LastName
        User's last name
    
    .PARAMETER Department
        Department name
    
    .PARAMETER Title
        Job title
    
    .PARAMETER Manager
        Manager's username
    
    .PARAMETER EmployeeID
        Employee ID number
    
    .PARAMETER StartDate
        Employment start date
    
    .PARAMETER Template
        Onboarding template to use
    
    .EXAMPLE
        New-ADUserAccount -FirstName "John" -LastName "Smith" -Department "IT" -Title "Help Desk Analyst"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FirstName,
        
        [Parameter(Mandatory)]
        [string]$LastName,
        
        [Parameter(Mandatory)]
        [string]$Department,
        
        [Parameter(Mandatory)]
        [string]$Title,
        
        [string]$Manager,
        
        [string]$EmployeeID,
        
        [string]$Phone,
        
        [string]$Mobile,
        
        [string]$Office,
        
        [string]$Company = "Company Name",
        
        [string]$StreetAddress,
        
        [string]$City,
        
        [string]$State,
        
        [string]$PostalCode,
        
        [string]$Country = "US",
        
        [datetime]$StartDate = (Get-Date),
        
        [ValidateSet('Standard', 'Contractor', 'Executive', 'Intern', 'ITAdmin')]
        [string]$Template = "Standard",
        
        [string]$CustomOU,
        
        [switch]$Enabled
    )
    
    Write-Log "Creating AD user account for $FirstName $LastName" -Level Action
    
    # Get template settings
    $templateSettings = $script:OnboardingTemplates[$Template]
    
    # Generate username
    $username = Get-NextAvailableUsername -FirstName $FirstName -LastName $LastName
    Write-Log "Generated username: $username" -Level Info
    
    # Generate email
    $email = "$username@$($script:Config.EmailDomain)"
    
    # Generate password
    $password = New-SecurePassword -Length $script:Config.PasswordLength
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    
    # Determine OU
    $userOU = if ($CustomOU) { $CustomOU } else { Get-UserOU -Department $Department -UserType $Template }
    Write-Log "Target OU: $userOU" -Level Debug
    
    # Get manager DN if specified
    $managerDN = $null
    if ($Manager) {
        try {
            $managerUser = Get-ADUser -Identity $Manager -ErrorAction Stop
            $managerDN = $managerUser.DistinguishedName
            Write-Log "Manager found: $($managerUser.Name)" -Level Info
        }
        catch {
            Write-Log "Manager '$Manager' not found in AD" -Level Warning
        }
    }
    
    # Build user parameters
    $userParams = @{
        SamAccountName = $username
        UserPrincipalName = $email
        Name = "$FirstName $LastName"
        GivenName = $FirstName
        Surname = $LastName
        DisplayName = "$FirstName $LastName"
        EmailAddress = $email
        Department = $Department
        Title = $Title
        Company = $Company
        Path = $userOU
        AccountPassword = $securePassword
        ChangePasswordAtLogon = $script:Config.RequirePasswordChange
        Enabled = $Enabled -or $false
        Description = "Created $(Get-Date -Format 'yyyy-MM-dd') - $Title"
    }
    
    # Add optional parameters
    if ($EmployeeID) { $userParams.EmployeeID = $EmployeeID }
    if ($Phone) { $userParams.OfficePhone = $Phone }
    if ($Mobile) { $userParams.MobilePhone = $Mobile }
    if ($Office) { $userParams.Office = $Office }
    if ($StreetAddress) { $userParams.StreetAddress = $StreetAddress }
    if ($City) { $userParams.City = $City }
    if ($State) { $userParams.State = $State }
    if ($PostalCode) { $userParams.PostalCode = $PostalCode }
    if ($Country) { $userParams.Country = $Country }
    if ($managerDN) { $userParams.Manager = $managerDN }
    
    # Account expiration from template
    if ($templateSettings.AccountExpires) {
        $userParams.AccountExpirationDate = $templateSettings.AccountExpires
        Write-Log "Account will expire: $($templateSettings.AccountExpires)" -Level Info
    }
    
    if ($PSCmdlet.ShouldProcess("$FirstName $LastName ($username)", "Create AD user account")) {
        try {
            # Create user
            New-ADUser @userParams -ErrorAction Stop
            Write-Log "AD user account created successfully" -Level Success
            
            # Return user info
            $newUser = Get-ADUser -Identity $username -Properties *
            
            return [PSCustomObject]@{
                Username = $username
                Email = $email
                Password = $password
                DisplayName = "$FirstName $LastName"
                Department = $Department
                Title = $Title
                OU = $userOU
                Template = $Template
                ADUser = $newUser
                CreatedAt = Get-Date
            }
        }
        catch {
            Write-Log "Failed to create AD user: $_" -Level Error
            throw
        }
    }
}

function Set-UserGroupMembership {
    <#
    .SYNOPSIS
        Adds user to appropriate groups based on department and template
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [string]$Department,
        
        [string]$Template = "Standard",
        
        [string[]]$AdditionalGroups
    )
    
    Write-Log "Configuring group membership for $Username" -Level Action
    
    $groupsToAdd = @()
    
    # Default groups for all users
    $groupsToAdd += $script:Config.DefaultGroups
    
    # Department-specific groups
    if ($script:Config.DepartmentGroups.ContainsKey($Department)) {
        $groupsToAdd += $script:Config.DepartmentGroups[$Department]
    }
    
    # Template-specific groups
    $templateSettings = $script:OnboardingTemplates[$Template]
    if ($templateSettings.Groups) {
        $groupsToAdd += $templateSettings.Groups
    }
    
    # License group
    if ($templateSettings.LicenseType -and $script:Config.LicenseGroups.ContainsKey($templateSettings.LicenseType)) {
        $groupsToAdd += $script:Config.LicenseGroups[$templateSettings.LicenseType]
    }
    
    # Additional custom groups
    if ($AdditionalGroups) {
        $groupsToAdd += $AdditionalGroups
    }
    
    # Remove duplicates
    $groupsToAdd = $groupsToAdd | Select-Object -Unique
    
    $addedGroups = @()
    $failedGroups = @()
    
    foreach ($group in $groupsToAdd) {
        if ($PSCmdlet.ShouldProcess($group, "Add $Username to group")) {
            try {
                # Check if group exists
                $adGroup = Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction Stop
                
                if ($adGroup) {
                    Add-ADGroupMember -Identity $adGroup -Members $Username -ErrorAction Stop
                    $addedGroups += $group
                    Write-Log "  Added to group: $group" -Level Success
                }
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                Write-Log "  Group not found: $group" -Level Warning
                $failedGroups += $group
            }
            catch {
                if ($_.Exception.Message -match "already a member") {
                    Write-Log "  Already member of: $group" -Level Debug
                    $addedGroups += $group
                }
                else {
                    Write-Log "  Failed to add to group $group : $_" -Level Warning
                    $failedGroups += $group
                }
            }
        }
    }
    
    Write-Log "Group membership configured: $($addedGroups.Count) added, $($failedGroups.Count) failed" -Level Info
    
    return [PSCustomObject]@{
        Username = $Username
        AddedGroups = $addedGroups
        FailedGroups = $failedGroups
    }
}

#endregion

#region Home Folder

function New-UserHomeFolder {
    <#
    .SYNOPSIS
        Creates user home folder with appropriate permissions
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$HomeFolderRoot = $script:Config.HomeFolderRoot,
        
        [switch]$SetADAttribute
    )
    
    $homePath = Join-Path $HomeFolderRoot $Username
    
    Write-Log "Creating home folder: $homePath" -Level Action
    
    if ($PSCmdlet.ShouldProcess($homePath, "Create home folder")) {
        try {
            # Create folder
            if (-not (Test-Path $homePath)) {
                New-Item -Path $homePath -ItemType Directory -Force | Out-Null
                Write-Log "Home folder created" -Level Success
            }
            else {
                Write-Log "Home folder already exists" -Level Warning
            }
            
            # Set permissions
            $acl = Get-Acl $homePath
            
            # Remove inheritance
            $acl.SetAccessRuleProtection($true, $false)
            
            # Add SYSTEM - Full Control
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($systemRule)
            
            # Add Domain Admins - Full Control
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$($env:USERDOMAIN)\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($adminRule)
            
            # Add User - Modify
            $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$($env:USERDOMAIN)\$Username", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($userRule)
            
            # Apply ACL
            Set-Acl -Path $homePath -AclObject $acl
            Write-Log "Permissions configured" -Level Success
            
            # Set AD attribute
            if ($SetADAttribute) {
                Set-ADUser -Identity $Username -HomeDirectory $homePath -HomeDrive "H:"
                Write-Log "AD home directory attribute set" -Level Success
            }
            
            return [PSCustomObject]@{
                Username = $Username
                HomePath = $homePath
                Created = $true
            }
        }
        catch {
            Write-Log "Failed to create home folder: $_" -Level Error
            throw
        }
    }
}

function New-UserProfileFolder {
    <#
    .SYNOPSIS
        Creates roaming profile folder
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$ProfileRoot = $script:Config.ProfilePath
    )
    
    $profilePath = Join-Path $ProfileRoot $Username
    
    Write-Log "Creating profile folder: $profilePath" -Level Action
    
    if ($PSCmdlet.ShouldProcess($profilePath, "Create profile folder")) {
        try {
            if (-not (Test-Path $profilePath)) {
                New-Item -Path $profilePath -ItemType Directory -Force | Out-Null
            }
            
            # Set permissions (similar to home folder but for profile)
            $acl = Get-Acl $profilePath
            $acl.SetAccessRuleProtection($true, $false)
            
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($systemRule)
            
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$($env:USERDOMAIN)\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($adminRule)
            
            $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$($env:USERDOMAIN)\$Username", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($userRule)
            
            Set-Acl -Path $profilePath -AclObject $acl
            
            # Set AD attribute
            Set-ADUser -Identity $Username -ProfilePath $profilePath
            
            Write-Log "Profile folder created and configured" -Level Success
            
            return $profilePath
        }
        catch {
            Write-Log "Failed to create profile folder: $_" -Level Error
            throw
        }
    }
}

#endregion

#region Welcome Email

function New-WelcomeEmail {
    <#
    .SYNOPSIS
        Generates welcome email content for new user
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$UserInfo,
        
        [string]$TemplatePath,
        
        [switch]$AsHTML
    )
    
    Write-Log "Generating welcome email" -Level Info
    
    $welcomeContent = @"
================================================================================
                        WELCOME TO $($script:Config.Company)!
================================================================================

Dear $($UserInfo.DisplayName),

Welcome to the team! Your IT accounts have been created and are ready for use.

ACCOUNT INFORMATION
--------------------------------------------------------------------------------
Username:       $($UserInfo.Username)
Email:          $($UserInfo.Email)
Temporary Password: $($UserInfo.Password)

IMPORTANT: You will be required to change your password upon first login.

GETTING STARTED
--------------------------------------------------------------------------------
1. Log in to your computer using the username and password above
2. Change your password when prompted
3. Set up your email in Outlook
4. Complete your IT orientation training

USEFUL LINKS
--------------------------------------------------------------------------------
• IT Self-Service Portal: https://helpdesk.$($script:Config.EmailDomain)
• Password Reset: https://passwordreset.$($script:Config.EmailDomain)
• Company Intranet: https://intranet.$($script:Config.EmailDomain)
• IT Knowledge Base: https://kb.$($script:Config.EmailDomain)

NEED HELP?
--------------------------------------------------------------------------------
IT Help Desk: $($script:Config.ITSupportEmail)
Phone: (555) 123-4567
Hours: Monday - Friday, 8:00 AM - 6:00 PM

We're excited to have you on board!

Best regards,
IT Department
$($script:Config.Company)

================================================================================
This email contains confidential information. Please do not share your
password with anyone. IT will never ask for your password.
================================================================================
"@

    if ($AsHTML) {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .header h1 { margin: 0; font-size: 24px; }
        .content { padding: 30px; background: #fff; border: 1px solid #ddd; }
        .credentials { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #667eea; }
        .credentials table { width: 100%; }
        .credentials td { padding: 8px 0; }
        .credentials .label { font-weight: bold; width: 150px; }
        .password { font-family: monospace; background: #fff3cd; padding: 5px 10px; border-radius: 4px; }
        .warning { background: #fff3cd; border: 1px solid #ffc107; padding: 15px; border-radius: 8px; margin: 20px 0; }
        .links { margin: 20px 0; }
        .links a { display: block; padding: 10px; background: #f8f9fa; margin: 5px 0; border-radius: 4px; text-decoration: none; color: #667eea; }
        .links a:hover { background: #e9ecef; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; border-radius: 0 0 8px 8px; font-size: 12px; color: #666; }
        .help { background: #d4edda; padding: 15px; border-radius: 8px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎉 Welcome to $($script:Config.Company)!</h1>
    </div>
    <div class="content">
        <p>Dear <strong>$($UserInfo.DisplayName)</strong>,</p>
        <p>Welcome to the team! Your IT accounts have been created and are ready for use.</p>
        
        <div class="credentials">
            <h3>📋 Your Account Information</h3>
            <table>
                <tr><td class="label">Username:</td><td><strong>$($UserInfo.Username)</strong></td></tr>
                <tr><td class="label">Email:</td><td><strong>$($UserInfo.Email)</strong></td></tr>
                <tr><td class="label">Temporary Password:</td><td><span class="password">$($UserInfo.Password)</span></td></tr>
            </table>
        </div>
        
        <div class="warning">
            ⚠️ <strong>Important:</strong> You will be required to change your password upon first login.
        </div>
        
        <h3>🚀 Getting Started</h3>
        <ol>
            <li>Log in to your computer using the username and password above</li>
            <li>Change your password when prompted</li>
            <li>Set up your email in Outlook</li>
            <li>Complete your IT orientation training</li>
        </ol>
        
        <h3>🔗 Useful Links</h3>
        <div class="links">
            <a href="https://helpdesk.$($script:Config.EmailDomain)">IT Self-Service Portal</a>
            <a href="https://passwordreset.$($script:Config.EmailDomain)">Password Reset Tool</a>
            <a href="https://intranet.$($script:Config.EmailDomain)">Company Intranet</a>
            <a href="https://kb.$($script:Config.EmailDomain)">IT Knowledge Base</a>
        </div>
        
        <div class="help">
            <h3>📞 Need Help?</h3>
            <p>
                <strong>IT Help Desk:</strong> $($script:Config.ITSupportEmail)<br>
                <strong>Phone:</strong> (555) 123-4567<br>
                <strong>Hours:</strong> Monday - Friday, 8:00 AM - 6:00 PM
            </p>
        </div>
        
        <p>We're excited to have you on board!</p>
        <p>Best regards,<br><strong>IT Department</strong></p>
    </div>
    <div class="footer">
        <p>🔒 This email contains confidential information. Please do not share your password with anyone.<br>
        IT will never ask for your password.</p>
    </div>
</body>
</html>
"@
        return $htmlContent
    }
    
    return $welcomeContent
}

function Send-WelcomeEmail {
    <#
    .SYNOPSIS
        Sends welcome email to new user or their manager
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$UserInfo,
        
        [string]$SendTo,
        
        [switch]$SendToManager,
        
        [switch]$SendToHR,
        
        [string]$SMTPServer = "smtp.$($script:Config.EmailDomain)"
    )
    
    Write-Log "Sending welcome email" -Level Action
    
    $recipients = @()
    
    if ($SendTo) {
        $recipients += $SendTo
    }
    
    if ($SendToManager -and $UserInfo.ADUser.Manager) {
        $manager = Get-ADUser -Identity $UserInfo.ADUser.Manager -Properties EmailAddress
        if ($manager.EmailAddress) {
            $recipients += $manager.EmailAddress
        }
    }
    
    if ($SendToHR) {
        $recipients += $script:Config.HREmail
    }
    
    if (-not $recipients) {
        Write-Log "No recipients specified for welcome email" -Level Warning
        return $false
    }
    
    $emailContent = New-WelcomeEmail -UserInfo $UserInfo -AsHTML
    
    try {
        $mailParams = @{
            To = $recipients
            From = $script:Config.ITSupportEmail
            Subject = "Welcome to $($script:Config.Company) - Account Information for $($UserInfo.DisplayName)"
            Body = $emailContent
            BodyAsHtml = $true
            SmtpServer = $SMTPServer
        }
        
        Send-MailMessage @mailParams -ErrorAction Stop
        Write-Log "Welcome email sent to: $($recipients -join ', ')" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to send welcome email: $_" -Level Error
        
        # Save to file as fallback
        $fallbackPath = Join-Path $script:Config.ReportPath "WelcomeEmail_$($UserInfo.Username)_$(Get-Date -Format 'yyyyMMdd').html"
        $emailContent | Out-File -FilePath $fallbackPath -Encoding UTF8
        Write-Log "Welcome email saved to: $fallbackPath" -Level Info
        
        return $false
    }
}

#endregion

#region Main Onboarding Function

function New-UserOnboarding {
    <#
    .SYNOPSIS
        Complete user onboarding process
    
    .DESCRIPTION
        Performs full user onboarding including:
        - AD account creation
        - Group membership
        - Home folder setup
        - Welcome email generation
        - Documentation
    
    .PARAMETER FirstName
        User's first name
    
    .PARAMETER LastName
        User's last name
    
    .PARAMETER Department
        Department name
    
    .PARAMETER Title
        Job title
    
    .PARAMETER Manager
        Manager's username
    
    .PARAMETER Template
        Onboarding template (Standard, Contractor, Executive, Intern, ITAdmin)
    
    .PARAMETER StartDate
        Employment start date
    
    .PARAMETER SkipHomeFolder
        Skip home folder creation
    
    .PARAMETER SkipEmail
        Skip welcome email
    
    .EXAMPLE
        New-UserOnboarding -FirstName "John" -LastName "Smith" -Department "IT" -Title "Help Desk Analyst" -Manager "jdoe"
    
    .EXAMPLE
        New-UserOnboarding -FirstName "Jane" -LastName "Contractor" -Department "IT" -Title "Consultant" -Template "Contractor"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FirstName,
        
        [Parameter(Mandatory)]
        [string]$LastName,
        
        [Parameter(Mandatory)]
        [string]$Department,
        
        [Parameter(Mandatory)]
        [string]$Title,
        
        [string]$Manager,
        
        [string]$EmployeeID,
        
        [string]$Phone,
        
        [string]$Mobile,
        
        [string]$Office,
        
        [datetime]$StartDate = (Get-Date),
        
        [ValidateSet('Standard', 'Contractor', 'Executive', 'Intern', 'ITAdmin')]
        [string]$Template = "Standard",
        
        [string[]]$AdditionalGroups,
        
        [switch]$SkipHomeFolder,
        
        [switch]$SkipEmail,
        
        [switch]$EnableAccount
    )
    
    # Initialize session
    $script:OnboardingSession = @{
        StartTime = Get-Date
        User = "$FirstName $LastName"
        Actions = @()
        Errors = @()
        Warnings = @()
    }
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    User Onboarding                             ║" -ForegroundColor Green
    Write-Host "║                    $FirstName $LastName".PadRight(45) + "║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    $results = [PSCustomObject]@{
        Success = $false
        Username = $null
        Email = $null
        Password = $null
        UserInfo = $null
        Groups = $null
        HomeFolder = $null
        WelcomeEmailSent = $false
        Errors = @()
        LogFile = $null
    }
    
    try {
        # Step 1: Create AD Account
        Write-Host ""
        Write-Log "Step 1: Creating Active Directory account..." -Level Action
        
        $userParams = @{
            FirstName = $FirstName
            LastName = $LastName
            Department = $Department
            Title = $Title
            Template = $Template
            StartDate = $StartDate
            Enabled = $EnableAccount
        }
        
        if ($Manager) { $userParams.Manager = $Manager }
        if ($EmployeeID) { $userParams.EmployeeID = $EmployeeID }
        if ($Phone) { $userParams.Phone = $Phone }
        if ($Mobile) { $userParams.Mobile = $Mobile }
        if ($Office) { $userParams.Office = $Office }
        
        $userInfo = New-ADUserAccount @userParams
        
        $results.Username = $userInfo.Username
        $results.Email = $userInfo.Email
        $results.Password = $userInfo.Password
        $results.UserInfo = $userInfo
        
        # Step 2: Configure Group Membership
        Write-Host ""
        Write-Log "Step 2: Configuring group membership..." -Level Action
        
        $groupResult = Set-UserGroupMembership -Username $userInfo.Username `
                                               -Department $Department `
                                               -Template $Template `
                                               -AdditionalGroups $AdditionalGroups
        
        $results.Groups = $groupResult
        
        # Step 3: Create Home Folder
        if (-not $SkipHomeFolder -and $script:Config.CreateHomeFolder) {
            Write-Host ""
            Write-Log "Step 3: Creating home folder..." -Level Action
            
            $templateSettings = $script:OnboardingTemplates[$Template]
            
            if ($templateSettings.HomeFolder) {
                $homeResult = New-UserHomeFolder -Username $userInfo.Username -SetADAttribute
                $results.HomeFolder = $homeResult
            }
            else {
                Write-Log "Home folder skipped (template setting)" -Level Info
            }
        }
        else {
            Write-Log "Step 3: Home folder creation skipped" -Level Info
        }
        
        # Step 4: Create Roaming Profile (if enabled)
        if ($script:Config.CreateRoamingProfile) {
            Write-Host ""
            Write-Log "Step 4: Creating roaming profile..." -Level Action
            $profilePath = New-UserProfileFolder -Username $userInfo.Username
        }
        
        # Step 5: Generate/Send Welcome Email
        Write-Host ""
        Write-Log "Step 5: Generating welcome documentation..." -Level Action
        
        # Always generate welcome email content
        $welcomeContent = New-WelcomeEmail -UserInfo $userInfo
        
        # Save welcome email to file
        if (-not (Test-Path $script:Config.ReportPath)) {
            New-Item -Path $script:Config.ReportPath -ItemType Directory -Force | Out-Null
        }
        
        $welcomeFilePath = Join-Path $script:Config.ReportPath "WelcomeInfo_$($userInfo.Username)_$(Get-Date -Format 'yyyyMMdd').txt"
        $welcomeContent | Out-File -FilePath $welcomeFilePath -Encoding UTF8
        Write-Log "Welcome information saved to: $welcomeFilePath" -Level Success
        
        # Also save HTML version
        $welcomeHtml = New-WelcomeEmail -UserInfo $userInfo -AsHTML
        $welcomeHtmlPath = Join-Path $script:Config.ReportPath "WelcomeInfo_$($userInfo.Username)_$(Get-Date -Format 'yyyyMMdd').html"
        $welcomeHtml | Out-File -FilePath $welcomeHtmlPath -Encoding UTF8
        
        # Send email if not skipped
        if (-not $SkipEmail -and $script:Config.SendWelcomeEmail) {
            if ($Manager) {
                $emailSent = Send-WelcomeEmail -UserInfo $userInfo -SendToManager -SendToHR
            }
            else {
                $emailSent = Send-WelcomeEmail -UserInfo $userInfo -SendToHR
            }
            $results.WelcomeEmailSent = $emailSent
        }
        
        # Enable account if requested
        if ($EnableAccount) {
            Enable-ADAccount -Identity $userInfo.Username
            Write-Log "Account enabled" -Level Success
        }
        else {
            Write-Log "Account created but NOT enabled. Enable manually when ready." -Level Warning
        }
        
        $results.Success = $true
        
    }
    catch {
        Write-Log "Onboarding failed: $_" -Level Error
        $results.Errors += $_.Exception.Message
    }
    finally {
        # Save onboarding log
        $results.LogFile = Save-OnboardingLog -Username $results.Username
        $results.Errors = $script:OnboardingSession.Errors
    }
    
    # Summary
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $(if ($results.Success) { 'Green' } else { 'Red' })
    Write-Host "║                    Onboarding Summary                          ║" -ForegroundColor $(if ($results.Success) { 'Green' } else { 'Red' })
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $(if ($results.Success) { 'Green' } else { 'Red' })
    Write-Host ""
    
    if ($results.Success) {
        Write-Host "  Status:      SUCCESS" -ForegroundColor Green
        Write-Host "  Username:    $($results.Username)" -ForegroundColor White
        Write-Host "  Email:       $($results.Email)" -ForegroundColor White
        Write-Host "  Password:    $($results.Password)" -ForegroundColor Yellow
        Write-Host "  Department:  $Department" -ForegroundColor White
        Write-Host "  Template:    $Template" -ForegroundColor White
        Write-Host "  Groups:      $($results.Groups.AddedGroups.Count) assigned" -ForegroundColor White
        
        if ($results.HomeFolder) {
            Write-Host "  Home Folder: $($results.HomeFolder.HomePath)" -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "  ⚠️  IMPORTANT: " -ForegroundColor Yellow -NoNewline
        Write-Host "Save the password above - it cannot be retrieved!" -ForegroundColor White
        
        if (-not $EnableAccount) {
            Write-Host "  ⚠️  Account is DISABLED. Enable when user is ready to start." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  Status: FAILED" -ForegroundColor Red
        foreach ($error in $results.Errors) {
            Write-Host "  Error: $error" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "  Log file: $($results.LogFile)" -ForegroundColor Gray
    Write-Host ""
    
    return $results
}

#endregion

#region Bulk Import

function Import-UserOnboarding {
    <#
    .SYNOPSIS
        Bulk onboard users from CSV file
    
    .PARAMETER CSVPath
        Path to CSV file with user information
    
    .PARAMETER Template
        Default template to use (can be overridden per user in CSV)
    
    .EXAMPLE
        Import-UserOnboarding -CSVPath ".\new-hires.csv"
    
    .NOTES
        CSV Columns: FirstName, LastName, Department, Title, Manager, EmployeeID, Template
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$CSVPath,
        
        [string]$DefaultTemplate = "Standard",
        
        [switch]$EnableAccounts,
        
        [switch]$ContinueOnError
    )
    
    if (-not (Test-Path $CSVPath)) {
        Write-Log "CSV file not found: $CSVPath" -Level Error
        return
    }
    
    Write-Log "Importing users from: $CSVPath" -Level Info
    
    $users = Import-Csv -Path $CSVPath
    $results = @()
    $successCount = 0
    $failCount = 0
    
    Write-Host ""
    Write-Host "Found $($users.Count) users to onboard" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($user in $users) {
        Write-Host "─" * 60 -ForegroundColor Gray
        
        try {
            $template = if ($user.Template) { $user.Template } else { $DefaultTemplate }
            
            $onboardParams = @{
                FirstName = $user.FirstName
                LastName = $user.LastName
                Department = $user.Department
                Title = $user.Title
                Template = $template
                EnableAccount = $EnableAccounts
                SkipEmail = $true  # Send summary email instead
            }
            
            if ($user.Manager) { $onboardParams.Manager = $user.Manager }
            if ($user.EmployeeID) { $onboardParams.EmployeeID = $user.EmployeeID }
            if ($user.Phone) { $onboardParams.Phone = $user.Phone }
            if ($user.Office) { $onboardParams.Office = $user.Office }
            
            $result = New-UserOnboarding @onboardParams
            
            $results += [PSCustomObject]@{
                Name = "$($user.FirstName) $($user.LastName)"
                Username = $result.Username
                Email = $result.Email
                Password = $result.Password
                Status = if ($result.Success) { "Success" } else { "Failed" }
                Error = if ($result.Errors) { $result.Errors -join "; " } else { $null }
            }
            
            if ($result.Success) {
                $successCount++
            }
            else {
                $failCount++
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Name = "$($user.FirstName) $($user.LastName)"
                Username = $null
                Email = $null
                Password = $null
                Status = "Failed"
                Error = $_.Exception.Message
            }
            $failCount++
            
            if (-not $ContinueOnError) {
                Write-Log "Stopping due to error. Use -ContinueOnError to proceed." -Level Error
                break
            }
        }
    }
    
    # Export results
    $exportPath = Join-Path $script:Config.ReportPath "BulkOnboarding_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    
    # Summary
    Write-Host ""
    Write-Host "═" * 60 -ForegroundColor Cyan
    Write-Host "BULK ONBOARDING COMPLETE" -ForegroundColor Cyan
    Write-Host "═" * 60 -ForegroundColor Cyan
    Write-Host "  Successful: $successCount" -ForegroundColor Green
    Write-Host "  Failed:     $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Results:    $exportPath" -ForegroundColor Gray
    Write-Host ""
    
    return $results
}

function New-OnboardingTemplate {
    <#
    .SYNOPSIS
        Creates a CSV template for bulk onboarding
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath = ".\new-hires-template.csv"
    )
    
    $template = @(
        [PSCustomObject]@{
            FirstName = "John"
            LastName = "Smith"
            Department = "IT"
            Title = "Help Desk Analyst"
            Manager = "jdoe"
            EmployeeID = "EMP001"
            Phone = "(555) 123-4567"
            Office = "Building A, Floor 2"
            Template = "Standard"
        },
        [PSCustomObject]@{
            FirstName = "Jane"
            LastName = "Doe"
            Department = "HR"
            Title = "HR Coordinator"
            Manager = "msmith"
            EmployeeID = "EMP002"
            Phone = "(555) 123-4568"
            Office = "Building A, Floor 1"
            Template = "Standard"
        }
    )
    
    $template | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Log "Template created: $OutputPath" -Level Success
    
    return $OutputPath
}

#endregion

#region Interactive Wizard

function Start-OnboardingWizard {
    <#
    .SYNOPSIS
        Interactive user onboarding wizard
    #>
    [CmdletBinding()]
    param()
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              User Onboarding Wizard                            ║" -ForegroundColor Cyan
    Write-Host "║              SysAdmin Toolkit v2.0                             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Enter new user information:" -ForegroundColor Yellow
    Write-Host ""
    
    # Collect information
    $firstName = Read-Host "First Name"
    $lastName = Read-Host "Last Name"
    
    # Department selection
    Write-Host ""
    Write-Host "Available Departments:" -ForegroundColor Cyan
    $depts = $script:Config.OUPaths.Keys | Sort-Object
    $i = 1
    foreach ($dept in $depts) {
        Write-Host "  $i. $dept"
        $i++
    }
    $deptChoice = Read-Host "Select Department (1-$($depts.Count))"
    $department = $depts[[int]$deptChoice - 1]
    
    $title = Read-Host "Job Title"
    $manager = Read-Host "Manager Username (optional)"
    $employeeID = Read-Host "Employee ID (optional)"
    
    # Template selection
    Write-Host ""
    Write-Host "User Templates:" -ForegroundColor Cyan
    Write-Host "  1. Standard - Regular employee"
    Write-Host "  2. Contractor - Temporary access (90 days)"
    Write-Host "  3. Executive - Full access"
    Write-Host "  4. Intern - Limited access (120 days)"
    Write-Host "  5. ITAdmin - IT administrator"
    $templateChoice = Read-Host "Select Template (1-5)"
    $template = switch ($templateChoice) {
        "1" { "Standard" }
        "2" { "Contractor" }
        "3" { "Executive" }
        "4" { "Intern" }
        "5" { "ITAdmin" }
        default { "Standard" }
    }
    
    $enableNow = Read-Host "Enable account immediately? (Y/N)"
    $enable = $enableNow -eq 'Y'
    
    # Confirm
    Write-Host ""
    Write-Host "═" * 50 -ForegroundColor Yellow
    Write-Host "Please confirm the following:" -ForegroundColor Yellow
    Write-Host "═" * 50 -ForegroundColor Yellow
    Write-Host "  Name:       $firstName $lastName"
    Write-Host "  Department: $department"
    Write-Host "  Title:      $title"
    Write-Host "  Manager:    $(if ($manager) { $manager } else { 'Not specified' })"
    Write-Host "  Template:   $template"
    Write-Host "  Enabled:    $enable"
    Write-Host ""
    
    $confirm = Read-Host "Proceed with onboarding? (Y/N)"
    
    if ($confirm -eq 'Y') {
        $params = @{
            FirstName = $firstName
            LastName = $lastName
            Department = $department
            Title = $title
            Template = $template
            EnableAccount = $enable
        }
        
        if ($manager) { $params.Manager = $manager }
        if ($employeeID) { $params.EmployeeID = $employeeID }
        
        New-UserOnboarding @params
    }
    else {
        Write-Host "Onboarding cancelled." -ForegroundColor Yellow
    }
}

#endregion

# Export functions
Export-ModuleMember -Function New-UserOnboarding, Import-UserOnboarding, New-OnboardingTemplate,
    Start-OnboardingWizard, New-ADUserAccount, Set-UserGroupMembership,
    New-UserHomeFolder, New-WelcomeEmail, Send-WelcomeEmail

# Display available commands
Write-Host ""
Write-Host "User Onboarding Module Loaded" -ForegroundColor Green
Write-Host "Run 'Start-OnboardingWizard' for interactive onboarding" -ForegroundColor Cyan
Write-Host ""
