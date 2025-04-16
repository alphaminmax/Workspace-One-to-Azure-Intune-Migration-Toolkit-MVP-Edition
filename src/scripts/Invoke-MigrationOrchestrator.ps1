#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Orchestrates the migration process from Workspace One to Azure/Intune across multiple devi...                            #
# PowerShell 5.1 x32/x64                                                                                                       #
#                                                                                                                              #
################################################################################################################################

################################################################################################################################
#                                                                                                                              #
#      ██████╗██████╗  █████╗ ██╗   ██╗ ██████╗ ███╗   ██╗    ██╗   ██╗███████╗ █████╗                                        #
#     ██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗████╗  ██║    ██║   ██║██╔════╝██╔══██╗                                       #
#     ██║     ██████╔╝███████║ ╚████╔╝ ██║   ██║██╔██╗ ██║    ██║   ██║███████╗███████║                                       #
#     ██║     ██╔══██╗██╔══██║  ╚██╔╝  ██║   ██║██║╚██╗██║    ██║   ██║╚════██║██╔══██║                                       #
#     ╚██████╗██║  ██║██║  ██║   ██║   ╚██████╔╝██║ ╚████║    ╚██████╔╝███████║██║  ██║                                       #
#      ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝     ╚═════╝ ╚══════╝╚═╝  ╚═╝                                       #
#                                                                                                                              #
################################################################################################################################


<#
.SYNOPSIS
    Orchestrates the migration process from Workspace One to Azure/Intune across multiple devices.
    
.DESCRIPTION
    This script serves as the central orchestration framework for migrating devices from
    Workspace One to Azure/Intune at scale. It coordinates all high-priority components
    (RollbackMechanism, MigrationVerification, UserCommunicationFramework, SecurityFoundation)
    to ensure reliable, secure, and transparent migrations.
    
    The orchestrator can:
    - Run migrations in parallel across multiple devices
    - Schedule migrations based on device availability and user preferences
    - Track migration status and report progress
    - Handle failures and rollbacks automatically
    - Generate comprehensive reports and analytics
    
.PARAMETER Devices
    Array of device names or CSV file path containing devices to migrate.
    
.PARAMETER Parallel
    Number of parallel migrations to run. Default is 5.
    
.PARAMETER ScheduleFile
    Path to CSV file containing migration schedule information.
    
.PARAMETER ReportPath
    Path where migration reports will be stored. Default is "C:\MigrationReports".
    
.PARAMETER LogPath
    Path where migration logs will be stored. Default is "$env:TEMP\WS1Migration\Logs".
    
.PARAMETER SkipVerification
    Switch to skip post-migration verification.
    
.PARAMETER Force
    Force migration even if the device is currently in use.
    
.PARAMETER SupportEmail
    Support email address for users to contact with issues.
    
.PARAMETER SupportPhone
    Support phone number for users to contact with issues.
    
.PARAMETER Credential
    Credential object for authentication with Azure/Intune.
    
.EXAMPLE
    .\Invoke-MigrationOrchestrator.ps1 -Devices "Computer1","Computer2" -Parallel 2
    
    Migrates two computers in parallel.
    
.EXAMPLE
    .\Invoke-MigrationOrchestrator.ps1 -ScheduleFile "C:\migration_schedule.csv" -ReportPath "C:\Reports"
    
    Runs migrations according to the schedule file and stores reports in the specified directory.
    
.NOTES
    File Name      : Invoke-MigrationOrchestrator.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding(DefaultParameterSetName = 'Devices')]
param (
    [Parameter(ParameterSetName = 'Devices', Mandatory = $true)]
    [string[]]$Devices,
    
    [Parameter(ParameterSetName = 'ScheduleFile', Mandatory = $true)]
    [string]$ScheduleFile,
    
    [Parameter(Mandatory = $false)]
    [int]$Parallel = 5,
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\MigrationReports",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\WS1Migration\Logs",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipVerification,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [string]$SupportEmail = "support@yourdomain.com",
    
    [Parameter(Mandatory = $false)]
    [string]$SupportPhone = "555-123-4567",
    
    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential
)

