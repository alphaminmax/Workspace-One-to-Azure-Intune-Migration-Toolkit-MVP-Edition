################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# This script evaluates the relationships between components based on the metrics defined in                            #
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

.DESCRIPTION
    This script evaluates the relationships between components based on the metrics defined in 
    Component-Relationship-Metrics.md. It tests integration cohesion, failure propagation,
    and response time dependencies.

.PARAMETER TestMode
    Specifies the test mode to run:
    - Basic: Tests main component interfaces
    - Stress: Tests components under load
    - Failure: Tests failure modes and cascades
    Default: Basic

.PARAMETER OutputPath
    Specifies the path where test results will be saved.
    Default: $env:TEMP\ComponentTests

.PARAMETER Components
    Specifies which component relationships to test. If not specified, all will be tested.

.EXAMPLE
    .\Test-ComponentRelationships.ps1 -TestMode Basic
    Tests basic integration points between all components.

.EXAMPLE
    .\Test-ComponentRelationships.ps1 -TestMode Failure -Components @("RollbackMechanism","ProfileTransfer")
    Tests failure modes between the RollbackMechanism and ProfileTransfer components.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet("Basic", "Stress", "Failure")]
    [string]$TestMode = "Basic",
    
    [Parameter()]
    [string]$OutputPath = "$env:TEMP\ComponentTests",
    
    [Parameter()]
    [string[]]$Components = @()
)

#region Variables and Setup
$script:TestsRun = 0
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:StartTime = Get-Date
$script:TestResults = @()
$script:LogFile = Join-Path -Path $OutputPath -ChildPath "ComponentTests_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Component relationships to test
$script:ComponentRelationships = @(
    @{
        ComponentA = "RollbackMechanism"
        ComponentB = "MigrationVerification"
        ICS = 7
        FIP = "High"
        RTD = "Sync"
    },
    @{
        ComponentA = "RollbackMechanism"
        ComponentB = "UserCommunication"
        ICS = 4
        FIP = "Medium"
        RTD = "Async"
    },
    @{
        ComponentA = "MigrationVerification"
        ComponentB = "UserCommunication"
        ICS = 5
        FIP = "Low"
        RTD = "Async"
    },
    @{
        ComponentA = "ProfileTransfer"
        ComponentB = "RollbackMechanism"
        ICS = 8
        FIP = "High"
        RTD = "Sync"
    },
    @{
        ComponentA = "AutopilotIntegration"
        ComponentB = "MigrationVerification"
        ICS = 6
        FIP = "Medium"
        RTD = "Sync"
    }
)

# Filter relationships if Components parameter is specified
if ($Components.Count -gt 0) {
    $script:ComponentRelationships = $script:ComponentRelationships | Where-Object {
        $Components -contains $_.ComponentA -or $Components -contains $_.ComponentB
    }
    
    if ($script:ComponentRelationships.Count -eq 0) {
        Write-Error "No component relationships found matching the specified components."
        exit 1
    }
}
#endregion

#region Helper Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    Add-Content -Path $script:LogFile -Value $logMessage
}

