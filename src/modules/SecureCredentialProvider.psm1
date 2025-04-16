#Requires -Version 5.1
#Requires -Modules Az.KeyVault
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Provides secure credential management using Azure Key Vault and environment variables.                                #
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
    Provides secure credential management using Azure Key Vault and environment variables.

.DESCRIPTION
    This module integrates with Azure Key Vault and environment variables to securely
    retrieve and manage credentials for the Workspace ONE to Microsoft Intune migration toolkit.
    It implements a layered approach to credential retrieval with fallback mechanisms.

.NOTES
    File Name      : SecureCredentialProvider.psm1
    Author         : Migration Toolkit Team
    Prerequisite   : Az.KeyVault PowerShell module
    Version        : 1.0.0
#>

# Import required modules
if (-not (Get-Module -Name Az.KeyVault -ListAvailable)) {
    throw "This module requires the Az.KeyVault module. Install using: Install-Module -Name Az.KeyVault -Scope CurrentUser -Force"
}

# Define internal module variables
$script:keyVaultName = $null
$script:connectionEstablished = $false
$script:useKeyVault = $false
$script:useEnvFile = $false
$script:standardAdminAccount = $null
$script:envFilePath = $null
$script:envVariables = @{}

function Initialize-SecureCredentialProvider {
    <#
    .SYNOPSIS
        Initializes the Secure Credential Provider with configuration options.
    
    .DESCRIPTION
        Sets up the credential provider with specified options for credential retrieval.
        Can be configured to use Azure Key Vault, environment variables, or both.
        
    .PARAMETER KeyVaultName
        The name of the Azure Key Vault to use for credential storage and retrieval.
        
    .PARAMETER EnvFilePath
        Path to the .env file containing environment variables.
        
    .PARAMETER StandardAdminAccount
        Username for the standard admin account to use for privileged operations.
        The password will be retrieved from secure storage.
        
    .PARAMETER UseKeyVault
        Switch to enable Azure Key Vault integration.
        
    .PARAMETER UseEnvFile
        Switch to enable .env file usage for environment variables.
        
    .EXAMPLE
        Initialize-SecureCredentialProvider -KeyVaultName "MigrationKeyVault" -UseKeyVault -EnvFilePath "./.env" -UseEnvFile
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
        [switch]$UseKeyVault,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseEnvFile
    )
    
    # Import the logging module if available
    try {
        Import-Module -Name "$PSScriptRoot/LoggingModule.psm1" -ErrorAction SilentlyContinue
        $loggingAvailable = $true
    }
    catch {
        $loggingAvailable = $false
    }
    
    # Log initialization
    if ($loggingAvailable) {
        Write-Log -Message "Initializing Secure Credential Provider" -Level INFO
    }
    else {
        Write-Verbose "Initializing Secure Credential Provider"
    }
    
    # Set module variables
    $script:keyVaultName = $KeyVaultName
    $script:useKeyVault = $UseKeyVault.IsPresent
    $script:useEnvFile = $UseEnvFile.IsPresent
    $script:standardAdminAccount = $StandardAdminAccount
    $script:envFilePath = $EnvFilePath
    
    # Connect to Azure Key Vault if specified
    if ($script:useKeyVault) {
        if ([string]::IsNullOrEmpty($script:keyVaultName)) {
            throw "KeyVaultName is required when UseKeyVault is specified."
        }
        
        try {
            # Check if already connected
            $context = Get-AzContext -ErrorAction SilentlyContinue
            
            if (-not $context) {
                # Log the connection attempt
                if ($loggingAvailable) {
                    Write-Log -Message "Connecting to Azure for Key Vault access" -Level INFO
                }
                else {
                    Write-Verbose "Connecting to Azure for Key Vault access"
                }
                
                # Interactive sign-in
                Connect-AzAccount -ErrorAction Stop
            }
            
            # Verify Key Vault exists and is accessible
            $vault = Get-AzKeyVault -VaultName $script:keyVaultName -ErrorAction Stop
            $script:connectionEstablished = $true
            
            if ($loggingAvailable) {
                Write-Log -Message "Successfully connected to Azure Key Vault: $script:keyVaultName" -Level INFO
            }
            else {
                Write-Verbose "Successfully connected to Azure Key Vault: $script:keyVaultName"
            }
        }
        catch {
            $script:connectionEstablished = $false
            $errorMessage = "Failed to connect to Azure Key Vault: $_"
            
            if ($loggingAvailable) {
                Write-Log -Message $errorMessage -Level ERROR
            }
            else {
                Write-Error $errorMessage
            }
            
            throw $errorMessage
        }
    }
    
    # Load environment variables from .env file if specified
    if ($script:useEnvFile) {
        if (-not (Test-Path -Path $script:envFilePath)) {
            $envWarning = "Environment file not found at path: $script:envFilePath"
            
            if ($loggingAvailable) {
                Write-Log -Message $envWarning -Level WARNING
            }
            else {
                Write-Warning $envWarning
            }
        }
        else {
            # Load environment variables from .env file
            try {
                $envContent = Get-Content -Path $script:envFilePath -ErrorAction Stop
                
                foreach ($line in $envContent) {
                    if ($line.Trim() -eq "" -or $line.StartsWith("#")) {
                        continue
                    }
                    
                    $keyValue = $line.Split('=', 2)
                    if ($keyValue.Length -eq 2) {
                        $key = $keyValue[0].Trim()
                        $value = $keyValue[1].Trim()
                        
                        # Store in our internal hash table
                        $script:envVariables[$key] = $value
                        
                        # Also set as an environment variable for this session
                        [Environment]::SetEnvironmentVariable($key, $value, "Process")
                    }
                }
                
                if ($loggingAvailable) {
                    Write-Log -Message "Successfully loaded environment variables from $script:envFilePath" -Level INFO
                }
                else {
                    Write-Verbose "Successfully loaded environment variables from $script:envFilePath"
                }
            }
            catch {
                $envError = "Error loading environment variables from $script:envFilePath`: $_"
                
                if ($loggingAvailable) {
                    Write-Log -Message $envError -Level ERROR
                }
                else {
                    Write-Error $envError
                }
            }
        }
    }
    
    return $true
}