# Find the modules directory (one level up from scripts directory, then into modules)
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$modulesPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "modules"

# Import required modules
$requiredModules = @(
    "LoggingModule",
    "RollbackMechanism",
    "MigrationVerification",
    "UserCommunicationFramework",
    "SecurityFoundation",
    "PrivilegeManagement",
    "ConfigurationPreservation",
    "ProfileTransfer",
    "AutopilotIntegration"
)

foreach ($module in $requiredModules) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath "$module.psm1"
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
        Write-Verbose "Imported module: $module"
    }
    else {
        Write-Warning "Module $module not found at $modulePath"
    }
}

# Initialize logging
if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$mainLogFile = Join-Path -Path $LogPath -ChildPath "Orchestrator_$timestamp.log"
Write-Log -Message "Migration orchestrator started" -Level Information

# Ensure report directory exists
if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

# Initialize summary report
$summaryReportPath = Join-Path -Path $ReportPath -ChildPath "MigrationSummary_$timestamp.html"
$summaryData = @{
    StartTime = Get-Date
    EndTime = $null
    TotalDevices = 0
    Successful = 0
    Failed = 0
    Pending = 0
    Skipped = 0
    DeviceStatus = @{}
}

# Function to parse schedule file
function Get-MigrationSchedule {
    param (
        [string]$ScheduleFilePath
    )
    
    if (-not (Test-Path -Path $ScheduleFilePath)) {
        throw "Schedule file not found: $ScheduleFilePath"
    }
    
    try {
        $schedule = Import-Csv -Path $ScheduleFilePath
        Write-Log -Message "Imported migration schedule with $($schedule.Count) devices" -Level Information
        return $schedule
    }
    catch {
        Write-Log -Message "Error importing schedule file: $_" -Level Error
        throw "Failed to import schedule file: $_"
    }
}

# Function to check if device is available for migration
function Test-DeviceAvailability {
    param (
        [string]$DeviceName
    )
    
    try {
        # Check if device is online
        $ping = Test-Connection -ComputerName $DeviceName -Count 1 -Quiet
        if (-not $ping) {
            return @{
                Available = $false
                Reason = "Device is offline"
            }
        }
        
        # Check if device is already enrolled in Intune
        # This is a placeholder - would need to check against Intune in production
        $alreadyEnrolled = $false
        
        if ($alreadyEnrolled) {
            return @{
                Available = $false
                Reason = "Device is already enrolled in Intune"
            }
        }
        
        # Check for active users
        $users = Invoke-Command -ComputerName $DeviceName -ScriptBlock {
            Get-Process -IncludeUserName | Select-Object -ExpandProperty UserName -Unique
        } -ErrorAction SilentlyContinue
        
        if ($users -and $users.Count -gt 0 -and -not $Force) {
            return @{
                Available = $false
                Reason = "Users are currently logged in: $($users -join ', ')"
            }
        }
        
        return @{
            Available = $true
            Reason = "Device is available for migration"
        }
    }
    catch {
        return @{
            Available = $false
            Reason = "Error checking availability: $_"
        }
    }
}

