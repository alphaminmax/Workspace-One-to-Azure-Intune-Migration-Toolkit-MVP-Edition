![Crayon Logo](./assests/img/Crayon-Logo-RGB-Negative.svg)

# Workspace One to Azure/Intune Migration Toolkit - MVP Edition

A streamlined PowerShell-based solution for migrating devices from VMware Workspace One to Microsoft Intune/Azure AD. This MVP (Minimum Viable Product) edition focuses on core migration functionality without enterprise overhead.

## MVP Approach

This toolkit follows an MVP approach that:

1. **Focuses on Core Functionality**: Prioritizes essential migration components
2. **Simplifies Deployment**: Reduces complexity for quick implementation
3. **Enables Fast Iterations**: Allows for rapid testing and improvement cycles
4. **Provides Foundation**: Establishes a base for future feature expansion

For comprehensive details about the MVP approach, see [MVP Migration Guide](docs/MVP-Migration-Guide.md).

## Overview

This toolkit provides:

1. **Migration Process**: Automated migration from Workspace One to Azure Intune
2. **Migration Validation**: Tools to verify prerequisites and environment readiness
3. **Script Testing**: Automated validation of PowerShell scripts
4. **Connectivity Testing**: Verification of network requirements for migration
5. **Migration Reporting**: Basic HTML reports of migration status and results

## System Requirements

- Windows 10 (Build 1809 or later) or Windows 11
- PowerShell 5.1 or later (PowerShell 7.x recommended for advanced features)
- Standard user account (solution handles privilege elevation when required)
- Network connectivity to both Workspace One and Azure/Intune endpoints
- Valid Azure AD credentials for the target tenant

## Project Structure

The project is organized into the following directories:

```
ws1-to-azure-migration/
├── src/
│   ├── modules/                      # PowerShell modules
│   │   ├── LoggingModule.psm1        # Centralized logging
│   │   ├── ValidationModule.psm1     # Environment and migration validation
│   │   ├── PrivilegeManagement.psm1  # Privilege elevation without admin rights
│   │   ├── ProfileTransfer.psm1      # User profile migration
│   │   ├── ApplicationDataMigration.psm1 # Application settings migration
│   │   ├── GraphAPIIntegration.psm1  # Microsoft Graph API integration
│   │   ├── UserCommunicationFramework.psm1  # User notifications and guides
│   │   ├── LockScreenGuidance.psm1   # Lock screen customization during migration
│   │   ├── RollbackMechanism.psm1    # Migration recovery and rollback
│   │   ├── EnhancedReporting.psm1    # Advanced reporting and analytics 
│   │   ├── MigrationVerification.psm1 # Migration verification and validation
│   │   └── WorkspaceOneWizard.psm1   # GUI interface (supports silent mode)
│   ├── scripts/                      # PowerShell scripts
│   │   ├── Invoke-WorkspaceOneSetup.ps1
│   │   ├── Test-WS1Environment.ps1
│   │   ├── Test-MigratedDevice.ps1
│   │   ├── Invoke-MigrationOrchestrator.ps1
│   │   └── TestScripts.ps1
│   ├── tests/                        # Test scripts and validation
│   │   ├── Test-HighPriorityComponents.ps1
│   │   ├── Test-IntegrationCredentialSecurity.ps1
│   │   ├── Test-SecureCredentialProvider.ps1
│   │   └── Test-SecurityFoundation.ps1
│   ├── templates/                    # HTML and notification templates
│   ├── gui/                          # GUI components and resources
│   ├── config/                       # Module-specific configurations
│   └── tools/                        # Additional tools
│       ├── Test-MigrationConnectivity.ps1
│       └── New-TemporaryAdminAccount.ps1
├── config/                           # Configuration files
│   ├── WS1Config.json
│   └── settings.json
├── deployment/                       # Deployment resources
│   ├── Deploy-WS1EnrollmentTools.ps1
│   ├── intune-templates/             # Intune-specific deployment templates
│   ├── sccm-templates/               # SCCM-specific deployment templates
│   └── gpo-templates/                # GPO-specific deployment templates
├── dashboard/                        # Migration visualization
│   └── WS1EnrollmentDashboard.html
├── docs/                             # Documentation
│   ├── LoggingModule.md
│   ├── ValidationTool.md
│   ├── MigrationTools.md
│   ├── LockScreenGuidance.md
│   ├── ApplicationDataMigration.md
│   ├── PrivilegeManagement.md
│   ├── UserCommunicationFramework.md
│   └── EnhancedReporting.md
├── index/                            # Search and reference indexes
├── assets/                           # Static resources and images
├── diagrams/                         # Architecture and flow diagrams
├── reports/                          # Generated reports and analytics
├── archived/                         # Previous migration scripts 
└── README.md                         # This file
```

