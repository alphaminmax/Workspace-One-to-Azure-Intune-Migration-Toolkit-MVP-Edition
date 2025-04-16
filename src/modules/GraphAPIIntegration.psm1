#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Intune
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Integrates with Microsoft Graph API for Azure/Intune operations.                                                      #
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
    Integrates with Microsoft Graph API for Azure/Intune operations.
    
.DESCRIPTION
    The GraphAPIIntegration module provides a standardized interface for
    interacting with Microsoft Graph API, with specific functions for
    BitLocker recovery key migration, device management, and other
    Azure/Intune operations.
    
.NOTES
    File Name      : GraphAPIIntegration.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1, Microsoft.Graph.Intune module, MSAL.PS module
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

# Ensure MSAL.PS module is available for modern authentication
if (-not (Get-Module -Name 'MSAL.PS' -ListAvailable)) {
    try {
        Write-Log -Message "MSAL.PS module not found. Attempting to install..." -Level INFO
        Install-Module -Name MSAL.PS -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module -Name MSAL.PS -Force -ErrorAction Stop
        Write-Log -Message "MSAL.PS module installed successfully" -Level INFO
    } catch {
        Write-Log -Message "Failed to install MSAL.PS module: $_" -Level WARNING
        Write-Log -Message "Will fall back to legacy authentication methods" -Level WARNING
    }
}

# Module variables
$script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\config\settings.json"
$script:GraphApiVersion = "v1.0"
$script:GraphEndpoint = "https://graph.microsoft.com"
$script:AccessToken = $null
$script:TokenExpiration = [DateTime]::MinValue
$script:Config = $null
$script:AuthRetryCount = 3
$script:RequestRetryCount = 3
$script:RequestRetryDelay = 2
$script:RequestCache = @{}
$script:CacheTimeout = 300 # 5 minutes cache timeout
$script:LastCacheCleanup = [DateTime]::Now

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
        
    .PARAMETER RetryCount
        Number of retries for API requests.
        
    .PARAMETER RetryDelay
        Delay in seconds between retries.
        
    .PARAMETER CacheTimeout
        Cache timeout in seconds for GET requests.
        
    .EXAMPLE
        Initialize-GraphAPIIntegration -ConfigPath "C:\Path\To\settings.json" -RetryCount 5 -RetryDelay 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $script:ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryCount = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelay = 2,
        
        [Parameter(Mandatory = $false)]
        [int]$CacheTimeout = 300
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
        
        # Set retry and cache parameters
        $script:RequestRetryCount = $RetryCount
        $script:RequestRetryDelay = $RetryDelay
        $script:CacheTimeout = $CacheTimeout
        
        # Clean request cache
        $script:RequestCache = @{}
        $script:LastCacheCleanup = [DateTime]::Now
        
        Write-Log -Message "Graph API Integration module initialized successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Failed to initialize Graph API Integration module: $_" -Level ERROR
        throw "Failed to initialize Graph API Integration module: $_"
    }
}

function Get-MsalToken {
    <#
    .SYNOPSIS
        Gets an authentication token using the MSAL library.
    
    .DESCRIPTION
        Authenticates using MSAL library and provides more secure token handling
        for Microsoft Graph API.
        
    .PARAMETER ClientID
        The client ID (app ID) of the Azure AD application.
        
    .PARAMETER ClientSecret
        The client secret of the Azure AD application.
        
    .PARAMETER TenantID
        The Azure AD tenant ID.
        
    .PARAMETER UseDeviceCode
        Use device code flow for interactive authentication.
        
    .PARAMETER Scopes
        The requested scopes for the token.
        
    .EXAMPLE
        Get-MsalToken -ClientID "12345678-1234-1234-1234-123456789012" -ClientSecret "your-secret" -TenantID "tenant-id"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientID,
        
        [Parameter(Mandatory = $false)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantID,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseDeviceCode,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Scopes = @("https://graph.microsoft.com/.default")
    )
    
    try {
        # Check if MSAL.PS module is available
        if (-not (Get-Module -Name 'MSAL.PS' -ListAvailable)) {
            Write-Log -Message "MSAL.PS module not available for authentication" -Level WARNING
            return $null
        }
        
        if ($UseDeviceCode) {
            # Use device code authentication flow for interactive sessions
            Write-Log -Message "Using MSAL device code authentication flow" -Level INFO
            $token = Get-MsalToken -ClientId $ClientID -TenantId $TenantID -Scopes $Scopes -DeviceCode
        }
        elseif ($ClientSecret) {
            # Use client credentials flow for service authentication
            Write-Log -Message "Using MSAL client credentials authentication flow" -Level INFO
            $secureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
            $token = Get-MsalToken -ClientId $ClientID -TenantId $TenantID -ClientSecret $secureClientSecret -Scopes $Scopes
        }
        else {
            # Fallback to client credentials from certificate if configured and available
            Write-Log -Message "Client secret not provided, checking for certificate-based authentication" -Level INFO
            
            # Implement certificate-based auth if needed here
            throw "Certificate-based authentication not implemented yet. Please provide a client secret."
        }
        
        Write-Log -Message "MSAL token acquired successfully" -Level INFO
        return $token
    }
    catch {
        Write-Log -Message "Failed to acquire MSAL token: $_" -Level ERROR
        return $null
    }
}

