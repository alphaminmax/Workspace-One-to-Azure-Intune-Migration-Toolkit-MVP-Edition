#Requires -Version 5.1

<#
.SYNOPSIS
    Security Foundation module for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    Provides core security functionality for the migration process including:
    - Secure credential handling
    - Encryption of sensitive data
    - Least privilege execution
    - Audit logging of security-relevant events
    - Secure API communications
    
.NOTES
    File Name      : SecurityFoundation.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

# Import required modules
if (-not (Get-Module -Name 'LoggingModule' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LoggingModule.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module LoggingModule.psm1 not found in $PSScriptRoot"
    }
}

# Import SecureCredentialProvider if available
$secureCredentialProviderPath = Join-Path -Path $PSScriptRoot -ChildPath 'SecureCredentialProvider.psm1'
$secureCredentialProviderAvailable = $false
if (Test-Path -Path $secureCredentialProviderPath) {
    try {
        Import-Module -Name $secureCredentialProviderPath -Force
        $secureCredentialProviderAvailable = $true
        Write-Log -Message "SecureCredentialProvider module loaded successfully" -Level INFO
    } catch {
        Write-Log -Message "Failed to load SecureCredentialProvider module: $_" -Level WARNING
    }
}

# Script level variables
$script:SecurityConfig = @{
    AuditLogPath = Join-Path -Path $env:TEMP -ChildPath "WS1Migration\SecurityAudit"
    EncryptionCertThumbprint = $null
    SecureKeyPath = Join-Path -Path $env:TEMP -ChildPath "WS1Migration\SecureKeys"
    ApiTimeoutSeconds = 30
    TlsVersion = "Tls12"
    RequireAdminForSensitiveOperations = $true
    UseWindowsCredentialManager = $true
    UseKeyVault = $false
    KeyVaultName = $null
    UseEnvFile = $false
    EnvFilePath = "./.env"
}

# Ensure audit log path exists
if (-not (Test-Path -Path $script:SecurityConfig.AuditLogPath)) {
    New-Item -Path $script:SecurityConfig.AuditLogPath -ItemType Directory -Force | Out-Null
}

# Ensure secure key path exists
if (-not (Test-Path -Path $script:SecurityConfig.SecureKeyPath)) {
    New-Item -Path $script:SecurityConfig.SecureKeyPath -ItemType Directory -Force | Out-Null
}

# Set TLS version
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Private Functions

function Write-SecurityAuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Critical')]
        [string]$Level = 'Information',
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'SecurityFoundation',
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalInfo = @{}
    )
    
    # Create audit entry
    $auditEntry = @{
        Timestamp = Get-Date -Format 'o'
        User = $env:USERNAME
        Computer = $env:COMPUTERNAME
        Process = $PID
        Level = $Level
        Component = $Component
        Message = $Message
        AdditionalInfo = $AdditionalInfo
    }
    
    # Convert to JSON
    $auditJson = ConvertTo-Json -InputObject $auditEntry -Depth 3 -Compress
    
    # Write to audit log
    $auditLogFile = Join-Path -Path $script:SecurityConfig.AuditLogPath -ChildPath "SecurityAudit_$(Get-Date -Format 'yyyyMMdd').log"
    $auditJson | Out-File -FilePath $auditLogFile -Append -Encoding utf8
    
    # Also send to regular log
    Write-Log -Message "[Security Audit] $Message" -Level $Level
}

function Get-EncryptionCertificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Thumbprint = $script:SecurityConfig.EncryptionCertThumbprint,
        
        [Parameter(Mandatory = $false)]
        [switch]$Create
    )
    
    # First try to find certificate by thumbprint if provided
    if ($Thumbprint) {
        $cert = Get-Item -Path "Cert:\CurrentUser\My\$Thumbprint" -ErrorAction SilentlyContinue
        if ($cert) {
            return $cert
        }
    }
    
    # Then try to find certificate by subject
    $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | 
        Where-Object { $_.Subject -like "*WS1MigrationEncryption*" } | 
        Sort-Object NotAfter -Descending | 
        Select-Object -First 1
    
    if ($cert) {
        # Update config with thumbprint
        $script:SecurityConfig.EncryptionCertThumbprint = $cert.Thumbprint
        return $cert
    }
    
    # Create if requested and not found
    if ($Create) {
        $cert = New-SelfSignedCertificate -Subject "CN=WS1MigrationEncryption" -KeyAlgorithm RSA `
            -KeyLength 2048 -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" `
            -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable `
            -KeyUsage KeyEncipherment,DataEncipherment,KeyAgreement `
            -NotAfter (Get-Date).AddYears(1)
        
        # Update config with thumbprint
        $script:SecurityConfig.EncryptionCertThumbprint = $cert.Thumbprint
        
        Write-SecurityAuditLog -Message "Created new encryption certificate $($cert.Thumbprint)" -Level Information
        return $cert
    }
    
    return $null
}

