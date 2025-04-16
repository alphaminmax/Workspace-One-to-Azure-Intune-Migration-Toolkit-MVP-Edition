![Crayon Logo](./assests/img/Crayon-Logo-RGB-Negative.svg)

# Workspace ONE to Azure/Intune Migration Toolkit - Technical SME Guide

## Introduction

This comprehensive guide is designed for Technical Subject Matter Experts (SMEs) responsible for implementing and supporting the Workspace ONE to Azure/Intune migration process. The toolkit provides an MVP (Minimum Viable Product) solution focused on essential migration functionality for enterprise environments.

## System Requirements

- **Operating System**: Windows 10 (Build 1809 or later) or Windows 11
- **PowerShell**: PowerShell 5.1 or later (PowerShell 7.x recommended for advanced features)
- **Account Privileges**: 
  - Standard user account for basic operations
  - Administrative access for certain operations (toolkit handles privilege elevation)
- **Network Connectivity**: 
  - Workspace ONE API endpoints
  - Azure/Microsoft Graph API endpoints
  - Microsoft Intune service endpoints
- **Storage**: Minimum 2GB free disk space for toolkit and logs

## Architecture Overview

The toolkit follows a modular architecture with these key components:

1. **Core Modules**:
   - `UserCommunicationFramework.psm1`: Manages all user notifications 
   - `RollbackMechanism.psm1`: Provides backup and recovery
   - `MigrationVerification.psm1`: Validates migration success
   - `SecurityFoundation.psm1`: Ensures secure operations

2. **Entry Points**:
   - `Invoke-WorkspaceOneSetup.ps1`: Initial configuration
   - `Start-WS1AzureMigration.ps1`: Primary migration script
   - `Test-MigratedDevice.ps1`: Verification tool

## Installation and Setup

### Standard Installation

1. Clone or extract the toolkit to a local directory:
   ```powershell
   git clone https://github.com/alphaminmax/Workspace-One-to-Azure-Intune-Migration-Toolkit-MVP-Edition.git
   ```

2. Configure settings using the .env file (recommended):
   ```powershell
   # Copy the template file
   Copy-Item .env.template .env
   
   # Edit the .env file with your credentials
   notepad .env
   ```
   
   Your .env file should contain:
   ```
   # Azure Credentials
   AZURE_CLIENT_ID=your-client-id
   AZURE_CLIENT_SECRET=your-client-secret
   AZURE_TENANT_ID=your-tenant-id
   
   # Workspace ONE Credentials
   WS1_HOST=your-ws1-host
   WS1_USERNAME=your-ws1-username
   WS1_PASSWORD=your-ws1-password
   WS1_API_KEY=your-ws1-api-key
   ```

3. Run the initialization script:
   ```powershell
   .\src\scripts\Initialize-SecureEnvironment.ps1 -StandardAdminAccount "MigrationAdmin"
   ```

### Enterprise Deployment Options

#### Option 1: Azure Key Vault Integration

1. Create an Azure Key Vault with required secrets:
   - `WS1-ClientID`
   - `WS1-ClientSecret`
   - `AzureAD-ClientID`
   - `AzureAD-ClientSecret`
   - `MigrationAdmin-Username`
   - `MigrationAdmin-Password`

2. Initialize with Key Vault integration:
   ```powershell
   .\src\scripts\Initialize-SecureEnvironment.ps1 -KeyVaultName "WS1MigrationVault"
   ```

#### Option 2: Environment Variables

1. Copy the included template to create your `.env` file:
   ```powershell
   Copy-Item .env.template .env
   ```

2. Edit the `.env` file with your specific credentials:
   ```
   AZURE_CLIENT_ID=your-client-id
   AZURE_CLIENT_SECRET=your-client-secret
   WS1_USERNAME=your-ws1-username
   WS1_PASSWORD=your-ws1-password
   WS1_API_KEY=your-ws1-api-key
   ```

