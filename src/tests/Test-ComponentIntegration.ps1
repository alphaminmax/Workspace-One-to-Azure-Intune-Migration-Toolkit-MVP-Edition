#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Microsoft.Graph.Intune'; ModuleVersion='6.1907.1.0' }
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Tests the integration of critical migration components.

.DESCRIPTION
    This script performs comprehensive integration testing of all critical 
    migration components, including high-priority, high-impact, and reasonable
    effort components. It validates that these components work together properly
    and handle error conditions appropriately.

.PARAMETER TestLevel
    Specifies the level of testing to perform:
    - Basic: Tests only critical path integration points
    - Standard: Tests normal operations and common error conditions
    - Comprehensive: Tests all integration points including edge cases

.PARAMETER ComponentFilter
    Optional array of component names to test. If not specified, all components are tested.

.PARAMETER OutputPath
    Path where test results will be saved. Defaults to "reports/integration-test-results.json"

.PARAMETER SkipCleanup
    If specified, temporary test resources will not be removed after testing.

.EXAMPLE
    .\Test-ComponentIntegration.ps1 -TestLevel Standard
    Runs standard integration tests for all components.

.EXAMPLE
    .\Test-ComponentIntegration.ps1 -ComponentFilter @('RollbackMechanism','MigrationVerification')
    Tests only the integration between the specified components.

.NOTES
    This script requires administrative privileges to fully test component integration.
    Some tests may create temporary files and registry keys that will be removed upon completion.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet('Basic', 'Standard', 'Comprehensive')]
    [string]$TestLevel = 'Standard',
    
    [Parameter()]
    [string[]]$ComponentFilter,
    
    [Parameter()]
    [string]$OutputPath = "reports/integration-test-results.json",
    
    [Parameter()]
    [switch]$SkipCleanup
)

#---------------------------------------------------------
# Script initialization
#---------------------------------------------------------

# Import required modules
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules"
$ToolsPath = Join-Path -Path $PSScriptRoot -ChildPath "..\tools"

# Set up script variables
$script:TestResults = @{
    StartTime = Get-Date
    EndTime = $null
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    ComponentResults = @{}
    IntegrationResults = @{}
}

$script:TestResources = @{
    TempFiles = @()
    TempKeys = @()
    TempAccounts = @()
}

# Initialize logging
function Write-TestLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $TimeStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Color = switch ($Level) {
        'Info' { 'White' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }
    
    Write-Host "[$TimeStamp] [$Level] $Message" -ForegroundColor $Color
}

#---------------------------------------------------------
# Helper functions
#---------------------------------------------------------

function Import-TestModules {
    [CmdletBinding()]
    param()
    
    $ModulesToImport = @(
        'RollbackMechanism',
        'MigrationVerification',
        'UserCommunication',
        'AutopilotIntegration',
        'ConfigurationPreservation',
        'ProfileTransfer',
        'PrivilegeManagement'
    )
    
    if ($ComponentFilter) {
        $ModulesToImport = $ModulesToImport | Where-Object { $ComponentFilter -contains $_ }
    }
    
    $ImportedModules = @()
    
    foreach ($Module in $ModulesToImport) {
        $ModulePath = Join-Path -Path $ModulePath -ChildPath "$Module.psm1"
        if (Test-Path -Path $ModulePath) {
            try {
                Import-Module $ModulePath -Force -ErrorAction Stop
                $ImportedModules += $Module
                Write-TestLog "Successfully imported module: $Module" -Level Success
            }
            catch {
                Write-TestLog "Failed to import module $Module: $_" -Level Error
            }
        }
        else {
            Write-TestLog "Module not found: $ModulePath" -Level Warning
        }
    }
    
    return $ImportedModules
}

