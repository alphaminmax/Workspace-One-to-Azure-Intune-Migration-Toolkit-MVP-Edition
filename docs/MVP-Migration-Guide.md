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

### Scripts

- **Invoke-WorkspaceOneSetup.ps1**: Main entry point for the migration process
- **Test-WS1Environment.ps1**: Validates prerequisites for migration
- **Test-MigratedDevice.ps1**: Verifies successful migration
- **TestScripts.ps1**: Validates PowerShell scripts for quality and functionality

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

The MVP toolkit requires credentials for both Workspace ONE and Azure/Intune. To maintain security:

1. **Never store credentials in the repository**: Use the template configuration files with placeholders
2. **Use secure storage options**: 
   - Environment variables
   - Azure Key Vault
   - Windows Credential Manager
3. **Follow security best practices**: Principle of least privilege, credential rotation, etc.

For comprehensive guidance on credential management, refer to the [Secure Credential Handling Documentation](Secure-Credential-Handling.md).

## Migration Process

The MVP toolkit implements a simplified migration workflow:

1. **Preparation**: Run `Test-WS1Environment.ps1` to check prerequisites
2. **Validation**: Verify system requirements and connectivity
3. **Authentication Transition**: Configure credential providers for seamless identity transition
4. **Migration**: Execute the migration process with `Invoke-WorkspaceOneSetup.ps1`
5. **Verification**: Validate the migration with `Test-MigratedDevice.ps1`

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
- Early-stage implementation of Authentication Transition Management

## Future Enhancements

The MVP can be extended with additional features as needs grow:

- Advanced telemetry and analytics
- Enhanced security features
- Scaling capabilities for larger deployments
- Integration with service management platforms
- Multi-platform support
- Complete credential provider manipulation library 
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

For detailed troubleshooting, check the logs generated during each step of the process. 