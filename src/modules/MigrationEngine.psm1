<# 
.SYNOPSIS
    Migration Engine Module for Workspace ONE to Intune migration
.DESCRIPTION
    Core engine that orchestrates the migration process, including step sequencing, 
    error handling, and rollback mechanisms.
.NOTES
    File Name  : MigrationEngine.psm1
    Author     : Workspace ONE to Intune Migration Team
    Version    : 1.0.0
    Requires   : PowerShell 5.1 or later
#>

#Region Module Variables
# Module-level variables
$script:MigrationSteps = @()
$script:CurrentStepIndex = -1
$script:MigrationID = $null
$script:MigrationStartTime = $null
$script:MigrationConfig = @{}
$script:LogEnabled = $true
$script:LogPath = "$env:ProgramData\WS1_Migration\Logs"
$script:RestorePoints = @()
$script:BackupLocation = "$env:ProgramData\WS1_Migration\Backups"
$script:RollbackStack = [System.Collections.Stack]::new()
$script:MigrationPhases = @("Preparation", "WS1Disconnect", "IntuneConnect", "Verification", "Cleanup")
$script:CurrentPhase = "NotStarted"
#EndRegion

#Region Migration Engine Core Functions

function Initialize-MigrationEngine {
    <#
    .SYNOPSIS
        Initializes the migration engine.
    .DESCRIPTION
        Sets up the migration engine with configuration and creates a new migration session.
    .PARAMETER ConfigPath
        Path to the migration configuration file.
    .PARAMETER BackupLocation
        Location where backups will be stored.
    .PARAMETER LogPath
        Path where log files will be stored.
    .EXAMPLE
        Initialize-MigrationEngine -ConfigPath "./config/migration-config.json" -BackupLocation "C:\Backups"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "./config/settings.json",

        [Parameter(Mandatory = $false)]
        [string]$BackupLocation = "$env:ProgramData\WS1_Migration\Backups",

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "$env:ProgramData\WS1_Migration\Logs"
    )

    try {
        # Import necessary modules
        Import-Module -Name "$PSScriptRoot\LoggingModule.psm1" -ErrorAction Stop
        
        # Set module variables
        $script:LogPath = $LogPath
        $script:BackupLocation = $BackupLocation
        $script:MigrationStartTime = Get-Date
        $script:MigrationID = "MIG-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        
        # Create log and backup directories
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        
        if (-not (Test-Path -Path $script:BackupLocation)) {
            New-Item -Path $script:BackupLocation -ItemType Directory -Force | Out-Null
        }
        
        # Create migration-specific backup folder
        $migrationBackupFolder = Join-Path -Path $script:BackupLocation -ChildPath $script:MigrationID
        New-Item -Path $migrationBackupFolder -ItemType Directory -Force | Out-Null
        
        # Load configuration
        if (Test-Path -Path $ConfigPath) {
            $script:MigrationConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
            Write-LogMessage -Message "Migration configuration loaded from $ConfigPath" -Level INFO
        }
        else {
            Write-LogMessage -Message "Configuration file not found at $ConfigPath, using defaults" -Level WARNING
            $script:MigrationConfig = @{}
        }
        
        # Reset migration steps and state
        $script:MigrationSteps = @()
        $script:CurrentStepIndex = -1
        $script:RollbackStack.Clear()
        $script:RestorePoints = @()
        $script:CurrentPhase = "NotStarted"
        
        Write-LogMessage -Message "Migration engine initialized with ID: $script:MigrationID" -Level INFO
        return $true
    }
    catch {
        Write-Error "Failed to initialize migration engine: $_"
        return $false
    }
}

