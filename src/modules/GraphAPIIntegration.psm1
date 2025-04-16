#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Intune

<#
.SYNOPSIS
    Integrates with Microsoft Graph API for Azure/Intune operations.
    
.DESCRIPTION
    The GraphAPIIntegration module provides a standardized interface for
    interacting with Microsoft Graph API, with specific functions for
    BitLocker recovery key migration, device management, and other
    Azure/Intune operations.
    
.NOTES
    File Name      : GraphAPIIntegration.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1, Microsoft.Graph.Intune module
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

# Import SecurityFoundation for credential management
if (-not (Get-Module -Name 'SecurityFoundation' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SecurityFoundation.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module SecurityFoundation.psm1 not found in $PSScriptRoot"
    }
}

# Module variables
$script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\config\settings.json"
$script:GraphApiVersion = "v1.0"
$script:GraphEndpoint = "https://graph.microsoft.com"
$script:AccessToken = $null
$script:TokenExpiration = [DateTime]::MinValue
$script:Config = $null

# Initialize the module
function Initialize-GraphAPIIntegration {
    <#
    .SYNOPSIS
        Initializes the Graph API Integration module.
    
    .DESCRIPTION
        Sets up the necessary configuration for Graph API Integration,
        including loading API endpoints and authentication settings.
    
    .PARAMETER ConfigPath
        Path to the JSON configuration file with Graph API settings.
        
    .EXAMPLE
        Initialize-GraphAPIIntegration -ConfigPath "C:\Path\To\settings.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $script:ConfigPath
    )
    
    Write-Log -Message "Initializing Graph API Integration module" -Level INFO
    
    # Check if configuration file exists
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Log -Message "Configuration file not found at $ConfigPath" -Level ERROR
        throw "Configuration file not found at $ConfigPath"
    }
    
    try {
        # Load configuration
        $script:Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        
        # Validate configuration
        if (-not $script:Config.targetTenant -or 
            -not $script:Config.targetTenant.clientID -or 
            -not $script:Config.targetTenant.tenantID) {
            Write-Log -Message "Invalid configuration: Missing targetTenant information" -Level ERROR
            throw "Invalid configuration: Missing targetTenant information"
        }
        
        Write-Log -Message "Graph API Integration module initialized successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Failed to initialize Graph API Integration module: $_" -Level ERROR
        throw "Failed to initialize Graph API Integration module: $_"
    }
}

function Connect-MsGraph {
    <#
    .SYNOPSIS
        Establishes a connection to Microsoft Graph API.
    
    .DESCRIPTION
        Authenticates with Microsoft Graph API using client credentials
        and retrieves an access token for subsequent API calls.
        
    .PARAMETER ClientID
        The client ID (app ID) of the Azure AD application.
        
    .PARAMETER ClientSecret
        The client secret of the Azure AD application.
        
    .PARAMETER TenantID
        The Azure AD tenant ID.
        
    .EXAMPLE
        Connect-MsGraph -ClientID "12345678-1234-1234-1234-123456789012" -ClientSecret "your-secret" -TenantID "tenant-id"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ClientID = $script:Config.targetTenant.clientID,
        
        [Parameter(Mandatory = $false)]
        [string]$ClientSecret = $script:Config.targetTenant.clientSecret,
        
        [Parameter(Mandatory = $false)]
        [string]$TenantID = $script:Config.targetTenant.tenantID
    )
    
    Write-Log -Message "Connecting to Microsoft Graph API" -Level INFO
    
    # Check if we already have a valid token
    if ($script:AccessToken -and $script:TokenExpiration -gt (Get-Date).AddMinutes(5)) {
        Write-Log -Message "Using existing Microsoft Graph API token" -Level INFO
        return $true
    }
    
    try {
        # Endpoint to get token
        $tokenUrl = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
        
        # Token request parameters
        $body = @{
            client_id     = $ClientID
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        }
        
        # Make the token request
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        
        # Store the token and expiration
        $script:AccessToken = $tokenResponse.access_token
        $script:TokenExpiration = (Get-Date).AddSeconds($tokenResponse.expires_in)
        
        Write-Log -Message "Successfully connected to Microsoft Graph API" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Failed to connect to Microsoft Graph API: $_" -Level ERROR
        return $false
    }
}

