#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Provides rollback capability for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The RollbackMechanism module provides comprehensive rollback functionality for failed
    migrations from Workspace One to Azure/Intune. It includes functions for:
    - Creating system restore points before migration
    - Backing up critical registry keys and settings
    - Backing up user profiles selectively
    - Restoring from backups when migration fails
    - Cleaning up after successful migration or rollback
    
.NOTES
    File Name      : RollbackMechanism.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Copyright      : Organization Name
    Version        : 1.0.0
#>

# Import required modules
if (-not (Get-Module -Name 'LoggingModule' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LoggingModule.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module LoggingModule.psm1 not found in $PSScriptRoot"
    }
}

# Script-level variables
$script:BackupBasePath = $env:TEMP
$script:DefaultRestorePointDescription = "Pre-Migration Restore Point"
$script:RestorePointCreated = $false
$script:BackupItems = @()
$script:TransactionInProgress = $false

#region Private Functions

function Test-AdminRights {
    <#
    .SYNOPSIS
        Checks if the current PowerShell session has admin rights.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-BackupFolder {
    <#
    .SYNOPSIS
        Creates a new backup folder with a timestamp.
    #>
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFolder = Join-Path -Path $script:BackupBasePath -ChildPath "WS1Migration_Backup_$timestamp"
    
    if (-not (Test-Path -Path $backupFolder)) {
        New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
        Write-Log -Message "Created backup folder: $backupFolder" -Level Information
    }
    
    return $backupFolder
}

function Backup-RegistryKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$BackupFolder
    )
    
    $keyName = Split-Path -Path $Path -Leaf
    $backupFile = Join-Path -Path $BackupFolder -ChildPath "$keyName.reg"
    
    try {
        & reg.exe export "$Path" "$backupFile" /y | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Successfully backed up registry key: $Path" -Level Information
            return $backupFile
        } else {
            Write-Log -Message "Failed to backup registry key: $Path. Exit code: $LASTEXITCODE" -Level Error
            return $null
        }
    } catch {
        Write-Log -Message "Error backing up registry key: $Path. $_" -Level Error
        return $null
    }
}

function Test-BackupIntegrity {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BackupFolder
    )
    
    $allFiles = Get-ChildItem -Path $BackupFolder -Recurse -File
    $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
    
    if ($totalSize -eq 0 -or $null -eq $allFiles) {
        Write-Log -Message "Backup integrity check failed. Empty or missing backup." -Level Error
        return $false
    }
    
    # Check registry backup files
    $regFiles = $allFiles | Where-Object { $_.Extension -eq '.reg' }
    foreach ($file in $regFiles) {
        $content = Get-Content -Path $file.FullName -Raw
        if (-not $content -or $content.Length -lt 10) {
            Write-Log -Message "Registry backup file appears invalid: $($file.FullName)" -Level Error
            return $false
        }
    }
    
    Write-Log -Message "Backup integrity check passed. $($allFiles.Count) files, $totalSize bytes." -Level Information
    return $true
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the rollback mechanism for a migration operation.
    
.DESCRIPTION
    Sets up the rollback environment by creating a backup folder and initializing
    tracking variables. Must be called before any migration operations begin.
    
.PARAMETER BackupPath
    Optional. The path where backup files will be stored. If not specified,
    a folder in the temp directory will be used.
    
.EXAMPLE
    Initialize-RollbackMechanism -BackupPath "C:\MigrationBackups"
    
.OUTPUTS
    System.String. Returns the path to the backup folder.
#>
function Initialize-RollbackMechanism {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path -Path $_ -IsValid })]
        [string]$BackupPath
    )
    
    try {
        if (-not (Test-AdminRights)) {
            throw "Administrator rights are required to initialize the rollback mechanism."
        }
        
        # Set backup path if provided
        if ($BackupPath) {
            if (-not (Test-Path -Path $BackupPath)) {
                New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
            }
            $script:BackupBasePath = $BackupPath
        }
        
        $backupFolder = New-BackupFolder
        
        # Reset tracking variables
        $script:BackupItems = @()
        $script:RestorePointCreated = $false
        $script:TransactionInProgress = $true
        
        Write-Log -Message "Rollback mechanism initialized. Backup path: $backupFolder" -Level Information
        return $backupFolder
    }
    catch {
        Write-Log -Message "Failed to initialize rollback mechanism. $_" -Level Error
        throw "Failed to initialize rollback mechanism: $_"
    }
}

<#
.SYNOPSIS
    Creates a system restore point before migration.
    
.DESCRIPTION
    Creates a Windows System Restore Point that can be used to roll back
    system changes if migration fails.
    
