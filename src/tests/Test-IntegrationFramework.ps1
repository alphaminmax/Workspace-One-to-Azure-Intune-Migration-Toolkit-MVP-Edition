#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Tests the integration between all high-priority components of the migration solution.                                 #
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
    Tests the integration between all high-priority components of the migration solution.

.DESCRIPTION
    This script validates that all high-priority components (RollbackMechanism, 
    MigrationVerification, UserCommunicationFramework) work together correctly
    in various migration scenarios. It simulates migration workflows and ensures
    that components interact properly with the orchestration framework.

.PARAMETER TestDevice
    Name of a test device to use for integration testing.

.PARAMETER LogPath
    Path where test logs will be stored.

.PARAMETER ReportPath
    Path where test reports will be generated.

.PARAMETER SkipRollbackTests
    Switch to skip testing of rollback functionality.

.EXAMPLE
    .\Test-IntegrationFramework.ps1 -TestDevice "TestPC01" -LogPath "C:\TestLogs"
    
    Tests integration using the specified test device and log location.

.NOTES
    File Name      : Test-IntegrationFramework.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TestDevice = $env:COMPUTERNAME,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\MigrationIntegrationTests",
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "$env:TEMP\MigrationIntegrationTests\Reports",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipRollbackTests,
    
    [Parameter(Mandatory = $false)]
    [switch]$Mock
)

# Find the modules directory (one level up from tests directory, then into modules)
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$modulesPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "modules"
$scriptsPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "scripts"

# Import required modules
$requiredModules = @(
    "LoggingModule",
    "RollbackMechanism",
    "MigrationVerification",
    "UserCommunicationFramework",
    "MigrationAnalytics"
)

foreach ($module in $requiredModules) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath "$module.psm1"
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
        Write-Verbose "Imported module: $module"
    }
    else {
        Write-Warning "Module $module not found at $modulePath"
        exit 1
    }
}

# Ensure directories exist
if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

# Initialize test report
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$testReportPath = Join-Path -Path $ReportPath -ChildPath "IntegrationTestReport_$timestamp.html"
$testLogPath = Join-Path -Path $LogPath -ChildPath "IntegrationTest_$timestamp.log"

# Initialize logging
Write-Log -Message "Starting integration tests for high-priority components" -Level Information -LogFilePath $testLogPath

# Test result tracking
$testResults = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    TestDetails = @()
}

# Function to record test results
function Record-TestResult {
    param (
        [string]$TestName,
        [string]$Component,
        [bool]$Success,
        [string]$ErrorMessage = "",
        [int]$Duration = 0
    )
    
    $status = if ($Success) { "Passed" } else { "Failed" }
    Write-Log -Message "Test '$TestName' $status for component '$Component'" -Level ($Success ? "Information" : "Error") -LogFilePath $testLogPath
    
    $testResults.TotalTests++
    if ($Success) {
        $testResults.PassedTests++
    }
    else {
        $testResults.FailedTests++
    }
    
    $testResults.TestDetails += @{
        TestName = $TestName
        Component = $Component
        Status = $status
        ErrorMessage = $ErrorMessage
        Duration = $Duration
        Timestamp = Get-Date
    }
}

# Function to run a test with error handling
function Invoke-IntegrationTest {
    param (
        [string]$TestName,
        [string]$Component,
        [scriptblock]$Test
    )
    
    Write-Host "Running test: $TestName..." -ForegroundColor Cyan
    $startTime = Get-Date
    
    try {
        $result = & $Test
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        Record-TestResult -TestName $TestName -Component $Component -Success $true -Duration $duration
        Write-Host "Test passed: $TestName" -ForegroundColor Green
        return $true
    }
    catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        Record-TestResult -TestName $TestName -Component $Component -Success $false -ErrorMessage $_.Exception.Message -Duration $duration
        Write-Host "Test failed: $TestName - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Mock functions for testing
function Initialize-MockEnvironment {
    # Create mock functions for testing without real migration operations
    if ($Mock) {
        # Mock RollbackMechanism functions
        function global:New-SystemRestorePoint { param($Description) return @{ Success = $true; ID = [guid]::NewGuid() } }
        function global:New-RegistryBackup { param($BackupPath) return @{ Success = $true; Path = "$BackupPath\MockBackup.reg" } }
        
        # Mock MigrationVerification functions
        function global:Test-DeviceEnrollment { param($DeviceId) return $true }
        function global:Test-ApplicationInstallation { param($AppId) return $true }
        
        # Mock UserCommunicationFramework functions
        function global:Send-MigrationNotification { param($Type, $UserEmail, $Parameters) return $true }
        
        # Mock other functions as needed
        Write-Host "Mock environment initialized for testing" -ForegroundColor Yellow
    }
}

# Initialize mock environment if requested
Initialize-MockEnvironment

#region Integration Tests

# Test 1: Component Loading Test
Invoke-IntegrationTest -TestName "Component Loading" -Component "Integration" -Test {
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module)) {
            throw "Failed to load module: $module"
        }
    }
    
    return $true
}