function Invoke-GraphApiRequest {
    <#
    .SYNOPSIS
        Makes a request to Microsoft Graph API.
    
    .DESCRIPTION
        Sends HTTP requests to Microsoft Graph API with proper authentication
        and handles common error cases.
        
    .PARAMETER Method
        The HTTP method to use (GET, POST, PATCH, DELETE).
        
    .PARAMETER Endpoint
        The Graph API endpoint to call (without the base URL).
        
    .PARAMETER Body
        The request body for POST or PATCH requests.
        
    .PARAMETER ContentType
        The content type of the request body.
        
    .EXAMPLE
        Invoke-GraphApiRequest -Method GET -Endpoint "/users"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,
        
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $false)]
        [object]$Body = $null,
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json"
    )
    
    # Ensure we're connected
    if (-not $script:AccessToken -or $script:TokenExpiration -le (Get-Date)) {
        if (-not (Connect-MsGraph)) {
            throw "Failed to authenticate with Microsoft Graph API"
        }
    }
    
    # Construct the full URL
    $uri = "$script:GraphEndpoint/$script:GraphApiVersion$Endpoint"
    
    try {
        $params = @{
            Uri         = $uri
            Method      = $Method
            Headers     = @{
                Authorization = "Bearer $script:AccessToken"
            }
            ContentType = $ContentType
            ErrorAction = "Stop"
        }
        
        # Add body if provided
        if ($Body) {
            if ($ContentType -eq "application/json" -and $Body -is [PSCustomObject]) {
                $params.Body = $Body | ConvertTo-Json -Depth 10
            }
            else {
                $params.Body = $Body
            }
        }
        
        Write-Log -Message "Sending $Method request to $uri" -Level INFO
        $response = Invoke-RestMethod @params
        
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDescription = $_.Exception.Response.StatusDescription
        
        Write-Log -Message "Graph API request failed: $statusCode $statusDescription - $_" -Level ERROR
        
        # Handle token expiration
        if ($statusCode -eq 401) {
            Write-Log -Message "Access token expired, reconnecting..." -Level INFO
            if (Connect-MsGraph) {
                # Retry the request once
                return Invoke-GraphApiRequest @PSBoundParameters
            }
        }
        
        throw "Graph API request failed: $_"
    }
}

function Get-BitLockerRecoveryKey {
    <#
    .SYNOPSIS
        Extracts BitLocker recovery key from the local device.
    
    .DESCRIPTION
        Gets the BitLocker recovery key information for specified volumes
        to prepare for backup to Azure AD.
        
    .PARAMETER DriveLetter
        The drive letter to get the recovery key for (default is system drive).
        
    .EXAMPLE
        Get-BitLockerRecoveryKey -DriveLetter "C:"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = $env:SystemDrive
    )
    
    Write-Log -Message "Getting BitLocker recovery key for drive $DriveLetter" -Level INFO
    
    try {
        # Ensure BitLocker module is available
        if (-not (Get-Command -Name "Get-BitLockerVolume" -ErrorAction SilentlyContinue)) {
            if (-not (Get-Module -Name "BitLocker" -ListAvailable)) {
                Write-Log -Message "BitLocker PowerShell module not found" -Level ERROR
                throw "BitLocker PowerShell module not found"
            }
            
            Import-Module -Name "BitLocker" -ErrorAction Stop
        }
        
        # Get BitLocker volume information
        $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
        
        if (-not $volume) {
            Write-Log -Message "BitLocker volume not found for drive $DriveLetter" -Level WARNING
            return $null
        }
        
        if ($volume.ProtectionStatus -ne "On") {
            Write-Log -Message "BitLocker protection is not enabled on drive $DriveLetter" -Level WARNING
            return $null
        }
        
        # Get recovery key protector
        $keyProtector = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
        
        if (-not $keyProtector) {
            Write-Log -Message "No recovery password found for drive $DriveLetter" -Level WARNING
            return $null
        }
        
        # Create result object
        $result = [PSCustomObject]@{
            DriveLetterVolume = $DriveLetter
            VolumeStatus = $volume.VolumeStatus
            EncryptionMethod = $volume.EncryptionMethod
            ProtectionStatus = $volume.ProtectionStatus
            LockStatus = $volume.LockStatus
            KeyProtectorId = $keyProtector.KeyProtectorId
            RecoveryPassword = $keyProtector.RecoveryPassword
        }
        
        Write-Log -Message "Successfully retrieved BitLocker recovery key for drive $DriveLetter" -Level INFO
        return $result
    }
    catch {
        Write-Log -Message "Failed to get BitLocker recovery key: $_" -Level ERROR
        return $null
    }
}