function Test-AdminPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SecureFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyName
    )
    
    $secureFileName = "$KeyName.secure"
    return Join-Path -Path $script:SecurityConfig.SecureKeyPath -ChildPath $secureFileName
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Configures security settings for the migration process.
    
.DESCRIPTION
    Sets up security configuration for the migration process including
    audit logging path, encryption certificate, and security requirements.
    
.PARAMETER AuditLogPath
    Path where security audit logs will be stored.
    
.PARAMETER EncryptionCertificateThumbprint
    Thumbprint of the certificate to use for encryption.
    
.PARAMETER SecureKeyPath
    Path where secure keys will be stored.
    
.PARAMETER ApiTimeoutSeconds
    Timeout for API calls in seconds.
    
.PARAMETER RequireAdminForSensitiveOperations
    Whether sensitive operations require admin privileges.
    
.PARAMETER UseWindowsCredentialManager
    Whether to use Windows Credential Manager for storing credentials.
    
.EXAMPLE
    Set-SecurityConfiguration -AuditLogPath "C:\Logs\Migration\Security" -RequireAdminForSensitiveOperations $false
    
.OUTPUTS
    None
#>
function Set-SecurityConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$AuditLogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$EncryptionCertificateThumbprint,
        
        [Parameter(Mandatory = $false)]
        [string]$SecureKeyPath,
        
        [Parameter(Mandatory = $false)]
        [int]$ApiTimeoutSeconds,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireAdminForSensitiveOperations,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseWindowsCredentialManager
    )
    
    # Update configuration with provided values
    if ($PSBoundParameters.ContainsKey('AuditLogPath')) {
        if (-not (Test-Path -Path $AuditLogPath)) {
            New-Item -Path $AuditLogPath -ItemType Directory -Force | Out-Null
        }
        $script:SecurityConfig.AuditLogPath = $AuditLogPath
    }
    
    if ($PSBoundParameters.ContainsKey('EncryptionCertificateThumbprint')) {
        $script:SecurityConfig.EncryptionCertThumbprint = $EncryptionCertificateThumbprint
    }
    
    if ($PSBoundParameters.ContainsKey('SecureKeyPath')) {
        if (-not (Test-Path -Path $SecureKeyPath)) {
            New-Item -Path $SecureKeyPath -ItemType Directory -Force | Out-Null
        }
        $script:SecurityConfig.SecureKeyPath = $SecureKeyPath
    }
    
    if ($PSBoundParameters.ContainsKey('ApiTimeoutSeconds')) {
        $script:SecurityConfig.ApiTimeoutSeconds = $ApiTimeoutSeconds
    }
    
    if ($PSBoundParameters.ContainsKey('RequireAdminForSensitiveOperations')) {
        $script:SecurityConfig.RequireAdminForSensitiveOperations = $RequireAdminForSensitiveOperations
    }
    
    if ($PSBoundParameters.ContainsKey('UseWindowsCredentialManager')) {
        $script:SecurityConfig.UseWindowsCredentialManager = $UseWindowsCredentialManager
    }
    
    Write-SecurityAuditLog -Message "Security configuration updated" -Level Information
}

<#
.SYNOPSIS
    Protects sensitive data using encryption.
    
.DESCRIPTION
    Encrypts sensitive data using a certificate and stores it securely.
    
.PARAMETER Data
    The data to encrypt.
    
.PARAMETER KeyName
    A unique identifier for this data.
    
.PARAMETER AsSecureString
    Whether the data is provided as a SecureString.
    
.EXAMPLE
    Protect-SensitiveData -Data "api_key_12345" -KeyName "ApiKey"
    
.EXAMPLE
    $securePassword = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
    Protect-SensitiveData -Data $securePassword -KeyName "AdminPassword" -AsSecureString
    
.OUTPUTS
    System.Boolean. Returns $true if encryption was successful.
