# Secure Credential Handling

This document outlines best practices for managing credentials and sensitive configuration data when using the Workspace One to Azure/Intune Migration Toolkit.

## Overview

The migration toolkit requires credentials and connection information for both Workspace ONE and Microsoft Azure/Intune environments. Handling these credentials securely is crucial to maintain the security of your migration process.

## Credential Types

The toolkit works with several types of sensitive data:

1. **Azure AD/Intune Credentials**
   - Client ID
   - Client Secret
   - Tenant ID
   - Tenant Name

2. **Workspace ONE Credentials**
   - API Host
   - Username
   - Password
   - API Key

3. **BitLocker Recovery Keys**
   - Recovery passwords
   - Key protector IDs

## Secure Storage Options

### 1. Environment Variables (Recommended for Development)

Use environment variables to avoid storing credentials in configuration files:

```powershell
# Set environment variables for Azure credentials
$env:AZURE_CLIENT_ID = "your-client-id"
$env:AZURE_CLIENT_SECRET = "your-client-secret"
$env:AZURE_TENANT_ID = "your-tenant-id"

# Set environment variables for Workspace ONE credentials
$env:WS1_HOST = "your-ws1-host"
$env:WS1_USERNAME = "your-username"
$env:WS1_PASSWORD = "your-password"
$env:WS1_API_KEY = "your-api-key"

# Run the migration with environment variables
.\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseEnvironmentVariables
```

### 2. Azure Key Vault (Recommended for Production)

For production environments, store credentials in Azure Key Vault:

1. **Store secrets in Key Vault**:
   ```powershell
   Set-AzKeyVaultSecret -VaultName "MigrationKeyVault" -Name "WS1-ApiKey" -SecretValue (ConvertTo-SecureString "your-api-key" -AsPlainText -Force)
   ```

2. **Configure the toolkit to use Key Vault**:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseKeyVault -KeyVaultName "MigrationKeyVault"
   ```

### 3. Windows Credential Manager

For local deployments, use the Windows Credential Manager:

```powershell
# Store credentials in Windows Credential Manager
$cred = Get-Credential -Message "Enter Workspace ONE credentials"
New-StoredCredential -Target "WS1Migration" -UserName $cred.UserName -Password $cred.GetNetworkCredential().Password -Persist LocalMachine

# Reference them in the toolkit
.\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseCredentialManager -CredentialTarget "WS1Migration"
```

### 4. Configuration Files (Not Recommended for Production)

For testing only, you can use configuration files with these safeguards:

1. Store the config file outside the repository
2. Ensure strict file permissions
3. Delete the file after use
4. Never commit files with real credentials

## Secure Configuration File Practices

When using configuration files:

1. **Use the template file** as a starting point:
   ```powershell
   Copy-Item -Path .\config\settings.json -Destination C:\Secure\settings.local.json
   ```

2. **Set strict permissions** on the local file:
   ```powershell
   $acl = Get-Acl -Path C:\Secure\settings.local.json
   $acl.SetAccessRuleProtection($true, $false)
   $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$env:USERNAME", "FullControl", "Allow")
   $acl.AddAccessRule($rule)
   Set-Acl -Path C:\Secure\settings.local.json -AclObject $acl
   ```

3. **Reference the external config** file:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -ConfigPath "C:\Secure\settings.local.json"
   ```

## BitLocker Key Security

BitLocker keys require special handling:

1. **Temporary Storage**: Keys are stored in memory only during the migration process
2. **Secure Backup**: Keys are backed up to Azure AD/Intune before migration
3. **Key Verification**: All backed-up keys are verified after migration
4. **Audit Logging**: All operations involving recovery keys are logged with timestamps

## Automation Considerations

When using the toolkit in automated deployments:

1. **Pipeline Variables**: Use pipeline variables/secrets for credentials
2. **Just-In-Time Access**: Generate short-lived application tokens
3. **Scoped Permissions**: Use the principle of least privilege
4. **Credential Rotation**: Rotate credentials regularly
5. **Audit Logs**: Monitor credential usage

## Security Best Practices

1. **Separate Credentials by Environment**: Use different credentials for dev/test/prod
2. **Principle of Least Privilege**: Assign minimal required permissions
3. **Audit Trail**: Monitor and log all credential usage
4. **Rotation Schedule**: Regularly rotate all credentials
5. **Secure Transport**: Always use HTTPS/TLS for API communication
6. **Post-Migration Cleanup**: Remove or rotate credentials after migration

## Troubleshooting

If you encounter credential-related issues:

1. Verify environment variables are set correctly
2. Check Key Vault access permissions
3. Ensure service principals have required permissions
4. Verify network connectivity to authentication endpoints
5. Check credential expiration dates 