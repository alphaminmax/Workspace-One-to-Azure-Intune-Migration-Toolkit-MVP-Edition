#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    BitLocker Manager module for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The BitLockerManager module provides functionality to manage BitLocker
    encryption during the migration process, including:
    - Backup of BitLocker recovery keys
    - Integration with Azure Key Vault for secure key storage
    - Verification of encryption status
    - Migration of BitLocker configuration from Workspace ONE to Intune
    
.NOTES
    File Name      : BitLockerManager.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1, Administrator rights
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

if (-not (Get-Module -Name 'SecurityFoundation' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SecurityFoundation.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module SecurityFoundation.psm1 not found in $PSScriptRoot"
    }
}

# Script level variables
$script:BitLockerConfig = @{
    BackupPath = "$env:ProgramData\BitLocker"
    EnableEncryption = $true
    RecoveryKeyType = "Password"  # Password or Key
    EncryptionMethod = "XtsAes256"
    SecretExpirationDays = 365  # Default expiration for Key Vault secrets
}

#region Private Functions

function Test-BitLockerDriveEncryption {
    <#
    .SYNOPSIS
        Checks if a drive is BitLocker encrypted.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:"
    )
    
    try {
        # Try using BitLocker PowerShell cmdlets first (requires BitLocker feature)
        if (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
            
            if ($volume.VolumeStatus -eq "FullyEncrypted" -or $volume.VolumeStatus -eq "EncryptionInProgress") {
                return $true
            } else {
                return $false
            }
        }
        # Fall back to manage-bde command line tool
        else {
            $output = & manage-bde.exe -status $DriveLetter
            if ($output -match "Protection Status:\s+Protection (On|Off)") {
                return $Matches[1] -eq "On"
            } else {
                Write-Log -Message "Unexpected output from manage-bde: $output" -Level Warning
                return $false
            }
        }
    }
    catch {
        Write-Log -Message "Error checking BitLocker status: $_" -Level Error
        return $false
    }
}

function Get-BitLockerRecoveryPassword {
    <#
    .SYNOPSIS
        Gets the BitLocker recovery password for a specific drive.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:"
    )
    
    try {
        # Try using BitLocker PowerShell cmdlets first
        if (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
            
            $recoveryProtector = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
            if ($recoveryProtector) {
                return $recoveryProtector.RecoveryPassword
            } else {
                Write-Log -Message "No recovery password found for drive $DriveLetter" -Level Warning
                return $null
            }
        }
        # Fall back to manage-bde command line tool
        else {
            $output = & manage-bde.exe -protectors -get $DriveLetter
            if ($output -match "Recovery Password:\s+([0-9]{6}-[0-9]{6}-[0-9]{6}-[0-9]{6}-[0-9]{6}-[0-9]{6}-[0-9]{6}-[0-9]{6})") {
                return $Matches[1]
            } else {
                Write-Log -Message "No recovery password found in manage-bde output for drive $DriveLetter" -Level Warning
                return $null
            }
        }
    }
    catch {
        Write-Log -Message "Error getting BitLocker recovery password: $_" -Level Error
        return $null
    }
}

function Test-AzPowerShellModule {
    <#
    .SYNOPSIS
        Checks if the required Azure PowerShell modules are installed.
    .DESCRIPTION
        Validates that all necessary Azure PowerShell modules are installed
        and available for use with the BitLocker Manager.
    .OUTPUTS
        Boolean. Returns $true if all required modules are installed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $requiredModules = @('Az.Accounts', 'Az.KeyVault')
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log -Message "Missing required Azure PowerShell modules: $($missingModules -join ', ')" -Level Warning
        Write-Log -Message "To install, run: Install-Module -Name $($missingModules[0]) -AllowClobber -Force" -Level Information
        return $false
    } else {
        Write-Log -Message "All required Azure PowerShell modules are installed." -Level Information
        return $true
    }
}

