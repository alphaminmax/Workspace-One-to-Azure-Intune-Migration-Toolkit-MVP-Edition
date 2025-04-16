# MVP Migration Toolkit - Quick Start Guide

## Overview

The MVP Migration Toolkit provides a simplified approach to migrating devices from VMware Workspace ONE to Microsoft Azure/Intune. This MVP (Minimum Viable Product) version focuses on core migration functionality without the enterprise overhead of the full toolkit, making it ideal for small to medium deployments or initial testing.

## Components

The MVP toolkit includes the following essential components:

### Core Modules

- **LoggingModule.psm1**: Basic logging functionality with file and console output
- **ValidationModule.psm1**: Environment and migration validation
- **RollbackMechanism.psm1**: Simple rollback capability for failed migrations
- **UserCommunicationFramework.psm1**: User notifications and guidance throughout migration
- **AuthenticationTransitionManager.psm1**: Manages identity provider transitions and credential providers
- **SecurityFoundation.psm1**: Manages security aspects including certificates and encryption
- **SecureCredentialProvider.psm1**: Unified interface for secure credential management
- **GraphAPIIntegration.psm1**: Integration with Microsoft Graph API for Azure/Intune operations

### Scripts

- **Invoke-WorkspaceOneSetup.ps1**: Main entry point for the migration process
- **Test-WS1Environment.ps1**: Validates prerequisites for migration
- **Test-MigratedDevice.ps1**: Verifies successful migration
- **TestScripts.ps1**: Validates PowerShell scripts for quality and functionality
- **Test-KeyVaultIntegration.ps1**: Validates Azure Key Vault functionality

### UI Components

- **Basic Dashboard**: Simple HTML-based interface for migration status

## Quick Setup

1. Clone or download the repository to your admin workstation
2. Ensure PowerShell 5.1 or higher is installed
3. Run as administrator: `.\src\scripts\Invoke-WorkspaceOneSetup.ps1`

## Configuration

Edit the `config/WS1Config.json` file to set your environment-specific parameters:

```json
{
    "EnrollmentServer": "https://your-ws1-server.com",
    "IntuneIntegrationEnabled": true,
    "LogLevel": "INFO",
    "OrganizationName": "Your Organization",
    "HelpDeskPhoneNumber": "Your-Support-Number",
    "HelpDeskEmail": "your-support@example.com"
}
```

### Secure Credential Handling

The MVP toolkit now includes comprehensive credential management through the SecureCredentialProvider module with optional Azure Key Vault integration:

1. **Multiple storage options**:
   - Azure Key Vault (recommended for production)
   - Encrypted local files using the Windows Data Protection API
   - Environment variables (for development/testing only)
   
2. **Implementation options**:
   ```powershell
   # Initialize with Azure Key Vault
   Initialize-CredentialProvider -KeyVaultName "MyMigrationKeyVault" -UseManagedIdentity $true
   
   # Or initialize with local secure storage
   Initialize-CredentialProvider -LocalStoragePath "C:\MigrationData\Credentials"
   ```

For comprehensive guidance on credential management, refer to:
- [Secure Credential Provider Documentation](SecureCredentialProvider.md)
- [Key Vault Integration Guide](KeyVaultIntegration.md)
- [Security Foundation Documentation](SecurityFoundation.md)

## Migration Process

The MVP toolkit implements a simplified migration workflow:

1. **Preparation**: Run `Test-WS1Environment.ps1` to check prerequisites
2. **Validation**: Verify system requirements and connectivity
3. **Authentication Transition**: Configure credential providers for seamless identity transition
4. **Security Setup**: Initialize security components using `SecurityFoundation.psm1`
5. **Migration**: Execute the migration process with `Invoke-WorkspaceOneSetup.ps1`
6. **Verification**: Validate the migration with `Test-MigratedDevice.ps1`

## User Communication

The MVP toolkit includes a User Communication Framework to keep end users informed during the migration process:

1. **Notifications**: Configuration-based email and toast notifications at key stages
2. **Guides**: HTML-based user guides for pre and post-migration steps
3. **Progress Updates**: Visual indicators of migration progress
4. **Feedback Collection**: Optional user feedback gathering

For detailed information, see the [User Communication Framework Documentation](UserCommunicationFramework.md).

## Authentication Transition

The Authentication Transition Manager handles identity provider transitions during migration:

1. **Pre-Migration**: Assesses current authentication state and prepares fallback methods
2. **During Migration**: Enables Azure AD credential providers while maintaining existing methods
3. **Post-Migration**: Verifies authentication and optionally disables legacy methods

For more details, refer to the [Authentication Transition Manager Documentation](AuthenticationTransitionManager.md).

## Security Foundation

The Security Foundation module provides essential security services:

1. **Certificate Management**: Generation and validation of certificates for encryption
2. **Key Vault Integration**: Secure storage of sensitive information in Azure Key Vault
3. **Encryption Services**: Protection of configuration data and credentials
4. **Secure Storage**: Safe handling of migration-related sensitive information

To initialize the security infrastructure:

```powershell
Import-Module "src\modules\SecurityFoundation.psm1"
Initialize-SecurityFoundation -UseKeyVault $true -KeyVaultName "MyMigrationVault"
```

For more information, see the [Security Foundation Documentation](SecurityFoundation.md).

## GraphAPI Integration

The GraphAPI Integration module facilitates interaction with Microsoft Graph API:

1. **Azure/Intune Management**: Device and policy management via Graph API
2. **BitLocker Key Migration**: Secure transfer of BitLocker keys to Azure AD
3. **Authentication**: Secure token handling for Graph API access

Review the [GraphAPI Integration Documentation](GraphAPIIntegration.md) for implementation details.

## Validation

After migration, run the validation script to ensure success:

```powershell
.\src\scripts\Test-MigratedDevice.ps1 -GenerateReport
```

This will:
- Check Azure AD/Intune enrollment status
- Verify Workspace ONE removal
- Validate policy application
- Confirm required apps installation
- Verify authentication configuration
- Generate an HTML report if requested

## Limitations

The MVP toolkit has some limitations compared to the full enterprise version:

- Limited reporting and analytics
- Basic rollback functionality (no advanced recovery)
- Simplified user experience without portal access
- No automation for large-scale deployments
- Limited integrations with external systems

## Future Enhancements

The MVP can be extended with additional features as needs grow:

- Advanced telemetry and analytics
- Enhanced security features
- Scaling capabilities for larger deployments
- Integration with service management platforms
- Multi-platform support
- Expanded fallback authentication methods

## Troubleshooting

### Common Issues

1. **Module not found errors**:
   - Ensure all modules are in the correct path: `src/modules/`

2. **Permission issues**:
   - Run all scripts as administrator
   - Authentication Transition Manager requires admin rights to modify credential providers

3. **Connectivity failures**:
   - Verify network connectivity to Workspace ONE and Azure endpoints
   - Check firewall settings

4. **Authentication problems**:
   - Review credential provider settings
   - Use `Restore-CredentialProviderSettings` to revert problematic changes
   - Ensure fallback authentication is enabled

5. **Migration failures**:
   - Review logs in the `C:\Temp\Logs` directory
   - Run `Test-MigratedDevice.ps1` to identify specific issues

6. **Key Vault access issues**:
   - Verify network connectivity to Azure
   - Check permissions and service principal configuration
   - Review Azure Key Vault access policies
   - Use `Test-KeyVaultIntegration.ps1` to diagnose issues

For detailed troubleshooting, check the logs generated during each step of the process. 