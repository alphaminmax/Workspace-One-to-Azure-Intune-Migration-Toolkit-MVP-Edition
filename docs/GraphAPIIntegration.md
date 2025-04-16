# Graph API Integration Module

## Overview

The Graph API Integration module provides a standardized interface for interacting with Microsoft Graph API. This module enables key functionality for Azure/Intune operations including BitLocker recovery key migration, device management, user management, and more.

## Key Features

- **Modern Authentication** - Uses MSAL (Microsoft Authentication Library) for secure authentication
- **Caching Support** - Improves performance by caching API responses
- **Retry Logic** - Implements exponential backoff and intelligent retry for reliability
- **Error Handling** - Comprehensive error handling with detailed logging
- **BitLocker Integration** - Specialized functions for managing BitLocker recovery keys
- **Helper Functions** - Simplified access to common Graph API operations

## Prerequisites

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1+
- Microsoft.Graph.Intune module
- MSAL.PS module (optional, will be auto-installed if missing)
- Network connectivity to Graph API endpoints
- Azure AD application with appropriate permissions

## Module Setup

### Installation

The GraphAPIIntegration module is part of the WS1 Migration Toolkit and is automatically available when the toolkit is installed. No separate installation is required.

### Configuration

The module requires a configuration file (`config/settings.json`) with the following structure:

```json
{
  "targetTenant": {
    "clientID": "00000000-0000-0000-0000-000000000000",
    "clientSecret": "your-client-secret",
    "tenantName": "contoso.com",
    "tenantID": "00000000-0000-0000-0000-000000000000"
  },
  "bitlockerMethod": "MIGRATE"
}
```

## Core Functions

### Authentication

- `Initialize-GraphAPIIntegration` - Set up Graph API integration with configuration
- `Get-MsalToken` - Get authentication token using MSAL
- `Connect-MsGraph` - Establish connection to Microsoft Graph API

### API Operations

- `Invoke-GraphApiRequest` - Make requests to Microsoft Graph API with caching and retry support

### BitLocker Operations

- `Get-BitLockerRecoveryKey` - Extract BitLocker recovery key from local device
- `Backup-BitLockerKeyToAzureAD` - Back up BitLocker recovery key to Azure AD
- `Confirm-BitLockerKeyBackup` - Verify BitLocker key backup in Azure AD
- `Migrate-BitLockerKeys` - Migrate all BitLocker keys to Azure AD

### Helper Functions

- `Get-GraphDevice` - Get device information from Intune/Azure AD
- `Get-GraphUser` - Get user information from Azure AD
- `Get-GraphBitLockerKeys` - Get BitLocker keys from Azure AD
- `Set-DevicePrimaryUser` - Set primary user for device in Intune
- `Register-DeviceWithAutopilot` - Register device with Windows Autopilot
- `Get-DeviceComplianceStatus` - Get device compliance status
- `Get-DeviceHardwareHash` - Extract hardware hash ID from local device
- `Register-DeviceToAutopilot` - Extract hardware hash and register with Autopilot

## Usage Examples

### Initialize and Connect

```powershell
# Initialize the module with default configuration
Initialize-GraphAPIIntegration

# Connect to Microsoft Graph API
Connect-MsGraph
```

### BitLocker Key Migration

```powershell
# Migrate all BitLocker keys to Azure AD
$results = Migrate-BitLockerKeys

# Get detailed results
$results | Format-List

# Force migration even if not enabled in configuration
Migrate-BitLockerKeys -ForceMigration
```

### Device Management

```powershell
# Get device by name
$device = Get-GraphDevice -DeviceName "Laptop123"

# Get all Windows devices
$allDevices = Get-GraphDevice -Filter "operatingSystem eq 'Windows'"

# Set primary user for a device
Set-DevicePrimaryUser -DeviceId $device.id -UserId "user@contoso.com"

# Check device compliance
$complianceStatus = Get-DeviceComplianceStatus -DeviceId $device.id
```

### BitLocker Key Management

```powershell
# Extract BitLocker key from C: drive
$key = Get-BitLockerRecoveryKey -DriveLetter "C:"

# Back up BitLocker key to Azure AD
Backup-BitLockerKeyToAzureAD -DriveLetter "C:"

# Verify BitLocker key is backed up
$isBackedUp = Confirm-BitLockerKeyBackup -DriveLetter "C:"

# Get all BitLocker keys for a device from Azure AD
$deviceKeys = Get-GraphBitLockerKeys -DeviceId $device.id -IncludeKeyValue
```

### Autopilot Registration

```powershell
# Extract hardware hash from local device
$hardwareInfo = Get-DeviceHardwareHash

# Save hardware hash to file
$hardwareInfo = Get-DeviceHardwareHash -OutputPath "C:\Temp\HardwareHash.csv"

# Extract hardware hash and register with Autopilot in one step
$result = Register-DeviceToAutopilot -GroupTag "Sales" -AssignedUser "user@contoso.com"

# Register device on a specific platform
$result = Register-DeviceToAutopilot -Platform "Windows" -GroupTag "IT"

# Check if registration was successful
if ($result.Success) {
    Write-Host "Device registered successfully with serial number: $($result.SerialNumber)"
}
```

## Error Handling

The GraphAPIIntegration module provides comprehensive error handling:

1. All functions include try/catch blocks with detailed error logging
2. API calls include intelligent retry with exponential backoff
3. Authentication failures trigger automatic token refresh
4. Response parsing includes detailed error information from Graph API

## API Permissions Required

The Azure AD application used for Graph API access should have the following permissions:

- `DeviceManagementManagedDevices.Read.All` - Read device information
- `DeviceManagementManagedDevices.ReadWrite.All` - Manage devices
- `BitlockerKey.Read.All` - Read BitLocker keys
- `BitlockerKey.ReadWrite.All` - Manage BitLocker keys
- `User.Read.All` - Read user information
- `Device.Read.All` - Read device information in Azure AD

## Integration with Other Modules

The GraphAPIIntegration module integrates with:

- **LoggingModule** - For comprehensive logging
- **SecurityFoundation** - For secure credential management
- **AutopilotIntegration** - For Windows Autopilot operations

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify client ID, client secret, and tenant ID
   - Ensure the application has proper permissions
   - Check network connectivity to Azure AD endpoints

2. **Permission Errors**
   - Verify the application has been granted admin consent
   - Check that the required permissions are assigned

3. **BitLocker Key Backup Failures**
   - Ensure the device is Azure AD joined or hybrid joined
   - Verify BitLocker is enabled and protection is on
   - Check that recovery keys exist on the device

### Logging

The module uses the LoggingModule for detailed logging. To increase verbosity:

```powershell
Set-LogLevel -Level DEBUG
```

## References

- [Microsoft Graph API Documentation](https://docs.microsoft.com/en-us/graph/overview)
- [BitLocker Recovery Key API](https://docs.microsoft.com/en-us/graph/api/resources/bitlockerrecoverykey)
- [Microsoft Authentication Library](https://docs.microsoft.com/en-us/azure/active-directory/develop/msal-overview) 