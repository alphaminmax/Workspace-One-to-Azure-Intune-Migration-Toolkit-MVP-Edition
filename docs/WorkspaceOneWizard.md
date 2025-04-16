![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# WorkspaceOneWizard Module

## Overview

The WorkspaceOneWizard module provides a graphical user interface (GUI) for facilitating Workspace ONE enrollment with Intune integration in Windows 10/11 environments. This module helps end users complete enrollment when automated methods via GPO or endpoint management have failed.

## Core Features

- User-friendly graphical enrollment wizard
- Automated prerequisite verification
- Real-time enrollment progress tracking
- Configurable enrollment parameters
- Comprehensive logging of enrollment activities
- Support for Intune integration
- Error handling and user guidance

## Technical Specifications

- **File Location**: `src/modules/WorkspaceOneWizard.psm1`
- **PowerShell Version Required**: 5.1 or higher
- **Dependencies**: System.Windows.Forms, System.Drawing
- **Exposed Functions**:
  - `Show-EnrollmentWizard`
  - `Test-EnrollmentPrerequisites`
  - `Import-EnvConfig`

## Architecture

The module follows a modular design with these key components:

1. **Configuration Management**
   - Import-EnvConfig: Loads settings from environment variables
   - Default settings used if no configuration is found

2. **Logging System**
   - Initialize-WS1Logging: Sets up logging infrastructure
   - Write-WS1Log: Standardized logging function for various message levels

3. **Prerequisite Verification**
   - Test-EnrollmentPrerequisites: Verifies required conditions are met
   - Checks network connectivity, server accessibility, and device eligibility

4. **Enrollment Process**
   - Start-EnrollmentProcess: Coordinates the enrollment steps
   - Handles communication with enrollment servers

5. **User Interface**
   - Show-EnrollmentWizard: Main GUI entry point
   - Progress reporting and status updates
   - Error handling and user guidance

## Integration Points

The WorkspaceOneWizard module integrates with:

1. **Workspace ONE API**
   - Communicates with VMware Workspace ONE servers
   - Handles enrollment requests and verification

2. **Microsoft Intune**
   - Optional integration for hybrid management
   - Configurable through environment variables

3. **Other Project Modules**
   - Invoked by the Invoke-WorkspaceOneSetup.ps1 script
   - Used by the Test-WS1Environment.ps1 for validation

## Usage Examples

### Basic Usage

```powershell
# Import the module
Import-Module -Name ".\WorkspaceOneWizard.psm1"

# Launch the enrollment wizard
Show-EnrollmentWizard
```

### Testing Prerequisites Only

```powershell
# Import the module
Import-Module -Name ".\WorkspaceOneWizard.psm1"

# Test prerequisites without starting enrollment
$prereqResults = Test-EnrollmentPrerequisites
if ($prereqResults.Success) {
    Write-Host "System ready for enrollment"
} else {
    Write-Host "System not ready for enrollment. Issues:"
    $prereqResults.Issues
}
```

### Custom Configuration

```powershell
# Import the module
Import-Module -Name ".\WorkspaceOneWizard.psm1"

# Load configuration from a custom .env file
Import-EnvConfig -EnvFilePath "C:\CustomConfig\.env"

# Launch the enrollment wizard with custom settings
Show-EnrollmentWizard
```

## Environment Variable Configuration

The module supports configuration through environment variables, typically set in a `.env` file:

```
# Basic Configuration
WS1_ENROLLMENT_SERVER=https://ws1enrollmentserver.example.com
WS1_INTUNE_INTEGRATION_ENABLED=true
WS1_LOG_PATH=C:\Logs\WS1_Enrollment

# UI Customization
WS1_COMPANY_LOGO=C:\branding\logo.png
WS1_PRIMARY_COLOR=#0078D4
WS1_COMPANY_NAME=Example Corporation
```

For more information on environment configuration, see [Environment Configuration Guide](Environment-Configuration.md).

## Error Handling

The module implements comprehensive error handling:

1. **Prerequisite Failures**: Shows specific guidance on resolving prerequisite issues
2. **Network Issues**: Provides troubleshooting steps for connectivity problems
3. **Enrollment Failures**: Logs detailed error information and suggests remediation
4. **UI Exceptions**: Gracefully handles interface errors with user-friendly messages

## Logging

Logs are stored in `%TEMP%\WS1_Enrollment_Logs` by default with the naming pattern `WS1_Enrollment_yyyyMMdd_HHmmss.log`. The log file contains:

- Timestamp for each event
- Log level (INFO, WARNING, ERROR)
- Detailed message about the operation
- Success/failure status

## Relationship with Other Components

| Component | Relationship | Integration Cohesion Score | Notes |
|-----------|-------------|---------------------------|-------|
| Invoke-WorkspaceOneSetup.ps1 | Called by | 5 (Moderate) | Main entry point |
| Test-WS1Environment.ps1 | Used by | 4 (Moderate) | For validation |
| LoggingModule.psm1 | Complementary | 3 (Loose) | For consistent logging |

## Performance Considerations

- GUI operations run on the main thread
- Enrollment operations use background workers to prevent UI freezing
- Progress reporting minimizes UI thread impact

## Security Considerations

- Requires standard user permissions for basic operation
- Certain enrollment steps may require elevated privileges
- All user inputs are validated to prevent injection attacks
- Sensitive information is not stored in plain text

## Future Enhancements

- Multi-language support
- Enhanced branding customization
- Support for additional authentication methods
- Offline enrollment capabilities
- Improved diagnostics and self-repair 