.PARAMETER Description
    Optional. The description for the restore point. Defaults to "Pre-Migration Restore Point".
    
.EXAMPLE
    New-MigrationRestorePoint -Description "WS1 to Azure Pre-Migration"
    
.OUTPUTS
    System.Boolean. Returns $true if successful, $false otherwise.
#>
function New-MigrationRestorePoint {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Description = $script:DefaultRestorePointDescription
    )
    
    if (-not $script:TransactionInProgress) {
        throw "Rollback mechanism must be initialized first. Call Initialize-RollbackMechanism."
    }
    
    try {
        # Check if Windows restore is available
        $restoreService = Get-Service -Name "SDRSVC" -ErrorAction SilentlyContinue
        if ($null -eq $restoreService -or $restoreService.Status -ne "Running") {
            Write-Log -Message "System Restore service is not running. Restore point cannot be created." -Level Warning
            return $false
        }
        
        # Create restore point
        $restorePoint = Checkpoint-Computer -Description $Description -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
        $script:RestorePointCreated = $true
        Write-Log -Message "System restore point created successfully. Description: $Description" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to create system restore point. $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Backs up Workspace One configuration before migration.
    
.DESCRIPTION
    Creates a backup of Workspace One related registry keys, configuration files,
    and settings to enable rollback if needed.
    
.PARAMETER BackupFolder
    The folder where backups will be stored. If not specified, uses the folder
    created by Initialize-RollbackMechanism.
    
.EXAMPLE
    Backup-WorkspaceOneConfiguration -BackupFolder "C:\MigrationBackups\WS1_Backup"
    
.OUTPUTS
    System.Boolean. Returns $true if successful, $false otherwise.
#>
function Backup-WorkspaceOneConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$BackupFolder
    )
    
    if (-not $script:TransactionInProgress) {
        throw "Rollback mechanism must be initialized first. Call Initialize-RollbackMechanism."
    }
    
    if (-not $BackupFolder) {
        $BackupFolder = Join-Path -Path $script:BackupBasePath -ChildPath "WS1Migration_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (-not (Test-Path -Path $BackupFolder)) {
            New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
        }
    }
    
    try {
        # Create dedicated WS1 backup folder
        $ws1Folder = Join-Path -Path $BackupFolder -ChildPath "WorkspaceOne"
        if (-not (Test-Path -Path $ws1Folder)) {
            New-Item -Path $ws1Folder -ItemType Directory -Force | Out-Null
        }
        
        # Backup Workspace ONE registry keys
        $registryKeys = @(
            "HKLM\SOFTWARE\AirWatch",
            "HKLM\SOFTWARE\VMware, Inc.",
            "HKLM\SOFTWARE\Microsoft\Enrollments",
            "HKLM\SOFTWARE\Microsoft\EnterpriseResourceManager",
            "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceManagement"
        )
        
        $backupSuccess = $true
        foreach ($key in $registryKeys) {
            $backupFile = Backup-RegistryKey -Path $key -BackupFolder $ws1Folder
            if ($backupFile) {
                $script:BackupItems += @{
                    Type = "Registry"
                    Path = $key
                    BackupFile = $backupFile
                }
            } else {
                $backupSuccess = $false
                Write-Log -Message "Warning: Failed to backup registry key $key" -Level Warning
            }
        }
        
        # Backup Workspace ONE files and folders
        $ws1Paths = @(
            "$env:ProgramData\AirWatch",
            "$env:ProgramData\VMware"
        )
        
        foreach ($path in $ws1Paths) {
            if (Test-Path -Path $path) {
                $destinationPath = Join-Path -Path $ws1Folder -ChildPath (Split-Path -Path $path -Leaf)
                try {
                    Copy-Item -Path $path -Destination $destinationPath -Recurse -Force -ErrorAction Stop
                    $script:BackupItems += @{
                        Type = "Folder"
                        Path = $path
                        BackupFile = $destinationPath
                    }
                } catch {
                    $backupSuccess = $false
                    Write-Log -Message "Warning: Failed to backup folder $path. $_" -Level Warning
                }
            }
        }
        
        # Verify backup integrity
        $integrityCheck = Test-BackupIntegrity -BackupFolder $ws1Folder
        if (-not $integrityCheck) {
            Write-Log -Message "Backup integrity check failed. Backup may be incomplete." -Level Warning
            $backupSuccess = $false
        }
        
        Write-Log -Message "Workspace One configuration backup completed. Status: $(if ($backupSuccess) { 'Success' } else { 'Partial' })" -Level Information
        return $backupSuccess
    }
    catch {
        Write-Log -Message "Failed to backup Workspace One configuration. $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Rolls back a failed migration to Workspace One.
    
.DESCRIPTION
    Restores system to pre-migration state by restoring registry keys,
    configuration files, and optionally using System Restore.
    
.PARAMETER UseSystemRestore
    If true, will use the Windows System Restore feature to roll back. Default is $false.
    
.PARAMETER Force
    Force the rollback even if not all components can be restored. Default is $false.
    
.EXAMPLE
    Restore-WorkspaceOneMigration -UseSystemRestore $true
    
.OUTPUTS
    System.Boolean. Returns $true if rollback was successful, $false otherwise.
#>
function Restore-WorkspaceOneMigration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$UseSystemRestore = $false,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    if (-not $script:TransactionInProgress) {
        throw "No migration transaction in progress. Rollback not needed."
    }
    
    try {
        Write-Log -Message "Starting migration rollback..." -Level Warning
        
        # Option 1: Use System Restore if requested and available
        if ($UseSystemRestore -and $script:RestorePointCreated) {
            Write-Log -Message "Attempting to rollback using System Restore..." -Level Warning
            try {
                # Note: This will trigger a reboot
                Restore-Computer -RestorePoint 0 -Confirm:$false
                # If we get here, the restore didn't initiate properly
                Write-Log -Message "System Restore did not initiate properly." -Level Error
                # Continue with manual rollback
            }
            catch {
                Write-Log -Message "System Restore failed. Falling back to manual rollback. $_" -Level Error
                # Continue with manual rollback
            }
        }
        
        # Option 2: Manual rollback of registry and files
        $rollbackSuccess = $true
        
        # Restore registry keys in reverse order
        Write-Log -Message "Restoring registry keys..." -Level Information
        $registryBackups = $script:BackupItems | Where-Object { $_.Type -eq "Registry" }
        foreach ($backup in $registryBackups) {
            try {
                if (Test-Path -Path $backup.BackupFile) {
                    & reg.exe import "$($backup.BackupFile)" | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log -Message "Successfully restored registry key from: $($backup.BackupFile)" -Level Information
                    } else {
                        $rollbackSuccess = $false
                        Write-Log -Message "Failed to restore registry key from: $($backup.BackupFile). Exit code: $LASTEXITCODE" -Level Error
                    }
                } else {
                    $rollbackSuccess = $false
                    Write-Log -Message "Registry backup file not found: $($backup.BackupFile)" -Level Error
                }
            } catch {
                $rollbackSuccess = $false
                Write-Log -Message "Error restoring registry key: $_" -Level Error
            }
        }
        
        # Restore folders
        Write-Log -Message "Restoring backed up folders..." -Level Information
        $folderBackups = $script:BackupItems | Where-Object { $_.Type -eq "Folder" }
        foreach ($backup in $folderBackups) {
            try {
                if (Test-Path -Path $backup.BackupFile) {
                    if (Test-Path -Path $backup.Path) {
                        # Rename existing folder as a precaution
                        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                        $renamedPath = "$($backup.Path)_MigrationFailed_$timestamp"
                        Rename-Item -Path $backup.Path -NewName $renamedPath -Force -ErrorAction SilentlyContinue
                    }
                    
                    # Restore from backup
                    Copy-Item -Path $backup.BackupFile -Destination $backup.Path -Recurse -Force -ErrorAction Stop
                    Write-Log -Message "Successfully restored folder from: $($backup.BackupFile)" -Level Information
                } else {
                    $rollbackSuccess = $false
                    Write-Log -Message "Folder backup not found: $($backup.BackupFile)" -Level Error
                }
            } catch {
                $rollbackSuccess = $false
                Write-Log -Message "Error restoring folder: $_" -Level Error
            }
        }
        
        # Reset Workspace ONE MDM service if it exists
        $mdmService = Get-Service -Name "AirWatchMDMService" -ErrorAction SilentlyContinue
        if ($null -ne $mdmService) {
            try {
                Restart-Service -Name "AirWatchMDMService" -Force -ErrorAction SilentlyContinue
                Write-Log -Message "AirWatch MDM Service restarted." -Level Information
            } catch {
                Write-Log -Message "Failed to restart AirWatch MDM Service: $_" -Level Warning
            }
        }
        
        # Reset TransactionInProgress
        $script:TransactionInProgress = $false
        
        if (-not $rollbackSuccess -and -not $Force) {
            Write-Log -Message "Rollback completed with errors. Some components may not have been restored." -Level Warning
        } else {
            Write-Log -Message "Rollback completed successfully." -Level Information
        }
        
        return $rollbackSuccess -or $Force
    }
    catch {
        Write-Log -Message "Critical error during rollback: $_" -Level Error
        $script:TransactionInProgress = $false
        return $false
    }
}

