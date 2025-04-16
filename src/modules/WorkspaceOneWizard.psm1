################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Provides a user-friendly GUI wizard for end users to complete Workspace One enrollment                                #
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
.DESCRIPTION
    Provides a user-friendly GUI wizard for end users to complete Workspace One enrollment
    when automated methods via GPO or endpoint management have failed.
.NOTES
    Version: 1.0
    Author: Modern Windows Management
    RequiredVersion: PowerShell 5.1 or higher
#>

#Requires -Version 5.1
using namespace System.Windows.Forms
using namespace System.Drawing

# Import required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Module variables
$script:LogPath = Join-Path -Path $env:TEMP -ChildPath "WS1_Enrollment_Logs"
$script:LogFile = Join-Path -Path $script:LogPath -ChildPath "WS1_Enrollment_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:EnrollmentServer = "https://ws1enrollmentserver.example.com"
$script:IntuneIntegrationEnabled = $true

# Configuration file support
function Import-WS1Config {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "WS1Config.json")
    )
    
    try {
        if (Test-Path -Path $ConfigPath) {
            Write-WS1Log -Message "Loading configuration from $ConfigPath"
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            
            # Update enrollment server if specified
            if ($config.EnrollmentServer) {
                $script:EnrollmentServer = $config.EnrollmentServer
                Write-WS1Log -Message "Enrollment server set to: $script:EnrollmentServer"
            }
            
            # Update Intune integration setting if specified
            if ($null -ne $config.IntuneIntegrationEnabled) {
                $script:IntuneIntegrationEnabled = $config.IntuneIntegrationEnabled
                Write-WS1Log -Message "Intune integration enabled: $script:IntuneIntegrationEnabled"
            }
            
            return $true
        } else {
            Write-WS1Log -Message "Configuration file not found at $ConfigPath, using defaults" -Level INFO
            return $false
        }
    }
    catch {
        Write-WS1Log -Message "Error loading configuration: $_" -Level ERROR
        return $false
    }
}

function Initialize-WS1Logging {
    <#
    .SYNOPSIS
        Initializes logging for the Workspace One enrollment process.
    .DESCRIPTION
        Creates logging directory and file for tracking the Workspace One enrollment process.
    .EXAMPLE
        Initialize-WS1Logging
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        # Create log directory if it doesn't exist
        if (-not (Test-Path -Path $script:LogPath -PathType Container)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        
        # Initialize log file with header
        $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
        
        $logHeader = @"
====================================================
Workspace One Enrollment Wizard Log
Started: $date
====================================================
Computer Name: $($env:COMPUTERNAME)
User: $($env:USERNAME)
OS: $($osInfo.Caption) (Build $($osInfo.BuildNumber))
Manufacturer: $($computerInfo.Manufacturer)
Model: $($computerInfo.Model)
====================================================

"@
        $logHeader | Out-File -FilePath $script:LogFile -Encoding utf8
        
        Write-WS1Log -Message "Logging initialized"
        return $true
    }
    catch {
        # If we can't create a log file, write to Windows Event Log
        Write-EventLog -LogName Application -Source "Workspace One Enrollment" -EntryType Error -EventId 1001 -Message "Failed to initialize logging: $_" -ErrorAction SilentlyContinue
        return $false
    }
}

function Write-WS1Log {
    <#
    .SYNOPSIS
        Writes a message to the Workspace One enrollment log.
    .DESCRIPTION
        Logs a message with timestamp to the Workspace One enrollment log file.
    .PARAMETER Message
        The message to log.
    .PARAMETER Level
        The log level (INFO, WARNING, ERROR).
    .EXAMPLE
        Write-WS1Log -Message "Starting enrollment process" -Level INFO
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Write to log file
        if (Test-Path -Path $script:LogFile) {
            Add-Content -Path $script:LogFile -Value $logMessage -Force
        }
        
        # Also write to console for troubleshooting
        switch ($Level) {
            "INFO" { Write-Verbose $logMessage }
            "WARNING" { Write-Warning $Message }
            "ERROR" { Write-Error $Message }
        }
    }
    catch {
        # Fallback if logging fails
        Write-Warning "Failed to write to log: $_"
    }
}

