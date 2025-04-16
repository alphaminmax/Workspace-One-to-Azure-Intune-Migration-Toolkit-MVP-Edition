# Graph API Integration Module

## Overview

The Graph API Integration module (`GraphAPIIntegration.psm1`) provides a standardized interface for interacting with Microsoft Graph API, with specific functionality for BitLocker recovery key migration, device management, and other Azure/Intune operations.

This module serves as the primary interface between the Workspace ONE to Azure/Intune migration solution and Microsoft's cloud services, enabling secure and reliable data exchange during the migration process.

## Key Features

- **BitLocker Recovery Key Migration**: Extracts and securely backs up BitLocker recovery keys to Azure AD
- **Multiple Backup Methods**: Supports both native Windows BitLocker cmdlets and custom Graph API implementations
- **Device Type Detection**: Automatically determines the appropriate backup method based on device join type
- **Validation**: Confirms successful migration of BitLocker keys to Azure AD
- **Error Handling**: Comprehensive error handling with detailed logging
- **Token Management**: Efficient token acquisition and caching for Graph API operations

## Prerequisites

- PowerShell 5.1 or later
- Microsoft.Graph.Intune PowerShell module
- Azure AD application registration with appropriate permissions
- Network connectivity to Microsoft Graph API endpoints

## Installation

The module is part of the Workspace ONE to Azure/Intune migration toolkit and is automatically installed with the solution.

## Configuration

The module uses the main configuration file (`config/settings.json`) for authentication and operational settings. The following settings are particularly relevant:

```json
{
    "targetTenant": {
        "clientID": "your-client-id",
        "clientSecret": "your-client-secret",
        "tenantName": "your-tenant-name",
        "tenantID": "your-tenant-id"
    },
    "bitlockerMethod": "MIGRATE"
}
```

- `targetTenant`: Contains authentication details for Azure AD/Microsoft Graph
- `bitlockerMethod`: Set to "MIGRATE" to enable BitLocker key migration functionality

## Module Functions

### Initialize-GraphAPIIntegration

Initializes the module and loads configuration settings.

```powershell
Initialize-GraphAPIIntegration [-ConfigPath <string>]
```

#### Parameters:
- `ConfigPath`: (Optional) Path to the JSON configuration file. Default is the standard config path.

#### Example:
```powershell
Initialize-GraphAPIIntegration -ConfigPath "C:\Path\To\custom-settings.json"
```

### Connect-MsGraph

Establishes a connection to Microsoft Graph API using client credentials flow.

```powershell
Connect-MsGraph [-ClientID <string>] [-ClientSecret <string>] [-TenantID <string>]
```

#### Parameters:
- `ClientID`: (Optional) The Azure AD application client ID. Default is from configuration.
- `ClientSecret`: (Optional) The Azure AD application client secret. Default is from configuration.
- `TenantID`: (Optional) The Azure AD tenant ID. Default is from configuration.

#### Example:
```powershell
Connect-MsGraph -ClientID "12345678-1234-1234-1234-123456789012" -TenantID "11111111-1111-1111-1111-111111111111"
```

### Get-BitLockerRecoveryKey

Extracts BitLocker recovery key information from a specified volume.

```powershell
Get-BitLockerRecoveryKey [-DriveLetter <string>]
```

#### Parameters:
- `DriveLetter`: (Optional) The drive letter to extract the recovery key from. Default is the system drive.

#### Example:
```powershell
$bitlockerInfo = Get-BitLockerRecoveryKey -DriveLetter "D:"
$recoveryKey = $bitlockerInfo.RecoveryPassword
```

### Backup-BitLockerKeyToAzureAD

Backs up a BitLocker recovery key to Azure AD using either native Windows cmdlets or Graph API.

```powershell
Backup-BitLockerKeyToAzureAD [-DriveLetter <string>] [-ForceMsGraph]
```

#### Parameters:
- `DriveLetter`: (Optional) The drive letter to back up the recovery key for. Default is the system drive.
- `ForceMsGraph`: (Switch) Forces the use of Graph API instead of native Windows cmdlets.

#### Example:
```powershell
# Back up system drive using optimal method
Backup-BitLockerKeyToAzureAD

# Force Graph API method for D: drive
Backup-BitLockerKeyToAzureAD -DriveLetter "D:" -ForceMsGraph
```

### Confirm-BitLockerKeyBackup

Verifies that a BitLocker recovery key has been successfully backed up to Azure AD.

```powershell
Confirm-BitLockerKeyBackup [-DriveLetter <string>]
```

#### Parameters:
- `DriveLetter`: (Optional) The drive letter to verify backup for. Default is the system drive.

#### Example:
```powershell
$isBackedUp = Confirm-BitLockerKeyBackup -DriveLetter "C:"
```

### Migrate-BitLockerKeys

Main function for migrating all BitLocker recovery keys on the device to Azure AD.

```powershell
Migrate-BitLockerKeys [-ForceMigration]
```

#### Parameters:
- `ForceMigration`: (Switch) Forces migration even if not enabled in the configuration.

#### Example:
```powershell
# Migrate all BitLocker keys according to configuration
$results = Migrate-BitLockerKeys

# Force migration regardless of configuration
$results = Migrate-BitLockerKeys -ForceMigration
```

## Usage Examples

### Migrating All BitLocker Keys

```powershell
# Import the module
Import-Module -Name ".\src\modules\GraphAPIIntegration.psm1"

# Run the migration
$migrationResults = Migrate-BitLockerKeys

# Check results
if ($migrationResults.Success) {
    Write-Host "All BitLocker keys successfully migrated to Azure AD"
} else {
    Write-Host "Some errors occurred during migration:"
    foreach ($error in $migrationResults.Errors) {
        Write-Host "- $error"
    }
}
```

### Backing Up a Specific Drive's BitLocker Key

```powershell
# Import the module
Import-Module -Name ".\src\modules\GraphAPIIntegration.psm1"

# Initialize
Initialize-GraphAPIIntegration

# Back up specific drive
$backupSuccess = Backup-BitLockerKeyToAzureAD -DriveLetter "D:"

if ($backupSuccess) {
    Write-Host "D: drive BitLocker key backed up successfully"
} else {
    Write-Host "Failed to back up BitLocker key for D: drive"
}
```

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify the client ID, client secret, and tenant ID in the configuration
   - Ensure the Azure AD application has appropriate permissions

2. **BitLocker Key Extraction Failures**
   - Verify BitLocker is enabled and a recovery password protector exists
   - Check that the BitLocker PowerShell module is available

3. **Key Backup Failures**
   - For native cmdlet method: Ensure the user is signed in with appropriate credentials
   - For Graph API method: Verify network connectivity to Graph endpoints

### Logging

The module uses the `LoggingModule` for detailed logging. View these logs to diagnose issues:

```powershell
Get-Content -Path "C:\Temp\Logs\MigrationLog.log"
```

## Integration with Other Modules

The Graph API Integration module works closely with:

- **SecurityFoundation**: For secure credential management
- **LoggingModule**: For comprehensive logging
- **MigrationVerification**: For validating the migration process
- **RollbackMechanism**: For handling rollback scenarios 