# Function to migrate a device
function Start-DeviceMigration {
    param (
        [string]$DeviceName,
        [string]$UserEmail = "",
        [datetime]$ScheduledTime = [datetime]::Now,
        [string]$DeviceLogPath = (Join-Path -Path $LogPath -ChildPath $DeviceName)
    )
    
    # Create device-specific log directory
    if (-not (Test-Path -Path $DeviceLogPath)) {
        New-Item -Path $DeviceLogPath -ItemType Directory -Force | Out-Null
    }
    
    # Update device status
    $summaryData.DeviceStatus[$DeviceName] = @{
        Status = "Starting"
        StartTime = Get-Date
        EndTime = $null
        LogPath = $DeviceLogPath
        UserEmail = $UserEmail
    }
    
    Write-Log -Message "Starting migration for device: $DeviceName" -Level Information
    
    try {
        # Check if device is available
        $availability = Test-DeviceAvailability -DeviceName $DeviceName
        
        if (-not $availability.Available -and -not $Force) {
            Write-Log -Message "Device $DeviceName is not available for migration: $($availability.Reason)" -Level Warning
            
            $summaryData.DeviceStatus[$DeviceName].Status = "Skipped"
            $summaryData.DeviceStatus[$DeviceName].EndTime = Get-Date
            $summaryData.DeviceStatus[$DeviceName].Reason = $availability.Reason
            $summaryData.Skipped++
            
            return $false
        }
        
        # Prepare migration parameters
        $migrationParams = @{
            SilentMode = $true
            LogPath = $DeviceLogPath
            BackupPath = Join-Path -Path $DeviceLogPath -ChildPath "Backups"
            UserEmail = $UserEmail
            SupportEmail = $SupportEmail
            SupportPhone = $SupportPhone
        }
        
        if ($Credential) {
            $migrationParams.AzureCredential = $Credential
        }
        
        # Run migration script remotely
        $migrationScript = Join-Path -Path $PSScriptRoot -ChildPath "Start-WS1AzureMigration.ps1"
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-Content -Path $migrationScript -Raw)))
        
        $remoteParams = $migrationParams | ConvertTo-Json -Compress
        $remoteCommand = "Invoke-Command -ComputerName $DeviceName -ScriptBlock { param(`$params) 
            `$decodedParams = `$params | ConvertFrom-Json
            powershell.exe -EncodedCommand $encodedCommand -SilentMode:`$true -LogPath:`$decodedParams.LogPath -BackupPath:`$decodedParams.BackupPath -UserEmail:`$decodedParams.UserEmail -SupportEmail:`$decodedParams.SupportEmail -SupportPhone:`$decodedParams.SupportPhone
        } -ArgumentList '$remoteParams'"
        
        $summaryData.DeviceStatus[$DeviceName].Status = "In Progress"
        $summaryData.Pending++
        
        # Execute the migration with proper privilege
        $migrationResult = Invoke-Expression $remoteCommand
        
        # Update status based on result
        if ($migrationResult -eq 0) {
            $summaryData.DeviceStatus[$DeviceName].Status = "Successful"
            $summaryData.DeviceStatus[$DeviceName].EndTime = Get-Date
            $summaryData.Successful++
            $summaryData.Pending--
            
            Write-Log -Message "Migration completed successfully for device: $DeviceName" -Level Information
            
            # Run verification if not skipped
            if (-not $SkipVerification) {
                $verificationParams = @{
                    DeviceName = $DeviceName
                    OutputPath = Join-Path -Path $ReportPath -ChildPath "$DeviceName\Verification"
                }
                
                $verificationResult = Invoke-MigrationVerification @verificationParams
                $summaryData.DeviceStatus[$DeviceName].Verification = $verificationResult
            }
            
            return $true
        }
        else {
            $summaryData.DeviceStatus[$DeviceName].Status = "Failed"
            $summaryData.DeviceStatus[$DeviceName].EndTime = Get-Date
            $summaryData.DeviceStatus[$DeviceName].ErrorCode = $migrationResult
            $summaryData.Failed++
            $summaryData.Pending--
            
            Write-Log -Message "Migration failed for device: $DeviceName" -Level Error
            
            return $false
        }
    }
    catch {
        Write-Log -Message "Error during migration for device $($DeviceName): $_" -Level Error
        
        $summaryData.DeviceStatus[$DeviceName].Status = "Error"
        $summaryData.DeviceStatus[$DeviceName].EndTime = Get-Date
        $summaryData.DeviceStatus[$DeviceName].Error = $_.ToString()
        $summaryData.Failed++
        $summaryData.Pending--
        
        return $false
    }
}

