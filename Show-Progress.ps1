#Requires -Version 5.1

<#
.SYNOPSIS
    Wrapper script to show the Workspace ONE to Azure/Intune Migration Toolkit progress.
    
.DESCRIPTION
    This script provides a convenient way to view the project status and progress
    from anywhere in the project. It delegates to the main dashboard script.
    
.PARAMETER ShowExtended
    Display extended components, not just MVP components.
    
.PARAMETER Format
    The output format. Options: Console, HTML, JSON. Default is Console.
    
.PARAMETER SaveReport
    Switch to save a report file instead of just displaying in console.
    
.PARAMETER ReportPath
    Path to save the report file. Default is project root directory.
    
.EXAMPLE
    .\Show-Progress.ps1
    
.EXAMPLE
    .\Show-Progress.ps1 -ShowExtended -Format HTML -SaveReport
    
.NOTES
    File Name      : Show-Progress.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$ShowExtended,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$Format = 'Console',
    
    [Parameter(Mandatory = $false)]
    [switch]$SaveReport,
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath
)

# Get the directory where this script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct path to dashboard script
$dashboardScript = Join-Path -Path $scriptDir -ChildPath "dashboard\Show-ProjectStatus.ps1"

# If the dashboard script doesn't exist in the expected location, try to find it
if (-not (Test-Path -Path $dashboardScript)) {
    $possiblePaths = @(
        ".\dashboard\Show-ProjectStatus.ps1",
        ".\Show-ProjectStatus.ps1",
        "$scriptDir\dashboard\Show-ProjectStatus.ps1"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path -Path $path) {
            $dashboardScript = $path
            break
        }
    }
}

# Prepare command line arguments
$arguments = @()

if ($ShowExtended) {
    $arguments += "-ShowExtendedComponents"
}

$arguments += "-OutputFormat"
$arguments += $Format

if ($SaveReport) {
    # Determine report filename based on format
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $extension = if ($Format -eq 'HTML') { 'html' } elseif ($Format -eq 'JSON') { 'json' } else { 'txt' }
    $filename = "WS1_Migration_Status_$timestamp.$extension"
    
    # Determine report path
    if (-not $ReportPath) {
        $ReportPath = Join-Path -Path $scriptDir -ChildPath $filename
    } else {
        # Ensure the path has filename
        if ((Split-Path -Leaf $ReportPath) -notmatch '\.' + $extension) {
            $ReportPath = Join-Path -Path $ReportPath -ChildPath $filename
        }
    }
    
    $arguments += "-OutputPath"
    $arguments += "`"$ReportPath`""
}

# Execute the dashboard script
$command = "& `"$dashboardScript`" $($arguments -join ' ')"
Write-Host "Executing: $command" -ForegroundColor Cyan
Invoke-Expression $command

# Provide additional information if report was saved
if ($SaveReport -and (Test-Path -Path $ReportPath)) {
    Write-Host "`nReport saved to: $ReportPath" -ForegroundColor Green
    
    # If it's an HTML report, offer to open it
    if ($Format -eq 'HTML') {
        $openReport = Read-Host "Would you like to open the report now? (Y/N)"
        if ($openReport -eq 'Y' -or $openReport -eq 'y') {
            Start-Process $ReportPath
        }
    }
} 