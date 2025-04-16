#Requires -Version 5.1
#Requires -Modules @{ ModuleName="PresentationFramework"; ModuleVersion="1.0.0.0" }
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# GUI interface for the Workspace One to Azure/Intune Migration Toolkit.                                                #
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
    GUI interface for the Workspace One to Azure/Intune Migration Toolkit.
    
.DESCRIPTION
    Provides a user-friendly interface for initiating and monitoring the migration
    from Workspace One to Azure/Intune, designed to run without admin rights.
    
.NOTES
    File Name      : MigrationUI.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1, .NET Framework 4.5
    Version        : 1.0.0
#>

# Import required modules
$modulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\modules'
$modulesToImport = @(
    'LoggingModule.psm1',
    'UserCommunicationFramework.psm1',
    'MigrationVerification.psm1',
    'RollbackMechanism.psm1'
)

foreach ($module in $modulesToImport) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath $module
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        Write-Error "Required module $module not found in $modulesPath"
        exit 1
    }
}

# Script Parameters
param (
    [Parameter(Mandatory = $false)]
    [switch]$SilentMode,
    
    [Parameter(Mandatory = $false)]
    [switch]$AutoStart,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\WS1Migration"
)

# Script Variables
$script:MigrationStatus = @{
    IsRunning = $false
    CurrentStep = ""
    PercentComplete = 0
    StartTime = $null
    EstimatedEndTime = $null
    ErrorOccurred = $false
    ErrorMessage = ""
}

# Add the WPF assembly when running in interactive mode
if (-not $SilentMode) {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms
}

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Initialize logging
$Global:LogFilePath = Join-Path -Path $LogPath -ChildPath "MigrationUI_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-Log -Message "Migration UI started. Silent Mode: $SilentMode" -Level Information

# Set notification configuration
Set-NotificationConfig -CompanyName "Your Organization" -SupportEmail "support@yourdomain.com" -SupportPhone "555-123-4567" -EnableToast $true