## Core Functionality

### Validation Module

The solution includes a validation module for ensuring environment readiness and migration success:

- **Prerequisite Testing**: Checks system requirements and connectivity
- **Migration Verification**: Validates successful migration to Intune
- **Reporting**: Generates HTML reports of validation results

### Rollback Mechanism

Implements a simple rollback capability for failed migrations:

- **System Restore Points**: Creates restore points before migration
- **Configuration Backup**: Preserves Workspace ONE configuration
- **Registry Backup**: Stores critical registry keys

### User Communication Framework

Provides comprehensive communication with end users during the migration process:

- **Multi-channel Notifications**: Support for Windows toast notifications, email, and Microsoft Teams
- **Migration Progress Display**: Visual and notification-based progress updates
- **User Guides**: HTML-based documentation for migration steps and procedures
- **Feedback Collection**: Mechanisms to gather user feedback on migration experience
- **Customizable Branding**: Company-specific branding for all user communications
- **Silent Operation Support**: Operates in silent mode for unattended migrations
- **Email Notifications**: Configurable email notifications for migration status updates
- **SMS Notifications**: Optional text message alerts for critical migration events

### Enhanced Reporting

Comprehensive reporting system for migration status and analytics:

- **HTML/PDF/Text Reports**: Generate reports in multiple formats for different audiences
- **Executive Summaries**: High-level overviews for management and stakeholders
- **Technical Reports**: Detailed information for IT administrators
- **Customizable Templates**: Branded report templates with configurable sections
- **Scheduled Reporting**: Automatic report generation and distribution on schedules
- **Email Distribution**: Send reports automatically to configurable recipients
- **Migration Analytics**: Detailed metrics on migration success rates and performance
- **Component Analysis**: Success rates by migration component for troubleshooting
- **CSV Data Export**: Raw data exports for custom analysis

### Lock Screen Guidance

Customizes the Windows lock screen to provide contextual guidance during migration:

- **Stage-aware Messaging**: Updates lock screen content based on migration progress
- **Visual Progress Indicators**: Shows progress bars and status during migration
- **Corporate Branding**: Incorporates company logo and color schemes
- **User Action Prompts**: Clear instructions when user input is required
- **HTML Templates**: Customizable HTML-based templates for each migration stage
- **Automatic Restoration**: Reverts to original lock screen after migration completes

### Logging

Comprehensive logging for troubleshooting:

- **Centralized Logging**: All components use the common logging module
- **Multiple Log Levels**: Support for INFO, WARNING, ERROR, and DEBUG
- **File and Console Output**: Logs to both file and console

### Privilege Management

The solution uses a sophisticated privilege elevation model that enables execution without requiring users to have administrator rights:

- **Just-in-time Elevation**: Temporary privilege elevation only when required
- **Task Scheduler Technique**: Uses Windows Task Scheduler for privilege elevation
- **Temporary Admin Account**: Secure creation and deletion of temporary accounts
- **Minimal Privilege Scope**: Elevation limited to specific operations that require it
- **Automatic Cleanup**: All privileged artifacts are removed after migration

### User Profile Migration

Handles the complex task of migrating user profiles between management systems:

- **Profile Ownership Transfer**: Changes ownership of user profile folders
- **Registry Migration**: Transfers user-specific registry settings
- **Data Preservation**: Ensures no user data is lost during migration
- **Special Folders Handling**: Properly manages special Windows folders and libraries
- **SID Mapping**: Tracks and maps user SIDs between environments

