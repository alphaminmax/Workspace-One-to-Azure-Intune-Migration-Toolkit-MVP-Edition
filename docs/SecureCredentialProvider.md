![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Secure Credential Provider

## Overview

The SecureCredentialProvider module provides a unified interface for securely storing, managing, and retrieving credentials throughout the Workspace ONE to Azure/Intune Migration Toolkit. This module supports multiple storage backends including Azure Key Vault, encrypted files, and environment variables.

## Key Features

- **Multiple Backend Support**: Store credentials in Azure Key Vault, encrypted files, or environment variables
- **Transparent Access**: Access credentials with a consistent API regardless of storage location
- **Fallback Mechanisms**: Configure prioritized fallback between storage methods
- **Secure by Default**: All credentials stored using Windows Data Protection API when using local storage
- **Integration**: Seamless integration with SecurityFoundation and GraphAPIIntegration modules

## Module Functions

### Initialize-CredentialProvider

Initializes the credential provider with specified configuration settings.

#### Parameters

- **KeyVaultName** *(String)*: Optional. The name of the Azure Key Vault to use for credential storage
- **KeyVaultApplicationId** *(String)*: Optional. The application ID for Azure Key Vault authentication
- **UseManagedIdentity** *(Boolean)*: Optional. Indicates whether to use managed identity for Key Vault authentication
- **LocalStoragePath** *(String)*: Optional. Path to use for local credential storage
- **EncryptionCertificateThumbprint** *(String)*: Optional. Thumbprint of the certificate to use for local storage encryption

#### Example

```powershell
# Initialize with Key Vault
Initialize-CredentialProvider -KeyVaultName "MyMigrationKeyVault" -UseManagedIdentity $true

# Initialize with local storage
Initialize-CredentialProvider -LocalStoragePath "C:\MigrationData\Credentials"
```

### Set-CredentialProviderConfig

Updates the configuration for the credential provider.

#### Parameters

- **UseKeyVault** *(Boolean)*: Optional. Whether to use Azure Key Vault for credential storage
- **KeyVaultName** *(String)*: Optional. The name of the Azure Key Vault
- **UseEnvironmentVariables** *(Boolean)*: Optional. Whether to use environment variables for credential storage
- **UseLocalStorage** *(Boolean)*: Optional. Whether to use encrypted local storage for credentials
- **LocalStoragePath** *(String)*: Optional. Path for local credential storage

#### Example

```powershell
# Configure multiple storage backends with priority
Set-CredentialProviderConfig -UseKeyVault $true `
                            -KeyVaultName "MyMigrationKeyVault" `
                            -UseEnvironmentVariables $true `
                            -UseLocalStorage $true `
                            -LocalStoragePath "C:\MigrationData\Credentials"
```

### Get-SecureCredential

Retrieves a credential from the configured storage location.

#### Parameters

- **Name** *(String)*: Required. The name of the credential to retrieve
- **Source** *(String)*: Optional. Specifies the source to retrieve from: "KeyVault", "Environment", "LocalStorage"
- **UseFallback** *(Boolean)*: Optional. Whether to try alternative sources if the primary source fails
- **DefaultCredential** *(PSCredential)*: Optional. A default credential to return if not found in any source

#### Example

```powershell
# Get credential with fallback
$credential = Get-SecureCredential -Name "WorkspaceOneAdmin" -UseFallback $true

# Get credential from a specific source
$credential = Get-SecureCredential -Name "IntuneAdmin" -Source "KeyVault"
```

### Set-SecureCredential

Stores a credential in the specified location.

#### Parameters

- **Name** *(String)*: Required. The name to associate with the credential
- **Credential** *(PSCredential)*: Required. The credential to store
- **Target** *(String)*: Optional. Where to store the credential: "KeyVault", "Environment", "LocalStorage"

#### Example

```powershell
# Create a credential
$password = ConvertTo-SecureString "Password123!" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("admin@contoso.com", $password)

# Store the credential
Set-SecureCredential -Name "TenantAdmin" -Credential $credential -Target "KeyVault"
```

### Remove-SecureCredential

Removes a credential from storage.

#### Parameters

- **Name** *(String)*: Required. The name of the credential to remove
- **Target** *(String)*: Optional. The storage target to remove from

#### Example

```powershell
# Remove a credential from all storage locations
Remove-SecureCredential -Name "LegacyCredential"

# Remove a credential from a specific location
Remove-SecureCredential -Name "TempCredential" -Target "LocalStorage"
```

### Test-CredentialProvider

Tests the credential provider configuration and access to configured storage locations.

#### Parameters

- **TestKeyVault** *(Boolean)*: Optional. Whether to test Key Vault access
- **TestLocalStorage** *(Boolean)*: Optional. Whether to test local storage access
- **Detailed** *(Boolean)*: Optional. Whether to return detailed test results

#### Example

```powershell
# Test all configured storage backends
$testResults = Test-CredentialProvider -Detailed $true

# Test a specific backend
Test-CredentialProvider -TestKeyVault $true
```

## Integration with Other Modules

### SecurityFoundation Integration

```powershell
# SecurityFoundation uses SecureCredentialProvider internally
Import-Module "src/modules/SecurityFoundation.psm1"
Initialize-SecurityFoundation -KeyVaultName "MyMigrationKeyVault"

# Now credentials are managed through SecurityFoundation
$encryptionCert = Get-EncryptionCertificate 
```

### GraphAPIIntegration Integration

```powershell
# GraphAPIIntegration uses SecureCredentialProvider for storing tokens
Import-Module "src/modules/GraphAPIIntegration.psm1"
Initialize-GraphAPIConnection -TenantId "contoso.onmicrosoft.com" -UseKeyVault $true

# Authentication tokens managed securely behind the scenes
Invoke-GraphApiRequest -Endpoint "/users" -Method "GET"
```

## Storage Methods Comparison

| Feature | Azure Key Vault | Local Encrypted Storage | Environment Variables |
|---------|----------------|------------------------|----------------------|
| Security Level | Highest | High | Medium |
| Persistence | Yes | Yes | Session only |
| Shared Access | Yes | No | No |
| Audit Trail | Yes | Limited | No |
| Internet Required | Yes | No | No |
| Setup Complexity | Medium | Low | Low |

## Security Best Practices

1. **Prefer Key Vault**: Use Azure Key Vault for production environments when possible
2. **Clean Up Credentials**: Remove credentials when they are no longer needed
3. **Local Encryption**: Always use certificate-based encryption for local storage
4. **Avoid Hard Coding**: Never hardcode credentials in scripts or configuration files
5. **Audit Usage**: Regularly review credential access logs

## Error Handling

The module implements robust error handling for credential operations:

```powershell
try {
    $credential = Get-SecureCredential -Name "WorkspaceOneAdmin" -ErrorAction Stop
    # Use the credential
}
catch [CredentialNotFoundException] {
    Write-Log -Level Error "Credential not found. Please ensure it has been properly stored."
    # Prompt for credential or handle the error
}
catch {
    Write-Log -Level Error "An error occurred while retrieving the credential: $_"
    # Handle other errors
}
```

## Related Documentation

- [Key Vault Integration Guide](./KeyVaultIntegration.md)
- [Security Foundation Module](./SecurityFoundation.md)
- [Graph API Integration](./GraphAPIIntegration.md)
- [User Communication Framework](./UserCommunicationFramework.md) 