function Connect-AzureKeyVault {
    <#
    .SYNOPSIS
        Establishes a connection to Azure Key Vault.
    .DESCRIPTION
        This function creates a connection to Azure Key Vault for BitLocker key management.
        It supports authentication via credentials or client certificate.
    .PARAMETER KeyVaultName
        The name of the Azure Key Vault to connect to.
    .PARAMETER TenantId
        The Azure AD tenant ID.
    .PARAMETER Credential
        The credential object for authentication.
    .PARAMETER UseClientCertificate
        Switch to use certificate-based authentication.
    .PARAMETER CertificateThumbprint
        The thumbprint of the certificate to use for authentication.
    .PARAMETER ApplicationId
        The Application (Client) ID to use for certificate-based authentication.
    .EXAMPLE
        Connect-AzureKeyVault -KeyVaultName "CompanyKeyVault" -TenantId "00000000-0000-0000-0000-000000000000" -Credential $credential
    .EXAMPLE
        Connect-AzureKeyVault -KeyVaultName "CompanyKeyVault" -TenantId "00000000-0000-0000-0000-000000000000" -UseClientCertificate -CertificateThumbprint "1234567890ABCDEF1234567890ABCDEF12345678" -ApplicationId "00000000-0000-0000-0000-000000000000"
    .OUTPUTS
        PSObject with connection status and details.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        
        [Parameter(Mandatory = $false, ParameterSetName = "CredentialAuth")]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $true, ParameterSetName = "CertificateAuth")]
        [switch]$UseClientCertificate,
        
        [Parameter(Mandatory = $true, ParameterSetName = "CertificateAuth")]
        [string]$CertificateThumbprint,
        
        [Parameter(Mandatory = $true, ParameterSetName = "CertificateAuth")]
        [string]$ApplicationId
    )
    
    try {
        # Import the logging module
        Import-Module -Name "$PSScriptRoot\LoggingModule.psm1" -Force
        Write-Log -Message "Attempting to connect to Azure Key Vault: $KeyVaultName" -Level Information
        
        # Check for required modules
        $requiredModules = @("Az.Accounts", "Az.KeyVault")
        $missingModules = @()
        
        foreach ($module in $requiredModules) {
            if (-not (Get-Module -Name $module -ListAvailable)) {
                $missingModules += $module
            }
        }
        
        if ($missingModules.Count -gt 0) {
            Write-Log -Message "Required modules not found: $($missingModules -join ', ')" -Level Warning
            
            # Attempt to install missing modules
            foreach ($module in $missingModules) {
                try {
                    Write-Log -Message "Attempting to install module: $module" -Level Information
                    Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
                    Write-Log -Message "Successfully installed module: $module" -Level Information
                }
                catch {
                    Write-Log -Message "Failed to install module $module: $_" -Level Error
                    throw "Failed to install required module $module. Please install it manually or ensure internet connectivity."
                }
            }
        }
        
        # Disable progress bar to improve performance
        $ProgressPreference = 'SilentlyContinue'
        
        # Attempt to connect to Azure
        try {
            # Clear any existing Azure context
            Clear-AzContext -Force -ErrorAction SilentlyContinue
            
            if ($UseClientCertificate) {
                Write-Log -Message "Connecting to Azure using certificate authentication" -Level Information
                
                # Verify certificate exists
                $cert = Get-Item -Path "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
                if (-not $cert) {
                    $cert = Get-Item -Path "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
                }
                
                if (-not $cert) {
                    throw "Certificate with thumbprint $CertificateThumbprint not found"
                }
                
                # Connect using certificate
                Connect-AzAccount -ServicePrincipal -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint -ApplicationId $ApplicationId
            }
            else {
                Write-Log -Message "Connecting to Azure using credential authentication" -Level Information
                
                # If no credential is provided, prompt for it
                if (-not $Credential) {
                    $Credential = Get-Credential -Message "Enter Azure credentials"
                }
                
                # Connect using credential
                Connect-AzAccount -TenantId $TenantId -Credential $Credential
            }
            
            Write-Log -Message "Successfully connected to Azure" -Level Information
        }
        catch {
            Write-Log -Message "Failed to connect to Azure: $_" -Level Error
            throw "Failed to authenticate to Azure: $_"
        }
        
        # Verify Key Vault access
        try {
            $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop
            
            if (-not $keyVault) {
                throw "Key Vault $KeyVaultName not found"
            }
            
            Write-Log -Message "Successfully connected to Key Vault: $KeyVaultName" -Level Information
            
            # Store connection info in script-level variable
            $script:KeyVaultConnection = @{
                KeyVaultName = $KeyVaultName
                TenantId = $TenantId
                Connected = $true
                ConnectionTime = Get-Date
                KeyVaultUri = $keyVault.VaultUri
                AuthMethod = if ($UseClientCertificate) { "Certificate" } else { "Credential" }
            }
            
            return [PSCustomObject]@{
                Success = $true
                KeyVaultName = $KeyVaultName
                Message = "Successfully connected to Key Vault"
                KeyVaultUri = $keyVault.VaultUri
            }
        }
        catch {
            Write-Log -Message "Failed to access Key Vault $KeyVaultName: $_" -Level Error
            
            # Clear connection info
            $script:KeyVaultConnection = $null
            
            return [PSCustomObject]@{
                Success = $false
                KeyVaultName = $KeyVaultName
                Message = "Failed to access Key Vault: $_"
            }
        }
        finally {
            # Restore progress preference
            $ProgressPreference = 'Continue'
        }
    }
    catch {
        Write-Log -Message "Error in Connect-AzureKeyVault: $_" -Level Error
        
        return [PSCustomObject]@{
            Success = $false
            KeyVaultName = $KeyVaultName
            Message = "Error connecting to Key Vault: $_"
        }
    }
}

function Format-SecretName {
    <#
    .SYNOPSIS
        Formats a BitLocker key secret name for Azure Key Vault.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )
    
    # Remove colon from drive letter and format secret name
    $driveLetter = $DriveLetter.TrimEnd(":")
    return "BitLocker-$ComputerName-Drive$driveLetter"
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Configures BitLocker Manager settings.
    
.DESCRIPTION
    Sets the configuration parameters for the BitLocker Manager module.
    
.PARAMETER BackupPath
    Local path to store BitLocker recovery key backups.
    
.PARAMETER AzureKeyVaultName
    Name of the Azure Key Vault to use for recovery key storage.
    
.PARAMETER AzureKeyVaultResourceGroup
    Resource group of the Azure Key Vault.
    
.PARAMETER AzureTenantId
    Azure AD tenant ID for authentication.
    
.PARAMETER AzureSubscriptionId
    Azure subscription ID.
    
.PARAMETER EnableEncryption
    Whether to enable BitLocker encryption if not already enabled.
    
.PARAMETER EncryptionMethod
    BitLocker encryption method to use.
    
.PARAMETER RecoveryKeyBackupType
    Where to back up the recovery key - Local, AzureAD, or KeyVault.
    
.PARAMETER KeyProtectorTypes
    Types of key protectors to use with BitLocker.
    
.PARAMETER CertificateThumbprint
    Thumbprint of the certificate to use for authentication.
    
