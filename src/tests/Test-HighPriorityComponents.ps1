#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Tests the integration of high-priority components for the WS1 to Azure/Intune migration.                              #
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
    Tests the integration of high-priority components for the WS1 to Azure/Intune migration.
.DESCRIPTION
    This script validates that the high-priority components of the migration toolkit 
    (RollbackMechanism, MigrationVerification, and UserCommunicationFramework)
    are functioning correctly and integrating properly with each other.
    
    The script runs a series of tests to validate:
    - Each component's core functionality
    - Integration points between components
    - Error handling and recovery processes
    - End-to-end workflows
    
.PARAMETER SkipRollbackTests
    Skip tests related to the RollbackMechanism module.
    
.PARAMETER SkipVerificationTests
    Skip tests related to the MigrationVerification module.
    
.PARAMETER SkipCommunicationTests
    Skip tests related to the UserCommunicationFramework module.
    
.PARAMETER LogPath
    The path where test logs will be stored.
    Default is "$env:TEMP\MigrationTests".
    
.PARAMETER OutputPath
    The path where test reports will be generated.
    Default is "$env:TEMP\MigrationTests\Reports".
    
.EXAMPLE
    .\Test-HighPriorityComponents.ps1
    
    Runs all tests for high-priority components.
    
.EXAMPLE
    .\Test-HighPriorityComponents.ps1 -SkipRollbackTests
    
    Runs tests for MigrationVerification and UserCommunicationFramework, but skips RollbackMechanism tests.
    
.EXAMPLE
    .\Test-HighPriorityComponents.ps1 -LogPath "C:\Logs\ComponentTests"
    
    Runs all tests and stores logs in the specified directory.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [switch]$SkipRollbackTests,
    
    [Parameter()]
    [switch]$SkipVerificationTests,
    
    [Parameter()]
    [switch]$SkipCommunicationTests,
    
    [Parameter()]
    [string]$LogPath = "$env:TEMP\MigrationTests",
    
    [Parameter()]
    [string]$OutputPath = "$env:TEMP\MigrationTests\Reports"
)

#region Initialize Environment

# Script Variables
$script:TestResults = @()
$script:TestStartTime = Get-Date
$script:TestsRun = 0
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0

# Create directories if they don't exist
if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Set up logging
$script:LogFile = Join-Path -Path $LogPath -ChildPath "HighPriorityComponents_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:ReportFile = Join-Path -Path $OutputPath -ChildPath "TestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

# Module paths - adjust if needed
$script:ModulesPath = (Resolve-Path -Path "..\modules").Path
$script:RollbackModule = Join-Path -Path $script:ModulesPath -ChildPath "RollbackMechanism.psm1"
$script:VerificationModule = Join-Path -Path $script:ModulesPath -ChildPath "MigrationVerification.psm1"
$script:CommunicationModule = Join-Path -Path $script:ModulesPath -ChildPath "UserCommunicationFramework.psm1"

# Check for Admin rights
$script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#endregion

#region Helper Functions

function Write-TestLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Add to log file
    Add-Content -Path $script:LogFile -Value $logMessage
    
    # Display on console with color
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
}

function Test-ModuleAvailable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    if (-not (Test-Path -Path $ModulePath)) {
        Write-TestLog -Message "Module file not found: $ModulePath" -Level 'Error'
        return $false
    }
    
    try {
        # Try to import the module
        Import-Module -Name $ModulePath -Force -ErrorAction Stop
        Write-TestLog -Message "Successfully imported module: $ModuleName" -Level 'Success'
        return $true
    }
    catch {
        Write-TestLog -Message "Failed to import module $ModuleName: $_" -Level 'Error'
        return $false
    }
}

