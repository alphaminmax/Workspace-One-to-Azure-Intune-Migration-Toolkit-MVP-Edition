![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Security Foundation Module

## Overview

The SecurityFoundation module forms the core security layer of the Workspace ONE to Azure/Intune Migration Toolkit. It provides robust protection for sensitive data, credential management, and encryption services throughout the migration process. The module integrates with Azure Key Vault (through the SecureCredentialProvider) to ensure enterprise-grade security for all migration operations.

## Key Features

- **Certificate Management**: Generate, import, and manage encryption certificates
- **Data Protection**: Encrypt and decrypt sensitive configuration data and credentials
- **Azure Key Vault Integration**: Store secrets, keys, and certificates in Azure Key Vault
- **Secure Credential Handling**: Integrated with SecureCredentialProvider for unified credential management
- **Integrity Verification**: Validate data integrity during migration processes
- **Security Auditing**: Comprehensive logging of security-related operations
- **Compliance Support**: Helps maintain security compliance during migration

## Prerequisites

- PowerShell 5.1 or later
- Az.KeyVault module (for Azure Key Vault integration)
- SecureCredentialProvider module (internal dependency)
- LoggingModule (for audit trail)

## Core Functions

### Module Initialization

#### Initialize-SecurityFoundation

Initializes the security foundation module with encryption certificates and configuration.

```powershell
Initialize-SecurityFoundation [-CreateEncryptionCert] [-KeyVaultName <String>] [-UseKeyVault] [-ConfigPath <String>]
```

**Parameters:**
- `CreateEncryptionCert`: Create a new encryption certificate if one doesn't exist
- `KeyVaultName`: Name of the Azure Key Vault to use
- `UseKeyVault`: Use Azure Key Vault for secret storage
- `ConfigPath`: Path to security configuration file

**Example:**
```powershell
# Initialize with local certificate
Initialize-SecurityFoundation -CreateEncryptionCert

# Initialize with Azure Key Vault
Initialize-SecurityFoundation -UseKeyVault -KeyVaultName "MigrationKeyVault"
```

#### Set-SecurityConfiguration

Configures security settings for the module.

```powershell
Set-SecurityConfiguration [-AuditLogPath <String>] [-SecureKeyPath <String>] [-ApiTimeoutSeconds <Int>] [-UseKeyVault <Boolean>] [-KeyVaultName <String>] [-RequireAdminForSensitiveOperations <Boolean>]
```

**Parameters:**
- `AuditLogPath`: Path for security audit logs
- `SecureKeyPath`: Path for storing secure keys locally
- `ApiTimeoutSeconds`: Timeout for API operations
- `UseKeyVault`: Whether to use Azure Key Vault
- `KeyVaultName`: Name of the Azure Key Vault
- `RequireAdminForSensitiveOperations`: Require administrator privileges for sensitive operations

**Example:**
```powershell
Set-SecurityConfiguration -AuditLogPath "C:\Logs\SecurityAudit" `
                        -SecureKeyPath "C:\Secure\Keys" `
                        -UseKeyVault $true `
                        -KeyVaultName "MigrationKeyVault" `
                        -RequireAdminForSensitiveOperations $true
```

### Certificate Management

#### Get-EncryptionCertificate

Retrieves the encryption certificate used for securing data.

```powershell
Get-EncryptionCertificate [-CertificateThumbprint <String>] [-KeyVault] [-KeyVaultCertificateName <String>]
```

**Parameters:**
- `CertificateThumbprint`: Thumbprint of the certificate to retrieve
- `KeyVault`: Retrieve certificate from Azure Key Vault
- `KeyVaultCertificateName`: Name of the certificate in Azure Key Vault

**Example:**
```powershell
# Get default encryption certificate
$certificate = Get-EncryptionCertificate

# Get certificate from Key Vault
$certificate = Get-EncryptionCertificate -KeyVault -KeyVaultCertificateName "MigrationEncryptionCert"
```

#### New-EncryptionCertificate

Creates a new certificate for encryption operations.

```powershell
New-EncryptionCertificate [-Subject <String>] [-ExportPath <String>] [-ExportToKeyVault] [-ValidDays <Int>]
```

**Parameters:**
- `Subject`: Subject of the certificate
- `ExportPath`: Path to export the certificate
- `ExportToKeyVault`: Export the certificate to Azure Key Vault
- `ValidDays`: Number of days the certificate is valid

**Example:**
```powershell
# Create and export to file
New-EncryptionCertificate -Subject "CN=MigrationToolkit" -ExportPath "C:\Secure\Certs"

# Create and export to Key Vault
New-EncryptionCertificate -Subject "CN=MigrationToolkit" -ExportToKeyVault
```

### Data Protection

#### Protect-SensitiveData

Encrypts sensitive data using the encryption certificate.

```powershell
Protect-SensitiveData -Data <Object> [-KeyName <String>] [-Certificate <X509Certificate>]
```

**Parameters:**
- `Data`: The data to encrypt
- `KeyName`: Name to associate with the protected data
- `Certificate`: Certificate to use for encryption

**Example:**
```powershell
# Encrypt configuration data
$sensitiveConfig = @{
    "apiKey" = "secret-api-key-123"
    "endpoint" = "https://api.example.com"
}
$encryptedData = Protect-SensitiveData -Data $sensitiveConfig -KeyName "APIConfig"
```

#### Unprotect-SensitiveData

Decrypts previously protected data.

```powershell
Unprotect-SensitiveData -KeyName <String> [-Certificate <X509Certificate>] [-AsPlainText]
```

**Parameters:**
- `KeyName`: Name of the protected data
- `Certificate`: Certificate to use for decryption
- `AsPlainText`: Return the data as plain text rather than a secure string

**Example:**
```powershell
# Decrypt configuration data
$decryptedConfig = Unprotect-SensitiveData -KeyName "APIConfig"

# Get as plain text
$plainTextData = Unprotect-SensitiveData -KeyName "APIConfig" -AsPlainText
```

### Credential Management

#### Get-SecureCredential

Retrieves a credential securely stored using the SecureCredentialProvider.

```powershell
Get-SecureCredential -CredentialName <String> [-UseKeyVault] [-DefaultCredential <PSCredential>]
```

**Parameters:**
- `CredentialName`: Name of the credential to retrieve
- `UseKeyVault`: Retrieve from Azure Key Vault
- `DefaultCredential`: Default credential to return if not found

**Example:**
```powershell
# Get credential from default store
$credential = Get-SecureCredential -CredentialName "WorkspaceOneAdmin"

# Get credential from Key Vault
$credential = Get-SecureCredential -CredentialName "IntuneAdmin" -UseKeyVault
```

#### Set-SecureCredential

Stores a credential securely using the SecureCredentialProvider.

```powershell
Set-SecureCredential -Credential <PSCredential> -CredentialName <String> [-UseKeyVault] [-Metadata <Hashtable>]
```

**Parameters:**
- `Credential`: The credential to store
- `CredentialName`: Name to associate with the credential
- `UseKeyVault`: Store in Azure Key Vault
- `Metadata`: Additional metadata to store with the credential

**Example:**
```powershell
# Create and store credential
$password = ConvertTo-SecureString "Password123!" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("admin@contoso.com", $password)
Set-SecureCredential -Credential $credential -CredentialName "TenantAdmin" -UseKeyVault
```

#### Remove-SecureCredential

Removes a securely stored credential.

```powershell
Remove-SecureCredential -CredentialName <String> [-UseKeyVault]
```

**Parameters:**
- `CredentialName`: Name of the credential to remove
- `UseKeyVault`: Remove from Azure Key Vault

**Example:**
```powershell
Remove-SecureCredential -CredentialName "OldCredential" -UseKeyVault
```

### Secret Management

#### Get-SecureSecret

Retrieves a secret value from secure storage.

```powershell
Get-SecureSecret -Name <String> [-UseKeyVault] [-AsPlainText]
```

**Parameters:**
- `Name`: Name of the secret to retrieve
- `UseKeyVault`: Retrieve from Azure Key Vault
- `AsPlainText`: Return as plain text instead of secure string

**Example:**
```powershell
# Get secret as secure string
$apiKeySecure = Get-SecureSecret -Name "ApiKey" -UseKeyVault

# Get secret as plain text
$apiKey = Get-SecureSecret -Name "ApiKey" -UseKeyVault -AsPlainText
```

#### Set-SecureSecret

Stores a secret value in secure storage.

```powershell
Set-SecureSecret -Name <String> -SecretValue <SecureString> [-UseKeyVault]
```

**Parameters:**
- `Name`: Name to associate with the secret
- `SecretValue`: The secret value to store
- `UseKeyVault`: Store in Azure Key Vault

**Example:**
```powershell
# Create and store a secret
$secretValue = ConvertTo-SecureString "TopSecretApiKey123!" -AsPlainText -Force
Set-SecureSecret -Name "ApiKey" -SecretValue $secretValue -UseKeyVault
```

### Security Audit

#### Write-SecurityEvent

Records a security event in the audit log.

```powershell
Write-SecurityEvent -Message <String> [-Level <String>] [-Component <String>]
```

**Parameters:**
- `Message`: The message to log
- `Level`: Severity level of the event
- `Component`: Component generating the event

**Example:**
```powershell
# Log security event
Write-SecurityEvent -Message "Encryption certificate created" -Level "Information" -Component "CertificateManagement"

# Log sensitive operation
Write-SecurityEvent -Message "Admin credentials modified" -Level "Warning" -Component "CredentialManagement"
```

## Azure Key Vault Integration

The SecurityFoundation module integrates with Azure Key Vault through the SecureCredentialProvider module to provide enhanced security for enterprise environments:

### Setting Up Key Vault Integration

```powershell
# Import required modules
Import-Module ".\src\modules\SecurityFoundation.psm1"
Import-Module ".\src\modules\SecureCredentialProvider.psm1"

# Set up and initialize
Set-CredentialProviderConfig -UseKeyVault $true -KeyVaultName "MigrationKeyVault"
Set-SecurityConfiguration -UseKeyVault $true -KeyVaultName "MigrationKeyVault"

# Initialize both modules
Initialize-CredentialProvider
Initialize-SecurityFoundation
```

### Key Vault Benefits

1. **Centralized Secret Management**: Store all sensitive data in a single, secure location
2. **Managed Service**: Offload security maintenance to Azure's managed service
3. **Access Control**: Fine-grained access control with Azure AD integration
4. **Audit Trail**: Comprehensive logging of all secret access
5. **Key Rotation**: Simplified certificate and key rotation processes

## Integration Examples

### Secure Data Protection Workflow

```powershell
# Initialize security foundation
Initialize-SecurityFoundation -UseKeyVault -KeyVaultName "MigrationKeyVault"

# Create or get encryption certificate
$cert = Get-EncryptionCertificate -KeyVault
if (-not $cert) {
    $cert = New-EncryptionCertificate -Subject "CN=Migration Encryption" -ExportToKeyVault
}

# Protect sensitive configuration
$sensitiveData = @{
    "apiEndpoint" = "https://api.example.com"
    "apiKey" = "secret-key-123"
    "tenantId" = "00000000-0000-0000-0000-000000000000"
}

$protectedData = Protect-SensitiveData -Data $sensitiveData -KeyName "MigrationConfig" -Certificate $cert

# Later, retrieve and use the protected data
$config = Unprotect-SensitiveData -KeyName "MigrationConfig" -Certificate $cert
$endpoint = $config.apiEndpoint
$apiKey = $config.apiKey
```

### Credential Management with Key Vault

```powershell
# Initialize with Key Vault integration
Initialize-SecurityFoundation -UseKeyVault -KeyVaultName "MigrationKeyVault"

# Store admin credentials
$adminPassword = ConvertTo-SecureString "ComplexPassword123!" -AsPlainText -Force
$adminCred = New-Object System.Management.Automation.PSCredential("admin@contoso.com", $adminPassword)
Set-SecureCredential -Credential $adminCred -CredentialName "DomainAdmin" -UseKeyVault

# Store API key as a secret
$apiKey = ConvertTo-SecureString "api-key-1234567890" -AsPlainText -Force
Set-SecureSecret -Name "WorkspaceOneApiKey" -SecretValue $apiKey -UseKeyVault

# Retrieve credentials for operations
$migrationCred = Get-SecureCredential -CredentialName "DomainAdmin" -UseKeyVault
$apiKeyValue = Get-SecureSecret -Name "WorkspaceOneApiKey" -UseKeyVault -AsPlainText

# Use credentials in operations
# ... migration code using $migrationCred and $apiKeyValue ...
```

## Security Best Practices

1. **Use Key Vault in Production**: Always use Azure Key Vault for production environments
2. **Principle of Least Privilege**: Grant minimal permissions to service principals
3. **Certificate Management**: Regularly rotate encryption certificates
4. **Audit Security Events**: Regularly review security audit logs
5. **Secure Local Storage**: If using local storage, ensure appropriate file system security
6. **Clean Up**: Remove credentials and keys when no longer needed
7. **Require Admin for Sensitive Operations**: Enable RequireAdminForSensitiveOperations for sensitive tasks

## Troubleshooting

### Common Issues

1. **Certificate Access Issues**:
   - Ensure certificates are accessible to the executing user
   - Verify certificate has a private key for decryption operations
   - Check certificate validity and expiration dates

2. **Key Vault Authentication Problems**:
   - Verify Azure AD permissions are correctly configured
   - Ensure the service principal has appropriate Key Vault access policies
   - Check network connectivity to Azure Key Vault

3. **Encryption/Decryption Failures**:
   - Verify using the same certificate for encryption and decryption
   - Ensure the encryption certificate has the required cryptographic capabilities
   - Check for sufficient permissions to access protected data

4. **Integration Issues**:
   - Ensure both SecurityFoundation and SecureCredentialProvider are properly initialized
   - Verify configuration settings are consistent between modules
   - Check that dependency modules are correctly loaded

### Diagnostic Tools

```powershell
# Test encryption certificate
$cert = Get-EncryptionCertificate
if ($cert) {
    Write-Host "Certificate found: $($cert.Subject), Expiration: $($cert.NotAfter)"
    Write-Host "Has private key: $($cert.HasPrivateKey)"
} else {
    Write-Host "No encryption certificate found"
}

# Test Key Vault access
try {
    $secret = Get-SecureSecret -Name "TestSecret" -UseKeyVault -ErrorAction Stop
    Write-Host "Key Vault access successful"
} catch {
    Write-Host "Key Vault access failed: $_"
}
```

## Testing Security Configuration

The toolkit includes comprehensive test scripts for validating security functionality:

```powershell
# Test SecureCredentialProvider
.\src\tests\Test-SecureCredentialProvider.ps1 -KeyVaultName "MyMigrationKeyVault"

# Test integration between SecurityFoundation and SecureCredentialProvider
.\src\tests\Test-IntegrationCredentialSecurity.ps1 -KeyVaultName "MyMigrationKeyVault"

# Test Key Vault integration specifically
.\src\scripts\Test-KeyVaultIntegration.ps1 -KeyVaultName "MyMigrationKeyVault"
```

## Related Documentation

- [SecureCredentialProvider Module](Secure-Credential-Handling.md)
- [Key Vault Integration Guide](KeyVaultIntegration.md)
- [Graph API Integration](GraphAPIIntegration.md)
- [MVP Migration Guide](MVP-Migration-Guide.md) 