# Test 2: Analytics Integration Test
Invoke-IntegrationTest -TestName "Analytics Integration" -Component "MigrationAnalytics" -Test {
    # Clear any existing metrics for testing
    if (Get-Command -Name Clear-MigrationMetrics -ErrorAction SilentlyContinue) {
        Clear-MigrationMetrics -Force | Out-Null
    }
    
    # Initialize analytics
    Initialize-MigrationAnalytics -MetricsPath "$LogPath\Metrics" -ReportsPath "$ReportPath\Analytics" | Out-Null
    
    # Register test events
    Register-MigrationEvent -DeviceName $TestDevice -Status "Started" | Out-Null
    Register-ComponentUsage -ComponentName "TestComponent" -Invocations 1 -Successes 1 | Out-Null
    Register-MigrationPhaseTime -DeviceName $TestDevice -Phase "TestPhase" -Seconds 10 | Out-Null
    Register-MigrationEvent -DeviceName $TestDevice -Status "Completed" | Out-Null
    
    # Generate report
    $reportPath = New-MigrationAnalyticsReport -OutputPath "$ReportPath\Analytics\TestReport" -Format "HTML" | Out-Null
    
    # Get summary
    $summary = Get-MigrationSummaryStats
    
    if ($summary.TotalMigrations -lt 1) {
        throw "Analytics integration failed: No migrations recorded"
    }
    
    return $true
}

# Test 3: User Communication Integration Test
Invoke-IntegrationTest -TestName "User Communication Integration" -Component "UserCommunicationFramework" -Test {
    # Test user notification
    $notificationResult = Send-MigrationNotification -Type "TestNotification" -UserEmail "test@example.com" -Parameters @("Test Parameter")
    
    if (-not $notificationResult) {
        throw "Failed to send test notification"
    }
    
    # Test status logging
    $logResult = Log-UserMessage -Message "Test integration message" -Level "Information"
    
    if (-not $logResult) {
        throw "Failed to log user message"
    }
    
    return $true
}

# Test 4: Verification Integration Test
Invoke-IntegrationTest -TestName "Verification Integration" -Component "MigrationVerification" -Test {
    # Run a verification test
    $verificationResult = Start-MigrationVerification -DeviceName $TestDevice -OutputPath "$ReportPath\Verification"
    
    # Validate verification results structure
    if (-not $verificationResult.ContainsKey("DeviceVerification")) {
        throw "Missing DeviceVerification results"
    }
    
    if (-not $verificationResult.ContainsKey("ApplicationVerification")) {
        throw "Missing ApplicationVerification results"
    }
    
    return $true
}

# Test 5: Rollback Integration Test (skip if requested)
if (-not $SkipRollbackTests) {
    Invoke-IntegrationTest -TestName "Rollback Integration" -Component "RollbackMechanism" -Test {
        # Create test backup
        $backupId = Start-MigrationBackup -BackupPath "$LogPath\Backups" -CreateRestorePoint:$(-not $Mock)
        
        if (-not $backupId) {
            throw "Failed to create migration backup"
        }
        
        # Test rollback initiation (in mock mode)
        if ($Mock) {
            $rollbackResult = Start-MigrationRollback -BackupId $backupId -Force
            
            if (-not $rollbackResult.Success) {
                throw "Rollback simulation failed: $($rollbackResult.Message)"
            }
        }
        
        return $true
    }
}