function Get-SecureCredential {
    <#
    .SYNOPSIS
        Retrieves a secure credential from the configured sources.
    
    .DESCRIPTION
        Attempts to retrieve credentials using a cascading approach:
        1. From Azure Key Vault (if configured)
        2. From environment variables (either from .env file or system environment)
        3. Prompts user if interactive mode is allowed and credential not found
        
    .PARAMETER CredentialName
        The name/identifier of the credential to retrieve.
        
    .PARAMETER AllowInteractive
        If set, allows prompting the user for credentials if not found in Key Vault or environment.
        
    .PARAMETER DefaultUsername
        Optional default username to use if prompting interactively.
        
    .EXAMPLE
        $cred = Get-SecureCredential -CredentialName "WorkspaceOneAPI" -AllowInteractive
    #>
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CredentialName,
        
        [Parameter(Mandatory = $false)]
        [switch]$AllowInteractive,
        
        [Parameter(Mandatory = $false)]
        [string]$DefaultUsername = ""
    )
    
    # Import the logging module if available
    try {
        Import-Module -Name "$PSScriptRoot/LoggingModule.psm1" -ErrorAction SilentlyContinue
        $loggingAvailable = $true
    }
    catch {
        $loggingAvailable = $false
    }
    
    if ($loggingAvailable) {
        Write-Log -Message "Retrieving secure credential: $CredentialName" -Level INFO
    }
    else {
        Write-Verbose "Retrieving secure credential: $CredentialName"
    }
    
    # Try Azure Key Vault first if configured
    if ($script:useKeyVault -and $script:connectionEstablished) {
        try {
            $secretName = $CredentialName.Replace(" ", "").Replace("-", "").Replace("_", "")
            $usernameSecret = Get-AzKeyVaultSecret -VaultName $script:keyVaultName -Name "$secretName-username" -ErrorAction SilentlyContinue
            $passwordSecret = Get-AzKeyVaultSecret -VaultName $script:keyVaultName -Name "$secretName-password" -ErrorAction SilentlyContinue
            
            if ($passwordSecret) {
                $username = if ($usernameSecret) { $usernameSecret.SecretValue | ConvertFrom-SecureString -AsPlainText } else { $DefaultUsername }
                $password = $passwordSecret.SecretValue
                
                if (-not [string]::IsNullOrEmpty($username)) {
                    if ($loggingAvailable) {
                        Write-Log -Message "Found credential in Azure Key Vault: $CredentialName" -Level INFO
                    }
                    else {
                        Write-Verbose "Found credential in Azure Key Vault: $CredentialName"
                    }
                    
                    return New-Object System.Management.Automation.PSCredential($username, $password)
                }
            }
        }
        catch {
            if ($loggingAvailable) {
                Write-Log -Message "Error retrieving credential from Key Vault: $_" -Level WARNING
            }
            else {
                Write-Warning "Error retrieving credential from Key Vault: $_"
            }
        }
    }
    
    # Try environment variables next
    $usernameEnvVar = "${CredentialName}_USERNAME".Replace(" ", "_").ToUpper()
    $passwordEnvVar = "${CredentialName}_PASSWORD".Replace(" ", "_").ToUpper()
    
    $username = [Environment]::GetEnvironmentVariable($usernameEnvVar)
    $password = [Environment]::GetEnvironmentVariable($passwordEnvVar)
    
    if (-not [string]::IsNullOrEmpty($password)) {
        $username = if ([string]::IsNullOrEmpty($username)) { $DefaultUsername } else { $username }
        
        if (-not [string]::IsNullOrEmpty($username)) {
            if ($loggingAvailable) {
                Write-Log -Message "Found credential in environment variables: $CredentialName" -Level INFO
            }
            else {
                Write-Verbose "Found credential in environment variables: $CredentialName"
            }
            
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
            return New-Object System.Management.Automation.PSCredential($username, $securePassword)
        }
    }
    
    # If we're here, credential wasn't found and we need interactive input if allowed
    if ($AllowInteractive) {
        if ($loggingAvailable) {
            Write-Log -Message "Prompting user for credential: $CredentialName" -Level WARNING
        }
        else {
            Write-Warning "Credential not found in secure storage. Prompting for input."
        }
        
        $promptMessage = "Enter credentials for: $CredentialName"
        return Get-Credential -Message $promptMessage -UserName $DefaultUsername
    }
    
    # If we're here, credential wasn't found and interactive input isn't allowed
    $errorMessage = "Credential not found and interactive input not allowed: $CredentialName"
    
    if ($loggingAvailable) {
        Write-Log -Message $errorMessage -Level ERROR
    }
    else {
        Write-Error $errorMessage
    }
    
    throw $errorMessage
}

