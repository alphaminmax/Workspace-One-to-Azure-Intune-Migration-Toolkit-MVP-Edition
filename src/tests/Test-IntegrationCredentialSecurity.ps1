#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Integration tests for SecurityFoundation and SecureCredentialProvider modules.                                        #
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
    Integration tests for SecurityFoundation and SecureCredentialProvider modules.
    
.DESCRIPTION
    This script performs end-to-end integration tests for credential management between
    the SecurityFoundation and SecureCredentialProvider modules to ensure they work together
    as expected for sensitive data handling in the migration toolkit.
    
.PARAMETER TestPath
    Path where test files will be created.
    
.PARAMETER LogPath
    Path where test logs will be stored.
    
.PARAMETER KeyVaultName
    Optional. Name of an Azure Key Vault to use for integration tests.
    If not provided, Key Vault integration tests will be skipped.
    
.PARAMETER SkipKeyVaultTests
    Skip tests that require Azure Key Vault.
    
.EXAMPLE
    .\Test-IntegrationCredentialSecurity.ps1
    
.EXAMPLE
    .\Test-IntegrationCredentialSecurity.ps1 -KeyVaultName "migration-test-vault" -SkipKeyVaultTests:$false
    
.NOTES
    File Name      : Test-IntegrationCredentialSecurity.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TestPath = "$env:TEMP\IntegrationCredentialTests",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\IntegrationCredentialTests\Logs",
    
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipKeyVaultTests = (-not $KeyVaultName)
)

#region Initialize Test Environment

# Test framework variables
$script:TestsRun = 0
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0
$script:TestResults = @()
$script:StartTime = Get-Date

# Create test directories
if (-not (Test-Path -Path $TestPath)) {
    New-Item -Path $TestPath -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Set up logging
function Write-TestLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Output to console with color
    switch ($Level) {
        "Info"    { Write-Host $logMessage -ForegroundColor Gray }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Error"   { Write-Host $logMessage -ForegroundColor Red }
    }
    
    # Write to log file
    $logFile = Join-Path -Path $LogPath -ChildPath "IntegrationCredentialTest.log"
    $logMessage | Out-File -FilePath $logFile -Append
}

# Import required modules
$modulesPath = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath "modules"
$securityFoundationPath = Join-Path -Path $modulesPath -ChildPath "SecurityFoundation.psm1"
$secureCredentialPath = Join-Path -Path $modulesPath -ChildPath "SecureCredentialProvider.psm1"
$loggingModulePath = Join-Path -Path $modulesPath -ChildPath "LoggingModule.psm1"

# Try to import modules
try {
    if (Test-Path -Path $loggingModulePath) {
        Import-Module $loggingModulePath -Force -ErrorAction Stop
        Write-TestLog -Message "Imported LoggingModule" -Level Success
    }
    
    if (Test-Path -Path $secureCredentialPath) {
        Import-Module $secureCredentialPath -Force -ErrorAction Stop
        Write-TestLog -Message "Imported SecureCredentialProvider module" -Level Success
    }
    else {
        throw "SecureCredentialProvider module not found at: $secureCredentialPath"
    }
    
    if (Test-Path -Path $securityFoundationPath) {
        Import-Module $securityFoundationPath -Force -ErrorAction Stop
        Write-TestLog -Message "Imported SecurityFoundation module" -Level Success
    }
    else {
        throw "SecurityFoundation module not found at: $securityFoundationPath"
    }
}
catch {
    Write-TestLog -Message "Failed to import required modules: $_" -Level Error
    exit 1
}

# Initialize logging
if (Get-Command "Initialize-Logging" -ErrorAction SilentlyContinue) {
    Initialize-Logging -LogPath $LogPath -LogLevel "VERBOSE"
}