#>
function Protect-SensitiveData {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$Data,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$KeyName,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsSecureString
    )
    
    try {
        # Get or create encryption certificate
        $cert = Get-EncryptionCertificate -Create
        if (-not $cert) {
            Write-SecurityAuditLog -Message "Failed to obtain encryption certificate" -Level Error
            return $false
        }
        
        # Convert data to secure string if not already
        $secureData = $Data
        if (-not $AsSecureString) {
            $secureData = ConvertTo-SecureString -String $Data -AsPlainText -Force
        }
        
        # Convert secure string to encrypted string
        $encryptedData = ConvertFrom-SecureString -SecureString $secureData -Key $cert.GetPublicKey().Key
        
        # Save to file
        $securePath = Get-SecureFilePath -KeyName $KeyName
        $encryptedData | Out-File -FilePath $securePath -Force
        
        Write-SecurityAuditLog -Message "Protected sensitive data for key: $KeyName" -Level Information
        return $true
    }
    catch {
        Write-SecurityAuditLog -Message "Failed to protect sensitive data: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Retrieves and decrypts protected sensitive data.
    
.DESCRIPTION
    Decrypts sensitive data that was previously protected using Protect-SensitiveData.
    
.PARAMETER KeyName
    The unique identifier used when the data was protected.
    
.PARAMETER AsPlainText
    Whether to return the data as plain text (string). Default is to return a SecureString.
    
.EXAMPLE
    $apiKey = Unprotect-SensitiveData -KeyName "ApiKey" -AsPlainText
    
.EXAMPLE
    $securePassword = Unprotect-SensitiveData -KeyName "AdminPassword"
    
.OUTPUTS
    System.Object. Returns either a SecureString or a String depending on AsPlainText.
#>
function Unprotect-SensitiveData {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$KeyName,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsPlainText
    )
    
    try {
        # Get encryption certificate
        $cert = Get-EncryptionCertificate
        if (-not $cert) {
            Write-SecurityAuditLog -Message "Failed to obtain encryption certificate" -Level Error
            return $null
        }
        
        # Get encrypted data
        $securePath = Get-SecureFilePath -KeyName $KeyName
        if (-not (Test-Path -Path $securePath)) {
            Write-SecurityAuditLog -Message "No protected data found for key: $KeyName" -Level Warning
            return $null
        }
        
        $encryptedData = Get-Content -Path $securePath
        
        # Decrypt data
        $secureData = ConvertTo-SecureString -String $encryptedData -Key $cert.GetPublicKey().Key
        
        # Return data in requested format
        if ($AsPlainText) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureData)
            $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            
            Write-SecurityAuditLog -Message "Retrieved sensitive data as plain text for key: $KeyName" -Level Information
            return $plainText
        }
        else {
            Write-SecurityAuditLog -Message "Retrieved sensitive data as secure string for key: $KeyName" -Level Information
            return $secureData
        }
    }
    catch {
        Write-SecurityAuditLog -Message "Failed to unprotect sensitive data: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
    Executes a script block with elevated privileges if required.
    
.DESCRIPTION
    Executes a script block, elevating privileges if necessary and allowed by security policy.
    
.PARAMETER ScriptBlock
    The script block to execute.
    
.PARAMETER ArgumentList
    Arguments to pass to the script block.
    
.PARAMETER ForceElevation
    Whether to always elevate, even if already running as admin.
    
.PARAMETER RequireAdmin
    Whether the operation requires administrative privileges.
    
.EXAMPLE
    Invoke-ElevatedOperation -ScriptBlock { Restart-Service -Name "SomeService" } -RequireAdmin
    
.OUTPUTS
    System.Object. Returns the result of the script block execution.
#>
function Invoke-ElevatedOperation {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @(),
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceElevation,
        
        [Parameter(Mandatory = $false)]
        [switch]$RequireAdmin
    )
    
    # Check if we're already running as admin
    $isAdmin = Test-AdminPrivilege
    
    # Determine if elevation is needed
    $needsElevation = $ForceElevation -or ($RequireAdmin -and -not $isAdmin)
    
    # Log the operation
    $additionalInfo = @{
        IsAlreadyAdmin = $isAdmin
        NeedsElevation = $needsElevation
        RequireAdmin = $RequireAdmin.IsPresent
        ForceElevation = $ForceElevation.IsPresent
    }
    
    Write-SecurityAuditLog -Message "Executing potentially privileged operation" -Level Information -AdditionalInfo $additionalInfo
    
    if ($needsElevation) {
        # Check security policy
        if ($RequireAdmin -and $script:SecurityConfig.RequireAdminForSensitiveOperations -and -not $isAdmin) {
            # Serialize the script block and arguments
            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptBlock.ToString()))
            $encodedArgs = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($ArgumentList | ConvertTo-Json -Compress)))
            
            # Create elevation parameters
            $params = @{
                FilePath = "powershell.exe"
                ArgumentList = "-NoProfile -EncodedCommand $encodedCommand -ExecutionPolicy Bypass"
                Verb = "RunAs"
                WindowStyle = "Hidden"
                Wait = $true
                PassThru = $true
            }
            
            # Start elevated process
            Write-SecurityAuditLog -Message "Elevating privileges for operation" -Level Information
            
            try {
                $elevatedProcess = Start-Process @params
                
                if ($elevatedProcess.ExitCode -ne 0) {
                    Write-SecurityAuditLog -Message "Elevated operation failed with exit code: $($elevatedProcess.ExitCode)" -Level Error
                    return $null
                }
                
                # Result would need to be passed back somehow, this is simplified
                return "Operation completed with elevated privileges"
            }
            catch {
                Write-SecurityAuditLog -Message "Failed to execute with elevated privileges: $_" -Level Error
                return $null
            }
        }
        else {
            Write-SecurityAuditLog -Message "Security policy prohibits elevation for sensitive operations" -Level Error
            return $null
        }
    }
    else {
        # Execute directly
        try {
            $result = & $ScriptBlock @ArgumentList
            Write-SecurityAuditLog -Message "Operation executed successfully without elevation" -Level Information
            return $result
        }
        catch {
            Write-SecurityAuditLog -Message "Operation failed: $_" -Level Error
            return $null
        }
    }
}

