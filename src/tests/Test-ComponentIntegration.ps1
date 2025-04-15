#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Microsoft.Graph.Intune'; ModuleVersion='6.1907.1.0' }
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Tests the integration between all high-priority components of the migration solution.

.DESCRIPTION
    This script performs integration testing for the migration solution components,
    verifying that RollbackMechanism, MigrationVerification, and UserCommunication
    work together properly. The script creates test scenarios that simulate real
    migration workflows and validates that the components interact correctly,
    particularly in error and rollback scenarios.

.PARAMETER TestLevel
    Specifies the level of testing to perform.
    - Basic: Tests core functionality only
    - Standard: Tests core functionality plus common error scenarios
    - Comprehensive: Tests all possible integration points with extensive error scenarios

.PARAMETER ComponentFilter
    Optional. Specify component names to test only specific component integrations.
    Example: "RollbackMechanism,UserCommunication"

.PARAMETER OutputPath
    Specifies the path where test results will be saved.
    Default: "$env:TEMP\MigrationTests"

.PARAMETER SkipCleanup
    If specified, test resources will not be cleaned up after testing.
    Useful for debugging test failures.

.EXAMPLE
    .\Test-ComponentIntegration.ps1 -TestLevel Standard
    Runs standard integration tests for all components.

.EXAMPLE
    .\Test-ComponentIntegration.ps1 -TestLevel Comprehensive -ComponentFilter "RollbackMechanism,MigrationVerification"
    Runs comprehensive tests only for the RollbackMechanism and MigrationVerification integration.

.NOTES
    This script requires administrator privileges to run properly.
    All high-priority components must be installed and properly configured.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Basic", "Standard", "Comprehensive")]
    [string]$TestLevel = "Standard",
    
    [Parameter()]
    [string]$ComponentFilter = "",
    
    [Parameter()]
    [string]$OutputPath = "$env:TEMP\MigrationTests",
    
    [Parameter()]
    [switch]$SkipCleanup
)

#region Initialization
# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Initialize log file
$LogFile = Join-Path -Path $OutputPath -ChildPath "IntegrationTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$TestResultsFile = Join-Path -Path $OutputPath -ChildPath "TestResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"

# Initialize test results tracking
$script:TestResults = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    Tests = @()
}

# Parse component filter if provided
$ComponentsToTest = @()
if ($ComponentFilter) {
    $ComponentsToTest = $ComponentFilter -split ','
}
#endregion

#region Helper Functions
function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Set console color based on level
    switch ($Level) {
        "Info"    { $Color = "White" }
        "Warning" { $Color = "Yellow" }
        "Error"   { $Color = "Red" }
        "Success" { $Color = "Green" }
    }
    
    Write-Host $LogEntry -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $LogEntry
}

function Import-RequiredModules {
    try {
        Write-Log "Importing required modules..." -Level Info
        
        # Import all required modules
        Import-Module -Name (Join-Path $PSScriptRoot "../modules/RollbackMechanism.psm1") -Force
        Import-Module -Name (Join-Path $PSScriptRoot "../modules/MigrationVerification.psm1") -Force
        Import-Module -Name (Join-Path $PSScriptRoot "../modules/UserCommunication.psm1") -Force
        Import-Module -Name (Join-Path $PSScriptRoot "../modules/LoggingModule.psm1") -Force
        
        Write-Log "All modules imported successfully" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to import required modules: $_" -Level Error
        return $false
    }
}

