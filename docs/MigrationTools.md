# Workspace One to Azure Migration Tools

This document provides details about the tools developed to facilitate the migration from VMware Workspace One to Microsoft Azure.

## Core Tools

### TestScripts.ps1

**Purpose**: Validates the quality and functionality of all PowerShell scripts used in the migration process.

**Key Features**:
- Checks script syntax for errors that might cause failures during migration
- Tests script initialization to ensure proper setup of variables and modules
- Generates detailed HTML reports showing test results
- Logs all test activities for troubleshooting
- Helps maintain code quality throughout the migration project

**Usage Example**:
```powershell
.\src\scripts\TestScripts.ps1
```

### LoggingModule.psm1

**Purpose**: Provides standardized logging across all migration scripts for consistent troubleshooting and auditing.

**Key Features**:
- Multiple log levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- Logs to both console and file for easy monitoring
- Consistent timestamping and formatting
- Task duration tracking for performance monitoring
- System information collection for environmental context
- Optional Windows Event Log integration

**Usage Example**:
```powershell
Import-Module .\src\modules\LoggingModule.psm1
Initialize-Logging -LogPath "C:\Temp\MigrationLogs"
Write-LogMessage -Message "Starting migration process" -Level INFO
```

### Test-WS1Environment.ps1

**Purpose**: Analyzes the current Workspace One environment to establish baseline configurations and requirements for Azure.

**Key Features**:
- Validates current Workspace One configuration
- Checks device enrollment status
- Identifies potential migration blockers
- Generates HTML report of environment readiness
- Provides recommendations for migration preparation

**Usage Example**:
```powershell
.\src\scripts\Test-WS1Environment.ps1 -GenerateReport
```

## Migration Support Tools

### Device-Inventory.ps1

**Purpose**: Creates a comprehensive inventory of devices currently managed by Workspace One.

**Key Features**:
- Collects device hardware and software information
- Records current management status and policies
- Identifies special configurations or exceptions
- Generates CSV export for migration planning
- Tags devices for migration waves based on complexity

### Policy-Mapper.ps1

**Purpose**: Maps Workspace One policies to their Azure Intune equivalents.

**Key Features**:
- Analyzes current Workspace One policy configurations
- Identifies equivalent Intune policies 
- Highlights configurations that need manual attention
- Creates policy migration documentation
- Generates PowerShell scripts for policy creation in Intune

### App-Inventory.ps1

**Purpose**: Inventories applications managed through Workspace One for recreation in Intune.

**Key Features**:
- Lists all applications with their deployment settings
- Records installation requirements and dependencies
- Documents application targeting and user assignments
- Identifies applications needing repackaging for Intune
- Creates migration checklist for application deployment

## Migration Execution Tools

### Start-DeviceMigration.ps1

**Purpose**: Performs the actual migration of a device from Workspace One to Azure.

**Key Features**:
- Supports different migration methods (in-place, side-by-side, fresh enrollment)
- Backs up current device configuration before changes
- Handles Workspace One un-enrollment when needed
- Performs Azure/Intune enrollment
- Validates successful migration
- Comprehensive logging of all migration steps

### Migration-Dashboard.ps1

**Purpose**: Provides real-time visualization of migration progress.

**Key Features**:
- Visual dashboard showing migration status by department/location
- Progress tracking for each migration phase
- Success/failure metrics and reporting
- Issue identification and tracking
- Executive-level reporting capabilities

## Validation and Cleanup Tools

### Test-MigratedDevice.ps1

**Purpose**: Validates that a migrated device is functioning correctly in Azure.

**Key Features**:
- Verifies successful enrollment in Azure/Intune
- Confirms policy application and compliance
- Checks application installation status
- Tests network connectivity and resource access
- Generates validation report

### Remove-WS1Components.ps1

**Purpose**: Safely removes Workspace One components after successful migration.

**Key Features**:
- Removes Workspace One agent when no longer needed
- Cleans up registry entries and configuration files
- Preserves user data and settings
- Logs cleanup actions for audit purposes
- Can be scheduled to run post-migration verification

## Getting Started

1. Begin with environment assessment using `Test-WS1Environment.ps1`
2. Create inventory using `Device-Inventory.ps1` and `App-Inventory.ps1`
3. Plan policy migration with `Policy-Mapper.ps1`
4. Execute migrations using `Start-DeviceMigration.ps1`
5. Monitor progress with `Migration-Dashboard.ps1`
6. Validate migrations with `Test-MigratedDevice.ps1`
7. Clean up with `Remove-WS1Components.ps1` 