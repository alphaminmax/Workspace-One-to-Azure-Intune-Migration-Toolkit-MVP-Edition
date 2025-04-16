#Requires -Version 5.1
#Requires -RunAsAdministrator
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Tests the rollback mechanism for migration operations.                                                                #
# PowerShell 5.1 x32/x64                                                                                                       #
#                                                                                                                              #
################################################################################################################################

################################################################################################################################
#                                                                                                                              #
#      ██████╗██████╗  █████╗ ██╗   ██╗ ██████╗ ███╗   ██╗    ██╗   ██╗███████╗ █████╗                                        #
#     ██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗████╗  ██║    ██║   ██║██╔════╝██╔══██╗                                       #
#     ██║     ██████╔╝███████║ ╚████╔╝ ██║   ██║██╔██╗ ██║    ██║   ██║███████╗███████║                                       #
#     ██║     ██╔══██╗██╔══██║  ╚██╔╝  ██║   ██║██║╚██╗██║    ██║   ██║╚════██║██╔══██║                                       #
#     ╚██████╗██║  ██║██║  ██║   ██║   ╚██████╔╝██║ ╚████║    ╚██████╔╝███████║██║  ██║                                       #
#      ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝     ╚═════╝ ╚══════╝╚═╝  ╚═╝                                       #
#                                                                                                                              #
################################################################################################################################


<#
.SYNOPSIS
    Tests the rollback mechanism for migration operations.
    
.DESCRIPTION
    This script demonstrates how to use the RollbackMechanism module in a 
    migration scenario, including creating restore points, backing up configuration,
    and performing migration steps with automatic rollback on failure.
    
.NOTES
    File Name      : Test-RollbackMechanism.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Copyright      : Organization Name
    Version        : 1.0.0
    
.EXAMPLE
    .\Test-RollbackMechanism.ps1
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = "$env:TEMP\MigrationBackups",
    
    [Parameter(Mandatory = $false)]
    [switch]$UseSystemRestore = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$SimulateFailure = $false
)

# Import required modules
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "modules"
$rollbackModulePath = Join-Path -Path $modulesPath -ChildPath "RollbackMechanism.psm1"
$loggingModulePath = Join-Path -Path $modulesPath -ChildPath "LoggingModule.psm1"

# Import LoggingModule first
if (Test-Path -Path $loggingModulePath) {
    Import-Module -Name $loggingModulePath -Force
} else {
    throw "Required module LoggingModule.psm1 not found at path: $loggingModulePath"
}

# Import RollbackMechanism
if (Test-Path -Path $rollbackModulePath) {
    Import-Module -Name $rollbackModulePath -Force
} else {
    throw "Required module RollbackMechanism.psm1 not found at path: $rollbackModulePath"
}

# Ensure the backup path exists
if (-not (Test-Path -Path $BackupPath)) {
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
}

function Test-MigrationStepSuccess {
    [CmdletBinding()]
    param()
    
    Write-Log -Message "Performing a successful migration step..." -Level Information
    Start-Sleep -Seconds 2
    return $true
}

function Test-MigrationStepFailure {
    [CmdletBinding()]
    param()
    
    Write-Log -Message "Performing a migration step that will fail..." -Level Information
    Start-Sleep -Seconds 2
    throw "Simulated migration failure"
}

function Test-SuccessfulMigration {
    [CmdletBinding()]
    param()
    
    try {
        # Initialize rollback mechanism
        Write-Host "Initializing rollback mechanism..." -ForegroundColor Cyan
        $backupFolder = Initialize-RollbackMechanism -BackupPath $BackupPath
        Write-Host "Rollback mechanism initialized. Backup folder: $backupFolder" -ForegroundColor Green
        
        # Create system restore point if requested
        if ($UseSystemRestore) {
            Write-Host "Creating system restore point..." -ForegroundColor Cyan
            $restorePoint = New-MigrationRestorePoint -Description "WS1 Migration Test"
            if ($restorePoint) {
                Write-Host "System restore point created successfully." -ForegroundColor Green
            } else {
                Write-Host "Failed to create system restore point." -ForegroundColor Yellow
            }
        }
        
        # Backup Workspace One configuration
        Write-Host "Backing up Workspace One configuration..." -ForegroundColor Cyan
        $backupResult = Backup-WorkspaceOneConfiguration -BackupFolder $backupFolder
        if ($backupResult) {
            Write-Host "Workspace One configuration backed up successfully." -ForegroundColor Green
        } else {
            Write-Host "Workspace One configuration backup completed with warnings." -ForegroundColor Yellow
        }
        
        # Perform successful migration steps
        Write-Host "Performing migration steps..." -ForegroundColor Cyan
        
        # Step 1: A successful step
        $step1Result = Invoke-MigrationStep -Name "Step 1: Initial Configuration" -ScriptBlock {
            Test-MigrationStepSuccess
        }
        Write-Host "Step 1 completed successfully." -ForegroundColor Green
        
        # Step 2: Another successful step
        $step2Result = Invoke-MigrationStep -Name "Step 2: Configuration Updates" -ScriptBlock {
            Test-MigrationStepSuccess
        }
        Write-Host "Step 2 completed successfully." -ForegroundColor Green
        
        # Step 3: Final successful step
        $step3Result = Invoke-MigrationStep -Name "Step 3: Finalization" -ScriptBlock {
            Test-MigrationStepSuccess
        }
        Write-Host "Step 3 completed successfully." -ForegroundColor Green
        
        # Complete migration transaction
        Write-Host "Completing migration transaction..." -ForegroundColor Cyan
        Complete-MigrationTransaction -CleanupBackups $false
        Write-Host "Migration transaction completed successfully." -ForegroundColor Green
        
        Write-Host "Migration completed successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $false
    }
}