function Update-MigrationProgress {
    param (
        [Parameter(Mandatory = $true)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage
    )
    
    $script:MigrationStatus.PercentComplete = $PercentComplete
    $script:MigrationStatus.CurrentStep = $StatusMessage
    
    # Update UI or send notification based on mode
    if ($SilentMode) {
        Show-MigrationProgress -PercentComplete $PercentComplete -StatusMessage $StatusMessage -Silent
    } else {
        # Update UI controls
        if ($null -ne $progressBar) {
            $progressBar.Value = $PercentComplete
            $statusLabel.Content = $StatusMessage
            $percentLabel.Content = "$PercentComplete%"
            
            # Force UI update
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        # Also send notification at key milestones
        if ($PercentComplete -in @(25, 50, 75, 100)) {
            Show-MigrationProgress -PercentComplete $PercentComplete -StatusMessage $StatusMessage
        }
    }
    
    Write-Log -Message "Progress updated: $PercentComplete% - $StatusMessage" -Level Information
}

function Start-MigrationProcess {
    # Set migration status
    $script:MigrationStatus.IsRunning = $true
    $script:MigrationStatus.StartTime = Get-Date
    $script:MigrationStatus.EstimatedEndTime = (Get-Date).AddMinutes(30)
    $script:MigrationStatus.ErrorOccurred = $false
    $script:MigrationStatus.ErrorMessage = ""
    
    # Run migration in a background job to keep UI responsive
    $migrationScriptBlock = {
        param ($LogPath, $SilentMode)
        
        try {
            # Import required modules in the job context
            $modulesPath = Join-Path -Path $using:PSScriptRoot -ChildPath '..\modules'
            foreach ($module in @('LoggingModule', 'UserCommunicationFramework', 'RollbackMechanism')) {
                $modulePath = Join-Path -Path $modulesPath -ChildPath "$module.psm1"
                if (Test-Path -Path $modulePath) {
                    Import-Module -Name $modulePath -Force
                }
            }
            
            # Step 1: Preparation
            Update-MigrationProgress -PercentComplete 5 -StatusMessage "Preparing system for migration"
            Start-Sleep -Seconds 2 # Simulated work
            
            # Send notification
            Send-MigrationNotification -Type "MigrationStart"
            
            # Step 2: Backup
            Update-MigrationProgress -PercentComplete 10 -StatusMessage "Creating system backup"
            try {
                New-MigrationBackup -Component "Registry" -BackupPath "$env:TEMP\WS1Migration\Backups"
                New-MigrationBackup -Component "WorkspaceOne" -BackupPath "$env:TEMP\WS1Migration\Backups"
            } catch {
                Write-Log -Message "Backup error: $_" -Level Error
                throw "Failed to create backup: $_"
            }
            Start-Sleep -Seconds 3 # Simulated work
            
            # Step 3: Remove Workspace One
            Update-MigrationProgress -PercentComplete 30 -StatusMessage "Removing Workspace One components"
            Start-Sleep -Seconds 5 # Simulated work
            
            # Step 4: Prepare for Azure enrollment
            Update-MigrationProgress -PercentComplete 50 -StatusMessage "Preparing Azure/Intune enrollment"
            Start-Sleep -Seconds 5 # Simulated work
            
            # Step 5: Configure Intune enrollment
            Update-MigrationProgress -PercentComplete 70 -StatusMessage "Configuring Intune settings"
            Start-Sleep -Seconds 3 # Simulated work
            
            # Step 6: Verify migration
            Update-MigrationProgress -PercentComplete 90 -StatusMessage "Verifying migration"
            try {
                $verificationResult = Test-MigrationSuccess
                if (-not $verificationResult.Success) {
                    throw "Migration verification failed: $($verificationResult.Message)"
                }
            } catch {
                Write-Log -Message "Verification error: $_" -Level Error
                throw "Verification failed: $_"
            }
            
            # Step 7: Complete migration
            Update-MigrationProgress -PercentComplete 100 -StatusMessage "Migration completed successfully"
            Send-MigrationNotification -Type "MigrationComplete"
            
            # Get feedback if not in silent mode
            if (-not $SilentMode) {
                Get-MigrationFeedback
            }
            
            # Complete the migration transaction
            Complete-MigrationTransaction -RetentionDays 7
            
            return @{
                Success = $true
                Message = "Migration completed successfully"
            }
        }
        catch {
            Write-Log -Message "Migration error: $_" -Level Error
            
            # Try to rollback
            Update-MigrationProgress -PercentComplete 0 -StatusMessage "Error occurred, attempting rollback"
            
            try {
                Invoke-MigrationRollback -Force
                Update-MigrationProgress -PercentComplete 0 -StatusMessage "Rollback completed"
                Send-MigrationNotification -Type "MigrationFailed" -Parameters @("Migration failed with error: $($_.Exception.Message)")
            }
            catch {
                Write-Log -Message "Rollback error: $_" -Level Error
                Update-MigrationProgress -PercentComplete 0 -StatusMessage "Rollback failed"
            }
            
            return @{
                Success = $false
                Message = $_.Exception.Message
                Error = $_
            }
        }
    }
    
    $migrationJob = Start-Job -ScriptBlock $migrationScriptBlock -ArgumentList $LogPath, $SilentMode
    
    # Set up a timer to check job status
    if (-not $SilentMode) {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000 # 1 second
        $timer.Add_Tick({
            if ($migrationJob.State -eq "Completed") {
                $timer.Stop()
                
                # Get job results
                $results = Receive-Job -Job $migrationJob
                
                if ($results.Success) {
                    # Success
                    Update-MigrationProgress -PercentComplete 100 -StatusMessage "Migration completed successfully"
                    $script:MigrationStatus.IsRunning = $false
                    
                    if ($null -ne $startButton) {
                        $startButton.Content = "Migration Complete"
                        $startButton.IsEnabled = $false
                    }
                    
                    if ($null -ne $cancelButton) {
                        $cancelButton.Content = "Close"
                        $cancelButton.IsEnabled = $true
                    }
                } else {
                    # Failure
                    Update-MigrationProgress -PercentComplete 0 -StatusMessage "Migration failed: $($results.Message)"
                    $script:MigrationStatus.IsRunning = $false
                    $script:MigrationStatus.ErrorOccurred = $true
                    $script:MigrationStatus.ErrorMessage = $results.Message
                    
                    if ($null -ne $startButton) {
                        $startButton.Content = "Retry Migration"
                        $startButton.IsEnabled = $true
                    }
                    
                    if ($null -ne $cancelButton) {
                        $cancelButton.Content = "Close"
                        $cancelButton.IsEnabled = $true
                    }
                    
                    [System.Windows.MessageBox]::Show(
                        "Migration failed: $($results.Message)`n`nCheck the log file for more details.",
                        "Migration Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
                
                # Clean up job
                Remove-Job -Job $migrationJob
            }
            elseif ($migrationJob.State -eq "Failed") {
                $timer.Stop()
                
                # Handle job failure
                Update-MigrationProgress -PercentComplete 0 -StatusMessage "Migration job failed unexpectedly"
                $script:MigrationStatus.IsRunning = $false
                $script:MigrationStatus.ErrorOccurred = $true
                $script:MigrationStatus.ErrorMessage = "Migration job failed unexpectedly"
                
                if ($null -ne $startButton) {
                    $startButton.Content = "Retry Migration"
                    $startButton.IsEnabled = $true
                }
                
                if ($null -ne $cancelButton) {
                    $cancelButton.Content = "Close"
                    $cancelButton.IsEnabled = $true
                }
                
                # Clean up job
                Remove-Job -Job $migrationJob
                
                [System.Windows.MessageBox]::Show(
                    "Migration job failed unexpectedly. Check the log file for more details.",
                    "Migration Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            }
        })
        $timer.Start()
    } else {
        # Wait for job completion in silent mode
        $migrationJob | Wait-Job | Out-Null
        $results = Receive-Job -Job $migrationJob
        
        if ($results.Success) {
            Write-Log -Message "Silent migration completed successfully" -Level Information
        } else {
            Write-Log -Message "Silent migration failed: $($results.Message)" -Level Error
        }
        
        # Clean up job
        Remove-Job -Job $migrationJob
    }
}

# Only create GUI if not in silent mode
if (-not $SilentMode) {
    # Create WPF window
    [xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Workspace One to Azure/Intune Migration" 
    Height="450" 
    Width="600"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <StackPanel Grid.Row="0" Background="#0078D4" Padding="20,20,20,20">
            <TextBlock Text="Workspace One to Azure/Intune Migration" FontSize="24" Foreground="White"/>
            <TextBlock Text="This tool will migrate your device from Workspace One to Microsoft Intune" FontSize="12" Foreground="White" Margin="0,10,0,0"/>
        </StackPanel>
        
        <!-- Content -->
        <Grid Grid.Row="1" Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            
            <!-- Progress Section -->
            <StackPanel Grid.Row="0" Margin="0,20,0,10">
                <TextBlock Text="Migration Progress" FontSize="16" FontWeight="Bold"/>
                <Grid Margin="0,10,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <ProgressBar x:Name="progressBar" Height="20" Minimum="0" Maximum="100" Value="0" Grid.Column="0"/>
                    <TextBlock x:Name="percentLabel" Text="0%" Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock x:Name="statusLabel" Text="Ready to start migration" Margin="0,5,0,0"/>
            </StackPanel>
            
            <!-- Estimated Time -->
            <StackPanel Grid.Row="1" Margin="0,10,0,10">
                <TextBlock Text="Estimated Time" FontSize="16" FontWeight="Bold"/>
                <TextBlock Text="The migration process will take approximately 30 minutes to complete." Margin="0,5,0,0"/>
                <TextBlock Text="Please save your work before starting." Margin="0,5,0,0" FontWeight="Bold"/>
            </StackPanel>
            
            <!-- Notes -->
            <StackPanel Grid.Row="2" Margin="0,10,0,10">
                <TextBlock Text="Important Notes" FontSize="16" FontWeight="Bold"/>
                <TextBlock TextWrapping="Wrap" Margin="0,5,0,0">
                    • Your device will be migrated from Workspace One to Microsoft Intune.<LineBreak/>
                    • Your user profile and data will be preserved.<LineBreak/>
                    • Your device will restart during this process.<LineBreak/>
                    • You may be prompted to sign in with your Microsoft account after restart.<LineBreak/>
                    • For assistance, contact your IT support team.
                </TextBlock>
            </StackPanel>
        </Grid>
        
        <!-- Footer -->
        <Grid Grid.Row="2" Background="#F0F0F0" Padding="20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            
            <TextBlock x:Name="helpLabel" Grid.Column="0" VerticalAlignment="Center">
                <Hyperlink x:Name="helpLink">Need help?</Hyperlink>
            </TextBlock>
            
            <Button x:Name="cancelButton" Content="Cancel" Grid.Column="1" Padding="15,5" Margin="0,0,10,0" IsCancel="True"/>
            <Button x:Name="startButton" Content="Start Migration" Grid.Column="2" Padding="15,5" Background="#0078D4" Foreground="White" IsDefault="True"/>
        </Grid>
    </Grid>
</Window>
"@

    # Create window
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    
    # Get UI elements
    $progressBar = $window.FindName("progressBar")
    $percentLabel = $window.FindName("percentLabel")
    $statusLabel = $window.FindName("statusLabel")
    $startButton = $window.FindName("startButton")
    $cancelButton = $window.FindName("cancelButton")
    $helpLink = $window.FindName("helpLink")
    
    # Set button event handlers
    $startButton.Add_Click({
        if ($script:MigrationStatus.IsRunning) {
            return
        }
        
        $startButton.Content = "Migration in Progress..."
        $startButton.IsEnabled = $false
        $cancelButton.Content = "Cancel"
        $cancelButton.IsEnabled = $true
        
        # Start migration process
        Start-MigrationProcess
    })
    
    $cancelButton.Add_Click({
        if ($script:MigrationStatus.IsRunning) {
            $result = [System.Windows.MessageBox]::Show(
                "Are you sure you want to cancel the migration? This may leave your device in an inconsistent state.",
                "Confirm Cancellation",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                # Cancel migration
                Write-Log -Message "User canceled migration" -Level Warning
                Show-MigrationProgress -PercentComplete 0 -StatusMessage "Migration canceled by user"
                $window.Close()
            }
        } else {
            $window.Close()
        }
    })
    
    $helpLink.Add_Click({
        Show-MigrationGuide -GuideName "TroubleshootingGuide"
    })
    
    # Auto start if specified
    if ($AutoStart) {
        $startButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
    
    # Show window
    $null = $window.ShowDialog()
} else {
    # Silent mode operation
    Write-Log -Message "Running in silent mode" -Level Information
    Start-MigrationProcess
}

# Final cleanup
Write-Log -Message "Migration UI completed" -Level Information 