function Get-AdminCredential {
    <#
    .SYNOPSIS
        Retrieves the standard admin account credentials for privileged operations.
    
    .DESCRIPTION
        Gets the credentials for the standard admin account configured during initialization.
        Falls back to creating a temporary admin if the standard account isn't configured.
        
    .PARAMETER AllowTemporaryAdmin
        If set and standard admin isn't configured, allows creation of a temporary admin account.
        
    .PARAMETER TemporaryAdminPrefix
        Prefix to use for temporary admin account name if one needs to be created.
        
    .EXAMPLE
        $adminCred = Get-AdminCredential -AllowTemporaryAdmin
    #>
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$AllowTemporaryAdmin,
        
        [Parameter(Mandatory = $false)]
        [string]$TemporaryAdminPrefix = "WS1Mig"
    )
    
    # Import the logging module if available
    try {
        Import-Module -Name "$PSScriptRoot/LoggingModule.psm1" -ErrorAction SilentlyContinue
        $loggingAvailable = $true
    }
    catch {
        $loggingAvailable = $false
    }
    
    # Check if standard admin account is configured
    if (-not [string]::IsNullOrEmpty($script:standardAdminAccount)) {
        if ($loggingAvailable) {
            Write-Log -Message "Using standard admin account: $script:standardAdminAccount" -Level INFO
        }
        else {
            Write-Verbose "Using standard admin account: $script:standardAdminAccount"
        }
        
        # Try to get admin credentials from secure storage
        try {
            return Get-SecureCredential -CredentialName "StandardAdmin" -DefaultUsername $script:standardAdminAccount -AllowInteractive
        }
        catch {
            if ($loggingAvailable) {
                Write-Log -Message "Failed to retrieve standard admin credentials: $_" -Level WARNING
            }
            else {
                Write-Warning "Failed to retrieve standard admin credentials: $_"
            }
            
            # Fall through to temporary admin if allowed
        }
    }
    
    # Create temporary admin if allowed
    if ($AllowTemporaryAdmin) {
        if ($loggingAvailable) {
            Write-Log -Message "Standard admin account not configured or credentials not found. Creating temporary admin." -Level WARNING
        }
        else {
            Write-Warning "Standard admin account not configured or credentials not found. Creating temporary admin."
        }
        
        # Import privilege management module to create temporary admin
        try {
            Import-Module -Name "$PSScriptRoot/PrivilegeManagement.psm1" -ErrorAction Stop
            return New-TemporaryAdminAccount -Prefix $TemporaryAdminPrefix
        }
        catch {
            $errorMessage = "Failed to create temporary admin account: $_"
            
            if ($loggingAvailable) {
                Write-Log -Message $errorMessage -Level ERROR
            }
            else {
                Write-Error $errorMessage
            }
            
            throw $errorMessage
        }
    }
    
    # If we're here, no admin account is available
    $errorMessage = "No admin credentials available. Configure a standard admin account or allow temporary admin creation."
    
    if ($loggingAvailable) {
        Write-Log -Message $errorMessage -Level ERROR
    }
    else {
        Write-Error $errorMessage
    }
    
    throw $errorMessage
}

