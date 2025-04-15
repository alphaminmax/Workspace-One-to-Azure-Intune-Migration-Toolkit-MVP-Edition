# Workspace One Enrollment and Management Toolkit

A comprehensive PowerShell-based solution for facilitating Workspace One enrollment with Intune integration for Windows 10/11 environments, including tools for script validation, deployment, and enrollment status tracking.

## Overview

This toolkit provides:

1. **Workspace One Enrollment**: User-friendly GUI wizard for guiding users through the enrollment process
2. **Integration with Intune**: Support for Workspace One and Microsoft Intune integration
3. **Script Testing**: Automated validation of PowerShell scripts for syntax errors and initialization issues
4. **Script Reporting**: Detailed HTML reports of test results
5. **Environment Validation**: Tools to verify system readiness for enrollment
6. **Deployment Options**: Support for Intune, SCCM, and GPO deployment methods
7. **Enrollment Dashboard**: Web-based visualization of enrollment status

## System Requirements

- Windows 10 (Build 1809 or later) or Windows 11
- PowerShell 5.1 or later (PowerShell 7.x recommended for advanced features)
- Administrative privileges (for certain operations)
- Network connectivity to enrollment servers

## Project Structure

The project is organized into the following directories:

```
workspace-one-toolkit/
├── src/
│   ├── modules/          # PowerShell modules
│   │   ├── WorkspaceOneWizard.psm1
│   │   └── LoggingModule.psm1
│   └── scripts/          # PowerShell scripts
│       ├── Invoke-WorkspaceOneSetup.ps1
│       ├── Test-WS1Environment.ps1
│       └── TestScripts.ps1
├── config/               # Configuration files
│   ├── WS1Config.json
│   └── settings.json
├── deployment/           # Deployment resources
│   └── Deploy-WS1EnrollmentTools.ps1
├── dashboard/            # Enrollment visualization
│   └── WS1EnrollmentDashboard.html
├── docs/                 # Documentation
│   ├── LoggingModule.md
│   ├── ValidationTool.md
│   └── README_UPDATES.md
├── archived/             # Archived and deprecated files
└── README.md             # This file
```

## Getting Started

### Installation

1. Download or clone this repository to your local machine
2. Ensure execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. Navigate to the script directory:
   ```powershell
   cd path\to\workspace-one-toolkit
   ```

### Basic Usage

To run the complete solution (script testing and enrollment wizard):

```powershell
.\src\scripts\Invoke-WorkspaceOneSetup.ps1
```

### Command-Line Parameters

| Parameter | Description |
|-----------|-------------|
| `-TestScriptsOnly` | Only run script testing, skip enrollment |
| `-EnrollmentOnly` | Skip script testing, only run enrollment |
| `-NoGUI` | Run enrollment in console mode without GUI |
| `-Verbose` | Show detailed progress information |

### Examples

Test scripts only, skip enrollment:
```powershell
.\src\scripts\Invoke-WorkspaceOneSetup.ps1 -TestScriptsOnly
```

Run enrollment wizard only:
```powershell
.\src\scripts\Invoke-WorkspaceOneSetup.ps1 -EnrollmentOnly
```

Run enrollment in console mode (no GUI):
```powershell
.\src\scripts\Invoke-WorkspaceOneSetup.ps1 -EnrollmentOnly -NoGUI
```

## Core Components

### Workspace One Wizard Module

The `WorkspaceOneWizard.psm1` module provides:

- **User-Friendly Interface**: Easy-to-follow steps for enrollment
- **Prerequisite Checking**: Verifies network connectivity and device eligibility
- **Detailed Logging**: Comprehensive logging of enrollment process
- **Error Handling**: Clear error messages and troubleshooting information

### Environment Validation Tool

The `Test-WS1Environment.ps1` script:

- Validates system readiness for Workspace One enrollment
- Checks network connectivity to enrollment servers
- Verifies administrative privileges and system requirements
- Generates an HTML readiness report

### Deployment Tool

The `Deploy-WS1EnrollmentTools.ps1` script supports:

- **Multiple Deployment Methods**: Intune, SCCM, and GPO
- **Custom Configurations**: Organization name and enrollment server URL
- **Silent Mode**: Optional silent mode for automated deployment
- **Documentation**: Generates deployment instructions

### Enrollment Dashboard

The `WS1EnrollmentDashboard.html` provides:

- Real-time visualization of enrollment status
- Device distribution by platform
- Departmental enrollment progress
- Issue tracking and monitoring

## Customization

### Configuration File

The `WS1Config.json` file allows customization of:

```json
{
    "EnrollmentServer": "https://ws1.example.com",
    "IntuneIntegrationEnabled": true,
    "LogLevel": "INFO",
    "OrganizationName": "Your Company Name",
    "HelpDeskPhoneNumber": "1-800-555-1234",
    "HelpDeskEmail": "helpdesk@example.com"
}
```

## Troubleshooting

### Log Files

- Script testing logs: `C:\Temp\Logs\ScriptTests_[timestamp]`
- Enrollment logs: `%TEMP%\WS1_Enrollment_Logs`
- Setup logs: `C:\Temp\Logs\WS1_Setup_[timestamp]`

### Common Issues

**Issue**: Script testing fails with access denied errors  
**Solution**: Run PowerShell as Administrator

**Issue**: Enrollment wizard fails to connect to server  
**Solution**: Verify network connectivity and server URL

**Issue**: GUI does not appear  
**Solution**: Ensure .NET Framework is properly installed

## Integration with Endpoint Management

This solution can be deployed through your existing endpoint management solution:

1. **Group Policy**: Use GPO to deploy and schedule the script
2. **Intune**: Package the scripts as a Win32 app or PowerShell script
3. **SCCM/MECM**: Deploy as a package or application

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Developed for modern Windows 10/11 environments
- Compatible with Workspace One and Microsoft Intune
- Designed for enterprise deployment scenarios