<#
.SYNOPSIS
    Stores credentials securely for later use.
    
.DESCRIPTION
    Saves credentials securely using Windows Credential Manager or encrypted files.
    
.PARAMETER Credential
    The credential to store.
    
.PARAMETER CredentialName
    A unique name to identify this credential.
    
.PARAMETER UseCredentialManager
    Whether to use Windows Credential Manager instead of encrypted files.
    
.EXAMPLE
    $cred = Get-Credential
    Set-SecureCredential -Credential $cred -CredentialName "AzureAPI"
    
.OUTPUTS
    System.Boolean. Returns $true if the credential was stored successfully.
#>
function Set-SecureCredential {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$CredentialName,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseCredentialManager = $script:SecurityConfig.UseWindowsCredentialManager
    )
    
    try {
        if ($UseCredentialManager) {
            # Use Windows Credential Manager
            $credManagerModule = Join-Path -Path $PSScriptRoot -ChildPath "CredentialManager.psm1"
            if (Test-Path -Path $credManagerModule) {
                Import-Module -Name $credManagerModule -Force
                
                # Store credential using external module
                if (Get-Command -Name "Save-Credential" -ErrorAction SilentlyContinue) {
                    Save-Credential -Credential $Credential -Target "WS1Migration_$CredentialName"
                    Write-SecurityAuditLog -Message "Stored credential '$CredentialName' in Windows Credential Manager" -Level Information
                    return $true
                }
                else {
                    # Fallback to file-based storage
                    Write-SecurityAuditLog -Message "CredentialManager module found but Save-Credential command not available. Falling back to file-based storage." -Level Warning
                }
            }
            else {
                # Fallback to file-based storage
                Write-SecurityAuditLog -Message "CredentialManager module not found. Falling back to file-based storage." -Level Warning
            }
        }
        
        # Store username and password separately using our encryption
        $usernameKey = "${CredentialName}_Username"
        $passwordKey = "${CredentialName}_Password"
        
        $usernameSuccess = Protect-SensitiveData -Data $Credential.UserName -KeyName $usernameKey
        $passwordSuccess = Protect-SensitiveData -Data $Credential.Password -KeyName $passwordKey -AsSecureString
        
        $success = $usernameSuccess -and $passwordSuccess
        if ($success) {
            Write-SecurityAuditLog -Message "Stored credential '$CredentialName' using file-based encryption" -Level Information
        }
        else {
            Write-SecurityAuditLog -Message "Failed to store credential '$CredentialName'" -Level Error
        }
        
        return $success
    }
    catch {
        Write-SecurityAuditLog -Message "Error storing credential: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Retrieves previously stored credentials.
    
.DESCRIPTION
    Gets credentials that were previously stored using Set-SecureCredential.
    
.PARAMETER CredentialName
    The unique name of the credential to retrieve.
    
.PARAMETER UseCredentialManager
    Whether to try retrieving from Windows Credential Manager.
    
.EXAMPLE
    $apiCred = Get-SecureCredential -CredentialName "AzureAPI"
    
.OUTPUTS
    System.Management.Automation.PSCredential. The retrieved credential.
#>
function Get-SecureCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$CredentialName,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseCredentialManager = $script:SecurityConfig.UseWindowsCredentialManager
    )
    
    try {
        if ($UseCredentialManager) {
            # Try Windows Credential Manager first
            $credManagerModule = Join-Path -Path $PSScriptRoot -ChildPath "CredentialManager.psm1"
            if (Test-Path -Path $credManagerModule) {
                Import-Module -Name $credManagerModule -Force
                
                # Get credential using external module
                if (Get-Command -Name "Get-StoredCredential" -ErrorAction SilentlyContinue) {
                    $credential = Get-StoredCredential -Target "WS1Migration_$CredentialName"
                    if ($credential) {
                        Write-SecurityAuditLog -Message "Retrieved credential '$CredentialName' from Windows Credential Manager" -Level Information
                        return $credential
                    }
                }
            }
        }
        
        # Fall back to file-based storage
        $usernameKey = "${CredentialName}_Username"
        $passwordKey = "${CredentialName}_Password"
        
        # Check if we have both username and password files
        $usernameFile = Get-SecureFilePath -KeyName $usernameKey
        $passwordFile = Get-SecureFilePath -KeyName $passwordKey
        
        if (-not (Test-Path -Path $usernameFile) -or -not (Test-Path -Path $passwordFile)) {
            Write-SecurityAuditLog -Message "Credential '$CredentialName' not found" -Level Warning
            return $null
        }
        
        # Get username and password
        $username = Unprotect-SensitiveData -KeyName $usernameKey -AsPlainText
        $password = Unprotect-SensitiveData -KeyName $passwordKey
        
        if (-not $username -or -not $password) {
            Write-SecurityAuditLog -Message "Failed to retrieve parts of credential '$CredentialName'" -Level Error
            return $null
        }
        
        # Create credential object
        $credential = New-Object System.Management.Automation.PSCredential ($username, $password)
        Write-SecurityAuditLog -Message "Retrieved credential '$CredentialName' from file-based storage" -Level Information
        
        return $credential
    }
    catch {
        Write-SecurityAuditLog -Message "Error retrieving credential: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
    Securely invokes a web request with proper TLS settings.
    
.DESCRIPTION
    Performs a web request with security best practices for TLS and timeouts.
    
.PARAMETER Uri
    The URI to send the request to.
    
.PARAMETER Method
    The HTTP method to use. Default is GET.
    
.PARAMETER Headers
    Headers to include in the request.
    
.PARAMETER Body
    The body of the request.
    
.PARAMETER ContentType
    The content type of the request.
    
.PARAMETER Credential
    Credentials to use for authentication.
    
.PARAMETER TimeoutSeconds
    Timeout for the request in seconds.
    
.EXAMPLE
    Invoke-SecureWebRequest -Uri "https://graph.microsoft.com/v1.0/users" -Credential $graphCred
    
.OUTPUTS
    System.Object. The response from the web request.
#>
function Invoke-SecureWebRequest {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Uri,
        
        [Parameter(Mandatory = $false)]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},
        
        [Parameter(Mandatory = $false)]
        [object]$Body = $null,
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json",
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = $script:SecurityConfig.ApiTimeoutSeconds
    )
    
    try {
        # Ensure we're using TLS 1.2 or higher
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Build parameters
        $params = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
            ContentType = $ContentType
            UseBasicParsing = $true
            TimeoutSec = $TimeoutSeconds
        }
        
        if ($Body) {
            if ($Body -is [string]) {
                $params.Body = $Body
            }
            else {
                $params.Body = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
            }
        }
        
        if ($Credential) {
            $params.Credential = $Credential
        }
        
        # Log request (but no credentials or sensitive data)
        $logParams = $params.Clone()
        if ($logParams.ContainsKey('Credential')) { $logParams.Remove('Credential') }
        if ($logParams.ContainsKey('Body')) { 
            # Redact potential sensitive content in body
            $logParams.Body = "*** REDACTED ***" 
        }
        
        $additionalInfo = @{
            Uri = $Uri
            Method = $Method
            TimeoutSeconds = $TimeoutSeconds
        }
        
        Write-SecurityAuditLog -Message "Making secure web request to $Uri" -Level Information -AdditionalInfo $additionalInfo
        
        # Make the request
        $response = Invoke-WebRequest @params
        
        # Log response (but not content)
        $responseInfo = @{
            StatusCode = $response.StatusCode
            StatusDescription = $response.StatusDescription
            ContentLength = $response.RawContentLength
        }
        
        Write-SecurityAuditLog -Message "Web request completed with status $($response.StatusCode)" -Level Information -AdditionalInfo $responseInfo
        
        return $response
    }
    catch {
        Write-SecurityAuditLog -Message "Web request failed: $_" -Level Error -AdditionalInfo @{ Uri = $Uri; Method = $Method }
        throw $_
    }
}