function Set-SecureCredential {
    <#
    .SYNOPSIS
        Stores a credential securely in Azure Key Vault.
    
    .DESCRIPTION
        Saves username and password to Azure Key Vault for later retrieval.
        
    .PARAMETER CredentialName
        The name/identifier of the credential to store.
        
    .PARAMETER Credential
        The PSCredential object containing the username and password.
        
    .EXAMPLE
        $cred = Get-Credential
        Set-SecureCredential -CredentialName "WorkspaceOneAPI" -Credential $cred
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CredentialName,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    # Import the logging module if available
    try {
        Import-Module -Name "$PSScriptRoot/LoggingModule.psm1" -ErrorAction SilentlyContinue
        $loggingAvailable = $true
    }
    catch {
        $loggingAvailable = $false
    }
    
    # Ensure Key Vault is configured
    if (-not $script:useKeyVault -or -not $script:connectionEstablished) {
        $errorMessage = "Azure Key Vault is not configured or connection is not established."
        
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        
        throw $errorMessage
    }
    
    try {
        $secretName = $CredentialName.Replace(" ", "").Replace("-", "").Replace("_", "")
        
        # Store username
        $usernameSecureString = ConvertTo-SecureString -String $Credential.UserName -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $script:keyVaultName -Name "$secretName-username" -SecretValue $usernameSecureString -ErrorAction Stop
        
        # Store password
        Set-AzKeyVaultSecret -VaultName $script:keyVaultName -Name "$secretName-password" -SecretValue $Credential.Password -ErrorAction Stop
        
        if ($loggingAvailable) {
            Write-Log -Message "Successfully stored credential in Key Vault: $CredentialName" -Level INFO
        }
        else {
            Write-Verbose "Successfully stored credential in Key Vault: $CredentialName"
        }
        
        return $true
    }
    catch {
        $errorMessage = "Failed to store credential in Key Vault: $_"
        
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        
        throw $errorMessage
    }
}