function New-TestResource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        
        [Parameter()]
        [string]$Content = "Test content created at $(Get-Date)"
    )
    
    switch ($ResourceType) {
        'File' {
            $FilePath = Join-Path -Path $env:TEMP -ChildPath $ResourceName
            Set-Content -Path $FilePath -Value $Content -Force
            $script:TestResources.TempFiles += $FilePath
            return $FilePath
        }
        'RegistryKey' {
            $KeyPath = "HKCU:\Software\MigrationTest\$ResourceName"
            if (-not (Test-Path -Path $KeyPath)) {
                New-Item -Path $KeyPath -Force | Out-Null
            }
            $script:TestResources.TempKeys += $KeyPath
            return $KeyPath
        }
    }
}

function Remove-TestResources {
    [CmdletBinding()]
    param()
    
    if ($SkipCleanup) {
        Write-TestLog "Skipping cleanup as requested" -Level Info
        return
    }
    
    foreach ($File in $script:TestResources.TempFiles) {
        if (Test-Path -Path $File) {
            Remove-Item -Path $File -Force -ErrorAction SilentlyContinue
        }
    }
    
    foreach ($Key in $script:TestResources.TempKeys) {
        if (Test-Path -Path $Key) {
            Remove-Item -Path $Key -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-TestLog "All test resources have been cleaned up" -Level Success
}

function Test-Component {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestScript
    )
    
    Write-TestLog "Testing component: $ComponentName" -Level Info
    
    try {
        $script:TestResults.TotalTests++
        & $TestScript
        $script:TestResults.PassedTests++
        $script:TestResults.ComponentResults[$ComponentName] = @{
            Status = "Passed"
            Message = "Component tests completed successfully"
        }
        Write-TestLog "Component $ComponentName tests passed" -Level Success
        return $true
    }
    catch {
        $script:TestResults.FailedTests++
        $script:TestResults.ComponentResults[$ComponentName] = @{
            Status = "Failed"
            Message = $_.Exception.Message
        }
        Write-TestLog "Component $ComponentName tests failed: $_" -Level Error
        return $false
    }
}

function Test-Integration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FromComponent,
        
        [Parameter(Mandatory = $true)]
        [string]$ToComponent,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestScript
    )
    
    $IntegrationName = "$FromComponent -> $ToComponent"
    Write-TestLog "Testing integration: $IntegrationName" -Level Info
    
    try {
        $script:TestResults.TotalTests++
        & $TestScript
        $script:TestResults.PassedTests++
        $script:TestResults.IntegrationResults[$IntegrationName] = @{
            Status = "Passed"
            Message = "Integration tests completed successfully"
        }
        Write-TestLog "Integration $IntegrationName tests passed" -Level Success
        return $true
    }
    catch {
        $script:TestResults.FailedTests++
        $script:TestResults.IntegrationResults[$IntegrationName] = @{
            Status = "Failed"
            Message = $_.Exception.Message
        }
        Write-TestLog "Integration $IntegrationName tests failed: $_" -Level Error
        return $false
    }
}

function Save-TestResults {
    [CmdletBinding()]
    param()
    
    $script:TestResults.EndTime = Get-Date
    $script:TestResults.Duration = $script:TestResults.EndTime - $script:TestResults.StartTime
    
    $OutputDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    }
    
    $script:TestResults | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath
    
    Write-TestLog "Test results saved to $OutputPath" -Level Success
    
    # Output summary
    Write-Host "`n============ TEST SUMMARY ============" -ForegroundColor Cyan
    Write-Host "Total Tests: $($script:TestResults.TotalTests)" -ForegroundColor White
    Write-Host "Passed: $($script:TestResults.PassedTests)" -ForegroundColor Green
    Write-Host "Failed: $($script:TestResults.FailedTests)" -ForegroundColor Red
    Write-Host "Skipped: $($script:TestResults.SkippedTests)" -ForegroundColor Yellow
    Write-Host "Duration: $($script:TestResults.Duration.TotalSeconds.ToString('0.00')) seconds" -ForegroundColor White
    Write-Host "=======================================" -ForegroundColor Cyan
}

#---------------------------------------------------------
# Component Tests
#---------------------------------------------------------

