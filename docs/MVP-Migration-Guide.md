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

## Quick Setup

1. Clone or download the repository to your admin workstation:
   ```powershell
   git clone https://github.com/alphaminmax/Workspace-One-to-Azure-Intune-Migration-Toolkit-MVP-Edition.git
   cd WS1-Migration-Toolkit
   ```

2. Create and configure your environment file:
   ```powershell
   Copy-Item .env.template .env
   notepad .env
   ```
   See the [Configuration](#configuration) section below for details on setting up your `.env` file.

3. Run as administrator:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseEnvFile -EnvFilePath ".\.env"
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

## Configuration

The toolkit uses environment variables stored in a `.env` file for configuration. This approach provides better security by separating credentials from code.

### Setup Process

1. **Copy the template file**:
   ```powershell
   Copy-Item .env.template .env
   ```

2. **Edit the `.env` file** with your specific values:
   ```
   # Basic Configuration
   WS1_ENROLLMENT_SERVER=https://your-ws1-server.com
   WS1_INTUNE_INTEGRATION_ENABLED=true
   WS1_LOG_LEVEL=INFO
   WS1_ORGANIZATION_NAME=Your Organization
   WS1_HELPDESK_PHONE=Your-Support-Number
   WS1_HELPDESK_EMAIL=your-support@example.com
   
   # Azure AD/Intune Credentials
   AZURE_CLIENT_ID=your-client-id
   AZURE_CLIENT_SECRET=your-client-secret
   AZURE_TENANT_ID=your-tenant-id
   AZURE_TENANT_NAME=yourtenant.onmicrosoft.com
   
   # Workspace ONE Credentials
   WS1_HOST=yourcompany.awmdm.com
   WS1_USERNAME=ws1admin
   WS1_PASSWORD=your-ws1-password
   WS1_API_KEY=your-api-key
   
   # Migration Settings
   BITLOCKER_METHOD=MIGRATE
   LOCAL_PATH=C:\\ProgramData\\IntuneMigration
   LOG_PATH=C:\\Temp\\Logs
   REG_PATH=HKLM\\SOFTWARE\\IntuneMigration
   GROUP_TAG=WS1_Migrated
   ```

3. **Initialize with the `.env` file**:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseEnvFile -EnvFilePath ".\.env"
   ```

For comprehensive guidance on environment configuration, see [Environment Configuration](Environment-Configuration.md).

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

## Migration Process

The MVP toolkit implements a simplified migration workflow:

1. **Preparation**: Run `Test-WS1Environment.ps1` to check prerequisites
2. **Validation**: Verify system requirements and connectivity
3. **Authentication Transition**: Configure credential providers for seamless identity transition
4. **Security Setup**: Initialize security components using `SecurityFoundation.psm1`
5. **Migration**: Execute the migration process with `Invoke-WorkspaceOneSetup.ps1`
6. **Verification**: Validate the migration with `Test-MigratedDevice.ps1`