function Get-SecretFromKeyVault {
    <#
    .SYNOPSIS
        Retrieves a secret from Azure Key Vault.
    
    .DESCRIPTION
        Gets a specific secret from the configured Azure Key Vault.
        
    .PARAMETER SecretName
        The name of the secret to retrieve.
        
    .PARAMETER AsPlainText
        If set, returns the secret as plain text. Otherwise, returns as SecureString.
        
    .EXAMPLE
        $clientSecret = Get-SecretFromKeyVault -SecretName "AzureAD-ClientSecret" -AsPlainText
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecretName,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsPlainText
    )
    
    # Import the logging module if available
    try {
        Import-Module -Name "$PSScriptRoot/LoggingModule.psm1" -ErrorAction SilentlyContinue
        $loggingAvailable = $true
    }
    catch {
        $loggingAvailable = $false
    }
    
    # Ensure Key Vault is configured
    if (-not $script:useKeyVault -or -not $script:connectionEstablished) {
        $errorMessage = "Azure Key Vault is not configured or connection is not established."
        
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        
        throw $errorMessage
    }
    
    try {
        $secret = Get-AzKeyVaultSecret -VaultName $script:keyVaultName -Name $SecretName -ErrorAction Stop
        
        if ($secret) {
            if ($loggingAvailable) {
                Write-Log -Message "Successfully retrieved secret from Key Vault: $SecretName" -Level INFO
            }
            else {
                Write-Verbose "Successfully retrieved secret from Key Vault: $SecretName"
            }
            
            if ($AsPlainText) {
                return $secret.SecretValue | ConvertFrom-SecureString -AsPlainText
            }
            else {
                return $secret.SecretValue
            }
        }
        else {
            $errorMessage = "Secret not found in Key Vault: $SecretName"
            
            if ($loggingAvailable) {
                Write-Log -Message $errorMessage -Level WARNING
            }
            else {
                Write-Warning $errorMessage
            }
            
            return $null
        }
    }
    catch {
        $errorMessage = "Failed to retrieve secret from Key Vault: $_"
        
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        
        throw $errorMessage
    }
}

function Set-SecretInKeyVault {
    <#
    .SYNOPSIS
        Stores a secret in Azure Key Vault.
    
    .DESCRIPTION
        Saves a secret value to Azure Key Vault for later retrieval.
        
    .PARAMETER SecretName
        The name of the secret to store.
        
    .PARAMETER SecretValue
        The value to store, either as string or SecureString.
        
    .EXAMPLE
        Set-SecretInKeyVault -SecretName "AzureAD-ClientSecret" -SecretValue "your-client-secret"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecretName,
        
        [Parameter(Mandatory = $true)]
        [object]$SecretValue
    )
    
    # Import the logging module if available
    try {
        Import-Module -Name "$PSScriptRoot/LoggingModule.psm1" -ErrorAction SilentlyContinue
        $loggingAvailable = $true
    }
    catch {
        $loggingAvailable = $false
    }
    
    # Ensure Key Vault is configured
    if (-not $script:useKeyVault -or -not $script:connectionEstablished) {
        $errorMessage = "Azure Key Vault is not configured or connection is not established."
        
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        
        throw $errorMessage
    }
    
    try {
        # Convert to SecureString if provided as string
        $secureValue = if ($SecretValue -is [string]) {
            ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
        }
        elseif ($SecretValue -is [System.Security.SecureString]) {
            $SecretValue
        }
        else {
            throw "SecretValue must be a string or SecureString."
        }
        
        # Store the secret
        Set-AzKeyVaultSecret -VaultName $script:keyVaultName -Name $SecretName -SecretValue $secureValue -ErrorAction Stop
        
        if ($loggingAvailable) {
            Write-Log -Message "Successfully stored secret in Key Vault: $SecretName" -Level INFO
        }
        else {
            Write-Verbose "Successfully stored secret in Key Vault: $SecretName"
        }
        
        return $true
    }
    catch {
        $errorMessage = "Failed to store secret in Key Vault: $_"
        
        if ($loggingAvailable) {
            Write-Log -Message $errorMessage -Level ERROR
        }
        else {
            Write-Error $errorMessage
        }
        
        throw $errorMessage
    }
}

# Export public functions
Export-ModuleMember -Function Initialize-SecureCredentialProvider
Export-ModuleMember -Function Get-SecureCredential
Export-ModuleMember -Function Set-SecureCredential
Export-ModuleMember -Function Get-AdminCredential
Export-ModuleMember -Function Get-SecretFromKeyVault
Export-ModuleMember -Function Set-SecretInKeyVault 