function Register-MigrationStep {
    <#
    .SYNOPSIS
        Registers a migration step to be executed.
    .DESCRIPTION
        Adds a migration step to the engine's execution plan.
    .PARAMETER Name
        Name of the migration step.
    .PARAMETER ScriptBlock
        Script block to execute for this step.
    .PARAMETER Phase
        Migration phase this step belongs to.
    .PARAMETER RollbackScriptBlock
        Script block to execute if rollback is needed.
    .PARAMETER ContinueOnError
        Whether to continue with migration if this step fails.
    .EXAMPLE
        Register-MigrationStep -Name "Backup WS1 Configuration" -ScriptBlock { Backup-WorkspaceOneConfig } -Phase "Preparation" -RollbackScriptBlock { Restore-WorkspaceOneConfig }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Preparation", "WS1Disconnect", "IntuneConnect", "Verification", "Cleanup")]
        [string]$Phase = "Preparation",

        [Parameter(Mandatory = $false)]
        [scriptblock]$RollbackScriptBlock = $null,

        [Parameter(Mandatory = $false)]
        [bool]$ContinueOnError = $false
    )

    try {
        # Create step object
        $step = [PSCustomObject]@{
            Name = $Name
            ScriptBlock = $ScriptBlock
            RollbackScriptBlock = $RollbackScriptBlock
            Phase = $Phase
            Status = "Pending"
            StartTime = $null
            EndTime = $null
            ErrorDetails = $null
            ContinueOnError = $ContinueOnError
            StepIndex = $script:MigrationSteps.Count
            HasExecuted = $false
        }
        
        # Add step to the list
        $script:MigrationSteps += $step
        
        Write-LogMessage -Message "Migration step registered: $Name (Phase: $Phase)" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to register migration step: $_" -Level ERROR
        return $false
    }
}

function Start-Migration {
    <#
    .SYNOPSIS
        Starts the migration process.
    .DESCRIPTION
        Executes all registered migration steps in sequence.
    .PARAMETER UseTransactions
        Whether to use PowerShell transactions for atomic operations.
    .PARAMETER CreateSystemRestore
        Whether to create a System Restore point before migration.
    .EXAMPLE
        Start-Migration -CreateSystemRestore
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$UseTransactions,

        [Parameter(Mandatory = $false)]
        [switch]$CreateSystemRestore
    )

    try {
        # Check if migration engine is initialized
        if ($null -eq $script:MigrationID) {
            Write-LogMessage -Message "Migration engine not initialized. Call Initialize-MigrationEngine first." -Level ERROR
            return $false
        }
        
        # Check if steps are registered
        if ($script:MigrationSteps.Count -eq 0) {
            Write-LogMessage -Message "No migration steps registered. Use Register-MigrationStep to register steps." -Level ERROR
            return $false
        }
        
        Write-LogMessage -Message "Starting migration process (ID: $script:MigrationID)" -Level INFO
        
        # Create system restore point if requested
        if ($CreateSystemRestore) {
            try {
                Write-LogMessage -Message "Creating System Restore point before migration" -Level INFO
                $restorePointResult = Checkpoint-Computer -Description "WS1 to Intune Migration - $script:MigrationID" -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
                
                if ($restorePointResult) {
                    $script:RestorePoints += [PSCustomObject]@{
                        Type = "SystemRestore"
                        CreationTime = Get-Date
                        Description = "WS1 to Intune Migration - $script:MigrationID"
                    }
                    Write-LogMessage -Message "System Restore point created successfully" -Level INFO
                }
            }
            catch {
                Write-LogMessage -Message "Failed to create System Restore point: $_. Continuing migration." -Level WARNING
            }
        }
        
        # Execute each step
        $script:CurrentStepIndex = 0
        $previousPhase = "NotStarted"
        
        foreach ($step in $script:MigrationSteps) {
            # Update current phase if changing
            if ($step.Phase -ne $previousPhase) {
                $script:CurrentPhase = $step.Phase
                $previousPhase = $step.Phase
                Write-LogMessage -Message "Starting migration phase: $($step.Phase)" -Level INFO
            }
            
            Write-LogMessage -Message "Executing step $($script:CurrentStepIndex + 1) of $($script:MigrationSteps.Count): $($step.Name)" -Level INFO
            
            $step.Status = "Running"
            $step.StartTime = Get-Date
            
            try {
                # Wrap in transaction if requested
                if ($UseTransactions) {
                    Start-Transaction
                    
                    try {
                        # Invoke the step script block
                        $result = Invoke-Command -ScriptBlock $step.ScriptBlock
                        
                        # Complete transaction if successful
                        Complete-Transaction
                    }
                    catch {
                        # Undo transaction if failed
                        Undo-Transaction
                        throw $_
                    }
                }
                else {
                    # Invoke the step script block without transaction
                    $result = Invoke-Command -ScriptBlock $step.ScriptBlock
                }
                
                $step.Status = "Completed"
                $step.HasExecuted = $true
                $step.EndTime = Get-Date
                
                # Push to rollback stack if rollback script is available
                if ($null -ne $step.RollbackScriptBlock) {
                    $script:RollbackStack.Push($step)
                }
                
                Write-LogMessage -Message "Step completed successfully: $($step.Name)" -Level INFO
            }
            catch {
                $step.Status = "Failed"
                $step.ErrorDetails = $_
                $step.EndTime = Get-Date
                
                Write-LogMessage -Message "Step failed: $($step.Name) - $_" -Level ERROR
                
                if (-not $step.ContinueOnError) {
                    Write-LogMessage -Message "Migration halted due to step failure. Initiating rollback..." -Level ERROR
                    
                    # Initiate rollback if configured to stop on error
                    Invoke-MigrationRollback
                    return $false
                }
                else {
                    Write-LogMessage -Message "Continuing migration despite step failure (ContinueOnError=True)" -Level WARNING
                }
            }
            
            $script:CurrentStepIndex++
        }
        
        Write-LogMessage -Message "Migration completed successfully" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage -Message "Migration process failed: $_" -Level ERROR
        
        # Attempt rollback
        Invoke-MigrationRollback
        return $false
    }
}