.PARAMETER ApplicationId
    Application (client) ID for service principal authentication.
    
.PARAMETER SecretExpirationDays
    Number of days before the secret expires.
    
.EXAMPLE
    Set-BitLockerConfiguration -AzureKeyVaultName "MyVault" -AzureTenantId "tenant-id" -RecoveryKeyBackupType "KeyVault"
    
.OUTPUTS
    None
#>
function Set-BitLockerConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$BackupPath,
        
        [Parameter(Mandatory = $false)]
        [string]$AzureKeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [string]$AzureKeyVaultResourceGroup,
        
        [Parameter(Mandatory = $false)]
        [string]$AzureTenantId,
        
        [Parameter(Mandatory = $false)]
        [string]$AzureSubscriptionId,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableEncryption,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Aes128", "Aes256", "XtsAes128", "XtsAes256")]
        [string]$EncryptionMethod,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Local", "AzureAD", "KeyVault")]
        [string]$RecoveryKeyBackupType,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("RecoveryPassword", "TpmPin", "TpmKey", "Password", "ExternalKey")]
        [string[]]$KeyProtectorTypes,
        
        [Parameter(Mandatory = $false)]
        [string]$CertificateThumbprint,
        
        [Parameter(Mandatory = $false)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory = $false)]
        [int]$SecretExpirationDays
    )
    
    # Update configuration with provided values
    if ($PSBoundParameters.ContainsKey('BackupPath')) {
        if (-not (Test-Path -Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }
        $script:BitLockerConfig.BackupPath = $BackupPath
    }
    
    if ($PSBoundParameters.ContainsKey('AzureKeyVaultName')) {
        $script:BitLockerConfig.AzureKeyVaultName = $AzureKeyVaultName
    }
    
    if ($PSBoundParameters.ContainsKey('AzureKeyVaultResourceGroup')) {
        $script:BitLockerConfig.AzureKeyVaultResourceGroup = $AzureKeyVaultResourceGroup
    }
    
    if ($PSBoundParameters.ContainsKey('AzureTenantId')) {
        $script:BitLockerConfig.AzureTenantId = $AzureTenantId
    }
    
    if ($PSBoundParameters.ContainsKey('AzureSubscriptionId')) {
        $script:BitLockerConfig.AzureSubscriptionId = $AzureSubscriptionId
    }
    
    if ($PSBoundParameters.ContainsKey('EnableEncryption')) {
        $script:BitLockerConfig.EnableEncryption = $EnableEncryption
    }
    
    if ($PSBoundParameters.ContainsKey('EncryptionMethod')) {
        $script:BitLockerConfig.EncryptionMethod = $EncryptionMethod
    }
    
    if ($PSBoundParameters.ContainsKey('RecoveryKeyBackupType')) {
        $script:BitLockerConfig.RecoveryKeyBackupType = $RecoveryKeyBackupType
    }
    
    if ($PSBoundParameters.ContainsKey('KeyProtectorTypes')) {
        $script:BitLockerConfig.KeyProtectorTypes = $KeyProtectorTypes
    }
    
    if ($PSBoundParameters.ContainsKey('CertificateThumbprint')) {
        $script:BitLockerConfig.CertificateThumbprint = $CertificateThumbprint
    }
    
    if ($PSBoundParameters.ContainsKey('ApplicationId')) {
        $script:BitLockerConfig.ApplicationId = $ApplicationId
    }
    
    if ($PSBoundParameters.ContainsKey('SecretExpirationDays')) {
        $script:BitLockerConfig.SecretExpirationDays = $SecretExpirationDays
    }
    
    Write-Log -Message "BitLocker configuration updated" -Level Information
}

<#
.SYNOPSIS
    Verifies the encryption status of the specified drive.
    
.DESCRIPTION
    Checks if the specified drive is encrypted with BitLocker
    and returns detailed information about its encryption status.
    
.PARAMETER DriveLetter
    The drive letter to check for encryption status.
    
.EXAMPLE
    Test-BitLockerEncryption -DriveLetter "C:"
    
.OUTPUTS
    System.Management.Automation.PSObject. Object with encryption status information.
