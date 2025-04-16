#Requires -Version 5.1
#Requires -Modules Az.KeyVault
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Tests Azure Key Vault integration with security modules.                                                              #
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
    Tests Azure Key Vault integration with security modules.

.DESCRIPTION
    This script validates the functionality of the SecureCredentialProvider and SecurityFoundation modules
    with Azure Key Vault. It performs a series of tests to ensure credentials can be properly stored,
    retrieved, and managed securely.

.PARAMETER KeyVaultName
    The name of the Azure Key Vault to test against.

.PARAMETER ConfigPath
    Optional path to the configuration file. If not specified, uses the default config location.

.EXAMPLE
    .\Test-KeyVaultIntegration.ps1 -KeyVaultName "MyMigrationKeyVault"

.NOTES
    Requires Az.KeyVault module to be installed.
    Must be executed with sufficient permissions to access the Key Vault.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\..\config\settings.json"
)

# Import required modules
Import-Module -Name "$PSScriptRoot\..\modules\LoggingModule.psm1" -Force
Import-Module -Name "$PSScriptRoot\..\modules\SecureCredentialProvider.psm1" -Force
Import-Module -Name "$PSScriptRoot\..\modules\SecurityFoundation.psm1" -Force

# Initialize logging
Initialize-Logging -LogName "KeyVaultIntegrationTest" -LogLevel "Verbose"

function Test-KeyVaultAccess {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Level "Info" -Message "Testing Key Vault access for: $KeyVaultName"
    
    try {
        $vault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop
        Write-LogMessage -Level "Success" -Message "Successfully connected to Key Vault: $($vault.VaultName)"
        return $true
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed to access Key Vault: $_"
        return $false
    }
}

function Test-CredentialProviderInitialization {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Level "Info" -Message "Testing SecureCredentialProvider initialization"
    
    try {
        Initialize-CredentialProvider -KeyVaultName $KeyVaultName -ErrorAction Stop
        Write-LogMessage -Level "Success" -Message "Successfully initialized SecureCredentialProvider"
        return $true
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed to initialize SecureCredentialProvider: $_"
        return $false
    }
}

function Test-CredentialStorage {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Level "Info" -Message "Testing credential storage and retrieval"
    
    $testUsername = "testuser@example.com"
    $testPassword = ConvertTo-SecureString "TestP@ssw0rd" -AsPlainText -Force
    $testCredential = New-Object System.Management.Automation.PSCredential($testUsername, $testPassword)
    
    try {
        # Store credential
        Set-SecureCredential -Name "TestCredential" -Credential $testCredential -ErrorAction Stop
        Write-LogMessage -Level "Success" -Message "Successfully stored test credential"
        
        # Retrieve credential
        $retrievedCredential = Get-SecureCredential -Name "TestCredential" -ErrorAction Stop
        
        if ($retrievedCredential.UserName -eq $testUsername) {
            Write-LogMessage -Level "Success" -Message "Successfully retrieved test credential"
            return $true
        }
        else {
            Write-LogMessage -Level "Error" -Message "Retrieved credential does not match expected username"
            return $false
        }
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed in credential storage test: $_"
        return $false
    }
    finally {
        # Clean up test credential
        try {
            Remove-SecureCredential -Name "TestCredential" -ErrorAction SilentlyContinue
            Write-LogMessage -Level "Info" -Message "Cleaned up test credential"
        }
        catch {
            Write-LogMessage -Level "Warning" -Message "Failed to clean up test credential: $_"
        }
    }
}

function Test-SecretStorage {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Level "Info" -Message "Testing secret storage and retrieval"
    
    $testSecretValue = "ThisIsATestSecret123!"
    $secureSecret = ConvertTo-SecureString $testSecretValue -AsPlainText -Force
    
    try {
        # Store secret
        Set-SecureSecret -Name "TestSecret" -SecretValue $secureSecret -ErrorAction Stop
        Write-LogMessage -Level "Success" -Message "Successfully stored test secret"
        
        # Retrieve secret
        $retrievedSecretSecure = Get-SecureSecret -Name "TestSecret" -ErrorAction Stop
        $retrievedSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedSecretSecure)
        )
        
        if ($retrievedSecret -eq $testSecretValue) {
            Write-LogMessage -Level "Success" -Message "Successfully retrieved test secret"
            return $true
        }
        else {
            Write-LogMessage -Level "Error" -Message "Retrieved secret does not match expected value"
            return $false
        }
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed in secret storage test: $_"
        return $false
    }
    finally {
        # Clean up test secret
        try {
            Remove-SecureSecret -Name "TestSecret" -ErrorAction SilentlyContinue
            Write-LogMessage -Level "Info" -Message "Cleaned up test secret"
        }
        catch {
            Write-LogMessage -Level "Warning" -Message "Failed to clean up test secret: $_"
        }
    }
}

function Test-SecurityFoundationIntegration {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Level "Info" -Message "Testing SecurityFoundation integration with Key Vault"
    
    try {
        # Initialize the security foundation module
        Initialize-SecurityFoundation -KeyVaultName $KeyVaultName -ErrorAction Stop
        Write-LogMessage -Level "Success" -Message "Successfully initialized SecurityFoundation module"
        
        # Test encryption certificate access
        $cert = Get-EncryptionCertificate -ErrorAction Stop
        
        if ($cert -ne $null) {
            Write-LogMessage -Level "Success" -Message "Successfully retrieved encryption certificate"
            return $true
        }
        else {
            Write-LogMessage -Level "Error" -Message "Failed to retrieve encryption certificate"
            return $false
        }
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed in SecurityFoundation integration test: $_"
        return $false
    }
}

# Main test execution
Write-LogMessage -Level "Info" -Message "=== Starting Key Vault Integration Tests ==="
Write-LogMessage -Level "Info" -Message "Key Vault: $KeyVaultName"
Write-LogMessage -Level "Info" -Message "Config Path: $ConfigPath"

$totalTests = 4
$passedTests = 0

# Test 1: Key Vault Access
if (Test-KeyVaultAccess) {
    $passedTests++
}
else {
    Write-LogMessage -Level "Error" -Message "Key Vault access test failed. Cannot continue with remaining tests."
    exit 1
}

# Test 2: Credential Provider Initialization
if (Test-CredentialProviderInitialization) {
    $passedTests++
}
else {
    Write-LogMessage -Level "Error" -Message "SecureCredentialProvider initialization failed. Cannot continue with remaining tests."
    exit 1
}

# Test 3: Credential Storage
if (Test-CredentialStorage) {
    $passedTests++
}

# Test 4: Secret Storage
if (Test-SecretStorage) {
    $passedTests++
}

# Test 5: SecurityFoundation Integration
if (Test-SecurityFoundationIntegration) {
    $passedTests++
    $totalTests++
}

# Output summary
Write-LogMessage -Level "Info" -Message "=== Key Vault Integration Test Summary ==="
Write-LogMessage -Level "Info" -Message "Tests Run: $totalTests"
Write-LogMessage -Level "Info" -Message "Tests Passed: $passedTests"
Write-LogMessage -Level "Info" -Message "Pass Rate: $([math]::Round(($passedTests/$totalTests)*100, 2))%"

if ($passedTests -eq $totalTests) {
    Write-LogMessage -Level "Success" -Message "All Key Vault integration tests passed successfully!"
    exit 0
}
else {
    Write-LogMessage -Level "Warning" -Message "Some Key Vault integration tests failed. Review the log for details."
    exit 1
} 





