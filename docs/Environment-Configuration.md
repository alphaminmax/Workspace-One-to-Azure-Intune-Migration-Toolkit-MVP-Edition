# Environment Configuration Guide

## Overview

The Workspace ONE to Azure/Intune Migration Toolkit uses environment variables to securely manage sensitive configuration settings. This approach separates credentials and API keys from your code, providing better security and flexibility across different environments.

## Environment Configuration Methods

The toolkit supports three main methods for environment configuration:

1. **Environment Variables File (.env)**: Local file-based configuration
2. **Azure Key Vault**: Enterprise-grade secure secret storage
3. **System Environment Variables**: System-wide configuration

## Using .env Files (Recommended for Development)

The `.env` approach is recommended for development and testing environments.

### Setup Process

1. **Copy the template file**:
   ```powershell
   Copy-Item .env.template .env
   ```

2. **Edit the `.env` file** with your specific values:
   ```
   # Azure Credentials
   AZURE_CLIENT_ID=your-client-id
   AZURE_CLIENT_SECRET=your-client-secret
   AZURE_TENANT_ID=your-tenant-id
   
   # Workspace ONE Credentials
   WS1_USERNAME=your-ws1-username
   WS1_PASSWORD=your-ws1-password
   WS1_API_KEY=your-ws1-api-key
   WS1_HOST=your-ws1-host
   
   # Admin Account (Optional)
   ADMIN_USERNAME=MigrationAdmin
   ADMIN_PASSWORD=ComplexPassword123!
   
   # Email Configuration (Optional)
   SMTP_SERVER=smtp.company.com
   SMTP_PORT=587
   SMTP_USERNAME=notifications@company.com
   SMTP_PASSWORD=EmailPassword123!
   ```

3. **Initialize with the `.env` file**:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseEnvFile -EnvFilePath ".\.env"
   ```

### Security Considerations

- The `.env` file is automatically added to `.gitignore` to prevent accidental commits
- Don't share your `.env` file with others; each developer should create their own
- Consider encrypting the `.env` file when not in use with tools like:
  ```powershell
  ConvertTo-SecureString -String (Get-Content .env -Raw) -AsPlainText -Force | ConvertFrom-SecureString | Out-File .env.encrypted
  ```

## Using Azure Key Vault (Recommended for Production)

For production environments, Azure Key Vault provides a robust security solution.

### Setup Process

1. **Create an Azure Key Vault** in your Azure portal

2. **Add the following secrets** to your Key Vault:
   - `WS1-ClientID`
   - `WS1-ClientSecret`
   - `WS1-Username`
   - `WS1-Password`
   - `WS1-ApiKey`
   - `AzureAD-ClientID`
   - `AzureAD-ClientSecret`
   - `MigrationAdmin-Username` (optional)
   - `MigrationAdmin-Password` (optional)

3. **Grant access** to the service principal or user identity that will run the migration

4. **Initialize with Key Vault integration**:
   ```powershell
   .\src\scripts\Initialize-SecureEnvironment.ps1 -KeyVaultName "WS1MigrationVault"
   ```

## Using System Environment Variables

System environment variables can be used for CI/CD pipelines or server deployments.

### Setup Process

1. **Set environment variables** at the system or user level:
   ```powershell
   [Environment]::SetEnvironmentVariable("AZURE_CLIENT_ID", "your-client-id", "User")
   [Environment]::SetEnvironmentVariable("AZURE_CLIENT_SECRET", "your-client-secret", "User")
   # Add additional variables as needed
   ```

2. **Run the setup script** without specific environment parameters:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1
   ```
   
   The toolkit will automatically detect and use the system environment variables.

## Environment Variable Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| AZURE_CLIENT_ID | Azure AD application client ID | `1a2b3c4d-5e6f-7g8h-9i0j-klmnopqrstuv` |
| AZURE_CLIENT_SECRET | Azure AD application client secret | `YourSecretValue` |
| AZURE_TENANT_ID | Azure AD tenant ID | `abcdef12-3456-7890-abcd-ef1234567890` |
| WS1_USERNAME | Workspace ONE admin username | `admin@company.com` |
| WS1_PASSWORD | Workspace ONE admin password | `SecurePassword123!` |
| WS1_API_KEY | Workspace ONE API key | `YourApiKeyValue` |
| WS1_HOST | Workspace ONE host URL | `company.workspaceone.com` |

### Optional Variables

| Variable | Description | Example |
|----------|-------------|---------|
| ADMIN_USERNAME | Local admin account name | `MigrationAdmin` |
| ADMIN_PASSWORD | Local admin account password | `ComplexPassword123!` |
| SMTP_SERVER | SMTP server for notifications | `smtp.company.com` |
| SMTP_PORT | SMTP port | `587` |
| SMTP_USERNAME | Email account for sending notifications | `notifications@company.com` |
| SMTP_PASSWORD | Email account password | `EmailPassword123!` |
| LOG_PATH | Custom log directory | `C:\MigrationLogs` |
| BACKUP_PATH | Custom backup directory | `C:\MigrationBackups` |

## Multiple Environment Support

For managing different environments (dev, test, prod), you can:

1. **Create multiple .env files**:
   ```
   .env.dev
   .env.test
   .env.prod
   ```

2. **Specify the environment file** when running:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseEnvFile -EnvFilePath ".\.env.prod"
   ```

## Troubleshooting

### Common Issues

1. **Missing variables**: The script will warn you about missing required variables
   ```
   WARNING: Missing required variable: AZURE_CLIENT_ID
   ```

2. **Permission issues with .env file**: Ensure you have read permissions
   ```powershell
   Get-Acl .env | Format-List
   ```

3. **Key Vault access denied**: Verify your Azure credentials and permissions
   ```powershell
   Connect-AzAccount
   Get-AzKeyVault -VaultName "WS1MigrationVault"
   ```

### Best Practices

1. Regularly rotate secrets and update your .env files
2. Remove unused .env files when no longer needed
3. Consider using different Azure service principals for different environments
4. Implement the principle of least privilege for all credentials
5. Audit access to your Key Vault regularly

## Further Reading

- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- [PowerShell Environment Variables](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables)
- [Secure Credential Management in PowerShell](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/about/about_securestring) 