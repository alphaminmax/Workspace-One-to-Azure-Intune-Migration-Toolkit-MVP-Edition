<#
.SYNOPSIS
    Updates settings.json file with values from .env or Azure Key Vault.

.DESCRIPTION
    This script reads values from a .env file or Azure Key Vault and updates the settings.json file 
    with those values, ensuring sensitive credentials aren't stored directly in the settings file.

.PARAMETER EnvFilePath
    Path to the .env file. Defaults to "./.env" in the current directory.

.PARAMETER SettingsPath
    Path to the settings.json file. Defaults to "./config/settings.json".

.PARAMETER UseKeyVault
    If specified, retrieves secrets from Azure Key Vault instead of just the .env file.

.PARAMETER KeyVaultName
    The name of the Azure Key Vault to use. Required if UseKeyVault is specified.

.EXAMPLE
    .\Update-SettingsFromEnv.ps1
    
.EXAMPLE
    .\Update-SettingsFromEnv.ps1 -EnvFilePath "C:\Secure\.env" -SettingsPath "C:\Config\settings.json"
    
.EXAMPLE
    .\Update-SettingsFromEnv.ps1 -UseKeyVault -KeyVaultName "WS1MigrationVault"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$EnvFilePath = "./.env",
    
    [Parameter(Mandatory = $false)]
    [string]$SettingsPath = "./config/settings.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$UseKeyVault,
    
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName
)

# Import required modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules"
$credentialProviderPath = Join-Path -Path $modulePath -ChildPath "SecureCredentialProvider.psm1"
$loggingModulePath = Join-Path -Path $modulePath -ChildPath "LoggingModule.psm1"

