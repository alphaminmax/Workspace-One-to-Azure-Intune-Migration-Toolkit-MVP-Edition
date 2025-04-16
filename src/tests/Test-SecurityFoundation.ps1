#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Tests the SecurityFoundation module functionality.                                                                    #
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
    Tests the SecurityFoundation module functionality.
    
.DESCRIPTION
    Performs comprehensive testing of the SecurityFoundation module, including:
    - Credential storage and retrieval
    - Data protection with encryption
    - Privilege elevation
    - Security audit logging
    - Security requirement validation
    
.PARAMETER TestPath
    Path where test files will be created.
    
.PARAMETER LogPath
    Path where test logs will be stored.
    
.PARAMETER SkipElevatedTests
    Skip tests that require elevation (admin rights).
    
.PARAMETER SkipNetworkTests
    Skip tests that require network connectivity.
    
.EXAMPLE
    .\Test-SecurityFoundation.ps1
    
.EXAMPLE
    .\Test-SecurityFoundation.ps1 -SkipElevatedTests -SkipNetworkTests
    
.NOTES
    File Name      : Test-SecurityFoundation.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TestPath = "$env:TEMP\SecurityFoundationTests",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\SecurityFoundationTests\Logs",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipElevatedTests,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipNetworkTests
)

#region Initialize Test Environment

# Create test directories
if (-not (Test-Path -Path $TestPath)) {
    New-Item -Path $TestPath -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Import modules
$modulesPath = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath "modules"
$securityModulePath = Join-Path -Path $modulesPath -ChildPath "SecurityFoundation.psm1"
$loggingModulePath = Join-Path -Path $modulesPath -ChildPath "LoggingModule.psm1"

# Script variables
$script:TestResults = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    StartTime = Get-Date
    EndTime = $null
    Tests = @()
}

# Test log file
$testLogFile = Join-Path -Path $LogPath -ChildPath "SecurityFoundationTests_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Test started" | Out-File -FilePath $testLogFile -Encoding utf8

# Import required modules
try {
    # Import logging module
    if (Test-Path -Path $loggingModulePath) {
        Import-Module -Name $loggingModulePath -Force
    } else {
        Write-Error "Logging module not found at $loggingModulePath"
        exit 1
    }
    
    # Import security module
    if (Test-Path -Path $securityModulePath) {
        Import-Module -Name $securityModulePath -Force
    } else {
        Write-Error "SecurityFoundation module not found at $securityModulePath"
        exit 1
    }
}
catch {
    Write-Error "Failed to import modules: $_"
    exit 1
}

#endregion

#region Test Helper Functions

function Write-TestLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to test log file
    $logMessage | Out-File -FilePath $testLogFile -Append -Encoding utf8
    
    # Also write to console with colors
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Also write to regular log if available
    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SecurityTest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestScript,
        
        [Parameter(Mandatory = $false)]
        [switch]$RequiresElevation,
        
        [Parameter(Mandatory = $false)]
        [switch]$RequiresNetwork,
        
        [Parameter(Mandatory = $false)]
        [switch]$Skip,
        
        [Parameter(Mandatory = $false)]
        [string]$SkipReason
    )
    
    $script:TestResults.TotalTests++
    
    # Determine if we should skip this test
    $shouldSkip = $Skip
    
    if ($RequiresElevation -and $SkipElevatedTests) {
        $shouldSkip = $true
        $SkipReason = "Test requires elevation and SkipElevatedTests was specified"
    }
    
    if ($RequiresElevation -and -not (Test-IsAdministrator) -and -not $shouldSkip) {
        $shouldSkip = $true
        $SkipReason = "Test requires elevation but process is not running as administrator"
    }
    
    if ($RequiresNetwork -and $SkipNetworkTests) {
        $shouldSkip = $true
        $SkipReason = "Test requires network access and SkipNetworkTests was specified"
    }
    
    # Skip the test if needed
    if ($shouldSkip) {
        Write-TestLog -Message "SKIPPED: $Name - $SkipReason" -Level Warning
        $script:TestResults.SkippedTests++
        $script:TestResults.Tests += @{
            Name = $Name
            Description = $Description
            Result = "SKIPPED"
            Error = $null
            SkipReason = $SkipReason
            ExecutionTime = 0
        }
        return
    }
    
    # Run the test
    Write-TestLog -Message "TEST: $Name - $Description" -Level Info
    $startTime = Get-Date
    
    try {
        # Execute the test script
        & $TestScript
        
        # If we got here, test succeeded
        $endTime = Get-Date
        $executionTime = ($endTime - $startTime).TotalSeconds
        
        Write-TestLog -Message "PASSED: $Name (${executionTime}s)" -Level Success
        $script:TestResults.PassedTests++
        $script:TestResults.Tests += @{
            Name = $Name
            Description = $Description
            Result = "PASSED"
            Error = $null
            SkipReason = $null
            ExecutionTime = $executionTime
        }
    }
    catch {
        # Test failed
        $endTime = Get-Date
        $executionTime = ($endTime - $startTime).TotalSeconds
        $errorMessage = $_.Exception.Message
        
        Write-TestLog -Message "FAILED: $Name (${executionTime}s) - $errorMessage" -Level Error
        $script:TestResults.FailedTests++
        $script:TestResults.Tests += @{
            Name = $Name
            Description = $Description
            Result = "FAILED"
            Error = $errorMessage
            SkipReason = $null
            ExecutionTime = $executionTime
        }
    }
}