#EndRegion

#Region Rollback Mechanisms

function New-MigrationBackup {
    <#
    .SYNOPSIS
        Creates a backup of a component for potential rollback.
    .DESCRIPTION
        Creates a backup of a migration component and registers it for potential rollback.
    .PARAMETER Component
        Name of the component to back up.
    .PARAMETER BackupScript
        Script block to execute for the backup.
    .PARAMETER Data
        Additional data to store with the backup.
    .PARAMETER BackupPath
        Path where the backup will be stored.
    .EXAMPLE
        New-MigrationBackup -Component "WorkspaceOneConfig" -BackupScript { Backup-WorkspaceOneConfiguration -Path $BackupPath } -BackupPath "C:\Backups\WS1Config"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $false)]
        [scriptblock]$BackupScript = $null,

        [Parameter(Mandatory = $false)]
        [object]$Data = $null,

        [Parameter(Mandatory = $false)]
        [string]$BackupPath = $null
    )

    try {
        # Generate backup path if not provided
        if (-not $BackupPath) {
            $BackupPath = Join-Path -Path $script:BackupLocation -ChildPath $script:MigrationID -AdditionalChildPath $Component
        }
        
        # Create backup directory
        if (-not (Test-Path -Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }
        
        Write-LogMessage -Message "Creating backup for component: $Component" -Level INFO
        
        # Execute backup script if provided
        $backupResult = $null
        if ($null -ne $BackupScript) {
            $backupResult = Invoke-Command -ScriptBlock $BackupScript -ArgumentList $BackupPath
        }
        
        # Create backup metadata
        $backupMetadata = [PSCustomObject]@{
            Component = $Component
            CreationTime = Get-Date
            BackupPath = $BackupPath
            MigrationID = $script:MigrationID
            Data = $Data
            Result = $backupResult
        }
        
        # Save metadata
        $metadataPath = Join-Path -Path $BackupPath -ChildPath "backup-metadata.json"
        $backupMetadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Force
        
        Write-LogMessage -Message "Backup created for component: $Component at $BackupPath" -Level INFO
        return $backupMetadata
    }
    catch {
        Write-LogMessage -Message ("Failed to create backup for component " + $Component + ": " + $_) -Level ERROR
        return $null
    }
}

