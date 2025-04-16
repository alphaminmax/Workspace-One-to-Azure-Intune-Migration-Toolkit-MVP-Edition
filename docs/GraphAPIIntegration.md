# Graph API Integration Module

## Overview

The GraphAPIIntegration module provides a comprehensive interface for interacting with Microsoft Graph API within the migration toolkit. It enables the migration process to access and manage Azure AD and Microsoft Intune resources, with specific focus on BitLocker recovery key migration and device management operations.

## Key Features

- **Simplified Authentication**: Streamlined authentication to Microsoft Graph API using modern authentication methods
- **BitLocker Recovery Key Management**: Extract and migrate BitLocker keys to Azure AD
- **Request Caching**: Efficient caching mechanism to reduce API calls and improve performance
- **Retry Logic**: Built-in retry capability for handling transient API failures
- **Error Handling**: Comprehensive error management with detailed logging
- **Device Management**: Functions for retrieving and managing device information
- **User Management**: Functions for retrieving user information and relationships

## Prerequisites

- PowerShell 5.1 or higher
- The following PowerShell modules:
  - Microsoft.Graph.Intune
  - MSAL.PS
  - Microsoft.Graph.Authentication
- Network connectivity to Microsoft Graph endpoints
- Appropriate permissions configured in Azure AD

## Module Functions

### Core Authentication Functions

#### Initialize-GraphApiIntegration
Initializes the Graph API integration module with required configuration.

**Parameters:**
- `ClientId` (String): The Azure AD application client ID
- `TenantId` (String): The Azure AD tenant ID
- `ClientSecret` (SecureString): The client secret for the application, if using app authentication
- `CertificateThumbprint` (String): The certificate thumbprint for certificate-based authentication
- `UseUserAuth` (Boolean): Whether to use interactive user authentication instead of service principal
- `ApiVersion` (String): The Graph API version to use (default: "v1.0")
- `CacheLocation` (String): The location to store the authentication cache

**Example:**
```powershell
# Initialize with client secret authentication
Initialize-GraphApiIntegration -ClientId "12345678-abcd-1234-efgh-1234567890ab" `
                              -TenantId "87654321-abcd-1234-efgh-1234567890ab" `
                              -ClientSecret $secureClientSecret `
                              -ApiVersion "v1.0"

# Initialize with certificate authentication
Initialize-GraphApiIntegration -ClientId "12345678-abcd-1234-efgh-1234567890ab" `
                              -TenantId "87654321-abcd-1234-efgh-1234567890ab" `
                              -CertificateThumbprint "ABCDEF1234567890ABCDEF1234567890ABCDEF12" `
                              -ApiVersion "v1.0"

# Initialize with user authentication
Initialize-GraphApiIntegration -UseUserAuth $true `
                              -TenantId "87654321-abcd-1234-efgh-1234567890ab"
```

#### Get-GraphApiAuthToken
Obtains an authentication token for Microsoft Graph API.

**Parameters:**
- `TokenCache` (PSObject): Optional parameter to pass an existing token cache
- `Force` (Boolean): Forces a new token to be obtained, ignoring any cached token

**Example:**
```powershell
$token = Get-GraphApiAuthToken
$token = Get-GraphApiAuthToken -Force $true
```

#### Connect-MicrosoftGraph
Establishes a connection to Microsoft Graph API.

**Parameters:**
- `Token` (PSObject): The authentication token object
- `ApiVersion` (String): The API version to connect to (default: "v1.0")

**Example:**
```powershell
Connect-MicrosoftGraph -Token $token -ApiVersion "beta"
```

### API Request Functions

#### Invoke-GraphApiRequest
Makes a request to the Microsoft Graph API.

**Parameters:**
- `Method` (String): The HTTP method to use (GET, POST, PATCH, DELETE)
- `Endpoint` (String): The API endpoint to call
- `Body` (PSObject): The request body for POST/PATCH requests
- `ContentType` (String): The content type for the request
- `Headers` (Hashtable): Additional headers to include
- `MaxRetries` (Int): Maximum number of retry attempts
- `UseCache` (Boolean): Whether to use request caching

**Example:**
```powershell
# Get all users
$users = Invoke-GraphApiRequest -Method "GET" -Endpoint "/users"

# Create a new group
$groupBody = @{
    displayName = "Migration Group"
    mailEnabled = $false
    securityEnabled = $true
    mailNickname = "migrationgroup"
}
$newGroup = Invoke-GraphApiRequest -Method "POST" -Endpoint "/groups" -Body $groupBody -ContentType "application/json"
```

### BitLocker Functions

#### Get-BitLockerRecoveryKey
Retrieves BitLocker recovery keys from the local system.

**Parameters:**
- `VolumeType` (String): Filter for specific volume types ("OperatingSystem", "Fixed", "Removable", "All")
- `IncludeDetails` (Boolean): Whether to include detailed volume information

**Example:**
```powershell
# Get all BitLocker keys
$allKeys = Get-BitLockerRecoveryKey

