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
    
.PARAMETER SkipRegistryRestore
    Skip restoring registry keys.
    
.PARAMETER SkipFileRestore
    Skip restoring files.
    
.PARAMETER SkipServiceRestore
    Skip restoring services.
    
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
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipRegistryRestore,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipFileRestore,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipServiceRestore
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
        if (-not $SkipRegistryRestore) {
            Write-Log -Message "Restoring registry keys..." -Level Information
            $registryBackups = $script:BackupItems | Where-Object { $_.Type -eq "Registry" }
            
            # Sort registry backups to ensure consistent restore order
            $registryBackups = $registryBackups | Sort-Object -Property { $_.Path.Length } -Descending
            
            foreach ($backup in $registryBackups) {
                try {
                    if (Test-Path -Path $backup.BackupFile) {
                        # Check if the registry key path exists before restore
                        $keyPath = $backup.Path
                        $keyExists = $false
                        
                        # Convert HKLM:\Path to registry provider format
                        if ($keyPath -match "^HKLM:\\(.+)$") {
                            $keyPath = "HKEY_LOCAL_MACHINE\$($Matches[1])"
                            $keyExists = $true
                        }
                        elseif ($keyPath -match "^HKLM\\(.+)$") {
                            $keyPath = "HKEY_LOCAL_MACHINE\$($Matches[1])"
                            $keyExists = $true
                        }
                        elseif ($keyPath -match "^HKCU:\\(.+)$") {
                            $keyPath = "HKEY_CURRENT_USER\$($Matches[1])"
                            $keyExists = $true
                        }
                        elseif ($keyPath -match "^HKCU\\(.+)$") {
                            $keyPath = "HKEY_CURRENT_USER\$($Matches[1])"
                            $keyExists = $true
                        }
                        
                        # Save existing registry key if it exists
                        $tempBackupPath = $null
                        if ($keyExists) {
                            $tempBackupPath = Join-Path -Path $env:TEMP -ChildPath "RollbackTemp_$(Get-Random).reg"
                            & reg.exe export "$keyPath" "$tempBackupPath" /y | Out-Null
                        }
                        
                        # Try to restore from backup
                        & reg.exe import "$($backup.BackupFile)" | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log -Message "Successfully restored registry key from: $($backup.BackupFile)" -Level Information
                            
                            # If temporary backup was created, keep it for safety
                            if ($tempBackupPath -and (Test-Path -Path $tempBackupPath)) {
                                $safetyPath = Join-Path -Path $script:BackupBasePath -ChildPath "RollbackSafety_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
                                Move-Item -Path $tempBackupPath -Destination $safetyPath -Force
                                Write-Log -Message "Previous registry state saved to: $safetyPath" -Level Information
                            }
                        } else {
                            $rollbackSuccess = $false
                            Write-Log -Message "Failed to restore registry key from: $($backup.BackupFile). Exit code: $LASTEXITCODE" -Level Error
                            
                            # Try to restore previous state if we have it
                            if ($tempBackupPath -and (Test-Path -Path $tempBackupPath)) {
                                & reg.exe import "$tempBackupPath" | Out-Null
                                Remove-Item -Path $tempBackupPath -Force -ErrorAction SilentlyContinue
                            }
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
        }
        
        # Restore folders
        if (-not $SkipFileRestore) {
            Write-Log -Message "Restoring backed up folders..." -Level Information
            $folderBackups = $script:BackupItems | Where-Object { $_.Type -eq "Folder" }
            foreach ($backup in $folderBackups) {
                try {
                    if (Test-Path -Path $backup.BackupFile) {
                        if (Test-Path -Path $backup.Path) {
                            # Rename existing folder as a precaution
                            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                            $renamedPath = "$($backup.Path)_MigrationFailed_$timestamp"
                            
                            # Rename with robocopy for safety (handles in-use files better)
                            $robocopyLogPath = Join-Path -Path $env:TEMP -ChildPath "RobocopyRename_$timestamp.log"
                            $robocopyParams = @(
                                "$($backup.Path)",
                                "$renamedPath",
                                "/E", "/MOVE", "/R:3", "/W:5",
                                "/LOG:$robocopyLogPath"
                            )
                            
                            Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyParams -Wait -NoNewWindow
                            
                            if (-not (Test-Path -Path $backup.Path)) {
                                Write-Log -Message "Successfully renamed existing folder to $renamedPath" -Level Information
                            } else {
                                # Fallback to rename
                                Rename-Item -Path $backup.Path -NewName $renamedPath -Force -ErrorAction SilentlyContinue
                            }
                        }
                        
                        # Restore from backup using robocopy for better reliability
                        $robocopyLogPath = Join-Path -Path $env:TEMP -ChildPath "RobocopyRestore_$(Get-Random).log"
                        $robocopyParams = @(
                            "$($backup.BackupFile)",
                            "$($backup.Path)",
                            "/E", "/R:3", "/W:5", "/XO",
                            "/LOG:$robocopyLogPath"
                        )
                        
                        Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyParams -Wait -NoNewWindow
                        
                        if (Test-Path -Path $backup.Path) {
                            Write-Log -Message "Successfully restored folder from: $($backup.BackupFile)" -Level Information
                        } else {
                            # Fallback to Copy-Item
                            New-Item -Path $backup.Path -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                            Copy-Item -Path "$($backup.BackupFile)\*" -Destination $backup.Path -Recurse -Force -ErrorAction Stop
                            Write-Log -Message "Successfully restored folder from: $($backup.BackupFile) using Copy-Item" -Level Information
                        }
                    } else {
                        $rollbackSuccess = $false
                        Write-Log -Message "Folder backup not found: $($backup.BackupFile)" -Level Error
                    }
                } catch {
                    $rollbackSuccess = $false
                    Write-Log -Message "Error restoring folder: $_" -Level Error
                }
            }
        }
        
        # Restore services
        if (-not $SkipServiceRestore) {
            # Reset Workspace ONE MDM service if it exists
            $mdmService = Get-Service -Name "AirWatchMDMService" -ErrorAction SilentlyContinue
            if ($null -ne $mdmService) {
                try {
                    # Check service startup type
                    $serviceInfo = Get-WmiObject -Class Win32_Service -Filter "Name='AirWatchMDMService'"
                    $startupType = $serviceInfo.StartMode
                    
                    # Ensure service is set to auto-start
                    if ($startupType -ne "Auto") {
                        Set-Service -Name "AirWatchMDMService" -StartupType Automatic
                        Write-Log -Message "AirWatch MDM Service startup type set to Automatic" -Level Information
                    }
                    
                    # Start the service
                    Start-Service -Name "AirWatchMDMService" -ErrorAction Stop
                    Write-Log -Message "AirWatch MDM Service started successfully" -Level Information
                } catch {
                    $rollbackSuccess = $false
                    Write-Log -Message "Failed to restart AirWatch MDM Service: $_" -Level Warning
                }
            }
            
            # Check and restore other Workspace ONE related services
            $ws1Services = @("AWService", "AWNetworkService", "AWWindowsUpdateService")
            foreach ($serviceName in $ws1Services) {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($null -ne $service) {
                    try {
                        # Ensure service is set to auto-start
                        Set-Service -Name $serviceName -StartupType Automatic -ErrorAction SilentlyContinue
                        
                        # Start the service
                        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                        Write-Log -Message "$serviceName started successfully" -Level Information
                    } catch {
                        Write-Log -Message "Failed to restart $serviceName: $_" -Level Warning
                    }
                }
            }
        }
        
        # Additional rollback actions
        
        # 1. Check and restore WS1 Hub app
        $hubAppPath = "$env:ProgramFiles\WindowsApps\AirWatchLLC.WorkspaceONEIntelligentHub*"
        if (Test-Path -Path $hubAppPath) {
            Write-Log -Message "Workspace ONE Hub app found, no restoration needed" -Level Information
        } else {
            Write-Log -Message "Workspace ONE Hub app not found. Manual reinstallation may be required." -Level Warning
        }
        
        # 2. Restore Workspace ONE MDM enrollment
        if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue) {
            $enrollments = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
            $ws1Enrollment = $enrollments | Where-Object { 
                (Get-ItemProperty -Path "$($_.PSPath)" -ErrorAction SilentlyContinue).ProviderID -match "AirWatch" 
            }
            
            if ($ws1Enrollment) {
                Write-Log -Message "Workspace ONE enrollment found, no restoration needed" -Level Information
            } else {
                Write-Log -Message "Workspace ONE enrollment not found. Manual re-enrollment may be required." -Level Warning
            }
        } else {
            Write-Log -Message "Enrollments registry key not found. Manual re-enrollment may be required." -Level Warning
        }
        
        # 3. Remove Intune enrollment if present
        try {
            $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
            $intuneEnrollments = Get-ChildItem -Path $enrollmentPath -ErrorAction SilentlyContinue | 
                Where-Object { 
                    $path = $_.PSPath
                    $providerID = Get-ItemProperty -Path $path -Name "ProviderID" -ErrorAction SilentlyContinue
                    $providerID -and $providerID.ProviderID -match "MS DM Server" 
                }
                
            if ($intuneEnrollments) {
                foreach ($enrollment in $intuneEnrollments) {
                    $enrollmentID = Split-Path -Path $enrollment.PSPath -Leaf
                    Write-Log -Message "Removing Intune enrollment: $enrollmentID" -Level Warning
                    Remove-Item -Path $enrollment.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Log -Message "Error removing Intune enrollments: $_" -Level Warning
        }
        
        # 4. Validate rollback success with basic checks
        $rollbackValidationSuccess = $true
        
        try {
            # Check if WS1 registry keys are present
            if (-not (Test-Path -Path "HKLM:\SOFTWARE\AirWatch" -ErrorAction SilentlyContinue)) {
                $rollbackValidationSuccess = $false
                Write-Log -Message "Validation failed: AirWatch registry key not found after rollback" -Level Warning
            }
            
            # Check if WS1 services exist
            $awService = Get-Service -Name "AirWatchMDMService" -ErrorAction SilentlyContinue
            if (-not $awService) {
                $rollbackValidationSuccess = $false
                Write-Log -Message "Validation failed: AirWatch MDM service not found after rollback" -Level Warning
            }
        } catch {
            $rollbackValidationSuccess = $false
            Write-Log -Message "Error during rollback validation: $_" -Level Error
        }
        
        # Reset TransactionInProgress
        $script:TransactionInProgress = $false
        
        $overallSuccess = $rollbackSuccess -and $rollbackValidationSuccess
        
        if (-not $overallSuccess -and -not $Force) {
            Write-Log -Message "Rollback completed with errors. Some components may not have been restored." -Level Warning
        } else {
            Write-Log -Message "Rollback completed successfully." -Level Information
        }
        
        return $overallSuccess -or $Force
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

function Restore-BackupItems {
    <#
    .SYNOPSIS
        Restores items from a backup based on the provided backup ID.
    .DESCRIPTION
        Restores registry keys and files from a backup created with the Backup-Items function.
        The function can restore all items or specific item types (Registry or Files).
        Also includes validation capabilities to verify the restoration process.
    .PARAMETER BackupId
        The ID of the backup to restore from.
    .PARAMETER ItemType
        The type of items to restore. Valid values are 'Registry', 'Files', or 'All'.
    .PARAMETER Force
        Switch to force restoration even if validation fails or conflicts exist.
    .PARAMETER Validate
        Switch to validate the restoration after completion.
    .EXAMPLE
        Restore-BackupItems -BackupId "Backup_20220915_123045" -ItemType All -Validate
    .EXAMPLE
        Restore-BackupItems -BackupId "Backup_20220915_123045" -ItemType Registry -Force
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Registry", "Files", "All")]
        [string]$ItemType = "All",
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [switch]$Validate
    )
    
    try {
        # Import the logging module
        Import-Module -Name "$PSScriptRoot\LoggingModule.psm1" -Force
        
        # Log the start of the restoration process
        Write-Log -Message "Starting restoration from backup ID: $BackupId" -Level Information
        
        # Get the backup path from the configuration or use default
        $backupRootPath = Get-BackupRootPath
        $backupPath = Join-Path -Path $backupRootPath -ChildPath $BackupId
        
        # Check if the backup exists
        if (-not (Test-Path -Path $backupPath)) {
            $errorMsg = "Backup not found: $BackupId"
            Write-Log -Message $errorMsg -Level Error
            throw $errorMsg
        }
        
        # Check if manifest exists
        $manifestPath = Join-Path -Path $backupPath -ChildPath "manifest.json"
        if (-not (Test-Path -Path $manifestPath)) {
            $errorMsg = "Backup manifest not found for backup ID: $BackupId"
            Write-Log -Message $errorMsg -Level Error
            throw $errorMsg
        }
        
        # Load the manifest
        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        
        # Initialize counters
        $restoredItems = 0
        $failedItems = 0
        $registryItemsRestored = 0
        $fileItemsRestored = 0
        
        # Check if the backup is already restored
        if ($manifest.Status -eq "Restored" -and -not $Force) {
            Write-Log -Message "Backup $BackupId is already marked as restored. Use -Force to restore again." -Level Warning
            return [PSCustomObject]@{
                Success = $false
                BackupId = $BackupId
                Message = "Backup is already marked as restored. Use -Force to restore again."
                RestoredItems = 0
                FailedItems = 0
            }
        }
        
        # Define a hashtable to store restoration statistics
        $restorationStats = @{
            StartTime = Get-Date
            EndTime = $null
            RestoredItems = 0
            FailedItems = 0
            RegistryItemsRestored = 0
            FileItemsRestored = 0
        }
        
        # Restore registry keys if specified
        if ($ItemType -eq "All" -or $ItemType -eq "Registry") {
            Write-Log -Message "Restoring registry keys from backup $BackupId" -Level Information
            
            $registryBackupPath = Join-Path -Path $backupPath -ChildPath "Registry"
            if (Test-Path -Path $registryBackupPath) {
                # Get all registry key backup files
                $registryFiles = Get-ChildItem -Path $registryBackupPath -Filter "*.reg" -File
                
                if ($registryFiles -and $registryFiles.Count -gt 0) {
                    $totalRegistryFiles = $registryFiles.Count
                    $currentRegistryFile = 0
                    
                    foreach ($regFile in $registryFiles) {
                        $currentRegistryFile++
                        $progressPercent = ($currentRegistryFile / $totalRegistryFiles) * 100
                        
                        # Show progress
                        Write-Progress -Activity "Restoring Registry Keys" -Status "Restoring $($regFile.Name)" -PercentComplete $progressPercent
                        
                        if ($PSCmdlet.ShouldProcess($regFile.FullName, "Import registry file")) {
                            try {
                                # Import the registry file
                                $regImportResult = Start-Process -FilePath "reg" -ArgumentList "import `"$($regFile.FullName)`"" -NoNewWindow -Wait -PassThru
                                
                                if ($regImportResult.ExitCode -eq 0) {
                                    $restoredItems++
                                    $registryItemsRestored++
                                    $restorationStats.RegistryItemsRestored++
                                    $restorationStats.RestoredItems++
                                    
                                    Write-Log -Message "Successfully restored registry key: $($regFile.Name)" -Level Information
                                }
                                else {
                                    $failedItems++
                                    $restorationStats.FailedItems++
                                    
                                    Write-Log -Message "Failed to restore registry key: $($regFile.Name), Exit code: $($regImportResult.ExitCode)" -Level Error
                                }
                            }
                            catch {
                                $failedItems++
                                $restorationStats.FailedItems++
                                
                                Write-Log -Message "Error restoring registry key: $($regFile.Name), Error: $_" -Level Error
                            }
                        }
                    }
                    
                    Write-Progress -Activity "Restoring Registry Keys" -Completed
                }
                else {
                    Write-Log -Message "No registry keys found in backup $BackupId" -Level Warning
                }
            }
            else {
                Write-Log -Message "Registry backup path not found for backup ID: $BackupId" -Level Warning
            }
        }
        
        # Restore files if specified
        if ($ItemType -eq "All" -or $ItemType -eq "Files") {
            Write-Log -Message "Restoring files from backup $BackupId" -Level Information
            
            $filesBackupPath = Join-Path -Path $backupPath -ChildPath "Files"
            if (Test-Path -Path $filesBackupPath) {
                # Load the file manifest
                $fileManifestPath = Join-Path -Path $filesBackupPath -ChildPath "filemanifest.json"
                
                if (Test-Path -Path $fileManifestPath) {
                    $fileManifest = Get-Content -Path $fileManifestPath -Raw | ConvertFrom-Json
                    
                    if ($fileManifest.Files -and $fileManifest.Files.Count -gt 0) {
                        $totalFiles = $fileManifest.Files.Count
                        $currentFile = 0
                        
                        foreach ($file in $fileManifest.Files) {
                            $currentFile++
                            $progressPercent = ($currentFile / $totalFiles) * 100
                            
                            # Show progress
                            Write-Progress -Activity "Restoring Files" -Status "Restoring $($file.OriginalPath)" -PercentComplete $progressPercent
                            
                            $backupFilePath = Join-Path -Path $filesBackupPath -ChildPath $file.BackupRelativePath
                            
                            if (Test-Path -Path $backupFilePath) {
                                # Ensure target directory exists
                                $targetDir = [System.IO.Path]::GetDirectoryName($file.OriginalPath)
                                if (-not (Test-Path -Path $targetDir)) {
                                    try {
                                        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                                        Write-Log -Message "Created directory: $targetDir" -Level Information
                                    }
                                    catch {
                                        Write-Log -Message "Failed to create directory: $targetDir, Error: $_" -Level Error
                                        $failedItems++
                                        $restorationStats.FailedItems++
                                        continue
                                    }
                                }
                                
                                if ($PSCmdlet.ShouldProcess($file.OriginalPath, "Restore file")) {
                                    try {
                                        # Check if target file exists and should be overwritten
                                        if (Test-Path -Path $file.OriginalPath) {
                                            if ($Force) {
                                                # Backup the current file before replacing
                                                $tempBackupPath = "$($file.OriginalPath).pre_restore"
                                                Copy-Item -Path $file.OriginalPath -Destination $tempBackupPath -Force -ErrorAction SilentlyContinue
                                                
                                                # Remove the current file
                                                Remove-Item -Path $file.OriginalPath -Force
                                                Write-Log -Message "Removed existing file: $($file.OriginalPath)" -Level Information
                                            }
                                            else {
                                                Write-Log -Message "File already exists: $($file.OriginalPath). Use -Force to overwrite." -Level Warning
                                                $failedItems++
                                                $restorationStats.FailedItems++
                                                continue
                                            }
                                        }
                                        
                                        # Copy the backup file to the original location
                                        Copy-Item -Path $backupFilePath -Destination $file.OriginalPath -Force
                                        
                                        $restoredItems++
                                        $fileItemsRestored++
                                        $restorationStats.FileItemsRestored++
                                        $restorationStats.RestoredItems++
                                        
                                        Write-Log -Message "Successfully restored file: $($file.OriginalPath)" -Level Information
                                    }
                                    catch {
                                        $failedItems++
                                        $restorationStats.FailedItems++
                                        
                                        Write-Log -Message "Error restoring file: $($file.OriginalPath), Error: $_" -Level Error
                                    }
                                }
                            }
                            else {
                                Write-Log -Message "Backup file not found: $backupFilePath" -Level Warning
                                $failedItems++
                                $restorationStats.FailedItems++
                            }
                        }
                        
                        Write-Progress -Activity "Restoring Files" -Completed
                    }
                    else {
                        Write-Log -Message "No files found in backup $BackupId" -Level Warning
                    }
                }
                else {
                    Write-Log -Message "File manifest not found for backup ID: $BackupId" -Level Warning
                }
            }
            else {
                Write-Log -Message "Files backup path not found for backup ID: $BackupId" -Level Warning
            }
        }
        
        # Update restoration statistics
        $restorationStats.EndTime = Get-Date
        
        # Update the manifest with restoration information
        $manifest.LastRestoreDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $manifest.Status = "Restored"
        $manifest.RestorationStats = $restorationStats
        
        # Save the updated manifest
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Force
        
        # Log the completion of the restoration process
        $summaryMessage = "Restoration completed for backup $BackupId. Restored items: $restoredItems (Registry: $registryItemsRestored, Files: $fileItemsRestored), Failed items: $failedItems"
        Write-Log -Message $summaryMessage -Level Information
        
        # Validate the restoration if requested
        $validationResults = $null
        if ($Validate) {
            Write-Log -Message "Validating restoration for backup $BackupId" -Level Information
            $validationResults = Test-RestorationValidity -BackupId $BackupId -ItemType $ItemType
            
            # Add validation results to the manifest
            $manifest.ValidationResults = $validationResults
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Force
            
            # Log validation results
            Write-Log -Message "Validation results: $($validationResults.ValidItems) items valid, $($validationResults.InvalidItems) items invalid" -Level Information
        }
        
        # Return result object
        return [PSCustomObject]@{
            Success = ($failedItems -eq 0)
            BackupId = $BackupId
            Message = $summaryMessage
            RestoredItems = $restoredItems
            FailedItems = $failedItems
            RegistryItemsRestored = $registryItemsRestored
            FileItemsRestored = $fileItemsRestored
            ValidationResults = $validationResults
        }
    }
    catch {
        Write-Log -Message "Error in Restore-BackupItems: $_" -Level Error
        
        return [PSCustomObject]@{
            Success = $false
            BackupId = $BackupId
            Message = "Error in restoration process: $_"
            RestoredItems = $restoredItems
            FailedItems = $failedItems + 1
        }
    }
}

function Test-RestorationValidity {
    <#
    .SYNOPSIS
        Validates that items were correctly restored from backup.
    .DESCRIPTION
        Checks that registry keys and files were correctly restored from a backup.
        Verifies that registry keys exist and files match their backup versions.
    .PARAMETER BackupId
        The ID of the backup to validate.
    .PARAMETER ItemType
        The type of items to validate. Valid values are 'Registry', 'Files', or 'All'.
    .EXAMPLE
        Test-RestorationValidity -BackupId "Backup_20220915_123045" -ItemType All
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Registry", "Files", "All")]
        [string]$ItemType = "All"
    )
    
    try {
        # Import the logging module
        Import-Module -Name "$PSScriptRoot\LoggingModule.psm1" -Force
        
        # Log the start of the validation process
        Write-Log -Message "Starting validation for backup ID: $BackupId" -Level Information
        
        # Get the backup path from the configuration or use default
        $backupRootPath = Get-BackupRootPath
        $backupPath = Join-Path -Path $backupRootPath -ChildPath $BackupId
        
        # Check if the backup exists
        if (-not (Test-Path -Path $backupPath)) {
            $errorMsg = "Backup not found: $BackupId"
            Write-Log -Message $errorMsg -Level Error
            throw $errorMsg
        }
        
        # Initialize counters
        $validItems = 0
        $invalidItems = 0
        $validRegistryItems = 0
        $invalidRegistryItems = 0
        $validFileItems = 0
        $invalidFileItems = 0
        
        # Detailed validation results
        $detailedResults = @{
            Registry = @()
            Files = @()
        }
        
        # Validate registry keys if specified
        if ($ItemType -eq "All" -or $ItemType -eq "Registry") {
            Write-Log -Message "Validating registry keys from backup $BackupId" -Level Information
            
            $registryBackupPath = Join-Path -Path $backupPath -ChildPath "Registry"
            if (Test-Path -Path $registryBackupPath) {
                # Get manifest to extract the original registry keys
                $manifestPath = Join-Path -Path $backupPath -ChildPath "manifest.json"
                if (Test-Path -Path $manifestPath) {
                    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
                    
                    if ($manifest.RegistryKeys -and $manifest.RegistryKeys.Count -gt 0) {
                        $totalKeys = $manifest.RegistryKeys.Count
                        $currentKey = 0
                        
                        foreach ($regKey in $manifest.RegistryKeys) {
                            $currentKey++
                            $progressPercent = ($currentKey / $totalKeys) * 100
                            
                            # Show progress
                            Write-Progress -Activity "Validating Registry Keys" -Status "Checking $regKey" -PercentComplete $progressPercent
                            
                            # Check if the registry key exists
                            $regKeyExists = $false
                            try {
                                # Convert PowerShell-style registry path to traditional format
                                $regPath = $regKey -replace "HKLM:", "HKEY_LOCAL_MACHINE" -replace "HKCU:", "HKEY_CURRENT_USER"
                                
                                # Use reg query to check if key exists
                                $regQueryResult = Start-Process -FilePath "reg" -ArgumentList "query `"$regPath`"" -NoNewWindow -Wait -PassThru
                                $regKeyExists = ($regQueryResult.ExitCode -eq 0)
                            }
                            catch {
                                $regKeyExists = $false
                                Write-Log -Message "Error checking registry key: $regKey, Error: $_" -Level Error
                            }
                            
                            if ($regKeyExists) {
                                $validItems++
                                $validRegistryItems++
                                Write-Log -Message "Registry key exists: $regKey" -Level Information
                                
                                $detailedResults.Registry += [PSCustomObject]@{
                                    Key = $regKey
                                    IsValid = $true
                                    Reason = "Key exists"
                                }
                            }
                            else {
                                $invalidItems++
                                $invalidRegistryItems++
                                Write-Log -Message "Registry key does not exist: $regKey" -Level Warning
                                
                                $detailedResults.Registry += [PSCustomObject]@{
                                    Key = $regKey
                                    IsValid = $false
                                    Reason = "Key does not exist"
                                }
                            }
                        }
                        
                        Write-Progress -Activity "Validating Registry Keys" -Completed
                    }
                    else {
                        Write-Log -Message "No registry keys found in backup manifest for $BackupId" -Level Warning
                    }
                }
                else {
                    Write-Log -Message "Manifest not found for backup ID: $BackupId" -Level Warning
                }
            }
            else {
                Write-Log -Message "Registry backup path not found for backup ID: $BackupId" -Level Warning
            }
        }
        
        # Validate files if specified
        if ($ItemType -eq "All" -or $ItemType -eq "Files") {
            Write-Log -Message "Validating files from backup $BackupId" -Level Information
            
            $filesBackupPath = Join-Path -Path $backupPath -ChildPath "Files"
            if (Test-Path -Path $filesBackupPath) {
                # Load the file manifest
                $fileManifestPath = Join-Path -Path $filesBackupPath -ChildPath "filemanifest.json"
                
                if (Test-Path -Path $fileManifestPath) {
                    $fileManifest = Get-Content -Path $fileManifestPath -Raw | ConvertFrom-Json
                    
                    if ($fileManifest.Files -and $fileManifest.Files.Count -gt 0) {
                        $totalFiles = $fileManifest.Files.Count
                        $currentFile = 0
                        
                        foreach ($file in $fileManifest.Files) {
                            $currentFile++
                            $progressPercent = ($currentFile / $totalFiles) * 100
                            
                            # Show progress
                            Write-Progress -Activity "Validating Files" -Status "Checking $($file.OriginalPath)" -PercentComplete $progressPercent
                            
                            # Check if the file exists and matches the backup
                            $fileValid = $false
                            $validationReason = ""
                            
                            if (Test-Path -Path $file.OriginalPath) {
                                $backupFilePath = Join-Path -Path $filesBackupPath -ChildPath $file.BackupRelativePath
                                
                                if (Test-Path -Path $backupFilePath) {
                                    try {
                                        # Compare file hash to verify content
                                        $originalHash = Get-FileHash -Path $file.OriginalPath -Algorithm SHA256
                                        $backupHash = Get-FileHash -Path $backupFilePath -Algorithm SHA256
                                        
                                        if ($originalHash.Hash -eq $backupHash.Hash) {
                                            $fileValid = $true
                                            $validationReason = "File exists and content matches"
                                        }
                                        else {
                                            $fileValid = $false
                                            $validationReason = "File exists but content differs"
                                        }
                                    }
                                    catch {
                                        $fileValid = $false
                                        $validationReason = "Error comparing files: $_"
                                        Write-Log -Message "Error comparing files: $($file.OriginalPath), Error: $_" -Level Error
                                    }
                                }
                                else {
                                    $fileValid = $false
                                    $validationReason = "Backup file not found"
                                    Write-Log -Message "Backup file not found: $backupFilePath" -Level Warning
                                }
                            }
                            else {
                                $fileValid = $false
                                $validationReason = "Original file not found"
                                Write-Log -Message "File does not exist: $($file.OriginalPath)" -Level Warning
                            }
                            
                            if ($fileValid) {
                                $validItems++
                                $validFileItems++
                                Write-Log -Message "File is valid: $($file.OriginalPath)" -Level Information
                                
                                $detailedResults.Files += [PSCustomObject]@{
                                    Path = $file.OriginalPath
                                    IsValid = $true
                                    Reason = $validationReason
                                }
                            }
                            else {
                                $invalidItems++
                                $invalidFileItems++
                                Write-Log -Message "File is invalid: $($file.OriginalPath) - $validationReason" -Level Warning
                                
                                $detailedResults.Files += [PSCustomObject]@{
                                    Path = $file.OriginalPath
                                    IsValid = $false
                                    Reason = $validationReason
                                }
                            }
                        }
                        
                        Write-Progress -Activity "Validating Files" -Completed
                    }
                    else {
                        Write-Log -Message "No files found in file manifest for backup $BackupId" -Level Warning
                    }
                }
                else {
                    Write-Log -Message "File manifest not found for backup ID: $BackupId" -Level Warning
                }
            }
            else {
                Write-Log -Message "Files backup path not found for backup ID: $BackupId" -Level Warning
            }
        }
        
        # Log the completion of the validation process
        $summaryMessage = "Validation completed for backup $BackupId. Valid items: $validItems (Registry: $validRegistryItems, Files: $validFileItems), Invalid items: $invalidItems (Registry: $invalidRegistryItems, Files: $invalidFileItems)"
        Write-Log -Message $summaryMessage -Level Information
        
        # Return result object
        return [PSCustomObject]@{
            Success = ($invalidItems -eq 0 -and $validItems -gt 0)
            BackupId = $BackupId
            Message = $summaryMessage
            ValidItems = $validItems
            InvalidItems = $invalidItems
            ValidRegistryItems = $validRegistryItems
            InvalidRegistryItems = $invalidRegistryItems
            ValidFileItems = $validFileItems
            InvalidFileItems = $invalidFileItems
            DetailedResults = $detailedResults
        }
    }
    catch {
        Write-Log -Message "Error in Test-RestorationValidity: $_" -Level Error
        
        return [PSCustomObject]@{
            Success = $false
            BackupId = $BackupId
            Message = "Error in validation process: $_"
            ValidItems = 0
            InvalidItems = 1
        }
    }
}

# Export the module functions
Export-ModuleMember -Function Backup-Items, 
                              Restore-BackupItems, 
                              Get-BackupStatus,
                              Test-BackupIntegrity,
                              Test-RestorationValidity,
                              Remove-Backup 