<#
.SYNOPSIS
    Completes the migration transaction and cleans up backups if requested.
    
.DESCRIPTION
    Marks the migration as complete, optionally retaining or cleaning up
    backup files created during the migration process.
    
.PARAMETER CleanupBackups
    If $true, deletes the backup files. Default is $false.
    
.PARAMETER BackupRetentionDays
    How many days to keep backups before they are eligible for cleanup.
    Only applicable if CleanupBackups is $true. Default is 7 days.
    
.EXAMPLE
    Complete-MigrationTransaction -CleanupBackups $true -BackupRetentionDays 14
    
.OUTPUTS
    None
#>
function Complete-MigrationTransaction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$CleanupBackups = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$BackupRetentionDays = 7
    )
    
    if (-not $script:TransactionInProgress) {
        Write-Log -Message "No migration transaction in progress." -Level Warning
        return
    }
    
    try {
        Write-Log -Message "Completing migration transaction..." -Level Information
        
        # Reset transaction flag
        $script:TransactionInProgress = $false
        
        # Cleanup backups if requested
        if ($CleanupBackups) {
            $cutoffDate = (Get-Date).AddDays(-$BackupRetentionDays)
            $backupFolders = Get-ChildItem -Path $script:BackupBasePath -Directory -Filter "WS1Migration_Backup_*"
            
            foreach ($folder in $backupFolders) {
                if ($folder.CreationTime -lt $cutoffDate) {
                    try {
                        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                        Write-Log -Message "Removed backup folder: $($folder.FullName)" -Level Information
                    } catch {
                        Write-Log -Message "Failed to remove backup folder: $($folder.FullName). $_" -Level Warning
                    }
                }
            }
        }
        
        Write-Log -Message "Migration transaction completed successfully." -Level Information
    }
    catch {
        Write-Log -Message "Error completing migration transaction: $_" -Level Error
    }
}

