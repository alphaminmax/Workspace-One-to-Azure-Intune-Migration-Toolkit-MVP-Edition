#Requires -Version 5.1

<#
.SYNOPSIS
    Provides analytics capabilities for the Workspace One to Azure/Intune migration process.

.DESCRIPTION
    The MigrationAnalytics module collects, analyzes, and reports on migration metrics
    to provide insights into migration performance, success rates, and areas for improvement.
    
    This module integrates with other high-priority components to gather data and generate
    comprehensive reports and visualizations.

.NOTES
    File Name      : MigrationAnalytics.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

# Import required modules
if (-not (Get-Module -Name 'LoggingModule' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LoggingModule.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module LoggingModule.psm1 not found in $PSScriptRoot"
    }
}

# Script-level variables
$script:MetricsStorePath = Join-Path -Path $env:TEMP -ChildPath "MigrationAnalytics"
$script:MetricsFileName = "MigrationMetrics.json"
$script:ReportsPath = Join-Path -Path $env:TEMP -ChildPath "MigrationReports"

# Initialize module
function Initialize-MigrationAnalytics {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$MetricsPath,
        
        [Parameter(Mandatory = $false)]
        [string]$ReportsPath
    )
    
    # Set custom paths if provided
    if ($MetricsPath) {
        $script:MetricsStorePath = $MetricsPath
    }
    
    if ($ReportsPath) {
        $script:ReportsPath = $ReportsPath
    }
    
    # Ensure directories exist
    if (-not (Test-Path -Path $script:MetricsStorePath)) {
        New-Item -Path $script:MetricsStorePath -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path -Path $script:ReportsPath)) {
        New-Item -Path $script:ReportsPath -ItemType Directory -Force | Out-Null
    }
    
    # Initialize metrics store if it doesn't exist
    $metricsFile = Join-Path -Path $script:MetricsStorePath -ChildPath $script:MetricsFileName
    if (-not (Test-Path -Path $metricsFile)) {
        $initialMetrics = @{
            MigrationSummary = @{
                TotalMigrations = 0
                SuccessfulMigrations = 0
                FailedMigrations = 0
                AverageTime = 0
                FirstMigration = $null
                LastMigration = $null
            }
            DeviceMetrics = @{}
            ComponentMetrics = @{
                RollbackMechanism = @{
                    Invocations = 0
                    Successes = 0
                    Failures = 0
                }
                MigrationVerification = @{
                    Invocations = 0
                    Successes = 0
                    Failures = 0
                }
                UserCommunication = @{
                    Notifications = 0
                    FeedbackReceived = 0
                }
                SecurityFoundation = @{
                    Events = 0
                    Warnings = 0
                    Errors = 0
                }
            }
            ErrorCategories = @{}
            TimeDistribution = @{
                Planning = 0
                Backup = 0
                WS1Removal = 0
                AzureSetup = 0
                IntuneEnrollment = 0
                Verification = 0
                UserInteraction = 0
            }
        }
        
        $initialMetrics | ConvertTo-Json -Depth 10 | Out-File -FilePath $metricsFile -Encoding utf8
        Write-Log -Message "Initialized migration metrics store at $metricsFile" -Level Information
    }
    
    return $true
}

# Get all metrics
function Get-MigrationMetrics {
    [CmdletBinding()]
    param ()
    
    $metricsFile = Join-Path -Path $script:MetricsStorePath -ChildPath $script:MetricsFileName
    
    if (-not (Test-Path -Path $metricsFile)) {
        Write-Log -Message "Metrics file not found at $metricsFile. Initializing new metrics." -Level Warning
        Initialize-MigrationAnalytics | Out-Null
    }
    
    try {
        $metrics = Get-Content -Path $metricsFile -Raw | ConvertFrom-Json
        return $metrics
    }
    catch {
        Write-Log -Message "Error reading metrics file: $_" -Level Error
        return $null
    }
}

