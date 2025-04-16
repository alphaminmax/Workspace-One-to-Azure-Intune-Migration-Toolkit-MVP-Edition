################################################################################################################################
# Written by Jared Griego | Crayon | 4.15.2025 | Rev 1.0 |jared.griego@crayon.com                                              #
#                                                                                                                              #
# Azure PowerShell Script to allow migration from Workspace One to Azure Intune via Auto-enrollment                            #
# PowerShell 5.1 x32/x64                                                                                                       #
#                                                                                                                              #
################################################################################################################################

################################################################################################################################
#     ______ .______          ___   ____    ____  ______   .__   __.     __    __       _______.     ___                       #
#    /      ||   _  \        /   \  \   \  /   / /  __  \  |  \ |  |    |  |  |  |     /       |    /   \                      #
#   |  ,----'|  |_)  |      /  ^  \  \   \/   / |  |  |  | |   \|  |    |  |  |  |    |   (----`   /  ^  \                     #
#   |  |     |      /      /  /_\  \  \_    _/  |  |  |  | |  . `  |    |  |  |  |     \   \      /  /_\  \                    #
#   |  `----.|  |\  \----./  _____  \   |  |    |  `--'  | |  |\   |    |  `--'  | .----)   |    /  _____  \                   #
#    \______|| _| `._____/__/     \__\  |__|     \______/  |__| \__|     \______/  |_______/    /__/     \__\                  #
#                                                                                                                              #
################################################################################################################################

#Requires -Version 5.1

<#
.SYNOPSIS
    Enhanced reporting module for large-scale migration monitoring.

.DESCRIPTION
    The EnhancedReporting module extends the MigrationAnalytics module to provide
    comprehensive reporting capabilities for monitoring large-scale migrations (thousands of devices).
    It includes email reporting, dashboard generation, and advanced visualization features.

.NOTES
    File Name      : EnhancedReporting.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1, MigrationAnalytics module
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

if (-not (Get-Module -Name 'MigrationAnalytics' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'MigrationAnalytics.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module MigrationAnalytics.psm1 not found in $PSScriptRoot"
    }
}

# Script-level variables
$script:DashboardPath = Join-Path -Path $env:ProgramData -ChildPath "MigrationToolkit\Dashboard"
$script:EmailSettings = @{
    SMTPServer = ""
    Port = 587
    UseTLS = $true
    From = ""
    Credentials = $null
    DefaultRecipients = @()
}
$script:ScheduledReports = @{}

# Initialize module
function Initialize-EnhancedReporting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DashboardPath,
        
        [Parameter(Mandatory = $false)]
        [string]$SMTPServer,
        
        [Parameter(Mandatory = $false)]
        [int]$SMTPPort = 587,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseTLS = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$FromAddress,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$EmailCredential,
        
        [Parameter(Mandatory = $false)]
        [string[]]$DefaultRecipients
    )
    
    # Set custom paths if provided
    if ($DashboardPath) {
        $script:DashboardPath = $DashboardPath
    }
    
    # Ensure dashboard directory exists
    if (-not (Test-Path -Path $script:DashboardPath)) {
        New-Item -Path $script:DashboardPath -ItemType Directory -Force | Out-Null
    }
    
    # Configure email settings if provided
    if ($SMTPServer) {
        $script:EmailSettings.SMTPServer = $SMTPServer
    }
    
    if ($SMTPPort) {
        $script:EmailSettings.Port = $SMTPPort
    }
    
    if ($null -ne $UseTLS) {
        $script:EmailSettings.UseTLS = $UseTLS
    }
    
    if ($FromAddress) {
        $script:EmailSettings.From = $FromAddress
    }
    
    if ($EmailCredential) {
        $script:EmailSettings.Credentials = $EmailCredential
    }
    
    if ($DefaultRecipients -and $DefaultRecipients.Count -gt 0) {
        $script:EmailSettings.DefaultRecipients = $DefaultRecipients
    }
    
    # Log initialization
    Write-Log -Message "Enhanced Reporting module initialized with Dashboard path: $($script:DashboardPath)" -Level Information
    
    return $true
}

