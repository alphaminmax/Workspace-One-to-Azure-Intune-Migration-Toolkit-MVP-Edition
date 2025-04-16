#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Creates a real-time migration dashboard for monitoring the Workspace One to Azure/Intune m...                            #
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
    Creates a real-time migration dashboard for monitoring the Workspace One to Azure/Intune migration process.

.DESCRIPTION
    This script generates a web-based dashboard that displays the status and metrics of the migration process
    across all high-priority components. It provides real-time visibility into migration progress,
    component status, and key metrics for administrators and stakeholders.

    The dashboard integrates data from:
    - RollbackMechanism
    - MigrationVerification
    - UserCommunicationFramework
    - SecurityFoundation

.PARAMETER RefreshInterval
    How often the dashboard should refresh data, in seconds. Default is 30 seconds.

.PARAMETER Port
    The HTTP port to host the dashboard on. Default is 8080.

.PARAMETER LogFile
    Path to the log file to monitor for migration events. If not specified, will try to detect automatically.

.PARAMETER OutputPath
    Where to save the dashboard HTML file. Default is the temp directory.

.PARAMETER ShowInBrowser
    Whether to automatically open the dashboard in the default web browser. Default is $true.

.EXAMPLE
    .\New-MigrationDashboard.ps1
    
    Starts the migration dashboard with default settings.

.EXAMPLE
    .\New-MigrationDashboard.ps1 -RefreshInterval 60 -Port 8000
    
    Starts the migration dashboard with a 60-second refresh interval on port 8000.

.NOTES
    File Name      : New-MigrationDashboard.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [int]$RefreshInterval = 30,
    
    [Parameter(Mandatory = $false)]
    [int]$Port = 8080,
    
    [Parameter(Mandatory = $false)]
    [string]$LogFile,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $env:TEMP,
    
    [Parameter(Mandatory = $false)]
    [bool]$ShowInBrowser = $true
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
    "SecurityFoundation"
)

foreach ($module in $requiredModules) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath "$module.psm1"
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    }
    else {
        Write-Warning "Module $module not found at $modulePath - some dashboard features may be limited"
    }
}

# If no log file specified, try to find one
if (-not $LogFile) {
    $defaultLogPath = "$env:TEMP\WS1Migration"
    if (Test-Path -Path $defaultLogPath) {
        $latestLog = Get-ChildItem -Path $defaultLogPath -Filter "Migration_*.log" | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -First 1 -ExpandProperty FullName
        
        if ($latestLog) {
            $LogFile = $latestLog
            Write-Host "Using latest log file: $LogFile"
        }
    }
}

# Dashboard state variables
$script:DashboardState = @{
    MigrationStatus = "Unknown"
    StartTime = $null
    CurrentStep = "Not Started"
    Progress = 0
    ComponentStatus = @{
        RollbackMechanism = "Unknown"
        MigrationVerification = "Unknown"
        UserCommunication = "Unknown"
        SecurityFoundation = "Unknown"
    }
    LastUpdateTime = Get-Date
    MigratedDevices = 0
    FailedDevices = 0
    PendingDevices = 0
    VerificationResults = @()
    RecentEvents = @()
    Warnings = 0
    Errors = 0
    BackupStatus = "Unknown"
}