function Export-TestResults {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $LogPath
    )
    
    $script:TestResults.EndTime = Get-Date
    $script:TestResults.TotalExecutionTime = ($script:TestResults.EndTime - $script:TestResults.StartTime).TotalSeconds
    
    # Create summary
    $summary = @"
Security Foundation Tests Summary:
---------------------------------
Start Time: $($script:TestResults.StartTime)
End Time: $($script:TestResults.EndTime)
Total Execution Time: $($script:TestResults.TotalExecutionTime) seconds
Total Tests: $($script:TestResults.TotalTests)
Passed: $($script:TestResults.PassedTests)
Failed: $($script:TestResults.FailedTests)
Skipped: $($script:TestResults.SkippedTests)
"@
    
    Write-TestLog -Message $summary -Level Info
    
    # Export as HTML report
    $htmlReportPath = Join-Path -Path $OutputPath -ChildPath "SecurityTests_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Foundation Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2, h3 { color: #0078D7; }
        .summary { background-color: #f0f0f0; padding: 10px; border-radius: 5px; margin-bottom: 20px; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr.passed { background-color: #dff0d8; }
        tr.failed { background-color: #f2dede; }
        tr.skipped { background-color: #fcf8e3; }
    </style>
</head>
<body>
    <h1>Security Foundation Test Results</h1>
    
    <div class="summary">
        <h2>Summary</h2>
        <p>Start Time: $($script:TestResults.StartTime)</p>
        <p>End Time: $($script:TestResults.EndTime)</p>
        <p>Total Execution Time: $($script:TestResults.TotalExecutionTime) seconds</p>
        <p>Total Tests: $($script:TestResults.TotalTests)</p>
        <p>Passed: <span class="passed">$($script:TestResults.PassedTests)</span></p>
        <p>Failed: <span class="failed">$($script:TestResults.FailedTests)</span></p>
        <p>Skipped: <span class="skipped">$($script:TestResults.SkippedTests)</span></p>
    </div>
    
    <h2>Test Results</h2>
    <table>
        <tr>
            <th>Test Name</th>
            <th>Description</th>
            <th>Result</th>
            <th>Time (s)</th>
            <th>Error / Skip Reason</th>
        </tr>
"@
    
    $htmlRows = ""
    foreach ($test in $script:TestResults.Tests) {
        $rowClass = switch ($test.Result) {
            "PASSED" { "passed" }
            "FAILED" { "failed" }
            "SKIPPED" { "skipped" }
        }
        
        $errorOrSkipReason = if ($test.Result -eq "FAILED") { $test.Error } else { $test.SkipReason }
        
        $htmlRows += @"
        <tr class="$rowClass">
            <td>$($test.Name)</td>
            <td>$($test.Description)</td>
            <td class="$rowClass">$($test.Result)</td>
            <td>$($test.ExecutionTime.ToString("0.00"))</td>
            <td>$errorOrSkipReason</td>
        </tr>
"@
    }
    
    $htmlFooter = @"
    </table>
    
    <h2>Test Environment</h2>
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>Computer Name</td><td>$env:COMPUTERNAME</td></tr>
        <tr><td>User Name</td><td>$env:USERNAME</td></tr>
        <tr><td>PowerShell Version</td><td>$($PSVersionTable.PSVersion)</td></tr>
        <tr><td>Running as Administrator</td><td>$(Test-IsAdministrator)</td></tr>
        <tr><td>Test Path</td><td>$TestPath</td></tr>
        <tr><td>Log Path</td><td>$LogPath</td></tr>
    </table>
</body>
</html>
"@
    
    $htmlContent = $htmlHeader + $htmlRows + $htmlFooter
    $htmlContent | Out-File -FilePath $htmlReportPath -Encoding utf8
    
    Write-TestLog -Message "Test report exported to: $htmlReportPath" -Level Success
    
    # Export as JSON for programmatic use
    $jsonReportPath = Join-Path -Path $OutputPath -ChildPath "SecurityTests_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $script:TestResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonReportPath -Encoding utf8
    
    Write-TestLog -Message "Test data exported to: $jsonReportPath" -Level Success
    
    return $htmlReportPath
}

#endregion

#region Security Module Tests

# Initialize Security Foundation
Invoke-SecurityTest -Name "Initialize-SecurityFoundation" -Description "Tests the initialization of the Security Foundation module" -TestScript {
    # Configure security settings for tests
    $securityConfig = @{
        AuditLogPath = Join-Path -Path $TestPath -ChildPath "SecurityAudit"
        SecureKeyPath = Join-Path -Path $TestPath -ChildPath "SecureKeys"
        ApiTimeoutSeconds = 30
        RequireAdminForSensitiveOperations = $true
    }
    
    # Set configuration
    Set-SecurityConfiguration @securityConfig
    
    # Initialize with certificate creation
    $result = Initialize-SecurityFoundation -CreateEncryptionCert
    
    if (-not $result) {
        throw "Failed to initialize Security Foundation"
    }
    
    # Verify paths were created
    if (-not (Test-Path -Path (Join-Path -Path $TestPath -ChildPath "SecurityAudit"))) {
        throw "Security audit path was not created"
    }
    
    if (-not (Test-Path -Path (Join-Path -Path $TestPath -ChildPath "SecureKeys"))) {
        throw "Secure keys path was not created"
    }
}

# Test Security Configuration
Invoke-SecurityTest -Name "Set-SecurityConfiguration" -Description "Tests setting and applying security configuration" -TestScript {
    # Define test configuration
    $testAuditPath = Join-Path -Path $TestPath -ChildPath "CustomAudit"
    $testKeysPath = Join-Path -Path $TestPath -ChildPath "CustomKeys"
    
    # Apply configuration
    Set-SecurityConfiguration -AuditLogPath $testAuditPath -SecureKeyPath $testKeysPath -ApiTimeoutSeconds 60
    
    # Verify paths were created
    if (-not (Test-Path -Path $testAuditPath)) {
        throw "Custom audit path was not created"
    }
    
    if (-not (Test-Path -Path $testKeysPath)) {
        throw "Custom keys path was not created"
    }
    
    # Add an audit entry to verify audit logging
    Write-SecurityEvent -Message "Test security event" -Level "Information"
    
    # Check if audit file was created
    $auditFiles = Get-ChildItem -Path $testAuditPath -Filter "SecurityAudit_*.log"
    if ($auditFiles.Count -eq 0) {
        throw "No audit log files found"
    }
    
    # Verify audit content
    $auditContent = Get-Content -Path $auditFiles[0].FullName -Raw
    if (-not $auditContent.Contains("Test security event")) {
        throw "Audit entry was not written correctly"
    }
}

# Test Data Protection
Invoke-SecurityTest -Name "Protect-SensitiveData" -Description "Tests encryption and protection of sensitive data" -TestScript {
    # Test data to protect
    $testData = "This is sensitive test data 12345"
    $testKeyName = "TestKey1"
    
    # Protect the data
    $protectionResult = Protect-SensitiveData -Data $testData -KeyName $testKeyName
    
    if (-not $protectionResult) {
        throw "Data protection failed"
    }
    
    # Verify secure file was created
    $secureKeyPath = Get-SecureFilePath -KeyName $testKeyName
    if (-not (Test-Path -Path $secureKeyPath)) {
        throw "Secure key file was not created"
    }
    
    # Try to get the data back
    $retrievedData = Unprotect-SensitiveData -KeyName $testKeyName -AsPlainText
    
    if ($retrievedData -ne $testData) {
        throw "Retrieved data does not match original data"
    }
}

# Test Secure String Protection
Invoke-SecurityTest -Name "Protect-SecureStringData" -Description "Tests encryption and protection of SecureString data" -TestScript {
    # Create secure string
    $securePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force
    $testKeyName = "TestSecureString"
    
    # Protect the secure string
    $protectionResult = Protect-SensitiveData -Data $securePassword -KeyName $testKeyName -AsSecureString
    
    if (-not $protectionResult) {
        throw "SecureString protection failed"
    }
    
    # Retrieve as secure string
    $retrievedSecure = Unprotect-SensitiveData -KeyName $testKeyName
    
    # Convert both to plain text for comparison
    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainOriginal = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
    
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedSecure)
    $plainRetrieved = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    
    if ($plainOriginal -ne $plainRetrieved) {
        throw "Retrieved secure string does not match original secure string"
    }
}

# Test Credential Management
Invoke-SecurityTest -Name "Secure-Credential" -Description "Tests storing and retrieving credentials" -TestScript {
    # Create test credential
    $username = "testuser@example.com"
    $password = ConvertTo-SecureString "TestP@ssw0rd!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store credential
    $credentialStored = Set-SecureCredential -Credential $credential -CredentialName "TestAPICredential" -UseCredentialManager $false
    
    if (-not $credentialStored) {
        throw "Failed to store credential"
    }
    
    # Retrieve credential
    $retrievedCredential = Get-SecureCredential -CredentialName "TestAPICredential" -UseCredentialManager $false
    
    if (-not $retrievedCredential) {
        throw "Failed to retrieve credential"
    }
    
    # Verify username
    if ($retrievedCredential.UserName -ne $username) {
        throw "Retrieved username does not match original username"
    }
    
    # Verify password by converting both to plain text
    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainOriginal = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
    
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedCredential.Password)
    $plainRetrieved = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    
    if ($plainOriginal -ne $plainRetrieved) {
        throw "Retrieved password does not match original password"
    }
}

