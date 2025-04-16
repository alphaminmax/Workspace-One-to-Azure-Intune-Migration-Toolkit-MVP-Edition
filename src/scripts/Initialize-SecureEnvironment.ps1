<#
.SYNOPSIS
    Initializes a secure environment for the migration toolkit using Azure Key Vault and .env file.

.DESCRIPTION
    This script sets up the secure credential environment for the Workspace ONE to Intune Migration Toolkit
    by configuring Azure Key Vault integration and loading environment variables from a .env file.
    It demonstrates how to use the SecureCredentialProvider module to handle sensitive information securely.

.PARAMETER KeyVaultName
    The name of the Azure Key Vault that contains secrets for the migration process.

.PARAMETER EnvFilePath
    The path to the .env file containing environment variables. Defaults to "./.env" in the current directory.

.PARAMETER StandardAdminAccount
    The username of the standard local admin account to use for privileged operations.

.PARAMETER AllowInteractive
    If specified, allows interactive prompting for missing credentials.

.PARAMETER SkipKeyVault
    If specified, skips Azure Key Vault integration and uses only environment variables.

.EXAMPLE
    .\Initialize-SecureEnvironment.ps1 -KeyVaultName "WS1MigrationVault" -StandardAdminAccount "MigrationAdmin"

.EXAMPLE
    .\Initialize-SecureEnvironment.ps1 -EnvFilePath "C:\Secure\.env" -SkipKeyVault -AllowInteractive

.NOTES
    File Name      : Initialize-SecureEnvironment.ps1
    Author         : Migration Toolkit Team
    Prerequisite   : SecureCredentialProvider.psm1, Az.KeyVault PowerShell module
    Version        : 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$EnvFilePath = "./.env",
    
    [Parameter(Mandatory = $false)]
    [string]$StandardAdminAccount,
    
    [Parameter(Mandatory = $false)]
    [switch]$AllowInteractive,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipKeyVault
)

# Import required modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules"
$credentialProviderPath = Join-Path -Path $modulePath -ChildPath "SecureCredentialProvider.psm1"
$loggingModulePath = Join-Path -Path $modulePath -ChildPath "LoggingModule.psm1"