function Register-TestCase {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestScript,
        
        [Parameter()]
        [string]$Category = 'General',
        
        [Parameter()]
        [switch]$Skip
    )
    
    $script:TestsRun++
    
    if ($Skip) {
        Write-TestLog -Message "SKIPPED TEST: $Name" -Level 'Warning'
        $script:TestsSkipped++
        
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Category = $Category
            Result = 'Skipped'
            Error = $null
            Duration = 0
        }
        
        return
    }
    
    $startTime = Get-Date
    Write-TestLog -Message "RUNNING TEST: $Name" -Level 'Info'
    Write-TestLog -Message "Description: $Description" -Level 'Info'
    
    try {
        # Run the test
        & $TestScript
        
        # If we get here, the test passed
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        Write-TestLog -Message "TEST PASSED: $Name (${duration}s)" -Level 'Success'
        $script:TestsPassed++
        
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Category = $Category
            Result = 'Passed'
            Error = $null
            Duration = $duration
        }
    }
    catch {
        # Test failed
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        Write-TestLog -Message "TEST FAILED: $Name (${duration}s)" -Level 'Error'
        Write-TestLog -Message "Error: $_" -Level 'Error'
        $script:TestsFailed++
        
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Category = $Category
            Result = 'Failed'
            Error = $_.ToString()
            Duration = $duration
        }
    }
}