### Application Data Migration

Provides comprehensive migration of application-specific settings for seamless user experience:

- **Outlook Profiles**: Migrates PST files, signatures, templates, and account settings
- **Browser Data**: Transfers bookmarks, cookies, extensions, and saved passwords
- **Credential Vault**: Preserves stored credentials and handles passkeys
- **Cross-User Migration**: Supports transferring settings between different user accounts
- **Secure Handling**: Ensures sensitive data is managed securely during migration

### Silent Operation

The solution supports fully silent operation for enterprise deployment:

- **No UI Mode**: Complete functionality without displaying user interface
- **Progress Reporting**: Background progress reporting via event log and status files
- **Error Handling**: Robust error management even in silent mode
- **Logging**: Comprehensive logging for troubleshooting silent deployments
- **Exit Codes**: Standard exit codes for integration with deployment tools

## Migration Process Overview

The migration process follows these main steps:

1. **Preparation**: Validate environment readiness and prerequisites
2. **Initial Migration**: Remove Workspace One management and prepare for Azure enrollment
3. **Intermediate Stage**: Configure device for Azure AD join
4. **User Profile Handling**: Capture user information and prepare profile migration
5. **Finalization**: Complete Azure enrollment and restore user data

## Detailed Tools Description

### 1. Script Testing Tool (`TestScripts.ps1`)

The script testing tool validates PowerShell scripts for syntax errors and basic initialization issues without actually executing their full functionality.

**Key Features:**
- **Syntax Validation**: Checks all PowerShell scripts for syntax errors using the PowerShell parser
- **Initialization Testing**: Verifies scripts can be loaded into memory without execution errors
- **HTML Reporting**: Generates comprehensive HTML reports showing test results for all scripts
- **Error Logging**: Detailed error logging with specific information about script issues
- **Recommendations**: Provides suggestions for fixing identified problems

### 2. Environment Validation Tool (`Test-WS1Environment.ps1`)

This tool ensures your environment meets all prerequisites for migration from Workspace One to Azure/Intune.

**Key Features:**
- **System Compatibility Check**: Verifies OS version, PowerShell version, and system architecture
- **Network Connectivity Test**: Tests connectivity to both Workspace One and Azure/Intune endpoints
- **Authentication Validation**: Optionally tests authentication credentials for both platforms
- **Privilege Check**: Verifies administrative access for required operations
- **Required Modules Check**: Ensures necessary PowerShell modules are available
- **HTML Reports**: Generates detailed readiness reports with recommendations

### 3. Connectivity Test Tool (`Test-MigrationConnectivity.ps1`)

This specialized tool tests network connectivity between your environment and both Workspace One and Azure/Intune endpoints.

**Key Features:**
- **Endpoint Accessibility**: Tests connectivity to critical service endpoints for both platforms
- **Authentication Testing**: Optional verification of authentication credentials
- **DNS Resolution**: Checks DNS resolution for service endpoints
- **Firewall Analysis**: Identifies potential firewall blocking issues
- **Detailed Logging**: Comprehensive logging of all test results
- **Recommendations**: Suggests fixes for identified connectivity issues

### 4. Privilege Management Module (`PrivilegeManagement.psm1`)

Enables the solution to perform privileged operations without requiring admin rights from the user.

**Key Features:**
- **Task Scheduler Elevation**: Uses Windows Task Scheduler for privilege elevation
- **Temporary Admin Management**: Creates and manages temporary admin accounts securely
- **Just-in-time Access**: Provides elevated rights only when needed
- **Secure Credential Handling**: Protects credentials during elevation
- **Audit Logging**: Detailed logging of all privileged operations

### 5. Profile Transfer Module (`ProfileTransfer.psm1`)

Handles the complex task of migrating user profiles during the management system transition.

**Key Features:**
- **SID Detection**: Automatically detects and maps user SIDs
- **Permission Management**: Updates permissions on user files and folders
- **Registry Transfer**: Migrates critical registry keys and values
- **Special Path Handling**: Special handling for Windows-specific paths
- **Rollback Capability**: Can restore profiles if migration fails