# Import logging module
if (Test-Path -Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
    $loggingAvailable = $true
    
    # Initialize logging
    $logFolder = Join-Path -Path $env:TEMP -ChildPath "MigrationLogs"
    if (-not (Test-Path -Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }
    
    Initialize-Logging -LogPath (Join-Path -Path $logFolder -ChildPath "SecureEnvironment.log") -LogLevel "INFO"
    Write-Log -Message "Starting secure environment initialization" -Level INFO
}
else {
    $loggingAvailable = $false
    Write-Verbose "Logging module not found at: $loggingModulePath"
}

# Import SecureCredentialProvider module
if (Test-Path -Path $credentialProviderPath) {
    try {
        Import-Module $credentialProviderPath -Force
        
        if ($loggingAvailable) {
            Write-Log -Message "Successfully imported SecureCredentialProvider module" -Level INFO
        }
        else {
            Write-Verbose "Successfully imported SecureCredentialProvider module"
        }
    }
    catch {
        if ($loggingAvailable) {
            Write-Log -Message "Failed to import SecureCredentialProvider module: $_" -Level ERROR
        }
        else {
            Write-Error "Failed to import SecureCredentialProvider module: $_"
        }
        
        exit 1
    }
}
else {
    if ($loggingAvailable) {
        Write-Log -Message "SecureCredentialProvider module not found at: $credentialProviderPath" -Level ERROR
    }
    else {
        Write-Error "SecureCredentialProvider module not found at: $credentialProviderPath"
    }
    
    exit 1
}

# Initialize secure credential provider
try {
    # Build parameters for initialization
    $initParams = @{}
    
    if (-not $SkipKeyVault -and -not [string]::IsNullOrEmpty($KeyVaultName)) {
        $initParams.KeyVaultName = $KeyVaultName
        $initParams.UseKeyVault = $true
        
        if ($loggingAvailable) {
            Write-Log -Message "Configuring Key Vault integration with vault: $KeyVaultName" -Level INFO
        }
        else {
            Write-Verbose "Configuring Key Vault integration with vault: $KeyVaultName"
        }
    }
    
    if (Test-Path -Path $EnvFilePath) {
        $initParams.EnvFilePath = $EnvFilePath
        $initParams.UseEnvFile = $true
        
        if ($loggingAvailable) {
            Write-Log -Message "Using environment file: $EnvFilePath" -Level INFO
        }
        else {
            Write-Verbose "Using environment file: $EnvFilePath"
        }
    }
    else {
        if ($loggingAvailable) {
            Write-Log -Message "Environment file not found at: $EnvFilePath" -Level WARNING
        }
        else {
            Write-Warning "Environment file not found at: $EnvFilePath"
        }
    }
    
    if (-not [string]::IsNullOrEmpty($StandardAdminAccount)) {
        $initParams.StandardAdminAccount = $StandardAdminAccount
        
        if ($loggingAvailable) {
            Write-Log -Message "Using standard admin account: $StandardAdminAccount" -Level INFO
        }
        else {
            Write-Verbose "Using standard admin account: $StandardAdminAccount"
        }
    }
    
    # Initialize the secure credential provider
    $result = Initialize-SecureCredentialProvider @initParams
    
    if ($result) {
        if ($loggingAvailable) {
            Write-Log -Message "Successfully initialized secure credential provider" -Level INFO
        }
        else {
            Write-Verbose "Successfully initialized secure credential provider"
        }
    }
    else {
        throw "Initialization returned false"
    }
}
catch {
    if ($loggingAvailable) {
        Write-Log -Message "Failed to initialize secure credential provider: $_" -Level ERROR
    }
    else {
        Write-Error "Failed to initialize secure credential provider: $_"
    }
    
    exit 1
}

# Demonstrate credential retrieval
try {
    # Retrieve Azure AD credentials
    if (-not $SkipKeyVault) {
        $azureClientId = $null
        $azureClientSecret = $null
        
        try {
            $azureClientId = Get-SecretFromKeyVault -SecretName "AzureAD-ClientID" -AsPlainText
            $azureClientSecret = Get-SecretFromKeyVault -SecretName "AzureAD-ClientSecret"
            
            if ($loggingAvailable) {
                if ($azureClientId) {
                    Write-Log -Message "Successfully retrieved Azure AD client ID" -Level INFO
                }
                
                if ($azureClientSecret) {
                    Write-Log -Message "Successfully retrieved Azure AD client secret" -Level INFO
                }
            }
            else {
                if ($azureClientId) {
                    Write-Verbose "Successfully retrieved Azure AD client ID"
                }
                
                if ($azureClientSecret) {
                    Write-Verbose "Successfully retrieved Azure AD client secret"
                }
            }
        }
        catch {
            if ($loggingAvailable) {
                Write-Log -Message "Failed to retrieve Azure AD credentials from Key Vault: $_" -Level WARNING
            }
            else {
                Write-Warning "Failed to retrieve Azure AD credentials from Key Vault: $_"
            }
        }
    }
    
    # Retrieve Workspace ONE API credentials
    try {
        $ws1Credential = Get-SecureCredential -CredentialName "WorkspaceOneAPI" -AllowInteractive:$AllowInteractive
        
        if ($ws1Credential) {
            if ($loggingAvailable) {
                Write-Log -Message "Successfully retrieved Workspace ONE API credentials for user: $($ws1Credential.UserName)" -Level INFO
            }
            else {
                Write-Verbose "Successfully retrieved Workspace ONE API credentials for user: $($ws1Credential.UserName)"
            }
        }
    }
    catch {
        if ($loggingAvailable) {
            Write-Log -Message "Failed to retrieve Workspace ONE API credentials: $_" -Level WARNING
        }
        else {
            Write-Warning "Failed to retrieve Workspace ONE API credentials: $_"
        }
    }
    
    # Get admin credentials
    try {
        $adminCred = Get-AdminCredential -AllowTemporaryAdmin:$AllowInteractive
        
        if ($adminCred) {
            if ($loggingAvailable) {
                Write-Log -Message "Successfully retrieved admin credentials for user: $($adminCred.UserName)" -Level INFO
            }
            else {
                Write-Verbose "Successfully retrieved admin credentials for user: $($adminCred.UserName)"
            }
            
            # Check if this is a standard or temporary admin
            if ($adminCred.UserName -eq $StandardAdminAccount) {
                if ($loggingAvailable) {
                    Write-Log -Message "Using standard admin account" -Level INFO
                }
                else {
                    Write-Verbose "Using standard admin account"
                }
            }
            else {
                if ($loggingAvailable) {
                    Write-Log -Message "Using temporary admin account" -Level WARNING
                }
                else {
                    Write-Warning "Using temporary admin account"
                }
            }
        }
    }
    catch {
        if ($loggingAvailable) {
            Write-Log -Message "Failed to retrieve admin credentials: $_" -Level ERROR
        }
        else {
            Write-Error "Failed to retrieve admin credentials: $_"
        }
    }
    
    # Output summary
    Write-Host "`n===== Secure Environment Initialization Summary =====" -ForegroundColor Green
    Write-Host "Key Vault Integration: $(-not $SkipKeyVault -and -not [string]::IsNullOrEmpty($KeyVaultName))"
    Write-Host "Environment File Used: $(Test-Path -Path $EnvFilePath)"
    Write-Host "Standard Admin Account: $StandardAdminAccount"
    Write-Host "Azure AD Credentials Retrieved: $($null -ne $azureClientId -and $null -ne $azureClientSecret)"
    Write-Host "Workspace ONE Credentials Retrieved: $($null -ne $ws1Credential)"
    Write-Host "Admin Credentials Retrieved: $($null -ne $adminCred)"
    Write-Host "================================================`n"
    
    if ($loggingAvailable) {
        Write-Log -Message "Secure environment initialization completed successfully" -Level INFO
        Write-Host "Log file available at: $(Join-Path -Path $logFolder -ChildPath "SecureEnvironment.log")" -ForegroundColor Cyan
    }
}
catch {
    if ($loggingAvailable) {
        Write-Log -Message "Error during credential retrieval demonstration: $_" -Level ERROR
    }
    else {
        Write-Error "Error during credential retrieval demonstration: $_"
    }
    
    exit 1
}

# Return success
exit 0 