<#
.SYNOPSIS
    Writes a security-related event to the audit log.
    
.DESCRIPTION
    Records security-relevant events in the audit log for compliance and troubleshooting.
    
.PARAMETER Message
    The message to log.
    
.PARAMETER Level
    The severity level of the event.
    
.PARAMETER Component
    The component that generated the event.
    
.PARAMETER AdditionalInfo
    Additional information to log with the event.
    
.EXAMPLE
    Write-SecurityEvent -Message "User authentication failed" -Level Error -Component "Authentication"
    
.OUTPUTS
    None
#>
function Write-SecurityEvent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Critical')]
        [string]$Level = 'Information',
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'MigrationSecurity',
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalInfo = @{}
    )
    
    # Add security-relevant details to AdditionalInfo
    if (-not $AdditionalInfo.ContainsKey('User')) {
        $AdditionalInfo.User = $env:USERNAME
    }
    
    if (-not $AdditionalInfo.ContainsKey('ComputerName')) {
        $AdditionalInfo.ComputerName = $env:COMPUTERNAME
    }
    
    if (-not $AdditionalInfo.ContainsKey('ProcessId')) {
        $AdditionalInfo.ProcessId = $PID
    }
    
    # Log through our audit function
    Write-SecurityAuditLog -Message $Message -Level $Level -Component $Component -AdditionalInfo $AdditionalInfo
}

<#
.SYNOPSIS
    Tests if all security requirements are met.
    
.DESCRIPTION
    Validates that the system meets all security requirements for the migration.
    
.PARAMETER RequireAdmin
    Whether to require administrative privileges.
    
.PARAMETER CheckCertificates
    Whether to check for required certificates.
    
.PARAMETER CheckTls
    Whether to check TLS version.
    
.EXAMPLE
    Test-SecurityRequirements -RequireAdmin $true
    