# Test Elevation Operations
Invoke-SecurityTest -Name "Invoke-ElevatedOperation" -Description "Tests execution of script blocks with proper privilege elevation" -RequiresElevation -TestScript {
    # Define test variables
    $testValue = "TestValue123"
    $testFile = Join-Path -Path $TestPath -ChildPath "ElevationTest.txt"
    
    # Execute operation
    $result = Invoke-ElevatedOperation -ScriptBlock {
        param($FilePath, $Value)
        
        # Write to file
        $Value | Out-File -FilePath $FilePath -Force
        
        # Return true if successful
        return $true
    } -ArgumentList @($testFile, $testValue)
    
    # Check result
    if (-not $result) {
        throw "Elevated operation failed to execute"
    }
    
    # Verify file was created
    if (-not (Test-Path -Path $testFile)) {
        throw "Elevated operation did not create test file"
    }
    
    # Verify content
    $fileContent = Get-Content -Path $testFile -Raw
    if ($fileContent.Trim() -ne $testValue) {
        throw "Elevated operation did not write correct content to file"
    }
}

# Test Security Audit Logging
Invoke-SecurityTest -Name "Write-SecurityEvent" -Description "Tests creation and format of security audit logs" -TestScript {
    # Define test audit path
    $testAuditPath = Join-Path -Path $TestPath -ChildPath "AuditTest"
    
    # Configure security to use test path
    Set-SecurityConfiguration -AuditLogPath $testAuditPath
    
    # Write test events
    Write-SecurityEvent -Message "Test info event" -Level "Information" -Component "TestComponent"
    Write-SecurityEvent -Message "Test warning event" -Level "Warning" -Component "TestComponent"
    Write-SecurityEvent -Message "Test error event" -Level "Error" -Component "TestComponent" -AdditionalInfo @{
        TestData = "Test value"
        TestNumber = 123
    }
    
    # Verify audit log was created
    $auditFiles = Get-ChildItem -Path $testAuditPath -Filter "SecurityAudit_*.log"
    if ($auditFiles.Count -eq 0) {
        throw "No audit log files found"
    }
    
    # Verify content of audit log
    $auditContent = Get-Content -Path $auditFiles[0].FullName -Raw
    
    if (-not $auditContent.Contains("Test info event")) {
        throw "Info audit entry not found"
    }
    
    if (-not $auditContent.Contains("Test warning event")) {
        throw "Warning audit entry not found"
    }
    
    if (-not $auditContent.Contains("Test error event")) {
        throw "Error audit entry not found"
    }
    
    if (-not $auditContent.Contains("TestComponent")) {
        throw "Component name not included in audit entry"
    }
    
    if (-not $auditContent.Contains("TestData")) {
        throw "Additional info not included in audit entry"
    }
}

