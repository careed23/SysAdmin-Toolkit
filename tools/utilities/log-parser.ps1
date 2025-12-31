<#
.SYNOPSIS
    Lightweight Log Analysis Tool.
    Parses text logs to group and count specific patterns (Errors, IPs, Status Codes).

.DESCRIPTION
    A strategic alternative to "Ctrl+F" in Notepad. It reads a log file, matches a regex pattern,
    and returns a frequency report of the matches. Useful for identifying top error sources
    or noisy IP addresses.

.EXAMPLE
    .\log-parser.ps1 -FilePath "C:\logs\iis.log" -Pattern " 500 "
    > Finds all occurrences of HTTP 500 errors and counts them.

.EXAMPLE
    .\log-parser.ps1 -FilePath "C:\logs\app.log" -Pattern "Exception" -Context 2
    > Finds "Exception" and shows 2 lines of context before/after.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$true)]
    [string]$Pattern,

    [int]$Context = 0,

    [switch]$ExportCSV
)

# 1. Validation
if (-not (Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    return
}

Write-Host "--- APEX LOG PARSER ---" -ForegroundColor Cyan
Write-Host "Target: $FilePath"
Write-Host "Searching for: '$Pattern'"
Write-Host "Scanning..." -NoNewline

# 2. The Heavy Lifting (Select-String is highly optimized)
try {
    if ($Context -gt 0) {
        # Context mode: Just show the raw hits with context
        $Hits = Select-String -Path $FilePath -Pattern $Pattern -Context $Context
        Write-Host " Done." -ForegroundColor Green
        Write-Host "Found $($Hits.Count) occurrences." -ForegroundColor Yellow
        
        foreach ($Hit in $Hits) {
            Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "Line $($Hit.LineNumber): $($Hit.Line)" -ForegroundColor Red
            if ($Hit.Context) {
                Write-Host "   Context: $($Hit.Context.PostContext)" -ForegroundColor Gray
            }
        }
    }
    else {
        # Analysis mode: Group and Count
        $Hits = Select-String -Path $FilePath -Pattern $Pattern
        Write-Host " Done." -ForegroundColor Green
        
        if ($Hits) {
            $Grouped = $Hits | Group-Object -Property Line | Sort-Object Count -Descending | Select-Object Count, Name
            
            Write-Host "`n[TOP OCCURRENCES REPORT]" -ForegroundColor Cyan
            $Grouped | Select-Object -First 20 | Format-Table -AutoSize

            if ($ExportCSV) {
                $OutPath = "$($FilePath)_Report.csv"
                $Grouped | Export-Csv -Path $OutPath -NoTypeInformation
                Write-Host "Report saved to: $OutPath" -ForegroundColor Green
            }
        }
        else {
            Write-Host "No matches found." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Error "Error parsing log: $_"
}
Strategic Value
Zero-Cost Analysis: Enterprise logging tools (Splunk, Datadog) cost thousands. This script solves the 80/20 use case (finding top errors) for free.

Performance: Select-String in PowerShell is extremely fast, even on files several hundred MBs in size, because it relies on .NET's optimized regex engine.

Quick Add Command
Run this in your terminal to create the file instantly:

Bash

cat << 'EOF' > SysAdmin-Toolkit/tools/log-parser.ps1
param([string]$FilePath, [string]$Pattern, [switch]$ExportCSV)
if(!(Test-Path $FilePath)){ Write-Error "File not found"; exit }
$Hits = Select-String -Path $FilePath -Pattern $Pattern
$Grouped = $Hits | Group-Object Line | Sort Count -Desc | Select Count, Name
$Grouped | Format-Table -AutoSize
if($ExportCSV){ $Grouped | Export-Csv "$FilePath.csv" }
EOF
