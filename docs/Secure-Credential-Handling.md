![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Secure Credential Handling in Migration Toolkit

This documentation provides guidance on how to securely manage credentials and secrets in the Workspace ONE to Azure/Intune Migration Toolkit using the SecureCredentialProvider module.

## Overview

The SecureCredentialProvider module delivers a robust, layered approach to credential management for the migration toolkit. It provides secure storage and retrieval of credentials through multiple methods, with Azure Key Vault integration as the preferred secure option.

## Key Features

- **Azure Key Vault Integration**: Store and retrieve credentials and secrets in Azure Key Vault
- **Environment Variable Support**: Fall back to environment variables when Key Vault is not available
- **Interactive Fallback**: Optionally prompt for credentials when not found in secure storage
- **Admin Credential Management**: Simplify administrative operations with standard or temporary admin accounts
- **Error Handling and Logging**: Comprehensive error handling and integration with LoggingModule

## Prerequisites

- PowerShell 5.1 or later
- Az.KeyVault PowerShell module
- Azure subscription with Key Vault access (for Key Vault integration)

## Module Installation

The SecureCredentialProvider module is included with the Migration Toolkit. Ensure the Az.KeyVault module is installed:

```powershell
Install-Module -Name Az.KeyVault -Scope CurrentUser -Force
```

## Getting Started

### Initializing the Provider

Before using the credential provider, initialize it with your preferred configuration:

```powershell
# Initialize with Azure Key Vault
Initialize-SecureCredentialProvider -KeyVaultName "MigrationKeyVault" -UseKeyVault -StandardAdminAccount "admin"

# Initialize with environment variables from .env file
Initialize-SecureCredentialProvider -EnvFilePath "./.env" -UseEnvFile

# Initialize with both Key Vault and environment variables
Initialize-SecureCredentialProvider -KeyVaultName "MigrationKeyVault" -UseKeyVault -EnvFilePath "./.env" -UseEnvFile
```

### Retrieving Credentials

Once initialized, retrieve credentials using the following methods:

```powershell
# Get credential from secure storage
$apiCred = Get-SecureCredential -CredentialName "WorkspaceOneAPI"

# Get credential with interactive fallback if not found
$intuneCredential = Get-SecureCredential -CredentialName "IntuneAPI" -AllowInteractive

# Get admin credentials for privileged operations
$adminCred = Get-AdminCredential -AllowTemporaryAdmin
```

### Storing Credentials in Key Vault

Store credentials securely in Azure Key Vault:

```powershell
# Create a credential and store it
$credential = Get-Credential -Message "Enter API credentials"
Set-SecureCredential -CredentialName "WorkspaceOneAPI" -Credential $credential
```

### Storing and Retrieving Secrets

For API keys and other secrets that are not username/password pairs:

```powershell
# Store a secret
Set-SecretInKeyVault -SecretName "APIKey" -SecretValue "your-api-key"

# Retrieve a secret
$apiKey = Get-SecretFromKeyVault -SecretName "APIKey" -AsPlainText
```

## Security Considerations

1. **Key Vault Access Control**: Ensure Azure Key Vault access is restricted to appropriate users and service principals
2. **Environment Variables**: When using environment variables, ensure .env files are excluded from source control
3. **Temporary Admin Accounts**: Use temporary admin accounts only when necessary and ensure they're removed after use
4. **Credential Rotation**: Implement regular credential rotation as part of your security practices

## Integration with Other Modules

The SecureCredentialProvider integrates with several other modules in the toolkit:

- **LoggingModule**: For comprehensive logging of credential operations
- **SecurityFoundation**: For broader security capabilities
- **GraphAPIIntegration**: For secure access to Microsoft Graph API
- **PrivilegeManagement**: For temporary admin account creation when needed

## Troubleshooting

Common issues and solutions:

1. **Key Vault Connection Failures**:
   - Ensure you have proper permissions to the Key Vault
   - Check network connectivity to Azure
   - Verify Azure context is properly authenticated

2. **Missing Credentials**:
   - Ensure credential names match exactly when storing and retrieving
   - Check if environment variables are properly set in the current session

3. **Permission Issues**:
   - For admin operations, ensure you're running PowerShell as administrator
   - Verify service principal permissions in Azure AD

## Examples

### Complete Workflow Example

```powershell
# Import the module
Import-Module "./src/modules/SecureCredentialProvider.psm1"

# Initialize with Key Vault
Initialize-SecureCredentialProvider -KeyVaultName "MigrationKeyVault" -UseKeyVault

# Store API credentials
$cred = Get-Credential -Message "Enter Workspace ONE API credentials"
Set-SecureCredential -CredentialName "WorkspaceOneAPI" -Credential $cred

# Store an API key
Set-SecretInKeyVault -SecretName "IntuneAPIKey" -SecretValue "your-api-key-here"

# Later, retrieve and use the credentials
$apiCred = Get-SecureCredential -CredentialName "WorkspaceOneAPI"
$apiKey = Get-SecretFromKeyVault -SecretName "IntuneAPIKey" -AsPlainText

# Use admin credentials for privileged operations
$adminCred = Get-AdminCredential -AllowTemporaryAdmin
```

## Best Practices

1. Always initialize the provider at the beginning of your scripts
2. Use descriptive credential names for easy identification
3. Implement proper error handling around credential operations
4. Avoid storing credentials in script files or source control
5. Use the `-AllowInteractive` parameter only when appropriate for your scenario
6. Log credential operations (success/failure) but never log the credentials themselves 