# Import logging module if available
if (Test-Path -Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
    $loggingAvailable = $true
    
    # Initialize logging
    $logFolder = Join-Path -Path $env:TEMP -ChildPath "MigrationLogs"
    if (-not (Test-Path -Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }
    
    Initialize-Logging -LogPath (Join-Path -Path $logFolder -ChildPath "UpdateSettings.log") -LogLevel "INFO"
    Write-Log -Message "Starting settings update from environment variables" -Level INFO
}
else {
    $loggingAvailable = $false
    Write-Verbose "Logging module not found at: $loggingModulePath"
}

# Check if settings file exists
if (-not (Test-Path -Path $SettingsPath)) {
    $errorMessage = "Settings file not found at: $SettingsPath"
    if ($loggingAvailable) {
        Write-Log -Message $errorMessage -Level ERROR
    }
    else {
        Write-Error $errorMessage
    }
    exit 1
}

# Initialize credential provider if using Key Vault
$secretProvider = $null
if ($UseKeyVault) {
    if ([string]::IsNullOrEmpty($KeyVaultName)) {
        $errorMessage = "KeyVaultName parameter is required when UseKeyVault is specified"
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        exit 1
    }
    
    # Import the SecureCredentialProvider module
    if (Test-Path -Path $credentialProviderPath) {
        try {
            Import-Module $credentialProviderPath -Force
            
            # Initialize the credential provider
            Initialize-SecureCredentialProvider -KeyVaultName $KeyVaultName -UseKeyVault -EnvFilePath $EnvFilePath -UseEnvFile
            
            if ($loggingAvailable) {
                Write-Log -Message "Successfully initialized SecureCredentialProvider with Key Vault: $KeyVaultName" -Level INFO
            }
            else {
                Write-Verbose "Successfully initialized SecureCredentialProvider with Key Vault: $KeyVaultName"
            }
            
            $secretProvider = "KeyVault"
        }
        catch {
            $errorMessage = "Failed to initialize SecureCredentialProvider: $_"
            if ($loggingAvailable) {
                Write-Log -Message $errorMessage -Level ERROR
            }
            else {
                Write-Error $errorMessage
            }
            exit 1
        }
    }
    else {
        $warningMessage = "SecureCredentialProvider module not found, falling back to .env file only"
        if ($loggingAvailable) {
            Write-Log -Message $warningMessage -Level WARNING
        }
        else {
            Write-Warning $warningMessage
        }
    }
}

# Load environment variables from .env file if not using Key Vault
$envVariables = @{}
if (-not $UseKeyVault -or $secretProvider -ne "KeyVault") {
    if (Test-Path -Path $EnvFilePath) {
        try {
            $envContent = Get-Content -Path $EnvFilePath -ErrorAction Stop
            
            foreach ($line in $envContent) {
                if ($line.Trim() -eq "" -or $line.StartsWith("#")) {
                    continue
                }
                
                $keyValue = $line.Split('=', 2)
                if ($keyValue.Length -eq 2) {
                    $key = $keyValue[0].Trim()
                    $value = $keyValue[1].Trim()
                    
                    # Store in our hash table
                    $envVariables[$key] = $value
                }
            }
            
            if ($loggingAvailable) {
                Write-Log -Message "Successfully loaded environment variables from $EnvFilePath" -Level INFO
            }
            else {
                Write-Verbose "Successfully loaded environment variables from $EnvFilePath"
            }
        }
        catch {
            $errorMessage = "Error loading environment variables from $EnvFilePath`: $_"
            if ($loggingAvailable) {
                Write-Log -Message $errorMessage -Level ERROR
            }
            else {
                Write-Error $errorMessage
            }
            exit 1
        }
    }
    else {
        $errorMessage = "Environment file not found at: $EnvFilePath"
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        exit 1
    }
}

# Load the settings.json file
try {
    $settings = Get-Content -Path $SettingsPath -Raw | ConvertFrom-Json
    
    if ($loggingAvailable) {
        Write-Log -Message "Successfully loaded settings from $SettingsPath" -Level INFO
    }
    else {
        Write-Verbose "Successfully loaded settings from $SettingsPath"
    }
}
catch {
    $errorMessage = "Error loading settings from $SettingsPath`: $_"
    if ($loggingAvailable) {
        Write-Log -Message $errorMessage -Level ERROR
    }
    else {
        Write-Error $errorMessage
    }
    exit 1
}

# Update settings with values from environment variables or Key Vault
try {
    # Local path
    if ($envVariables.ContainsKey("LOCAL_PATH") -and -not [string]::IsNullOrEmpty($envVariables["LOCAL_PATH"])) {
        $settings.localPath = $envVariables["LOCAL_PATH"]
    }
    
    # Log path
    if ($envVariables.ContainsKey("LOG_PATH") -and -not [string]::IsNullOrEmpty($envVariables["LOG_PATH"])) {
        $settings.logPath = $envVariables["LOG_PATH"]
    }
    
    # Target tenant settings
    # From environment variables
    if ($envVariables.ContainsKey("AZURE_CLIENT_ID") -and -not [string]::IsNullOrEmpty($envVariables["AZURE_CLIENT_ID"])) {
        $settings.targetTenant.clientID = $envVariables["AZURE_CLIENT_ID"]
    }
    
    if ($envVariables.ContainsKey("AZURE_CLIENT_SECRET") -and -not [string]::IsNullOrEmpty($envVariables["AZURE_CLIENT_SECRET"])) {
        $settings.targetTenant.clientSecret = $envVariables["AZURE_CLIENT_SECRET"]
    }
    
    if ($envVariables.ContainsKey("AZURE_TENANT_NAME") -and -not [string]::IsNullOrEmpty($envVariables["AZURE_TENANT_NAME"])) {
        $settings.targetTenant.tenantName = $envVariables["AZURE_TENANT_NAME"]
    }
    
    if ($envVariables.ContainsKey("AZURE_TENANT_ID") -and -not [string]::IsNullOrEmpty($envVariables["AZURE_TENANT_ID"])) {
        $settings.targetTenant.tenantID = $envVariables["AZURE_TENANT_ID"]
    }
    
    # From Key Vault
    if ($secretProvider -eq "KeyVault") {
        $clientID = Get-SecretFromKeyVault -SecretName "AzureAD-ClientID" -AsPlainText -ErrorAction SilentlyContinue
        if ($clientID) {
            $settings.targetTenant.clientID = $clientID
        }
        
        $clientSecret = Get-SecretFromKeyVault -SecretName "AzureAD-ClientSecret" -AsPlainText -ErrorAction SilentlyContinue
        if ($clientSecret) {
            $settings.targetTenant.clientSecret = $clientSecret
        }
        
        $tenantName = Get-SecretFromKeyVault -SecretName "AzureAD-TenantName" -AsPlainText -ErrorAction SilentlyContinue
        if ($tenantName) {
            $settings.targetTenant.tenantName = $tenantName
        }
        
        $tenantID = Get-SecretFromKeyVault -SecretName "AzureAD-TenantID" -AsPlainText -ErrorAction SilentlyContinue
        if ($tenantID) {
            $settings.targetTenant.tenantID = $tenantID
        }
    }
    
    # Workspace ONE settings
    # From environment variables
    if ($envVariables.ContainsKey("WS1_HOST") -and -not [string]::IsNullOrEmpty($envVariables["WS1_HOST"])) {
        $settings.ws1host = $envVariables["WS1_HOST"]
    }
    
    if ($envVariables.ContainsKey("WS1_USERNAME") -and -not [string]::IsNullOrEmpty($envVariables["WS1_USERNAME"])) {
        $settings.ws1username = $envVariables["WS1_USERNAME"]
    }
    
    if ($envVariables.ContainsKey("WS1_PASSWORD") -and -not [string]::IsNullOrEmpty($envVariables["WS1_PASSWORD"])) {
        $settings.ws1password = $envVariables["WS1_PASSWORD"]
    }
    
    if ($envVariables.ContainsKey("WS1_API_KEY") -and -not [string]::IsNullOrEmpty($envVariables["WS1_API_KEY"])) {
        $settings.ws1apikey = $envVariables["WS1_API_KEY"]
    }
    
    # From Key Vault
    if ($secretProvider -eq "KeyVault") {
        $ws1Host = Get-SecretFromKeyVault -SecretName "WorkspaceOne-Host" -AsPlainText -ErrorAction SilentlyContinue
        if ($ws1Host) {
            $settings.ws1host = $ws1Host
        }
        
        $ws1Username = Get-SecretFromKeyVault -SecretName "WorkspaceOne-Username" -AsPlainText -ErrorAction SilentlyContinue
        if ($ws1Username) {
            $settings.ws1username = $ws1Username
        }
        
        $ws1Password = Get-SecretFromKeyVault -SecretName "WorkspaceOne-Password" -AsPlainText -ErrorAction SilentlyContinue
        if ($ws1Password) {
            $settings.ws1password = $ws1Password
        }
        
        $ws1ApiKey = Get-SecretFromKeyVault -SecretName "WorkspaceOne-ApiKey" -AsPlainText -ErrorAction SilentlyContinue
        if ($ws1ApiKey) {
            $settings.ws1apikey = $ws1ApiKey
        }
    }
    
    # Other settings
    if ($envVariables.ContainsKey("REG_PATH") -and -not [string]::IsNullOrEmpty($envVariables["REG_PATH"])) {
        $settings.regPath = $envVariables["REG_PATH"]
    }
    
    if ($envVariables.ContainsKey("GROUP_TAG") -and -not [string]::IsNullOrEmpty($envVariables["GROUP_TAG"])) {
        $settings.groupTag = $envVariables["GROUP_TAG"]
    }
    
    if ($envVariables.ContainsKey("BITLOCKER_METHOD") -and -not [string]::IsNullOrEmpty($envVariables["BITLOCKER_METHOD"])) {
        $settings.bitlockerMethod = $envVariables["BITLOCKER_METHOD"]
    }
    
    # Save updated settings
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsPath
    
    if ($loggingAvailable) {
        Write-Log -Message "Successfully updated settings with values from environment/Key Vault" -Level INFO
    }
    else {
        Write-Verbose "Successfully updated settings with values from environment/Key Vault"
    }
}
catch {
    $errorMessage = "Error updating settings: $_"
    if ($loggingAvailable) {
        Write-Log -Message $errorMessage -Level ERROR
    }
    else {
        Write-Error $errorMessage
    }
    exit 1
}

# Mask sensitive information when displaying success
$maskedSettings = $settings | ConvertTo-Json -Depth 10
$maskedSettings = $maskedSettings -replace '(?<=:")(.*?)(?=")','********'

# Output success message
$sourceText = if ($UseKeyVault) { "Azure Key Vault and" } else { "" }
Write-Host "Settings updated successfully from $sourceText environment variables." -ForegroundColor Green

# Output details if verbose
if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
    Write-Verbose "Updated settings (sensitive information masked):"
    Write-Verbose $maskedSettings
}

if ($loggingAvailable) {
    Write-Log -Message "Settings update completed successfully" -Level INFO
}

exit 0 