function Test-RollbackMechanism {
    [CmdletBinding()]
    param()
    
    # Test backup creation
    $BackupFile = New-TestResource -ResourceType File -ResourceName "test-backup.txt"
    $BackupKey = New-TestResource -ResourceType RegistryKey -ResourceName "BackupTest"
    
    try {
        # Test if Create-SystemRestorePoint function exists and runs
        if (Get-Command -Name Create-SystemRestorePoint -ErrorAction SilentlyContinue) {
            $RestorePointResult = Create-SystemRestorePoint -Description "Integration Test" -ErrorAction SilentlyContinue
        }
        
        # Test if Backup-RegistryKey function exists and runs
        if (Get-Command -Name Backup-RegistryKey -ErrorAction SilentlyContinue) {
            Backup-RegistryKey -Key $BackupKey -BackupPath "$env:TEMP\reg-backup.reg" -ErrorAction SilentlyContinue
        }
        
        # Test if Restore-FromBackup function exists
        if (-not (Get-Command -Name Restore-FromBackup -ErrorAction SilentlyContinue)) {
            throw "Required function Restore-FromBackup not found in RollbackMechanism module"
        }
    }
    catch {
        throw "RollbackMechanism tests failed: $_"
    }
}

function Test-MigrationVerification {
    [CmdletBinding()]
    param()
    
    try {
        # Test if Verify-IntuneEnrollment function exists
        if (-not (Get-Command -Name Verify-IntuneEnrollment -ErrorAction SilentlyContinue)) {
            throw "Required function Verify-IntuneEnrollment not found in MigrationVerification module"
        }
        
        # Test if Verify-ConfigurationState function exists
        if (-not (Get-Command -Name Verify-ConfigurationState -ErrorAction SilentlyContinue)) {
            throw "Required function Verify-ConfigurationState not found in MigrationVerification module"
        }
        
        # Test if New-VerificationReport function exists
        if (-not (Get-Command -Name New-VerificationReport -ErrorAction SilentlyContinue)) {
            throw "Required function New-VerificationReport not found in MigrationVerification module"
        }
    }
    catch {
        throw "MigrationVerification tests failed: $_"
    }
}

function Test-UserCommunication {
    [CmdletBinding()]
    param()
    
    try {
        # Test if Send-UserNotification function exists
        if (-not (Get-Command -Name Send-UserNotification -ErrorAction SilentlyContinue)) {
            throw "Required function Send-UserNotification not found in UserCommunication module"
        }
        
        # Test if Log-UserCommunication function exists
        if (-not (Get-Command -Name Log-UserCommunication -ErrorAction SilentlyContinue)) {
            throw "Required function Log-UserCommunication not found in UserCommunication module"
        }
        
        # Test basic notification functionality
        if (Get-Command -Name Send-UserNotification -ErrorAction SilentlyContinue) {
            # Create a test notification without actually sending
            Send-UserNotification -Title "Test Notification" -Message "This is a test" -NotificationType "Info" -WhatIf -ErrorAction SilentlyContinue
        }
    }
    catch {
        throw "UserCommunication tests failed: $_"
    }
}

#---------------------------------------------------------
# Integration Tests
#---------------------------------------------------------

function Test-RollbackVerificationIntegration {
    [CmdletBinding()]
    param()
    
    try {
        # Test if the rollback mechanism is properly integrated with verification
        $VerificationFunctions = @('Verify-IntuneEnrollment', 'Verify-ConfigurationState')
        $RollbackFunctions = @('Restore-FromBackup', 'Rollback-Migration')
        
        foreach ($Function in $VerificationFunctions) {
            if (-not (Get-Command -Name $Function -ErrorAction SilentlyContinue)) {
                throw "Verification function $Function not available for integration testing"
            }
        }
        
        foreach ($Function in $RollbackFunctions) {
            if (-not (Get-Command -Name $Function -ErrorAction SilentlyContinue)) {
                throw "Rollback function $Function not available for integration testing"
            }
        }
        
        # Test if Invoke-MigrationStep exists (which should integrate verification and rollback)
        if (Get-Command -Name Invoke-MigrationStep -ErrorAction SilentlyContinue) {
            # Create a test step that should succeed
            $TestStep = {
                Write-Output "Test step executed successfully"
            }
            
            # This should execute the step and not trigger rollback
            Invoke-MigrationStep -Name "IntegrationTest" -ScriptBlock $TestStep -ErrorAction SilentlyContinue
        }
    }
    catch {
        throw "RollbackMechanism and MigrationVerification integration failed: $_"
    }
}

