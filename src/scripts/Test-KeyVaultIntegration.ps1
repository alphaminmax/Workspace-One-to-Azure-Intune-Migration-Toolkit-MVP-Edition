<#
.SYNOPSIS
    Tests the Key Vault integration in the SecurityFoundation module.
    
.DESCRIPTION
    This script demonstrates the use of the Azure Key Vault integration
    features in the SecurityFoundation module. It tests storing and
    retrieving credentials and secrets.
    
.PARAMETER KeyVaultName
    The name of the Azure Key Vault to use.
    
.PARAMETER EnvFilePath
    Optional path to a .env file containing environment variables.
    
.PARAMETER StandardAdminAccount
    Optional username of a standard admin account to use for privileged operations.
    
.EXAMPLE
    .\Test-KeyVaultIntegration.ps1 -KeyVaultName "MigrationKeyVault"
    
.EXAMPLE
    .\Test-KeyVaultIntegration.ps1 -KeyVaultName "MigrationKeyVault" -EnvFilePath "./.env" -StandardAdminAccount "MigrationAdmin"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$EnvFilePath = "./.env",
    
    [Parameter(Mandatory = $false)]
    [string]$StandardAdminAccount
)

# Change to the working directory (scripts folder)
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $scriptPath

# Import required modules
$modulePath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "modules"
$loggingModulePath = Join-Path -Path $modulePath -ChildPath "LoggingModule.psm1"
$securityFoundationPath = Join-Path -Path $modulePath -ChildPath "SecurityFoundation.psm1"
$secureCredentialProviderPath = Join-Path -Path $modulePath -ChildPath "SecureCredentialProvider.psm1"

# Import modules
Import-Module $loggingModulePath -Force
Import-Module $secureCredentialProviderPath -Force
Import-Module $securityFoundationPath -Force

# Initialize logging
$logFolder = Join-Path -Path $env:TEMP -ChildPath "KeyVaultTest"
if (-not (Test-Path -Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
}
Initialize-Logging -LogPath (Join-Path -Path $logFolder -ChildPath "KeyVaultTest.log") -LogLevel "INFO"

Write-Host "Starting Key Vault integration test..." -ForegroundColor Green
Write-Log -Message "Starting Key Vault integration test with vault: $KeyVaultName" -Level INFO

# Enable Key Vault integration
try {
    $enableResult = Enable-KeyVaultIntegration -KeyVaultName $KeyVaultName -EnvFilePath $EnvFilePath
    
    if (-not $enableResult) {
        Write-Host "Failed to enable Key Vault integration." -ForegroundColor Red
        Write-Log -Message "Failed to enable Key Vault integration" -Level ERROR
        exit 1
    }
    
    Write-Host "Key Vault integration enabled successfully." -ForegroundColor Green
    Write-Log -Message "Key Vault integration enabled successfully" -Level INFO
}
catch {
    Write-Host "Error enabling Key Vault integration: $_" -ForegroundColor Red
    Write-Log -Message "Error enabling Key Vault integration: $_" -Level ERROR
    exit 1
}

# Test storing and retrieving a credential
try {
    Write-Host "`nTesting credential storage and retrieval..." -ForegroundColor Cyan
    
    # Create a test credential
    $username = "testuser@example.com"
    $password = ConvertTo-SecureString -String "TestP@ssw0rd123!" -AsPlainText -Force
    $testCred = New-Object System.Management.Automation.PSCredential($username, $password)
    
    # Store credential in Key Vault
    $storeResult = Set-KeyVaultCredential -Name "TestCredential" -Credential $testCred
    
    if (-not $storeResult) {
        Write-Host "Failed to store credential in Key Vault." -ForegroundColor Red
        Write-Log -Message "Failed to store credential in Key Vault" -Level ERROR
    }
    else {
        Write-Host "Credential stored successfully in Key Vault." -ForegroundColor Green
        Write-Log -Message "Credential stored successfully in Key Vault" -Level INFO
        
        # Retrieve credential from Key Vault
        $retrievedCred = Get-KeyVaultCredential -Name "TestCredential"
        
        if ($null -eq $retrievedCred) {
            Write-Host "Failed to retrieve credential from Key Vault." -ForegroundColor Red
            Write-Log -Message "Failed to retrieve credential from Key Vault" -Level ERROR
        }
        else {
            $retrievedUsername = $retrievedCred.UserName
            Write-Host "Credential retrieved successfully from Key Vault: $retrievedUsername" -ForegroundColor Green
            Write-Log -Message "Credential retrieved successfully from Key Vault: $retrievedUsername" -Level INFO
        }
    }
}
catch {
    Write-Host "Error testing credential storage and retrieval: $_" -ForegroundColor Red
    Write-Log -Message "Error testing credential storage and retrieval: $_" -Level ERROR
}

# Test storing and retrieving a secret
try {
    Write-Host "`nTesting secret storage and retrieval..." -ForegroundColor Cyan
    
    # Create a test secret
    $secretValue = "TestSecretValue123!"
    
    # Store secret in Key Vault
    $storeResult = Set-KeyVaultSecret -Name "TestSecret" -SecretValue $secretValue
    
    if (-not $storeResult) {
        Write-Host "Failed to store secret in Key Vault." -ForegroundColor Red
        Write-Log -Message "Failed to store secret in Key Vault" -Level ERROR
    }
    else {
        Write-Host "Secret stored successfully in Key Vault." -ForegroundColor Green
        Write-Log -Message "Secret stored successfully in Key Vault" -Level INFO
        
        # Retrieve secret from Key Vault
        $retrievedSecret = Get-KeyVaultSecret -Name "TestSecret" -AsPlainText
        
        if ($null -eq $retrievedSecret) {
            Write-Host "Failed to retrieve secret from Key Vault." -ForegroundColor Red
            Write-Log -Message "Failed to retrieve secret from Key Vault" -Level ERROR
        }
        else {
            Write-Host "Secret retrieved successfully from Key Vault: $retrievedSecret" -ForegroundColor Green
            Write-Log -Message "Secret retrieved successfully from Key Vault" -Level INFO
        }
    }
}
catch {
    Write-Host "Error testing secret storage and retrieval: $_" -ForegroundColor Red
    Write-Log -Message "Error testing secret storage and retrieval: $_" -Level ERROR
}

# Test admin credential retrieval
if (-not [string]::IsNullOrEmpty($StandardAdminAccount)) {
    try {
        Write-Host "`nTesting admin credential retrieval..." -ForegroundColor Cyan
        
        # Retrieve admin credentials
        $adminCred = Get-AdminAccountCredential -AllowTemporaryAdmin
        
        if ($null -eq $adminCred) {
            Write-Host "Failed to retrieve admin credentials." -ForegroundColor Red
            Write-Log -Message "Failed to retrieve admin credentials" -Level ERROR
        }
        else {
            $adminUsername = $adminCred.UserName
            Write-Host "Admin credentials retrieved successfully: $adminUsername" -ForegroundColor Green
            Write-Log -Message "Admin credentials retrieved successfully: $adminUsername" -Level INFO
        }
    }
    catch {
        Write-Host "Error testing admin credential retrieval: $_" -ForegroundColor Red
        Write-Log -Message "Error testing admin credential retrieval: $_" -Level ERROR
    }
}

Write-Host "`nKey Vault integration test completed." -ForegroundColor Green
Write-Log -Message "Key Vault integration test completed" -Level INFO

# Display log file location
Write-Host "`nLog file: $(Join-Path -Path $logFolder -ChildPath "KeyVaultTest.log")" -ForegroundColor Cyan 