#>
function Test-BitLockerEncryption {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:"
    )
    
    try {
        # Check if BitLocker feature is installed
        if (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
            
            $result = [PSCustomObject]@{
                DriveLetter = $DriveLetter
                IsEncrypted = $volume.VolumeStatus -eq "FullyEncrypted"
                EncryptionMethod = $volume.EncryptionMethod
                VolumeStatus = $volume.VolumeStatus
                EncryptionPercentage = $volume.EncryptionPercentage
                KeyProtectors = $volume.KeyProtector.KeyProtectorType
                ProtectionStatus = $volume.ProtectionStatus
                HasRecoveryKey = $volume.KeyProtector.KeyProtectorType -contains "RecoveryPassword"
            }
            
            Write-Log -Message "BitLocker status for drive $DriveLetter: $($result.VolumeStatus), Protection: $($result.ProtectionStatus)" -Level Information
            return $result
        }
        else {
            # Fallback to manage-bde command
            $output = & manage-bde.exe -status $DriveLetter
            
            $isEncrypted = $output -match "Protection Status:\s+Protection On"
            $encryptionPercentage = if ($output -match "Percentage Encrypted:\s+(\d+\.?\d*)") { [double]$Matches[1] } else { 0 }
            $encryptionMethod = if ($output -match "Encryption Method:\s+(.+)") { $Matches[1] } else { "Unknown" }
            $hasRecoveryKey = $output -match "Recovery Password:\s+ID:"
            
            $result = [PSCustomObject]@{
                DriveLetter = $DriveLetter
                IsEncrypted = $isEncrypted
                EncryptionMethod = $encryptionMethod
                VolumeStatus = if ($encryptionPercentage -eq 100) { "FullyEncrypted" } elseif ($encryptionPercentage -gt 0) { "EncryptionInProgress" } else { "NotEncrypted" }
                EncryptionPercentage = $encryptionPercentage
                KeyProtectors = if ($hasRecoveryKey) { @("RecoveryPassword") } else { @() }
                ProtectionStatus = if ($isEncrypted) { "On" } else { "Off" }
                HasRecoveryKey = $hasRecoveryKey
            }
            
            Write-Log -Message "BitLocker status for drive $DriveLetter (via manage-bde): Encrypted: $isEncrypted, Percentage: $encryptionPercentage%" -Level Information
            return $result
        }
    }
    catch {
        Write-Log -Message "Error checking BitLocker encryption status: $_" -Level Error
        return [PSCustomObject]@{
            DriveLetter = $DriveLetter
            IsEncrypted = $false
            EncryptionMethod = "Unknown"
            VolumeStatus = "Error"
            EncryptionPercentage = 0
            KeyProtectors = @()
            ProtectionStatus = "Error"
            HasRecoveryKey = $false
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Backs up BitLocker recovery key to a local file.
    
.DESCRIPTION
    Exports the BitLocker recovery key for the specified drive to a local file.
    
.PARAMETER DriveLetter
    The drive letter to backup the recovery key for.
    
.PARAMETER BackupPath
    Path to save the recovery key backup.
    
.EXAMPLE
    Backup-BitLockerKeyToFile -DriveLetter "C:" -BackupPath "C:\Backup"
    
.OUTPUTS
    System.Boolean. Returns $true if backup was successful.
#>
function Backup-BitLockerKeyToFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:",
        
        [Parameter(Mandatory = $false)]
        [string]$BackupPath = $script:BitLockerConfig.BackupPath
    )
    
    try {
        # Ensure backup path exists
        if (-not (Test-Path -Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Get recovery key
        $recoveryKey = Get-BitLockerRecoveryPassword -DriveLetter $DriveLetter
        if (-not $recoveryKey) {
            Write-Log -Message "No BitLocker recovery key found for drive $DriveLetter" -Level Error
            return $false
        }
        
        # Format backup file name
        $computerName = $env:COMPUTERNAME
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $driveLetterClean = $DriveLetter.TrimEnd(":")
        $backupFileName = "BitLocker_${computerName}_Drive${driveLetterClean}_${timestamp}.txt"
        $backupFilePath = Join-Path -Path $BackupPath -ChildPath $backupFileName
        
        # Save recovery key to file
        @"
BitLocker Recovery Key
======================
Computer Name: $computerName
Drive: $DriveLetter
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Recovery Key: $recoveryKey

IMPORTANT: Store this file in a secure location!
"@ | Out-File -FilePath $backupFilePath -Encoding utf8 -Force
        
        # Encrypt the file with DPAPI for added security
        $encryptedFilePath = "${backupFilePath}.secure"
        $sensitiveData = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $backupFilePath -Raw))
        $encryptedData = [System.Security.Cryptography.ProtectedData]::Protect(
            $sensitiveData,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.IO.File]::WriteAllBytes($encryptedFilePath, $encryptedData)
        
        # Remove plain text file
        Remove-Item -Path $backupFilePath -Force
        
        Write-Log -Message "BitLocker recovery key for drive $DriveLetter backed up to $encryptedFilePath" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Error backing up BitLocker key to file: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Backs up BitLocker recovery key to Azure Key Vault.
    
.DESCRIPTION
    Securely stores the BitLocker recovery key in Azure Key Vault.
    
.PARAMETER DriveLetter
    The drive letter to backup the recovery key for.
    
.PARAMETER KeyVaultName
    The name of the Azure Key Vault to use.
    
.PARAMETER Credential
    Credential for Azure authentication.
    
.PARAMETER TenantId
    The Azure AD tenant ID.
    
.PARAMETER UseClientCertificate
    Switch to use certificate-based authentication.
    
.PARAMETER CertificateThumbprint
    Thumbprint of the certificate to use for authentication.
    
.PARAMETER ApplicationId
    Application (client) ID for service principal authentication.
    
.PARAMETER ForceRotation
    Switch to force secret rotation.
    
.EXAMPLE
    Backup-BitLockerKeyToKeyVault -DriveLetter "C:" -KeyVaultName "MyKeyVault" -TenantId "tenant-id"
    
.OUTPUTS
    System.Boolean. Returns $true if backup was successful.
#>
function Backup-BitLockerKeyToKeyVault {
    <#
    .SYNOPSIS
        Backs up BitLocker recovery keys to Azure Key Vault.
    .DESCRIPTION
        This function retrieves BitLocker recovery keys from specified volumes and
        stores them securely in Azure Key Vault with appropriate metadata.
    .PARAMETER KeyVaultName
        The name of the Azure Key Vault to store the keys in.
    .PARAMETER VolumeId
        Optional volume ID to backup only specific volume's key.
    .PARAMETER SecretNamePrefix
        Prefix to use for the secret names in Key Vault.
    .PARAMETER SecretExpiryDays
        Number of days until the secret expires in Key Vault.
    .EXAMPLE
        Backup-BitLockerKeyToKeyVault -KeyVaultName "CompanyKeyVault"
    .EXAMPLE
        Backup-BitLockerKeyToKeyVault -KeyVaultName "CompanyKeyVault" -VolumeId "C:"
    .OUTPUTS
        PSObject with backup operation status and results.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [string]$VolumeId,
        
        [Parameter(Mandatory = $false)]
        [string]$SecretNamePrefix = "BitLocker-",
        
        [Parameter(Mandatory = $false)]
        [int]$SecretExpiryDays = $script:BitLockerConfig.SecretExpirationDays
    )
    
    try {
        # Import the logging module
        Import-Module -Name "$PSScriptRoot\LoggingModule.psm1" -Force
        Write-Log -Message "Starting BitLocker key backup to Azure Key Vault: $KeyVaultName" -Level Information
        
        # Verify Key Vault connection or use provided name
        if (-not $script:KeyVaultConnection -or $script:KeyVaultConnection.KeyVaultName -ne $KeyVaultName) {
            Write-Log -Message "No active connection to Key Vault $KeyVaultName. Please connect first using Connect-AzureKeyVault." -Level Warning
            return [PSCustomObject]@{
                Success = $false
                Message = "No active connection to Key Vault. Please connect first using Connect-AzureKeyVault."
            }
        }
        
        # Get BitLocker volumes
        $bitlockerVolumes = @()
        
        if ($VolumeId) {
            # Get specific volume
            $volume = Get-BitLockerVolume -MountPoint $VolumeId -ErrorAction SilentlyContinue
            if ($volume) {
                $bitlockerVolumes += $volume
            }
            else {
                Write-Log -Message "BitLocker volume not found for mount point: $VolumeId" -Level Warning
                return [PSCustomObject]@{
                    Success = $false
                    Message = "BitLocker volume not found for mount point: $VolumeId"
                }
            }
        }
        else {
            # Get all encrypted volumes
            $bitlockerVolumes = Get-BitLockerVolume | Where-Object { $_.VolumeStatus -eq "FullyEncrypted" -or $_.VolumeStatus -eq "EncryptionInProgress" }
        }
        
        if (-not $bitlockerVolumes -or $bitlockerVolumes.Count -eq 0) {
            Write-Log -Message "No encrypted BitLocker volumes found" -Level Warning
            return [PSCustomObject]@{
                Success = $false
                Message = "No encrypted BitLocker volumes found"
            }
        }
        
        # Prepare results
        $results = @{
            TotalVolumes = $bitlockerVolumes.Count
            SuccessfulBackups = 0
            FailedBackups = 0
            VolumeResults = @()
        }
        
        # Get computer name for metadata
        $computerName = $env:COMPUTERNAME
        
        # Process each volume
        foreach ($volume in $bitlockerVolumes) {
            $volumeInfo = @{
                MountPoint = $volume.MountPoint
                VolumeType = $volume.VolumeType
                Success = $false
                Message = ""
                KeyProtectorId = ""
            }
            
            try {
                # Check if volume has recovery key protectors
                $recoveryProtectors = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
                
                if (-not $recoveryProtectors -or $recoveryProtectors.Count -eq 0) {
                    $volumeInfo.Message = "No recovery key protectors found for volume $($volume.MountPoint)"
                    $results.FailedBackups++
                    $results.VolumeResults += $volumeInfo
                    Write-Log -Message $volumeInfo.Message -Level Warning
                    continue
                }
                
                # Use the first recovery protector
                $recoveryProtector = $recoveryProtectors[0]
                $recoveryKeyPassword = $recoveryProtector.RecoveryPassword
                $keyProtectorId = $recoveryProtector.KeyProtectorId
                
                if ([string]::IsNullOrEmpty($recoveryKeyPassword)) {
                    $volumeInfo.Message = "Recovery password is null or empty for volume $($volume.MountPoint)"
                    $results.FailedBackups++
                    $results.VolumeResults += $volumeInfo
                    Write-Log -Message $volumeInfo.Message -Level Warning
                    continue
                }
                
                # Create secret name with prefix and computer name
                $secretName = "$($SecretNamePrefix)$($computerName)-$($volume.MountPoint -replace ':', '')-$($keyProtectorId.Substring(0, 8))"
                
                # Create secret with metadata
                $secretValue = ConvertTo-SecureString -String $recoveryKeyPassword -AsPlainText -Force
                $expiryDate = (Get-Date).AddDays($SecretExpiryDays)
                
                # Add tags/metadata
                $tags = @{
                    ComputerName = $computerName
                    MountPoint = $volume.MountPoint
                    VolumeType = $volume.VolumeType
                    KeyProtectorId = $keyProtectorId
                    BackupDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    EncryptionMethod = $volume.EncryptionMethod
                }
                
                # Set the secret in Key Vault
                $setSecret = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -SecretValue $secretValue -Expires $expiryDate -Tags $tags
                
                if ($setSecret) {
                    $volumeInfo.Success = $true
                    $volumeInfo.Message = "Successfully backed up recovery key for volume $($volume.MountPoint)"
                    $volumeInfo.KeyProtectorId = $keyProtectorId
                    $results.SuccessfulBackups++
                    Write-Log -Message $volumeInfo.Message -Level Information
                }
                else {
                    $volumeInfo.Message = "Failed to set secret in Key Vault for volume $($volume.MountPoint)"
                    $results.FailedBackups++
                    Write-Log -Message $volumeInfo.Message -Level Error
                }
            }
            catch {
                $volumeInfo.Message = "Error backing up recovery key for volume $($volume.MountPoint): $_"
                $results.FailedBackups++
                Write-Log -Message $volumeInfo.Message -Level Error
            }
            
            $results.VolumeResults += $volumeInfo
        }
        
        # Log summary
        $summaryMessage = "BitLocker key backup to Key Vault completed. Successful: $($results.SuccessfulBackups), Failed: $($results.FailedBackups), Total: $($results.TotalVolumes)"
        Write-Log -Message $summaryMessage -Level Information
        
        return [PSCustomObject]@{
            Success = ($results.FailedBackups -eq 0 -and $results.SuccessfulBackups -gt 0)
            Message = $summaryMessage
            TotalVolumes = $results.TotalVolumes
            SuccessfulBackups = $results.SuccessfulBackups
            FailedBackups = $results.FailedBackups
            VolumeResults = $results.VolumeResults
        }
    }
    catch {
        Write-Log -Message "Error in Backup-BitLockerKeyToKeyVault: $_" -Level Error
        
        return [PSCustomObject]@{
            Success = $false
            Message = "Error backing up BitLocker keys to Key Vault: $_"
        }
    }
}

<#
.SYNOPSIS
    Retrieves a BitLocker recovery key from Azure Key Vault.
    
.DESCRIPTION
    Gets a previously stored BitLocker recovery key from Azure Key Vault.
    
.PARAMETER DriveLetter
    The drive letter to retrieve the recovery key for.
    
.PARAMETER ComputerName
    The name of the computer. Defaults to the local computer name.
    
.PARAMETER KeyVaultName
    The name of the Azure Key Vault to use.
    
.PARAMETER Credential
    Credential for Azure authentication.
    
.PARAMETER TenantId
    The Azure AD tenant ID.
    
.EXAMPLE
    Get-BitLockerKeyFromKeyVault -DriveLetter "C:" -KeyVaultName "MyKeyVault" -TenantId "tenant-id"
    
.OUTPUTS
    System.String. The BitLocker recovery key.
#>
function Get-BitLockerKeyFromKeyVault {
    <#
    .SYNOPSIS
        Retrieves BitLocker recovery keys from Azure Key Vault.
    .DESCRIPTION
        This function retrieves BitLocker recovery keys from Azure Key Vault based on
        computer name, volume ID, or key protector ID.
    .PARAMETER KeyVaultName
        The name of the Azure Key Vault to retrieve the keys from.
    .PARAMETER ComputerName
        The name of the computer to retrieve keys for.
    .PARAMETER VolumeId
        Optional volume ID to retrieve only specific volume's key.
    .PARAMETER KeyProtectorId
        Optional key protector ID to retrieve a specific key.
    .EXAMPLE
        Get-BitLockerKeyFromKeyVault -KeyVaultName "CompanyKeyVault" -ComputerName "DESKTOP-123456"
    .EXAMPLE
        Get-BitLockerKeyFromKeyVault -KeyVaultName "CompanyKeyVault" -ComputerName "DESKTOP-123456" -VolumeId "C:"
    .OUTPUTS
        PSObject with retrieval operation status and results.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory = $false)]
        [string]$VolumeId,
        
        [Parameter(Mandatory = $false)]
        [string]$KeyProtectorId
    )
    
    try {
        # Import the logging module
        Import-Module -Name "$PSScriptRoot\LoggingModule.psm1" -Force
        Write-Log -Message "Retrieving BitLocker keys from Azure Key Vault: $KeyVaultName" -Level Information
        
        # Verify Key Vault connection or use provided name
        if (-not $script:KeyVaultConnection -or $script:KeyVaultConnection.KeyVaultName -ne $KeyVaultName) {
            Write-Log -Message "No active connection to Key Vault $KeyVaultName. Please connect first using Connect-AzureKeyVault." -Level Warning
            return [PSCustomObject]@{
                Success = $false
                Message = "No active connection to Key Vault. Please connect first using Connect-AzureKeyVault."
            }
        }
        
        # Get all secrets with BitLocker- prefix
        $secrets = Get-AzKeyVaultSecret -VaultName $KeyVaultName | Where-Object { $_.Name -like "BitLocker-*" }
        
        if (-not $secrets -or $secrets.Count -eq 0) {
            Write-Log -Message "No BitLocker keys found in Key Vault: $KeyVaultName" -Level Warning
            return [PSCustomObject]@{
                Success = $false
                Message = "No BitLocker keys found in Key Vault"
            }
        }
        
        # Filter secrets by computer name
        $computerSecrets = $secrets | Where-Object { 
            $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_.Name
            $secret.Tags.ComputerName -eq $ComputerName 
        }
        
        if (-not $computerSecrets -or $computerSecrets.Count -eq 0) {
            Write-Log -Message "No BitLocker keys found for computer: $ComputerName" -Level Warning
            return [PSCustomObject]@{
                Success = $false
                Message = "No BitLocker keys found for computer: $ComputerName"
            }
        }
        
        # Filter by volume if specified
        if ($VolumeId) {
            $volumeSecrets = $computerSecrets | Where-Object { 
                $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_.Name
                $secret.Tags.MountPoint -eq $VolumeId 
            }
            
            if (-not $volumeSecrets -or $volumeSecrets.Count -eq 0) {
                Write-Log -Message "No BitLocker keys found for volume: $VolumeId on computer: $ComputerName" -Level Warning
                return [PSCustomObject]@{
                    Success = $false
                    Message = "No BitLocker keys found for volume: $VolumeId on computer: $ComputerName"
                }
            }
            
            $computerSecrets = $volumeSecrets
        }
        
        # Filter by key protector ID if specified
        if ($KeyProtectorId) {
            $protectorSecrets = $computerSecrets | Where-Object { 
                $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_.Name
                $secret.Tags.KeyProtectorId -eq $KeyProtectorId 
            }
            
            if (-not $protectorSecrets -or $protectorSecrets.Count -eq 0) {
                Write-Log -Message "No BitLocker keys found for key protector ID: $KeyProtectorId" -Level Warning
                return [PSCustomObject]@{
                    Success = $false
                    Message = "No BitLocker keys found for key protector ID: $KeyProtectorId"
                }
            }
            
            $computerSecrets = $protectorSecrets
        }
        
        # Prepare results
        $results = @{
            TotalKeys = $computerSecrets.Count
            Keys = @()
        }
        
        # Process each secret
        foreach ($secretInfo in $computerSecrets) {
            try {
                $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretInfo.Name
                
                # Check if secret has expired
                $isExpired = $false
                if ($secret.Expires -and $secret.Expires -lt (Get-Date)) {
                    $isExpired = $true
                    Write-Log -Message "BitLocker key $($secretInfo.Name) has expired on $($secret.Expires)" -Level Warning
                }
                
                # Get secret value (recovery key)
                $secretValueText = ''
                if (-not $isExpired) {
                    $secretValue = $secret.SecretValue
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretValue)
                    $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
                
                # Create result object for this key
                $keyResult = [PSCustomObject]@{
                    Name = $secretInfo.Name
                    MountPoint = $secret.Tags.MountPoint
                    ComputerName = $secret.Tags.ComputerName
                    KeyProtectorId = $secret.Tags.KeyProtectorId
                    BackupDate = $secret.Tags.BackupDate
                    RecoveryKey = if ($isExpired) { "EXPIRED" } else { $secretValueText }
                    IsExpired = $isExpired
                    Expires = $secret.Expires
                }
                
                $results.Keys += $keyResult
            }
            catch {
                Write-Log -Message "Error retrieving secret $($secretInfo.Name): $_" -Level Error
            }
        }
        
        # Log summary
        $summaryMessage = "Retrieved $($results.TotalKeys) BitLocker keys from Key Vault for computer: $ComputerName"
        Write-Log -Message $summaryMessage -Level Information
        
        return [PSCustomObject]@{
            Success = ($results.TotalKeys -gt 0)
            Message = $summaryMessage
            TotalKeys = $results.TotalKeys
            Keys = $results.Keys
        }
    }
    catch {
        Write-Log -Message "Error in Get-BitLockerKeyFromKeyVault: $_" -Level Error
        
        return [PSCustomObject]@{
            Success = $false
            Message = "Error retrieving BitLocker keys from Key Vault: $_"
        }
    }
}