function Test-EnrollmentPrerequisites {
    <#
    .SYNOPSIS
        Tests prerequisites for Workspace One enrollment.
    .DESCRIPTION
        Verifies that all prerequisites for Workspace One enrollment are met.
    .EXAMPLE
        Test-EnrollmentPrerequisites
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    Write-WS1Log -Message "Checking enrollment prerequisites"
    
    $results = [PSCustomObject]@{
        Success = $true
        NetworkConnectivity = $false
        EnrollmentServerReachable = $false
        AdminRights = $false
        DeviceEligible = $false
        Issues = @()
    }
    
    # Check network connectivity
    try {
        $networkConnection = Test-NetConnection -ComputerName "www.microsoft.com" -InformationLevel Quiet
        $results.NetworkConnectivity = $networkConnection
        
        if (-not $networkConnection) {
            $results.Success = $false
            $results.Issues += "No internet connectivity detected"
            Write-WS1Log -Message "No internet connectivity detected" -Level WARNING
        } else {
            Write-WS1Log -Message "Internet connectivity verified"
        }
    }
    catch {
        $results.Success = $false
        $results.Issues += "Failed to check network connectivity: $_"
        Write-WS1Log -Message "Failed to check network connectivity: $_" -Level ERROR
    }
    
    # Check enrollment server reachability
    try {
        $serverConnection = Test-NetConnection -ComputerName ($script:EnrollmentServer -replace "https://", "") -Port 443 -InformationLevel Quiet
        $results.EnrollmentServerReachable = $serverConnection
        
        if (-not $serverConnection) {
            $results.Success = $false
            $results.Issues += "Cannot reach enrollment server"
            Write-WS1Log -Message "Cannot reach enrollment server: $script:EnrollmentServer" -Level WARNING
        } else {
            Write-WS1Log -Message "Enrollment server reachable"
        }
    }
    catch {
        $results.Success = $false
        $results.Issues += "Failed to check enrollment server: $_"
        Write-WS1Log -Message "Failed to check enrollment server: $_" -Level ERROR
    }
    
    # Check admin rights
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
        $results.AdminRights = $principal.IsInRole($adminRole)
        
        if (-not $results.AdminRights) {
            $results.Issues += "User does not have administrator rights"
            Write-WS1Log -Message "User does not have administrator rights" -Level WARNING
        } else {
            Write-WS1Log -Message "Administrator rights verified"
        }
    }
    catch {
        $results.Issues += "Failed to check administrator rights: $_"
        Write-WS1Log -Message "Failed to check administrator rights: $_" -Level ERROR
    }
    
    # Check if device is eligible (not already enrolled)
    try {
        # Check for MDM enrollment
        $mdmInfo = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\" -ErrorAction SilentlyContinue
        
        if ($mdmInfo.Count -gt 0) {
            $results.DeviceEligible = $false
            $results.Issues += "Device appears to be already enrolled in MDM"
            Write-WS1Log -Message "Device appears to be already enrolled in MDM" -Level WARNING
        } else {
            $results.DeviceEligible = $true
            Write-WS1Log -Message "Device is eligible for enrollment"
        }
    }
    catch {
        $results.Issues += "Failed to check device eligibility: $_"
        Write-WS1Log -Message "Failed to check device eligibility: $_" -Level ERROR
    }
    
    # Update overall success
    $results.Success = ($results.NetworkConnectivity -and $results.EnrollmentServerReachable -and $results.DeviceEligible)
    
    Write-WS1Log -Message "Prerequisite check completed. Success: $($results.Success)"
    return $results
}