### 6. Microsoft Graph Integration (`GraphAPIIntegration.psm1`)

Handles interaction with Microsoft Graph API for Azure AD and Intune operations.

**Key Features:**
- **Authentication Flow**: Manages authentication tokens and refresh
- **Device Registration**: Registers devices with Azure AD/Intune
- **User Assignment**: Assigns primary users to devices
- **Policy Application**: Applies appropriate policies to migrated devices
- **Compliance Checking**: Verifies device compliance post-migration

### 7. Migration Script Set

The migration process is handled by a set of coordinated scripts that execute different phases of the migration:

**Key Components:**
- **startMigrate.ps1**: Initiates the migration process, removes Workspace One management
- **middleBoot.ps1**: Handles the first reboot phase after Workspace One removal
- **newProfile.ps1**: Captures user information after initial sign-in
- **finalBoot.ps1**: Completes the migration process and finalizes Azure enrollment
- **postMigrate.ps1**: Handles post-migration tasks such as setting primary user in Intune
- **deploymigration.ps1**: Main deployment script for the migration toolkit

### 8. Deployment Tool (`Deploy-WS1EnrollmentTools.ps1`)

This tool packages and prepares the migration toolkit for deployment via different methods.

**Key Features:**
- **Multiple Deployment Methods**: Support for Intune, SCCM, and GPO deployment
- **Package Creation**: Creates deployment-ready packages
- **Configuration**: Customizable deployment settings
- **Documentation**: Generates deployment instructions
- **Silent Mode**: Supports silent/automated migration

### 9. Test Framework

The toolkit includes a comprehensive testing framework for validating components and their integration:

**Key Features:**
- **Component Testing**: Validates individual modules function correctly
- **Integration Testing**: Tests interaction between multiple components
- **High-Priority Component Validation**: Focused testing on critical modules
- **Automated Test Reports**: Generates HTML reports of test results
- **Scenario-Based Testing**: Tests complete migration workflows
- **Security Testing**: Validates credential handling and secure operations

The test framework is located in `src/tests/` and includes multiple test scripts:
- **Test-HighPriorityComponents.ps1**: Validates critical components like RollbackMechanism, MigrationVerification, and UserCommunicationFramework
- **Test-IntegrationCredentialSecurity.ps1**: Tests secure credential handling across components
- **Test-SecureCredentialProvider.ps1**: Validates the secure credential provider functionality
- **Test-SecurityFoundation.ps1**: Tests the security foundations of the toolkit

## Configuration and Security

### Secure Configuration Handling

The toolkit uses a configuration file (`config/settings.json`) that requires sensitive credentials. To maintain security:

1. **Template Configuration**: The repository includes a template configuration with placeholder values.

2. **Local Configuration**: Create your actual configuration locally by copying and modifying the template:
   ```powershell
   # Copy the template
   Copy-Item -Path .\config\settings.json -Destination .\config\settings.local.json
   
   # Edit the local copy with your actual credentials
   notepad .\config\settings.local.json
   ```

3. **Environment Variables**: For production use, we recommend using environment variables instead of hardcoded credentials:
   ```powershell
   # Set environment variables for sensitive values
   $env:WS1_CLIENT_ID = "your-client-id"
   $env:WS1_CLIENT_SECRET = "your-client-secret"
   
   # The toolkit will check for these environment variables before using the config file
   ```

4. **Azure Key Vault Integration**: For enterprise deployment, the toolkit now supports retrieving secrets directly from Azure Key Vault:
   ```powershell
   # Initialize with Key Vault integration
   .\src\scripts\Initialize-SecureEnvironment.ps1 -KeyVaultName "WS1MigrationVault" -StandardAdminAccount "MigrationAdmin"
   ```
   See [Azure Key Vault Integration](docs/Azure-KeyVault-Integration.md) for detailed setup instructions.

5. **Environment File (.env)**: The toolkit supports loading credentials from a `.env` file:
   ```
   # .env file example
   AZURE_CLIENT_ID=your-client-id
   AZURE_CLIENT_SECRET=your-client-secret
   ADMIN_USERNAME=MigrationAdmin
   ```

