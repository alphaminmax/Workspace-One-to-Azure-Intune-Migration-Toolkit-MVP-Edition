![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Migration Engine Module

## Overview

The MigrationEngine module serves as the core orchestration engine for the Workspace ONE to Azure/Intune Migration Toolkit. It manages the execution of migration steps, provides comprehensive error handling, and implements robust rollback mechanisms to ensure safe and reliable migrations.

## Key Features

- **Step Sequencing**: Manages the orderly execution of migration steps across defined phases
- **Error Handling**: Comprehensive error catching and reporting mechanism
- **Rollback Mechanisms**: Sophisticated rollback capabilities to restore the system to a known state if migration fails
- **Backup Management**: Component-level and system-wide backup functionality
- **Phase Management**: Organizes migration in logical phases (Preparation, WS1Disconnect, IntuneConnect, Verification, Cleanup)
- **Transaction Support**: Optional PowerShell transaction support for atomic operations
- **System Restore Integration**: Creates system restore points before critical operations

## Prerequisites

- PowerShell 5.1 or later
- Administrative privileges on the migration target system
- LoggingModule (included in toolkit)
- Workspace ONE and/or Intune modules depending on migration scenario

## Module Functions

### Core Functions

#### Initialize-MigrationEngine

Initializes the migration engine with configuration settings and creates a new migration session.

```powershell
Initialize-MigrationEngine [-ConfigPath <String>] [-BackupLocation <String>] [-LogPath <String>]
```

**Parameters:**
- `ConfigPath`: Path to the migration configuration file
- `BackupLocation`: Location where backups will be stored
- `LogPath`: Path where log files will be stored

**Example:**
```powershell
Initialize-MigrationEngine -ConfigPath "./config/migration-config.json" -BackupLocation "C:\MigrationBackups"
```

#### Register-MigrationStep

Registers a migration step to be executed by the engine.

```powershell
Register-MigrationStep -Name <String> -ScriptBlock <ScriptBlock> [-Phase <String>] [-RollbackScriptBlock <ScriptBlock>] [-ContinueOnError <Boolean>]
```

**Parameters:**
- `Name`: Name of the migration step
- `ScriptBlock`: Script block to execute for this step
- `Phase`: Migration phase this step belongs to
- `RollbackScriptBlock`: Script block to execute if rollback is needed
- `ContinueOnError`: Whether to continue with migration if this step fails

**Example:**
```powershell
Register-MigrationStep -Name "Backup WS1 Configuration" -ScriptBlock {
    Backup-WorkspaceOneConfiguration -Path "$env:TEMP\WS1Backup"
} -Phase "Preparation" -RollbackScriptBlock {
    Write-LogMessage -Message "No rollback needed for backup step" -Level INFO
}
```

#### Start-Migration

Starts the migration process by executing all registered migration steps in sequence.

```powershell
Start-Migration [-UseTransactions] [-CreateSystemRestore]
```

**Parameters:**
- `UseTransactions`: Whether to use PowerShell transactions for atomic operations
- `CreateSystemRestore`: Whether to create a System Restore point before migration

**Example:**
```powershell
Start-Migration -CreateSystemRestore
```

### Rollback Mechanism Functions

#### New-MigrationBackup

Creates a backup of a component for potential rollback.

```powershell
New-MigrationBackup -Component <String> [-BackupScript <ScriptBlock>] [-Data <Object>] [-BackupPath <String>]
```

**Parameters:**
- `Component`: Name of the component to back up
- `BackupScript`: Script block to execute for the backup
- `Data`: Additional data to store with the backup
- `BackupPath`: Path where the backup will be stored

**Example:**
```powershell
New-MigrationBackup -Component "WorkspaceOneConfig" -BackupScript {
    param($Path)
    Export-WorkspaceOneConfiguration -OutputPath $Path
} -BackupPath "C:\MigrationBackups\WS1Config"
```

#### Invoke-MigrationRollback

Performs a rollback of the migration by executing rollback procedures for already executed migration steps in reverse order.

```powershell
Invoke-MigrationRollback [-Force] [-StopAfterStepName <String>]
```

**Parameters:**
- `Force`: Force rollback even if some steps cannot be rolled back
- `StopAfterStepName`: Stop rollback after executing the rollback for the specified step

**Example:**
```powershell
Invoke-MigrationRollback -Force
```

#### Restore-MigrationBackup

Restores a previously created backup for a specific component.

```powershell
Restore-MigrationBackup -Component <String> [-BackupPath <String>] [-RestoreScript <ScriptBlock>]
```

**Parameters:**
- `Component`: Name of the component to restore
- `BackupPath`: Path to the backup to restore
- `RestoreScript`: Script block to execute for the restore

**Example:**
```powershell
Restore-MigrationBackup -Component "WorkspaceOneConfig" -RestoreScript {
    param($Path)
    Import-WorkspaceOneConfiguration -InputPath "$Path\ws1_config.xml"
}
```

#### Register-RollbackAction

Registers a rollback action for later execution if migration fails.

```powershell
Register-RollbackAction -Name <String> -RollbackScript <ScriptBlock> [-Priority <Int32>]
```

**Parameters:**
- `Name`: Name of the rollback action
- `RollbackScript`: Script block to execute for rollback
- `Priority`: Priority of the rollback action (higher numbers executed first)

**Example:**
```powershell
Register-RollbackAction -Name "Restore WS1 Enrollment" -RollbackScript {
    Restore-MDMEnrollment -Provider "WS1"
} -Priority 100
```

#### Backup-RegistryKey

Creates a backup of a registry key for potential rollback.

```powershell
Backup-RegistryKey -Path <String> -BackupPath <String> [-Recursive]
```

**Parameters:**
- `Path`: Registry path to back up
- `BackupPath`: Path where the backup file will be saved
- `Recursive`: Whether to include subkeys in the backup

**Example:**
```powershell
Backup-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -BackupPath "C:\MigrationBackups\WUpdatePolicy.reg" -Recursive
```

#### Restore-RegistryKey

Restores a registry key from a previously created backup.

```powershell
Restore-RegistryKey -BackupPath <String>
```

**Parameters:**
- `BackupPath`: Path to the registry backup file

**Example:**
```powershell
Restore-RegistryKey -BackupPath "C:\MigrationBackups\WUpdatePolicy.reg"
```

#### Backup-File

Creates a backup copy of a file for potential rollback.

```powershell
Backup-File -Path <String> -BackupPath <String>
```

**Parameters:**
- `Path`: Path to the file to back up
- `BackupPath`: Path where the backup will be saved

**Example:**
```powershell
Backup-File -Path "C:\config\settings.xml" -BackupPath "C:\MigrationBackups\settings.xml"
```

#### Restore-File

Restores a file from a previously created backup.

```powershell
Restore-File -BackupPath <String> -DestinationPath <String>
```

**Parameters:**
- `BackupPath`: Path to the backup file
- `DestinationPath`: Path where the file will be restored

**Example:**
```powershell
Restore-File -BackupPath "C:\MigrationBackups\settings.xml" -DestinationPath "C:\config\settings.xml"
```

#### Register-SystemRestorePoint

Creates a Windows System Restore point before major migration operations.

```powershell
Register-SystemRestorePoint -Description <String>
```

**Parameters:**
- `Description`: Description for the restore point

**Example:**
```powershell
Register-SystemRestorePoint -Description "Before WS1 to Intune Migration"
```

#### Get-RollbackSummary

Returns a summary of all rollback options currently available.

```powershell
Get-RollbackSummary
```

**Example:**
```powershell
$rollbackOptions = Get-RollbackSummary
$rollbackOptions.SystemRestorePoints | Format-Table
```

#### Test-CanUndo

Checks if rollback mechanisms are available for a migration.

```powershell
Test-CanUndo [-MigrationID <String>]
```

**Parameters:**
- `MigrationID`: ID of the migration to check

**Example:**
```powershell
$undoStatus = Test-CanUndo
if ($undoStatus.CanUndo) {
    Write-Host "Migration can be undone"
}
```

## Migration Workflow

The MigrationEngine organizes the migration process into distinct phases:

1. **Preparation**: 
   - Backup current configuration
   - Create system restore point
   - Validate prerequisites
   - Gather device information

2. **WS1Disconnect**:
   - Backup Workspace ONE settings
   - Unenroll from Workspace ONE
   - Remove Workspace ONE components

3. **IntuneConnect**:
   - Prepare for Intune enrollment
   - Enroll in Intune/Azure AD
   - Apply policies and configurations

4. **Verification**:
   - Validate Intune enrollment
   - Verify policy application
   - Check required applications
   - Validate security settings

5. **Cleanup**:
   - Remove temporary files
   - Finalize migration logs
   - Notify administrators

## Rollback Strategy

The MigrationEngine implements a multi-layered rollback strategy:

1. **Component-Level Rollback**: Each component can define its own rollback actions
2. **Step-Based Rollback**: Migration steps are rolled back in reverse order of execution
3. **System-Level Rollback**: System restore points for complete system recovery
4. **Manual Recovery Guidance**: If automated rollback fails, detailed guidance is provided

### Rollback Implementation Best Practices

When implementing migration steps with rollback support:

1. **Always register rollback actions** for steps that make system changes
2. **Create backups before destructive operations**
3. **Store original state** information for comparison during verification
4. **Test rollback procedures** thoroughly before production use
5. **Implement idempotent operations** that can be safely repeated

## Example Usage

### Basic Migration With Rollback

```powershell
# Initialize the migration engine
Initialize-MigrationEngine -ConfigPath "./config/migration-config.json"

# Register migration steps with rollback
Register-MigrationStep -Name "Backup Current Configuration" -ScriptBlock {
    New-MigrationBackup -Component "SystemConfiguration" -BackupScript {
        Backup-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -BackupPath "$BackupLocation\policies.reg" -Recursive
    }
} -Phase "Preparation"

Register-MigrationStep -Name "Unenroll from Workspace ONE" -ScriptBlock {
    # Backup enrollment first
    Backup-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -BackupPath "$BackupLocation\enrollments.reg" -Recursive
    
    # Unenroll from Workspace ONE
    $result = Invoke-WS1Unenrollment
    if (-not $result) {
        throw "Failed to unenroll from Workspace ONE"
    }
} -Phase "WS1Disconnect" -RollbackScriptBlock {
    # Restore enrollment
    Restore-RegistryKey -BackupPath "$BackupLocation\enrollments.reg"
    Write-LogMessage -Message "Restored enrollment registry keys" -Level INFO
}

# Start the migration with system restore point
Start-Migration -CreateSystemRestore
```

### Handling Migration Failure

```powershell
try {
    # Initialize and start migration
    Initialize-MigrationEngine
    
    # Register steps
    # ...
    
    # Start migration
    $result = Start-Migration
    
    if (-not $result) {
        throw "Migration failed"
    }
}
catch {
    Write-LogMessage -Message "Migration failed: $_" -Level ERROR
    
    # Check if rollback is possible
    $canUndo = Test-CanUndo
    
    if ($canUndo.CanUndo) {
        Write-LogMessage -Message "Attempting rollback..." -Level WARNING
        Invoke-MigrationRollback -Force
    }
    else {
        Write-LogMessage -Message "Cannot roll back changes automatically. Manual intervention required." -Level ERROR
    }
}
```

## Integration with Other Modules

The MigrationEngine module integrates with several other components of the toolkit:

- **LoggingModule**: For comprehensive logging of migration activities
- **ConfigurationManager**: To access migration configuration settings
- **WorkspaceOneIntegration**: To interact with Workspace ONE
- **IntuneIntegration**: To interact with Microsoft Intune
- **SecurityFoundation**: For secure handling of credentials and settings

## Troubleshooting

### Common Issues

1. **Migration step fails but rollback doesn't execute**:
   - Ensure rollback script blocks are properly registered
   - Check if the step has `ContinueOnError` set to `$true`

2. **System Restore point not created**:
   - Verify that System Restore is enabled on the system
   - Ensure the user has administrative privileges

3. **Incomplete rollback**:
   - Check the rollback logs for specific failures
   - Some changes may require manual intervention

### Diagnostic Commands

```powershell
# Check migration status
$migrationSteps = $script:MigrationSteps
$migrationSteps | Format-Table Name, Phase, Status, HasExecuted

# Examine rollback options
Get-RollbackSummary | ConvertTo-Json -Depth 5

# Test if rollback is possible
Test-CanUndo
```

## Security Considerations

- The MigrationEngine requires administrative privileges to function correctly
- Backups may contain sensitive information and should be stored securely
- System Restore points are system-wide and may be accessible to other administrators
- Registry backups may include security-sensitive information

## Related Documentation

- [Workspace ONE Integration](WorkspaceOneIntegration.md)
- [Intune Integration](IntuneIntegration.md)
- [Secure Credential Handling](Secure-Credential-Handling.md)
- [Security Foundation](SecurityFoundation.md) 