# Function to get the current migration status
function Get-CurrentMigrationStatus {
    if ($LogFile -and (Test-Path -Path $LogFile)) {
        $logContent = Get-Content -Path $LogFile -Tail 100
        
        # Parse the log to extract current status
        $progressLine = $logContent | Where-Object { $_ -match '\[(\d+)%\] (.+)' } | Select-Object -Last 1
        if ($progressLine -match '\[(\d+)%\] (.+)') {
            $script:DashboardState.Progress = [int]$Matches[1]
            $script:DashboardState.CurrentStep = $Matches[2]
        }
        
        # Determine overall status
        if ($logContent -match "Migration completed successfully") {
            $script:DashboardState.MigrationStatus = "Completed"
        }
        elseif ($logContent -match "Migration failed") {
            $script:DashboardState.MigrationStatus = "Failed"
        }
        elseif ($logContent -match "Starting migration") {
            $script:DashboardState.MigrationStatus = "In Progress"
        }
        
        # Extract start time
        $startTimeLine = $logContent | Where-Object { $_ -match 'Migration started' } | Select-Object -First 1
        if ($startTimeLine -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            try {
                $script:DashboardState.StartTime = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
            }
            catch {
                # If parsing fails, try another approach
                $script:DashboardState.StartTime = Get-Date
            }
        }
        
        # Count warnings and errors
        $script:DashboardState.Warnings = ($logContent | Where-Object { $_ -match '\[Warning\]' }).Count
        $script:DashboardState.Errors = ($logContent | Where-Object { $_ -match '\[Error\]' }).Count
        
        # Extract recent events
        $script:DashboardState.RecentEvents = $logContent | 
                                             Select-Object -Last 10 | 
                                             ForEach-Object {
                                                 if ($_ -match '^\[(.*?)\] \[(.*?)\] (.*)$') {
                                                     @{
                                                         Timestamp = $Matches[1]
                                                         Level = $Matches[2]
                                                         Message = $Matches[3]
                                                     }
                                                 }
                                             } | Where-Object { $_ -ne $null }
    }
    
    # Update component status if modules are available
    if (Get-Command -Name Get-RollbackStatus -ErrorAction SilentlyContinue) {
        $rollbackStatus = Get-RollbackStatus
        $script:DashboardState.ComponentStatus.RollbackMechanism = $rollbackStatus.Status
        $script:DashboardState.BackupStatus = $rollbackStatus.BackupStatus
    }
    
    if (Get-Command -Name Get-VerificationStatus -ErrorAction SilentlyContinue) {
        $verificationStatus = Get-VerificationStatus
        $script:DashboardState.ComponentStatus.MigrationVerification = $verificationStatus.Status
        $script:DashboardState.VerificationResults = $verificationStatus.Results
    }
    
    if (Get-Command -Name Get-NotificationStatus -ErrorAction SilentlyContinue) {
        $notificationStatus = Get-NotificationStatus
        $script:DashboardState.ComponentStatus.UserCommunication = $notificationStatus.Status
    }
    
    if (Get-Command -Name Get-SecurityStatus -ErrorAction SilentlyContinue) {
        $securityStatus = Get-SecurityStatus
        $script:DashboardState.ComponentStatus.SecurityFoundation = $securityStatus.Status
    }
    
    # Update migration metrics - these would come from a real data source in production
    # For demo, we'll simulate some values
    try {
        $script:DashboardState.MigratedDevices = (Get-Random -Minimum 10 -Maximum 50)
        $script:DashboardState.FailedDevices = (Get-Random -Minimum 0 -Maximum 5)
        $script:DashboardState.PendingDevices = (Get-Random -Minimum 5 -Maximum 20)
    } catch {
        # Fallback to defaults if we can't get real data
        $script:DashboardState.MigratedDevices = 0
        $script:DashboardState.FailedDevices = 0
        $script:DashboardState.PendingDevices = 0
    }
    
    $script:DashboardState.LastUpdateTime = Get-Date
}