function Invoke-MigrationRollback {
    <#
    .SYNOPSIS
        Performs a rollback of the migration.
    .DESCRIPTION
        Executes rollback procedures for already executed migration steps in reverse order.
    .PARAMETER Force
        Force rollback even if some steps cannot be rolled back.
    .PARAMETER StopAfterStepName
        Stop rollback after executing the rollback for the specified step.
    .EXAMPLE
        Invoke-MigrationRollback -Force
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [string]$StopAfterStepName = $null
    )

    try {
        Write-LogMessage -Message "Initiating migration rollback" -Level WARNING
        
        # Check if rollback stack is empty
        if ($script:RollbackStack.Count -eq 0) {
            Write-LogMessage -Message "No rollback steps available" -Level WARNING
            return $false
        }
        
        # Execute rollback steps in reverse order (from stack)
        $rollbackSuccess = $true
        $rollbackStepCount = 0
        
        while ($script:RollbackStack.Count -gt 0) {
            $step = $script:RollbackStack.Pop()
            $rollbackStepCount++
            
            Write-LogMessage -Message "Executing rollback for step: $($step.Name)" -Level INFO
            
            try {
                if ($null -ne $step.RollbackScriptBlock) {
                    # Execute the rollback script
                    Invoke-Command -ScriptBlock $step.RollbackScriptBlock
                    Write-LogMessage -Message "Rollback completed for step: $($step.Name)" -Level INFO
                }
                else {
                    Write-LogMessage -Message "No rollback script defined for step: $($step.Name)" -Level WARNING
                }
                
                # Stop if we've reached the specified step
                if ($StopAfterStepName -and $step.Name -eq $StopAfterStepName) {
                    Write-LogMessage -Message "Stopping rollback after step: $StopAfterStepName" -Level INFO
                    break
                }
            }
            catch {
                Write-LogMessage -Message "Failed to rollback step $($step.Name): $_" -Level ERROR
                
                if (-not $Force) {
                    $rollbackSuccess = $false
                    Write-LogMessage -Message "Rollback halted due to error" -Level ERROR
                    break
                }
                else {
                    Write-LogMessage -Message "Continuing rollback despite error (Force=True)" -Level WARNING
                }
            }
        }
        
        # Check if system restore points were created
        $systemRestorePoints = $script:RestorePoints | Where-Object { $_.Type -eq "SystemRestore" }
        if ($systemRestorePoints.Count -gt 0 -and (-not $rollbackSuccess -or $Force)) {
            Write-LogMessage -Message "Rollback unsuccessful or forced. Consider restoring to System Restore point manually." -Level WARNING
            
            foreach ($restorePoint in $systemRestorePoints) {
                Write-LogMessage -Message "System Restore point available from $($restorePoint.CreationTime) with description: $($restorePoint.Description)" -Level INFO
            }
        }
        
        Write-LogMessage -Message "Migration rollback completed. $rollbackStepCount steps processed." -Level INFO
        return $rollbackSuccess
    }
    catch {
        Write-LogMessage -Message "Critical error during rollback: $_" -Level ERROR
        return $false
    }
}