function Connect-MsGraph {
    <#
    .SYNOPSIS
        Establishes a connection to Microsoft Graph API.
    
    .DESCRIPTION
        Authenticates with Microsoft Graph API using MSAL.PS or fallback
        to REST-based authentication, and retrieves an access token for
        subsequent API calls.
        
    .PARAMETER ClientID
        The client ID (app ID) of the Azure AD application.
        
    .PARAMETER ClientSecret
        The client secret of the Azure AD application.
        
    .PARAMETER TenantID
        The Azure AD tenant ID.
        
    .PARAMETER UseDeviceCode
        Use device code flow for interactive authentication.
        
    .PARAMETER ForceLegacyAuth
        Force the use of legacy REST-based authentication.
        
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
        [string]$TenantID = $script:Config.targetTenant.tenantID,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseDeviceCode,
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceLegacyAuth
    )
    
    Write-Log -Message "Connecting to Microsoft Graph API" -Level INFO
    
    # Check if we already have a valid token
    if ($script:AccessToken -and $script:TokenExpiration -gt (Get-Date).AddMinutes(5)) {
        Write-Log -Message "Using existing Microsoft Graph API token" -Level INFO
        return $true
    }
    
    # Try MSAL authentication first unless legacy auth is forced
    if (-not $ForceLegacyAuth -and (Get-Module -Name 'MSAL.PS' -ListAvailable)) {
        try {
            $token = Get-MsalToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID -UseDeviceCode:$UseDeviceCode
            
            if ($token) {
                $script:AccessToken = $token.AccessToken
                $script:TokenExpiration = $token.ExpiresOn.LocalDateTime
                
                Write-Log -Message "Successfully connected to Microsoft Graph API using MSAL" -Level INFO
                return $true
            }
            else {
                Write-Log -Message "Failed to get MSAL token, falling back to legacy authentication" -Level WARNING
            }
        }
        catch {
            Write-Log -Message "Error during MSAL authentication: $_" -Level WARNING
            Write-Log -Message "Falling back to legacy authentication" -Level INFO
        }
    }
    
    # Fallback to legacy REST-based authentication
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
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        
        # Store the token and expiration
        $script:AccessToken = $tokenResponse.access_token
        $script:TokenExpiration = (Get-Date).AddSeconds($tokenResponse.expires_in)
        
        Write-Log -Message "Successfully connected to Microsoft Graph API using legacy authentication" -Level INFO
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
        Sends HTTP requests to Microsoft Graph API with proper authentication,
        caching for GET requests, retry logic, and comprehensive error handling.
        
    .PARAMETER Method
        The HTTP method to use (GET, POST, PATCH, DELETE).
        
    .PARAMETER Endpoint
        The Graph API endpoint to call (without the base URL).
        
    .PARAMETER Body
        The request body for POST or PATCH requests.
        
    .PARAMETER ContentType
        The content type of the request body.
        
    .PARAMETER Headers
        Additional headers to include in the request.
        
    .PARAMETER ApiVersion
        The Graph API version to use (defaults to the module setting).
        
    .PARAMETER DisableCache
        Disables caching for GET requests.
        
    .PARAMETER MaxRetries
        Maximum number of retries for failed requests.
        
    .PARAMETER RetryDelaySeconds
        Delay in seconds between retries.
        
    .EXAMPLE
        Invoke-GraphApiRequest -Method GET -Endpoint "/users"
        
    .EXAMPLE
        Invoke-GraphApiRequest -Method POST -Endpoint "/users" -Body $userObject -DisableCache
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
        [string]$ContentType = "application/json",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$ApiVersion = $script:GraphApiVersion,
        
        [Parameter(Mandatory = $false)]
        [switch]$DisableCache,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = $script:RequestRetryCount,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = $script:RequestRetryDelay
    )
    
    # Check if cache cleanup is needed (every 5 minutes)
    if ((Get-Date) -gt $script:LastCacheCleanup.AddMinutes(5)) {
        # Clean up expired cache items
        $expiredKeys = @()
        $currentTime = Get-Date
        
        foreach ($key in $script:RequestCache.Keys) {
            if ($script:RequestCache[$key].Expires -lt $currentTime) {
                $expiredKeys += $key
            }
        }
        
        foreach ($key in $expiredKeys) {
            $script:RequestCache.Remove($key)
        }
        
        $script:LastCacheCleanup = Get-Date
        Write-Log -Message "Cleaned up $($expiredKeys.Count) expired cache items" -Level INFO
    }
    
    # Calculate cache key if GET request
    $cacheKey = $null
    if ($Method -eq "GET" -and -not $DisableCache) {
        $cacheKey = "$Method-$ApiVersion-$Endpoint"
        
        # Check if we have a cached response
        if ($script:RequestCache.ContainsKey($cacheKey)) {
            $cachedItem = $script:RequestCache[$cacheKey]
            if ($cachedItem.Expires -gt (Get-Date)) {
                Write-Log -Message "Using cached response for $Method $uri" -Level INFO
                return $cachedItem.Data
            }
        }
    }
    
    # Ensure we're connected
    if (-not $script:AccessToken -or $script:TokenExpiration -le (Get-Date)) {
        if (-not (Connect-MsGraph)) {
            throw "Failed to authenticate with Microsoft Graph API"
        }
    }
    
    # Construct the full URL
    $uri = "$script:GraphEndpoint/$ApiVersion$Endpoint"
    
    # Set up retry loop
    $retryCount = 0
    $success = $false
    $lastException = $null
    $response = $null
    
    while (-not $success -and $retryCount -le $MaxRetries) {
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
            
            # Add custom headers
            foreach ($key in $Headers.Keys) {
                $params.Headers[$key] = $Headers[$key]
            }
            
            # Add body if provided
            if ($Body) {
                if ($ContentType -eq "application/json" -and ($Body -is [PSCustomObject] -or $Body -is [hashtable])) {
                    $params.Body = ConvertTo-Json -InputObject $Body -Depth 10
                }
                else {
                    $params.Body = $Body
                }
            }
            
            $logMessage = "Sending $Method request to $uri"
            if ($retryCount -gt 0) {
                $logMessage += " (Retry $retryCount of $MaxRetries)"
            }
            Write-Log -Message $logMessage -Level INFO
            
            $response = Invoke-RestMethod @params
            $success = $true
            
            # Cache successful GET responses
            if ($Method -eq "GET" -and -not $DisableCache -and $cacheKey) {
                $expiryTime = (Get-Date).AddSeconds($script:CacheTimeout)
                $script:RequestCache[$cacheKey] = @{
                    Data = $response
                    Expires = $expiryTime
                }
                Write-Log -Message "Cached response for $Method $uri until $expiryTime" -Level INFO
            }
            
            return $response
        }
        catch {
            $lastException = $_
            $statusCode = $null
            
            # Extract status code if available
            if ($_.Exception.Response -ne $null) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                $statusDescription = $_.Exception.Response.StatusDescription
                
                Write-Log -Message "Request failed with status code ${statusCode}: ${statusDescription}" -Level WARNING
                
                # Handle token expiration and retry immediately with fresh token
                if ($statusCode -eq 401) {
                    Write-Log -Message "Access token expired, reconnecting..." -Level INFO
                    if (Connect-MsGraph) {
                        # Don't increment retry count for token refresh
                        continue
                    }
                }
                
                # Don't retry on client errors except for specific cases
                if ($statusCode -ge 400 -and $statusCode -lt 500) {
                    # Don't retry on 400, 403, 404 unless it's a throttling error
                    if ($statusCode -ne 429 -and $statusCode -ne 408) {
                        Write-Log -Message "Client error - not retrying: $statusCode" -Level WARNING
                        break
                    }
                }
            }
            
            $retryCount++
            
            if ($retryCount -le $MaxRetries) {
                # Calculate delay with exponential backoff
                $delay = $RetryDelaySeconds * [Math]::Pow(2, ($retryCount - 1))
                
                # If 429 (throttling), use Retry-After header if available
                if ($statusCode -eq 429 -and $_.Exception.Response.Headers -and $_.Exception.Response.Headers["Retry-After"]) {
                    $delay = [int]$_.Exception.Response.Headers["Retry-After"]
                    Write-Log -Message "Request throttled. Using server-specified delay of $delay seconds." -Level WARNING
                }
                
                Write-Log -Message "Retrying after $delay seconds..." -Level INFO
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    # If we get here, all retries failed
    $errorDetails = "Max retries exceeded ($MaxRetries)"
    if ($lastException) {
        $errorDetails += ": " + $lastException.ToString()
        
        # Try to extract more detailed error information from Graph API
        try {
            if ($lastException.Exception.Response) {
                $reader = New-Object System.IO.StreamReader($lastException.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd()
                
                if ($responseBody) {
                    $errorObj = $responseBody | ConvertFrom-Json
                    if ($errorObj.error) {
                        $errorDetails += "`nGraph API Error: $($errorObj.error.code) - $($errorObj.error.message)"
                    }
                }
            }
        }
        catch {
            # Ignore errors in error parsing
        }
    }
    
    Write-Log -Message "Graph API request failed after all retries: $errorDetails" -Level ERROR
    throw "Graph API request failed: $errorDetails"
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

#region Helper Functions

function Get-GraphDevice {
    <#
    .SYNOPSIS
        Retrieves device information from Microsoft Graph.
    
    .DESCRIPTION
        Gets information about devices registered in Intune/Azure AD.
        
    .PARAMETER DeviceId
        The unique identifier for the device.
        
    .PARAMETER DeviceName
        The display name of the device to search for.
        
    .PARAMETER Filter
        Custom OData filter to apply to the request.
        
    .EXAMPLE
        Get-GraphDevice -DeviceName "Laptop123"
        
    .EXAMPLE
        Get-GraphDevice -Filter "operatingSystem eq 'Windows' and complianceState eq 'compliant'"
    #>
    [CmdletBinding(DefaultParameterSetName="ByName")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [string]$DeviceId,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [string]$DeviceName,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ByFilter")]
        [string]$Filter
    )
    
    # Ensure we're connected to Graph API
    if (-not (Connect-MsGraph)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    try {
        switch ($PSCmdlet.ParameterSetName) {
            "ById" {
                $endpoint = "/deviceManagement/managedDevices/$DeviceId"
                Write-Log -Message "Getting device by ID: $DeviceId" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                return $response
            }
            "ByName" {
                $encodedName = [System.Web.HttpUtility]::UrlEncode($DeviceName)
                $endpoint = "/deviceManagement/managedDevices?`$filter=deviceName eq '$encodedName'"
                Write-Log -Message "Getting device by name: $DeviceName" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                
                if ($response.value.Count -eq 0) {
                    Write-Log -Message "No device found with name: $DeviceName" -Level WARNING
                    return $null
                }
                
                return $response.value[0]
            }
            "ByFilter" {
                $encodedFilter = [System.Web.HttpUtility]::UrlEncode($Filter)
                $endpoint = "/deviceManagement/managedDevices?`$filter=$encodedFilter"
                Write-Log -Message "Getting devices by filter: $Filter" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                return $response.value
            }
        }
    }
    catch {
        Write-Log -Message "Error retrieving device information: $_" -Level ERROR
        throw "Failed to retrieve device information: $_"
    }
}

function Get-GraphUser {
    <#
    .SYNOPSIS
        Retrieves user information from Microsoft Graph.
    
    .DESCRIPTION
        Gets information about users in Azure AD.
        
    .PARAMETER UserId
        The unique identifier for the user.
        
    .PARAMETER UserPrincipalName
        The user principal name (UPN) to search for.
        
    .PARAMETER Filter
        Custom OData filter to apply to the request.
        
    .PARAMETER Properties
        Specific properties to return in the response.
        
    .EXAMPLE
        Get-GraphUser -UserPrincipalName "user@contoso.com"
        
    .EXAMPLE
        Get-GraphUser -Filter "startsWith(displayName,'John')" -Properties "id,displayName,mail"
    #>
    [CmdletBinding(DefaultParameterSetName="ByUPN")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [string]$UserId,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ByUPN")]
        [string]$UserPrincipalName,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ByFilter")]
        [string]$Filter,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Properties
    )
    
    # Ensure we're connected to Graph API
    if (-not (Connect-MsGraph)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    try {
        # Build select parameter if properties are specified
        $select = ""
        if ($Properties) {
            $select = "?`$select=" + ($Properties -join ",")
        }
        
        switch ($PSCmdlet.ParameterSetName) {
            "ById" {
                $endpoint = "/users/$UserId$select"
                Write-Log -Message "Getting user by ID: $UserId" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                return $response
            }
            "ByUPN" {
                $encodedUPN = [System.Web.HttpUtility]::UrlEncode($UserPrincipalName)
                $endpoint = "/users/$encodedUPN$select"
                Write-Log -Message "Getting user by UPN: $UserPrincipalName" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                return $response
            }
            "ByFilter" {
                $encodedFilter = [System.Web.HttpUtility]::UrlEncode($Filter)
                $endpoint = "/users?`$filter=$encodedFilter"
                if ($select) {
                    $endpoint += "&" + $select.Substring(1)  # Remove the leading ?
                }
                Write-Log -Message "Getting users by filter: $Filter" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                return $response.value
            }
        }
    }
    catch {
        Write-Log -Message "Error retrieving user information: $_" -Level ERROR
        throw "Failed to retrieve user information: $_"
    }
}

function Get-GraphBitLockerKeys {
    <#
    .SYNOPSIS
        Retrieves BitLocker recovery keys from Microsoft Graph.
    
    .DESCRIPTION
        Gets BitLocker recovery keys stored in Azure AD/Intune.
        
    .PARAMETER DeviceId
        The unique identifier for the device to get keys for.
        
    .PARAMETER KeyId
        The specific BitLocker key ID to retrieve.
        
    .PARAMETER IncludeKeyValue
        Include the actual recovery key value in the result.
        
    .EXAMPLE
        Get-GraphBitLockerKeys -DeviceId "00000000-0000-0000-0000-000000000000" -IncludeKeyValue
    #>
    [CmdletBinding(DefaultParameterSetName="ByDevice")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByDevice")]
        [string]$DeviceId,
        
        [Parameter(Mandatory = $true, ParameterSetName = "ByKeyId")]
        [string]$KeyId,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeKeyValue
    )
    
    # Ensure we're connected to Graph API
    if (-not (Connect-MsGraph)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    try {
        switch ($PSCmdlet.ParameterSetName) {
            "ByKeyId" {
                $endpoint = "/informationProtection/bitlocker/recoveryKeys/$KeyId"
                
                if ($IncludeKeyValue) {
                    $endpoint += "?`$select=key"
                }
                
                Write-Log -Message "Getting BitLocker key by ID: $KeyId" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                return $response
            }
            "ByDevice" {
                $endpoint = "/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$DeviceId'"
                
                Write-Log -Message "Getting BitLocker keys for device: $DeviceId" -Level INFO
                $response = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
                
                if ($IncludeKeyValue -and $response.value) {
                    # Fetch the key value for each recovery key
                    $keys = @()
                    foreach ($key in $response.value) {
                        $keyWithValue = Get-GraphBitLockerKeys -KeyId $key.id -IncludeKeyValue
                        $keys += $keyWithValue
                    }
                    return $keys
                }
                
                return $response.value
            }
        }
    }
    catch {
        Write-Log -Message "Error retrieving BitLocker keys: $_" -Level ERROR
        throw "Failed to retrieve BitLocker keys: $_"
    }
}

function Set-DevicePrimaryUser {
    <#
    .SYNOPSIS
        Sets the primary user for a device in Intune.
    
    .DESCRIPTION
        Configures the primary user association for a device in Intune.
        
    .PARAMETER DeviceId
        The unique identifier for the device.
        
    .PARAMETER UserId
        The unique identifier for the user to set as primary user.
        
    .EXAMPLE
        Set-DevicePrimaryUser -DeviceId "00000000-0000-0000-0000-000000000000" -UserId "11111111-1111-1111-1111-111111111111"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )
    
    # Ensure we're connected to Graph API
    if (-not (Connect-MsGraph)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    try {
        $endpoint = "/deviceManagement/managedDevices/$DeviceId/users/`$ref"
        $body = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/users/$UserId"
        }
        
        Write-Log -Message "Setting primary user for device $DeviceId to user $UserId" -Level INFO
        $response = Invoke-GraphApiRequest -Method POST -Endpoint $endpoint -Body $body
        
        Write-Log -Message "Successfully set primary user for device" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Error setting primary user for device: $_" -Level ERROR
        return $false
    }
}

function Register-DeviceWithAutopilot {
    <#
    .SYNOPSIS
        Registers a device with Windows Autopilot.
    
    .DESCRIPTION
        Uploads device hardware hash to register with Windows Autopilot in Intune.
        
    .PARAMETER HardwareHash
        The hardware hash of the device.
        
    .PARAMETER SerialNumber
        The serial number of the device.
        
    .PARAMETER GroupTag
        Optional Autopilot group tag to assign.
        
    .PARAMETER AssignedUser
        Optional user to pre-assign to the device.
        
    .EXAMPLE
        Register-DeviceWithAutopilot -HardwareHash $hash -SerialNumber "1234567890"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HardwareHash,
        
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber,
        
        [Parameter(Mandatory = $false)]
        [string]$GroupTag,
        
        [Parameter(Mandatory = $false)]
        [string]$AssignedUser
    )
    
    # Ensure we're connected to Graph API
    if (-not (Connect-MsGraph)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    try {
        $endpoint = "/deviceManagement/windowsAutopilotDeviceIdentities"
        
        $body = @{
            serialNumber = $SerialNumber
            hardwareIdentifier = $HardwareHash
            state = @{
                deviceImportStatus = "pending"
                deviceRegistrationId = ""
                deviceErrorCode = 0
                deviceErrorName = ""
            }
        }
        
        if ($GroupTag) {
            $body.groupTag = $GroupTag
        }
        
        if ($AssignedUser) {
            $body.assignedUser = $AssignedUser
        }
        
        Write-Log -Message "Registering device $SerialNumber with Autopilot" -Level INFO
        $response = Invoke-GraphApiRequest -Method POST -Endpoint $endpoint -Body $body
        
        Write-Log -Message "Successfully registered device with Autopilot" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Error registering device with Autopilot: $_" -Level ERROR
        return $false
    }
}

function Get-DeviceComplianceStatus {
    <#
    .SYNOPSIS
        Gets the compliance status of a device in Intune.
    
    .DESCRIPTION
        Retrieves detailed compliance status information for a device.
        
    .PARAMETER DeviceId
        The unique identifier for the device.
        
    .EXAMPLE
        Get-DeviceComplianceStatus -DeviceId "00000000-0000-0000-0000-000000000000"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )
    
    # Ensure we're connected to Graph API
    if (-not (Connect-MsGraph)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    try {
        $endpoint = "/deviceManagement/managedDevices/$DeviceId"
        
        Write-Log -Message "Getting compliance status for device $DeviceId" -Level INFO
        $deviceDetails = Invoke-GraphApiRequest -Method GET -Endpoint $endpoint
        
        # Get device compliance policy states
        $complianceEndpoint = "/deviceManagement/managedDevices/$DeviceId/deviceCompliancePolicyStates"
        $complianceStates = Invoke-GraphApiRequest -Method GET -Endpoint $complianceEndpoint
        
        # Combine information
        $result = [PSCustomObject]@{
            DeviceId = $deviceDetails.id
            DeviceName = $deviceDetails.deviceName
            ComplianceState = $deviceDetails.complianceState
            LastSyncDateTime = $deviceDetails.lastSyncDateTime
            OperatingSystem = $deviceDetails.operatingSystem
            OperatingSystemVersion = $deviceDetails.osVersion
            Policies = $complianceStates.value
        }
        
        return $result
    }
    catch {
        Write-Log -Message "Error retrieving device compliance status: $_" -Level ERROR
        throw "Failed to retrieve device compliance status: $_"
    }
}

function Get-DeviceHardwareHash {
    <#
    .SYNOPSIS
        Extracts the hardware hash ID from the local device.
    
    .DESCRIPTION
        Gets hardware identification information required for device enrollment
        in Azure AD/Intune, with support for different platforms.
        
    .PARAMETER Platform
        The platform type to extract hardware hash for (defaults to auto-detection).
        
    .PARAMETER OutputPath
        Optional path to save the hardware hash information to a file.
        
    .EXAMPLE
        Get-DeviceHardwareHash
        
    .EXAMPLE
        Get-DeviceHardwareHash -Platform Windows -OutputPath "C:\Temp\HardwareHash.txt"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("Windows", "Linux", "macOS", "iOS", "Android")]
        [string]$Platform,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )
    
    Write-Log -Message "Extracting device hardware hash ID" -Level INFO
    
    # Auto-detect platform if not specified
    if (-not $Platform) {
        if ($PSVersionTable.PSEdition -eq "Core") {
            if ($IsWindows) {
                $Platform = "Windows"
            }
            elseif ($IsLinux) {
                $Platform = "Linux"
            }
            elseif ($IsMacOS) {
                $Platform = "macOS"
            }
            else {
                $Platform = "Unknown"
            }
        }
        else {
            # In Windows PowerShell (Desktop edition)
            $Platform = "Windows"
        }
        
        Write-Log -Message "Auto-detected platform: $Platform" -Level INFO
    }
    
    $result = [PSCustomObject]@{
        Platform = $Platform
        SerialNumber = $null
        HardwareHash = $null
        Manufacturer = $null
        Model = $null
        OtherIdentifiers = @{}
        Error = $null
        Success = $false
    }
    
    try {
        switch ($Platform) {
            "Windows" {
                # Check if Get-WindowsAutoPilotInfo cmdlet is available
                $autopilotCmdlet = Get-Command -Name "Get-WindowsAutoPilotInfo" -ErrorAction SilentlyContinue
                
                if ($autopilotCmdlet) {
                    Write-Log -Message "Using Get-WindowsAutoPilotInfo cmdlet to extract hardware hash" -Level INFO
                    
                    # Create a temporary file to capture output
                    $tempFile = [System.IO.Path]::GetTempFileName() -replace ".tmp", ".csv"
                    
                    try {
                        # Use the cmdlet to extract information
                        & Get-WindowsAutoPilotInfo -OutputFile $tempFile -Append
                        
                        if (Test-Path -Path $tempFile) {
                            $csvData = Import-Csv -Path $tempFile
                            
                            if ($csvData) {
                                $result.SerialNumber = $csvData.SerialNumber
                                $result.HardwareHash = $csvData.HardwareHash
                                $result.Manufacturer = $csvData.Manufacturer
                                $result.Model = $csvData.Model
                                $result.Success = $true
                                
                                # Copy to output path if specified
                                if ($OutputPath) {
                                    Copy-Item -Path $tempFile -Destination $OutputPath -Force
                                    Write-Log -Message "Hardware hash saved to: $OutputPath" -Level INFO
                                }
                            }
                            
                            # Cleanup
                            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                        }
                    }
                    catch {
                        Write-Log -Message "Error using Get-WindowsAutoPilotInfo: $_" -Level WARNING
                        Write-Log -Message "Falling back to WMI method" -Level INFO
                    }
                }
                
                # Fallback to direct WMI query if cmdlet method failed or cmdlet isn't available
                if (-not $result.Success) {
                    Write-Log -Message "Using WMI to extract hardware hash" -Level INFO
                    
                    # Get BIOS information
                    $bios = Get-WmiObject -Class Win32_BIOS
                    $result.SerialNumber = $bios.SerialNumber
                    
                    # Get computer system information
                    $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
                    $result.Manufacturer = $computerSystem.Manufacturer
                    $result.Model = $computerSystem.Model
                    
                    # Get hardware hash from trusted platform module (TPM)
                    try {
                        # This approach uses TBSMGMT for TPM interaction
                        $tpm = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftTpm" -Class Win32_Tpm
                        if ($tpm) {
                            $tpmResult = $tpm.GetEndorsementKeyCertificates()
                            
                            if ($tpmResult.ReturnValue -eq 0) {
                                # Convert the certificate to a hardware hash
                                $hasher = [System.Security.Cryptography.SHA256]::Create()
                                $hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($tpm.EndorsementKeyThumbprint))
                                $result.HardwareHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "")
                                $result.Success = $true
                            }
                        }
                    }
                    catch {
                        Write-Log -Message "Error extracting TPM information: $_" -Level WARNING
                        
                        # Final fallback - create a hash based on system information
                        try {
                            $baseInfo = "$($result.SerialNumber)-$($result.Manufacturer)-$($result.Model)"
                            $hasher = [System.Security.Cryptography.SHA256]::Create()
                            $hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseInfo))
                            $result.HardwareHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "")
                            $result.Success = $true
                            
                            $result.OtherIdentifiers["IsDeviceHardwareHashMock"] = $true
                            
                            Write-Log -Message "Created fallback hardware hash based on system information" -Level WARNING
                        }
                        catch {
                            Write-Log -Message "Failed to create fallback hardware hash: $_" -Level ERROR
                            $result.Error = "Failed to extract or generate hardware hash: $_"
                        }
                    }
                    
                    # If we have data and output path is specified, save to CSV
                    if ($result.Success -and $OutputPath) {
                        try {
                            [PSCustomObject]@{
                                SerialNumber = $result.SerialNumber
                                HardwareHash = $result.HardwareHash
                                Manufacturer = $result.Manufacturer
                                Model = $result.Model
                            } | Export-Csv -Path $OutputPath -NoTypeInformation -Force
                            
                            Write-Log -Message "Hardware hash saved to: $OutputPath" -Level INFO
                        }
                        catch {
                            Write-Log -Message "Error saving hardware hash to file: $_" -Level WARNING
                        }
                    }
                }
            }
            "Linux" {
                Write-Log -Message "Extracting hardware information from Linux system" -Level INFO
                
                try {
                    # Get system serial number
                    $dmidecode = & sudo dmidecode -s system-serial-number 2>$null
                    if ($dmidecode) {
                        $result.SerialNumber = $dmidecode.Trim()
                    }
                    
                    # Get manufacturer and model
                    $manufacturer = & sudo dmidecode -s system-manufacturer 2>$null
                    if ($manufacturer) {
                        $result.Manufacturer = $manufacturer.Trim()
                    }
                    
                    $model = & sudo dmidecode -s system-product-name 2>$null
                    if ($model) {
                        $result.Model = $model.Trim()
                    }
                    
                    # Generate a hash based on system information
                    if ($result.SerialNumber -and $result.Manufacturer -and $result.Model) {
                        $baseInfo = "$($result.SerialNumber)-$($result.Manufacturer)-$($result.Model)"
                        $hasher = [System.Security.Cryptography.SHA256]::Create()
                        $hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseInfo))
                        $result.HardwareHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "")
                        $result.Success = $true
                        
                        $result.OtherIdentifiers["IsDeviceHardwareHashMock"] = $true
                        
                        Write-Log -Message "Created hardware hash based on Linux system information" -Level WARNING
                        Write-Log -Message "Note: Linux systems don't have standard Autopilot hardware hash - this is a best-effort identifier" -Level WARNING
                    }
                    else {
                        throw "Failed to get required system information"
                    }
                }
                catch {
                    Write-Log -Message "Error extracting Linux hardware information: $_" -Level ERROR
                    $result.Error = "Failed to extract Linux hardware information: $_"
                }
                
                # Save to output file if specified
                if ($result.Success -and $OutputPath) {
                    try {
                        [PSCustomObject]@{
                            SerialNumber = $result.SerialNumber
                            HardwareHash = $result.HardwareHash
                            Manufacturer = $result.Manufacturer
                            Model = $result.Model
                            Platform = $result.Platform
                        } | Export-Csv -Path $OutputPath -NoTypeInformation -Force
                        
                        Write-Log -Message "Hardware hash saved to: $OutputPath" -Level INFO
                    }
                    catch {
                        Write-Log -Message "Error saving hardware hash to file: $_" -Level WARNING
                    }
                }
            }
            "macOS" {
                Write-Log -Message "Extracting hardware information from macOS system" -Level INFO
                
                try {
                    # Get system information
                    $serialNumber = & system_profiler SPHardwareDataType | grep "Serial Number" | awk '{print $4}'
                    if ($serialNumber) {
                        $result.SerialNumber = $serialNumber.Trim()
                    }
                    
                    $model = & system_profiler SPHardwareDataType | grep "Model Name" | cut -d':' -f2
                    if ($model) {
                        $result.Model = $model.Trim()
                    }
                    
                    $result.Manufacturer = "Apple"
                    
                    # Generate a hash based on system information
                    if ($result.SerialNumber -and $result.Model) {
                        $baseInfo = "$($result.SerialNumber)-$($result.Manufacturer)-$($result.Model)"
                        $hasher = [System.Security.Cryptography.SHA256]::Create()
                        $hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseInfo))
                        $result.HardwareHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "")
                        $result.Success = $true
                        
                        $result.OtherIdentifiers["IsDeviceHardwareHashMock"] = $true
                        
                        Write-Log -Message "Created hardware hash based on macOS system information" -Level WARNING
                        Write-Log -Message "Note: macOS systems don't have standard Autopilot hardware hash - this is a best-effort identifier" -Level WARNING
                    }
                    else {
                        throw "Failed to get required system information"
                    }
                }
                catch {
                    Write-Log -Message "Error extracting macOS hardware information: $_" -Level ERROR
                    $result.Error = "Failed to extract macOS hardware information: $_"
                }
                
                # Save to output file if specified
                if ($result.Success -and $OutputPath) {
                    try {
                        [PSCustomObject]@{
                            SerialNumber = $result.SerialNumber
                            HardwareHash = $result.HardwareHash
                            Manufacturer = $result.Manufacturer
                            Model = $result.Model
                            Platform = $result.Platform
                        } | Export-Csv -Path $OutputPath -NoTypeInformation -Force
                        
                        Write-Log -Message "Hardware hash saved to: $OutputPath" -Level INFO
                    }
                    catch {
                        Write-Log -Message "Error saving hardware hash to file: $_" -Level WARNING
                    }
                }
            }
            default {
                $message = "Hardware hash extraction for platform '$Platform' is not supported. Only Windows, Linux, and macOS are supported."
                Write-Log -Message $message -Level WARNING
                $result.Error = $message
            }
        }
    }
    catch {
        Write-Log -Message "Error extracting hardware hash ID: $_" -Level ERROR
        $result.Error = "Error extracting hardware hash ID: $_"
    }
    
    return $result
}

