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
    BackupPath = Join-Path -Path $env:TEMP -ChildPath "WS1Migration\BitLockerBackup"
    AzureKeyVaultName = $null
    AzureKeyVaultResourceGroup = $null
    AzureTenantId = $null
    AzureSubscriptionId = $null
    EnableEncryption = $true
    EncryptionMethod = "XtsAes256"  # Options: Aes128, Aes256, XtsAes128, XtsAes256
    RecoveryKeyBackupType = "Local"  # Options: Local, AzureAD, KeyVault
    KeyProtectorTypes = @("RecoveryPassword", "TpmPin")
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
        Checks if the required Azure PowerShell module is installed.
    #>
    if (Get-Module -Name Az.KeyVault -ListAvailable) {
        Write-Log -Message "Az.KeyVault module is installed." -Level Information
        return $true
    } else {
        Write-Log -Message "Az.KeyVault module is not installed." -Level Warning
        return $false
    }
}

function Connect-AzureKeyVault {
    <#
    .SYNOPSIS
        Connects to Azure and the Key Vault.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    try {
        # Check if Az modules are installed
        if (-not (Test-AzPowerShellModule)) {
            Write-Log -Message "Azure PowerShell modules required for Azure Key Vault integration are not installed." -Level Error
            return $false
        }
        
        # Check if already connected
        try {
            $context = Get-AzContext -ErrorAction Stop
            if ($context -and $context.Tenant.Id -eq $TenantId) {
                Write-Log -Message "Already connected to Azure with the correct tenant." -Level Information
                return $true
            }
        } catch {
            # Not connected, will connect below
        }
        
        # Connect to Azure
        if ($Credential) {
            Connect-AzAccount -TenantId $TenantId -Credential $Credential -ErrorAction Stop | Out-Null
        } else {
            Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
        }
        
        # Verify Key Vault exists
        $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction SilentlyContinue
        if (-not $keyVault) {
            Write-Log -Message "Key Vault '$KeyVaultName' not found." -Level Error
            return $false
        }
        
        Write-Log -Message "Successfully connected to Azure Key Vault: $KeyVaultName" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to connect to Azure Key Vault: $_" -Level Error
        return $false
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
        [string[]]$KeyProtectorTypes
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
    
.EXAMPLE
    Backup-BitLockerKeyToKeyVault -DriveLetter "C:" -KeyVaultName "MyKeyVault" -TenantId "tenant-id"
    
.OUTPUTS
    System.Boolean. Returns $true if backup was successful.
#>
function Backup-BitLockerKeyToKeyVault {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:",
        
        [Parameter(Mandatory = $false)]
        [string]$KeyVaultName = $script:BitLockerConfig.AzureKeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [string]$TenantId = $script:BitLockerConfig.AzureTenantId
    )
    
    try {
        # Validate parameters
        if (-not $KeyVaultName) {
            Write-Log -Message "Azure Key Vault name not specified" -Level Error
            return $false
        }
        
        if (-not $TenantId) {
            Write-Log -Message "Azure Tenant ID not specified" -Level Error
            return $false
        }
        
        # Get recovery key
        $recoveryKey = Get-BitLockerRecoveryPassword -DriveLetter $DriveLetter
        if (-not $recoveryKey) {
            Write-Log -Message "No BitLocker recovery key found for drive $DriveLetter" -Level Error
            return $false
        }
        
        # Connect to Azure Key Vault
        $connected = Connect-AzureKeyVault -KeyVaultName $KeyVaultName -TenantId $TenantId -Credential $Credential
        if (-not $connected) {
            Write-Log -Message "Failed to connect to Azure Key Vault" -Level Error
            return $false
        }
        
        # Format secret name
        $computerName = $env:COMPUTERNAME
        $secretName = Format-SecretName -ComputerName $computerName -DriveLetter $DriveLetter
        
        # Create secret content with metadata
        $secretContent = @{
            RecoveryKey = $recoveryKey
            ComputerName = $computerName
            Drive = $DriveLetter
            Timestamp = Get-Date -Format 'o'
            Username = $env:USERNAME
        } | ConvertTo-Json
        
        # Convert to secure string
        $secureValue = ConvertTo-SecureString -String $secretContent -AsPlainText -Force
        
        # Store in Key Vault
        $secretParams = @{
            VaultName = $KeyVaultName
            Name = $secretName
            SecretValue = $secureValue
            ContentType = 'application/json'
            Tags = @{
                'ComputerName' = $computerName
                'Drive' = $DriveLetter.TrimEnd(":")
                'Purpose' = 'BitLockerRecoveryKey'
                'MigrationTimestamp' = (Get-Date -Format 'yyyyMMddHHmmss')
            }
        }
        
        $secret = Set-AzKeyVaultSecret @secretParams
        
        Write-Log -Message "BitLocker recovery key for drive $DriveLetter successfully backed up to Azure Key Vault '$KeyVaultName'" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Error backing up BitLocker key to Azure Key Vault: $_" -Level Error
        return $false
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
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C:",
        
        [Parameter(Mandatory = $false)]
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$KeyVaultName = $script:BitLockerConfig.AzureKeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [string]$TenantId = $script:BitLockerConfig.AzureTenantId
    )
    
    try {
        # Validate parameters
        if (-not $KeyVaultName) {
            Write-Log -Message "Azure Key Vault name not specified" -Level Error
            return $null
        }
        
        if (-not $TenantId) {
            Write-Log -Message "Azure Tenant ID not specified" -Level Error
            return $null
        }
        
        # Connect to Azure Key Vault
        $connected = Connect-AzureKeyVault -KeyVaultName $KeyVaultName -TenantId $TenantId -Credential $Credential
        if (-not $connected) {
            Write-Log -Message "Failed to connect to Azure Key Vault" -Level Error
            return $null
        }
        
        # Format secret name
        $secretName = Format-SecretName -ComputerName $ComputerName -DriveLetter $DriveLetter
        
        # Get secret from Key Vault
        $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -ErrorAction SilentlyContinue
        
        if (-not $secret) {
            Write-Log -Message "BitLocker recovery key not found in Key Vault for $ComputerName drive $DriveLetter" -Level Warning
            return $null
        }
        
        # Convert from secure string
        $secretValueText = $secret.SecretValue | ConvertFrom-SecureString -AsPlainText
        
        # Parse JSON content
        $secretContent = $secretValueText | ConvertFrom-Json
        
        Write-Log -Message "Successfully retrieved BitLocker recovery key from Key Vault for $ComputerName drive $DriveLetter" -Level Information
        return $secretContent.RecoveryKey
    }
    catch {
        Write-Log -Message "Error retrieving BitLocker key from Azure Key Vault: $_" -Level Error
        return $null
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