# Test runner function
function Invoke-IntegrationTest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestScript,
        
        [Parameter(Mandatory = $false)]
        [switch]$RequiresKeyVault,
        
        [Parameter(Mandatory = $false)]
        [switch]$Skip
    )
    
    # Skip if required and flag is set
    if ($RequiresKeyVault -and $SkipKeyVaultTests) {
        Write-TestLog -Message "SKIPPED: $Name - $Description (requires Key Vault)" -Level Warning
        $script:TestsSkipped++
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Result = "Skipped"
            Error = "Test requires Key Vault access"
            Duration = 0
        }
        return
    }
    
    # Skip if explicitly requested
    if ($Skip) {
        Write-TestLog -Message "SKIPPED: $Name - $Description" -Level Warning
        $script:TestsSkipped++
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Result = "Skipped"
            Error = "Test explicitly skipped"
            Duration = 0
        }
        return
    }
    
    Write-TestLog -Message "RUNNING: $Name - $Description" -Level Info
    $script:TestsRun++
    
    $startTime = Get-Date
    $errorInfo = $null
    $success = $false
    
    try {
        & $TestScript
        $success = $true
    }
    catch {
        $errorInfo = $_
    }
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    if ($success) {
        Write-TestLog -Message "PASSED: $Name ($($duration.ToString('0.00'))s)" -Level Success
        $script:TestsPassed++
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Result = "Passed"
            Error = $null
            Duration = $duration
        }
    }
    else {
        Write-TestLog -Message "FAILED: $Name - $($errorInfo.Exception.Message)" -Level Error
        $script:TestsFailed++
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Result = "Failed"
            Error = $errorInfo.Exception.Message
            Duration = $duration
        }
    }
}

