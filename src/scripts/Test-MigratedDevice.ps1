#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Tests if a device has been successfully migrated from Workspace ONE to Azure/Intune.
    
.DESCRIPTION
    This script performs validation checks to ensure that a device has been
    successfully migrated from Workspace ONE to Azure/Intune, including checking
    enrollment status, policy application, and required apps.
    
.NOTES
    File Name      : Test-MigratedDevice.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
    
.EXAMPLE
    .\Test-MigratedDevice.ps1
    
.EXAMPLE
    .\Test-MigratedDevice.ps1 -GenerateReport
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$GenerateReport
)

# Set script paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path -Path $scriptPath -ChildPath "..\modules"
$logPath = Join-Path -Path $env:TEMP -ChildPath "MigrationLogs"

# Import required modules
$modulesToImport = @(
    "LoggingModule.psm1",
    "ValidationModule.psm1"
)

foreach ($module in $modulesToImport) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath $module
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        Write-Error "Required module $module not found at path: $modulePath"
        exit 1
    }
}

# Initialize logging
if (-not (Test-Path -Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

Initialize-Logging -LogPath $logPath -LogFileName "MigrationValidation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-LogMessage -Message "Starting migration validation" -Level INFO

# Perform validation
try {
    # Test the migrated device
    $validationResults = Test-MigratedDevice
    
    # Display results
    Write-Host "`n=== Migration Validation Results ===" -ForegroundColor Cyan
    
    if ($validationResults.Success) {
        Write-Host "✓ Migration validation successful!" -ForegroundColor Green
    } else {
        Write-Host "✗ Migration validation failed. Issues found:" -ForegroundColor Red
        foreach ($issue in $validationResults.Issues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
    }
    
    Write-Host "`nDetailed Results:" -ForegroundColor Cyan
    Write-Host "  Azure/Intune Enrollment: $(if ($validationResults.EnrolledToIntuneOrAzure) { "✓" } else { "✗" })" -ForegroundColor $(if ($validationResults.EnrolledToIntuneOrAzure) { "Green" } else { "Red" })
    Write-Host "  Workspace ONE Removed: $(if ($validationResults.WorkspaceOneRemoved) { "✓" } else { "✗" })" -ForegroundColor $(if ($validationResults.WorkspaceOneRemoved) { "Green" } else { "Red" })
    Write-Host "  Intune Policies Applied: $(if ($validationResults.PoliciesApplied) { "✓" } else { "✗" })" -ForegroundColor $(if ($validationResults.PoliciesApplied) { "Green" } else { "Red" })
    Write-Host "  Required Apps Installed: $(if ($validationResults.RequiredAppsInstalled) { "✓" } else { "✗" })" -ForegroundColor $(if ($validationResults.RequiredAppsInstalled) { "Green" } else { "Red" })
    
    # Generate report if requested
    if ($GenerateReport) {
        $reportPath = Join-Path -Path $logPath -ChildPath "MigrationValidationReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        
        $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Migration Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0066cc; }
        .success { color: green; }
        .failure { color: red; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .timestamp { color: gray; font-size: 0.8em; }
    </style>
</head>
<body>
    <h1>Migration Validation Report</h1>
    <p class="timestamp">Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    
    <h2 class="$(if ($validationResults.Success) { 'success' } else { 'failure' })">
        Overall Status: $(if ($validationResults.Success) { 'SUCCESS' } else { 'FAILED' })
    </h2>
    
    <table>
        <tr>
            <th>Check</th>
            <th>Status</th>
        </tr>
        <tr>
            <td>Azure/Intune Enrollment</td>
            <td class="$(if ($validationResults.EnrolledToIntuneOrAzure) { 'pass' } else { 'fail' })">
                $(if ($validationResults.EnrolledToIntuneOrAzure) { 'PASS' } else { 'FAIL' })
            </td>
        </tr>
        <tr>
            <td>Workspace ONE Removed</td>
            <td class="$(if ($validationResults.WorkspaceOneRemoved) { 'pass' } else { 'fail' })">
                $(if ($validationResults.WorkspaceOneRemoved) { 'PASS' } else { 'FAIL' })
            </td>
        </tr>
        <tr>
            <td>Intune Policies Applied</td>
            <td class="$(if ($validationResults.PoliciesApplied) { 'pass' } else { 'fail' })">
                $(if ($validationResults.PoliciesApplied) { 'PASS' } else { 'FAIL' })
            </td>
        </tr>
        <tr>
            <td>Required Apps Installed</td>
            <td class="$(if ($validationResults.RequiredAppsInstalled) { 'pass' } else { 'fail' })">
                $(if ($validationResults.RequiredAppsInstalled) { 'PASS' } else { 'FAIL' })
            </td>
        </tr>
    </table>
    
    $(if ($validationResults.Issues.Count -gt 0) {
    @"
    <h2>Issues Found:</h2>
    <ul>
        $(foreach ($issue in $validationResults.Issues) {
            "<li>$issue</li>"
        })
    </ul>
"@
    })
    
    <p>For detailed logs, check: $logPath</p>
</body>
</html>
"@
        
        $htmlReport | Out-File -FilePath $reportPath -Force
        Write-Host "`nReport generated: $reportPath" -ForegroundColor Cyan
        
        # Open the report
        try {
            Start-Process $reportPath
        } catch {
            Write-LogMessage -Message "Unable to open report automatically: $_" -Level WARNING
        }
    }
}
catch {
    Write-LogMessage -Message "Error during migration validation: $_" -Level ERROR
    Write-Host "Error during migration validation: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Ensure transcript is stopped if it was started
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Transcript might not be running
    }
} 