# Save metrics
function Save-MigrationMetrics {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Metrics
    )
    
    $metricsFile = Join-Path -Path $script:MetricsStorePath -ChildPath $script:MetricsFileName
    
    try {
        $Metrics | ConvertTo-Json -Depth 10 | Out-File -FilePath $metricsFile -Encoding utf8
        return $true
    }
    catch {
        Write-Log -Message "Error saving metrics file: $_" -Level Error
        return $false
    }
}

# Register a new migration with metrics
function Register-MigrationEvent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Started", "Completed", "Failed")]
        [string]$Status,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorCategory = "",
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = "",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$TimeMetrics = @{},
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ComponentUsage = @{}
    )
    
    $metrics = Get-MigrationMetrics
    $timestamp = Get-Date
    
    # Initialize device entry if it doesn't exist
    if (-not $metrics.DeviceMetrics.$DeviceName) {
        $metrics.DeviceMetrics.$DeviceName = @{
            FirstAttempt = $timestamp
            LastAttempt = $timestamp
            Attempts = 0
            Successes = 0
            Failures = 0
            LastStatus = ""
            ErrorHistory = @()
            TimeMetrics = @{}
        }
    }
    
    # Update device metrics
    $metrics.DeviceMetrics.$DeviceName.LastAttempt = $timestamp
    $metrics.DeviceMetrics.$DeviceName.Attempts++
    $metrics.DeviceMetrics.$DeviceName.LastStatus = $Status
    
    # Update status-specific metrics
    switch ($Status) {
        "Started" {
            # Just tracking the start - no additional metrics yet
        }
        "Completed" {
            $metrics.DeviceMetrics.$DeviceName.Successes++
            $metrics.MigrationSummary.SuccessfulMigrations++
            
            # If we have time metrics, store them
            if ($TimeMetrics.Count -gt 0) {
                $metrics.DeviceMetrics.$DeviceName.TimeMetrics = $TimeMetrics
                
                # Update global time distribution
                foreach ($phase in $TimeMetrics.Keys) {
                    if ($metrics.TimeDistribution.ContainsKey($phase)) {
                        # Calculate new average
                        $currentCount = $metrics.MigrationSummary.SuccessfulMigrations
                        $currentAvg = $metrics.TimeDistribution.$phase
                        $newValue = $TimeMetrics.$phase
                        
                        # Weighted average calculation
                        $metrics.TimeDistribution.$phase = (($currentAvg * ($currentCount - 1)) + $newValue) / $currentCount
                    }
                }
            }
        }
        "Failed" {
            $metrics.DeviceMetrics.$DeviceName.Failures++
            $metrics.MigrationSummary.FailedMigrations++
            
            # Record error information
            if (-not [string]::IsNullOrEmpty($ErrorCategory)) {
                # Add to device error history
                $metrics.DeviceMetrics.$DeviceName.ErrorHistory += @{
                    Timestamp = $timestamp
                    Category = $ErrorCategory
                    Message = $ErrorMessage
                }
                
                # Update global error categories
                if (-not $metrics.ErrorCategories.$ErrorCategory) {
                    $metrics.ErrorCategories.$ErrorCategory = 0
                }
                $metrics.ErrorCategories.$ErrorCategory++
            }
        }
    }
    
    # Update component usage metrics
    if ($ComponentUsage.Count -gt 0) {
        foreach ($component in $ComponentUsage.Keys) {
            $usage = $ComponentUsage.$component
            
            if ($metrics.ComponentMetrics.ContainsKey($component)) {
                $metrics.ComponentMetrics.$component.Invocations += $usage.Invocations
                $metrics.ComponentMetrics.$component.Successes += $usage.Successes
                $metrics.ComponentMetrics.$component.Failures += $usage.Failures
            }
        }
    }
    
    # Update global migration summary
    $metrics.MigrationSummary.TotalMigrations = $metrics.MigrationSummary.SuccessfulMigrations + $metrics.MigrationSummary.FailedMigrations
    
    if ($null -eq $metrics.MigrationSummary.FirstMigration) {
        $metrics.MigrationSummary.FirstMigration = $timestamp
    }
    
    $metrics.MigrationSummary.LastMigration = $timestamp
    
    # Save the updated metrics
    Save-MigrationMetrics -Metrics $metrics
    
    Write-Log -Message "Registered migration event for device $DeviceName with status $Status" -Level Information
    return $true
}

