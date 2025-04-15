#Requires -Version 5.1

<#
.SYNOPSIS
    Main entry point for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    Orchestrates the complete migration process from Workspace One to Azure/Intune,
    integrating the high-priority components:
    - RollbackMechanism: For recovery from failed migrations
    - MigrationVerification: For validating successful migration
    - UserCommunicationFramework: For user notifications and feedback
    
    This script serves as the primary entry point for both interactive and silent migrations.
    
.PARAMETER SilentMode
    Run in silent mode without user interaction. Default is $false.
    
.PARAMETER LogPath
    Path to store log files. Default is "$env:TEMP\WS1Migration".
    
.PARAMETER BackupPath
    Path to store backup files for rollback. Default is "$env:TEMP\WS1Migration\Backups".
    
.PARAMETER RequiredApplications
    List of applications that must be present after migration for verification.
    
.PARAMETER VerifyOnly
    Only verify a previous migration without performing migration steps. Default is $false.
    
.PARAMETER UserEmail
    Email address of the user for notifications. If not provided, toast notifications only.
    
.PARAMETER CompanyName
    Company name for notifications. Default is "Your Organization".
    
.PARAMETER SupportEmail
    Support email address for notifications. Default is "support@yourdomain.com".
    
.PARAMETER SupportPhone
    Support phone number for notifications. Default is "555-123-4567".
    
.EXAMPLE
    .\Start-WS1AzureMigration.ps1
    
.EXAMPLE
    .\Start-WS1AzureMigration.ps1 -SilentMode -UserEmail "user@contoso.com"
    
.NOTES
    File Name      : Start-WS1AzureMigration.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

# Script Parameters
param (
    [Parameter(Mandatory = $false)]
    [switch]$SilentMode,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\WS1Migration",
    
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = "$env:TEMP\WS1Migration\Backups",
    
    [Parameter(Mandatory = $false)]
    [string[]]$RequiredApplications = @("Microsoft 365 Apps", "Company VPN"),
    
    [Parameter(Mandatory = $false)]
    [switch]$VerifyOnly,
    
    [Parameter(Mandatory = $false)]
    [string]$UserEmail,
    
    [Parameter(Mandatory = $false)]
    [string]$CompanyName = "Your Organization",
    
    [Parameter(Mandatory = $false)]
    [string]$SupportEmail = "support@yourdomain.com",
    
    [Parameter(Mandatory = $false)]
    [string]$SupportPhone = "555-123-4567"
)

# Find the modules directory (one level up from scripts directory, then into modules)
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$modulesPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "modules"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Create backup directory if it doesn't exist
if (-not (Test-Path -Path $BackupPath)) {
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
}

# Import the logging module first
$loggingModulePath = Join-Path -Path $modulesPath -ChildPath "LoggingModule.psm1"
if (Test-Path -Path $loggingModulePath) {
    Import-Module -Name $loggingModulePath -Force
} else {
    Write-Error "Required module LoggingModule.psm1 not found in $modulesPath"
    exit 1
}

# Initialize logging
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Global:LogFilePath = Join-Path -Path $LogPath -ChildPath "Migration_$timestamp.log"
Write-Log -Message "Migration started. Silent Mode: $SilentMode" -Level Information

# Function to import required modules
function Import-RequiredModule {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    $modulePath = Join-Path -Path $modulesPath -ChildPath "$ModuleName.psm1"
    
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
        Write-Log -Message "Imported module: $ModuleName" -Level Information
        return $true
    } else {
        Write-Log -Message "Required module $ModuleName not found in $modulesPath" -Level Error
        return $false
    }
}

# Import required modules
$allModulesAvailable = $true
$requiredModules = @(
    "RollbackMechanism",
    "MigrationVerification",
    "UserCommunicationFramework"
)

foreach ($module in $requiredModules) {
    $moduleAvailable = Import-RequiredModule -ModuleName $module
    if (-not $moduleAvailable) {
        $allModulesAvailable = $false
    }
}

if (-not $allModulesAvailable) {
    Write-Log -Message "One or more required modules are missing. Cannot proceed with migration." -Level Error
    Write-Error "One or more required modules are missing. Cannot proceed with migration."
    exit 1
}

# Set notification configuration
Set-NotificationConfig -CompanyName $CompanyName -SupportEmail $SupportEmail -SupportPhone $SupportPhone -EnableToast $true