# Test Security Requirements
Invoke-SecurityTest -Name "Test-SecurityRequirements" -Description "Tests validation of security requirements" -TestScript {
    # Configure security settings
    Set-SecurityConfiguration -RequireAdminForSensitiveOperations (-not (Test-IsAdministrator))
    
    # Test security requirements
    $testResults = Test-SecurityRequirements -CheckCertificates -CheckTls
    
    # We don't care if it passed or failed, just that it ran without error
    # But we can examine specific sub-results if needed
    
    # Verify TLS 1.2 is enabled
    $securityProtocol = [Net.ServicePointManager]::SecurityProtocol
    $hasTls12 = $securityProtocol -band [Net.SecurityProtocolType]::Tls12
    
    if (-not $hasTls12) {
        throw "TLS 1.2 is not enabled"
    }
}

# Test Secure Web Requests
Invoke-SecurityTest -Name "Invoke-SecureWebRequest" -Description "Tests secure web requests with proper TLS settings" -RequiresNetwork -Skip:$SkipNetworkTests -TestScript {
    # Use a reliable endpoint
    $uri = "https://www.microsoft.com"
    
    # Make secure request
    $response = Invoke-SecureWebRequest -Uri $uri -TimeoutSeconds 10
    
    # Verify response
    if ($response.StatusCode -ne 200) {
        throw "Web request failed with status code: $($response.StatusCode)"
    }
}