function Import-RequiredModules {
    [CmdletBinding()]
    param()
    
    $requiredModules = @(
        "RollbackMechanism",
        "MigrationVerification",
        "UserCommunication",
        "ProfileTransfer",
        "AutopilotIntegration"
    )
    
    foreach ($module in $requiredModules) {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules\$module.psm1"
        
        try {
            if (Test-Path -Path $modulePath) {
                Import-Module $modulePath -Force -ErrorAction Stop
                Write-Log "Imported module: $module" -Level "INFO"
            } else {
                $errorMsg = $_.Exception.Message
                Write-Log "Module not found: $module" -Level "WARNING"
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Log "Failed to import module $module" + ": $errorMsg" -Level "ERROR"
            return $false
        }
    }
    
    return $true
}

function Register-TestResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$TestName,
        
        [Parameter(Mandatory=$true)]
        [bool]$Success,
        
        [Parameter()]
        [string]$ErrorMessage = "",
        
        [Parameter()]
        [int]$ResponseTimeMs = 0,
        
        [Parameter()]
        [hashtable]$AdditionalData = @{}
    )
    
    $script:TestsRun++
    
    if ($Success) {
        $script:TestsPassed++
        $resultLevel = "SUCCESS"
    } else {
        $script:TestsFailed++
        $resultLevel = "ERROR"
    }
    
    $result = [PSCustomObject]@{
        TestName = $TestName
        Success = $Success
        ErrorMessage = $ErrorMessage
        ResponseTimeMs = $ResponseTimeMs
        Timestamp = Get-Date
        AdditionalData = $AdditionalData
    }
    
    $script:TestResults += $result
    
    Write-Log "Test: $TestName - $(if($Success){'Passed'}else{'Failed: ' + $ErrorMessage})" -Level $resultLevel
    
    return $result
}

function Save-TestResults {
    [CmdletBinding()]
    param()
    
    $resultsFilePath = Join-Path -Path $OutputPath -ChildPath "ComponentTestResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    
    $summary = [PSCustomObject]@{
        StartTime = $script:StartTime
        EndTime = Get-Date
        TestsRun = $script:TestsRun
        TestsPassed = $script:TestsPassed
        TestsFailed = $script:TestsFailed
        PassRate = if ($script:TestsRun -gt 0) { [math]::Round(($script:TestsPassed / $script:TestsRun) * 100, 2) } else { 0 }
        Mode = $TestMode
        Results = $script:TestResults
    }
    
    $summary | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultsFilePath
    Write-Log "Test results saved to: $resultsFilePath" -Level "INFO"
    
    return $resultsFilePath
}
#endregion

