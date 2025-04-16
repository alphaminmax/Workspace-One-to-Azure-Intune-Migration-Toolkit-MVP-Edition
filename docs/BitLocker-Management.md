# BitLocker Management in Migration Toolkit

## Overview

The BitLockerManager module provides comprehensive functionality for managing BitLocker encryption during the migration process from Workspace ONE to Intune. This module helps ensure that BitLocker recovery keys are preserved and migrated correctly to the new management platform.

## Workflow Diagrams

### BitLocker Migration Flow

The BitLocker migration workflow diagram can be found in the following file:
[BitLocker Management Flow Diagram](diagrams/bitlocker-flow.mmd)

### BitLocker Process Sequence

A detailed sequence diagram showing the BitLocker management process interactions is available in:
[BitLocker Management Sequence Diagram](diagrams/bitlocker-sequence.mmd)

## Key Features

- Backup and restore BitLocker recovery keys
- Multiple backup destinations: local file, Azure AD, or Azure Key Vault
- Integration with Azure Key Vault for secure key storage
- Verification of BitLocker encryption status
- Support for enabling BitLocker if not already enabled
- Seamless migration of BitLocker management from Workspace ONE to Intune

## Module Functions

| Function | Description |
|----------|-------------|
| `Set-BitLockerConfiguration` | Configures BitLocker Manager settings |
| `Test-BitLockerEncryption` | Verifies the encryption status of a drive |
| `Backup-BitLockerKeyToFile` | Backs up BitLocker recovery key to a local file |
| `Backup-BitLockerKeyToKeyVault` | Backs up BitLocker recovery key to Azure Key Vault |
| `Get-BitLockerKeyFromKeyVault` | Retrieves a BitLocker recovery key from Azure Key Vault |
| `Invoke-BitLockerMigration` | Migrates BitLocker configuration from Workspace ONE to Intune |
| `Initialize-BitLockerManager` | Initializes the BitLocker Manager module |

## Usage Examples

### Initialize BitLocker Manager

```powershell
# Initialize with default settings
Initialize-BitLockerManager

# Initialize with custom backup path
Initialize-BitLockerManager -BackupPath "C:\Backup\BitLocker" -RecoveryKeyBackupType "Local"
```

### Configure Azure Key Vault Integration

```powershell
# Configure BitLocker with Key Vault integration
Set-BitLockerConfiguration -AzureKeyVaultName "MyKeyVault" `
                          -AzureTenantId "tenant-id" `
                          -RecoveryKeyBackupType "KeyVault"
```

### Backup BitLocker Keys

```powershell
# Backup to local file
Backup-BitLockerKeyToFile -DriveLetter "C:"

# Backup to Key Vault
Backup-BitLockerKeyToKeyVault -DriveLetter "C:"
```

### Migrate BitLocker Configuration

```powershell
# Migrate BitLocker configuration with backup to Azure AD and Key Vault
Invoke-BitLockerMigration -DriveLetter "C:" -BackupToAzureAD -BackupToKeyVault
```

## Integration with Other Modules

The BitLocker Manager module integrates with:

- **SecurityFoundation**: For secure credential handling
- **LoggingModule**: For comprehensive logging
- **RollbackMechanism**: For rollback in case of migration failure
- **GraphAPIIntegration**: For Azure AD operations

## Error Handling

The module includes comprehensive error handling for common scenarios:

- BitLocker not enabled or available
- Azure Key Vault connectivity issues
- Permission or access control problems
- Recovery key backup failures

All errors are logged through the LoggingModule for troubleshooting and auditing. 