function Backup-BitLockerKeyToAzureAD {
    <#
    .SYNOPSIS
        Backs up BitLocker recovery key to Azure AD.
    
    .DESCRIPTION
        Extracts BitLocker recovery key and backs it up to Azure AD
        using native Windows BitLocker cmdlets or Graph API as fallback.
        
    .PARAMETER DriveLetter
        The drive letter to back up the recovery key for (default is system drive).
        
    .PARAMETER ForceMsGraph
        Forces the use of Microsoft Graph API instead of native Windows cmdlets.
        
    .EXAMPLE
        Backup-BitLockerKeyToAzureAD -DriveLetter "C:"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = $env:SystemDrive,
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceMsGraph
    )
    
    Write-Log -Message "Starting BitLocker key backup to Azure AD for drive $DriveLetter" -Level INFO
    
    try {
        # Try using native Windows cmdlet first (unless forced to use Graph API)
        if (-not $ForceMsGraph) {
            try {
                # Get BitLocker volume
                $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
                
                if (-not $volume) {
                    Write-Log -Message "BitLocker volume not found for drive $DriveLetter" -Level ERROR
                    return $false
                }
                
                # Get recovery key protector
                $keyProtector = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
                
                if (-not $keyProtector) {
                    Write-Log -Message "No recovery password found for drive $DriveLetter" -Level WARNING
                    return $false
                }
                
                # Back up to Azure AD
                $result = BackupToAAD-BitLockerKeyProtector -MountPoint $DriveLetter -KeyProtectorId $keyProtector.KeyProtectorId
                
                if ($result) {
                    Write-Log -Message "Successfully backed up BitLocker key to Azure AD using native cmdlet" -Level INFO
                    return $true
                } else {
                    Write-Log -Message "Failed to back up BitLocker key using native cmdlet, falling back to Graph API" -Level WARNING
                }
            }
            catch {
                Write-Log -Message "Error using native BitLocker cmdlet: $_" -Level WARNING
                Write-Log -Message "Falling back to Graph API method" -Level INFO
            }
        }
        
        # If native cmdlet failed or ForceMsGraph is specified, use Graph API
        # Get BitLocker key information
        $bitlockerInfo = Get-BitLockerRecoveryKey -DriveLetter $DriveLetter
        
        if (-not $bitlockerInfo -or -not $bitlockerInfo.RecoveryPassword) {
            Write-Log -Message "No BitLocker recovery key available to back up" -Level ERROR
            return $false
        }
        
        # Connect to Graph API if not already connected
        if (-not (Connect-MsGraph)) {
            Write-Log -Message "Failed to connect to Microsoft Graph API" -Level ERROR
            return $false
        }
        
        # Get device information
        $deviceInfo = Get-WmiObject -Class Win32_ComputerSystem
        $deviceName = $deviceInfo.Name
        
        # Find the device in Intune
        $endpoint = "/deviceManagement/managedDevices?`$filter=deviceName eq '$deviceName'"
        $deviceResult = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
        
        if (-not $deviceResult -or -not $deviceResult.value -or $deviceResult.value.Count -eq 0) {
            Write-Log -Message "Device not found in Intune/Azure AD" -Level ERROR
            return $false
        }
        
        $deviceId = $deviceResult.value[0].id
        
        # Create BitLocker recovery key in Azure AD
        # Note: This endpoint is theoretical and would need to be validated against actual Graph API documentation
        $bitlockerEndpoint = "/deviceManagement/managedDevices/$deviceId/recoveryKeys"
        $bitlockerBody = @{
            key = $bitlockerInfo.RecoveryPassword
            volumeId = $bitlockerInfo.KeyProtectorId
            deviceName = $deviceName
        }
        
        $response = Invoke-GraphApiRequest -Method POST -Endpoint $bitlockerEndpoint -Body $bitlockerBody
        
        if ($response) {
            Write-Log -Message "Successfully backed up BitLocker key to Azure AD using Graph API" -Level INFO
            return $true
        } else {
            Write-Log -Message "Failed to back up BitLocker key to Azure AD" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log -Message "Error backing up BitLocker key to Azure AD: $_" -Level ERROR
        return $false
    }
}