<#
.SYNOPSIS
    Executes a migration step with rollback capability.
    
.DESCRIPTION
    Executes a scriptblock representing a migration step. If the step fails,
    automatically rolls back changes made during the migration.
    
.PARAMETER Name
    The name of the migration step.
    
.PARAMETER ScriptBlock
    The scriptblock to execute.
    
.PARAMETER ErrorAction
    How to handle errors. Can be 'Stop', 'Continue', or 'SilentlyContinue'.
    
.PARAMETER UseSystemRestore
    Whether to use System Restore for rollback if step fails.
    
.EXAMPLE
    Invoke-MigrationStep -Name "Remove Workspace One Agent" -ScriptBlock { Uninstall-WorkspaceOneAgent } -ErrorAction Stop
    
.OUTPUTS
    System.Object. Returns the output of the scriptblock if successful.
#>
function Invoke-MigrationStep {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Stop', 'Continue', 'SilentlyContinue')]
        [string]$ErrorAction = 'Stop',
        
        [Parameter(Mandatory = $false)]
        [bool]$UseSystemRestore = $false
    )
    
    if (-not $script:TransactionInProgress) {
        throw "Rollback mechanism must be initialized first. Call Initialize-RollbackMechanism."
    }
    
    Write-Log -Message "Starting migration step: $Name" -Level Information
    
    try {
        # Execute the migration step
        $result = & $ScriptBlock
        Write-Log -Message "Successfully completed migration step: $Name" -Level Information
        return $result
    }
    catch {
        Write-Log -Message "Failed to execute migration step: $Name. $_" -Level Error
        
        if ($ErrorAction -eq 'Stop') {
            Write-Log -Message "Rolling back migration due to failed step: $Name" -Level Warning
            $rollbackSuccess = Restore-WorkspaceOneMigration -UseSystemRestore $UseSystemRestore
            
            if (-not $rollbackSuccess) {
                Write-Log -Message "Rollback failed after migration step failure: $Name" -Level Error
            }
            
            throw "Migration step failed: $Name. Original error: $_. Rollback status: $(if ($rollbackSuccess) { 'Successful' } else { 'Failed' })"
        }
        elseif ($ErrorAction -eq 'Continue') {
            Write-Log -Message "Continuing migration despite step failure: $Name" -Level Warning
            return $null
        }
        else {
            # SilentlyContinue - just log and return null
            return $null
        }
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Initialize-RollbackMechanism, New-MigrationRestorePoint, Backup-WorkspaceOneConfiguration, Restore-WorkspaceOneMigration, Complete-MigrationTransaction, Invoke-MigrationStep 