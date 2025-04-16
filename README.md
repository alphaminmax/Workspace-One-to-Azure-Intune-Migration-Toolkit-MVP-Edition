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
│   │   ├── PrivilegeManagement.psm1  # Privilege elevation without admin rights
│   │   ├── ProfileTransfer.psm1      # User profile migration
│   │   ├── GraphAPIIntegration.psm1  # Microsoft Graph API integration
│   │   └── WorkspaceOneWizard.psm1   # GUI interface (supports silent mode)
│   ├── scripts/                      # PowerShell scripts
│   │   ├── Invoke-WorkspaceOneSetup.ps1
│   │   ├── Test-WS1Environment.ps1
│   │   └── TestScripts.ps1
│   └── tools/                        # Additional tools
│       ├── Test-MigrationConnectivity.ps1
│       └── New-TemporaryAdminAccount.ps1
├── config/                           # Configuration files
│   ├── WS1Config.json
│   └── settings.json
├── deployment/                       # Deployment resources
│   ├── Deploy-WS1EnrollmentTools.ps1
│   ├── intune-templates/             # Intune-specific deployment templates
│   ├── sccm-templates/              # SCCM-specific deployment templates
│   └── gpo-templates/               # GPO-specific deployment templates
├── dashboard/                        # Migration visualization
│   └── WS1EnrollmentDashboard.html
├── docs/                             # Documentation
│   ├── LoggingModule.md
│   ├── ValidationTool.md
│   ├── MigrationTools.md
│   └── PrivilegeManagement.md
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

## Troubleshooting Guide

### Log File Locations

All toolkit components generate detailed logs to help with troubleshooting:

- **Script Testing Logs**: `C:\Temp\Logs\ScriptTests_[timestamp]\ScriptTesting_[timestamp].log`
- **Migration Logs**: `C:\Temp\WS1_Migration\Logs\Migration_[timestamp].log`
- **Setup Logs**: `C:\Temp\Logs\WS1_Setup_[timestamp]\Setup_[timestamp].log`
- **Environment Test Logs**: `C:\Temp\Logs\EnvTest_[timestamp].log`
- **Deployment Logs**: `C:\Temp\Logs\Deployment_[timestamp].log`
- **Privilege Operation Logs**: `C:\Temp\Logs\PrivilegeOps_[timestamp].log`

### Common Issues and Solutions

#### Issue 1: Migration Script Failures
- **Symptoms**: Migration scripts fail during execution
- **Troubleshooting Steps**:
  1. Check log files for specific error messages
  2. Verify PowerShell version compatibility
  3. Ensure all required modules are available
  4. Check for network connectivity issues
  5. Verify administrative privileges

#### Issue 2: Connectivity Problems
- **Symptoms**: Unable to connect to Workspace One or Azure endpoints
- **Troubleshooting Steps**:
  1. Run `Test-MigrationConnectivity.ps1` to diagnose network issues
  2. Verify server URLs are correct in configuration
  3. Check corporate firewall settings
  4. Test basic network connectivity with ping/traceroute
  5. Verify DNS resolution is working properly

#### Issue 3: Azure AD Join Failures
- **Symptoms**: Device fails to join Azure AD during migration
- **Troubleshooting Steps**:
  1. Check Azure AD credentials and permissions
  2. Verify network connectivity to Azure AD endpoints
  3. Check for existing device records in Azure AD
  4. Review device compatibility with Azure AD join
  5. Verify time synchronization on the device

#### Issue 4: User Profile Migration Issues
- **Symptoms**: User profile data not migrating correctly
- **Troubleshooting Steps**:
  1. Check permissions on user profile folders
  2. Verify user SID capture in logs
  3. Check disk space for profile migration
  4. Review encryption status of user files
  5. Manually copy user data if necessary

#### Issue 5: Privilege Elevation Failures
- **Symptoms**: Operations requiring admin rights fail
- **Troubleshooting Steps**:
  1. Check privilege elevation logs
  2. Verify task scheduler service is running
  3. Check local security policy settings
  4. Verify temporary admin account creation
  5. Review UAC settings on the device

## Integration with Endpoint Management

### Intune Deployment

1. **Package Creation**:
   ```powershell
   .\deployment\Deploy-WS1EnrollmentTools.ps1 -DeploymentType Intune -OutputPath "C:\Temp\IntunePackage"
   ```

2. **Intune Upload Process**:
   - Navigate to Intune portal > Apps > Windows apps
   - Add a new Windows app (Win32)
   - Upload the generated .intunewin file
   - Configure detection rules as specified in the generated instructions
   - Set the deployment to run in the user context (important!)
   - Assign to appropriate user/device groups

### SCCM/MECM Deployment

1. **Package Creation**:
   ```powershell
   .\deployment\Deploy-WS1EnrollmentTools.ps1 -DeploymentType SCCM -OutputPath "C:\Temp\SCCMPackage"
   ```

2. **SCCM Deployment Process**:
   - In SCCM console, go to Software Library > Application Management > Applications
   - Create a new application with the generated package
   - Create deployment types using the provided installation/uninstallation commands
   - Set the deployment to run whether or not a user is logged in
   - Configure detection methods as outlined in the generated instructions
   - Deploy to appropriate collections

### GPO Deployment

1. **Package Creation**:
   ```powershell
   .\deployment\Deploy-WS1EnrollmentTools.ps1 -DeploymentType GPO -OutputPath "C:\Temp\GPOPackage"
   ```

2. **GPO Configuration Process**:
   - Copy the generated files to a network share accessible by target computers
   - Create a new GPO in Group Policy Management Console
   - Edit the GPO and navigate to Computer Configuration > Policies > Windows Settings > Scripts
   - Configure startup or logon scripts using the generated GPOScript.ps1
   - Link the GPO to appropriate OUs containing target computers

## Security Considerations

The migration toolkit implements several security measures:

1. **Secure Credential Handling**
   - No plaintext passwords stored
   - Credentials encrypted during transmission
   - Uses Windows Data Protection API for local credential storage

2. **Temporary Account Security**
   - Complex random passwords for temporary accounts
   - Limited lifetime for all admin accounts
   - Audit logging of account creation and deletion

3. **Principle of Least Privilege**
   - Elevation only for specific operations that require it
   - No permanent elevation
   - Operations run in user context whenever possible

4. **Secure Cleanup**
   - All temporary admin accounts removed
   - Scheduled tasks removed after use
   - Temporary files securely deleted

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Developed for modern Windows 10/11 environments
- Compatible with Workspace One unenrollment and Azure AD/Intune enrollment
- Designed for enterprise migration scenarios


