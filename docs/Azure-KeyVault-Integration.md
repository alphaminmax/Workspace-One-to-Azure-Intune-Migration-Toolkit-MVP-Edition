# Azure Key Vault Integration

This document describes how to integrate the Workspace ONE to Azure/Intune Migration Toolkit with Azure Key Vault for secure credential management.

## Overview

The toolkit supports retrieving sensitive credentials and configuration values from Azure Key Vault, providing a secure way to handle authentication information without storing it in local configuration files.

## Prerequisites

1. **Azure Subscription** with permissions to create/access Key Vaults
2. **PowerShell Az Module** installed
   ```powershell
   Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
   ```
3. **Application Registration** in Azure AD with appropriate permissions

## Setting Up Azure Key Vault

### 1. Create a Key Vault

```powershell
# Login to Azure
Connect-AzAccount

# Create a resource group if needed
New-AzResourceGroup -Name "MigrationTools-RG" -Location "East US"

# Create a Key Vault
New-AzKeyVault -Name "WS1MigrationVault" -ResourceGroupName "MigrationTools-RG" -Location "East US" -EnabledForTemplateDeployment
```

### 2. Add Required Secrets to the Key Vault

```powershell
# Add Azure AD credentials
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "AzureAD-ClientID" -SecretValue (ConvertTo-SecureString "your-client-id" -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "AzureAD-ClientSecret" -SecretValue (ConvertTo-SecureString "your-client-secret" -AsPlainText -Force)

# Add Workspace ONE credentials
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "WorkspaceOne-Username" -SecretValue (ConvertTo-SecureString "ws1-username" -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "WorkspaceOne-Password" -SecretValue (ConvertTo-SecureString "ws1-password" -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "WorkspaceOne-ApiKey" -SecretValue (ConvertTo-SecureString "ws1-api-key" -AsPlainText -Force)

# Add Standard Admin Account credentials
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "StandardAdmin-username" -SecretValue (ConvertTo-SecureString "local-admin-username" -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "StandardAdmin-password" -SecretValue (ConvertTo-SecureString "local-admin-password" -AsPlainText -Force)
```

### 3. Set Access Policies

```powershell
# Get the object ID of the user who will run the scripts
$userObjectId = (Get-AzADUser -UserPrincipalName "your-email@domain.com").Id

# Set access policy for the user
Set-AzKeyVaultAccessPolicy -VaultName "WS1MigrationVault" -ObjectId $userObjectId -PermissionsToSecrets Get,List

# If using a service principal (recommended for automation)
$spObjectId = (Get-AzADServicePrincipal -DisplayName "MigrationServicePrincipal").Id
Set-AzKeyVaultAccessPolicy -VaultName "WS1MigrationVault" -ObjectId $spObjectId -PermissionsToSecrets Get,List
```

## Using the SecureCredentialProvider Module

The toolkit includes a `SecureCredentialProvider.psm1` module that handles all interactions with Azure Key Vault. Here's how to use it:

### 1. Initialize the Credential Provider

```powershell
Import-Module "$PSScriptRoot\src\modules\SecureCredentialProvider.psm1"

# Initialize with Key Vault
Initialize-SecureCredentialProvider -KeyVaultName "WS1MigrationVault" -UseKeyVault -StandardAdminAccount "LocalAdmin"

# Or with both Key Vault and .env file
Initialize-SecureCredentialProvider -KeyVaultName "WS1MigrationVault" -UseKeyVault -EnvFilePath "./.env" -UseEnvFile -StandardAdminAccount "LocalAdmin"
```

### 2. Retrieve Credentials and Secrets

```powershell
# Get a credential (username + password)
$ws1Credential = Get-SecureCredential -CredentialName "WorkspaceOneAPI"

# Get a specific secret
$clientId = Get-SecretFromKeyVault -SecretName "AzureAD-ClientID" -AsPlainText
$clientSecret = Get-SecretFromKeyVault -SecretName "AzureAD-ClientSecret"  # Returns as SecureString

# Get admin credentials (either standard or temporary)
$adminCred = Get-AdminCredential -AllowTemporaryAdmin
```

### 3. Store New Credentials or Secrets

```powershell
# Store a credential
$newCred = Get-Credential -Message "Enter new API credentials"
Set-SecureCredential -CredentialName "NewApiCredential" -Credential $newCred

# Store a secret
Set-SecretInKeyVault -SecretName "New-ConfigValue" -SecretValue "secret-value"
```

## Using a Standard Admin Account

The toolkit supports using a consistent standard admin account across all devices, which can be more manageable than creating temporary accounts on each device.

### Benefits of a Standard Admin Account

1. **Consistent Management**: Same account used across all devices
2. **Simplified Auditing**: All admin actions are tracked under the same account
3. **Reduced Overhead**: No need to create and clean up temporary accounts
4. **Password Rotation**: Centralized password management and rotation