function Restore-MigrationBackup {
    <#
    .SYNOPSIS
        Restores a specific migration backup.
    .DESCRIPTION
        Restores a previously created backup for a specific component.
    .PARAMETER Component
        Name of the component to restore.
    .PARAMETER BackupPath
        Path to the backup to restore. If not specified, the most recent backup will be used.
    .PARAMETER RestoreScript
        Script block to execute for the restore.
    .EXAMPLE
        Restore-MigrationBackup -Component "WorkspaceOneConfig" -RestoreScript { Restore-WorkspaceOneConfiguration -Path $BackupPath }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $false)]
        [string]$BackupPath = $null,

        [Parameter(Mandatory = $false)]
        [scriptblock]$RestoreScript = $null
    )

    try {
        Write-LogMessage -Message "Restoring backup for component: $Component" -Level INFO
        
        # Find backup if path not specified
        if (-not $BackupPath) {
            $componentFolder = Join-Path -Path $script:BackupLocation -ChildPath $script:MigrationID -AdditionalChildPath $Component
            
            if (Test-Path -Path $componentFolder) {
                $BackupPath = $componentFolder
            }
            else {
                # Look for any backup of this component
                $allBackups = Get-ChildItem -Path $script:BackupLocation -Directory -Recurse | 
                    Where-Object { $_.Name -eq $Component -or (Test-Path -Path (Join-Path -Path $_.FullName -ChildPath "backup-metadata.json")) }
                
                if ($allBackups.Count -gt 0) {
                    # Sort by creation time and get the most recent
                    $latestBackup = $allBackups | Sort-Object CreationTime -Descending | Select-Object -First 1
                    $BackupPath = $latestBackup.FullName
                }
                else {
                    Write-LogMessage -Message "No backup found for component: $Component" -Level ERROR
                    return $false
                }
            }
        }
        
        # Verify backup exists
        if (-not (Test-Path -Path $BackupPath)) {
            Write-LogMessage -Message "Backup path does not exist: $BackupPath" -Level ERROR
            return $false
        }
        
        # Load metadata
        $metadataPath = Join-Path -Path $BackupPath -ChildPath "backup-metadata.json"
        if (Test-Path -Path $metadataPath) {
            $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
        }
        else {
            $metadata = [PSCustomObject]@{
                Component = $Component
                CreationTime = (Get-Item -Path $BackupPath).CreationTime
                BackupPath = $BackupPath
                MigrationID = "Unknown"
                Data = $null
                Result = $null
            }
        }
        
        # Execute restore script if provided
        if ($null -ne $RestoreScript) {
            $result = Invoke-Command -ScriptBlock $RestoreScript -ArgumentList $BackupPath, $metadata
            
            if ($result) {
                Write-LogMessage -Message "Successfully restored backup for component: $Component from $BackupPath" -Level INFO
                return $true
            }
            else {
                Write-LogMessage -Message "Restore script for component $Component did not indicate success" -Level WARNING
                return $false
            }
        }
        else {
            Write-LogMessage -Message "No restore script provided for component: $Component" -Level WARNING
            return $true  # Return true because the backup was found, even if no restore script was provided
        }
    }
    catch {
        Write-LogMessage -Message ("Failed to restore backup for component " + $Component + ": " + $_) -Level ERROR
        return $false
    }
}

function Register-RollbackAction {
    <#
    .SYNOPSIS
        Registers a rollback action for later execution.
    .DESCRIPTION
        Adds a rollback action to the rollback stack.
    .PARAMETER Name
        Name of the rollback action.
    .PARAMETER RollbackScript
        Script block to execute for rollback.
    .PARAMETER Priority
        Priority of the rollback action (higher numbers executed first).
    .EXAMPLE
        Register-RollbackAction -Name "Restore WS1 Configuration" -RollbackScript { Restore-WorkspaceOneConfiguration } -Priority 100
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$RollbackScript,

        [Parameter(Mandatory = $false)]
        [int]$Priority = 0
    )

    try {
        # Create rollback action
        $rollbackAction = [PSCustomObject]@{
            Name = $Name
            RollbackScriptBlock = $RollbackScript
            Priority = $Priority
            RegistrationTime = Get-Date
            StepIndex = $script:CurrentStepIndex
        }
        
        # Add to rollback stack
        $script:RollbackStack.Push($rollbackAction)
        
        Write-LogMessage -Message "Registered rollback action: $Name (Priority: $Priority)" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to register rollback action: $_" -Level ERROR
        return $false
    }
}