.OUTPUTS
    System.Boolean. Returns $true if all requirements are met.
#>
function Test-SecurityRequirements {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$RequireAdmin = $script:SecurityConfig.RequireAdminForSensitiveOperations,
        
        [Parameter(Mandatory = $false)]
        [switch]$CheckCertificates,
        
        [Parameter(Mandatory = $false)]
        [switch]$CheckTls
    )
    
    $allPassed = $true
    $results = @{}
    
    # Check admin privileges if required
    if ($RequireAdmin) {
        $isAdmin = Test-AdminPrivilege
        $results.AdminPrivileges = $isAdmin
        $allPassed = $allPassed -and $isAdmin
        
        if (-not $isAdmin) {
            Write-SecurityAuditLog -Message "Security requirement failed: Administrative privileges required" -Level Warning
        }
    }
    
    # Check for encryption certificate
    if ($CheckCertificates) {
        $cert = Get-EncryptionCertificate
        $hasCert = $null -ne $cert
        $results.EncryptionCertificate = $hasCert
        $allPassed = $allPassed -and $hasCert
        
        if (-not $hasCert) {
            Write-SecurityAuditLog -Message "Security requirement failed: Encryption certificate not found" -Level Warning
        }
    }
    
    # Check TLS version
    if ($CheckTls) {
        $currentTls = [Net.ServicePointManager]::SecurityProtocol
        $hasTls12 = $currentTls -band [Net.SecurityProtocolType]::Tls12
        $results.Tls12Enabled = $hasTls12
        $allPassed = $allPassed -and $hasTls12
        
        if (-not $hasTls12) {
            Write-SecurityAuditLog -Message "Security requirement failed: TLS 1.2 not enabled" -Level Warning
            # Try to enable it
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        }
    }
    
    # Log overall result
    if ($allPassed) {
        Write-SecurityAuditLog -Message "All security requirements met" -Level Information -AdditionalInfo $results
    }
    else {
        Write-SecurityAuditLog -Message "Some security requirements not met" -Level Warning -AdditionalInfo $results
    }
    
    return $allPassed
}

<#
.SYNOPSIS
    Initializes the Security Foundation.
    
.DESCRIPTION
    Sets up the Security Foundation module and ensures all security requirements are met.
    
.PARAMETER CreateEncryptionCert
    Whether to create an encryption certificate if one doesn't exist.
    
.PARAMETER RequireAdmin
    Whether to require administrative privileges.
    
.EXAMPLE
    Initialize-SecurityFoundation -CreateEncryptionCert
    
.OUTPUTS
    System.Boolean. Returns $true if initialization was successful.