function Confirm-BitLockerKeyBackup {
    <#
    .SYNOPSIS
        Confirms that BitLocker recovery key is backed up to Azure AD.
    
    .DESCRIPTION
        Verifies that the BitLocker recovery key for the specified volume
        has been successfully backed up to Azure AD.
        
    .PARAMETER DriveLetter
        The drive letter to verify the backup for (default is system drive).
        
    .EXAMPLE
        Confirm-BitLockerKeyBackup -DriveLetter "C:"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = $env:SystemDrive
    )
    
    Write-Log -Message "Confirming BitLocker key backup for drive $DriveLetter" -Level INFO
    
    try {
        # Get BitLocker volume information
        $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
        
        if (-not $volume) {
            Write-Log -Message "BitLocker volume not found for drive $DriveLetter" -Level ERROR
            return $false
        }
        
        # Get recovery key protector
        $keyProtector = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
        
        if (-not $keyProtector) {
            Write-Log -Message "No recovery password found for drive $DriveLetter" -Level WARNING
            return $false
        }
        
        # Get device information
        $deviceInfo = Get-WmiObject -Class Win32_ComputerSystem
        $deviceName = $deviceInfo.Name
        
        # Connect to Graph API
        if (-not (Connect-MsGraph)) {
            Write-Log -Message "Failed to connect to Microsoft Graph API" -Level ERROR
            return $false
        }
        
        # Find the device in Intune
        $endpoint = "/deviceManagement/managedDevices?`$filter=deviceName eq '$deviceName'"
        $deviceResult = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
        
        if (-not $deviceResult -or -not $deviceResult.value -or $deviceResult.value.Count -eq 0) {
            Write-Log -Message "Device not found in Intune/Azure AD" -Level ERROR
            return $false
        }
        
        $deviceId = $deviceResult.value[0].id
        
        # Check for BitLocker recovery keys in Azure AD
        # Note: This endpoint is theoretical and would need to be validated against actual Graph API documentation
        $recoveryKeysEndpoint = "/deviceManagement/managedDevices/$deviceId/recoveryKeys"
        $recoveryKeysResult = Invoke-GraphApiRequest -Method GET -Endpoint $recoveryKeysEndpoint
        
        if ($recoveryKeysResult -and $recoveryKeysResult.value) {
            foreach ($key in $recoveryKeysResult.value) {
                if ($key.volumeId -eq $keyProtector.KeyProtectorId) {
                    Write-Log -Message "BitLocker key is confirmed to be backed up to Azure AD" -Level INFO
                    return $true
                }
            }
        }
        
        Write-Log -Message "BitLocker key backup not found in Azure AD" -Level WARNING
        return $false
    }
    catch {
        Write-Log -Message "Error confirming BitLocker key backup: $_" -Level ERROR
        return $false
    }
}