# Get only OS volume keys with details
$osKeys = Get-BitLockerRecoveryKey -VolumeType "OperatingSystem" -IncludeDetails $true
```

#### Backup-BitLockerKeyToAzureAD
Backs up a BitLocker recovery key to Azure AD.

**Parameters:**
- `RecoveryKey` (String): The BitLocker recovery key
- `KeyId` (String): The BitLocker key ID
- `DeviceId` (String): The Azure AD device ID
- `VolumeType` (String): The type of volume the key is for

**Example:**
```powershell
Backup-BitLockerKeyToAzureAD -RecoveryKey "123456-123456-123456-123456-123456-123456-123456-123456" `
                             -KeyId "00000000-0000-0000-0000-000000000000" `
                             -DeviceId $azureDeviceId `
                             -VolumeType "OperatingSystem"
```

#### Confirm-BitLockerKeyBackup
Confirms that a BitLocker key was successfully backed up to Azure AD.

**Parameters:**
- `KeyId` (String): The BitLocker key ID
- `DeviceId` (String): The Azure AD device ID

**Example:**
```powershell
$backupSuccess = Confirm-BitLockerKeyBackup -KeyId "00000000-0000-0000-0000-000000000000" -DeviceId $azureDeviceId
```

#### Migrate-BitLockerKeys
Migrates BitLocker recovery keys from the local system to Azure AD.

**Parameters:**
- `DeviceId` (String): The Azure AD device ID
- `VolumeTypes` (Array): Array of volume types to migrate keys for
- `ValidateBackup` (Boolean): Whether to validate the backup was successful

**Example:**
```powershell
# Migrate all keys
$migrationResult = Migrate-BitLockerKeys -DeviceId $azureDeviceId -ValidateBackup $true

# Migrate only OS volume keys
$migrationResult = Migrate-BitLockerKeys -DeviceId $azureDeviceId -VolumeTypes @("OperatingSystem") -ValidateBackup $true
```

### Device Management Functions

#### Get-AzureADDeviceId
Retrieves the Azure AD device ID for the current device.

**Example:**
```powershell
$deviceId = Get-AzureADDeviceId
```

#### Get-DeviceInformation
Retrieves device information from Microsoft Graph API.

**Parameters:**
- `DeviceId` (String): The Azure AD device ID
- `IncludeDetails` (Boolean): Whether to include additional device details

**Example:**
```powershell
$deviceInfo = Get-DeviceInformation -DeviceId $deviceId -IncludeDetails $true
```

### User Management Functions

#### Get-AzureADUserId
Retrieves the Azure AD user ID for the specified user.

**Parameters:**
- `UserPrincipalName` (String): The user principal name
- `Email` (String): The user's email address

**Example:**
```powershell
$userId = Get-AzureADUserId -UserPrincipalName "user@example.com"
$userId = Get-AzureADUserId -Email "user@example.com"
```

#### Get-UserInformation
Retrieves user information from Microsoft Graph API.

**Parameters:**
- `UserId` (String): The Azure AD user ID
- `IncludeDetails` (Boolean): Whether to include additional user details

**Example:**
```powershell
$userInfo = Get-UserInformation -UserId $userId -IncludeDetails $true
```

## Integration with Other Modules

### SecurityFoundation Integration

The GraphAPIIntegration module works closely with the SecurityFoundation module for secure credential management:

```powershell
# Import required modules
Import-Module "src\modules\SecurityFoundation.psm1"
Import-Module "src\modules\GraphAPIIntegration.psm1"

# Initialize security foundation
Initialize-SecurityFoundation -UseKeyVault $true -KeyVaultName "MigrationKeyVault"

# Retrieve credentials securely
$clientSecret = Get-AzureKeyVaultSecret -SecretName "GraphApiClientSecret"

# Initialize Graph API integration with secure credentials
Initialize-GraphApiIntegration -ClientId $clientId -TenantId $tenantId -ClientSecret $clientSecret
```

### SecureCredentialProvider Integration

The module can also leverage the SecureCredentialProvider for credential management:

```powershell
# Import required modules
Import-Module "src\modules\SecureCredentialProvider.psm1"
Import-Module "src\modules\GraphAPIIntegration.psm1"

# Initialize credential provider
Initialize-CredentialProvider -KeyVaultName "MigrationKeyVault"

# Retrieve credentials
$clientId = Get-SecureCredential -Name "GraphApiClientId" -AsPlainText
$clientSecret = Get-SecureCredential -Name "GraphApiClientSecret"

# Initialize Graph API
Initialize-GraphApiIntegration -ClientId $clientId -TenantId $tenantId -ClientSecret $clientSecret
```

## BitLocker Key Migration Process

The BitLocker key migration process follows these steps:

1. **Identify BitLocker-protected volumes**:
   ```powershell
   $bitlockerVolumes = Get-BitLockerRecoveryKey -IncludeDetails $true
   ```

