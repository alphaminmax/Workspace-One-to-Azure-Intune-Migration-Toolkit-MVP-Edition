#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Tests for SecureCredentialProvider module functionality.                                                              #
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
    Tests for SecureCredentialProvider module functionality.
    
.DESCRIPTION
    Comprehensive tests for the SecureCredentialProvider module, covering:
    - Local credential storage and retrieval
    - Azure Key Vault integration
    - Environment variable credential support
    - Fallback mechanisms
    - Error handling and recovery
    
.PARAMETER TestPath
    Path where test files will be created.
    
.PARAMETER LogPath
    Path where test logs will be stored.
    
.PARAMETER KeyVaultName
    Optional. Name of an Azure Key Vault to use for integration tests.
    If not provided, Key Vault tests will be skipped.
    
.PARAMETER SkipKeyVaultTests
    Skip tests that require Azure Key Vault.
    
.EXAMPLE
    .\Test-SecureCredentialProvider.ps1
    
.EXAMPLE
    .\Test-SecureCredentialProvider.ps1 -KeyVaultName "migration-test-vault" -SkipKeyVaultTests:$false
    
.NOTES
    File Name      : Test-SecureCredentialProvider.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TestPath = "$env:TEMP\SecureCredentialProviderTests",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\SecureCredentialProviderTests\Logs",
    
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
    $logFile = Join-Path -Path $LogPath -ChildPath "Test-SecureCredentialProvider.log"
    $logMessage | Out-File -FilePath $logFile -Append
}

# Import required modules
$modulesPath = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath "modules"
$secureCredentialPath = Join-Path -Path $modulesPath -ChildPath "SecureCredentialProvider.psm1"
$loggingModulePath = Join-Path -Path $modulesPath -ChildPath "LoggingModule.psm1"