# Export test results to HTML
function Export-TestResults {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportFile = Join-Path -Path $LogPath -ChildPath "IntegrationTestReport-$timestamp.html"
    
    $totalDuration = ((Get-Date) - $script:StartTime).TotalSeconds
    
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>Integration Tests - SecurityFoundation and SecureCredentialProvider</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0066cc; }
        .summary { background-color: #f0f0f0; padding: 10px; border-radius: 5px; margin-bottom: 20px; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 8px; }
        th { background-color: #0066cc; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        tr.failed { background-color: #ffe6e6; }
        tr.passed { background-color: #e6ffe6; }
        tr.skipped { background-color: #fff5e6; }
    </style>
</head>
<body>
    <h1>Integration Tests - SecurityFoundation and SecureCredentialProvider</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p>Total Tests: $script:TestsRun</p>
        <p class="pass">Passed: $script:TestsPassed</p>
        <p class="fail">Failed: $script:TestsFailed</p>
        <p class="skip">Skipped: $script:TestsSkipped</p>
        <p>Total Duration: $($totalDuration.ToString('0.00')) seconds</p>
    </div>
    <h2>Test Details</h2>
    <table>
        <tr>
            <th>Test Name</th>
            <th>Description</th>
            <th>Result</th>
            <th>Duration (s)</th>
            <th>Error</th>
        </tr>
"@

    $htmlRows = ""
    foreach ($result in $script:TestResults) {
        $rowClass = switch ($result.Result) {
            "Passed"  { "passed" }
            "Failed"  { "failed" }
            "Skipped" { "skipped" }
        }
        
        $htmlRows += @"
        <tr class="$rowClass">
            <td>$($result.Name)</td>
            <td>$($result.Description)</td>
            <td>$($result.Result)</td>
            <td>$($result.Duration.ToString('0.00'))</td>
            <td>$($result.Error)</td>
        </tr>
"@
    }

    $htmlFooter = @"
    </table>
</body>
</html>
"@

    $htmlContent = $htmlHeader + $htmlRows + $htmlFooter
    $htmlContent | Out-File -FilePath $reportFile -Encoding utf8
    
    Write-TestLog -Message "Test report saved to: $reportFile" -Level Info
    return $reportFile
}

#endregion

#region Define Tests

# Test module initialization and integration
Invoke-IntegrationTest -Name "Module-Initialization" -Description "Tests initialization of both modules together" -TestScript {
    # Configure paths for testing
    $securityConfig = @{
        AuditLogPath = Join-Path -Path $TestPath -ChildPath "SecurityAudit"
        SecureKeyPath = Join-Path -Path $TestPath -ChildPath "SecureKeys"
        ApiTimeoutSeconds = 30
        RequireAdminForSensitiveOperations = $false
    }
    
    $credentialConfig = @{
        CredentialStorePath = Join-Path -Path $TestPath -ChildPath "Credentials"
        UseEnvironmentVariables = $true
        UseCredentialManager = $false
        UseKeyVault = $false
    }
    
    # Initialize SecurityFoundation first
    $securityInitResult = Set-SecurityConfiguration @securityConfig
    
    if (-not $securityInitResult) {
        throw "Failed to initialize SecurityFoundation module"
    }
    
    # Initialize SecurityFoundation
    $sfInitResult = Initialize-SecurityFoundation -CreateEncryptionCert
    
    if (-not $sfInitResult) {
        throw "Failed to initialize SecurityFoundation"
    }
    
    # Initialize SecureCredentialProvider
    $scpInitResult = Initialize-CredentialProvider @credentialConfig
    
    if (-not $scpInitResult) {
        throw "Failed to initialize SecureCredentialProvider"
    }
    
    # Verify both modules are working
    $sfActive = Test-SecurityInitialized
    $scpActive = Test-CredentialProviderInitialized
    
    if (-not $sfActive) {
        throw "SecurityFoundation initialization check failed"
    }
    
    if (-not $scpActive) {
        throw "SecureCredentialProvider initialization check failed"
    }
}

# Test SecurityFoundation using SecureCredentialProvider
Invoke-IntegrationTest -Name "SF-Using-SCP" -Description "Tests SecurityFoundation using SecureCredentialProvider for credential storage" -TestScript {
    # Set up paths
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "SF_SCP_Integration"
    
    # Configure SecureCredentialProvider
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Create test credential
    $username = "sfintegration@example.com"
    $password = ConvertTo-SecureString "IntegrationP@ss123!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store credential using SecurityFoundation (which should use SCP internally)
    $credentialStored = Set-SecureCredential -Credential $credential -CredentialName "SFIntegrationTest"
    
    if (-not $credentialStored) {
        throw "Failed to store credential through SecurityFoundation"
    }
    
    # Retrieve using SecurityFoundation
    $retrievedSF = Get-SecureCredential -CredentialName "SFIntegrationTest"
    
    if (-not $retrievedSF) {
        throw "Failed to retrieve credential through SecurityFoundation"
    }
    
    # Verify username
    if ($retrievedSF.UserName -ne $username) {
        throw "Retrieved username does not match original. Expected: $username, Got: $($retrievedSF.UserName)"
    }
    
    # Convert both secure strings to plain text for comparison
    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainOriginal = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
    
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedSF.Password)
    $plainRetrieved = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    
    if ($plainOriginal -ne $plainRetrieved) {
        throw "Retrieved password does not match original"
    }
    
    # Now verify we can access directly through SCP as well
    $retrievedSCP = Get-StoredCredential -Name "SFIntegrationTest"
    
    if (-not $retrievedSCP) {
        throw "Failed to retrieve credential directly through SecureCredentialProvider"
    }
    
    # Verify username matches
    if ($retrievedSCP.UserName -ne $username) {
        throw "Retrieved username via SCP does not match. Expected: $username, Got: $($retrievedSCP.UserName)"
    }
}

# Test sensitive data protection with both modules
Invoke-IntegrationTest -Name "SensitiveData-Protection" -Description "Tests protecting sensitive data using both modules" -TestScript {
    # Initialize the modules with test paths
    $securityConfig = @{
        AuditLogPath = Join-Path -Path $TestPath -ChildPath "SensitiveDataTest\Audit"
        SecureKeyPath = Join-Path -Path $TestPath -ChildPath "SensitiveDataTest\Keys"
    }
    
    $credentialConfig = @{
        CredentialStorePath = Join-Path -Path $TestPath -ChildPath "SensitiveDataTest\Credentials"
        UseEnvironmentVariables = $false
        UseCredentialManager = $false
        UseKeyVault = $false
    }
    
    Set-SecurityConfiguration @securityConfig
    Initialize-SecurityFoundation -CreateEncryptionCert
    Initialize-CredentialProvider @credentialConfig
    
    # Sensitive data to protect
    $apiKey = "abcdef123456SECRETKEY7890"
    $connectionString = "Server=myserver;Database=mydb;User Id=sa;Password=P@ssw0rd;"
    
    # Protect the data using SecurityFoundation
    $apiKeyProtected = Protect-SensitiveData -Data $apiKey -KeyName "APIKeyTest"
    $connStringProtected = Protect-SensitiveData -Data $connectionString -KeyName "ConnStringTest"
    
    if (-not $apiKeyProtected -or -not $connStringProtected) {
        throw "Failed to protect sensitive data"
    }
    
    # Create credential with the protected data
    $username = "apiuser"
    $protectedPassword = ConvertTo-SecureString "dummy" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $protectedPassword)
    
    # Store credential with metadata about the protected data
    $metadata = @{
        ApiKeyName = "APIKeyTest"
        ConnectionStringName = "ConnStringTest"
    }
    
    $credentialStored = Set-SecureCredential -Credential $credential -CredentialName "ServiceCredential" -Metadata $metadata
    
    if (-not $credentialStored) {
        throw "Failed to store credential with metadata"
    }
    
    # Retrieve credential and protected data
    $retrievedCred = Get-SecureCredential -CredentialName "ServiceCredential"
    
    if (-not $retrievedCred) {
        throw "Failed to retrieve credential"
    }
    
    # Get metadata
    $retrievedMetadata = Get-CredentialMetadata -CredentialName "ServiceCredential"
    
    if (-not $retrievedMetadata -or -not $retrievedMetadata.ApiKeyName -or -not $retrievedMetadata.ConnectionStringName) {
        throw "Failed to retrieve credential metadata"
    }
    
    # Retrieve protected data
    $retrievedApiKey = Unprotect-SensitiveData -KeyName $retrievedMetadata.ApiKeyName -AsPlainText
    $retrievedConnString = Unprotect-SensitiveData -KeyName $retrievedMetadata.ConnectionStringName -AsPlainText
    
    # Verify data integrity
    if ($retrievedApiKey -ne $apiKey) {
        throw "Retrieved API key does not match original. Expected: $apiKey, Got: $retrievedApiKey"
    }
    
    if ($retrievedConnString -ne $connectionString) {
        throw "Retrieved connection string does not match original"
    }
}

# Test cross-module credential management with Key Vault
Invoke-IntegrationTest -Name "KeyVault-Integration" -Description "Tests both modules with Azure Key Vault integration" -RequiresKeyVault -TestScript {
    # Skip if no Key Vault name provided
    if (-not $KeyVaultName) {
        throw "Key Vault name required for this test"
    }
    
    # Configure both modules to use Key Vault
    Set-SecurityConfiguration -UseKeyVault $true -KeyVaultName $KeyVaultName
    Set-CredentialProviderConfig -UseKeyVault $true -KeyVaultName $KeyVaultName
    
    # Create test credential
    $username = "keyvaultintegration@example.com"
    $password = ConvertTo-SecureString "KeyVaultIntegP@ss!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store through SecurityFoundation
    $sfStored = Set-SecureCredential -Credential $credential -CredentialName "KVIntegrationTest" -UseKeyVault
    
    if (-not $sfStored) {
        throw "Failed to store credential through SecurityFoundation with Key Vault"
    }
    
    # Try to retrieve directly through SecureCredentialProvider
    $retrievedSCP = Get-StoredCredential -Name "KVIntegrationTest" -UseKeyVault
    
    if (-not $retrievedSCP) {
        throw "Failed to retrieve credential via SecureCredentialProvider from Key Vault"
    }
    
    # Verify username
    if ($retrievedSCP.UserName -ne $username) {
        throw "Retrieved username via SCP from Key Vault does not match. Expected: $username, Got: $($retrievedSCP.UserName)"
    }
    
    # Now retrieve through SecurityFoundation
    $retrievedSF = Get-SecureCredential -CredentialName "KVIntegrationTest" -UseKeyVault
    
    if (-not $retrievedSF) {
        throw "Failed to retrieve credential through SecurityFoundation from Key Vault"
    }
    
    # Verify username
    if ($retrievedSF.UserName -ne $username) {
        throw "Retrieved username via SecurityFoundation from Key Vault does not match. Expected: $username, Got: $($retrievedSF.UserName)"
    }
    
    # Clean up
    Remove-SecureCredential -CredentialName "KVIntegrationTest" -UseKeyVault
}

# Test security audit and audit trail
Invoke-IntegrationTest -Name "Security-Audit-Trail" -Description "Tests security audit logging across both modules" -TestScript {
    # Set up audit path
    $auditPath = Join-Path -Path $TestPath -ChildPath "AuditTrail"
    
    # Configure modules
    Set-SecurityConfiguration -AuditLogPath $auditPath
    
    # Create test credential
    $username = "audittrail@example.com"
    $password = ConvertTo-SecureString "AuditP@ss123!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Perform sensitive operations that should be logged
    Write-SecurityEvent -Message "Starting security audit test" -Level "Information" -Component "IntegrationTest"
    
    # Store credential
    Set-SecureCredential -Credential $credential -CredentialName "AuditTrailTest"
    
    # Access sensitive data
    Get-SecureCredential -CredentialName "AuditTrailTest"
    
    # Create and protect sensitive data
    Protect-SensitiveData -Data "Sensitive audit test data" -KeyName "AuditTestKey"
    
    # Access protected data
    Unprotect-SensitiveData -KeyName "AuditTestKey" -AsPlainText
    
    # Delete sensitive data
    Remove-SecureCredential -CredentialName "AuditTrailTest"
    
    Write-SecurityEvent -Message "Completed security audit test" -Level "Information" -Component "IntegrationTest"
    
    # Verify audit logs were created
    $auditFiles = Get-ChildItem -Path $auditPath -Filter "SecurityAudit_*.log" -ErrorAction SilentlyContinue
    
    if ($auditFiles.Count -eq 0) {
        throw "No audit log files found"
    }
    
    # Verify audit content
    $auditContent = Get-Content -Path $auditFiles[0].FullName -Raw
    
    # Check for expected audit entries
    $expectedEntries = @(
        "Starting security audit test",
        "credential",
        "AuditTrailTest",
        "sensitive data",
        "Completed security audit test"
    )
    
    foreach ($entry in $expectedEntries) {
        if (-not $auditContent.Contains($entry)) {
            throw "Expected audit entry '$entry' not found in audit logs"
        }
    }
}

# Test error handling and recovery across modules
Invoke-IntegrationTest -Name "Error-Handling-Recovery" -Description "Tests error handling and recovery across both modules" -TestScript {
    # Configure test paths
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "ErrorRecovery"
    
    # Configure modules
    Set-SecurityConfiguration -SecureKeyPath "$credentialStorePath\Keys"
    Set-CredentialProviderConfig -CredentialStorePath "$credentialStorePath\Credentials" -UseKeyVault:$false
    
    # Create test credential
    $username = "errorrecovery@example.com"
    $password = ConvertTo-SecureString "RecoveryP@ss123!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store credential
    Set-SecureCredential -Credential $credential -CredentialName "ErrorRecoveryTest"
    
    # Test error recovery - nonexistent credential
    try {
        $nonExistentResult = Get-SecureCredential -CredentialName "NonExistentCredential" -ErrorAction SilentlyContinue
        
        # Should be null, not throw exception
        if ($nonExistentResult -ne $null) {
            throw "Expected null for non-existent credential, got a value"
        }
    }
    catch {
        throw "Error handling for non-existent credential failed: $_"
    }
    
    # Test with default credential fallback
    $defaultUsername = "default@example.com"
    $defaultPassword = ConvertTo-SecureString "DefaultP@ss123!" -AsPlainText -Force
    $defaultCred = New-Object System.Management.Automation.PSCredential($defaultUsername, $defaultPassword)
    
    $fallbackResult = Get-SecureCredential -CredentialName "NonExistentCredential" -DefaultCredential $defaultCred
    
    if (-not $fallbackResult) {
        throw "Failed to return default credential on fallback"
    }
    
    if ($fallbackResult.UserName -ne $defaultUsername) {
        throw "Default credential not returned correctly"
    }
    
    # Test graceful failure with invalid data
    try {
        # Create an invalid credential file
        $invalidPath = Join-Path -Path "$credentialStorePath\Credentials" -ChildPath "InvalidCred.cred"
        "This is not valid credential data" | Out-File -FilePath $invalidPath -Force
        
        # Try to access it
        $invalidResult = Get-StoredCredential -Name "InvalidCred" -ErrorAction SilentlyContinue
        
        # Should handle gracefully (return null)
        if ($invalidResult -ne $null) {
            throw "Invalid credential data should return null"
        }
    }
    catch {
        throw "Failed to handle invalid credential data gracefully: $_"
    }
}

# Test cross-module performance
Invoke-IntegrationTest -Name "Cross-Module-Performance" -Description "Tests performance of operations across both modules" -TestScript {
    # Configure test paths
    $perfTestPath = Join-Path -Path $TestPath -ChildPath "PerformanceTest"
    
    # Configure modules
    Set-SecurityConfiguration -SecureKeyPath "$perfTestPath\Keys"
    Set-CredentialProviderConfig -CredentialStorePath "$perfTestPath\Credentials" -UseKeyVault:$false
    
    # Prepare test items
    $testItems = 10
    $credentials = @()
    
    for ($i = 1; $i -le $testItems; $i++) {
        $username = "perfuser$i@example.com"
        $password = ConvertTo-SecureString "PerfP@ss$i!" -AsPlainText -Force
        $credentials += New-Object System.Management.Automation.PSCredential($username, $password)
    }
    
    # Test write performance
    $writeStart = Get-Date
    
    for ($i = 0; $i -lt $testItems; $i++) {
        Set-SecureCredential -Credential $credentials[$i] -CredentialName "PerfTest$i"
    }
    
    $writeEnd = Get-Date
    $writeDuration = ($writeEnd - $writeStart).TotalSeconds
    
    # Write performance should be reasonable
    if ($writeDuration -gt 10) {
        throw "Credential storage performance is too slow: $writeDuration seconds for $testItems items"
    }
    
    # Test read performance
    $readStart = Get-Date
    
    for ($i = 0; $i -lt $testItems; $i++) {
        Get-SecureCredential -CredentialName "PerfTest$i"
    }
    
    $readEnd = Get-Date
    $readDuration = ($readEnd - $readStart).TotalSeconds
    
    # Read performance should be reasonable
    if ($readDuration -gt 5) {
        throw "Credential retrieval performance is too slow: $readDuration seconds for $testItems items"
    }
    
    # Verify module can handle concurrent operations
    $concurrentStart = Get-Date
    
    # These will be simultaneous
    $results = 1..$testItems | ForEach-Object -Parallel {
        $index = $_
        Get-SecureCredential -CredentialName "PerfTest$($index-1)"
    } -ThrottleLimit 5
    
    $concurrentEnd = Get-Date
    $concurrentDuration = ($concurrentEnd - $concurrentStart).TotalSeconds
    
    # Verify all results were returned
    if ($results.Count -lt $testItems) {
        throw "Concurrent operations returned incomplete results: $($results.Count) of $testItems"
    }
}

#endregion

#region Execute Tests and Report Results

try {
    Write-TestLog -Message "Starting integration tests for SecurityFoundation and SecureCredentialProvider..." -Level Info
    
    # Export results
    $reportPath = Export-TestResults
    
    # Open report if interactive
    if ([Environment]::UserInteractive -and $reportPath) {
        Start-Process $reportPath
    }
    
    # Report final status
    if ($script:TestsFailed -eq 0) {
        Write-TestLog -Message "All integration tests completed successfully! ($script:TestsPassed passed, $script:TestsSkipped skipped)" -Level Success
        exit 0
    }
    else {
        Write-TestLog -Message "$script:TestsFailed tests failed. See report for details." -Level Error
        exit 1
    }
}
catch {
    Write-TestLog -Message "Test execution error: $_" -Level Error
    exit 1
}

#endregion 