# Test 6: Orchestration Integration Test
Invoke-IntegrationTest -TestName "Orchestration Integration" -Component "Integration" -Test {
    # Test that orchestration script exists and is valid
    $orchestratorPath = Join-Path -Path $scriptsPath -ChildPath "Invoke-MigrationOrchestrator.ps1"
    
    if (-not (Test-Path -Path $orchestratorPath)) {
        throw "Orchestrator script not found at $orchestratorPath"
    }
    
    # Validate script syntax (won't execute it)
    $syntaxErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $orchestratorPath -Raw), [ref]$syntaxErrors)
    
    if ($syntaxErrors.Count -gt 0) {
        throw "Orchestrator script has syntax errors: $($syntaxErrors[0].Message)"
    }
    
    return $true
}

# Test 7: Dashboard Integration Test
Invoke-IntegrationTest -TestName "Dashboard Integration" -Component "Integration" -Test {
    # Test that dashboard script exists and is valid
    $dashboardPath = Join-Path -Path $scriptsPath -ChildPath "New-MigrationDashboard.ps1"
    
    if (-not (Test-Path -Path $dashboardPath)) {
        throw "Dashboard script not found at $dashboardPath"
    }
    
    # Validate script syntax (won't execute it)
    $syntaxErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $dashboardPath -Raw), [ref]$syntaxErrors)
    
    if ($syntaxErrors.Count -gt 0) {
        throw "Dashboard script has syntax errors: $($syntaxErrors[0].Message)"
    }
    
    return $true
}

# Test 8: End-to-End Integration Simulation
Invoke-IntegrationTest -TestName "End-to-End Integration Simulation" -Component "Integration" -Test {
    if (-not $Mock) {
        Write-Host "Skipping end-to-end test in non-mock mode" -ForegroundColor Yellow
        $testResults.SkippedTests++
        return $true
    }
    
    # Simulate a complete migration workflow
    
    # 1. Initialize migration events
    Register-MigrationEvent -DeviceName $TestDevice -Status "Started" | Out-Null
    
    # 2. Create backups
    $backupId = Start-MigrationBackup -BackupPath "$LogPath\Backups" -CreateRestorePoint:$false
    
    # 3. Register component usage for each component
    @("RollbackMechanism", "MigrationVerification", "UserCommunicationFramework") | ForEach-Object {
        Register-ComponentUsage -ComponentName $_ -Invocations 1 -Successes 1 | Out-Null
    }
    
    # 4. Register phase times
    @("Planning", "Backup", "WS1Removal", "AzureSetup", "IntuneEnrollment", "Verification") | ForEach-Object {
        Register-MigrationPhaseTime -DeviceName $TestDevice -Phase $_ -Seconds (Get-Random -Minimum 5 -Maximum 30) | Out-Null
    }
    
    # 5. Send test notifications
    Send-MigrationNotification -Type "MigrationProgress" -UserEmail "test@example.com" -Parameters @(50, "Testing integration") | Out-Null
    
    # 6. Run verification
    Start-MigrationVerification -DeviceName $TestDevice -OutputPath "$ReportPath\Verification" | Out-Null
    
    # 7. Complete migration
    Register-MigrationEvent -DeviceName $TestDevice -Status "Completed" | Out-Null
    
    # 8. Generate reports
    New-MigrationAnalyticsReport -OutputPath "$ReportPath\Analytics\EndToEndTest" -Format "HTML" | Out-Null
    
    return $true
}

#endregion