#>
function Initialize-SecurityFoundation {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$CreateEncryptionCert,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireAdmin = $script:SecurityConfig.RequireAdminForSensitiveOperations
    )
    
    Write-SecurityAuditLog -Message "Initializing Security Foundation" -Level Information
    
    try {
        # Ensure all paths exist
        if (-not (Test-Path -Path $script:SecurityConfig.AuditLogPath)) {
            New-Item -Path $script:SecurityConfig.AuditLogPath -ItemType Directory -Force | Out-Null
        }
        
        if (-not (Test-Path -Path $script:SecurityConfig.SecureKeyPath)) {
            New-Item -Path $script:SecurityConfig.SecureKeyPath -ItemType Directory -Force | Out-Null
        }
        
        # Check and get encryption certificate
        if ($CreateEncryptionCert) {
            $cert = Get-EncryptionCertificate -Create
            if (-not $cert) {
                Write-SecurityAuditLog -Message "Failed to create encryption certificate" -Level Error
                return $false
            }
        }
        
        # Set TLS version
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Check all security requirements
        $requirementsMet = Test-SecurityRequirements -RequireAdmin $RequireAdmin -CheckCertificates -CheckTls
        
        if (-not $requirementsMet) {
            Write-SecurityAuditLog -Message "Security Foundation initialization completed with warnings" -Level Warning
        }
        else {
            Write-SecurityAuditLog -Message "Security Foundation initialized successfully" -Level Information
        }
        
        return $true
    }
    catch {
        Write-SecurityAuditLog -Message "Failed to initialize Security Foundation: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Configures the module to use Azure Key Vault for credential storage.
    
.DESCRIPTION
    Enables Azure Key Vault integration for secure credential storage and retrieval
    using the SecureCredentialProvider module.
    
.PARAMETER KeyVaultName
    The name of the Azure Key Vault to use.
    
.PARAMETER EnvFilePath
    Optional path to a .env file containing environment variables.
    
.PARAMETER StandardAdminAccount
    Optional username of a standard admin account to use for privileged operations.
    
.EXAMPLE
    Enable-KeyVaultIntegration -KeyVaultName "MigrationKeyVault"
    
.EXAMPLE
    Enable-KeyVaultIntegration -KeyVaultName "MigrationKeyVault" -EnvFilePath "./.env" -StandardAdminAccount "MigrationAdmin"
    
.OUTPUTS
    System.Boolean. Returns $true if Key Vault integration was enabled successfully.
#>
function Enable-KeyVaultIntegration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [string]$EnvFilePath = "./.env",
        
        [Parameter(Mandatory = $false)]
        [string]$StandardAdminAccount
    )
    
    # Verify SecureCredentialProvider is available
    if (-not $secureCredentialProviderAvailable) {
        Write-SecurityAuditLog -Message "Cannot enable Key Vault integration - SecureCredentialProvider module not available" -Level Error
        return $false
    }
    
    try {
        # Update security configuration
        $script:SecurityConfig.UseKeyVault = $true
        $script:SecurityConfig.KeyVaultName = $KeyVaultName
        $script:SecurityConfig.EnvFilePath = $EnvFilePath
        
        # Initialize the SecureCredentialProvider
        $initParams = @{
            KeyVaultName = $KeyVaultName
            UseKeyVault = $true
        }
        
        if ([System.IO.File]::Exists($EnvFilePath)) {
            $initParams.EnvFilePath = $EnvFilePath
            $initParams.UseEnvFile = $true
            $script:SecurityConfig.UseEnvFile = $true
        }
        
        if (-not [string]::IsNullOrEmpty($StandardAdminAccount)) {
            $initParams.StandardAdminAccount = $StandardAdminAccount
        }
        
        $result = Initialize-SecureCredentialProvider @initParams
        
        if ($result) {
            Write-SecurityAuditLog -Message "Key Vault integration enabled successfully with vault: $KeyVaultName" -Level Information
            return $true
        } else {
            Write-SecurityAuditLog -Message "Failed to initialize SecureCredentialProvider" -Level Error
            return $false
        }
    }
    catch {
        Write-SecurityAuditLog -Message "Error enabling Key Vault integration: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Stores a credential securely in Azure Key Vault.
    
.DESCRIPTION
    Uses the SecureCredentialProvider to securely store credentials in Azure Key Vault.
    
.PARAMETER Name
    The name/identifier for the credential.
    
.PARAMETER Credential
    The PSCredential object containing the username and password.
    
.EXAMPLE
    $cred = Get-Credential
    Set-KeyVaultCredential -Name "ApiAccess" -Credential $cred
    
.OUTPUTS
    System.Boolean. Returns $true if the credential was stored successfully.
#>
function Set-KeyVaultCredential {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    # Verify Key Vault integration is enabled
    if (-not $script:SecurityConfig.UseKeyVault -or -not $secureCredentialProviderAvailable) {
        Write-SecurityAuditLog -Message "Key Vault integration not enabled" -Level Error
        return $false
    }
    
    try {
        $result = Set-SecureCredential -CredentialName $Name -Credential $Credential
        
        if ($result) {
            Write-SecurityAuditLog -Message "Credential '$Name' stored successfully in Key Vault" -Level Information
            return $true
        } else {
            Write-SecurityAuditLog -Message "Failed to store credential '$Name' in Key Vault" -Level Error
            return $false
        }
    }
    catch {
        Write-SecurityAuditLog -Message "Error storing credential in Key Vault: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Retrieves a credential from Azure Key Vault.
    
.DESCRIPTION
    Uses the SecureCredentialProvider to retrieve credentials from Azure Key Vault.
    
.PARAMETER Name
    The name/identifier of the credential to retrieve.
    
.PARAMETER AllowInteractive
    If set, allows prompting the user for credentials if not found in Key Vault.
    
.EXAMPLE
    $cred = Get-KeyVaultCredential -Name "ApiAccess"
    
.EXAMPLE
    $cred = Get-KeyVaultCredential -Name "ApiAccess" -AllowInteractive
    
.OUTPUTS
    System.Management.Automation.PSCredential. The retrieved credential.
#>
function Get-KeyVaultCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [switch]$AllowInteractive
    )
    
    # Verify Key Vault integration is enabled
    if (-not $script:SecurityConfig.UseKeyVault -or -not $secureCredentialProviderAvailable) {
        Write-SecurityAuditLog -Message "Key Vault integration not enabled" -Level Error
        return $null
    }
    
    try {
        $credential = Get-SecureCredential -CredentialName $Name -AllowInteractive:$AllowInteractive
        
        if ($credential) {
            Write-SecurityAuditLog -Message "Credential '$Name' retrieved successfully from Key Vault" -Level Information
            return $credential
        } else {
            Write-SecurityAuditLog -Message "Credential '$Name' not found in Key Vault" -Level Warning
            return $null
        }
    }
    catch {
        Write-SecurityAuditLog -Message "Error retrieving credential from Key Vault: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
    Stores a secret in Azure Key Vault.
    
.DESCRIPTION
    Uses the SecureCredentialProvider to store a secret in Azure Key Vault.
    
.PARAMETER Name
    The name of the secret.
    
.PARAMETER SecretValue
    The secret value to store, either as a string or SecureString.
    
.EXAMPLE
    Set-KeyVaultSecret -Name "ApiKey" -SecretValue "1234567890"
    
.EXAMPLE
    $secureValue = ConvertTo-SecureString "1234567890" -AsPlainText -Force
    Set-KeyVaultSecret -Name "ApiKey" -SecretValue $secureValue
    
.OUTPUTS
    System.Boolean. Returns $true if the secret was stored successfully.
#>
function Set-KeyVaultSecret {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [object]$SecretValue
    )
    
    # Verify Key Vault integration is enabled
    if (-not $script:SecurityConfig.UseKeyVault -or -not $secureCredentialProviderAvailable) {
        Write-SecurityAuditLog -Message "Key Vault integration not enabled" -Level Error
        return $false
    }
    
    try {
        $result = Set-SecretInKeyVault -SecretName $Name -SecretValue $SecretValue
        
        if ($result) {
            Write-SecurityAuditLog -Message "Secret '$Name' stored successfully in Key Vault" -Level Information
            return $true
        } else {
            Write-SecurityAuditLog -Message "Failed to store secret '$Name' in Key Vault" -Level Error
            return $false
        }
    }
    catch {
        Write-SecurityAuditLog -Message "Error storing secret in Key Vault: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Retrieves a secret from Azure Key Vault.
    
.DESCRIPTION
    Uses the SecureCredentialProvider to retrieve a secret from Azure Key Vault.
    
.PARAMETER Name
    The name of the secret to retrieve.
    
.PARAMETER AsPlainText
    If set, returns the secret as plain text. Otherwise, returns as SecureString.
    
.EXAMPLE
    $apiKey = Get-KeyVaultSecret -Name "ApiKey" -AsPlainText
    
.EXAMPLE
    $secureApiKey = Get-KeyVaultSecret -Name "ApiKey"
    
.OUTPUTS
    System.Object. Returns either a SecureString or a String depending on AsPlainText.
#>
function Get-KeyVaultSecret {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsPlainText
    )
    
    # Verify Key Vault integration is enabled
    if (-not $script:SecurityConfig.UseKeyVault -or -not $secureCredentialProviderAvailable) {
        Write-SecurityAuditLog -Message "Key Vault integration not enabled" -Level Error
        return $null
    }
    
    try {
        $secret = Get-SecretFromKeyVault -SecretName $Name -AsPlainText:$AsPlainText
        
        if ($null -ne $secret) {
            Write-SecurityAuditLog -Message "Secret '$Name' retrieved successfully from Key Vault" -Level Information
            return $secret
        } else {
            Write-SecurityAuditLog -Message "Secret '$Name' not found in Key Vault" -Level Warning
            return $null
        }
    }
    catch {
        Write-SecurityAuditLog -Message "Error retrieving secret from Key Vault: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
    Gets admin credentials, either from Key Vault or using temporary admin.
    
.DESCRIPTION
    Retrieves admin credentials for privileged operations, either using the standard
    admin account from Key Vault or creating a temporary admin account.
    
.PARAMETER AllowTemporaryAdmin
    If set and standard admin isn't available via Key Vault, allows creation of a temporary admin account.
    
.EXAMPLE
    $adminCred = Get-AdminAccountCredential -AllowTemporaryAdmin
    
.OUTPUTS
    System.Management.Automation.PSCredential. The admin credentials.
#>
function Get-AdminAccountCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$AllowTemporaryAdmin
    )
    
    # Check if Key Vault integration is enabled and SecureCredentialProvider is available
    if ($script:SecurityConfig.UseKeyVault -and $secureCredentialProviderAvailable) {
        try {
            $adminCred = Get-AdminCredential -AllowTemporaryAdmin:$AllowTemporaryAdmin
            
            if ($adminCred) {
                Write-SecurityAuditLog -Message "Admin credentials retrieved successfully" -Level Information
                return $adminCred
            }
        }
        catch {
            Write-SecurityAuditLog -Message "Error retrieving admin credentials from Key Vault: $_" -Level Warning
        }
    }
    
    # Fall back to legacy method if Key Vault integration failed or isn't enabled
    if ($AllowTemporaryAdmin) {
        Write-SecurityAuditLog -Message "Falling back to creating temporary admin account" -Level Information
        return New-TemporaryAdminAccount
    } else {
        Write-SecurityAuditLog -Message "Admin credentials not available and creation of temporary admin not allowed" -Level Error
        return $null
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Set-SecurityConfiguration, Protect-SensitiveData, Unprotect-SensitiveData,
    Invoke-ElevatedOperation, Set-SecureCredential, Get-SecureCredential, Invoke-SecureWebRequest,
    Write-SecurityEvent, Test-SecurityRequirements, Initialize-SecurityFoundation,
    Enable-KeyVaultIntegration, Set-KeyVaultCredential, Get-KeyVaultCredential,
    Set-KeyVaultSecret, Get-KeyVaultSecret, Get-AdminAccountCredential 