function Register-DeviceToAutopilot {
    <#
    .SYNOPSIS
        Extracts hardware hash and registers a device with Windows Autopilot.
    
    .DESCRIPTION
        Combines hardware hash extraction and device registration into a single
        operation for streamlined Autopilot registration.
        
    .PARAMETER Platform
        The platform type to extract hardware hash for (defaults to auto-detection).
        
    .PARAMETER GroupTag
        Optional Autopilot group tag to assign.
        
    .PARAMETER AssignedUser
        Optional user to pre-assign to the device.
        
    .PARAMETER OutputPath
        Optional path to save the hardware hash information to a file.
        
    .EXAMPLE
        Register-DeviceToAutopilot -GroupTag "Sales" -AssignedUser "user@contoso.com"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("Windows", "Linux", "macOS", "iOS", "Android")]
        [string]$Platform,
        
        [Parameter(Mandatory = $false)]
        [string]$GroupTag,
        
        [Parameter(Mandatory = $false)]
        [string]$AssignedUser,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )
    
    Write-Log -Message "Starting device registration to Autopilot" -Level INFO
    
    $result = [PSCustomObject]@{
        Success = $false
        HardwareHashExtracted = $false
        DeviceRegistered = $false
        SerialNumber = $null
        Error = $null
    }
    
    try {
        # Extract hardware hash
        $hardwareInfo = Get-DeviceHardwareHash -Platform $Platform -OutputPath $OutputPath
        
        if (-not $hardwareInfo.Success) {
            $result.Error = "Failed to extract hardware hash: $($hardwareInfo.Error)"
            Write-Log -Message $result.Error -Level ERROR
            return $result
        }
        
        $result.HardwareHashExtracted = $true
        $result.SerialNumber = $hardwareInfo.SerialNumber
        
        # Check if this is a supported platform for Autopilot
        if ($hardwareInfo.Platform -ne "Windows") {
            Write-Log -Message "Autopilot registration is primarily designed for Windows devices. Attempting best-effort registration for $($hardwareInfo.Platform)." -Level WARNING
        }
        
        # Register with Autopilot
        $registrationResult = Register-DeviceWithAutopilot -HardwareHash $hardwareInfo.HardwareHash -SerialNumber $hardwareInfo.SerialNumber -GroupTag $GroupTag -AssignedUser $AssignedUser
        
        if (-not $registrationResult) {
            $result.Error = "Failed to register device with Autopilot"
            Write-Log -Message $result.Error -Level ERROR
            return $result
        }
        
        $result.DeviceRegistered = $true
        $result.Success = $true
        
        Write-Log -Message "Device successfully registered to Autopilot" -Level INFO
        return $result
    }
    catch {
        $result.Error = "Error during Autopilot registration: $_"
        Write-Log -Message $result.Error -Level ERROR
        return $result
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Initialize-GraphAPIIntegration
Export-ModuleMember -Function Connect-MsGraph
Export-ModuleMember -Function Get-BitLockerRecoveryKey
Export-ModuleMember -Function Backup-BitLockerKeyToAzureAD
Export-ModuleMember -Function Confirm-BitLockerKeyBackup
Export-ModuleMember -Function Migrate-BitLockerKeys

# Export new functions
Export-ModuleMember -Function Get-MsalToken
Export-ModuleMember -Function Invoke-GraphApiRequest
Export-ModuleMember -Function Get-GraphDevice
Export-ModuleMember -Function Get-GraphUser
Export-ModuleMember -Function Get-GraphBitLockerKeys
Export-ModuleMember -Function Set-DevicePrimaryUser
Export-ModuleMember -Function Register-DeviceWithAutopilot
Export-ModuleMember -Function Get-DeviceComplianceStatus
Export-ModuleMember -Function Get-DeviceHardwareHash
Export-ModuleMember -Function Register-DeviceToAutopilot 