# Function to update migration progress
function Update-MigrationStatus {
    param (
        [Parameter(Mandatory = $true)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage
    )
    
    Write-Log -Message "[$PercentComplete%] $StatusMessage" -Level Information
    
    if ($SilentMode) {
        Show-MigrationProgress -PercentComplete $PercentComplete -StatusMessage $StatusMessage -Silent -UserEmail $UserEmail
    } else {
        Show-MigrationProgress -PercentComplete $PercentComplete -StatusMessage $StatusMessage -UserEmail $UserEmail
    }
}

# Function to perform verification only
function Start-MigrationVerificationOnly {
    try {
        Write-Log -Message "Starting migration verification only" -Level Information
        Update-MigrationStatus -PercentComplete 10 -StatusMessage "Starting migration verification"
        
        # Generate verification reports directory in log path
        $reportPath = Join-Path -Path $LogPath -ChildPath "VerificationReports"
        if (-not (Test-Path -Path $reportPath)) {
            New-Item -Path $reportPath -ItemType Directory -Force | Out-Null
        }
        
        Update-MigrationStatus -PercentComplete 50 -StatusMessage "Running verification checks..."
        
        # Run comprehensive verification
        $verificationResults = Invoke-MigrationVerification -OutputPath $reportPath -Format "Both" -RequiredApplications $RequiredApplications
        
        if ($verificationResults.OverallSuccess) {
            Update-MigrationStatus -PercentComplete 100 -StatusMessage "Verification completed successfully"
            Send-MigrationNotification -Type "MigrationComplete" -UserEmail $UserEmail
            
            if (-not $SilentMode) {
                # Open verification report
                if ($verificationResults.ReportPaths.Count -gt 0) {
                    Start-Process $verificationResults.ReportPaths[0]
                }
            }
            
            return $true
        } else {
            Update-MigrationStatus -PercentComplete 100 -StatusMessage "Verification completed with issues"
            
            if ($verificationResults.ContainsKey("Error")) {
                Send-MigrationNotification -Type "MigrationFailed" -Parameters @($verificationResults.Error) -UserEmail $UserEmail
            } else {
                Send-MigrationNotification -Type "MigrationFailed" -Parameters @("Verification failed. See report for details.") -UserEmail $UserEmail
            }
            
            if (-not $SilentMode) {
                # Open verification report
                if ($verificationResults.ReportPaths.Count -gt 0) {
                    Start-Process $verificationResults.ReportPaths[0]
                }
            }
            
            return $false
        }
    }
    catch {
        Update-MigrationStatus -PercentComplete 100 -StatusMessage "Verification failed with error"
        Write-Log -Message "Verification error: $_" -Level Error
        Send-MigrationNotification -Type "MigrationFailed" -Parameters @($_.Exception.Message) -UserEmail $UserEmail
        return $false
    }
}

# Function to perform the migration
function Start-FullMigration {
    try {
        Write-Log -Message "Starting full migration process" -Level Information
        Update-MigrationStatus -PercentComplete 0 -StatusMessage "Initializing migration"
        
        # 1. Initialize rollback mechanism
        $backupFolder = Initialize-RollbackMechanism -BackupPath $BackupPath
        if (-not $backupFolder) {
            throw "Failed to initialize rollback mechanism"
        }
        
        Update-MigrationStatus -PercentComplete 5 -StatusMessage "Creating system restore point"
        
        # 2. Create system restore point
        $restorePoint = New-MigrationRestorePoint -Description "Pre-Migration Restore Point"
        if (-not $restorePoint) {
            Write-Log -Message "Failed to create system restore point. Continuing without it." -Level Warning
        }
        
        # 3. Notify user of migration start
        Send-MigrationNotification -Type "MigrationStart" -UserEmail $UserEmail
        
        # 4. Backup Workspace One configuration
        Update-MigrationStatus -PercentComplete 10 -StatusMessage "Backing up Workspace One configuration"
        $backupSuccess = Invoke-MigrationStep -Name "Backup Workspace One Configuration" -ScriptBlock {
            return Backup-WorkspaceOneConfiguration -BackupFolder $backupFolder
        } -ErrorAction Continue
        
        if (-not $backupSuccess) {
            Write-Log -Message "Warning: Backup of Workspace One configuration was not fully successful" -Level Warning
        }
        
        # 5. Uninstall Workspace One components
        Update-MigrationStatus -PercentComplete 20 -StatusMessage "Removing Workspace One components"
        $uninstallSuccess = Invoke-MigrationStep -Name "Uninstall Workspace One" -ScriptBlock {
            # Simulated uninstall (replace with actual uninstall logic)
            $airWatchAgent = Get-Service -Name "AirWatchMDMService" -ErrorAction SilentlyContinue
            if ($null -ne $airWatchAgent) {
                # Actual uninstall would happen here
                Write-Log -Message "Would uninstall Workspace One agent here" -Level Information
            }
            return $true
        } -ErrorAction Continue
        
        if (-not $uninstallSuccess) {
            throw "Failed to uninstall Workspace One components"
        }
        
        # 6. Pre-configure Azure enrollment
        Update-MigrationStatus -PercentComplete 30 -StatusMessage "Preparing for Azure enrollment"
        $prepSuccess = Invoke-MigrationStep -Name "Prepare Azure Enrollment" -ScriptBlock {
            # Simulated Azure preparation (replace with actual preparation logic)
            Write-Log -Message "Would prepare Azure enrollment here" -Level Information
            return $true
        } -ErrorAction Continue
        
        if (-not $prepSuccess) {
            throw "Failed to prepare for Azure enrollment"
        }
        
        # 7. Configure Azure AD Join
        Update-MigrationStatus -PercentComplete 50 -StatusMessage "Configuring Azure AD Join"
        $joinSuccess = Invoke-MigrationStep -Name "Configure Azure AD Join" -ScriptBlock {
            # Simulated Azure AD Join (replace with actual join logic)
            Write-Log -Message "Would configure Azure AD Join here" -Level Information
            return $true
        } -ErrorAction Continue
        
        if (-not $joinSuccess) {
            throw "Failed to configure Azure AD Join"
        }
        
        # 8. Configure Intune enrollment
        Update-MigrationStatus -PercentComplete 70 -StatusMessage "Configuring Intune enrollment"
        $intuneSuccess = Invoke-MigrationStep -Name "Configure Intune Enrollment" -ScriptBlock {
            # Simulated Intune enrollment (replace with actual enrollment logic)
            Write-Log -Message "Would configure Intune enrollment here" -Level Information
            return $true
        } -ErrorAction Continue
        
        if (-not $intuneSuccess) {
            throw "Failed to configure Intune enrollment"
        }
        
        # 9. Verify migration
        Update-MigrationStatus -PercentComplete 90 -StatusMessage "Verifying migration"
        
        # Generate verification reports directory in log path
        $reportPath = Join-Path -Path $LogPath -ChildPath "VerificationReports"
        if (-not (Test-Path -Path $reportPath)) {
            New-Item -Path $reportPath -ItemType Directory -Force | Out-Null
        }
        
        $verificationResults = Invoke-MigrationVerification -OutputPath $reportPath -Format "Both" -RequiredApplications $RequiredApplications
        
        if (-not $verificationResults.OverallSuccess) {
            throw "Migration verification failed. See report for details."
        }
        
        # 10. Complete transaction
        Update-MigrationStatus -PercentComplete 95 -StatusMessage "Finalizing migration"
        Complete-MigrationTransaction -CleanupBackups $false
        
        # 11. Notify user of completion
        Update-MigrationStatus -PercentComplete 100 -StatusMessage "Migration completed successfully"
        Send-MigrationNotification -Type "MigrationComplete" -UserEmail $UserEmail
        
        # 12. Collect feedback if not in silent mode
        if (-not $SilentMode) {
            Get-MigrationFeedback -UserEmail $UserEmail
            
            # Open verification report
            if ($verificationResults.ReportPaths.Count -gt 0) {
                Start-Process $verificationResults.ReportPaths[0]
            }
        }
        
        Write-Log -Message "Migration completed successfully" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Migration error: $_" -Level Error
        
        # Try to rollback
        Update-MigrationStatus -PercentComplete 0 -StatusMessage "Error occurred, attempting rollback"
        
        try {
            Restore-WorkspaceOneMigration -UseSystemRestore $true -Force
            Update-MigrationStatus -PercentComplete 0 -StatusMessage "Rollback completed"
            Send-MigrationNotification -Type "MigrationFailed" -Parameters @("Migration failed with error: $($_.Exception.Message)") -UserEmail $UserEmail
        }
        catch {
            Write-Log -Message "Rollback error: $_" -Level Error
            Update-MigrationStatus -PercentComplete 0 -StatusMessage "Rollback failed"
            Send-MigrationNotification -Type "MigrationFailed" -Parameters @("Migration and rollback both failed. Please contact IT support.") -UserEmail $UserEmail
        }
        
        return $false
    }
}

# Main execution flow
try {
    if ($VerifyOnly) {
        # Only perform verification
        $success = Start-MigrationVerificationOnly
    }
    else {
        # Perform full migration
        $success = Start-FullMigration
    }
    
    # Return exit code
    if ($success) {
        Write-Host "Migration completed successfully. See log file for details: $Global:LogFilePath" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "Migration failed. See log file for details: $Global:LogFilePath" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Log -Message "Unhandled exception in migration script: $_" -Level Error
    Write-Host "Unhandled exception in migration script. See log file for details: $Global:LogFilePath" -ForegroundColor Red
    exit 1
} 