6. **GitIgnore**: The `.gitignore` file is configured to exclude actual configuration files with credentials from being committed to the repository.

### Standard Admin Account

The toolkit now supports using a standard admin account across all devices for privileged operations, which simplifies management compared to temporary accounts:

1. **Consistent Identity**: Use the same admin account on all devices
2. **Central Management**: Store the credentials securely in Azure Key Vault
3. **Simplified Auditing**: All privileged actions use the same identity

See [Azure Key Vault Integration](docs/Azure-KeyVault-Integration.md) for details on setting up and using a standard admin account.

### Handling Settings in Different Environments

For different environments (dev, test, prod), we recommend:

1. **Environment-Specific Files**: Create separate config files for each environment:
   ```
   config/settings.dev.json
   config/settings.test.json
   config/settings.prod.json
   ```

2. **Environment Selection**: Specify which environment to use:
   ```powershell
   .\src\scripts\Invoke-WorkspaceOneSetup.ps1 -Environment "dev"
   ```

3. **Parameterized Deployment**: For CI/CD pipelines, use parameterized deployments:
   ```powershell
   .\deployment\Deploy-WS1EnrollmentTools.ps1 -ConfigSource "Pipeline" -TenantId $tenantId -ClientId $clientId
   ```

## Getting Started: Quick Start Guide

### Prerequisites

1. **Verify System Requirements**:
   - Windows 10 (Build 1809 or later) or Windows 11
   - PowerShell 5.1 or later
   - Network connectivity to both Workspace One and Azure/Intune endpoints

2. **Install Required PowerShell Modules**:
   ```powershell
   # Install required modules if missing
   Install-Module -Name Microsoft.Graph.Intune -Scope CurrentUser -Force
   ```

3. **Set Proper Execution Policy**:
   ```powershell
   # Change execution policy to allow script execution
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### Installation

1. **Download the Repository**:
   ```powershell
   # Via Git
   git clone https://github.com/your-org/ws1-to-azure-migration.git
   
   # Or download and extract the ZIP file manually
   ```

2. **Navigate to Project Directory**:
   ```powershell
   cd path\to\ws1-to-azure-migration
   ```

3. **Configure Environment**:
   ```powershell
   # Edit the configuration file with your organization's settings
   notepad .\config\WS1Config.json
   ```

### Basic Usage

To validate your environment before migration:

```powershell
# Run environment validation tool
.\src\scripts\Test-WS1Environment.ps1 -GenerateReport
```

To perform the migration:

```powershell
# Start the migration process
.\src\scripts\Invoke-WorkspaceOneSetup.ps1
```

To verify a successful migration:

```powershell
# Verify migration success
.\src\scripts\Test-MigratedDevice.ps1 -GenerateReport
```

## Migration Process Details

The migration process occurs in multiple stages, each handled by a specific script:

### Stage 1: Initial Migration

Handled by `startMigrate.ps1`:
- Authenticates to Microsoft Graph API
- Collects device information (hostname, serial number, OS build)
- Removes Workspace One management agent
- Creates temporary admin account for privileged operations
- Copies migration package files locally
- Sets up scheduled tasks for subsequent stages
- Prepares for first reboot

### Stage 2: Intermediate Stage

Handled by `middleBoot.ps1`:
- Runs after first reboot
- Elevates privileges using temporary admin account
- Configures credential providers
- Sets up user guidance for next steps
- Prepares for user authentication to Azure AD
- Sets up scheduled tasks for next stages

### Stage 3: User Profile Handling

Handled by `newProfile.ps1`:
- Captures user SID and account information
- Stores user data for profile migration
- Configures final stage scheduled task
- Maps old profile to new user account
- Prepares for final reboot

### Stage 4: Finalization

Handled by `finalBoot.ps1`:
- Completes Azure AD enrollment
- Transfers ownership of user profiles
- Migrates user data and settings
- Applies appropriate Intune policies
- Cleans up temporary files and settings
- Removes temporary admin accounts
- Finalizes Intune registration

### Stage 5: Post-Migration

Handled by `postMigrate.ps1`:
- Sets primary user in Intune
- Migrates BitLocker recovery keys
- Updates device group tags
- Registers device with Autopilot if configured
- Completes final configuration

## Non-Admin Execution Model

The solution's privilege management system allows execution without permanent admin rights:

### Privilege Elevation Methods

1. **Task Scheduler**
   - Creates a scheduled task running as SYSTEM
   - Executes privileged code blocks through this task
   - Automatically removes task after completion

2. **Temporary Admin Account**
   - Creates a temporary local admin account with a complex password
   - Uses this account only for specific operations
   - Securely removes account after migration completes

3. **COM Object Elevation**
   - Uses COM objects to perform operations with elevated privileges
   - Allows specific actions without full admin rights
   - Properly handles UAC prompts when running interactively

### Elevation API

The `PrivilegeManagement.psm1` module provides these key functions:

```powershell
# Run a code block with elevation
Invoke-ElevatedOperation -ScriptBlock { code-requiring-admin-rights }

