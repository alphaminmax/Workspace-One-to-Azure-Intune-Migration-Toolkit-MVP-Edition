# Rollback Mechanism for WS1 to Azure Migration

## Overview

The Rollback Mechanism is a critical component of the Workspace ONE to Azure/Intune migration toolkit. It provides a comprehensive safety net that enables automatic recovery when migration operations fail. This system-level protection minimizes disruption to end-users and ensures business continuity even when unexpected errors occur during migration.

## Table of Contents

- [Key Features](#key-features)
- [Implementation Components](#implementation-components)
- [Usage Guide](#usage-guide)
  - [Basic Usage](#basic-usage)
  - [Advanced Usage](#advanced-usage)
- [Function Reference](#function-reference)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Integration with Migration Process](#integration-with-migration-process)

## Key Features

- **Transaction-based approach**: Treats the entire migration as an atomic transaction
- **Multi-level protection**: Combines file, registry, and system-level backups
- **System Restore integration**: Utilizes Windows System Restore for deep system changes 
- **Automatic rollback**: Triggers recovery automatically when errors occur
- **Selective backups**: Creates targeted backups of critical components
- **Integrity verification**: Validates backups before relying on them
- **Cleanup management**: Handles temporary files and backup retention
- **Step-by-step execution**: Wraps each migration step with rollback protection

## Implementation Components

The Rollback Mechanism consists of the following components:

1. **RollbackMechanism.psm1**: Core PowerShell module implementing the rollback functionality
2. **Test-RollbackMechanism.ps1**: Test script demonstrating usage and validating functionality
3. **Integration with LoggingModule.psm1**: Comprehensive logging of all rollback operations

## Usage Guide

### Basic Usage

The simplest way to use the Rollback Mechanism is to wrap your migration process with the initialization and completion functions:

```powershell
# Import the module
Import-Module -Name ".\src\modules\RollbackMechanism.psm1"

# Initialize rollback
Initialize-RollbackMechanism -BackupPath "C:\MigrationBackups"

# Create a restore point (optional)
New-MigrationRestorePoint -Description "Pre-Migration Snapshot"

# Backup Workspace One configuration
Backup-WorkspaceOneConfiguration

# Perform migration operations
# ...

# Complete the transaction
Complete-MigrationTransaction -CleanupBackups $false
```

### Advanced Usage

For more robust implementation, use the `Invoke-MigrationStep` function to wrap each significant step:

```powershell
# Initialize rollback 
$backupFolder = Initialize-RollbackMechanism

# Create a restore point
New-MigrationRestorePoint

# Perform migration steps with automatic rollback on failure
Invoke-MigrationStep -Name "Remove Workspace One Agent" -ScriptBlock {
    # Code to remove Workspace One agent
    Uninstall-WorkspaceOneAgent
} -ErrorAction Stop

Invoke-MigrationStep -Name "Prepare for Azure Enrollment" -ScriptBlock {
    # Code to prepare for Azure enrollment
    Prepare-AzureEnrollment
} -ErrorAction Stop

Invoke-MigrationStep -Name "Enroll in Azure/Intune" -ScriptBlock {
    # Code to enroll in Azure/Intune
    Register-AzureDevice
} -ErrorAction Stop

# Complete the transaction
Complete-MigrationTransaction
```

## Function Reference

### `Initialize-RollbackMechanism`

Initializes the rollback environment and prepares for migration operations.

**Parameters:**
- `-BackupPath` (optional): Custom path for storing backups

**Returns:** The path to the backup folder

### `New-MigrationRestorePoint`

Creates a Windows System Restore point before migration.

**Parameters:**
- `-Description` (optional): Custom description for the restore point

**Returns:** Boolean indicating success or failure

### `Backup-WorkspaceOneConfiguration`

Creates a backup of Workspace One related registry keys, configuration files, and settings.

**Parameters:**
- `-BackupFolder` (optional): Custom folder for storing the backup

**Returns:** Boolean indicating success or failure

### `Restore-WorkspaceOneMigration`

Restores system to pre-migration state after a failure.

**Parameters:**
- `-UseSystemRestore` (optional): Whether to use System Restore for rollback
- `-Force` (optional): Force rollback even if some components can't be restored

**Returns:** Boolean indicating success or failure

### `Complete-MigrationTransaction`

Completes the migration transaction and optionally cleans up backups.

**Parameters:**
- `-CleanupBackups` (optional): Whether to delete backup files
- `-BackupRetentionDays` (optional): Days to keep backups before cleanup

**Returns:** None

### `Invoke-MigrationStep`

Executes a migration step with automatic rollback on failure.

**Parameters:**
- `-Name`: Name of the step
- `-ScriptBlock`: Code to execute
- `-ErrorAction` (optional): How to handle errors ('Stop', 'Continue', 'SilentlyContinue')
- `-UseSystemRestore` (optional): Whether to use System Restore for rollback

**Returns:** Output of the scriptblock if successful

## Best Practices

1. **Always initialize the rollback mechanism first**: Call `Initialize-RollbackMechanism` before any migration steps.

2. **Create system restore points for system-level changes**: Use `New-MigrationRestorePoint` when modifying system components.

3. **Wrap critical operations with `Invoke-MigrationStep`**: This ensures automatic rollback on failure.

4. **Keep migration steps focused and atomic**: Each step should do one logical operation to simplify rollback.

5. **Set appropriate error actions**: Use `-ErrorAction Stop` for critical steps to ensure rollback occurs.

6. **Test rollback scenarios**: Use the `Test-RollbackMechanism.ps1` script to validate rollback functionality.

7. **Retain backups in production**: Use `-CleanupBackups $false` in production to keep recovery options available.

8. **Consider backup storage**: For large deployments, ensure adequate space for backups.

## Troubleshooting

### Rollback fails to restore registry keys

**Possible causes:**
- Registry key permissions issues
- Invalid backup file
- Registry key locked by a process

**Solution:**
- Check registry key permissions
- Validate backup file contents
- Close applications that might lock registry keys

### System Restore point not created

**Possible causes:**
- System Restore service not running
- Insufficient disk space
- System Restore disabled by policy

**Solution:**
- Ensure System Restore service (SDRSVC) is running
- Check available disk space
- Verify System Restore is enabled in system settings

### Backup files missing or invalid

**Possible causes:**
- Disk space issues during backup
- Permission problems
- Antivirus interference

**Solution:**
- Ensure adequate disk space
- Run with appropriate permissions
- Configure antivirus exclusions for backup folders

## Integration with Migration Process

The Rollback Mechanism is designed to integrate seamlessly with the broader migration process:

### Pre-Migration Phase

During pre-migration assessment and planning:
- Test rollback functionality for your specific environment
- Ensure backup storage locations have adequate space
- Verify System Restore functionality if it will be used

### Migration Execution Phase

When executing the migration:
1. Initialize rollback mechanism
2. Create system restore point
3. Backup current configuration
4. Execute migration steps wrapped with rollback protection
5. Complete transaction and retain backups

### Post-Migration Phase

After successful migration:
- Implement a backup cleanup schedule
- Document rollback procedures for help desk staff
- Maintain recent backups until the migration is verified stable

### Failure Recovery

If migration fails:
1. Automatic rollback should restore system to pre-migration state
2. Verify system functionality after rollback
3. Check logs for failure reasons
4. Address underlying issues before retrying migration 