# Generate HTML report
function New-TestReport {
    $passRate = if ($testResults.TotalTests -gt 0) { 
        [math]::Round(($testResults.PassedTests / $testResults.TotalTests) * 100, 1)
    } else { 0 }
    
    $statusClass = if ($passRate -ge 90) { "success" } elseif ($passRate -ge 75) { "warning" } else { "danger" }
    
    # Prepare test rows
    $testRows = ""
    foreach ($test in $testResults.TestDetails) {
        $rowClass = switch ($test.Status) {
            "Passed" { "table-success" }
            "Failed" { "table-danger" }
            default { "" }
        }
        
        $errorInfo = if ($test.ErrorMessage) { $test.ErrorMessage } else { "" }
        
        $testRows += @"
        <tr class="$rowClass">
            <td>$($test.TestName)</td>
            <td>$($test.Component)</td>
            <td>$($test.Status)</td>
            <td>$($test.Duration) sec</td>
            <td>$($test.Timestamp)</td>
            <td>$errorInfo</td>
        </tr>
"@
    }
    
    # Create HTML report
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Integration Test Report</title>
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
        .card {
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
        .summary {
            display: flex;
            justify-content: space-between;
            margin: 20px 0;
        }
        .summary-box {
            background-color: #f8f9fa;
            border-radius: 5px;
            padding: 15px;
            text-align: center;
            flex: 1;
            margin: 0 10px;
        }
        .summary-value {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
        }
        .summary-label {
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
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #f8f9fa;
        }
        .table-success td { background-color: #d4edda; }
        .table-danger td { background-color: #f8d7da; }
        .table-warning td { background-color: #fff3cd; }
        
        .status-badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 4px;
            color: white;
            font-weight: bold;
        }
        .status-success { background-color: #28a745; }
        .status-warning { background-color: #ffc107; color: #212529; }
        .status-danger { background-color: #dc3545; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Integration Test Report</h1>
            <p>Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        </div>
        
        <div class="card">
            <h2 class="card-title">Test Summary</h2>
            <div>
                <h3>Overall Status: <span class="status-badge status-$statusClass">$passRate% Pass Rate</span></h3>
            </div>
            <div class="summary">
                <div class="summary-box">
                    <div class="summary-value">$($testResults.TotalTests)</div>
                    <div class="summary-label">Total Tests</div>
                </div>
                <div class="summary-box">
                    <div class="summary-value" style="color: #28a745;">$($testResults.PassedTests)</div>
                    <div class="summary-label">Passed</div>
                </div>
                <div class="summary-box">
                    <div class="summary-value" style="color: #dc3545;">$($testResults.FailedTests)</div>
                    <div class="summary-label">Failed</div>
                </div>
                <div class="summary-box">
                    <div class="summary-value" style="color: #6c757d;">$($testResults.SkippedTests)</div>
                    <div class="summary-label">Skipped</div>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2 class="card-title">Test Details</h2>
            <table>
                <thead>
                    <tr>
                        <th>Test Name</th>
                        <th>Component</th>
                        <th>Status</th>
                        <th>Duration</th>
                        <th>Timestamp</th>
                        <th>Error Message</th>
                    </tr>
                </thead>
                <tbody>
                    $testRows
                </tbody>
            </table>
        </div>
        
        <div class="card">
            <h2 class="card-title">Test Environment</h2>
            <p><strong>Test Device:</strong> $TestDevice</p>
            <p><strong>Log Path:</strong> $LogPath</p>
            <p><strong>Report Path:</strong> $ReportPath</p>
            <p><strong>Mock Mode:</strong> $($Mock.ToString())</p>
            <p><strong>Skip Rollback Tests:</strong> $($SkipRollbackTests.ToString())</p>
            <p><strong>PowerShell Version:</strong> $($PSVersionTable.PSVersion.ToString())</p>
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $testReportPath -Encoding utf8
    Write-Host "Test report generated at: $testReportPath" -ForegroundColor Green
}

# Generate the test report
New-TestReport

# Output summary to console
$passRate = if ($testResults.TotalTests -gt 0) { 
    [math]::Round(($testResults.PassedTests / $testResults.TotalTests) * 100, 1)
} else { 0 }

Write-Host "`nIntegration Test Summary:" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "Total Tests:   $($testResults.TotalTests)" -ForegroundColor White
Write-Host "Passed:        $($testResults.PassedTests)" -ForegroundColor Green
Write-Host "Failed:        $($testResults.FailedTests)" -ForegroundColor Red
Write-Host "Skipped:       $($testResults.SkippedTests)" -ForegroundColor Gray
Write-Host "Pass Rate:     $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 75) { "Yellow" } else { "Red" })
Write-Host "`nTest Log:      $testLogPath" -ForegroundColor White
Write-Host "Test Report:   $testReportPath" -ForegroundColor White

# Return success if all tests passed
exit $($testResults.FailedTests -eq 0) 