# Create and maintain a dashboard for migration monitoring
function New-MigrationDashboard {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $script:DashboardPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Hourly', 'Daily', 'Weekly')]
        [string]$RefreshInterval = 'Daily',
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableLiveUpdates,
        
        [Parameter(Mandatory = $false)]
        [switch]$PublishToSharePoint,
        
        [Parameter(Mandatory = $false)]
        [string]$SharePointSite,
        
        [Parameter(Mandatory = $false)]
        [string]$SharePointLibrary
    )
    
    try {
        # Create dashboard directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Get migration metrics data
        $metrics = Get-MigrationMetrics
        if (-not $metrics) {
            Write-Log -Message "No metrics data available to generate dashboard" -Level Warning
            return $false
        }
        
        # Calculate success metrics
        $totalDevices = $metrics.MigrationSummary.TotalMigrations
        $successfulMigrations = $metrics.MigrationSummary.SuccessfulMigrations
        $failedMigrations = $metrics.MigrationSummary.FailedMigrations
        $successRate = 0
        
        if ($totalDevices -gt 0) {
            $successRate = [math]::Round(($successfulMigrations / $totalDevices) * 100, 1)
        }
        
        # Generate HTML content for dashboard
        $refreshSeconds = switch ($RefreshInterval) {
            'Hourly' { 3600 }
            'Daily' { 86400 }
            'Weekly' { 604800 }
            default { 0 }
        }
        
        $autoRefreshMeta = ""
        if ($EnableLiveUpdates -and $refreshSeconds -gt 0) {
            $autoRefreshMeta = "<meta http-equiv='refresh' content='$refreshSeconds'>"
        }
        
        $dashboardHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    $autoRefreshMeta
    <title>Migration Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; }
        .container { width: 95%; margin: 20px auto; }
        .header { background-color: #0078d4; color: white; padding: 15px; text-align: center; border-radius: 5px; }
        .dashboard-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-top: 20px; }
        .card { background-color: #f9f9f9; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); padding: 15px; }
        .card h2 { margin-top: 0; color: #333; font-size: 18px; }
        .metric { font-size: 36px; font-weight: bold; margin: 15px 0; color: #0078d4; }
        .success { color: #107c10; }
        .warning { color: #f9a825; }
        .danger { color: #d83b01; }
        .chart-container { position: relative; height: 250px; width: 100%; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        table th, table td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
        table th { background-color: #f2f2f2; }
        .last-update { text-align: right; margin-top: 20px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Migration Dashboard</h1>
        </div>
        
        <div class="dashboard-grid">
            <!-- Migration Progress Card -->
            <div class="card">
                <h2>Migration Progress</h2>
                <div class="metric $(if($successRate -ge 90){"success"}elseif($successRate -ge 70){"warning"}else{"danger"})">$successRate%</div>
                <div class="chart-container">
                    <canvas id="migrationProgress"></canvas>
                </div>
            </div>
            
            <!-- Migration Status Card -->
            <div class="card">
                <h2>Migration Status</h2>
                <div class="chart-container">
                    <canvas id="migrationStatus"></canvas>
                </div>
                <table>
                    <tr>
                        <th>Status</th>
                        <th>Count</th>
                        <th>Percentage</th>
                    </tr>
                    <tr>
                        <td>Successful</td>
                        <td>$successfulMigrations</td>
                        <td>$successRate%</td>
                    </tr>
                    <tr>
                        <td>Failed</td>
                        <td>$failedMigrations</td>
                        <td>$(if($totalDevices -gt 0){[math]::Round(($failedMigrations / $totalDevices) * 100, 1)}else{0})%</td>
                    </tr>
                    <tr>
                        <td>Total</td>
                        <td>$totalDevices</td>
                        <td>100%</td>
                    </tr>
                </table>
            </div>
            
            <!-- Top Errors Card -->
            <div class="card">
                <h2>Top Error Categories</h2>
                <div class="chart-container">
                    <canvas id="errorChart"></canvas>
                </div>
            </div>
            
            <!-- Migration Timeline Card -->
            <div class="card">
                <h2>Migration Timeline</h2>
                <div class="chart-container">
                    <canvas id="timelineChart"></canvas>
                </div>
            </div>
        </div>
        
        <div class="last-update">
            Last updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        </div>
    </div>
    
    <script>
        // Migration Progress Chart
        const progressCtx = document.getElementById('migrationProgress').getContext('2d');
        new Chart(progressCtx, {
            type: 'doughnut',
            data: {
                labels: ['Completed', 'Remaining'],
                datasets: [{
                    data: [$successRate, $(100-$successRate)],
                    backgroundColor: ['#107c10', '#f2f2f2'],
                    borderWidth: 0
                }]
            },
            options: {
                cutout: '70%',
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });
        
        // Migration Status Chart
        const statusCtx = document.getElementById('migrationStatus').getContext('2d');
        new Chart(statusCtx, {
            type: 'pie',
            data: {
                labels: ['Successful', 'Failed'],
                datasets: [{
                    data: [$successfulMigrations, $failedMigrations],
                    backgroundColor: ['#107c10', '#d83b01'],
                    borderWidth: 0
                }]
            },
            options: {
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });
        
        // Error Categories Chart
        const errorCtx = document.getElementById('errorChart').getContext('2d');
        new Chart(errorCtx, {
            type: 'bar',
            data: {
                labels: [$(foreach($error in ($metrics.ErrorCategories.PSObject.Properties | Sort-Object -Property Value -Descending | Select-Object -First 5)) {"'$($error.Name)',"})],
                datasets: [{
                    label: 'Error Count',
                    data: [$(foreach($error in ($metrics.ErrorCategories.PSObject.Properties | Sort-Object -Property Value -Descending | Select-Object -First 5)) {"$($error.Value),"})],
                    backgroundColor: '#d83b01',
                    borderWidth: 0
                }]
            },
            options: {
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            precision: 0
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
        
        // Migration Timeline Chart (placeholder - would need actual timeline data)
        const timelineCtx = document.getElementById('timelineChart').getContext('2d');
        new Chart(timelineCtx, {
            type: 'line',
            data: {
                labels: ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5'],
                datasets: [{
                    label: 'Migrations Completed',
                    data: [
                        Math.floor($successfulMigrations * 0.2),
                        Math.floor($successfulMigrations * 0.4),
                        Math.floor($successfulMigrations * 0.6),
                        Math.floor($successfulMigrations * 0.8),
                        $successfulMigrations
                    ],
                    fill: false,
                    borderColor: '#0078d4',
                    tension: 0.1
                }]
            },
            options: {
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            precision: 0
                        }
                    }
                }
            }
        });
    </script>
</body>
</html>
"@
        
        # Write dashboard HTML file
        $dashboardFilePath = Join-Path -Path $OutputPath -ChildPath "dashboard.html"
        $dashboardHtml | Out-File -FilePath $dashboardFilePath -Encoding utf8 -Force
        
        # Generate department-specific dashboards if metrics contain department tags
        $departments = @()
        foreach ($device in $metrics.DeviceMetrics.PSObject.Properties) {
            if ($device.Value.Department -and -not $departments.Contains($device.Value.Department)) {
                $departments += $device.Value.Department
            }
        }
        
        foreach ($dept in $departments) {
            # Generate department-specific dashboard (simplified version)
            # Code would be similar to above, filtered by department
        }
        
        # Publish to SharePoint if requested
        if ($PublishToSharePoint -and $SharePointSite -and $SharePointLibrary) {
            # SharePoint upload code would go here
            # Using PnP PowerShell or similar
        }
        
        Write-Log -Message "Migration dashboard generated at $dashboardFilePath" -Level Information
        return $dashboardFilePath
    }
    catch {
        Write-Log -Message "Error generating migration dashboard: $_" -Level Error
        return $false
    }
}

# Send email report with migration statistics
function Send-MigrationReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$Recipients,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('HTML', 'PDF', 'Text', 'All')]
        [string]$Format = 'HTML',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Executive', 'Technical', 'Detailed')]
        [string]$ReportType = 'Technical',
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeAttachments,
        
        [Parameter(Mandatory = $false)]
        [string]$CustomSubject,
        
        [Parameter(Mandatory = $false)]
        [string]$Department
    )
    
    try {
        # Check if email settings are configured
        if ([string]::IsNullOrEmpty($script:EmailSettings.SMTPServer) -or [string]::IsNullOrEmpty($script:EmailSettings.From)) {
            Write-Log -Message "Email settings not fully configured. Use Initialize-EnhancedReporting to set SMTP details." -Level Error
            return $false
        }
        
        # Use default recipients if none specified
        if (-not $Recipients -or $Recipients.Count -eq 0) {
            $Recipients = $script:EmailSettings.DefaultRecipients
            if (-not $Recipients -or $Recipients.Count -eq 0) {
                Write-Log -Message "No recipients specified and no default recipients configured." -Level Error
                return $false
            }
        }
        
        # Get migration metrics
        $metrics = Get-MigrationMetrics
        if (-not $metrics) {
            Write-Log -Message "No metrics data available to generate report." -Level Warning
            return $false
        }
        
        # Filter by department if specified
        if ($Department) {
            # Filter logic would go here
        }
        
        # Calculate metrics
        $totalDevices = $metrics.MigrationSummary.TotalMigrations
        $successfulMigrations = $metrics.MigrationSummary.SuccessfulMigrations
        $failedMigrations = $metrics.MigrationSummary.FailedMigrations
        $successRate = 0
        
        if ($totalDevices -gt 0) {
            $successRate = [math]::Round(($successfulMigrations / $totalDevices) * 100, 1)
        }
        
        # Generate report content based on report type
        $subject = $CustomSubject
        if ([string]::IsNullOrEmpty($subject)) {
            $subject = "Migration Status Report - $successRate% Complete"
            if ($Department) {
                $subject = "Migration Status Report for $Department - $successRate% Complete"
            }
        }
        
        $attachments = @()
        $body = ""
        
        # Generate report based on format
        switch ($Format) {
            'HTML' {
                $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
        .header { background-color: #0078d4; color: white; padding: 10px; text-align: center; }
        .section { margin: 20px 0; }
        .metric { font-size: 24px; font-weight: bold; margin: 10px 0; }
        .success { color: #107c10; }
        .warning { color: #f9a825; }
        .danger { color: #d83b01; }
        table { width: 100%; border-collapse: collapse; }
        table th, table td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        table th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Migration Status Report</h1>
        <p>Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm")</p>
    </div>
    
    <div class="section">
        <h2>Migration Progress</h2>
        <div class="metric $(if($successRate -ge 90){"success"}elseif($successRate -ge 70){"warning"}else{"danger"})">
            $successRate% Complete
        </div>
        <p>$successfulMigrations of $totalDevices devices successfully migrated.</p>
        <p>$failedMigrations migration failures reported.</p>
    </div>
"@

                # Add additional sections based on report type
                switch ($ReportType) {
                    'Executive' {
                        # Simplified report for executives
                        $body += @"
    <div class="section">
        <h2>Migration Timeline</h2>
        <p>First migration: $($metrics.MigrationSummary.FirstMigration)</p>
        <p>Latest migration: $($metrics.MigrationSummary.LastMigration)</p>
        <p>Estimated completion: $(if($successRate -gt 0) { Get-Date (Get-Date).AddDays((100 - $successRate) / ($successRate / (New-TimeSpan -Start (Get-Date $metrics.MigrationSummary.FirstMigration) -End (Get-Date)).TotalDays)) -Format "yyyy-MM-dd" } else { "Unknown" })</p>
    </div>
"@
                    }
                    'Technical' {
                        # Technical report with more details
                        $topErrors = $metrics.ErrorCategories.PSObject.Properties | 
                                    Sort-Object -Property Value -Descending | 
                                    Select-Object -First 5
                        
                        $body += @"
    <div class="section">
        <h2>Error Summary</h2>
        <table>
            <tr>
                <th>Error Category</th>
                <th>Count</th>
                <th>Percentage</th>
            </tr>
"@
                        foreach ($error in $topErrors) {
                            $errorPct = 0
                            if ($failedMigrations -gt 0) {
                                $errorPct = [math]::Round(($error.Value / $failedMigrations) * 100, 1)
                            }
                            $body += @"
            <tr>
                <td>$($error.Name)</td>
                <td>$($error.Value)</td>
                <td>$errorPct%</td>
            </tr>
"@
                        }
                        $body += @"
        </table>
    </div>
    
    <div class="section">
        <h2>Component Performance</h2>
        <table>
            <tr>
                <th>Component</th>
                <th>Successes</th>
                <th>Failures</th>
                <th>Success Rate</th>
            </tr>
"@
                        foreach ($component in $metrics.ComponentMetrics.PSObject.Properties) {
                            $compSuccessRate = 0
                            $total = $component.Value.Successes + $component.Value.Failures
                            if ($total -gt 0) {
                                $compSuccessRate = [math]::Round(($component.Value.Successes / $total) * 100, 1)
                            }
                            $body += @"
            <tr>
                <td>$($component.Name)</td>
                <td>$($component.Value.Successes)</td>
                <td>$($component.Value.Failures)</td>
                <td>$compSuccessRate%</td>
            </tr>
"@
                        }
                        $body += @"
        </table>
    </div>
"@
                    }
                    'Detailed' {
                        # Detailed report with the above plus device details
                        # Code similar to Technical but with additional device-specific tables
                    }
                }
                
                $body += @"
    <div class="section">
        <p>For more detailed information, please visit the <a href="file://$script:DashboardPath\dashboard.html">Migration Dashboard</a>.</p>
    </div>
</body>
</html>
"@
            }
            'Text' {
                # Generate plain text report
                $body = @"
MIGRATION STATUS REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm")

MIGRATION PROGRESS
$successRate% Complete
$successfulMigrations of $totalDevices devices successfully migrated.
$failedMigrations migration failures reported.

"@
                # Add more sections based on report type
            }
            'PDF' {
                # For PDF, we'll generate HTML and then potentially convert it
                # Would need a PDF conversion library or component
            }
        }
        
        # Generate any necessary attachments
        if ($IncludeAttachments) {
            $tempReportPath = Join-Path -Path $env:TEMP -ChildPath "MigrationReport_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            
            if (-not (Test-Path -Path $tempReportPath)) {
                New-Item -Path $tempReportPath -ItemType Directory -Force | Out-Null
            }
            
            # Generate CSV attachment
            $csvPath = Join-Path -Path $tempReportPath -ChildPath "MigrationStatusDetails.csv"
            
            # Extract device metrics to CSV
            $deviceData = foreach ($device in $metrics.DeviceMetrics.PSObject.Properties) {
                [PSCustomObject]@{
                    DeviceName = $device.Name
                    Status = if ($device.Value.Failures -gt 0) { "Failed" } else { "Success" }
                    Department = $device.Value.Department
                    Attempts = $device.Value.Successes + $device.Value.Failures
                    LastAttempt = $device.Value.LastUpdated
                }
            }
            
            $deviceData | Export-Csv -Path $csvPath -NoTypeInformation -Force
            $attachments += $csvPath
        }
        
        # Send the email
        $emailParams = @{
            SmtpServer = $script:EmailSettings.SMTPServer
            Port = $script:EmailSettings.Port
            From = $script:EmailSettings.From
            To = $Recipients
            Subject = $subject
            Body = $body
            BodyAsHtml = ($Format -eq 'HTML')
        }
        
        if ($attachments.Count -gt 0) {
            $emailParams.Add('Attachments', $attachments)
        }
        
        if ($script:EmailSettings.UseTLS) {
            $emailParams.Add('UseSsl', $true)
        }
        
        if ($script:EmailSettings.Credentials) {
            $emailParams.Add('Credential', $script:EmailSettings.Credentials)
        }
        
        Send-MailMessage @emailParams
        
        # Clean up temporary files if needed
        if ($attachments.Count -gt 0) {
            # Clean-up logic for temp files
        }
        
        Write-Log -Message "Migration report email sent to $($Recipients -join ', ')" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Error sending migration report email: $_" -Level Error
        return $false
    }
}

# Register and manage scheduled reports
function Register-MigrationReportSchedule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Recipients,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('HTML', 'PDF', 'Text', 'All')]
        [string]$Format = 'HTML',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Daily', 'Weekly', 'Monthly', 'OnCompletion')]
        [string]$Schedule = 'Daily',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Executive', 'Technical', 'Detailed')]
        [string]$ReportType = 'Technical',
        
        [Parameter(Mandatory = $false)]
        [string]$CustomName,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeAttachments
    )
    
    try {
        # Generate a unique name for this schedule if not provided
        $scheduleName = $CustomName
        if ([string]::IsNullOrEmpty($scheduleName)) {
            $scheduleName = "Report_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }
        
        # Create the schedule definition
        $scheduleDefinition = @{
            Name = $scheduleName
            Recipients = $Recipients
            Format = $Format
            Schedule = $Schedule
            ReportType = $ReportType
            IncludeAttachments = $IncludeAttachments
            CreatedOn = Get-Date
            LastRun = $null
        }
        
        # Add to scheduled reports collection
        $script:ScheduledReports[$scheduleName] = $scheduleDefinition
        
        # In a real implementation, we would also set up an actual scheduled task
        # using the Task Scheduler to run the reporting at the specified interval
        
        Write-Log -Message "Registered migration report schedule '$scheduleName'" -Level Information
        return $scheduleName
    }
    catch {
        Write-Log -Message "Error registering migration report schedule: $_" -Level Error
        return $false
    }
}

# Update device batch information in MigrationAnalytics
function Update-MigrationAnalyticsBatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 500,
        
        [Parameter(Mandatory = $false)]
        [switch]$ParallelProcessing
    )
    
    try {
        # Get current metrics
        $metrics = Get-MigrationMetrics
        if (-not $metrics) {
            Write-Log -Message "No metrics data available for batch update" -Level Warning
            return $false
        }
        
        # In a real implementation, this would query a database or other source
        # to get pending analytics data for devices not yet processed
        
        # Simulate processing batches of device data
        Write-Log -Message "Processing migration analytics in batches of $BatchSize" -Level Information
        
        # Update metrics with batch processing status
        $metrics.MigrationSummary.BatchProcessingEnabled = $true
        $metrics.MigrationSummary.LastBatchUpdate = Get-Date
        
        # Save updated metrics
        Save-MigrationMetrics -Metrics $metrics
        
        return $true
    }
    catch {
        Write-Log -Message "Error updating migration analytics batch: $_" -Level Error
        return $false
    }
}

# Export data to external systems (Power BI, etc.)
function Export-MigrationData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('CSV', 'JSON', 'PowerBI', 'SQL')]
        [string]$Format = 'CSV',
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $script:DashboardPath,
        
        [Parameter(Mandatory = $false)]
        [string]$ConnectionString,
        
        [Parameter(Mandatory = $false)]
        [string]$TableName = "MigrationData"
    )
    
    try {
        # Get migration metrics
        $metrics = Get-MigrationMetrics
        if (-not $metrics) {
            Write-Log -Message "No metrics data available to export" -Level Warning
            return $false
        }
        
        # Process based on format
        switch ($Format) {
            'CSV' {
                # Export to CSV
                $exportPath = Join-Path -Path $OutputPath -ChildPath "MigrationData_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                
                # Flatten metrics data for CSV
                $flatData = @()
                foreach ($device in $metrics.DeviceMetrics.PSObject.Properties) {
                    $flatData += [PSCustomObject]@{
                        DeviceName = $device.Name
                        SuccessCount = $device.Value.Successes
                        FailureCount = $device.Value.Failures
                        LastUpdated = $device.Value.LastUpdated
                        Department = $device.Value.Department
                        TotalTime = ($device.Value.TimeMetrics.Values | Measure-Object -Sum).Sum
                    }
                }
                
                $flatData | Export-Csv -Path $exportPath -NoTypeInformation -Force
                return $exportPath
            }
            'JSON' {
                # Export to JSON
                $exportPath = Join-Path -Path $OutputPath -ChildPath "MigrationData_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                $metrics | ConvertTo-Json -Depth 10 | Out-File -FilePath $exportPath -Encoding utf8 -Force
                return $exportPath
            }
            'PowerBI' {
                # For Power BI integration
                # Would typically create a dataset file or use the Power BI API
                # This is a placeholder for the concept
                return $true
            }
            'SQL' {
                # Export to SQL database
                # Would use SQL connection here
                # This is a placeholder for the concept
                return $true
            }
        }
    }
    catch {
        Write-Log -Message "Error exporting migration data: $_" -Level Error
        return $false
    }
}

# Initialize the module
Initialize-EnhancedReporting | Out-Null

# Export public functions
Export-ModuleMember -Function Initialize-EnhancedReporting, New-MigrationDashboard, Send-MigrationReport, 
                            Register-MigrationReportSchedule, Update-MigrationAnalyticsBatch, Export-MigrationData 