2. **Get Azure AD device ID**:
   ```powershell
   $deviceId = Get-AzureADDeviceId
   ```

3. **Migrate keys to Azure AD**:
   ```powershell
   $migrationResult = Migrate-BitLockerKeys -DeviceId $deviceId -ValidateBackup $true
   ```

4. **Verify migration success**:
   ```powershell
   if ($migrationResult.Success) {
       Write-Host "BitLocker keys successfully migrated to Azure AD"
   } else {
       Write-Error "BitLocker key migration failed"
       foreach ($error in $migrationResult.Errors) {
           Write-Error $error
       }
   }
   ```

## Error Handling

The module includes comprehensive error handling with detailed logging:

```powershell
try {
    $result = Migrate-BitLockerKeys -DeviceId $deviceId -ValidateBackup $true
    if (-not $result.Success) {
        throw "BitLocker key migration failed: $($result.Errors -join '; ')"
    }
} catch {
    Write-Error "An error occurred during BitLocker key migration: $_"
    Write-Log -Level "ERROR" -Message "BitLocker key migration failed: $_" -Source "GraphAPIIntegration"
    # Implement fallback or recovery mechanism
}
```

## Best Practices

1. **Use application permissions with certificates** for non-interactive scenarios
2. **Implement caching** to reduce API calls and improve performance
3. **Include proper error handling** for all API operations
4. **Validate successful operations** especially for critical functions like BitLocker key backup
5. **Monitor API usage** to stay within service limits
6. **Use managed identities** when running in Azure environments
7. **Follow least privilege principle** when configuring application permissions

## Troubleshooting

Common issues and their resolutions:

1. **Authentication failures**:
   - Verify client ID, tenant ID, and client secret/certificate
   - Check that the application has appropriate permissions
   - Ensure the certificate is valid and accessible

2. **API permission issues**:
   - Verify the application has been granted the required permissions
   - Check for admin consent if required
   - Review Azure AD application permission configuration

3. **BitLocker key backup failures**:
   - Ensure the device is properly registered in Azure AD
   - Verify the user has appropriate permissions
   - Check BitLocker status on the volume

4. **Request throttling**:
   - Implement exponential backoff in retry logic
   - Reduce unnecessary API calls
   - Use batch requests where possible

5. **Network connectivity issues**:
   - Verify connectivity to Graph API endpoints
   - Check proxy settings if applicable
   - Review firewall configurations

## Module Dependencies

- Microsoft.Graph.Intune
- MSAL.PS
- Microsoft.Graph.Authentication 
- SecurityFoundation.psm1 (optional, for secure credential management)
- SecureCredentialProvider.psm1 (optional, for credential retrieval)
- LoggingModule.psm1 (for consistent logging)

## Example - Full BitLocker Migration Script

```powershell
# Import required modules
Import-Module "src\modules\GraphAPIIntegration.psm1"
Import-Module "src\modules\LoggingModule.psm1"
Import-Module "src\modules\SecureCredentialProvider.psm1"

# Initialize modules
Initialize-Logging -LogPath "C:\Temp\Logs\BitLockerMigration.log" -LogLevel "VERBOSE"
Initialize-CredentialProvider -KeyVaultName "MigrationKeyVault"

# Get credentials
$clientId = Get-SecureCredential -Name "GraphApiClientId" -AsPlainText
$clientSecret = Get-SecureCredential -Name "GraphApiClientSecret"
$tenantId = Get-SecureCredential -Name "AzureTenantId" -AsPlainText

# Initialize Graph API
Initialize-GraphApiIntegration -ClientId $clientId -TenantId $tenantId -ClientSecret $clientSecret

# Connect to Graph API
$token = Get-GraphApiAuthToken
Connect-MicrosoftGraph -Token $token

# Get device ID
$deviceId = Get-AzureADDeviceId
if (-not $deviceId) {
    Write-Log -Level "ERROR" -Message "Device not registered in Azure AD" -Source "BitLockerMigration"
    exit 1
}

# Migrate BitLocker keys
$migrationParams = @{
    DeviceId = $deviceId
    VolumeTypes = @("OperatingSystem", "Fixed")
    ValidateBackup = $true
}

$result = Migrate-BitLockerKeys @migrationParams

# Generate report
$report = @{
    Timestamp = Get-Date
    DeviceId = $deviceId
    Success = $result.Success
    KeysMigrated = $result.MigratedKeys.Count
    Errors = $result.Errors
}

# Write results
Write-Log -Level "INFO" -Message "BitLocker migration completed with status: $($result.Success)" -Source "BitLockerMigration"
Write-Log -Level "INFO" -Message "Keys migrated: $($result.MigratedKeys.Count)" -Source "BitLockerMigration"

if (-not $result.Success) {
    foreach ($error in $result.Errors) {
        Write-Log -Level "ERROR" -Message $error -Source "BitLockerMigration"
    }
}

# Output report
$report | ConvertTo-Json | Out-File "C:\Temp\Logs\BitLockerMigrationReport.json"
``` 