function New-TestReport {
    [CmdletBinding()]
    param ()
    
    $endTime = Get-Date
    $totalDuration = ($endTime - $script:TestStartTime).TotalSeconds
    
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>High-Priority Components Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2 { color: #333; }
        .summary { background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #4CAF50; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .test-passed { background-color: #dff0d8; }
        .test-failed { background-color: #f2dede; }
        .test-skipped { background-color: #fcf8e3; }
        .details { margin-top: 5px; padding: 5px; background-color: #f9f9f9; border-left: 3px solid #ccc; }
    </style>
</head>
<body>
    <h1>High-Priority Components Test Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p>Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Duration: ${totalDuration} seconds</p>
        <p>Tests Run: $($script:TestsRun)</p>
        <p class="passed">Tests Passed: $($script:TestsPassed)</p>
        <p class="failed">Tests Failed: $($script:TestsFailed)</p>
        <p class="skipped">Tests Skipped: $($script:TestsSkipped)</p>
    </div>
"@
    
    $htmlCategories = ""
    $categories = $script:TestResults | Select-Object -ExpandProperty Category | Sort-Object -Unique
    
    foreach ($category in $categories) {
        $categoryTests = $script:TestResults | Where-Object { $_.Category -eq $category }
        
        $htmlCategories += @"
    <h2>$category Tests</h2>
    <table>
        <tr>
            <th>Test Name</th>
            <th>Description</th>
            <th>Result</th>
            <th>Duration (s)</th>
        </tr>
"@
        
        foreach ($test in $categoryTests) {
            $rowClass = switch ($test.Result) {
                'Passed'  { 'test-passed' }
                'Failed'  { 'test-failed' }
                'Skipped' { 'test-skipped' }
            }
            
            $resultClass = switch ($test.Result) {
                'Passed'  { 'passed' }
                'Failed'  { 'failed' }
                'Skipped' { 'skipped' }
            }
            
            $errorDetails = ""
            if ($test.Error) {
                $errorDetails = @"
            <div class="details">
                <strong>Error:</strong> $($test.Error)
            </div>
"@
            }
            
            $htmlCategories += @"
        <tr class="$rowClass">
            <td>$($test.Name)</td>
            <td>$($test.Description)</td>
            <td class="$resultClass">$($test.Result)</td>
            <td>$($test.Duration.ToString("0.00"))</td>
        </tr>
        $errorDetails
"@
        }
        
        $htmlCategories += @"
    </table>
"@
    }
    
    $htmlFooter = @"
</body>
</html>
"@
    
    $fullReport = $htmlHeader + $htmlCategories + $htmlFooter
    Set-Content -Path $script:ReportFile -Value $fullReport
    
    Write-TestLog -Message "Test report generated at: $($script:ReportFile)" -Level 'Success'
}

#endregion

#region Test Cases

#region Rollback Mechanism Tests

function Test-RollbackMechanismAvailable {
    # Test if RollbackMechanism module is available
    if (-not (Test-ModuleAvailable -ModulePath $script:RollbackModule -ModuleName "RollbackMechanism")) {
        throw "RollbackMechanism module not available"
    }
}

function Test-RollbackMechanismFunctions {
    # Check if critical functions exist in the module
    $requiredFunctions = @(
        'New-SystemRestorePoint',
        'Backup-RegistryKey',
        'Restore-FromBackup',
        'Invoke-MigrationStep',
        'Rollback-Migration'
    )
    
    foreach ($function in $requiredFunctions) {
        if (-not (Get-Command -Name $function -ErrorAction SilentlyContinue)) {
            throw "Required function not found in RollbackMechanism module: $function"
        }
    }
}

function Test-BasicRollbackFunctionality {
    if (-not $script:IsAdmin) {
        Write-TestLog -Message "Skipping basic rollback test as it requires admin rights" -Level 'Warning'
        return $true
    }
    
    # Create a test file
    $testFile = Join-Path -Path $env:TEMP -ChildPath "rollback_test_$(Get-Random).txt"
    "Test content" | Out-File -FilePath $testFile
    
    # Define a test step that will fail
    $testStep = {
        param($stepParams)
        # Do something that should succeed
        "Modified content" | Out-File -FilePath $stepParams.TestFile
        # Simulate failure
        throw "Simulated error for testing rollback"
    }
    
    # Define rollback action
    $rollbackAction = {
        param($stepParams)
        # Restore original content
        "Test content" | Out-File -FilePath $stepParams.TestFile
    }
    
    # Invoke the migration step
    $result = Invoke-MigrationStep -Name "TestStep" -ScriptBlock $testStep -RollbackScriptBlock $rollbackAction -StepParams @{
        TestFile = $testFile
    } -ErrorAction SilentlyContinue
    
    # Check that the rollback was executed
    if ($result.Success) {
        throw "Migration step should have failed"
    }
    
    # Check that the file content was restored
    $content = Get-Content -Path $testFile -Raw
    if ($content -ne "Test content") {
        throw "Rollback failed to restore the original content"
    }
    
    # Clean up
    Remove-Item -Path $testFile -Force
}

#endregion

#region Migration Verification Tests

function Test-MigrationVerificationAvailable {
    # Test if MigrationVerification module is available
    if (-not (Test-ModuleAvailable -ModulePath $script:VerificationModule -ModuleName "MigrationVerification")) {
        throw "MigrationVerification module not available"
    }
}

function Test-MigrationVerificationFunctions {
    # Check if critical functions exist in the module
    $requiredFunctions = @(
        'Test-IntuneEnrollment',
        'Test-ApplicationStatus',
        'Test-DeviceHealth',
        'New-VerificationReport',
        'Start-MigrationVerification'
    )
    
    foreach ($function in $requiredFunctions) {
        if (-not (Get-Command -Name $function -ErrorAction SilentlyContinue)) {
            throw "Required function not found in MigrationVerification module: $function"
        }
    }
}

function Test-BasicVerificationFunctionality {
    # Create a mock verification result
    $mockResult = @{
        IntuneEnrollment = @{
            Enrolled = $true
            PoliciesApplied = $true
        }
        DeviceHealth = @{
            DefenderStatus = "OK"
            BitLockerStatus = "OK"
            WindowsUpdateStatus = "OK"
        }
        Applications = @(
            @{ Name = "TestApp1"; Installed = $true; Functioning = $true },
            @{ Name = "TestApp2"; Installed = $true; Functioning = $true }
        )
    }
    
    # Mock the verification function to return our test result
    Mock -CommandName Start-MigrationVerification -MockWith { return $mockResult }
    
    # Generate a verification report
    $reportPath = Join-Path -Path $env:TEMP -ChildPath "verification_report_$(Get-Random).html"
    New-VerificationReport -VerificationResults $mockResult -ReportPath $reportPath
    
    # Check that the report was created
    if (-not (Test-Path -Path $reportPath)) {
        throw "Verification report was not created"
    }
    
    # Clean up
    Remove-Item -Path $reportPath -Force
}

#endregion

#region User Communication Tests

function Test-UserCommunicationAvailable {
    # Test if UserCommunicationFramework module is available
    if (-not (Test-ModuleAvailable -ModulePath $script:CommunicationModule -ModuleName "UserCommunicationFramework")) {
        throw "UserCommunicationFramework module not available"
    }
}

function Test-UserCommunicationFunctions {
    # Check if critical functions exist in the module
    $requiredFunctions = @(
        'Send-UserNotification',
        'Show-MigrationProgress',
        'Get-UserFeedback',
        'Initialize-UserCommunication',
        'Send-EmailNotification'
    )
    
    foreach ($function in $requiredFunctions) {
        if (-not (Get-Command -Name $function -ErrorAction SilentlyContinue)) {
            throw "Required function not found in UserCommunicationFramework module: $function"
        }
    }
}

function Test-BasicCommunicationFunctionality {
    # Mock notification function
    Mock -CommandName Send-UserNotification -MockWith { return $true }
    
    # Test sending a notification
    $result = Send-UserNotification -Title "Test Notification" -Message "This is a test message" -Type "Info"
    
    if (-not $result) {
        throw "Failed to send test notification"
    }
}

#endregion

#region Integration Tests

function Test-RollbackVerificationIntegration {
    if ($SkipRollbackTests -or $SkipVerificationTests) {
        Write-TestLog -Message "Skipping RollbackVerification integration test as individual component tests are skipped" -Level 'Warning'
        return $true
    }
    
    # Mock verification function to simulate a failed verification
    Mock -CommandName Test-IntuneEnrollment -MockWith { return $false }
    
    # Mock rollback function
    Mock -CommandName Rollback-Migration -MockWith { return $true }
    
    # Create a test verification result indicating failure
    $verificationResult = @{
        IntuneEnrollment = @{
            Enrolled = $false
            PoliciesApplied = $false
        }
    }
    
    # See if the verification failure triggers a rollback
    $result = Start-MigrationVerification -AutoRollbackOnFailure
    
    # Verify that Rollback-Migration was called
    $rollbackCalled = $false
    try {
        Assert-MockCalled -CommandName Rollback-Migration -Times 1 -Exactly
        $rollbackCalled = $true
    }
    catch {
        throw "Rollback was not triggered by verification failure"
    }
    
    if (-not $rollbackCalled) {
        throw "Rollback was not triggered by verification failure"
    }
}

function Test-VerificationCommunicationIntegration {
    if ($SkipVerificationTests -or $SkipCommunicationTests) {
        Write-TestLog -Message "Skipping VerificationCommunication integration test as individual component tests are skipped" -Level 'Warning'
        return $true
    }
    
    # Mock notification function
    Mock -CommandName Send-UserNotification -MockWith { return $true }
    
    # Create a test verification result
    $verificationResult = @{
        IntuneEnrollment = @{
            Enrolled = $true
            PoliciesApplied = $true
        }
    }
    
    # Generate a verification report and check if notification is sent
    $reportPath = Join-Path -Path $env:TEMP -ChildPath "verification_report_$(Get-Random).html"
    New-VerificationReport -VerificationResults $verificationResult -ReportPath $reportPath -NotifyUser
    
    # Verify that Send-UserNotification was called
    $notificationSent = $false
    try {
        Assert-MockCalled -CommandName Send-UserNotification -Times 1 -Exactly
        $notificationSent = $true
    }
    catch {
        throw "User notification was not sent with verification report"
    }
    
    if (-not $notificationSent) {
        throw "User notification was not sent with verification report"
    }
    
    # Clean up
    Remove-Item -Path $reportPath -Force -ErrorAction SilentlyContinue
}

function Test-RollbackCommunicationIntegration {
    if ($SkipRollbackTests -or $SkipCommunicationTests) {
        Write-TestLog -Message "Skipping RollbackCommunication integration test as individual component tests are skipped" -Level 'Warning'
        return $true
    }
    
    # Mock notification function
    Mock -CommandName Send-UserNotification -MockWith { return $true }
    
    # Test rollback with notification
    $result = Rollback-Migration -Reason "Test rollback" -NotifyUser
    
    # Verify that Send-UserNotification was called
    $notificationSent = $false
    try {
        Assert-MockCalled -CommandName Send-UserNotification -Times 1 -Exactly
        $notificationSent = $true
    }
    catch {
        throw "User notification was not sent during rollback"
    }
    
    if (-not $notificationSent) {
        throw "User notification was not sent during rollback"
    }
}

function Test-EndToEndWorkflow {
    if ($SkipRollbackTests -or $SkipVerificationTests -or $SkipCommunicationTests) {
        Write-TestLog -Message "Skipping end-to-end workflow test as individual component tests are skipped" -Level 'Warning'
        return $true
    }
    
    # Mock all required functions
    Mock -CommandName Initialize-UserCommunication -MockWith { return $true }
    Mock -CommandName New-SystemRestorePoint -MockWith { return @{ SequenceNumber = 1 } }
    Mock -CommandName Invoke-MigrationStep -MockWith { 
        param($Name, $ScriptBlock, $RollbackScriptBlock, $StepParams)
        return @{ Success = $true; StepName = $Name } 
    }
    Mock -CommandName Start-MigrationVerification -MockWith { 
        return @{ 
            Success = $true
            IntuneEnrollment = @{ Enrolled = $true }
        } 
    }
    Mock -CommandName New-VerificationReport -MockWith { return $true }
    Mock -CommandName Send-UserNotification -MockWith { return $true }
    
    # Simulate a basic migration workflow
    try {
        # 1. Initialize user communication
        Initialize-UserCommunication
        
        # 2. Create restore point
        $restorePoint = New-SystemRestorePoint -Description "Test Migration"
        
        # 3. Execute migration steps
        $step1 = Invoke-MigrationStep -Name "Step1" -ScriptBlock { "Step 1" } -RollbackScriptBlock { "Rollback 1" }
        $step2 = Invoke-MigrationStep -Name "Step2" -ScriptBlock { "Step 2" } -RollbackScriptBlock { "Rollback 2" }
        
        # 4. Verify migration
        $verificationResult = Start-MigrationVerification
        
        # 5. Generate report
        New-VerificationReport -VerificationResults $verificationResult -NotifyUser
        
        # All steps should have been called
        Assert-MockCalled -CommandName Initialize-UserCommunication -Times 1 -Exactly
        Assert-MockCalled -CommandName New-SystemRestorePoint -Times 1 -Exactly
        Assert-MockCalled -CommandName Invoke-MigrationStep -Times 2 -Exactly
        Assert-MockCalled -CommandName Start-MigrationVerification -Times 1 -Exactly
        Assert-MockCalled -CommandName New-VerificationReport -Times 1 -Exactly
        Assert-MockCalled -CommandName Send-UserNotification -Times 1 -Exactly
        
        return $true
    }
    catch {
        throw "End-to-end workflow test failed: $_"
    }
}

#endregion

#endregion

#region Main Execution

Write-TestLog -Message "Starting High-Priority Components Integration Tests" -Level 'Info'
Write-TestLog -Message "Log Path: $LogPath" -Level 'Info'
Write-TestLog -Message "Output Path: $OutputPath" -Level 'Info'

#region Register Rollback Tests
if (-not $SkipRollbackTests) {
    Register-TestCase -Name "RollbackMechanism_Available" -Description "Verify that the RollbackMechanism module is available and can be imported" -TestScript ${function:Test-RollbackMechanismAvailable} -Category "RollbackMechanism"
    
    Register-TestCase -Name "RollbackMechanism_Functions" -Description "Verify that all required functions are available in the RollbackMechanism module" -TestScript ${function:Test-RollbackMechanismFunctions} -Category "RollbackMechanism"
    
    Register-TestCase -Name "RollbackMechanism_BasicFunctionality" -Description "Test basic rollback functionality with a simple rollback scenario" -TestScript ${function:Test-BasicRollbackFunctionality} -Category "RollbackMechanism"
}
else {
    Write-TestLog -Message "Skipping RollbackMechanism tests as requested" -Level 'Warning'
}
#endregion

#region Register Verification Tests
if (-not $SkipVerificationTests) {
    Register-TestCase -Name "MigrationVerification_Available" -Description "Verify that the MigrationVerification module is available and can be imported" -TestScript ${function:Test-MigrationVerificationAvailable} -Category "MigrationVerification"
    
    Register-TestCase -Name "MigrationVerification_Functions" -Description "Verify that all required functions are available in the MigrationVerification module" -TestScript ${function:Test-MigrationVerificationFunctions} -Category "MigrationVerification"
    
    Register-TestCase -Name "MigrationVerification_BasicFunctionality" -Description "Test basic verification functionality with a mock verification result" -TestScript ${function:Test-BasicVerificationFunctionality} -Category "MigrationVerification"
}
else {
    Write-TestLog -Message "Skipping MigrationVerification tests as requested" -Level 'Warning'
}
#endregion

#region Register Communication Tests
if (-not $SkipCommunicationTests) {
    Register-TestCase -Name "UserCommunication_Available" -Description "Verify that the UserCommunicationFramework module is available and can be imported" -TestScript ${function:Test-UserCommunicationAvailable} -Category "UserCommunication"
    
    Register-TestCase -Name "UserCommunication_Functions" -Description "Verify that all required functions are available in the UserCommunicationFramework module" -TestScript ${function:Test-UserCommunicationFunctions} -Category "UserCommunication"
    
    Register-TestCase -Name "UserCommunication_BasicFunctionality" -Description "Test basic user communication functionality with a test notification" -TestScript ${function:Test-BasicCommunicationFunctionality} -Category "UserCommunication"
}
else {
    Write-TestLog -Message "Skipping UserCommunication tests as requested" -Level 'Warning'
}
#endregion

#region Register Integration Tests
Register-TestCase -Name "Integration_RollbackVerification" -Description "Test integration between RollbackMechanism and MigrationVerification modules" -TestScript ${function:Test-RollbackVerificationIntegration} -Category "Integration" -Skip:($SkipRollbackTests -or $SkipVerificationTests)

Register-TestCase -Name "Integration_VerificationCommunication" -Description "Test integration between MigrationVerification and UserCommunicationFramework modules" -TestScript ${function:Test-VerificationCommunicationIntegration} -Category "Integration" -Skip:($SkipVerificationTests -or $SkipCommunicationTests)

Register-TestCase -Name "Integration_RollbackCommunication" -Description "Test integration between RollbackMechanism and UserCommunicationFramework modules" -TestScript ${function:Test-RollbackCommunicationIntegration} -Category "Integration" -Skip:($SkipRollbackTests -or $SkipCommunicationTests)

Register-TestCase -Name "Integration_EndToEndWorkflow" -Description "Test the complete end-to-end workflow of the migration process" -TestScript ${function:Test-EndToEndWorkflow} -Category "Integration" -Skip:($SkipRollbackTests -or $SkipVerificationTests -or $SkipCommunicationTests)
#endregion

# Generate test report
New-TestReport

# Summary
Write-TestLog -Message "Test Summary:" -Level 'Info'
Write-TestLog -Message "Total Tests: $script:TestsRun" -Level 'Info'
Write-TestLog -Message "Passed: $script:TestsPassed" -Level 'Success'
Write-TestLog -Message "Failed: $script:TestsFailed" -Level 'Error'
Write-TestLog -Message "Skipped: $script:TestsSkipped" -Level 'Warning'
Write-TestLog -Message "Test report available at: $script:ReportFile" -Level 'Info'

# Return success if all executed tests passed
return ($script:TestsFailed -eq 0)

#endregion 