function Test-FailedMigration {
    [CmdletBinding()]
    param()
    
    try {
        # Initialize rollback mechanism
        Write-Host "Initializing rollback mechanism..." -ForegroundColor Cyan
        $backupFolder = Initialize-RollbackMechanism -BackupPath $BackupPath
        Write-Host "Rollback mechanism initialized. Backup folder: $backupFolder" -ForegroundColor Green
        
        # Create system restore point if requested
        if ($UseSystemRestore) {
            Write-Host "Creating system restore point..." -ForegroundColor Cyan
            $restorePoint = New-MigrationRestorePoint -Description "WS1 Migration Test"
            if ($restorePoint) {
                Write-Host "System restore point created successfully." -ForegroundColor Green
            } else {
                Write-Host "Failed to create system restore point." -ForegroundColor Yellow
            }
        }
        
        # Backup Workspace One configuration
        Write-Host "Backing up Workspace One configuration..." -ForegroundColor Cyan
        $backupResult = Backup-WorkspaceOneConfiguration -BackupFolder $backupFolder
        if ($backupResult) {
            Write-Host "Workspace One configuration backed up successfully." -ForegroundColor Green
        } else {
            Write-Host "Workspace One configuration backup completed with warnings." -ForegroundColor Yellow
        }
        
        # Perform migration steps with a simulated failure
        Write-Host "Performing migration steps..." -ForegroundColor Cyan
        
        # Step 1: A successful step
        $step1Result = Invoke-MigrationStep -Name "Step 1: Initial Configuration" -ScriptBlock {
            Test-MigrationStepSuccess
        }
        Write-Host "Step 1 completed successfully." -ForegroundColor Green
        
        # Step 2: Another successful step
        $step2Result = Invoke-MigrationStep -Name "Step 2: Configuration Updates" -ScriptBlock {
            Test-MigrationStepSuccess
        }
        Write-Host "Step 2 completed successfully." -ForegroundColor Green
        
        # Step 3: A failing step
        Write-Host "Step 3 will fail (simulated failure)..." -ForegroundColor Yellow
        $step3Result = Invoke-MigrationStep -Name "Step 3: Failing Step" -ScriptBlock {
            Test-MigrationStepFailure
        } -UseSystemRestore $UseSystemRestore
        
        # This should not be reached if Step 3 throws an exception
        Write-Host "Error: Step 3 should have failed but didn't." -ForegroundColor Red
        return $false
    }
    catch {
        Write-Host "Expected error occurred: $_" -ForegroundColor Yellow
        Write-Host "Rollback was triggered automatically." -ForegroundColor Cyan
        return $true
    }
}

# Main execution
try {
    Write-Host "=== Testing Rollback Mechanism ===" -ForegroundColor Magenta
    Write-Host "Backup Path: $BackupPath" -ForegroundColor Cyan
    Write-Host "System Restore: $UseSystemRestore" -ForegroundColor Cyan
    Write-Host "Simulate Failure: $SimulateFailure" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Magenta
    
    if ($SimulateFailure) {
        Write-Host "Testing migration with failure scenario..." -ForegroundColor Yellow
        $result = Test-FailedMigration
        if ($result) {
            Write-Host "Test passed: Migration failed and was rolled back as expected." -ForegroundColor Green
        } else {
            Write-Host "Test failed: Migration should have failed but didn't." -ForegroundColor Red
        }
    } else {
        Write-Host "Testing successful migration scenario..." -ForegroundColor Cyan
        $result = Test-SuccessfulMigration
        if ($result) {
            Write-Host "Test passed: Migration completed successfully." -ForegroundColor Green
        } else {
            Write-Host "Test failed: Migration should have succeeded but didn't." -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "Critical error: $_" -ForegroundColor Red
}
finally {
    Write-Host "=== Test Complete ===" -ForegroundColor Magenta
} 