### Setting Up a Standard Admin Account

1. **Create the local user account** on your golden image or via group policy:
   ```powershell
   $secPassword = ConvertTo-SecureString "ComplexPassword123" -AsPlainText -Force
   New-LocalUser -Name "MigrationAdmin" -Password $secPassword -PasswordNeverExpires -AccountNeverExpires
   Add-LocalGroupMember -Group "Administrators" -Member "MigrationAdmin"
   ```

2. **Store the credentials in Key Vault**:
   ```powershell
   $adminCred = New-Object System.Management.Automation.PSCredential("MigrationAdmin", $secPassword)
   Set-SecureCredential -CredentialName "StandardAdmin" -Credential $adminCred
   ```

3. **Configure the toolkit to use the standard account**:
   ```powershell
   Initialize-SecureCredentialProvider -KeyVaultName "WS1MigrationVault" -UseKeyVault -StandardAdminAccount "MigrationAdmin"
   ```

### Security Considerations

1. **Account Management**: The standard admin account should be carefully managed, with a complex password that is rotated regularly
2. **Account Permissions**: Apply the principle of least privilege, giving the account only the permissions it needs
3. **Audit Logging**: Enable auditing for all actions taken by the admin account
4. **Password Storage**: Store the password securely in Key Vault, not in scripts or configuration files

## Fallback Mechanisms

The `SecureCredentialProvider` module implements a cascading approach to credential retrieval:

1. First tries Azure Key Vault (if configured)
2. Then tries environment variables (from .env file or system)
3. Finally, can prompt for credentials if interactive mode is allowed

This provides flexibility and resilience in different deployment scenarios.

## Implementation in Migration Scripts

When implementing the migration scripts, use the `SecureCredentialProvider` module as follows:

```powershell
# At the beginning of your main script
Import-Module "$PSScriptRoot\src\modules\SecureCredentialProvider.psm1"

# Initialize the credential provider
Initialize-SecureCredentialProvider -KeyVaultName $KeyVaultName -UseKeyVault -EnvFilePath $EnvFilePath -UseEnvFile -StandardAdminAccount $AdminAccount

# Get Azure AD credentials
$azureClientId = Get-SecretFromKeyVault -SecretName "AzureAD-ClientID" -AsPlainText
$azureClientSecret = Get-SecretFromKeyVault -SecretName "AzureAD-ClientSecret"

# Get Workspace ONE credentials
$ws1Credential = Get-SecureCredential -CredentialName "WorkspaceOneAPI"

# Get admin credentials for privileged operations
$adminCred = Get-AdminCredential -AllowTemporaryAdmin

# Use these credentials in your migration operations
Connect-MsGraph -ClientId $azureClientId -ClientSecret $azureClientSecret
Connect-WorkspaceOne -Credential $ws1Credential

# Perform privileged operations with admin credentials
Invoke-ElevatedOperation -Credential $adminCred -ScriptBlock {
    # Privileged operations here
}
```

## Service Principal Authentication

For automated deployments, it's recommended to use a service principal rather than user credentials:

```powershell
# Create a service principal
$sp = New-AzADServicePrincipal -DisplayName "MigrationServicePrincipal"
$spSecret = New-AzADServicePrincipalCredential -ObjectId $sp.Id

# Store service principal credentials in Key Vault
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "ServicePrincipal-AppId" -SecretValue (ConvertTo-SecureString $sp.AppId -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName "WS1MigrationVault" -Name "ServicePrincipal-Secret" -SecretValue (ConvertTo-SecureString $spSecret.SecretText -AsPlainText -Force)

# Grant Key Vault access to the service principal
Set-AzKeyVaultAccessPolicy -VaultName "WS1MigrationVault" -ServicePrincipalName $sp.AppId -PermissionsToSecrets Get,List
```

Then authenticate in your scripts using the service principal:

```powershell
$spAppId = Get-SecretFromKeyVault -SecretName "ServicePrincipal-AppId" -AsPlainText
$spSecret = Get-SecretFromKeyVault -SecretName "ServicePrincipal-Secret"
$tenantId = "your-tenant-id"

# Connect using service principal
Connect-AzAccount -ServicePrincipal -Credential (New-Object PSCredential($spAppId, $spSecret)) -TenantId $tenantId
```

## Additional Security Recommendations

1. **Managed Identities**: If running in Azure VMs, use managed identities instead of service principals
2. **Network Restrictions**: Configure Key Vault network ACLs to restrict access to specific networks
3. **Monitoring**: Enable Azure Monitor for Key Vault to track access and operations
4. **Key Rotation**: Implement regular rotation of keys and secrets
5. **Conditional Access**: Apply Conditional Access policies to Key Vault access 