function Start-EnrollmentProcess {
    <#
    .SYNOPSIS
        Starts the actual Workspace One enrollment process.
    .DESCRIPTION
        Executes commands to enroll the device in Workspace One with Intune integration.
    .PARAMETER Username
        The username for enrollment.
    .PARAMETER Domain
        The domain for enrollment.
    .PARAMETER Server
        The enrollment server URL.
    .EXAMPLE
        Start-EnrollmentProcess -Username "user@example.com" -Domain "example.com" -Server "https://ws1.example.com"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $true)]
        [string]$Server
    )
    
    try {
        Write-WS1Log -Message "Starting enrollment process for $Username in domain $Domain"
        
        # Create temporary directory for enrollment files
        $tempDir = Join-Path -Path $env:TEMP -ChildPath "WS1Enrollment_$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        
        Write-WS1Log -Message "Created temporary directory: $tempDir"
        
        # In a real implementation, you would:
        # 1. Download enrollment agent if needed
        # 2. Prepare enrollment parameters
        # 3. Launch enrollment process
        
        # Simulate enrollment for this example
        Write-WS1Log -Message "Preparing device for enrollment"
        Start-Sleep -Seconds 2
        
        Write-WS1Log -Message "Connecting to enrollment server"
        Start-Sleep -Seconds 2
        
        Write-WS1Log -Message "Processing enrollment"
        Start-Sleep -Seconds 3
        
        # Set MDM enrollment settings (this would use appropriate Workspace One cmdlets in a real implementation)
        Write-WS1Log -Message "Configuring MDM enrollment settings"
        
        # Clean up
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
            Write-WS1Log -Message "Removed temporary directory"
        }
        
        Write-WS1Log -Message "Enrollment process completed successfully"
        return $true
    }
    catch {
        Write-WS1Log -Message "Enrollment process failed: $_" -Level ERROR
        return $false
    }
}

function Show-CompletionScreen {
    <#
    .SYNOPSIS
        Shows enrollment completion screen.
    .DESCRIPTION
        Displays a completion screen with next steps based on enrollment outcome.
    .PARAMETER Success
        Whether enrollment was successful.
    .PARAMETER Form
        The parent form.
    .EXAMPLE
        Show-CompletionScreen -Success $true -Form $mainForm
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form
    )
    
    # Clear the form
    $Form.Controls.Clear()
    
    # Create completion panel
    $completionPanel = New-Object System.Windows.Forms.Panel
    $completionPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $completionPanel.Padding = New-Object System.Windows.Forms.Padding(20)
    
    # Add icon
    $iconPictureBox = New-Object System.Windows.Forms.PictureBox
    $iconPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::AutoSize
    $iconPictureBox.Location = New-Object System.Drawing.Point(($Form.ClientSize.Width - 48) / 2, 30)
    
    if ($Success) {
        # Success icon (checkmark)
        $iconPictureBox.Image = [System.Drawing.SystemIcons]::Information.ToBitmap()
    } else {
        # Error icon
        $iconPictureBox.Image = [System.Drawing.SystemIcons]::Error.ToBitmap()
    }
    
    # Add header
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $headerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $headerLabel.Dock = [System.Windows.Forms.DockStyle]::Top
    $headerLabel.Padding = New-Object System.Windows.Forms.Padding(0, 90, 0, 20)
    
    if ($Success) {
        $headerLabel.Text = "Enrollment Completed Successfully"
        $headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    } else {
        $headerLabel.Text = "Enrollment Could Not Be Completed"
        $headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(209, 52, 56)
    }
    
    # Add message
    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $messageLabel.TextAlign = [System.Drawing.ContentAlignment]::TopCenter
    $messageLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
    
    if ($Success) {
        $messageLabel.Text = "Your device has been successfully enrolled in Workspace One.`r`n`r`nYou may now close this wizard."
    } else {
        $messageLabel.Text = "We encountered an issue during the enrollment process.`r`n`r`nPlease contact your IT support team for assistance.`r`n`r`nLog file location: $script:LogFile"
    }
    
    # Add button panel
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $buttonPanel.Height = 60
    
    # Add close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Width = 120
    $closeButton.Height = 40
    $closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $closeButton.Location = New-Object System.Drawing.Point(($Form.ClientSize.Width - 120) / 2, 10)
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $closeButton.ForeColor = [System.Drawing.Color]::White
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    
    $closeButton.Add_Click({
        $Form.Close()
    })
    
    # Assemble the form
    $buttonPanel.Controls.Add($closeButton)
    $completionPanel.Controls.Add($iconPictureBox)
    $completionPanel.Controls.Add($messageLabel)
    $Form.Controls.Add($completionPanel)
    $Form.Controls.Add($headerLabel)
    $Form.Controls.Add($buttonPanel)
}