# Create a temporary admin account
$adminCreds = New-TemporaryAdminAccount -Prefix "WS1Mig"

# Remove the temporary account
Remove-TemporaryAdminAccount -Credential $adminCreds
```

## Silent Operation Capabilities

The solution supports fully unattended operation for mass deployment:

### Silent Mode Features

1. **Command-Line Parameters**
   - `-Silent` switch for completely non-interactive operation
   - `-LogPath` parameter for custom log location
   - `-NoReboot` option to control reboot behavior

2. **Progress Reporting**
   - Creates status files in a monitored directory
   - Writes to event log for enterprise monitoring
   - Updates registry keys for deployment tool status tracking

3. **Exit Codes**
   - Returns standardized exit codes for deployment tools
   - Provides detailed error codes for troubleshooting
   - Supports custom status reporting for SCCM/Intune

### Example Silent Deployment

```powershell
# Example for mass deployment
.\src\scripts\Invoke-WorkspaceOneSetup.ps1 -Silent -LogPath "C:\ProgramData\WS1Migration\Logs" -ConfigPath "\\server\share\config.json" -AzureTenantId "tenant-id"
```

## Documentation

The migration toolkit includes comprehensive documentation:

- [Migration Workflow Diagrams](docs/Workflow-Diagrams.md) - Visual workflows of key processes
- [BitLocker Management](docs/BitLocker-Management.md) - BitLocker key migration and management
- [Rollback Mechanism](docs/Rollback-Mechanism.md) - Backup and rollback capabilities
- [Intune Integration](docs/Intune-Integration.md) - Microsoft Intune API integration
- [Secure Credential Handling](docs/Secure-Credential-Handling.md) - Security and credential management
- [User Communication Framework](docs/UserCommunicationFramework.md) - User notification and feedback
- [Email Notification System](docs/Email-Notification-System.md) - Email templates and delivery mechanisms
- [Migration Reporting](docs/Migration-Reporting.md) - Comprehensive reporting capabilities
- [Environment Configuration](docs/Environment-Configuration.md) - Secure management of credentials and settings

### Enhanced Reporting

Comprehensive reporting system for migration status and analytics:

- **HTML/PDF/Text Reports**: Generate reports in multiple formats for different audiences
- **Executive Summaries**: High-level overviews for management and stakeholders
- **Technical Reports**: Detailed information for IT administrators
- **Customizable Templates**: Branded report templates with configurable sections
- **Scheduled Reporting**: Automatic report generation and distribution on schedules
- **Email Distribution**: Send reports automatically to configurable recipients
- **Migration Analytics**: Detailed metrics on migration success rates and performance
- **Component Analysis**: Success rates by migration component for troubleshooting
- **CSV Data Export**: Raw data exports for custom analysis

## Legal Information

### Copyright

© 2025 Crayon. All Rights Reserved.

### Disclaimer

**DATA LOSS DISCLAIMER**: Migrations between management systems involve inherent risks. Crayon specifically disclaims any responsibility for data loss, system instability, or service interruptions that may occur during or after the migration process. Users must maintain complete backups prior to migration.

See [LICENSE.md](LICENSE.md) for complete terms and conditions.