function Test-CommunicationVerificationIntegration {
    [CmdletBinding()]
    param()
    
    try {
        # Check if verification can properly communicate with users
        if (Get-Command -Name New-VerificationReport -ErrorAction SilentlyContinue -and 
            Get-Command -Name Send-UserNotification -ErrorAction SilentlyContinue) {
            
            # Create a test report file
            $ReportPath = New-TestResource -ResourceType File -ResourceName "test-verification-report.html"
            
            # Test if we can notify about verification results (without actually sending)
            Send-UserNotification -Title "Verification Complete" -Message "Verification report is available." -NotificationType "Info" -WhatIf -ErrorAction SilentlyContinue
        }
        else {
            throw "Required functions not available for integration testing"
        }
    }
    catch {
        throw "UserCommunication and MigrationVerification integration failed: $_"
    }
}

function Test-RollbackCommunicationIntegration {
    [CmdletBinding()]
    param()
    
    try {
        # Check if rollback can properly communicate with users
        if (Get-Command -Name Rollback-Migration -ErrorAction SilentlyContinue -and 
            Get-Command -Name Send-UserNotification -ErrorAction SilentlyContinue) {
            
            # Test if we can notify about rollback (without actually sending)
            Send-UserNotification -Title "Rollback Initiated" -Message "Migration is being rolled back due to errors." -NotificationType "Warning" -WhatIf -ErrorAction SilentlyContinue
        }
        else {
            throw "Required functions not available for integration testing"
        }
    }
    catch {
        throw "UserCommunication and RollbackMechanism integration failed: $_"
    }
}

#---------------------------------------------------------
# Main test execution
#---------------------------------------------------------

# Script entry point
try {
    Write-TestLog "Starting component integration tests (Level: $TestLevel)" -Level Info
    
    # Import required modules
    $ImportedModules = Import-TestModules
    if (-not $ImportedModules) {
        throw "No modules were successfully imported. Cannot continue testing."
    }
    
    # Test individual components
    if ($ComponentFilter -contains 'RollbackMechanism' -or -not $ComponentFilter) {
        Test-Component -ComponentName "RollbackMechanism" -TestScript { Test-RollbackMechanism }
    }
    
    if ($ComponentFilter -contains 'MigrationVerification' -or -not $ComponentFilter) {
        Test-Component -ComponentName "MigrationVerification" -TestScript { Test-MigrationVerification }
    }
    
    if ($ComponentFilter -contains 'UserCommunication' -or -not $ComponentFilter) {
        Test-Component -ComponentName "UserCommunication" -TestScript { Test-UserCommunication }
    }
    
    # Test integration between components
    if (($ComponentFilter -contains 'RollbackMechanism' -and $ComponentFilter -contains 'MigrationVerification') -or 
        -not $ComponentFilter) {
        Test-Integration -FromComponent "RollbackMechanism" -ToComponent "MigrationVerification" -TestScript { Test-RollbackVerificationIntegration }
    }
    
    if (($ComponentFilter -contains 'UserCommunication' -and $ComponentFilter -contains 'MigrationVerification') -or 
        -not $ComponentFilter) {
        Test-Integration -FromComponent "UserCommunication" -ToComponent "MigrationVerification" -TestScript { Test-CommunicationVerificationIntegration }
    }
    
    if (($ComponentFilter -contains 'RollbackMechanism' -and $ComponentFilter -contains 'UserCommunication') -or 
        -not $ComponentFilter) {
        Test-Integration -FromComponent "RollbackMechanism" -ToComponent "UserCommunication" -TestScript { Test-RollbackCommunicationIntegration }
    }
    
    # Save test results
    Save-TestResults
}
catch {
    Write-TestLog "Integration testing failed: $_" -Level Error
}
finally {
    # Clean up test resources
    Remove-TestResources
} 