3. Initialize with environment variables:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -UseEnvFile -EnvFilePath ".\.env"
   ```

## Pre-Migration Validation

Before beginning the migration process, validate your environment:

1. Verify script functionality:
   ```powershell
   .\src\scripts\TestScripts.ps1
   ```

2. Test environment readiness:
   ```powershell
   .\src\scripts\Test-WS1Environment.ps1 -GenerateReport
   ```

3. Test connectivity to required endpoints:
   ```powershell
   .\src\tools\Test-MigrationConnectivity.ps1
   ```

## Migration Process Workflow

The migration follows a five-stage process:

### Stage 1: Preparation
- Run `Start-WS1AzureMigration.ps1` to initiate the process
- System creates restore points and backups
- WS1 configuration is exported
- User receives initial notification

### Stage 2: WS1 Removal
- WS1 management components are uninstalled
- Local policies are adjusted
- System prepares for intermediate reboot

### Stage 3: Intermediate Processing
- System transitions to Azure/Intune management
- Prepares authentication components
- Configures device for Azure AD join

### Stage 4: Azure Enrollment
- Device joins Azure AD
- Intune enrollment completes
- User profiles are migrated

### Stage 5: Verification
- Validation checks are performed
- Reports are generated
- Notification of completion is sent

## Security Considerations

### Privilege Management

The toolkit uses three methods of privilege elevation:

1. **Just-in-time Elevation**: Creates temporary elevated tasks
2. **Temporary Admin Account**: Creates and removes accounts as needed
3. **Standard Admin Account**: Optional consistent admin identity (recommended for enterprise)

### Credential Handling

- No credentials are stored in plain text
- Azure Key Vault integration for enterprise deployments
- Environment variables for CI/CD scenarios
- Certificate-based encryption for local storage

## Logging and Monitoring

All activities are logged to multiple locations:

1. **Standard Logs**: `C:\Temp\Logs\WS1_Setup_[timestamp].log`
2. **Security Audit Logs**: `[LogPath]\SecurityAudit\[timestamp].log`
3. **Migration Logs**: `[LogPath]\Migration_[timestamp].log`
4. **Verification Reports**: `[LogPath]\VerificationReports\[timestamp].html`

## Troubleshooting Common Issues

### WS1 Component Removal Failures

If WS1 components fail to uninstall:

1. Check logs in `C:\Temp\Logs\` for specific errors
2. Attempt manual uninstallation of components
3. Run with `-EnrollmentOnly` flag to skip cleanup:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -EnrollmentOnly
   ```

### Azure AD Join Failures

If Azure AD join fails:

1. Verify Azure credentials in settings
2. Check network connectivity to Azure endpoints
3. Verify device is not already Azure AD joined:
   ```powershell
   dsregcmd /status
   ```

### Migration Verification Failures

If verification reports issues:

1. Run manual verification:
   ```powershell
   .\src\scripts\Test-MigratedDevice.ps1 -GenerateReport
   ```
2. Check if required applications are installed
3. Review Intune enrollment status in Company Portal app

## User Impact Management

The migration toolkit includes several features to minimize user disruption:

1. **Pre-migration Notifications**: Users are informed before migration starts
2. **Lock Screen Status**: Progress is displayed on lock screen
3. **Toast Notifications**: Status updates appear as Windows notifications
4. **Email Notifications**: Optional email updates if configured
5. **Migration Window Selection**: Schedule migrations during off-hours

## Reporting Functions

The toolkit provides detailed reporting features:

1. **Migration Status Reports**: Real-time updates during migration
2. **Verification Reports**: Detailed post-migration validation
3. **Executive Reports**: High-level summaries for management
4. **Email Distribution**: Automatic report delivery to stakeholders

### Generating Executive Reports

```powershell
Import-Module .\src\modules\EnhancedReporting.psm1
Send-MigrationReport -Recipients "management@company.com" -Format "HTML" -ReportType "Executive"
```

## Rollback Procedures

If migration fails, the toolkit provides rollback capabilities:

1. **Manual Rollback**:
   ```powershell
   Import-Module .\src\modules\RollbackMechanism.psm1
   Rollback-Migration -Reason "Migration failed during Stage 3"
   ```

2. **Automatic Rollback**: Occurs when critical errors are detected during migration

3. **System Restore**: Windows restore points can be used as a last resort

## Scaling Deployment

For enterprise-wide deployment:

1. **SCCM/Intune Deployment**:
   - Package the toolkit as an application in SCCM or Intune
   - Use `.\deployment\Deploy-WS1EnrollmentTools.ps1 -ConfigSource "Pipeline"`

2. **Silent Mode Deployment**:
   ```powershell
   .\src\scripts\Start-WS1AzureMigration.ps1 -SilentMode -UserEmail "user@company.com"
   ```

3. **Batched Deployment**: Use task sequences to deploy in phases

## Performance Optimization

For large-scale deployments:

1. **Resource Throttling**: Configure in `settings.json`:
   ```json
   "performance": {
     "maxConcurrentOperations": 3,
     "apiThrottleLimit": 60
   }
   ```

2. **Proxy Cache**: For software downloads:
   ```json
   "network": {
     "useProxyCache": true,
     "proxyCacheUrl": "http://proxy.company.com:8080"
   }
   ```

## Data Collection and Privacy

The toolkit collects the following data:

1. **Device Information**: Name, serial number, hardware details
2. **User Information**: Username, email (if provided)
3. **Migration Metrics**: Duration, success/failure status, component performance

All data collection complies with privacy regulations:

- Data is stored locally unless explicitly configured for central reporting
- Personal data is encrypted at rest
- Data retention follows your organization's policies

## Appendix: Command Reference

### Core Commands

- `Invoke-WorkspaceOneSetup.ps1`: Initial setup
- `Start-WS1AzureMigration.ps1`: Primary migration
- `Test-MigratedDevice.ps1`: Post-migration validation

### Reporting Commands

- `Send-MigrationReport`: Generate reports
- `Register-MigrationReportSchedule`: Schedule report generation

### Troubleshooting Commands

- `Test-WS1Environment.ps1`: Environment validation
- `Test-MigrationConnectivity.ps1`: Network connectivity testing
- `Test-RollbackMechanism.ps1`: Validate rollback functionality 