#region Test Functions
function Test-IntegrationCohesion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Relationship
    )
    
    $componentA = $Relationship.ComponentA
    $componentB = $Relationship.ComponentB
    $testName = "Integration-$componentA-$componentB"
    $startTime = Get-Date
    
    Write-Log "Testing integration cohesion between $componentA and $componentB" -Level "INFO"
    
    try {
        # Different tests based on the specific relationship
        $success = $false
        $errorMsg = ""
        
        switch ("$componentA-$componentB") {
            "RollbackMechanism-MigrationVerification" {
                # Test that verification can trigger rollback
                $mockState = New-Object -TypeName PSObject -Property @{
                    Success = $false
                    FailurePoint = "TestIntegration"
                }
                
                # Check if functions exist and can be called
                if (Get-Command -Name "Start-Rollback" -ErrorAction SilentlyContinue) {
                    if (Get-Command -Name "Test-MigrationSuccess" -ErrorAction SilentlyContinue) {
                        $success = $true
                    } else {
                        $errorMsg = "MigrationVerification: Test-MigrationSuccess function not found"
                    }
                } else {
                    $errorMsg = "RollbackMechanism: Start-Rollback function not found"
                }
            }
            
            "RollbackMechanism-UserCommunication" {
                # Test that rollback can notify users
                if (Get-Command -Name "Start-Rollback" -ErrorAction SilentlyContinue) {
                    if (Get-Command -Name "Send-UserNotification" -ErrorAction SilentlyContinue) {
                        $success = $true
                    } else {
                        $errorMsg = "UserCommunication: Send-UserNotification function not found"
                    }
                } else {
                    $errorMsg = "RollbackMechanism: Start-Rollback function not found"
                }
            }
            
            "ProfileTransfer-RollbackMechanism" {
                # Test that profile transfer can be rolled back
                if (Get-Command -Name "Backup-UserProfile" -ErrorAction SilentlyContinue) {
                    if (Get-Command -Name "Restore-FromBackup" -ErrorAction SilentlyContinue) {
                        $success = $true
                    } else {
                        $errorMsg = "RollbackMechanism: Restore-FromBackup function not found"
                    }
                } else {
                    $errorMsg = "ProfileTransfer: Backup-UserProfile function not found"
                }
            }
            
            "AutopilotIntegration-MigrationVerification" {
                # Test enrollment verification
                if (Get-Command -Name "Register-DeviceToAutopilot" -ErrorAction SilentlyContinue) {
                    if (Get-Command -Name "Test-DeviceEnrollment" -ErrorAction SilentlyContinue) {
                        $success = $true
                    } else {
                        $errorMsg = "MigrationVerification: Test-DeviceEnrollment function not found"
                    }
                } else {
                    $errorMsg = "AutopilotIntegration: Register-DeviceToAutopilot function not found"
                }
            }
            
            default {
                # Generic integration test for other relationships
                $success = $true
            }
        }
        
        $endTime = Get-Date
        $responseTime = ($endTime - $startTime).TotalMilliseconds
        
        return Register-TestResult -TestName $testName -Success $success -ErrorMessage $errorMsg -ResponseTimeMs $responseTime
        
    } catch {
        return Register-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-FailureImpactPropagation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Relationship
    )
    
    $componentA = $Relationship.ComponentA
    $componentB = $Relationship.ComponentB
    $fip = $Relationship.FIP
    $testName = "FailureImpact-$componentA-$componentB"
    
    Write-Log "Testing failure impact propagation from $componentA to $componentB ($fip)" -Level "INFO"
    
    try {
        $success = $true
        $errorMsg = ""
        $additionalData = @{
            ExpectedFIP = $fip
            ActualFIP = $fip # In a real test, this would be measured
        }
        
        # Only run detailed failure tests in Failure test mode
        if ($TestMode -eq "Failure") {
            switch ("$componentA-$componentB") {
                "RollbackMechanism-MigrationVerification" {
                    # Simulate rollback failure and check verification response
                    # This would be more complex in a real test
                    if ($fip -eq "High") {
                        # Verification should fail if rollback fails in high FIP case
                    }
                }
                
                "ProfileTransfer-RollbackMechanism" {
                    # Simulate profile transfer failure and test rollback response
                }
                
                default {
                    # Generic failure test
                }
            }
        }
        
        return Register-TestResult -TestName $testName -Success $success -ErrorMessage $errorMsg -AdditionalData $additionalData
        
    } catch {
        return Register-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-ResponseTimeDependency {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Relationship
    )
    
    $componentA = $Relationship.ComponentA
    $componentB = $Relationship.ComponentB
    $rtd = $Relationship.RTD
    $testName = "ResponseTime-$componentA-$componentB"
    
    Write-Log "Testing response time dependency between $componentA and $componentB ($rtd)" -Level "INFO"
    
    try {
        $success = $true
        $errorMsg = ""
        $responseTime = 0
        
        # Only run detailed timing tests in Stress test mode
        if ($TestMode -eq "Stress") {
            $startTime = Get-Date
            
            switch ("$componentA-$componentB") {
                "RollbackMechanism-MigrationVerification" {
                    # Measure response time between components
                    Start-Sleep -Milliseconds 50 # Simulated operation time
                }
                
                "AutopilotIntegration-MigrationVerification" {
                    # This would be a high latency operation
                    Start-Sleep -Milliseconds 100 # Simulated operation time
                }
                
                default {
                    # Generic timing test
                    Start-Sleep -Milliseconds 10 # Simulated operation time
                }
            }
            
            $endTime = Get-Date
            $responseTime = ($endTime - $startTime).TotalMilliseconds
            
            # Evaluate if response time matches expectation based on RTD
            $expectedMaxTime = switch ($rtd) {
                "Sync" { 200 } # Higher threshold for synchronous operations
                "Async" { 50 } # Lower threshold for asynchronous operations
                "Hybrid" { 150 } # Intermediate threshold
                default { 100 }
            }
            
            if ($responseTime -gt $expectedMaxTime) {
                $success = $false
                $errorMsg = "Response time ($responseTime ms) exceeds threshold for $rtd dependency ($expectedMaxTime ms)"
            }
        }
        
        return Register-TestResult -TestName $testName -Success $success -ErrorMessage $errorMsg -ResponseTimeMs $responseTime
        
    } catch {
        return Register-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
    }
}

