![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Azure Key Vault Integration

## Overview

This documentation covers the integration of Azure Key Vault with the Workspace ONE to Azure/Intune Migration Toolkit. Key Vault provides secure storage for credentials, certificates, and other secrets used during the migration process.

## Key Features

- **Secure Credential Storage**: Store Workspace ONE and Microsoft tenant credentials securely
- **Certificate Management**: Generate, store, and retrieve certificates used for encryption
- **Secret Management**: Secure storage for API keys, tokens, and other sensitive data
- **Azure AD Integration**: Authentication using managed identities or service principals
- **Audit Logging**: Comprehensive tracking of all secret access and modifications

## Setup Requirements

### Prerequisites

- An Azure subscription
- Permissions to create and manage Key Vault resources
- Az PowerShell modules installed:
  ```powershell
  Install-Module -Name Az.Accounts, Az.KeyVault -Force
  ```

### Creating a Key Vault

If you don't already have a Key Vault, create one using Azure Portal or PowerShell:

```powershell
# Login to Azure
Connect-AzAccount

# Create a resource group (if needed)
New-AzResourceGroup -Name "MigrationResourceGroup" -Location "East US"

# Create a Key Vault
New-AzKeyVault -Name "MyMigrationKeyVault" -ResourceGroupName "MigrationResourceGroup" -Location "East US" -Sku "Standard"
```

### Configuring Access Policies

Grant appropriate permissions to the account that will be running the migration:

```powershell
# Get the user's object ID
$userObjectId = (Get-AzADUser -UserPrincipalName "user@domain.com").Id

# Set access policy
Set-AzKeyVaultAccessPolicy -VaultName "MyMigrationKeyVault" -ObjectId $userObjectId -PermissionsToSecrets Get,List,Set,Delete -PermissionsToCertificates Get,List,Create,Delete
```

## Configuration

Update your `config/settings.json` file to include Key Vault settings:

```json
{
  "keyVault": {
    "enabled": true,
    "name": "MyMigrationKeyVault",
    "useAzureIdentity": true
  }
}
```

## Usage in the Migration Toolkit

### SecureCredentialProvider Module

The SecureCredentialProvider module integrates with Key Vault to securely manage credentials:

```powershell
# Initialize the credential provider
Initialize-CredentialProvider -KeyVaultName "MyMigrationKeyVault"

# Store a credential
$cred = Get-Credential -Message "Enter Workspace ONE admin credentials"
Set-SecureCredential -Name "WorkspaceOneAdmin" -Credential $cred

# Retrieve a credential
$wsOneCred = Get-SecureCredential -Name "WorkspaceOneAdmin"
```

### SecurityFoundation Module

The SecurityFoundation module uses Key Vault for encryption certificates and security operations:

```powershell
# Initialize the security foundation
Initialize-SecurityFoundation -KeyVaultName "MyMigrationKeyVault"

# Get an encryption certificate
$cert = Get-EncryptionCertificate

# Encrypt sensitive data
$encryptedData = Protect-SensitiveData -Data "sensitive information" -Certificate $cert

# Decrypt sensitive data
$decryptedData = Unprotect-SensitiveData -EncryptedData $encryptedData -Certificate $cert
```

### GraphAPIIntegration Module

The GraphAPIIntegration module uses Key Vault to securely store and retrieve auth tokens:

```powershell
# Initialize Graph API with Key Vault integration
Initialize-GraphAPIConnection -UseKeyVault $true -KeyVaultName "MyMigrationKeyVault"

# Get and use access token (retrieved securely from Key Vault)
$graphData = Invoke-GraphAPIRequest -Endpoint "/users" -Method "GET"
```

## Testing Key Vault Integration

Use the provided test script to validate Key Vault integration:

```powershell
.\src\scripts\Test-KeyVaultIntegration.ps1 -KeyVaultName "MyMigrationKeyVault"
```

The script tests:
1. Key Vault connectivity
2. SecureCredentialProvider initialization
3. Credential storage and retrieval
4. Secret storage and retrieval
5. SecurityFoundation integration

## Troubleshooting

### Common Issues

1. **Access Denied**
   - Ensure the user running the scripts has appropriate Key Vault access policies
   - Check if Azure AD authentication token is expired

2. **Key Vault Not Found**
   - Verify Key Vault name is spelled correctly
   - Confirm Key Vault exists in the expected subscription

3. **Certificate Operations Failing**
   - Ensure the user has certificate permissions in Key Vault
   - Check certificate validity and expiration

### Logging

The toolkit logs all Key Vault operations. To enable verbose logging:

```powershell
Initialize-Logging -LogLevel "Verbose" -LogPath "C:\Logs\KeyVaultOperations.log"
```

## Security Best Practices

1. **Use Managed Identities**: When possible, use Azure managed identities instead of service principals
2. **Implement Least Privilege**: Grant only the necessary permissions to identities accessing Key Vault
3. **Enable Soft Delete**: Configure Key Vault with soft-delete to prevent accidental data loss
4. **Set Expiration on Secrets**: Configure expiration times for sensitive credentials
5. **Regular Credential Rotation**: Implement processes to regularly rotate credentials stored in Key Vault

## Related Components

- [SecurityFoundation Module](./SecurityFoundation.md)
- [SecureCredentialProvider Module](./SecureCredentialProvider.md)
- [UserCommunicationFramework](./UserCommunicationFramework.md) 