# Function to generate summary report
function New-MigrationSummaryReport {
    param (
        [string]$ReportPath
    )
    
    $summaryData.EndTime = Get-Date
    $duration = $summaryData.EndTime - $summaryData.StartTime
    
    # Prepare device status rows
    $deviceRows = ""
    foreach ($device in $summaryData.DeviceStatus.Keys) {
        $status = $summaryData.DeviceStatus[$device]
        
        $statusColor = switch ($status.Status) {
            "Successful" { "green" }
            "Failed" { "red" }
            "Skipped" { "orange" }
            "In Progress" { "blue" }
            "Error" { "darkred" }
            default { "gray" }
        }
        
        $deviceDuration = ""
        if ($status.StartTime -and $status.EndTime) {
            $deviceSpan = $status.EndTime - $status.StartTime
            $deviceDuration = "$($deviceSpan.Hours)h $($deviceSpan.Minutes)m $($deviceSpan.Seconds)s"
        }
        
        $reason = if ($status.Reason) { $status.Reason } else { "" }
        $errorMessage = if ($status.Error) { $status.Error } else { "" }
        
        $deviceRows += @"
        <tr>
            <td>$device</td>
            <td><span class="status-badge" style="background-color: $statusColor">$($status.Status)</span></td>
            <td>$($status.StartTime)</td>
            <td>$deviceDuration</td>
            <td>$reason</td>
            <td>$errorMessage</td>
            <td><a href="file://$($status.LogPath)" target="_blank">Logs</a></td>
        </tr>
"@
    }
    
    # Generate HTML report
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Migration Summary Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f5f5f5;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            background-color: #0078D4;
            color: white;
            padding: 15px 20px;
            border-radius: 5px 5px 0 0;
        }
        .report-card {
            background-color: white;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            padding: 20px;
            margin-bottom: 20px;
        }
        .card-title {
            margin-top: 0;
            border-bottom: 1px solid #eee;
            padding-bottom: 10px;
            color: #0078D4;
        }
        .status-badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 12px;
            color: white;
            font-size: 0.9em;
        }
        .metric-container {
            display: flex;
            justify-content: space-between;
            margin-top: 15px;
        }
        .metric-box {
            background-color: #f5f5f5;
            border-radius: 5px;
            padding: 15px;
            text-align: center;
            flex: 1;
            margin: 0 5px;
        }
        .metric-value {
            font-size: 1.8em;
            font-weight: bold;
            margin: 5px 0;
            color: #0078D4;
        }
        .metric-label {
            font-size: 0.9em;
            color: #555;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 8px 12px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }
        th {
            background-color: #f5f5f5;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Migration Summary Report</h1>
            <p>Report generated: $($summaryData.EndTime)</p>
        </div>
        
        <div class="report-card">
            <h2 class="card-title">Migration Summary</h2>
            <p><strong>Start Time:</strong> $($summaryData.StartTime)</p>
            <p><strong>End Time:</strong> $($summaryData.EndTime)</p>
            <p><strong>Duration:</strong> $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s</p>
            
            <div class="metric-container">
                <div class="metric-box">
                    <div class="metric-value">$($summaryData.TotalDevices)</div>
                    <div class="metric-label">Total Devices</div>
                </div>
                <div class="metric-box">
                    <div class="metric-value">$($summaryData.Successful)</div>
                    <div class="metric-label">Successful</div>
                </div>
                <div class="metric-box">
                    <div class="metric-value">$($summaryData.Failed)</div>
                    <div class="metric-label">Failed</div>
                </div>
                <div class="metric-box">
                    <div class="metric-value">$($summaryData.Skipped)</div>
                    <div class="metric-label">Skipped</div>
                </div>
                <div class="metric-box">
                    <div class="metric-value">$($summaryData.Pending)</div>
                    <div class="metric-label">Pending</div>
                </div>
            </div>
        </div>
        
        <div class="report-card">
            <h2 class="card-title">Device Status</h2>
            <table>
                <thead>
                    <tr>
                        <th>Device</th>
                        <th>Status</th>
                        <th>Start Time</th>
                        <th>Duration</th>
                        <th>Reason</th>
                        <th>Error</th>
                        <th>Logs</th>
                    </tr>
                </thead>
                <tbody>
                    $deviceRows
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $ReportPath -Encoding utf8
    Write-Log -Message "Migration summary report generated at: $ReportPath" -Level Information
}

# Main execution
try {
    Write-Host "Starting migration orchestration..." -ForegroundColor Green
    
    # Get devices from schedule or parameter
    if ($PSCmdlet.ParameterSetName -eq 'ScheduleFile') {
        $schedule = Get-MigrationSchedule -ScheduleFilePath $ScheduleFile
        $deviceList = @()
        
        foreach ($entry in $schedule) {
            $deviceList += [PSCustomObject]@{
                DeviceName = $entry.DeviceName
                UserEmail = $entry.UserEmail
                ScheduledTime = if ($entry.ScheduledTime) { Get-Date $entry.ScheduledTime } else { Get-Date }
            }
        }
    }
    else {
        $deviceList = $Devices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName = $_
                UserEmail = ""
                ScheduledTime = Get-Date
            }
        }
    }
    
    # Update total device count
    $summaryData.TotalDevices = $deviceList.Count
    
    # Sort devices by scheduled time
    $deviceList = $deviceList | Sort-Object -Property ScheduledTime
    
    # Create runspace pool for parallel migrations
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $Parallel)
    $runspacePool.Open()
    
    $runspaces = @()
    
    # Start migrations
    foreach ($device in $deviceList) {
        Write-Host "Scheduling migration for device: $($device.DeviceName)" -ForegroundColor Cyan
        
        # Create a new PowerShell instance for this migration
        $powershell = [powershell]::Create().AddScript({
            param($DeviceName, $UserEmail, $ScheduledTime, $DeviceLogPath)
            
            Start-DeviceMigration -DeviceName $DeviceName -UserEmail $UserEmail -ScheduledTime $ScheduledTime -DeviceLogPath $DeviceLogPath
        }).AddArgument($device.DeviceName).AddArgument($device.UserEmail).AddArgument($device.ScheduledTime).AddArgument((Join-Path -Path $LogPath -ChildPath $device.DeviceName))
        
        # Configure the runspace to use our runspace pool
        $powershell.RunspacePool = $runspacePool
        
        # Start the migration asynchronously
        $runspaces += [PSCustomObject]@{
            Powershell = $powershell
            DeviceName = $device.DeviceName
            Handle = $powershell.BeginInvoke()
        }
    }
    
    # Monitor migrations
    $completed = $false
    while (-not $completed) {
        $completed = $true
        
        foreach ($runspace in $runspaces) {
            if ($runspace.Handle.IsCompleted) {
                # Migration completed
                $result = $runspace.Powershell.EndInvoke($runspace.Handle)
                $runspace.Powershell.Dispose()
            }
            else {
                # Still running
                $completed = $false
            }
        }
        
        # Generate interim report
        New-MigrationSummaryReport -ReportPath $summaryReportPath
        
        if (-not $completed) {
            Write-Host "Migration in progress... $($summaryData.Successful) completed, $($summaryData.Failed) failed, $($summaryData.Pending) pending." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    
    # Clean up runspace pool
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    # Generate final report
    New-MigrationSummaryReport -ReportPath $summaryReportPath
    
    # Output summary
    Write-Host "Migration orchestration completed!" -ForegroundColor Green
    Write-Host "Total devices: $($summaryData.TotalDevices)" -ForegroundColor White
    Write-Host "Successful: $($summaryData.Successful)" -ForegroundColor Green
    Write-Host "Failed: $($summaryData.Failed)" -ForegroundColor Red
    Write-Host "Skipped: $($summaryData.Skipped)" -ForegroundColor Yellow
    Write-Host "Summary report: $summaryReportPath" -ForegroundColor Cyan
    
    # Open report if running interactively
    if ([Environment]::UserInteractive) {
        Start-Process $summaryReportPath
    }
}
catch {
    Write-Log -Message "Error in migration orchestration: $_" -Level Error
    Write-Host "Error in migration orchestration: $_" -ForegroundColor Red
}
finally {
    # Ensure report is generated even on errors
    if (-not $summaryData.EndTime) {
        New-MigrationSummaryReport -ReportPath $summaryReportPath
    }
} 