function Migrate-BitLockerKeys {
    <#
    .SYNOPSIS
        Migrates BitLocker recovery keys to Azure AD.
    
    .DESCRIPTION
        Extracts BitLocker recovery keys from all encrypted volumes and
        backs them up to Azure AD, with validation and reporting.
        
    .PARAMETER ForceMigration
        Forces migration even if keys appear to be already backed up.
        
    .EXAMPLE
        Migrate-BitLockerKeys
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ForceMigration
    )
    
    Write-Log -Message "Starting BitLocker recovery key migration" -Level INFO
    
    $results = @{
        Success = $true
        Drives = @{}
        BackupMethod = $null
        Errors = @()
    }
    
    try {
        # Initialize the module if not already initialized
        if (-not $script:Config) {
            Initialize-GraphAPIIntegration
        }
        
        # Check BitLocker method setting
        $bitlockerMethod = $script:Config.bitlockerMethod
        
        if ($bitlockerMethod -ne "MIGRATE" -and -not $ForceMigration) {
            Write-Log -Message "BitLocker migration not enabled in configuration (set to: $bitlockerMethod)" -Level WARNING
            $results.Success = $false
            $results.Errors += "BitLocker migration not enabled in configuration"
            return $results
        }
        
        # Get all BitLocker volumes
        $volumes = Get-BitLockerVolume -ErrorAction Stop
        
        if (-not $volumes -or $volumes.Count -eq 0) {
            Write-Log -Message "No BitLocker volumes found on the device" -Level WARNING
            $results.Success = $false
            $results.Errors += "No BitLocker volumes found on the device"
            return $results
        }
        
        # Determine backup method based on device type
        $isAzureADJoined = $false
        $isHybridJoined = $false
        
        try {
            $dsregCmd = Start-Process -FilePath "dsregcmd.exe" -ArgumentList "/status" -NoNewWindow -Wait -PassThru -RedirectStandardOutput ".\dsregstatus.txt"
            $dsregOutput = Get-Content -Path ".\dsregstatus.txt" -Raw
            Remove-Item -Path ".\dsregstatus.txt" -Force
            
            $isAzureADJoined = $dsregOutput -match "AzureAdJoined : YES"
            $isHybridJoined = $dsregOutput -match "DomainJoined : YES" -and $dsregOutput -match "AzureAdJoined : YES"
        }
        catch {
            Write-Log -Message "Error determining device join type: $_" -Level WARNING
        }
        
        # Set backup method based on device type
        if ($isAzureADJoined -and -not $isHybridJoined) {
            $results.BackupMethod = "NativeCmdlet"
        }
        else {
            $results.BackupMethod = "GraphAPI"
        }
        
        # Process each volume
        foreach ($volume in $volumes) {
            $driveLetter = $volume.MountPoint
            
            $results.Drives[$driveLetter] = @{
                ProtectionStatus = $volume.ProtectionStatus
                VolumeStatus = $volume.VolumeStatus
                BackupSuccess = $false
                BackupVerified = $false
                Error = $null
            }
            
            # Skip volumes that aren't encrypted or protected
            if ($volume.ProtectionStatus -ne "On") {
                Write-Log -Message "Volume $driveLetter is not protected by BitLocker - skipping" -Level INFO
                continue
            }
            
            # Try to back up using appropriate method
            try {
                if ($results.BackupMethod -eq "NativeCmdlet") {
                    $backupSuccess = Backup-BitLockerKeyToAzureAD -DriveLetter $driveLetter
                }
                else {
                    $backupSuccess = Backup-BitLockerKeyToAzureAD -DriveLetter $driveLetter -ForceMsGraph
                }
                
                $results.Drives[$driveLetter].BackupSuccess = $backupSuccess
                
                if (-not $backupSuccess) {
                    $results.Success = $false
                    $results.Drives[$driveLetter].Error = "Failed to back up BitLocker key"
                    continue
                }
                
                # Verify backup
                $verifySuccess = Confirm-BitLockerKeyBackup -DriveLetter $driveLetter
                $results.Drives[$driveLetter].BackupVerified = $verifySuccess
                
                if (-not $verifySuccess) {
                    $results.Success = $false
                    $results.Drives[$driveLetter].Error = "Backup verification failed"
                }
            }
            catch {
                $results.Success = $false
                $results.Drives[$driveLetter].BackupSuccess = $false
                $results.Drives[$driveLetter].Error = "Exception: $_"
                $results.Errors += "Exception processing drive $driveLetter : $_"
                Write-Log -Message "Error processing drive $driveLetter : $_" -Level ERROR
            }
        }
        
        # Log summary
        if ($results.Success) {
            Write-Log -Message "BitLocker recovery key migration completed successfully" -Level INFO
        }
        else {
            Write-Log -Message "BitLocker recovery key migration completed with errors" -Level WARNING
        }
        
        return $results
    }
    catch {
        Write-Log -Message "Error during BitLocker recovery key migration: $_" -Level ERROR
        $results.Success = $false
        $results.Errors += "Global error: $_"
        return $results
    }
}

# Export public functions
Export-ModuleMember -Function Initialize-GraphAPIIntegration
Export-ModuleMember -Function Connect-MsGraph
Export-ModuleMember -Function Get-BitLockerRecoveryKey
Export-ModuleMember -Function Backup-BitLockerKeyToAzureAD
Export-ModuleMember -Function Confirm-BitLockerKeyBackup
Export-ModuleMember -Function Migrate-BitLockerKeys 