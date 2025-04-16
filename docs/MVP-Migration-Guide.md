![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Workspace ONE Migration Toolkit - MVP Quick Start Guide

## Introduction

This guide provides essential information for getting started with the Workspace ONE Migration Toolkit (MVP version). The MVP toolkit includes the core functionality needed to migrate users from legacy systems to Workspace ONE and Intune.

## What's Included in the MVP

1. **Core Modules**
   - UserAuthenticationModule
   - UserCommunicationFramework
   - EnhancedReporting
   - IntuneIntegrationFramework
   - WorkspaceOneWizard

2. **Essential Scripts**
   - Invoke-WorkspaceOneSetup.ps1
   - Test-WS1Environment.ps1
   - Start-Migration.ps1
   - Send-MigrationReport.ps1

3. **UI Components**
   - Basic enrollment wizard
   - Migration progress dialogs
   - Feedback collection forms

## Quick Setup Process

1. **Clone the repository**
   ```powershell
   git clone https://github.com/organization/WS1-Migration-Toolkit.git
   cd WS1-Migration-Toolkit
   ```

2. **Configure environment**
   - Create a `.env` file in the root directory with your environment-specific settings
   - Use the `.env.example` file as a template

3. **Verify prerequisites**
   ```powershell
   .\Test-WS1Environment.ps1
   ```

4. **Run the migration script**
   ```powershell
   .\Start-Migration.ps1
   ```

## Core Capabilities

### 1. Secure Credential Handling

The MVP toolkit includes essential functionality for secure handling of credentials:

- Secure storage of authentication tokens
- Integration with Windows Credential Manager
- Basic password policy enforcement
- Credential validation against directory services

### 2. Migration Process

The toolkit provides a streamlined migration process:

- User profile backup
- Basic application inventory
- Configuration migration
- Staged rollout capabilities
- Rollback procedures for failed migrations

### 3. User Communication

Effective user communication is facilitated through:

- Email notifications at key migration stages
- Basic SMS alerts for critical actions
- On-screen guidance during enrollment
- Self-service troubleshooting resources

### 4. Authentication Transition

The MVP supports the transition of authentication methods:

- Password synchronization between systems
- Multi-factor authentication setup
- Single sign-on configuration
- Conditional access policy application

### 5. Security Foundation

Security features included in the MVP:

- TLS 1.2+ for all communications
- Certificate validation
- Audit logging of all migration actions
- Compliance reporting for completed migrations

## Limitations of the MVP

The MVP version has the following limitations compared to the full toolkit:

1. **Limited device types supported** - Windows 10/11 only
2. **Minimal customization options** - Basic branding only
3. **Simplified reporting** - Essential metrics only
4. **Manual interventions required** - For complex migration scenarios
5. **Limited scalability** - Designed for deployments under 500 devices

## Environment Configuration

The toolkit uses environment variables for configuration, which can be set in a `.env` file. For more information, see [Environment Configuration](Environment-Configuration.md).

Key variables include:

```
# Authentication
WS1_AUTH_ENDPOINT=https://example.com/auth
WS1_CLIENT_ID=your_client_id_here
WS1_CLIENT_SECRET=your_client_secret_here

# Workspace ONE
WS1_API_ENDPOINT=https://as123.awmdm.com/api
WS1_ADMIN_USERNAME=administrator
WS1_TENANT_CODE=your_tenant_code

# Intune
INTUNE_TENANT_ID=your_tenant_id
INTUNE_APP_ID=your_app_id
INTUNE_APP_SECRET=your_app_secret
```

## Troubleshooting Common Issues

### Module Import Errors

```
Problem: Unable to import module X
Solution: Ensure you're running PowerShell 5.1 or higher and have all prerequisites installed
```

### Authentication Issues

```
Problem: Authentication failed with Workspace ONE API
Solution: Verify credentials in .env file and check network connectivity to authentication endpoint
```

### Permission Issues

```
Problem: Access denied when executing migration steps
Solution: Ensure script is running with administrative privileges
```

### Connectivity Failures

```
Problem: Unable to connect to Workspace ONE console
Solution: Validate network configuration, proxy settings, and firewall rules
```

### Enrollment Failures

```
Problem: Device enrollment fails at 80%
Solution: Check device prerequisites and review logs at %TEMP%\WS1_Enrollment_Logs
```

## Next Steps After MVP

After successfully implementing the MVP toolkit, consider these enhancements:

1. **Expand device coverage** to include macOS, iOS, and Android
2. **Implement advanced reporting** with Power BI integration
3. **Enhance automation** with scheduling and dependency management
4. **Add custom branding** for improved user experience
5. **Integrate with ServiceNow** or other ITSM platforms

## Support Resources

- **Documentation**: Full documentation is available in the `/docs` folder
- **Issue Tracking**: Report issues via the project's GitHub Issues
- **Community Forum**: Join discussions at https://community.example.com/ws1migration
- **Email Support**: mvp-support@example.com

---

*This is a living document that will be updated as the MVP toolkit evolves.*

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