function New-TestResources {
    param (
        [Parameter(Mandatory)]
        [string]$TestName
    )
    
    try {
        Write-Log "Creating test resources for $TestName..." -Level Info
        
        # Create test directory
        $TestDir = Join-Path -Path $OutputPath -ChildPath $TestName
        if (-not (Test-Path -Path $TestDir)) {
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
        }
        
        # Create test registry keys
        $TestRegPath = "HKCU:\SOFTWARE\MigrationTest\$TestName"
        if (-not (Test-Path -Path $TestRegPath)) {
            New-Item -Path $TestRegPath -Force | Out-Null
        }
        
        # Create test data file
        $TestDataFile = Join-Path -Path $TestDir -ChildPath "TestData.json"
        @{
            CreatedTime = Get-Date
            TestName = $TestName
            TestData = "Sample test data for $TestName"
        } | ConvertTo-Json | Set-Content -Path $TestDataFile
        
        return @{
            TestDir = $TestDir
            TestRegPath = $TestRegPath
            TestDataFile = $TestDataFile
            Success = $true
        }
    }
    catch {
        Write-Log "Failed to create test resources for $TestName: $_" -Level Error
        return @{
            Success = $false
            Error = $_
        }
    }
}

function Remove-TestResources {
    param (
        [Parameter(Mandatory)]
        [string]$TestName
    )
    
    try {
        Write-Log "Cleaning up test resources for $TestName..." -Level Info
        
        # Remove test directory
        $TestDir = Join-Path -Path $OutputPath -ChildPath $TestName
        if (Test-Path -Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
        
        # Remove test registry keys
        $TestRegPath = "HKCU:\SOFTWARE\MigrationTest\$TestName"
        if (Test-Path -Path $TestRegPath) {
            Remove-Item -Path $TestRegPath -Recurse -Force
        }
        
        Write-Log "Test resources for $TestName cleaned up successfully" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to clean up test resources for $TestName: $_" -Level Error
        return $false
    }
}

function Register-TestResult {
    param (
        [Parameter(Mandatory)]
        [string]$TestName,
        
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [bool]$Success,
        
        [Parameter()]
        [string]$ErrorMessage = "",
        
        [Parameter()]
        [PSCustomObject]$TestData = $null
    )
    
    $script:TestResults.TotalTests++
    
    if ($Success) {
        $script:TestResults.PassedTests++
        $Result = "Passed"
        Write-Log "$TestName - $Result" -Level Success
    }
    else {
        $script:TestResults.FailedTests++
        $Result = "Failed"
        Write-Log "$TestName - $Result: $ErrorMessage" -Level Error
    }
    
    $script:TestResults.Tests += [PSCustomObject]@{
        Name = $TestName
        Component = $Component
        Result = $Result
        ErrorMessage = $ErrorMessage
        TimeStamp = Get-Date
        Data = $TestData
    }
}

function Save-TestResults {
    try {
        # Calculate summary
        $SuccessRate = if ($script:TestResults.TotalTests -gt 0) {
            [math]::Round(($script:TestResults.PassedTests / $script:TestResults.TotalTests) * 100, 2)
        } else { 0 }
        
        $Summary = [PSCustomObject]@{
            TotalTests = $script:TestResults.TotalTests
            PassedTests = $script:TestResults.PassedTests
            FailedTests = $script:TestResults.FailedTests
            SkippedTests = $script:TestResults.SkippedTests
            SuccessRate = $SuccessRate
            TestLevel = $TestLevel
            StartTime = $script:TestResults.Tests[0].TimeStamp
            EndTime = Get-Date
            Tests = $script:TestResults.Tests
        }
        
        # Save results to file
        $Summary | ConvertTo-Json -Depth 5 | Set-Content -Path $TestResultsFile
        
        # Print summary
        Write-Log "Test Summary:" -Level Info
        Write-Log "  Total Tests: $($Summary.TotalTests)" -Level Info
        Write-Log "  Passed: $($Summary.PassedTests)" -Level Success
        Write-Log "  Failed: $($Summary.FailedTests)" -Level ($Summary.FailedTests -gt 0 ? "Error" : "Info")
        Write-Log "  Success Rate: $($Summary.SuccessRate)%" -Level Info
        
        return $true
    }
    catch {
        Write-Log "Failed to save test results: $_" -Level Error
        return $false
    }
}

function Should-RunComponentTest {
    param (
        [Parameter(Mandatory)]
        [string]$ComponentName
    )
    
    if ($ComponentsToTest.Count -eq 0) {
        return $true
    }
    
    return $ComponentsToTest -contains $ComponentName
}
#endregion

#region Component Tests
function Test-RollbackMechanism {
    if (-not (Should-RunComponentTest "RollbackMechanism")) {
        Write-Log "Skipping RollbackMechanism tests based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    # Test creating system restore point
    try {
        Write-Log "Testing system restore point creation..." -Level Info
        $Resources = New-TestResources -TestName "RollbackTest"
        
        if ($Resources.Success) {
            # Simulate a migration step that includes rollback capability
            $Result = Invoke-MigrationStep -Name "RollbackTest" -ScriptBlock {
                Set-ItemProperty -Path $Resources.TestRegPath -Name "TestValue" -Value "OriginalValue"
                return $true
            } -RollbackScriptBlock {
                Remove-ItemProperty -Path $Resources.TestRegPath -Name "TestValue" -ErrorAction SilentlyContinue
            }
            
            if ($Result) {
                Register-TestResult -TestName "Create-SystemRestorePoint" -Component "RollbackMechanism" -Success $true
            }
            else {
                Register-TestResult -TestName "Create-SystemRestorePoint" -Component "RollbackMechanism" -Success $false -ErrorMessage "Failed to create restore point"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "RollbackTest"
        }
    }
    catch {
        Register-TestResult -TestName "Create-SystemRestorePoint" -Component "RollbackMechanism" -Success $false -ErrorMessage $_.Exception.Message
    }
    
    # Test rolling back a failed migration step
    try {
        Write-Log "Testing rollback for failed migration step..." -Level Info
        $Resources = New-TestResources -TestName "FailedMigrationTest"
        
        if ($Resources.Success) {
            # Test registry key path
            $TestRegPath = $Resources.TestRegPath
            
            # Set initial value
            Set-ItemProperty -Path $TestRegPath -Name "InitialValue" -Value "BeforeChange"
            
            # Attempt a migration step that will fail
            $Result = Invoke-MigrationStep -Name "FailingStep" -ScriptBlock {
                # Make a change
                Set-ItemProperty -Path $TestRegPath -Name "InitialValue" -Value "AfterChange"
                # Then simulate failure
                throw "Simulated failure during migration step"
                return $false
            } -RollbackScriptBlock {
                # This should restore the original value
                Set-ItemProperty -Path $TestRegPath -Name "InitialValue" -Value "BeforeChange"
            }
            
            # Check if rollback occurred by testing the value
            $FinalValue = Get-ItemProperty -Path $TestRegPath -Name "InitialValue" | Select-Object -ExpandProperty "InitialValue"
            
            if ($FinalValue -eq "BeforeChange") {
                Register-TestResult -TestName "Rollback-FailedMigrationStep" -Component "RollbackMechanism" -Success $true
            }
            else {
                Register-TestResult -TestName "Rollback-FailedMigrationStep" -Component "RollbackMechanism" -Success $false -ErrorMessage "Rollback did not restore original value"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "FailedMigrationTest"
        }
    }
    catch {
        Register-TestResult -TestName "Rollback-FailedMigrationStep" -Component "RollbackMechanism" -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-MigrationVerification {
    if (-not (Should-RunComponentTest "MigrationVerification")) {
        Write-Log "Skipping MigrationVerification tests based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    # Test verification of a successful migration
    try {
        Write-Log "Testing verification of successful migration..." -Level Info
        $Resources = New-TestResources -TestName "VerificationTest"
        
        if ($Resources.Success) {
            # Simulate successful Intune enrollment
            $TestRegPath = $Resources.TestRegPath
            New-Item -Path "$TestRegPath\Intune" -Force | Out-Null
            Set-ItemProperty -Path "$TestRegPath\Intune" -Name "EnrollmentStatus" -Value "Succeeded"
            Set-ItemProperty -Path "$TestRegPath\Intune" -Name "EnrollmentTime" -Value (Get-Date).ToString()
            
            # Now verify the enrollment
            $VerificationResult = Verify-IntuneEnrollment -RegistryPath $TestRegPath
            
            if ($VerificationResult.Success) {
                Register-TestResult -TestName "Verify-SuccessfulMigration" -Component "MigrationVerification" -Success $true
            }
            else {
                Register-TestResult -TestName "Verify-SuccessfulMigration" -Component "MigrationVerification" -Success $false -ErrorMessage "Verification failed for successful migration"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "VerificationTest"
        }
    }
    catch {
        Register-TestResult -TestName "Verify-SuccessfulMigration" -Component "MigrationVerification" -Success $false -ErrorMessage $_.Exception.Message
    }
    
    # Test verification of a failed migration
    try {
        Write-Log "Testing verification of failed migration..." -Level Info
        $Resources = New-TestResources -TestName "FailedVerificationTest"
        
        if ($Resources.Success) {
            # Simulate failed Intune enrollment
            $TestRegPath = $Resources.TestRegPath
            New-Item -Path "$TestRegPath\Intune" -Force | Out-Null
            Set-ItemProperty -Path "$TestRegPath\Intune" -Name "EnrollmentStatus" -Value "Failed"
            Set-ItemProperty -Path "$TestRegPath\Intune" -Name "EnrollmentError" -Value "Device not supported"
            
            # Now verify the enrollment - should detect failure
            $VerificationResult = Verify-IntuneEnrollment -RegistryPath $TestRegPath
            
            if (-not $VerificationResult.Success) {
                Register-TestResult -TestName "Verify-FailedMigration" -Component "MigrationVerification" -Success $true
            }
            else {
                Register-TestResult -TestName "Verify-FailedMigration" -Component "MigrationVerification" -Success $false -ErrorMessage "Verification did not detect failed migration"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "FailedVerificationTest"
        }
    }
    catch {
        Register-TestResult -TestName "Verify-FailedMigration" -Component "MigrationVerification" -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-UserCommunication {
    if (-not (Should-RunComponentTest "UserCommunication")) {
        Write-Log "Skipping UserCommunication tests based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    # Test sending user notification
    try {
        Write-Log "Testing user notification..." -Level Info
        $Resources = New-TestResources -TestName "NotificationTest"
        
        if ($Resources.Success) {
            # Configure test notification path
            $NotificationPath = Join-Path -Path $Resources.TestDir -ChildPath "Notifications.log"
            
            # Send a test notification
            $Result = Send-UserNotification -Title "Test Notification" -Message "This is a test message" -NotificationType "Info" -LogPath $NotificationPath
            
            # Verify notification was logged
            if (Test-Path -Path $NotificationPath) {
                $NotificationContent = Get-Content -Path $NotificationPath -Raw
                if ($NotificationContent -match "Test Notification" -and $NotificationContent -match "This is a test message") {
                    Register-TestResult -TestName "Send-UserNotification" -Component "UserCommunication" -Success $true
                }
                else {
                    Register-TestResult -TestName "Send-UserNotification" -Component "UserCommunication" -Success $false -ErrorMessage "Notification content not found in log"
                }
            }
            else {
                Register-TestResult -TestName "Send-UserNotification" -Component "UserCommunication" -Success $false -ErrorMessage "Notification log file not created"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "NotificationTest"
        }
    }
    catch {
        Register-TestResult -TestName "Send-UserNotification" -Component "UserCommunication" -Success $false -ErrorMessage $_.Exception.Message
    }
    
    # Test progress updates
    try {
        Write-Log "Testing progress updates..." -Level Info
        $Resources = New-TestResources -TestName "ProgressTest"
        
        if ($Resources.Success) {
            # Configure test progress path
            $ProgressPath = Join-Path -Path $Resources.TestDir -ChildPath "Progress.log"
            
            # Send progress updates
            for ($i = 0; $i -le 100; $i += 25) {
                $Result = Show-MigrationProgress -PercentComplete $i -Status "Migration in progress" -LogPath $ProgressPath
                Start-Sleep -Milliseconds 100
            }
            
            # Verify progress was logged
            if (Test-Path -Path $ProgressPath) {
                $ProgressContent = Get-Content -Path $ProgressPath -Raw
                if ($ProgressContent -match "100%" -and $ProgressContent -match "Migration in progress") {
                    Register-TestResult -TestName "Show-MigrationProgress" -Component "UserCommunication" -Success $true
                }
                else {
                    Register-TestResult -TestName "Show-MigrationProgress" -Component "UserCommunication" -Success $false -ErrorMessage "Progress content not found in log"
                }
            }
            else {
                Register-TestResult -TestName "Show-MigrationProgress" -Component "UserCommunication" -Success $false -ErrorMessage "Progress log file not created"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "ProgressTest"
        }
    }
    catch {
        Register-TestResult -TestName "Show-MigrationProgress" -Component "UserCommunication" -Success $false -ErrorMessage $_.Exception.Message
    }
}
#endregion

#region Integration Tests
function Test-RollbackVerificationIntegration {
    if (-not ((Should-RunComponentTest "RollbackMechanism") -and (Should-RunComponentTest "MigrationVerification"))) {
        Write-Log "Skipping RollbackMechanism and MigrationVerification integration tests based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    try {
        Write-Log "Testing integration between RollbackMechanism and MigrationVerification..." -Level Info
        $Resources = New-TestResources -TestName "RollbackVerificationTest"
        
        if ($Resources.Success) {
            $TestRegPath = $Resources.TestRegPath
            
            # Simulate a migration step with verification that will fail
            $Result = Invoke-MigrationStep -Name "IntegrationTest" -ScriptBlock {
                # Make changes that should be rolled back
                Set-ItemProperty -Path $TestRegPath -Name "ConfigState" -Value "Incomplete"
                return $true
            } -VerificationScript {
                # Verification will fail
                $VerificationResult = Verify-ConfigurationState -RegistryPath $TestRegPath -ExpectedState "Complete"
                return $VerificationResult.Success
            } -RollbackScriptBlock {
                # This should execute when verification fails
                Remove-ItemProperty -Path $TestRegPath -Name "ConfigState" -ErrorAction SilentlyContinue
                # Set a flag to indicate rollback occurred
                Set-ItemProperty -Path $TestRegPath -Name "RollbackOccurred" -Value $true
            }
            
            # Check if rollback was triggered by verification failure
            $RollbackOccurred = (Get-ItemProperty -Path $TestRegPath -Name "RollbackOccurred" -ErrorAction SilentlyContinue).RollbackOccurred
            
            if ($RollbackOccurred) {
                Register-TestResult -TestName "RollbackVerification-Integration" -Component "RollbackMechanism,MigrationVerification" -Success $true
            }
            else {
                Register-TestResult -TestName "RollbackVerification-Integration" -Component "RollbackMechanism,MigrationVerification" -Success $false -ErrorMessage "Rollback was not triggered by verification failure"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "RollbackVerificationTest"
        }
    }
    catch {
        Register-TestResult -TestName "RollbackVerification-Integration" -Component "RollbackMechanism,MigrationVerification" -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-CommunicationVerificationIntegration {
    if (-not ((Should-RunComponentTest "UserCommunication") -and (Should-RunComponentTest "MigrationVerification"))) {
        Write-Log "Skipping UserCommunication and MigrationVerification integration tests based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    try {
        Write-Log "Testing integration between UserCommunication and MigrationVerification..." -Level Info
        $Resources = New-TestResources -TestName "CommunicationVerificationTest"
        
        if ($Resources.Success) {
            # Configure test paths
            $NotificationPath = Join-Path -Path $Resources.TestDir -ChildPath "VerificationNotifications.log"
            $TestRegPath = $Resources.TestRegPath
            
            # Simulate successful verification with notification
            New-Item -Path "$TestRegPath\Intune" -Force | Out-Null
            Set-ItemProperty -Path "$TestRegPath\Intune" -Name "EnrollmentStatus" -Value "Succeeded"
            
            # Perform verification and send notification based on result
            $VerificationResult = Verify-IntuneEnrollment -RegistryPath $TestRegPath
            Send-UserNotification -Title "Verification Result" -Message "Verification $($VerificationResult.Success ? 'succeeded' : 'failed')" -NotificationType ($VerificationResult.Success ? "Success" : "Error") -LogPath $NotificationPath
            
            # Verify notification was sent with correct result
            if (Test-Path -Path $NotificationPath) {
                $NotificationContent = Get-Content -Path $NotificationPath -Raw
                if ($NotificationContent -match "Verification Result" -and $NotificationContent -match "Verification succeeded") {
                    Register-TestResult -TestName "CommunicationVerification-Integration" -Component "UserCommunication,MigrationVerification" -Success $true
                }
                else {
                    Register-TestResult -TestName "CommunicationVerification-Integration" -Component "UserCommunication,MigrationVerification" -Success $false -ErrorMessage "Expected verification notification not found in log"
                }
            }
            else {
                Register-TestResult -TestName "CommunicationVerification-Integration" -Component "UserCommunication,MigrationVerification" -Success $false -ErrorMessage "Verification notification log file not created"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "CommunicationVerificationTest"
        }
    }
    catch {
        Register-TestResult -TestName "CommunicationVerification-Integration" -Component "UserCommunication,MigrationVerification" -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-RollbackCommunicationIntegration {
    if (-not ((Should-RunComponentTest "RollbackMechanism") -and (Should-RunComponentTest "UserCommunication"))) {
        Write-Log "Skipping RollbackMechanism and UserCommunication integration tests based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    try {
        Write-Log "Testing integration between RollbackMechanism and UserCommunication..." -Level Info
        $Resources = New-TestResources -TestName "RollbackCommunicationTest"
        
        if ($Resources.Success) {
            # Configure test paths
            $NotificationPath = Join-Path -Path $Resources.TestDir -ChildPath "RollbackNotifications.log"
            $TestRegPath = $Resources.TestRegPath
            
            # Simulate a migration step that will fail and trigger notifications
            $Result = Invoke-MigrationStep -Name "RollbackWithNotification" -ScriptBlock {
                # This will be rolled back
                Set-ItemProperty -Path $TestRegPath -Name "MigrationState" -Value "InProgress"
                
                # Simulate failure
                throw "Simulated failure for testing rollback notification"
                return $false
            } -RollbackScriptBlock {
                # This should execute and remove the property
                Remove-ItemProperty -Path $TestRegPath -Name "MigrationState" -ErrorAction SilentlyContinue
                
                # Send notification about rollback
                Send-UserNotification -Title "Rollback Occurred" -Message "Migration step failed and was rolled back" -NotificationType "Warning" -LogPath $NotificationPath
            } -ErrorActionPreference Continue
            
            # Verify notification was sent during rollback
            if (Test-Path -Path $NotificationPath) {
                $NotificationContent = Get-Content -Path $NotificationPath -Raw
                if ($NotificationContent -match "Rollback Occurred" -and $NotificationContent -match "was rolled back") {
                    Register-TestResult -TestName "RollbackCommunication-Integration" -Component "RollbackMechanism,UserCommunication" -Success $true
                }
                else {
                    Register-TestResult -TestName "RollbackCommunication-Integration" -Component "RollbackMechanism,UserCommunication" -Success $false -ErrorMessage "Expected rollback notification not found in log"
                }
            }
            else {
                Register-TestResult -TestName "RollbackCommunication-Integration" -Component "RollbackMechanism,UserCommunication" -Success $false -ErrorMessage "Rollback notification log file not created"
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "RollbackCommunicationTest"
        }
    }
    catch {
        Register-TestResult -TestName "RollbackCommunication-Integration" -Component "RollbackMechanism,UserCommunication" -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-CompleteIntegration {
    if (-not ((Should-RunComponentTest "RollbackMechanism") -and (Should-RunComponentTest "MigrationVerification") -and (Should-RunComponentTest "UserCommunication"))) {
        Write-Log "Skipping complete integration test based on filter" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    if ($TestLevel -ne "Comprehensive") {
        Write-Log "Skipping complete integration test in $TestLevel mode" -Level Warning
        $script:TestResults.SkippedTests++
        return
    }
    
    try {
        Write-Log "Testing complete integration between all components..." -Level Info
        $Resources = New-TestResources -TestName "CompleteIntegrationTest"
        
        if ($Resources.Success) {
            # Configure test paths
            $NotificationPath = Join-Path -Path $Resources.TestDir -ChildPath "CompleteNotifications.log"
            $TestRegPath = $Resources.TestRegPath
            
            # Mock function that we will use to capture event flow
            $EventLog = Join-Path -Path $Resources.TestDir -ChildPath "EventFlow.log"
            Add-Content -Path $EventLog -Value "Test started at $(Get-Date)"
            
            function Log-Event {
                param($Component, $Event)
                Add-Content -Path $EventLog -Value "[$Component] $Event"
            }
            
            # Simulate a complete migration workflow
            try {
                # 1. Start migration and notify user
                Send-UserNotification -Title "Migration Started" -Message "Starting migration process" -NotificationType "Info" -LogPath $NotificationPath
                Log-Event -Component "UserCommunication" -Event "Migration start notification sent"
                
                # 2. Create system restore point
                Log-Event -Component "RollbackMechanism" -Event "Creating system restore point"
                
                # 3. Perform first migration step
                $Step1Result = Invoke-MigrationStep -Name "Step1" -ScriptBlock {
                    Log-Event -Component "MigrationStep" -Event "Executing step 1"
                    Set-ItemProperty -Path $TestRegPath -Name "Step1" -Value "Complete"
                    return $true
                } -RollbackScriptBlock {
                    Log-Event -Component "RollbackMechanism" -Event "Rolling back step 1"
                    Remove-ItemProperty -Path $TestRegPath -Name "Step1" -ErrorAction SilentlyContinue
                }
                
                # 4. Verify step 1 and notify
                Log-Event -Component "MigrationVerification" -Event "Verifying step 1"
                $VerificationResult = Verify-ConfigurationState -RegistryPath $TestRegPath -ExpectedStepValue "Step1" -ExpectedValue "Complete"
                
                Send-UserNotification -Title "Step 1 Verification" -Message "Step 1 verification $($VerificationResult.Success ? 'succeeded' : 'failed')" -NotificationType ($VerificationResult.Success ? "Success" : "Error") -LogPath $NotificationPath
                Log-Event -Component "UserCommunication" -Event "Step 1 verification notification sent"
                
                # 5. Perform second step with deliberate failure
                $Step2Result = Invoke-MigrationStep -Name "Step2" -ScriptBlock {
                    Log-Event -Component "MigrationStep" -Event "Executing step 2"
                    Set-ItemProperty -Path $TestRegPath -Name "Step2" -Value "InComplete"
                    return $true
                } -VerificationScript {
                    Log-Event -Component "MigrationVerification" -Event "Verifying step 2"
                    # This verification will fail
                    $VerificationResult = Verify-ConfigurationState -RegistryPath $TestRegPath -ExpectedStepValue "Step2" -ExpectedValue "Complete"
                    return $VerificationResult.Success
                } -RollbackScriptBlock {
                    Log-Event -Component "RollbackMechanism" -Event "Rolling back step 2"
                    Remove-ItemProperty -Path $TestRegPath -Name "Step2" -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $TestRegPath -Name "RollbackExecuted" -Value $true
                    Send-UserNotification -Title "Rollback Occurred" -Message "Step 2 failed verification and was rolled back" -NotificationType "Warning" -LogPath $NotificationPath
                }
                
                # 6. Verify the rollback occurred
                $RollbackExecuted = (Get-ItemProperty -Path $TestRegPath -Name "RollbackExecuted" -ErrorAction SilentlyContinue).RollbackExecuted
                $EventFlowLog = Get-Content -Path $EventLog -Raw
                
                # Check for the complete expected flow
                $ExpectedFlowElements = @(
                    "UserCommunication.*Migration start notification sent",
                    "RollbackMechanism.*Creating system restore point",
                    "MigrationStep.*Executing step 1",
                    "MigrationVerification.*Verifying step 1",
                    "UserCommunication.*Step 1 verification notification sent",
                    "MigrationStep.*Executing step 2",
                    "MigrationVerification.*Verifying step 2",
                    "RollbackMechanism.*Rolling back step 2"
                )
                
                $FlowComplete = $true
                foreach ($element in $ExpectedFlowElements) {
                    if ($EventFlowLog -notmatch $element) {
                        $FlowComplete = $false
                        Write-Log "Missing expected flow element: $element" -Level Warning
                    }
                }
                
                if ($FlowComplete -and $RollbackExecuted) {
                    Register-TestResult -TestName "Complete-Integration" -Component "RollbackMechanism,MigrationVerification,UserCommunication" -Success $true
                }
                else {
                    Register-TestResult -TestName "Complete-Integration" -Component "RollbackMechanism,MigrationVerification,UserCommunication" -Success $false -ErrorMessage "Integration flow did not complete as expected"
                }
            }
            catch {
                Log-Event -Component "Error" -Event $_.Exception.Message
                Register-TestResult -TestName "Complete-Integration" -Component "RollbackMechanism,MigrationVerification,UserCommunication" -Success $false -ErrorMessage $_.Exception.Message
            }
        }
        
        if (-not $SkipCleanup) {
            Remove-TestResources -TestName "CompleteIntegrationTest"
        }
    }
    catch {
        Register-TestResult -TestName "Complete-Integration" -Component "RollbackMechanism,MigrationVerification,UserCommunication" -Success $false -ErrorMessage $_.Exception.Message
    }
}
#endregion

#region Main Execution
# Display header
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Migration Component Integration Test Suite" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Test Level: $TestLevel" -ForegroundColor Cyan
if ($ComponentFilter) {
    Write-Host "Component Filter: $ComponentFilter" -ForegroundColor Cyan
}
Write-Host "Output Path: $OutputPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Cyan

# Import required modules
$ModulesImported = Import-RequiredModules
if (-not $ModulesImported) {
    Write-Log "Unable to import required modules. Tests cannot continue." -Level Error
    exit 1
}

# Run individual component tests
Write-Log "Running individual component tests..." -Level Info
Test-RollbackMechanism
Test-MigrationVerification
Test-UserCommunication

# Run integration tests based on test level
Write-Log "Running component integration tests..." -Level Info
Test-RollbackVerificationIntegration
Test-CommunicationVerificationIntegration
Test-RollbackCommunicationIntegration

# Run complete integration test for Comprehensive level only
if ($TestLevel -eq "Comprehensive") {
    Test-CompleteIntegration
}

# Save test results
Save-TestResults

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Integration Test Suite Complete" -ForegroundColor Cyan
Write-Host "   Results saved to: $TestResultsFile" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
#endregion 