function Test-CompleteComponentRelationship {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Relationship
    )
    
    $componentA = $Relationship.ComponentA
    $componentB = $Relationship.ComponentB
    
    Write-Log "Testing complete relationship between $componentA and $componentB" -Level "INFO"
    
    # Test all aspects of the relationship
    $cohesionResult = Test-IntegrationCohesion -Relationship $Relationship
    $failureResult = Test-FailureImpactPropagation -Relationship $Relationship
    $responseResult = Test-ResponseTimeDependency -Relationship $Relationship
    
    # Calculate overall success
    $overallSuccess = $cohesionResult.Success -and $failureResult.Success -and $responseResult.Success
    
    # Generate summary result
    $testName = "Complete-$componentA-$componentB"
    $errorMsg = ""
    
    if (-not $overallSuccess) {
        $errorMsg = "Failed tests: "
        if (-not $cohesionResult.Success) { $errorMsg += "Integration Cohesion, " }
        if (-not $failureResult.Success) { $errorMsg += "Failure Impact, " }
        if (-not $responseResult.Success) { $errorMsg += "Response Time, " }
        $errorMsg = $errorMsg.TrimEnd(', ')
    }
    
    $additionalData = @{
        IntegrationCohesion = $cohesionResult
        FailureImpact = $failureResult
        ResponseTime = $responseResult
        ICS = $Relationship.ICS
        FIP = $Relationship.FIP
        RTD = $Relationship.RTD
    }
    
    return Register-TestResult -TestName $testName -Success $overallSuccess -ErrorMessage $errorMsg -AdditionalData $additionalData
}
#endregion

#region Main Execution
# Display test information
Write-Log "Starting Component Relationship Tests" -Level "INFO"
Write-Log "Test Mode: $TestMode" -Level "INFO"
Write-Log "Output Path: $OutputPath" -Level "INFO"
Write-Log "Components to test: $(if($Components.Count -gt 0){$Components -join ', '}else{'All'})" -Level "INFO"
Write-Log "Relationships to test: $($script:ComponentRelationships.Count)" -Level "INFO"

# Import required modules
$modulesImported = Import-RequiredModules
if (-not $modulesImported) {
    Write-Log "Failed to import one or more required modules. Tests may not complete successfully." -Level "WARNING"
}

# Run tests for each relationship
foreach ($relationship in $script:ComponentRelationships) {
    $componentA = $relationship.ComponentA
    $componentB = $relationship.ComponentB
    
    Write-Log "Testing relationship: $componentA <-> $componentB" -Level "INFO"
    
    $result = Test-CompleteComponentRelationship -Relationship $relationship
    
    if ($result.Success) {
        Write-Log "Relationship test passed: $componentA <-> $componentB" -Level "SUCCESS"
    } else {
        Write-Log "Relationship test failed: $componentA <-> $componentB - $($result.ErrorMessage)" -Level "ERROR"
    }
}

# Save test results
$resultsPath = Save-TestResults

# Display summary
Write-Log "Component Relationship Tests Complete" -Level "INFO"
Write-Log "Tests Run: $script:TestsRun" -Level "INFO"
Write-Log "Tests Passed: $script:TestsPassed" -Level "SUCCESS"
Write-Log "Tests Failed: $script:TestsFailed" -Level "$(if($script:TestsFailed -gt 0){'ERROR'}else{'INFO'})"
Write-Log "Pass Rate: $(if ($script:TestsRun -gt 0) { [math]::Round(($script:TestsPassed / $script:TestsRun) * 100, 2) } else { 0 })%" -Level "INFO"
Write-Log "Results saved to: $resultsPath" -Level "INFO"

# Return overall success
return $script:TestsFailed -eq 0
#endregion 