# Generate analytics report
function New-MigrationAnalyticsReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("HTML", "JSON", "CSV", "All")]
        [string]$Format = "HTML",
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDeviceDetails
    )
    
    $metrics = Get-MigrationMetrics
    
    if (-not $metrics) {
        Write-Log -Message "No metrics data available to generate report" -Level Warning
        return $null
    }
    
    # Use default output path if not specified
    if (-not $OutputPath) {
        $fileName = "MigrationAnalytics_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $OutputPath = Join-Path -Path $script:ReportsPath -ChildPath $fileName
    }
    
    # Calculate success rate
    $successRate = 0
    if ($metrics.MigrationSummary.TotalMigrations -gt 0) {
        $successRate = [math]::Round(($metrics.MigrationSummary.SuccessfulMigrations / $metrics.MigrationSummary.TotalMigrations) * 100, 1)
    }
    
    # Calculate duration between first and last migration
    $durationDays = 0
    if ($metrics.MigrationSummary.FirstMigration -and $metrics.MigrationSummary.LastMigration) {
        $firstDate = [datetime]$metrics.MigrationSummary.FirstMigration
        $lastDate = [datetime]$metrics.MigrationSummary.LastMigration
        $durationDays = ($lastDate - $firstDate).TotalDays
    }
    
    # Generate reports in requested format(s)
    $reportPaths = @()
    
    # HTML Report
    if ($Format -eq "HTML" -or $Format -eq "All") {
        $htmlPath = "$OutputPath.html"
        
        # Prepare device rows if needed
        $deviceRows = ""
        if ($IncludeDeviceDetails) {
            foreach ($device in $metrics.DeviceMetrics.PSObject.Properties) {
                $deviceName = $device.Name
                $deviceData = $device.Value
                
                $statusClass = switch ($deviceData.LastStatus) {
                    "Completed" { "success" }
                    "Failed" { "danger" }
                    default { "warning" }
                }
                
                $successRate = 0
                if ($deviceData.Attempts -gt 0) {
                    $successRate = [math]::Round(($deviceData.Successes / $deviceData.Attempts) * 100, 1)
                }
                
                $deviceRows += @"
                <tr>
                    <td>$deviceName</td>
                    <td class="text-$statusClass">$($deviceData.LastStatus)</td>
                    <td>$($deviceData.Attempts)</td>
                    <td>$($deviceData.Successes)</td>
                    <td>$($deviceData.Failures)</td>
                    <td>$successRate%</td>
                    <td>$($deviceData.LastAttempt)</td>
                </tr>
"@
            }
        }
        
        # Create HTML content
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Migration Analytics Report</title>
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
        .metric-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            grid-gap: 15px;
            margin: 20px 0;
        }
        .metric-box {
            background-color: #f8f9fa;
            border-radius: 5px;
            padding: 15px;
            text-align: center;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
            color: #0078D4;
        }
        .metric-label {
            font-size: 0.9em;
            color: #555;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 8px 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #f8f9fa;
        }
        .text-success { color: green; }
        .text-danger { color: red; }
        .text-warning { color: orange; }
        
        .chart-container {
            height: 300px;
            margin: 20px 0;
        }
        
        .progress {
            height: 20px;
            overflow: hidden;
            background-color: #f5f5f5;
            border-radius: 4px;
            box-shadow: inset 0 1px 2px rgba(0,0,0,.1);
            margin: 10px 0;
        }
        .progress-bar {
            float: left;
            width: 0;
            height: 100%;
            font-size: 12px;
            line-height: 20px;
            color: #fff;
            text-align: center;
            background-color: #0078D4;
        }
        .progress-bar-success { background-color: #5cb85c; }
        .progress-bar-danger { background-color: #d9534f; }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Migration Analytics Report</h1>
            <p>Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        </div>
        
        <!-- Summary Section -->
        <div class="report-card">
            <h2 class="card-title">Migration Summary</h2>
            
            <div class="metric-grid">
                <div class="metric-box">
                    <div class="metric-label">Total Migrations</div>
                    <div class="metric-value">$($metrics.MigrationSummary.TotalMigrations)</div>
                </div>
                <div class="metric-box">
                    <div class="metric-label">Successful Migrations</div>
                    <div class="metric-value">$($metrics.MigrationSummary.SuccessfulMigrations)</div>
                </div>
                <div class="metric-box">
                    <div class="metric-label">Failed Migrations</div>
                    <div class="metric-value">$($metrics.MigrationSummary.FailedMigrations)</div>
                </div>
                <div class="metric-box">
                    <div class="metric-label">Success Rate</div>
                    <div class="metric-value">$successRate%</div>
                </div>
            </div>
            
            <h3>Migration Progress</h3>
            <div class="progress">
                <div class="progress-bar progress-bar-success" style="width: $successRate%">
                    $successRate% Successful
                </div>
                <div class="progress-bar progress-bar-danger" style="width: $(100-$successRate)%">
                    $(100-$successRate)% Failed
                </div>
            </div>
            
            <p><strong>First Migration:</strong> $($metrics.MigrationSummary.FirstMigration)</p>
            <p><strong>Last Migration:</strong> $($metrics.MigrationSummary.LastMigration)</p>
            <p><strong>Duration:</strong> $([math]::Round($durationDays, 1)) days</p>
        </div>
        
        <!-- Component Performance -->
        <div class="report-card">
            <h2 class="card-title">Component Performance</h2>
            
            <div class="chart-container">
                <canvas id="componentChart"></canvas>
            </div>
            
            <table>
                <thead>
                    <tr>
                        <th>Component</th>
                        <th>Invocations</th>
                        <th>Successes</th>
                        <th>Failures</th>
                        <th>Success Rate</th>
                    </tr>
                </thead>
                <tbody>
"@

        # Add component rows
        foreach ($component in $metrics.ComponentMetrics.PSObject.Properties) {
            $componentName = $component.Name
            $componentData = $component.Value
            
            $componentSuccessRate = 0
            if ($componentData.Invocations -gt 0) {
                $componentSuccessRate = [math]::Round(($componentData.Successes / $componentData.Invocations) * 100, 1)
            }
            
            $htmlContent += @"
                    <tr>
                        <td>$componentName</td>
                        <td>$($componentData.Invocations)</td>
                        <td>$($componentData.Successes)</td>
                        <td>$($componentData.Failures)</td>
                        <td>$componentSuccessRate%</td>
                    </tr>
"@
        }
        
        $htmlContent += @"
                </tbody>
            </table>
        </div>
        
        <!-- Error Categories -->
        <div class="report-card">
            <h2 class="card-title">Error Analysis</h2>
            
            <div class="chart-container">
                <canvas id="errorChart"></canvas>
            </div>
            
            <table>
                <thead>
                    <tr>
                        <th>Error Category</th>
                        <th>Count</th>
                        <th>Percentage</th>
                    </tr>
                </thead>
                <tbody>
"@

        # Add error category rows
        $totalErrors = 0
        foreach ($errorCount in $metrics.ErrorCategories.PSObject.Properties.Value) {
            $totalErrors += $errorCount
        }
        
        foreach ($error in $metrics.ErrorCategories.PSObject.Properties) {
            $errorCategory = $error.Name
            $errorCount = $error.Value
            
            $errorPercentage = 0
            if ($totalErrors -gt 0) {
                $errorPercentage = [math]::Round(($errorCount / $totalErrors) * 100, 1)
            }
            
            $htmlContent += @"
                    <tr>
                        <td>$errorCategory</td>
                        <td>$errorCount</td>
                        <td>$errorPercentage%</td>
                    </tr>
"@
        }
        
        $htmlContent += @"
                </tbody>
            </table>
        </div>
"@

        # Add device details if requested
        if ($IncludeDeviceDetails) {
            $htmlContent += @"
        <!-- Device Details -->
        <div class="report-card">
            <h2 class="card-title">Device Details</h2>
            
            <table>
                <thead>
                    <tr>
                        <th>Device Name</th>
                        <th>Status</th>
                        <th>Attempts</th>
                        <th>Successes</th>
                        <th>Failures</th>
                        <th>Success Rate</th>
                        <th>Last Attempt</th>
                    </tr>
                </thead>
                <tbody>
                    $deviceRows
                </tbody>
            </table>
        </div>
"@
        }
        
        # Add charts and close HTML
        $htmlContent += @"
        <!-- Time Distribution -->
        <div class="report-card">
            <h2 class="card-title">Time Distribution</h2>
            
            <div class="chart-container">
                <canvas id="timeChart"></canvas>
            </div>
            
            <table>
                <thead>
                    <tr>
                        <th>Phase</th>
                        <th>Average Time (seconds)</th>
                    </tr>
                </thead>
                <tbody>
"@

        # Add time distribution rows
        foreach ($phase in $metrics.TimeDistribution.PSObject.Properties) {
            $phaseName = $phase.Name
            $phaseTime = [math]::Round($phase.Value, 1)
            
            $htmlContent += @"
                    <tr>
                        <td>$phaseName</td>
                        <td>$phaseTime</td>
                    </tr>
"@
        }
        
        $htmlContent += @"
                </tbody>
            </table>
        </div>
    </div>
    
    <script>
        // Component Performance Chart
        const componentCtx = document.getElementById('componentChart').getContext('2d');
        new Chart(componentCtx, {
            type: 'bar',
            data: {
                labels: [$(($metrics.ComponentMetrics.PSObject.Properties.Name | ForEach-Object { "'$_'" }) -join ', ')],
                datasets: [
                    {
                        label: 'Successes',
                        data: [$(($metrics.ComponentMetrics.PSObject.Properties.Value | ForEach-Object { $_.Successes }) -join ', ')],
                        backgroundColor: 'rgba(92, 184, 92, 0.5)',
                        borderColor: 'rgba(92, 184, 92, 1)',
                        borderWidth: 1
                    },
                    {
                        label: 'Failures',
                        data: [$(($metrics.ComponentMetrics.PSObject.Properties.Value | ForEach-Object { $_.Failures }) -join ', ')],
                        backgroundColor: 'rgba(217, 83, 79, 0.5)',
                        borderColor: 'rgba(217, 83, 79, 1)',
                        borderWidth: 1
                    }
                ]
            },
            options: {
                scales: {
                    y: {
                        beginAtZero: true
                    }
                },
                responsive: true,
                maintainAspectRatio: false
            }
        });
        
        // Error Categories Chart
        const errorCtx = document.getElementById('errorChart').getContext('2d');
        new Chart(errorCtx, {
            type: 'pie',
            data: {
                labels: [$(($metrics.ErrorCategories.PSObject.Properties.Name | ForEach-Object { "'$_'" }) -join ', ')],
                datasets: [{
                    data: [$(($metrics.ErrorCategories.PSObject.Properties.Value) -join ', ')],
                    backgroundColor: [
                        'rgba(255, 99, 132, 0.5)',
                        'rgba(54, 162, 235, 0.5)',
                        'rgba(255, 206, 86, 0.5)',
                        'rgba(75, 192, 192, 0.5)',
                        'rgba(153, 102, 255, 0.5)',
                        'rgba(255, 159, 64, 0.5)'
                    ],
                    borderColor: [
                        'rgba(255, 99, 132, 1)',
                        'rgba(54, 162, 235, 1)',
                        'rgba(255, 206, 86, 1)',
                        'rgba(75, 192, 192, 1)',
                        'rgba(153, 102, 255, 1)',
                        'rgba(255, 159, 64, 1)'
                    ],
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false
            }
        });
        
        // Time Distribution Chart
        const timeCtx = document.getElementById('timeChart').getContext('2d');
        new Chart(timeCtx, {
            type: 'horizontalBar',
            data: {
                labels: [$(($metrics.TimeDistribution.PSObject.Properties.Name | ForEach-Object { "'$_'" }) -join ', ')],
                datasets: [{
                    label: 'Average Time (seconds)',
                    data: [$(($metrics.TimeDistribution.PSObject.Properties.Value | ForEach-Object { [math]::Round($_, 1) }) -join ', ')],
                    backgroundColor: 'rgba(0, 120, 212, 0.5)',
                    borderColor: 'rgba(0, 120, 212, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                indexAxis: 'y',
                scales: {
                    x: {
                        beginAtZero: true
                    }
                },
                responsive: true,
                maintainAspectRatio: false
            }
        });
    </script>
</body>
</html>
"@

        # Save HTML report
        $htmlContent | Out-File -FilePath $htmlPath -Encoding utf8
        $reportPaths += $htmlPath
        Write-Log -Message "Generated HTML analytics report at $htmlPath" -Level Information
    }
    
    # JSON Report
    if ($Format -eq "JSON" -or $Format -eq "All") {
        $jsonPath = "$OutputPath.json"
        $metrics | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding utf8
        $reportPaths += $jsonPath
        Write-Log -Message "Generated JSON analytics report at $jsonPath" -Level Information
    }
    
    # CSV Report (summary only)
    if ($Format -eq "CSV" -or $Format -eq "All") {
        $csvPath = "$OutputPath.csv"
        
        # Create summary CSV
        $csvData = [PSCustomObject]@{
            TotalMigrations = $metrics.MigrationSummary.TotalMigrations
            SuccessfulMigrations = $metrics.MigrationSummary.SuccessfulMigrations
            FailedMigrations = $metrics.MigrationSummary.FailedMigrations
            SuccessRate = $successRate
            FirstMigration = $metrics.MigrationSummary.FirstMigration
            LastMigration = $metrics.MigrationSummary.LastMigration
            DurationDays = [math]::Round($durationDays, 1)
        }
        
        $csvData | Export-Csv -Path $csvPath -NoTypeInformation
        $reportPaths += $csvPath
        Write-Log -Message "Generated CSV analytics report at $csvPath" -Level Information
        
        # If device details requested, create a device CSV too
        if ($IncludeDeviceDetails) {
            $deviceCsvPath = "$OutputPath-Devices.csv"
            $deviceData = @()
            
            foreach ($device in $metrics.DeviceMetrics.PSObject.Properties) {
                $deviceName = $device.Name
                $deviceInfo = $device.Value
                
                $deviceSuccessRate = 0
                if ($deviceInfo.Attempts -gt 0) {
                    $deviceSuccessRate = [math]::Round(($deviceInfo.Successes / $deviceInfo.Attempts) * 100, 1)
                }
                
                $deviceData += [PSCustomObject]@{
                    DeviceName = $deviceName
                    LastStatus = $deviceInfo.LastStatus
                    Attempts = $deviceInfo.Attempts
                    Successes = $deviceInfo.Successes
                    Failures = $deviceInfo.Failures
                    SuccessRate = $deviceSuccessRate
                    LastAttempt = $deviceInfo.LastAttempt
                    FirstAttempt = $deviceInfo.FirstAttempt
                }
            }
            
            $deviceData | Export-Csv -Path $deviceCsvPath -NoTypeInformation
            $reportPaths += $deviceCsvPath
            Write-Log -Message "Generated device CSV report at $deviceCsvPath" -Level Information
        }
    }
    
    return $reportPaths
}

# Record component usage
function Register-ComponentUsage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,
        
        [Parameter(Mandatory = $false)]
        [int]$Invocations = 1,
        
        [Parameter(Mandatory = $false)]
        [int]$Successes = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$Failures = 0
    )
    
    $metrics = Get-MigrationMetrics
    
    # Create component entry if it doesn't exist
    if (-not $metrics.ComponentMetrics.$ComponentName) {
        $metrics.ComponentMetrics.$ComponentName = @{
            Invocations = 0
            Successes = 0
            Failures = 0
        }
    }
    
    # Update metrics
    $metrics.ComponentMetrics.$ComponentName.Invocations += $Invocations
    $metrics.ComponentMetrics.$ComponentName.Successes += $Successes
    $metrics.ComponentMetrics.$ComponentName.Failures += $Failures
    
    # Save metrics
    Save-MigrationMetrics -Metrics $metrics
    
    Write-Log -Message ("Registered usage for component " + $ComponentName + " - " + $Invocations + " invocations, " + $Successes + " successes, " + $Failures + " failures") -Level Information
    return $true
}

# Record time metrics for a migration phase
function Register-MigrationPhaseTime {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,
        
        [Parameter(Mandatory = $true)]
        [string]$Phase,
        
        [Parameter(Mandatory = $true)]
        [double]$Seconds
    )
    
    $metrics = Get-MigrationMetrics
    
    # Ensure device exists in metrics
    if (-not $metrics.DeviceMetrics.$DeviceName) {
        Write-Log -Message "Device $DeviceName not found in metrics. Register a migration event first." -Level Warning
        return $false
    }
    
    # Create time metrics entry if needed
    if (-not $metrics.DeviceMetrics.$DeviceName.TimeMetrics) {
        $metrics.DeviceMetrics.$DeviceName.TimeMetrics = @{}
    }
    
    # Record time for this phase
    $metrics.DeviceMetrics.$DeviceName.TimeMetrics.$Phase = $Seconds
    
    # Save metrics
    Save-MigrationMetrics -Metrics $metrics
    
    Write-Log -Message "Recorded $Seconds seconds for phase $Phase on device $DeviceName" -Level Information
    return $true
}

# Get quick summary stats
function Get-MigrationSummaryStats {
    [CmdletBinding()]
    param ()
    
    $metrics = Get-MigrationMetrics
    
    if (-not $metrics) {
        return $null
    }
    
    $successRate = 0
    if ($metrics.MigrationSummary.TotalMigrations -gt 0) {
        $successRate = [math]::Round(($metrics.MigrationSummary.SuccessfulMigrations / $metrics.MigrationSummary.TotalMigrations) * 100, 1)
    }
    
    # Find top errors
    $topErrors = @()
    if ($metrics.ErrorCategories.PSObject.Properties.Count -gt 0) {
        $topErrors = $metrics.ErrorCategories.PSObject.Properties | 
                     Sort-Object -Property Value -Descending | 
                     Select-Object -First 3 -Property Name, Value
    }
    
    return [PSCustomObject]@{
        TotalMigrations = $metrics.MigrationSummary.TotalMigrations
        SuccessfulMigrations = $metrics.MigrationSummary.SuccessfulMigrations
        FailedMigrations = $metrics.MigrationSummary.FailedMigrations
        SuccessRate = $successRate
        TopErrors = $topErrors
        FirstMigration = $metrics.MigrationSummary.FirstMigration
        LastMigration = $metrics.MigrationSummary.LastMigration
    }
}

# Clear all metrics data (for testing)
function Clear-MigrationMetrics {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $metricsFile = Join-Path -Path $script:MetricsStorePath -ChildPath $script:MetricsFileName
    
    if (Test-Path -Path $metricsFile) {
        if ($Force -or $PSCmdlet.ShouldProcess($metricsFile, "Delete migration metrics")) {
            Remove-Item -Path $metricsFile -Force
            Write-Log -Message "Cleared migration metrics data" -Level Warning
            
            # Re-initialize empty metrics
            Initialize-MigrationAnalytics | Out-Null
            return $true
        }
    }
    
    return $false
}

# Initialize the module
Initialize-MigrationAnalytics | Out-Null

# Export public functions
Export-ModuleMember -Function Get-MigrationMetrics, Register-MigrationEvent, New-MigrationAnalyticsReport, Register-ComponentUsage, Register-MigrationPhaseTime, Get-MigrationSummaryStats, Clear-MigrationMetrics, Initialize-MigrationAnalytics 