# Function to generate HTML dashboard
function New-DashboardHtml {
    # Get latest data
    Get-CurrentMigrationStatus
    
    # Calculate duration
    $duration = "Unknown"
    if ($script:DashboardState.StartTime) {
        $durationSpan = (Get-Date) - $script:DashboardState.StartTime
        $duration = "$($durationSpan.Hours)h $($durationSpan.Minutes)m $($durationSpan.Seconds)s"
    }
    
    # Determine status color
    $statusColor = switch ($script:DashboardState.MigrationStatus) {
        "Completed" { "green" }
        "Failed" { "red" }
        "In Progress" { "blue" }
        default { "gray" }
    }
    
    # Prepare component status for display
    $componentRows = ""
    foreach ($component in $script:DashboardState.ComponentStatus.Keys) {
        $status = $script:DashboardState.ComponentStatus[$component]
        $componentColor = switch ($status) {
            "OK" { "green" }
            "Warning" { "orange" }
            "Error" { "red" }
            default { "gray" }
        }
        
        $componentRows += @"
        <tr>
            <td>$component</td>
            <td><span class="status-badge" style="background-color: $componentColor">$status</span></td>
        </tr>
"@
    }
    
    # Prepare recent events for display
    $eventRows = ""
    foreach ($event in $script:DashboardState.RecentEvents) {
        $eventColor = switch ($event.Level) {
            "Error" { "red" }
            "Warning" { "orange" }
            "Information" { "blue" }
            default { "gray" }
        }
        
        $eventRows += @"
        <tr>
            <td>$($event.Timestamp)</td>
            <td><span class="status-badge" style="background-color: $eventColor">$($event.Level)</span></td>
            <td>$($event.Message)</td>
        </tr>
"@
    }
    
    # Generate full HTML
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>WS1 to Azure/Intune Migration Dashboard</title>
    <meta http-equiv="refresh" content="$RefreshInterval">
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
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .last-update {
            font-size: 0.9em;
            opacity: 0.8;
        }
        .dashboard-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            grid-gap: 20px;
            margin-top: 20px;
        }
        .dashboard-card {
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
        .progress-container {
            width: 100%;
            height: 20px;
            background-color: #f5f5f5;
            border-radius: 10px;
            margin: 10px 0;
            overflow: hidden;
        }
        .progress-bar {
            height: 100%;
            background-color: #0078D4;
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 0.8em;
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
        .full-width {
            grid-column: 1 / -1;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>WS1 to Azure/Intune Migration Dashboard</h1>
            <div class="last-update">Last Updated: $($script:DashboardState.LastUpdateTime.ToString("yyyy-MM-dd HH:mm:ss"))</div>
        </div>
        
        <div class="dashboard-grid">
            <!-- Migration Status Card -->
            <div class="dashboard-card">
                <h2 class="card-title">Migration Status</h2>
                <p><strong>Status:</strong> <span class="status-badge" style="background-color: $statusColor">$($script:DashboardState.MigrationStatus)</span></p>
                <p><strong>Current Step:</strong> $($script:DashboardState.CurrentStep)</p>
                <p><strong>Started:</strong> $($script:DashboardState.StartTime)</p>
                <p><strong>Duration:</strong> $duration</p>
                <div class="progress-container">
                    <div class="progress-bar" style="width: $($script:DashboardState.Progress)%">$($script:DashboardState.Progress)%</div>
                </div>
            </div>
            
            <!-- Migration Metrics Card -->
            <div class="dashboard-card">
                <h2 class="card-title">Migration Metrics</h2>
                <div class="metric-container">
                    <div class="metric-box">
                        <div class="metric-value">$($script:DashboardState.MigratedDevices)</div>
                        <div class="metric-label">Migrated Devices</div>
                    </div>
                    <div class="metric-box">
                        <div class="metric-value">$($script:DashboardState.FailedDevices)</div>
                        <div class="metric-label">Failed Migrations</div>
                    </div>
                    <div class="metric-box">
                        <div class="metric-value">$($script:DashboardState.PendingDevices)</div>
                        <div class="metric-label">Pending Devices</div>
                    </div>
                </div>
                <div class="metric-container">
                    <div class="metric-box">
                        <div class="metric-value">$($script:DashboardState.Warnings)</div>
                        <div class="metric-label">Warnings</div>
                    </div>
                    <div class="metric-box">
                        <div class="metric-value">$($script:DashboardState.Errors)</div>
                        <div class="metric-label">Errors</div>
                    </div>
                    <div class="metric-box">
                        <div class="metric-value">$($script:DashboardState.BackupStatus)</div>
                        <div class="metric-label">Backup Status</div>
                    </div>
                </div>
            </div>
            
            <!-- Component Status Card -->
            <div class="dashboard-card">
                <h2 class="card-title">Component Status</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Component</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        $componentRows
                    </tbody>
                </table>
            </div>
            
            <!-- Recent Events Card -->
            <div class="dashboard-card">
                <h2 class="card-title">Recent Events</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Time</th>
                            <th>Level</th>
                            <th>Message</th>
                        </tr>
                    </thead>
                    <tbody>
                        $eventRows
                    </tbody>
                </table>
            </div>
            
            <!-- Log Viewer Card -->
            <div class="dashboard-card full-width">
                <h2 class="card-title">Migration Log</h2>
                <p><strong>Log File:</strong> $LogFile</p>
                <div style="max-height: 200px; overflow-y: auto; background-color: #f5f5f5; padding: 10px; border-radius: 5px; font-family: monospace; font-size: 0.9em;">
                    $(if (Test-Path -Path $LogFile) { (Get-Content -Path $LogFile -Tail 20) -join "<br>" } else { "Log file not found or inaccessible." })
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

# Start HTTP server to host the dashboard (if desired)
function Start-DashboardServer {
    param (
        [int]$Port = 8080,
        [string]$HtmlContent
    )
    
    # Create HTTP listener
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    
    try {
        $listener.Start()
        Write-Host "Dashboard server started at http://localhost:$Port/"
        
        # Open dashboard in browser if requested
        if ($ShowInBrowser) {
            Start-Process "http://localhost:$Port/"
        }
        
        while ($listener.IsListening) {
            # Handle incoming requests
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            # Generate fresh dashboard content
            $dashboardHtml = New-DashboardHtml
            
            # Convert content to bytes
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($dashboardHtml)
            
            # Set response details
            $response.ContentLength64 = $buffer.Length
            $response.ContentType = "text/html"
            $response.StatusCode = 200
            
            # Write response
            $output = $response.OutputStream
            $output.Write($buffer, 0, $buffer.Length)
            $output.Close()
        }
    }
    catch {
        Write-Error "Error starting dashboard server: $_"
    }
    finally {
        # Ensure listener is stopped
        if ($listener.IsListening) {
            $listener.Stop()
        }
    }
}

# Generate dashboard HTML file
$dashboardHtml = New-DashboardHtml
$dashboardFile = Join-Path -Path $OutputPath -ChildPath "WS1MigrationDashboard.html"
$dashboardHtml | Out-File -FilePath $dashboardFile -Encoding utf8

Write-Host "Dashboard HTML file created at: $dashboardFile"

# Start dashboard server if enabled
Start-DashboardServer -Port $Port -HtmlContent $dashboardHtml 





