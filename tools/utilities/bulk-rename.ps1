<#
.SYNOPSIS
    Bulk File Renaming Utility.
    Uses Regex to rename thousands of files instantly.

.DESCRIPTION
    A powerful tool for sanitizing file names. Useful for:
    - Removing illegal characters before SharePoint migration.
    - Standardizing date formats (e.g., changing 2023.01.01 to 2023-01-01).
    - Appending prefixes/suffixes to project files.

.EXAMPLE
    .\bulk-rename.ps1 -Path "C:\Data" -Match " " -Replace "_"
    > Replaces all spaces with underscores in filenames.

.EXAMPLE
    .\bulk-rename.ps1 -Path "C:\Data" -Match "^" -Replace "Confidential_" -Recursive
    > Prepends "Confidential_" to the start of every file in the tree.

.EXAMPLE
    .\bulk-rename.ps1 -Path "C:\Docs" -Match "\.jpeg$" -Replace ".jpg" -WhatIf
    > Shows what files would be renamed without actually doing it.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
Param (
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [Parameter(Mandatory=$true)]
    [string]$Match,

    [Parameter(Mandatory=$true)]
    [string]$Replace,

    [switch]$Recursive
)

# 1. Validation
if (-not (Test-Path $Path)) {
    Write-Error "Directory not found: $Path"
    return
}

Write-Host "--- APEX BULK RENAME TOOL ---" -ForegroundColor Cyan
Write-Host "Target: $Path"
Write-Host "Pattern: '$Match' -> '$Replace'"

# 2. Get Files
$SearchOption = if ($Recursive) { "AllDirectories" } else { "TopDirectoryOnly" }
$Files = Get-ChildItem -Path $Path -File -Recurse:$Recursive

$Count = 0

foreach ($File in $Files) {
    # Check if the filename matches the pattern
    if ($File.Name -match $Match) {
        # Calculate new name
        $NewName = $File.Name -replace $Match, $Replace
        
        # Skip if name hasn't changed (regex match might consume 0 chars)
        if ($NewName -eq $File.Name) { continue }

        try {
            # 3. Rename (Supports -WhatIf automatically via CmdletBinding)
            Rename-Item -LiteralPath $File.FullName -NewName $NewName -ErrorAction Stop
            
            # Visual Feedback (Only prints if actually running)
            if (-not $PSCmdlet.ShouldProcess($File.Name, "Rename to $NewName")) {
                # This block runs during -WhatIf
            } else {
                Write-Host "Renamed: $($File.Name) -> $NewName" -ForegroundColor Green
                $Count++
            }
        }
        catch {
            Write-Warning "Failed to rename $($File.Name): $_"
        }
    }
}

Write-Host "Operation Complete. $Count files renamed." -ForegroundColor Yellow
Strategic Value
SharePoint/Cloud Migration: Cloud providers often block characters like #, %, &, {, }. You can strip these out instantly with regex: -Match "[#%&{}]" -Replace ""

Liability Reduction: Renaming files to include classification tags (e.g., CONFIDENTIAL-) at the file level ensures that even if the file is copied out of a secure folder, the warning label travels with it.

Quick Add Command
Run this to create the file instantly:

Bash

cat << 'EOF' > SysAdmin-Toolkit/tools/bulk-rename.ps1
param($Path, $Match, $Replace, $Recursive)
Get-ChildItem $Path -File -Recurse:$Recursive | Where-Object { $_.Name -match $Match } | ForEach-Object {
    $NewName = $_.Name -replace $Match, $Replace
    Rename-Item $_.FullName -NewName $NewName -WhatIf
}
EOF