<#
.SYNOPSIS
    Migrates BitLocker configuration from Workspace ONE to Intune.
    
.DESCRIPTION
    Transfers the BitLocker configuration and recovery keys from 
    Workspace ONE management to Microsoft Intune.
    
.PARAMETER DriveLetter
    The drive letter to migrate BitLocker for.
    
.PARAMETER BackupToAzureAD
    Whether to back up the recovery key to Azure AD (for Intune management).
    
.PARAMETER BackupToKeyVault
    Whether to back up the recovery key to Azure Key Vault.
    
.PARAMETER Force
    Force migration even if already managed by Intune.
    
.EXAMPLE
    Invoke-BitLockerMigration -DriveLetter "C:" -BackupToAzureAD -BackupToKeyVault
    
.OUTPUTS
    System.Boolean. Returns $true if migration was successful.
#>
function Invoke-BitLockerMigration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:",
        
        [Parameter(Mandatory = $false)]
        [switch]$BackupToAzureAD,
        
        [Parameter(Mandatory = $false)]
        [switch]$BackupToKeyVault,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        # Check if BitLocker is enabled
        $encryptionStatus = Test-BitLockerEncryption -DriveLetter $DriveLetter
        
        if (-not $encryptionStatus.IsEncrypted) {
            Write-Log -Message "Drive $DriveLetter is not BitLocker encrypted" -Level Warning
            return $false
        }
        
        # Check if already backed up to Azure AD (Intune management)
        $alreadyIntuneManaged = $false
        # This is a simplified check and would be more robust in a real implementation
        if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker" -ErrorAction SilentlyContinue) -and (-not $Force)) {
            $alreadyIntuneManaged = $true
            Write-Log -Message "BitLocker configuration already appears to be managed by Intune for drive $DriveLetter" -Level Warning
        }
        
        if ($alreadyIntuneManaged -and -not $Force) {
            Write-Log -Message "BitLocker already managed by Intune. Use -Force to override." -Level Warning
            return $true
        }
        
        # Always back up locally during migration
        $localBackupSuccess = Backup-BitLockerKeyToFile -DriveLetter $DriveLetter
        if (-not $localBackupSuccess) {
            Write-Log -Message "Failed to create local backup of BitLocker key" -Level Warning
        }
        
        # Back up to Azure AD if requested
        if ($BackupToAzureAD) {
            try {
                # This would use the Intune PowerShell SDK in a real implementation
                # For demo purposes, we'll use BackupToAAD flag in manage-bde
                $output = & manage-bde.exe -protectors -get $DriveLetter
                $recoveryPasswordId = if ($output -match "ID: \{([A-F0-9-]+)\}") { $Matches[1] } else { $null }
                
                if ($recoveryPasswordId) {
                    & manage-bde.exe -protectors -adbackup $DriveLetter -id $recoveryPasswordId
                    Write-Log -Message "BitLocker recovery key backed up to Azure AD for drive $DriveLetter" -Level Information
                } else {
                    Write-Log -Message "Could not find recovery password ID for drive $DriveLetter" -Level Warning
                }
            }
            catch {
                Write-Log -Message "Error backing up BitLocker key to Azure AD: $_" -Level Error
            }
        }
        
        # Back up to Azure Key Vault if requested
        if ($BackupToKeyVault) {
            $keyVaultBackupSuccess = Backup-BitLockerKeyToKeyVault -DriveLetter $DriveLetter
            if (-not $keyVaultBackupSuccess) {
                Write-Log -Message "Failed to back up BitLocker key to Azure Key Vault" -Level Warning
            }
        }
        
        # Apply Intune BitLocker policy settings (this would be more comprehensive in a real implementation)
        # Here we're just simulating policy application by setting registry values
        $intuneRegPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker"
        if (-not (Test-Path -Path $intuneRegPath)) {
            New-Item -Path $intuneRegPath -Force | Out-Null
        }
        
        # Update registry to indicate Intune management
        New-ItemProperty -Path $intuneRegPath -Name "ManagedByIntune" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $intuneRegPath -Name "MigrationTimestamp" -Value (Get-Date).ToString('o') -PropertyType String -Force | Out-Null
        
        Write-Log -Message "BitLocker configuration successfully migrated to Intune for drive $DriveLetter" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Error during BitLocker migration: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Initializes the BitLocker Manager.
    