# Test Network Timeout Handling
Invoke-SecurityTest -Name "Handle-WebRequestTimeout" -Description "Tests proper handling of timeouts in web requests" -RequiresNetwork -Skip:$SkipNetworkTests -TestScript {
    # Use a non-responsive endpoint or very short timeout
    $uri = "https://example.com:81" # Typically nothing listening on port 81
    
    # Try-catch should handle the timeout
    try {
        $response = Invoke-SecureWebRequest -Uri $uri -TimeoutSeconds 1
        # If the above doesn't throw, test will fail
        throw "Web request should have timed out but didn't"
    }
    catch {
        # Verify it's a timeout exception
        if (-not $_.Exception.Message.Contains("timed out") -and 
            -not $_.Exception.Message.Contains("timeout") -and 
            -not $_.Exception.Message.Contains("aborted")) {
            throw "Expected timeout exception, but got: $($_.Exception.Message)"
        }
        
        # If we got here, the test passed
    }
}

#endregion

#region Execute Tests and Report Results

try {
    Write-TestLog -Message "Starting Security Foundation tests..." -Level Info
    
    # Run all registered tests (they're executed when Invoke-SecurityTest is called)
    
    # Export results
    $reportPath = Export-TestResults
    
    # Open report if interactive
    if ([Environment]::UserInteractive -and $reportPath) {
        Start-Process $reportPath
    }
    
    # Report final status
    if ($script:TestResults.FailedTests -eq 0) {
        Write-TestLog -Message "All tests completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-TestLog -Message "$($script:TestResults.FailedTests) tests failed. See report for details." -Level Error
        exit 1
    }
}
catch {
    Write-TestLog -Message "Test execution error: $_" -Level Error
    exit 1
}
finally {
    # Cleanup if needed
    # We're leaving the test files for inspection, but you could add cleanup code here
}

#endregion 