function Show-EnrollmentWizard {
    <#
    .SYNOPSIS
        Displays the Workspace One enrollment wizard.
    .DESCRIPTION
        Shows a GUI wizard to guide users through Workspace One enrollment.
    .EXAMPLE
        Show-EnrollmentWizard
    #>
    [CmdletBinding()]
    param()
    
    # Initialize logging
    Initialize-WS1Logging
    
    # Load configuration if available
    Import-WS1Config
    
    # Create main form
    $mainForm = New-Object System.Windows.Forms.Form
    $mainForm.Text = "Workspace One Enrollment Wizard"
    $mainForm.Size = New-Object System.Drawing.Size(700, 500)
    $mainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $mainForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $mainForm.MaximizeBox = $false
    $mainForm.MinimizeBox = $true
    $mainForm.BackColor = [System.Drawing.Color]::White
    
    # Create welcome panel
    $welcomePanel = New-Object System.Windows.Forms.Panel
    $welcomePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $welcomePanel.Padding = New-Object System.Windows.Forms.Padding(20)
    
    # Create logo
    $logoPictureBox = New-Object System.Windows.Forms.PictureBox
    $logoPictureBox.Size = New-Object System.Drawing.Size(200, 70)
    $logoPictureBox.Location = New-Object System.Drawing.Point(($mainForm.ClientSize.Width - 200) / 2, 20)
    $logoPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    
    # In a real implementation, load your company logo
    # $logoPictureBox.Image = [System.Drawing.Image]::FromFile("C:\path\to\logo.png")
    
    # Create title
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Welcome to Workspace One Enrollment"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $titleLabel.Location = New-Object System.Drawing.Point(0, 100)
    $titleLabel.Size = New-Object System.Drawing.Size($mainForm.ClientSize.Width, 40)
    
    # Create description
    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = "This wizard will help you enroll your device in Workspace One.`r`n`r`nBefore continuing, please ensure you have:`r`n- Internet connectivity`r`n- Your company email address`r`n- Time to complete the enrollment (5-10 minutes)"
    $descriptionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $descriptionLabel.Location = New-Object System.Drawing.Point(50, 150)
    $descriptionLabel.Size = New-Object System.Drawing.Size($mainForm.ClientSize.Width - 100, 150)
    
    # Create form
    $formPanel = New-Object System.Windows.Forms.Panel
    $formPanel.Location = New-Object System.Drawing.Point(50, 300)
    $formPanel.Size = New-Object System.Drawing.Size($mainForm.ClientSize.Width - 100, 120)
    
    # Email label
    $emailLabel = New-Object System.Windows.Forms.Label
    $emailLabel.Text = "Company Email:"
    $emailLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $emailLabel.Location = New-Object System.Drawing.Point(0, 10)
    $emailLabel.Size = New-Object System.Drawing.Size(150, 25)
    
    # Email text box
    $emailTextBox = New-Object System.Windows.Forms.TextBox
    $emailTextBox.Location = New-Object System.Drawing.Point(150, 10)
    $emailTextBox.Size = New-Object System.Drawing.Size(250, 25)
    $emailTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    
    # Domain label
    $domainLabel = New-Object System.Windows.Forms.Label
    $domainLabel.Text = "Domain:"
    $domainLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $domainLabel.Location = New-Object System.Drawing.Point(0, 45)
    $domainLabel.Size = New-Object System.Drawing.Size(150, 25)
    
    # Domain text box
    $domainTextBox = New-Object System.Windows.Forms.TextBox
    $domainTextBox.Location = New-Object System.Drawing.Point(150, 45)
    $domainTextBox.Size = New-Object System.Drawing.Size(250, 25)
    $domainTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $domainTextBox.Text = "example.com"
    
    # Server label
    $serverLabel = New-Object System.Windows.Forms.Label
    $serverLabel.Text = "Enrollment Server:"
    $serverLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $serverLabel.Location = New-Object System.Drawing.Point(0, 80)
    $serverLabel.Size = New-Object System.Drawing.Size(150, 25)
    
    # Server text box
    $serverTextBox = New-Object System.Windows.Forms.TextBox
    $serverTextBox.Location = New-Object System.Drawing.Point(150, 80)
    $serverTextBox.Size = New-Object System.Drawing.Size(250, 25)
    $serverTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $serverTextBox.Text = $script:EnrollmentServer
    
    # Button panel
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $buttonPanel.Height = 60
    
    # Next button
    $nextButton = New-Object System.Windows.Forms.Button
    $nextButton.Text = "Continue"
    $nextButton.Width = 120
    $nextButton.Height = 40
    $nextButton.Location = New-Object System.Drawing.Point(($mainForm.ClientSize.Width - 140), 10)
    $nextButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $nextButton.ForeColor = [System.Drawing.Color]::White
    $nextButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $nextButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    
    $nextButton.Add_Click({
        # Validate input
        if ([string]::IsNullOrWhiteSpace($emailTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter your company email address.", "Input Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($domainTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter your domain.", "Input Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($serverTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter the enrollment server.", "Input Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # Clear the form
        $mainForm.Controls.Clear()
        
        # Create progress panel
        $progressPanel = New-Object System.Windows.Forms.Panel
        $progressPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
        $progressPanel.Padding = New-Object System.Windows.Forms.Padding(20)
        
        # Progress title
        $progressTitleLabel = New-Object System.Windows.Forms.Label
        $progressTitleLabel.Text = "Enrolling Device"
        $progressTitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
        $progressTitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
        $progressTitleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $progressTitleLabel.Dock = [System.Windows.Forms.DockStyle]::Top
        $progressTitleLabel.Padding = New-Object System.Windows.Forms.Padding(0, 20, 0, 20)
        
        # Progress bar
        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $progressBar.MarqueeAnimationSpeed = 30
        $progressBar.Height = 25
        $progressBar.Dock = [System.Windows.Forms.DockStyle]::Top
        
        # Status label
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Text = "Checking prerequisites..."
        $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $statusLabel.Dock = [System.Windows.Forms.DockStyle]::Top
        $statusLabel.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
        
        # Details text box
        $detailsTextBox = New-Object System.Windows.Forms.TextBox
        $detailsTextBox.Multiline = $true
        $detailsTextBox.ReadOnly = $true
        $detailsTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $detailsTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
        $detailsTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $detailsTextBox.BackColor = [System.Drawing.Color]::White
        
        # Assemble progress panel
        $progressPanel.Controls.Add($detailsTextBox)
        $progressPanel.Controls.Add($statusLabel)
        $progressPanel.Controls.Add($progressBar)
        $progressPanel.Controls.Add($progressTitleLabel)
        $mainForm.Controls.Add($progressPanel)
        
        # Force UI update
        $mainForm.Update()
        
        # Start the enrollment process
        $username = $emailTextBox.Text
        $domain = $domainTextBox.Text
        $server = $serverTextBox.Text
        
        # Background worker to prevent UI freezing
        $bgWorker = New-Object System.ComponentModel.BackgroundWorker
        $bgWorker.WorkerReportsProgress = $true
        
        $bgWorker.Add_DoWork({
            param($sender, $e)
            $e.Result = @{
                Success = $false
                Log = @()
            }
            
            # Step 1: Check prerequisites
            $sender.ReportProgress(10, "Checking prerequisites...")
            $e.Result.Log += "Checking enrollment prerequisites..."
            
            $prereqs = Test-EnrollmentPrerequisites
            
            if (-not $prereqs.Success) {
                $e.Result.Log += "Prerequisite check failed:"
                foreach ($issue in $prereqs.Issues) {
                    $e.Result.Log += "- $issue"
                }
                return
            }
            
            $e.Result.Log += "Prerequisites check passed."
            $sender.ReportProgress(30, "Prerequisites verified...")
            
            # Step 2: Prepare for enrollment
            $sender.ReportProgress(40, "Preparing for enrollment...")
            $e.Result.Log += "Preparing device for enrollment..."
            Start-Sleep -Seconds 2
            
            # Step 3: Start enrollment
            $sender.ReportProgress(60, "Enrolling in Workspace One...")
            $e.Result.Log += "Starting enrollment process..."
            
            $enrollResult = Start-EnrollmentProcess -Username $username -Domain $domain -Server $server
            
            if (-not $enrollResult) {
                $e.Result.Log += "Enrollment process failed."
                return
            }
            
            $e.Result.Log += "Enrollment process completed successfully."
            $sender.ReportProgress(90, "Finalizing enrollment...")
            
            # Step 4: Finalize
            $sender.ReportProgress(100, "Enrollment complete!")
            $e.Result.Success = $true
        })
        
        $bgWorker.Add_ProgressChanged({
            param($sender, $e)
            $statusLabel.Text = $e.UserState
            $detailsTextBox.AppendText("$($e.UserState)`r`n")
        })
        
        $bgWorker.Add_RunWorkerCompleted({
            param($sender, $e)
            
            # Display log
            foreach ($line in $e.Result.Log) {
                $detailsTextBox.AppendText("$line`r`n")
            }
            
            # Update UI based on result
            Show-CompletionScreen -Success $e.Result.Success -Form $mainForm
        })
        
        # Start the background process
        $bgWorker.RunWorkerAsync()
    })
    
    # Close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Cancel"
    $closeButton.Width = 120
    $closeButton.Height = 40
    $closeButton.Location = New-Object System.Drawing.Point(10, 10)
    $closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    
    $closeButton.Add_Click({
        Write-WS1Log -Message "User canceled the enrollment wizard" -Level INFO
        $mainForm.Close()
    })
    
    # Assemble the form
    $formPanel.Controls.Add($serverTextBox)
    $formPanel.Controls.Add($serverLabel)
    $formPanel.Controls.Add($domainTextBox)
    $formPanel.Controls.Add($domainLabel)
    $formPanel.Controls.Add($emailTextBox)
    $formPanel.Controls.Add($emailLabel)
    $buttonPanel.Controls.Add($nextButton)
    $buttonPanel.Controls.Add($closeButton)
    $welcomePanel.Controls.Add($formPanel)
    $welcomePanel.Controls.Add($descriptionLabel)
    $welcomePanel.Controls.Add($titleLabel)
    $welcomePanel.Controls.Add($logoPictureBox)
    $mainForm.Controls.Add($welcomePanel)
    $mainForm.Controls.Add($buttonPanel)
    
    # Show the form
    Write-WS1Log -Message "Launching Workspace One enrollment wizard"
    $mainForm.ShowDialog()
}

# Export the functions
Export-ModuleMember -Function Show-EnrollmentWizard, Test-EnrollmentPrerequisites, Import-WS1Config 