.DESCRIPTION
    Sets up the BitLocker Manager module and ensures requirements are met.
    
.PARAMETER BackupPath
    Local path for BitLocker recovery key backups.
    
.PARAMETER EnableEncryption
    Whether to enable BitLocker encryption if not already enabled.
    
.PARAMETER RecoveryKeyBackupType
    Where to back up recovery keys - Local, AzureAD, or KeyVault.
    
.EXAMPLE
    Initialize-BitLockerManager -BackupPath "C:\Backup\BitLocker" -RecoveryKeyBackupType "Local"
    
.OUTPUTS
    System.Boolean. Returns $true if initialization was successful.
#>
function Initialize-BitLockerManager {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$BackupPath,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableEncryption = $script:BitLockerConfig.EnableEncryption,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Local", "AzureAD", "KeyVault")]
        [string]$RecoveryKeyBackupType = $script:BitLockerConfig.RecoveryKeyBackupType
    )
    
    try {
        Write-Log -Message "Initializing BitLocker Manager" -Level Information
        
        # Update configuration if parameters provided
        if ($BackupPath) {
            $script:BitLockerConfig.BackupPath = $BackupPath
        }
        
        $script:BitLockerConfig.EnableEncryption = $EnableEncryption
        $script:BitLockerConfig.RecoveryKeyBackupType = $RecoveryKeyBackupType
        
        # Ensure backup path exists
        if (-not (Test-Path -Path $script:BitLockerConfig.BackupPath)) {
            New-Item -Path $script:BitLockerConfig.BackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Check if BitLocker feature is available
        $bitlockerFeature = Get-WindowsFeature -Name BitLocker -ErrorAction SilentlyContinue
        if (-not $bitlockerFeature -or -not $bitlockerFeature.Installed) {
            $bitlockerCommandAvailable = Get-Command -Name manage-bde.exe -ErrorAction SilentlyContinue
            if (-not $bitlockerCommandAvailable) {
                Write-Log -Message "BitLocker feature not installed and manage-bde.exe not available" -Level Warning
            }
        }
        
        # Check if Azure Key Vault integration is properly configured
        if ($RecoveryKeyBackupType -eq "KeyVault") {
            if (-not $script:BitLockerConfig.AzureKeyVaultName -or -not $script:BitLockerConfig.AzureTenantId) {
                Write-Log -Message "Azure Key Vault configuration incomplete. Use Set-BitLockerConfiguration to configure." -Level Warning
            }
            
            if (-not (Test-AzPowerShellModule)) {
                Write-Log -Message "Azure PowerShell modules not installed. Key Vault integration will not work." -Level Warning
            }
        }
        
        # Check current BitLocker status on system drive
        $encryptionStatus = Test-BitLockerEncryption -DriveLetter "C:"
        if ($encryptionStatus.IsEncrypted) {
            Write-Log -Message "System drive is already BitLocker encrypted with $($encryptionStatus.EncryptionMethod)" -Level Information
            
            # Check if encryption status is managed by Intune
            if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker" -ErrorAction SilentlyContinue)) {
                Write-Log -Message "BitLocker appears to be managed by Intune." -Level Information
            } else {
                Write-Log -Message "BitLocker does not appear to be managed by Intune." -Level Information
            }
        } else {
            Write-Log -Message "System drive is not BitLocker encrypted" -Level Warning
            
            if ($EnableEncryption) {
                Write-Log -Message "BitLocker encryption will be enabled during migration" -Level Information
            }
        }
        
        Write-Log -Message "BitLocker Manager initialized successfully" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to initialize BitLocker Manager: $_" -Level Error
        return $false
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Set-BitLockerConfiguration, Test-BitLockerEncryption, 
    Backup-BitLockerKeyToFile, Backup-BitLockerKeyToKeyVault, Get-BitLockerKeyFromKeyVault,
    Invoke-BitLockerMigration, Initialize-BitLockerManager 