function Backup-RegistryKey {
    <#
    .SYNOPSIS
        Creates a backup of a registry key.
    .DESCRIPTION
        Exports a registry key to a file for potential rollback.
    .PARAMETER Path
        Registry path to back up.
    .PARAMETER BackupPath
        Path where the backup file will be saved.
    .PARAMETER Recursive
        Whether to include subkeys in the backup.
    .EXAMPLE
        Backup-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -BackupPath "C:\Backups\WUpdatePolicy.reg" -Recursive
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $false)]
        [switch]$Recursive
    )

    try {
        Write-LogMessage -Message "Backing up registry key: $Path" -Level INFO
        
        # Create directory if it doesn't exist
        $backupDir = Split-Path -Path $BackupPath -Parent
        if (-not (Test-Path -Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        
        # Convert HKLM, HKCU paths to registry format
        $regPath = $Path -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace 'HKCU:\\', 'HKEY_CURRENT_USER\'
        
        # Use reg.exe to export the key
        $regArgs = @('export', $regPath, $BackupPath)
        if ($Recursive) {
            $regArgs += '/y'
        }
        
        $regProcess = Start-Process -FilePath 'reg.exe' -ArgumentList $regArgs -NoNewWindow -PassThru -Wait
        
        if ($regProcess.ExitCode -eq 0) {
            Write-LogMessage -Message "Registry key successfully backed up to $BackupPath" -Level INFO
            return $true
        }
        else {
            Write-LogMessage -Message "Failed to back up registry key. Exit code: $($regProcess.ExitCode)" -Level ERROR
            return $false
        }
    }
    catch {
        Write-LogMessage -Message "Failed to back up registry key: $_" -Level ERROR
        return $false
    }
}

function Restore-RegistryKey {
    <#
    .SYNOPSIS
        Restores a registry key from backup.
    .DESCRIPTION
        Imports a previously exported registry key.
    .PARAMETER BackupPath
        Path to the registry backup file.
    .EXAMPLE
        Restore-RegistryKey -BackupPath "C:\Backups\WUpdatePolicy.reg"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    try {
        Write-LogMessage -Message "Restoring registry key from backup: $BackupPath" -Level INFO
        
        # Verify backup file exists
        if (-not (Test-Path -Path $BackupPath)) {
            Write-LogMessage -Message "Registry backup file not found: $BackupPath" -Level ERROR
            return $false
        }
        
        # Use reg.exe to import the key
        $regProcess = Start-Process -FilePath 'reg.exe' -ArgumentList @('import', $BackupPath) -NoNewWindow -PassThru -Wait
        
        if ($regProcess.ExitCode -eq 0) {
            Write-LogMessage -Message "Registry key successfully restored from $BackupPath" -Level INFO
            return $true
        }
        else {
            Write-LogMessage -Message "Failed to restore registry key. Exit code: $($regProcess.ExitCode)" -Level ERROR
            return $false
        }
    }
    catch {
        Write-LogMessage -Message "Failed to restore registry key: $_" -Level ERROR
        return $false
    }
}

function Backup-File {
    <#
    .SYNOPSIS
        Creates a backup copy of a file.
    .DESCRIPTION
        Creates a backup copy of a file for potential rollback.
    .PARAMETER Path
        Path to the file to back up.
    .PARAMETER BackupPath
        Path where the backup will be saved.
    .EXAMPLE
        Backup-File -Path "C:\Config\settings.xml" -BackupPath "C:\Backups\settings.xml"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    try {
        Write-LogMessage -Message "Backing up file: $Path" -Level INFO
        
        # Verify source file exists
        if (-not (Test-Path -Path $Path)) {
            Write-LogMessage -Message "Source file not found: $Path" -Level ERROR
            return $false
        }
        
        # Create backup directory if it doesn't exist
        $backupDir = Split-Path -Path $BackupPath -Parent
        if (-not (Test-Path -Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy the file
        Copy-Item -Path $Path -Destination $BackupPath -Force
        
        if (Test-Path -Path $BackupPath) {
            Write-LogMessage -Message "File successfully backed up to $BackupPath" -Level INFO
            return $true
        }
        else {
            Write-LogMessage -Message "Failed to backup file: Backup file not created" -Level ERROR
            return $false
        }
    }
    catch {
        Write-LogMessage -Message "Failed to backup file: $_" -Level ERROR
        return $false
    }
}

function Restore-File {
    <#
    .SYNOPSIS
        Restores a file from backup.
    .DESCRIPTION
        Restores a file from a previously created backup.
    .PARAMETER BackupPath
        Path to the backup file.
    .PARAMETER DestinationPath
        Path where the file will be restored.
    .EXAMPLE
        Restore-File -BackupPath "C:\Backups\settings.xml" -DestinationPath "C:\Config\settings.xml"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    try {
        Write-LogMessage -Message "Restoring file from backup: $BackupPath to $DestinationPath" -Level INFO
        
        # Verify backup file exists
        if (-not (Test-Path -Path $BackupPath)) {
            Write-LogMessage -Message "Backup file not found: $BackupPath" -Level ERROR
            return $false
        }
        
        # Create destination directory if it doesn't exist
        $destDir = Split-Path -Path $DestinationPath -Parent
        if (-not (Test-Path -Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy the file
        Copy-Item -Path $BackupPath -Destination $DestinationPath -Force
        
        if (Test-Path -Path $DestinationPath) {
            Write-LogMessage -Message "File successfully restored to $DestinationPath" -Level INFO
            return $true
        }
        else {
            Write-LogMessage -Message "Failed to restore file: Destination file not created" -Level ERROR
            return $false
        }
    }
    catch {
        Write-LogMessage -Message "Failed to restore file: $_" -Level ERROR
        return $false
    }
}

function Register-SystemRestorePoint {
    <#
    .SYNOPSIS
        Creates a system restore point.
    .DESCRIPTION
        Creates a Windows System Restore point before major migration operations.
    .PARAMETER Description
        Description for the restore point.
    .EXAMPLE
        Register-SystemRestorePoint -Description "Before WS1 to Intune Migration"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {
        Write-LogMessage -Message "Creating System Restore point: $Description" -Level INFO
        
        # Check if system restore is enabled
        try {
            $srEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "RPSessionInterval" -ErrorAction Stop).RPSessionInterval -ne 0
        }
        catch {
            $srEnabled = $false
            Write-LogMessage -Message "Could not determine System Restore status: $_" -Level WARNING
        }
        
        if (-not $srEnabled) {
            Write-LogMessage -Message "System Restore appears to be disabled. Restore point may not be created." -Level WARNING
        }
        
        # Create restore point
        $result = Checkpoint-Computer -Description $Description -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
        
        if ($result) {
            # Add to restore points collection
            $script:RestorePoints += [PSCustomObject]@{
                Type = "SystemRestore"
                CreationTime = Get-Date
                Description = $Description
            }
            
            Write-LogMessage -Message "System Restore point created successfully" -Level INFO
            return $true
        }
        else {
            Write-LogMessage -Message "Failed to create System Restore point" -Level WARNING
            return $false
        }
    }
    catch {
        Write-LogMessage -Message "Failed to create System Restore point: $_" -Level ERROR
        return $false
    }
}

function Get-RollbackSummary {
    <#
    .SYNOPSIS
        Gets a summary of available rollback options.
    .DESCRIPTION
        Returns a summary of all rollback options currently available.
    .EXAMPLE
        Get-RollbackSummary
    #>
    [CmdletBinding()]
    param ()

    try {
        Write-LogMessage -Message "Generating rollback summary" -Level INFO
        
        # Collect rollback information
        $summary = [PSCustomObject]@{
            MigrationID = $script:MigrationID
            RollbackActionsCount = $script:RollbackStack.Count
            RollbackActions = @($script:RollbackStack.ToArray())
            SystemRestorePoints = @($script:RestorePoints | Where-Object { $_.Type -eq "SystemRestore" })
            BackupLocation = $script:BackupLocation
            ComponentBackups = @()
        }
        
        # Get component backups
        if (Test-Path -Path $script:BackupLocation) {
            $migrationFolder = Join-Path -Path $script:BackupLocation -ChildPath $script:MigrationID
            
            if (Test-Path -Path $migrationFolder) {
                $componentFolders = Get-ChildItem -Path $migrationFolder -Directory
                
                foreach ($folder in $componentFolders) {
                    $metadataPath = Join-Path -Path $folder.FullName -ChildPath "backup-metadata.json"
                    
                    if (Test-Path -Path $metadataPath) {
                        $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
                        $summary.ComponentBackups += $metadata
                    }
                    else {
                        $summary.ComponentBackups += [PSCustomObject]@{
                            Component = $folder.Name
                            CreationTime = $folder.CreationTime
                            BackupPath = $folder.FullName
                            MigrationID = $script:MigrationID
                            Data = $null
                            Result = $null
                        }
                    }
                }
            }
        }
        
        return $summary
    }
    catch {
        Write-LogMessage -Message "Failed to generate rollback summary: $_" -Level ERROR
        return $null
    }
}

function Test-CanUndo {
    <#
    .SYNOPSIS
        Tests if a migration can be undone.
    .DESCRIPTION
        Checks if rollback mechanisms are available for a migration.
    .PARAMETER MigrationID
        ID of the migration to check.
    .EXAMPLE
        Test-CanUndo -MigrationID "MIG-20230805-120000"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$MigrationID = $script:MigrationID
    )

    try {
        Write-LogMessage -Message "Testing if migration $MigrationID can be undone" -Level INFO
        
        $canUndo = $false
        $reasons = @()
        
        # Check if rollback stack has items
        if ($script:RollbackStack.Count -gt 0) {
            $canUndo = $true
            $reasons += "Rollback actions are available"
        }
        
        # Check for system restore points
        if ($script:RestorePoints.Count -gt 0) {
            $canUndo = $true
            $reasons += "System Restore points are available"
        }
        
        # Check for component backups
        $migrationFolder = Join-Path -Path $script:BackupLocation -ChildPath $MigrationID
        if (Test-Path -Path $migrationFolder) {
            $componentFolders = Get-ChildItem -Path $migrationFolder -Directory
            
            if ($componentFolders.Count -gt 0) {
                $canUndo = $true
                $reasons += "Component backups are available"
            }
        }
        
        $result = [PSCustomObject]@{
            MigrationID = $MigrationID
            CanUndo = $canUndo
            Reasons = $reasons
        }
        
        return $result
    }
    catch {
        Write-LogMessage -Message "Failed to test if migration can be undone: $_" -Level ERROR
        return $null
    }
}

#EndRegion Rollback Mechanisms

#Region Helper Functions

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes a log message.
    .DESCRIPTION
        Internal function to handle logging for the migration engine.
    .PARAMETER Message
        The message to log.
    .PARAMETER Level
        The level of the message (INFO, WARNING, ERROR, DEBUG).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Delegate to LoggingModule if available
    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level -Component "MigrationEngine"
    }
    else {
        # Fallback to console logging
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] [MigrationEngine] $Message"

        switch ($Level) {
            "INFO" { Write-Host $logMessage -ForegroundColor White }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "DEBUG" { Write-Host $logMessage -ForegroundColor Gray }
        }

        # Log to file if path exists
        if ($script:LogEnabled -and $script:LogPath) {
            $logFileName = "MigrationEngine_$(Get-Date -Format 'yyyyMMdd').log"
            $logFile = Join-Path -Path $script:LogPath -ChildPath $logFileName
            $logMessage | Out-File -FilePath $logFile -Append -Encoding utf8
        }
    }
}

#EndRegion Helper Functions

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-MigrationEngine',
    'Register-MigrationStep',
    'Start-Migration',
    'New-MigrationBackup',
    'Invoke-MigrationRollback',
    'Restore-MigrationBackup',
    'Register-RollbackAction',
    'Backup-RegistryKey',
    'Restore-RegistryKey',
    'Backup-File',
    'Restore-File',
    'Register-SystemRestorePoint',
    'Get-RollbackSummary',
    'Test-CanUndo'
) 