# Try to import modules
try {
    if (Test-Path -Path $loggingModulePath) {
        Import-Module $loggingModulePath -Force
        Write-TestLog -Message "Imported LoggingModule" -Level Success
    }
    
    if (Test-Path -Path $secureCredentialPath) {
        Import-Module $secureCredentialPath -Force
        Write-TestLog -Message "Imported SecureCredentialProvider module" -Level Success
    }
    else {
        throw "SecureCredentialProvider module not found at: $secureCredentialPath"
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
function Invoke-CredentialTest {
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
    $error = $null
    $success = $false
    
    try {
        & $TestScript
        $success = $true
    }
    catch {
        $error = $_
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
        Write-TestLog -Message "FAILED: $Name - $($error.Exception.Message)" -Level Error
        $script:TestsFailed++
        $script:TestResults += [PSCustomObject]@{
            Name = $Name
            Description = $Description
            Result = "Failed"
            Error = $error.Exception.Message
            Duration = $duration
        }
    }
}

# Export test results to HTML
function Export-TestResults {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportFile = Join-Path -Path $LogPath -ChildPath "TestReport-$timestamp.html"
    
    $totalDuration = ((Get-Date) - $script:StartTime).TotalSeconds
    
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>SecureCredentialProvider Test Results</title>
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
    <h1>SecureCredentialProvider Test Results</h1>
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

# Test initialization of credentials provider 
Invoke-CredentialTest -Name "Initialize-CredentialProvider" -Description "Tests initialization of the credential provider" -TestScript {
    # Create test config
    $config = @{
        CredentialStorePath = Join-Path -Path $TestPath -ChildPath "Credentials"
        UseEnvironmentVariables = $true
        UseCredentialManager = $false
        UseKeyVault = $false
    }
    
    # Initialize
    $result = Initialize-CredentialProvider @config
    
    if (-not $result) {
        throw "Failed to initialize credential provider"
    }
    
    # Verify credential store was created
    if (-not (Test-Path -Path $config.CredentialStorePath)) {
        throw "Credential store path was not created"
    }
}

# Test basic credential storage
Invoke-CredentialTest -Name "Set-GetCredential-Local" -Description "Tests storing and retrieving credentials locally" -TestScript {
    # Create test credential
    $username = "testuser@example.com"
    $password = ConvertTo-SecureString "TestP@ssw0rd!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Set credential store path
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "LocalCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Store credential
    $credentialStored = Set-StoredCredential -Credential $credential -Name "LocalTestCred"
    
    if (-not $credentialStored) {
        throw "Failed to store credential locally"
    }
    
    # Verify file was created
    $credFiles = Get-ChildItem -Path $credentialStorePath -Filter "*.cred" -ErrorAction SilentlyContinue
    if ($credFiles.Count -eq 0) {
        throw "No credential files found"
    }
    
    # Retrieve credential
    $retrievedCred = Get-StoredCredential -Name "LocalTestCred"
    
    if (-not $retrievedCred) {
        throw "Failed to retrieve credential"
    }
    
    # Verify username
    if ($retrievedCred.UserName -ne $username) {
        throw "Retrieved username does not match original username"
    }
    
    # Convert both secure strings to plain text for comparison
    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainOriginal = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
    
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedCred.Password)
    $plainRetrieved = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    
    if ($plainOriginal -ne $plainRetrieved) {
        throw "Retrieved password does not match original password"
    }
}

# Test credential removal
Invoke-CredentialTest -Name "Remove-StoredCredential" -Description "Tests removing stored credentials" -TestScript {
    # Create test credential
    $username = "removeuser@example.com"
    $password = ConvertTo-SecureString "RemoveP@ssw0rd!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Set credential store path
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "RemoveCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Store credential
    Set-StoredCredential -Credential $credential -Name "CredToRemove"
    
    # Verify it exists
    $exists = Test-CredentialExists -Name "CredToRemove"
    if (-not $exists) {
        throw "Credential was not stored successfully"
    }
    
    # Remove credential
    $removed = Remove-StoredCredential -Name "CredToRemove"
    if (-not $removed) {
        throw "Failed to remove credential"
    }
    
    # Verify it no longer exists
    $stillExists = Test-CredentialExists -Name "CredToRemove"
    if ($stillExists) {
        throw "Credential still exists after removal"
    }
}

# Test environment variable credentials
Invoke-CredentialTest -Name "EnvironmentVariable-Credentials" -Description "Tests retrieving credentials from environment variables" -TestScript {
    # Set credential provider config
    Set-CredentialProviderConfig -UseEnvironmentVariables $true
    
    # Set environment variables for testing
    $envCredName = "TEST_CREDENTIAL"
    $envUserVar = "${envCredName}_USERNAME"
    $envPassVar = "${envCredName}_PASSWORD"
    
    # Set test values
    $env:$envUserVar = "envuser@example.com"
    $env:$envPassVar = "EnvP@ssw0rd123!"
    
    try {
        # Try to get credential from environment
        $envCred = Get-StoredCredential -Name "TEST_CREDENTIAL" -EnvVarPrefix "TEST_CREDENTIAL"
        
        # Verify credential was returned
        if (-not $envCred) {
            throw "Failed to retrieve credential from environment variables"
        }
        
        # Verify username
        if ($envCred.UserName -ne $env:$envUserVar) {
            throw "Username from environment variable does not match expected value"
        }
        
        # Convert password to plain text for comparison
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($envCred.Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        
        if ($plainPassword -ne $env:$envPassVar) {
            throw "Password from environment variable does not match expected value"
        }
    }
    finally {
        # Clean up environment variables
        Remove-Item -Path "Env:$envUserVar" -ErrorAction SilentlyContinue
        Remove-Item -Path "Env:$envPassVar" -ErrorAction SilentlyContinue
    }
}

# Test fallback mechanisms
Invoke-CredentialTest -Name "Credential-Fallback" -Description "Tests credential retrieval with fallback mechanisms" -TestScript {
    # Configure multiple credential sources
    Set-CredentialProviderConfig -UseEnvironmentVariables $true -UseKeyVault $false
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "FallbackCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath
    
    # Create test credential in local store
    $username = "fallbackuser@example.com"
    $password = ConvertTo-SecureString "FallbackP@ssw0rd!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store credential
    Set-StoredCredential -Credential $credential -Name "FallbackCred"
    
    # Set up environment variables with different values
    $env:FALLBACKCRED_USERNAME = "wronguser@example.com"
    $env:FALLBACKCRED_PASSWORD = "WrongPassword123!"
    
    try {
        # Retrieve credentials with fallback (prefer env vars but they have wrong name)
        $retrievedCred = Get-StoredCredential -Name "FallbackCred" -UseFallback
        
        # Verify we got the right credential back
        if (-not $retrievedCred) {
            throw "Failed to retrieve credential with fallback"
        }
        
        # Verify it's the local credential that was retrieved
        if ($retrievedCred.UserName -ne $username) {
            throw "Fallback didn't work correctly - got wrong credential"
        }
    }
    finally {
        # Clean up
        Remove-Item -Path "Env:FALLBACKCRED_USERNAME" -ErrorAction SilentlyContinue
        Remove-Item -Path "Env:FALLBACKCRED_PASSWORD" -ErrorAction SilentlyContinue
    }
}

# Test credential listing
Invoke-CredentialTest -Name "Get-StoredCredentials" -Description "Tests listing all stored credentials" -TestScript {
    # Configure credential store
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "ListCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Create multiple test credentials
    $creds = @(
        @{ Name = "ListCred1"; Username = "user1@example.com"; Password = "Password1!" },
        @{ Name = "ListCred2"; Username = "user2@example.com"; Password = "Password2!" },
        @{ Name = "ListCred3"; Username = "user3@example.com"; Password = "Password3!" }
    )
    
    foreach ($cred in $creds) {
        $password = ConvertTo-SecureString $cred.Password -AsPlainText -Force
        $psCred = New-Object System.Management.Automation.PSCredential($cred.Username, $password)
        Set-StoredCredential -Credential $psCred -Name $cred.Name
    }
    
    # List all credentials
    $storedCreds = Get-StoredCredentials
    
    # Verify all credentials are listed
    if ($storedCreds.Count -lt $creds.Count) {
        throw "Not all credentials were returned. Expected at least $($creds.Count), got $($storedCreds.Count)"
    }
    
    # Verify each expected credential is in the list
    foreach ($cred in $creds) {
        $found = $storedCreds | Where-Object { $_.Name -eq $cred.Name }
        if (-not $found) {
            throw "Credential '$($cred.Name)' was not found in the list"
        }
    }
}

# Test credential update
Invoke-CredentialTest -Name "Update-StoredCredential" -Description "Tests updating existing credentials" -TestScript {
    # Configure credential store
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "UpdateCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Create initial credential
    $initialUsername = "initial@example.com"
    $initialPassword = ConvertTo-SecureString "InitialP@ss!" -AsPlainText -Force
    $initialCred = New-Object System.Management.Automation.PSCredential($initialUsername, $initialPassword)
    
    # Store initial credential
    Set-StoredCredential -Credential $initialCred -Name "UpdateTestCred"
    
    # Create updated credential
    $updatedUsername = "updated@example.com"
    $updatedPassword = ConvertTo-SecureString "UpdatedP@ss!" -AsPlainText -Force
    $updatedCred = New-Object System.Management.Automation.PSCredential($updatedUsername, $updatedPassword)
    
    # Update the credential
    $updateResult = Set-StoredCredential -Credential $updatedCred -Name "UpdateTestCred" -Force
    
    if (-not $updateResult) {
        throw "Failed to update credential"
    }
    
    # Retrieve updated credential
    $retrievedCred = Get-StoredCredential -Name "UpdateTestCred"
    
    # Verify username was updated
    if ($retrievedCred.UserName -ne $updatedUsername) {
        throw "Username was not updated correctly. Expected: $updatedUsername, Got: $($retrievedCred.UserName)"
    }
    
    # Verify password was updated
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedCred.Password)
    $plainRetrieved = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($updatedPassword)
    $plainUpdated = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    
    if ($plainRetrieved -ne $plainUpdated) {
        throw "Password was not updated correctly"
    }
}

# Test Azure Key Vault credential storage
Invoke-CredentialTest -Name "KeyVault-StoreCredential" -Description "Tests storing credentials in Azure Key Vault" -RequiresKeyVault -TestScript {
    # Skip if no Key Vault name provided
    if (-not $KeyVaultName) {
        throw "Key Vault name required for this test"
    }
    
    # Configure to use Key Vault
    Set-CredentialProviderConfig -UseKeyVault $true -KeyVaultName $KeyVaultName
    
    # Create test credential
    $username = "kvuser@example.com"
    $password = ConvertTo-SecureString "KeyVaultP@ss123!" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store in Key Vault
    $kvResult = Set-StoredCredential -Credential $credential -Name "KVTestCred" -UseKeyVault
    
    if (-not $kvResult) {
        throw "Failed to store credential in Key Vault"
    }
    
    # Retrieve from Key Vault
    $retrievedCred = Get-StoredCredential -Name "KVTestCred" -UseKeyVault
    
    if (-not $retrievedCred) {
        throw "Failed to retrieve credential from Key Vault"
    }
    
    # Verify username
    if ($retrievedCred.UserName -ne $username) {
        throw "Retrieved username from Key Vault doesn't match original. Expected: $username, Got: $($retrievedCred.UserName)"
    }
    
    # Verify password by converting both to plain text
    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainOriginal = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
    
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedCred.Password)
    $plainRetrieved = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    
    if ($plainOriginal -ne $plainRetrieved) {
        throw "Retrieved password from Key Vault doesn't match original"
    }
    
    # Clean up - remove the credential from Key Vault
    $removeResult = Remove-StoredCredential -Name "KVTestCred" -UseKeyVault
    
    if (-not $removeResult) {
        throw "Failed to remove test credential from Key Vault"
    }
}

# Test Key Vault credential listing
Invoke-CredentialTest -Name "KeyVault-ListCredentials" -Description "Tests listing credentials from Azure Key Vault" -RequiresKeyVault -TestScript {
    # Skip if no Key Vault name provided
    if (-not $KeyVaultName) {
        throw "Key Vault name required for this test"
    }
    
    # Configure to use Key Vault
    Set-CredentialProviderConfig -UseKeyVault $true -KeyVaultName $KeyVaultName
    
    # Create multiple test credentials
    $creds = @(
        @{ Name = "KVListCred1"; Username = "kvuser1@example.com"; Password = "KVPassword1!" },
        @{ Name = "KVListCred2"; Username = "kvuser2@example.com"; Password = "KVPassword2!" }
    )
    
    try {
        # Store credentials in Key Vault
        foreach ($cred in $creds) {
            $password = ConvertTo-SecureString $cred.Password -AsPlainText -Force
            $psCred = New-Object System.Management.Automation.PSCredential($cred.Username, $password)
            Set-StoredCredential -Credential $psCred -Name $cred.Name -UseKeyVault
        }
        
        # List credentials from Key Vault
        $kvCreds = Get-StoredCredentials -UseKeyVault
        
        # Verify each test credential is in the list
        foreach ($cred in $creds) {
            $found = $kvCreds | Where-Object { $_.Name -eq $cred.Name }
            if (-not $found) {
                throw "Credential '$($cred.Name)' was not found in Key Vault credential list"
            }
        }
    }
    finally {
        # Clean up - remove test credentials
        foreach ($cred in $creds) {
            Remove-StoredCredential -Name $cred.Name -UseKeyVault -ErrorAction SilentlyContinue
        }
    }
}

# Test error recovery - credential not found
Invoke-CredentialTest -Name "ErrorRecovery-CredentialNotFound" -Description "Tests recovery when credential is not found" -TestScript {
    # Configure to use local credentials
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "ErrorRecoveryCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Try to retrieve non-existent credential
    $nonExistentCred = Get-StoredCredential -Name "NonExistentCred" -ErrorAction SilentlyContinue
    
    # Should return null, not throw exception
    if ($nonExistentCred -ne $null) {
        throw "Expected null when retrieving non-existent credential, but got a value"
    }
    
    # Test with fallback to default
    $defaultUsername = "default@example.com"
    $defaultPassword = ConvertTo-SecureString "DefaultP@ss!" -AsPlainText -Force
    $defaultCred = New-Object System.Management.Automation.PSCredential($defaultUsername, $defaultPassword)
    
    $retrievedWithDefault = Get-StoredCredential -Name "NonExistentCred" -DefaultCredential $defaultCred
    
    if (-not $retrievedWithDefault) {
        throw "Failed to return default credential when primary not found"
    }
    
    if ($retrievedWithDefault.UserName -ne $defaultUsername) {
        throw "Default credential was not returned correctly"
    }
}

# Test error recovery - provider switching
Invoke-CredentialTest -Name "ErrorRecovery-ProviderSwitching" -Description "Tests switching between credential providers on failure" -TestScript {
    # Configure multiple providers
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "ProviderSwitchCreds"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false -UseEnvironmentVariables:$true
    
    # Create credential in local store
    $localUsername = "localswitch@example.com"
    $localPassword = ConvertTo-SecureString "LocalSwitchP@ss!" -AsPlainText -Force
    $localCred = New-Object System.Management.Automation.PSCredential($localUsername, $localPassword)
    Set-StoredCredential -Credential $localCred -Name "SwitchTestCred"
    
    # Force to try environment first (which will fail), then fall back to local
    $retrievedCred = Get-StoredCredential -Name "SwitchTestCred" -TryEnvVarsFirst $true -UseFallback $true
    
    if (-not $retrievedCred) {
        throw "Failed to retrieve credential with provider switching"
    }
    
    if ($retrievedCred.UserName -ne $localUsername) {
        throw "Provider switching returned wrong credential"
    }
}

# Test credential encryption
Invoke-CredentialTest -Name "Credential-Encryption" -Description "Tests that stored credentials are properly encrypted" -TestScript {
    # Configure local credential store
    $credentialStorePath = Join-Path -Path $TestPath -ChildPath "EncryptionTest"
    Set-CredentialProviderConfig -CredentialStorePath $credentialStorePath -UseKeyVault:$false
    
    # Create and store test credential
    $testUsername = "encrypt@example.com"
    $testPassword = "SuperSecretP@ssword123!"
    $secPassword = ConvertTo-SecureString $testPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($testUsername, $secPassword)
    
    Set-StoredCredential -Credential $credential -Name "EncryptionTestCred"
    
    # Find the credential file
    $credFile = Get-ChildItem -Path $credentialStorePath -Filter "EncryptionTestCred*.cred" | Select-Object -First 1
    
    if (-not $credFile) {
        throw "Credential file was not created"
    }
    
    # Read the raw file content
    $fileContent = Get-Content -Path $credFile.FullName -Raw
    
    # Verify the file does not contain the plain text password
    if ($fileContent.Contains($testPassword)) {
        throw "Credential file contains plain text password - encryption failed"
    }
    
    # Verify the file does not contain plain text username
    if ($fileContent.Contains($testUsername)) {
        throw "Credential file contains plain text username - encryption failed"
    }
    
    # Retrieve and verify the credential can be decrypted
    $retrievedCred = Get-StoredCredential -Name "EncryptionTestCred"
    
    if (-not $retrievedCred) {
        throw "Failed to decrypt and retrieve credential"
    }
    
    if ($retrievedCred.UserName -ne $testUsername) {
        throw "Decrypted username does not match original"
    }
    
    # Verify password
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedCred.Password)
    $decryptedPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    if ($decryptedPassword -ne $testPassword) {
        throw "Decrypted password does not match original"
    }
}

#endregion

#region Execute Tests and Report Results

try {
    Write-TestLog -Message "Starting SecureCredentialProvider tests..." -Level Info
    
    # Export results
    $reportPath = Export-TestResults
    
    # Open report if interactive
    if ([Environment]::UserInteractive -and $reportPath) {
        Start-Process $reportPath
    }
    
    # Report final status
    if ($script:TestsFailed -eq 0) {
        Write-TestLog -Message "All tests completed successfully! ($script:TestsPassed passed, $script:TestsSkipped skipped)" -Level Success
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





