#Requires -Version 5.1

<#
.SYNOPSIS
    Provides user communication functionality for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The UserCommunicationFramework module handles all communication with end users
    during the migration process from Workspace One to Azure/Intune, including:
    - Sending notifications about migration status
    - Displaying migration progress
    - Providing guides and documentation
    - Collecting user feedback
    - Supporting multi-channel communication (email, Teams, toast notifications)
    
.NOTES
    File Name      : UserCommunicationFramework.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
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

# Script level variables
$script:NotificationConfig = @{
    EmailEnabled = $false
    TeamsEnabled = $false
    ToastEnabled = $true
    SMTPServer = ""
    FromAddress = ""
    TemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath "..\templates\notifications"
    CompanyName = "Organization"
    SupportEmail = "support@organization.com"
    SupportPhone = "555-123-4567"
}

$script:GuidesPath = Join-Path -Path $PSScriptRoot -ChildPath "..\templates\guides"
$script:FeedbackPath = Join-Path -Path $env:TEMP -ChildPath "MigrationFeedback"

#region Private Functions

function Get-NotificationTemplate {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("MigrationStart", "MigrationProgress", "MigrationComplete", "MigrationFailed", "ActionRequired")]
        [string]$TemplateName
    )
    
    $templatePath = Join-Path -Path $script:NotificationConfig.TemplatesPath -ChildPath "$TemplateName.html"
    
    if (Test-Path -Path $templatePath) {
        return Get-Content -Path $templatePath -Raw
    }
    else {
        # Return a basic template if the file doesn't exist
        switch ($TemplateName) {
            "MigrationStart" {
                return @"
<html>
<body>
<h2>Migration Starting</h2>
<p>Your device is being migrated from Workspace One to Microsoft Intune.</p>
<p>This process may take 30-60 minutes to complete.</p>
<p>Please save your work and keep your device powered on and connected to the network.</p>
<p>For assistance, contact $($script:NotificationConfig.SupportEmail) or call $($script:NotificationConfig.SupportPhone).</p>
</body>
</html>
"@
            }
            "MigrationProgress" {
                return @"
<html>
<body>
<h2>Migration in Progress</h2>
<p>Your device migration is {0}% complete.</p>
<p>Current activity: {1}</p>
<p>Please do not restart your device until the migration is complete.</p>
<p>For assistance, contact $($script:NotificationConfig.SupportEmail) or call $($script:NotificationConfig.SupportPhone).</p>
</body>
</html>
"@
            }
            "MigrationComplete" {
                return @"
<html>
<body>
<h2>Migration Complete</h2>
<p>Your device has been successfully migrated to Microsoft Intune.</p>
<p>You can now use your device normally.</p>
<p>For assistance, contact $($script:NotificationConfig.SupportEmail) or call $($script:NotificationConfig.SupportPhone).</p>
</body>
</html>
"@
            }
            "MigrationFailed" {
                return @"
<html>
<body>
<h2>Migration Issue Detected</h2>
<p>An issue was detected during the migration of your device.</p>
<p>Error: {0}</p>
<p>Our support team has been notified and will be in touch shortly.</p>
<p>For immediate assistance, contact $($script:NotificationConfig.SupportEmail) or call $($script:NotificationConfig.SupportPhone).</p>
</body>
</html>
"@
            }
            "ActionRequired" {
                return @"
<html>
<body>
<h2>Action Required</h2>
<p>Your attention is required to continue the migration process.</p>
<p>Please {0}</p>
<p>For assistance, contact $($script:NotificationConfig.SupportEmail) or call $($script:NotificationConfig.SupportPhone).</p>
</body>
</html>
"@
            }
        }
    }
}

function Show-ToastNotification {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$ImagePath = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpirationTime = 10
    )
    
    try {
        # Load assemblies for Windows 10 toast notifications
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        
        # Define the toast notification XML
        $templateType = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($templateType)
        
        # Set the title and message
        $templateNodes = $template.GetElementsByTagName("text")
        $templateNodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
        $templateNodes.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null
        
        # Set the image if provided
        if ($ImagePath) {
            $imageElements = $template.GetElementsByTagName("image")
            $imageElements.Item(0).Attributes.GetNamedItem("src").NodeValue = $ImagePath
        }
        
        # Create and show the toast notification
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        $toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes($ExpirationTime)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Migration Tool").Show($toast)
        
        Write-Log -Message "Toast notification displayed: $Title" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to display toast notification: $_" -Level Error
        return $false
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Configures the notification settings for user communications.
    
.DESCRIPTION
    Sets up the notification system with company branding, support contact information,
    and enables/disables different notification channels (email, Teams, toast).
    
.PARAMETER CompanyName
    The name of the company to display in communications.
    
.PARAMETER SupportEmail
    The support email address to include in notifications.
    
.PARAMETER SupportPhone
    The support phone number to include in notifications.
    
.PARAMETER SMTPServer
    The SMTP server to use for email notifications.
    
.PARAMETER FromAddress
    The email address to send notifications from.
    
.PARAMETER EnableEmail
    Enable email notifications. Default is false.
    
.PARAMETER EnableTeams
    Enable Microsoft Teams notifications. Default is false.
    
.PARAMETER EnableToast
    Enable Windows toast notifications. Default is true.
    
.PARAMETER TemplatesPath
    The path to custom notification templates.
    
.EXAMPLE
    Set-NotificationConfig -CompanyName "Contoso" -SupportEmail "help@contoso.com" -SupportPhone "555-123-4567" -EnableEmail $true -SMTPServer "smtp.contoso.com" -FromAddress "migration@contoso.com"
    
.OUTPUTS
    None
#>
function Set-NotificationConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$CompanyName,
        
        [Parameter(Mandatory = $false)]
        [string]$SupportEmail,
        
        [Parameter(Mandatory = $false)]
        [string]$SupportPhone,
        
        [Parameter(Mandatory = $false)]
        [string]$SMTPServer,
        
        [Parameter(Mandatory = $false)]
        [string]$FromAddress,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableEmail,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableTeams,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableToast,
        
        [Parameter(Mandatory = $false)]
        [string]$TemplatesPath
    )
    
    # Update only the provided parameters
    if ($PSBoundParameters.ContainsKey('CompanyName')) { $script:NotificationConfig.CompanyName = $CompanyName }
    if ($PSBoundParameters.ContainsKey('SupportEmail')) { $script:NotificationConfig.SupportEmail = $SupportEmail }
    if ($PSBoundParameters.ContainsKey('SupportPhone')) { $script:NotificationConfig.SupportPhone = $SupportPhone }
    if ($PSBoundParameters.ContainsKey('SMTPServer')) { $script:NotificationConfig.SMTPServer = $SMTPServer }
    if ($PSBoundParameters.ContainsKey('FromAddress')) { $script:NotificationConfig.FromAddress = $FromAddress }
    if ($PSBoundParameters.ContainsKey('EnableEmail')) { $script:NotificationConfig.EmailEnabled = $EnableEmail }
    if ($PSBoundParameters.ContainsKey('EnableTeams')) { $script:NotificationConfig.TeamsEnabled = $EnableTeams }
    if ($PSBoundParameters.ContainsKey('EnableToast')) { $script:NotificationConfig.ToastEnabled = $EnableToast }
    if ($PSBoundParameters.ContainsKey('TemplatesPath') -and (Test-Path -Path $TemplatesPath)) { 
        $script:NotificationConfig.TemplatesPath = $TemplatesPath 
    }
    
    Write-Log -Message "Notification configuration updated" -Level Information
}

<#
.SYNOPSIS
    Sends a notification to the user about migration status.
    
.DESCRIPTION
    Sends a notification to the user using the configured communication channels
    (toast, email, Teams) about the migration status or required actions.
    
.PARAMETER Type
    The type of notification to send.
    
.PARAMETER UserEmail
    The user's email address for email notifications.
    
.PARAMETER Parameters
    Additional parameters to include in the notification template.
    
.EXAMPLE
    Send-MigrationNotification -Type "MigrationStart" -UserEmail "user@contoso.com"
    
.OUTPUTS
    System.Boolean. Returns $true if at least one notification was sent successfully.
#>
function Send-MigrationNotification {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("MigrationStart", "MigrationProgress", "MigrationComplete", "MigrationFailed", "ActionRequired")]
        [string]$Type,
        
        [Parameter(Mandatory = $false)]
        [string]$UserEmail,
        
        [Parameter(Mandatory = $false)]
        [object[]]$Parameters = @()
    )
    
    $successCount = 0
    $totalAttempts = 0
    
    # Get notification content
    $template = Get-NotificationTemplate -TemplateName $Type
    
    if ($Parameters.Count -gt 0) {
        # Format the template with parameters
        $notificationContent = $template -f $Parameters
    } else {
        $notificationContent = $template
    }
    
    # Set title based on notification type
    $title = switch ($Type) {
        "MigrationStart" { "Migration Starting" }
        "MigrationProgress" { "Migration in Progress" }
        "MigrationComplete" { "Migration Complete" }
        "MigrationFailed" { "Migration Issue Detected" }
        "ActionRequired" { "Action Required" }
    }
    
    # Send toast notification if enabled
    if ($script:NotificationConfig.ToastEnabled) {
        $totalAttempts++
        
        # Extract plain text message from HTML content
        if ($notificationContent -match "<body>(.*?)</body>") {
            $plainText = $matches[1] -replace "<[^>]+>", " " -replace "\s+", " "
        } else {
            $plainText = $notificationContent -replace "<[^>]+>", " " -replace "\s+", " "
        }
        
        $toastSuccess = Show-ToastNotification -Title $title -Message $plainText
        if ($toastSuccess) { $successCount++ }
    }
    
    # Send email notification if enabled and user email provided
    if ($script:NotificationConfig.EmailEnabled -and $UserEmail -and $script:NotificationConfig.SMTPServer -and $script:NotificationConfig.FromAddress) {
        $totalAttempts++
        
        try {
            $emailParams = @{
                SmtpServer = $script:NotificationConfig.SMTPServer
                From = $script:NotificationConfig.FromAddress
                To = $UserEmail
                Subject = "$($script:NotificationConfig.CompanyName) - $title"
                Body = $notificationContent
                BodyAsHtml = $true
                Priority = "High"
            }
            
            Send-MailMessage @emailParams
            $successCount++
            Write-Log -Message "Email notification sent to $($UserEmail): $title" -Level Information
        }
        catch {
            Write-Log -Message "Failed to send email notification: $_" -Level Error
        }
    }
    
    # Teams notification would be implemented here
    # Not included in this version
    
    return ($successCount -gt 0 -and $totalAttempts -gt 0)
}

<#
.SYNOPSIS
    Displays migration progress UI to the user.
    
.DESCRIPTION
    Shows migration progress with a visual progress bar and status messages
    using either a WPF window or silent mode for unattended migrations.
    
.PARAMETER PercentComplete
    Percentage of migration completed (0-100).
    
.PARAMETER StatusMessage
    Current status message to display to the user.
    
.PARAMETER Silent
    Run in silent mode, which sends notifications without UI. Default is $false.
    
.PARAMETER UserEmail
    The user's email address for notifications in silent mode.
    
.EXAMPLE
    Show-MigrationProgress -PercentComplete 50 -StatusMessage "Installing Intune client..."
    
.OUTPUTS
    None
#>
function Show-MigrationProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage,
        
        [Parameter(Mandatory = $false)]
        [switch]$Silent = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$UserEmail
    )
    
    # Log progress
    Write-Log -Message "Migration progress: $PercentComplete% - $StatusMessage" -Level Information
    
    if ($Silent) {
        # Send notification but no UI
        if ($PercentComplete -in @(25, 50, 75, 100)) {
            Send-MigrationNotification -Type "MigrationProgress" -UserEmail $UserEmail -Parameters @($PercentComplete, $StatusMessage)
        }
        return
    }
    
    # Note: In a full implementation, this would create a WPF progress window
    # For this version, we'll use a simplified approach with toast notifications
    
    # Only send toast at certain milestones to avoid notification spam
    if ($PercentComplete -in @(25, 50, 75, 100)) {
        Send-MigrationNotification -Type "MigrationProgress" -Parameters @($PercentComplete, $StatusMessage)
    }
    
    # Display console progress bar for interactive sessions
    if (-not [System.Environment]::UserInteractive) { return }
    
    Write-Progress -Activity "Migration to Azure/Intune" -Status $StatusMessage -PercentComplete $PercentComplete
}

<#
.SYNOPSIS
    Shows a user guide or documentation.
    
.DESCRIPTION
    Displays a specific guide to help users through the migration process
    or to troubleshoot common issues.
    
.PARAMETER GuideName
    The name of the guide to display.
    
.PARAMETER OutputPath
    Path to save the guide file. If not specified, opens in default browser.
    
.EXAMPLE
    Show-MigrationGuide -GuideName "PostMigrationSteps"
    
.OUTPUTS
    System.Boolean. Returns $true if guide was successfully displayed.
#>
function Show-MigrationGuide {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("WelcomeGuide", "PreMigrationSteps", "PostMigrationSteps", "TroubleshootingGuide")]
        [string]$GuideName,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )
    
    $guidePath = Join-Path -Path $script:GuidesPath -ChildPath "$GuideName.html"
    
    # Check if guide exists, if not create a placeholder
    if (-not (Test-Path -Path $guidePath)) {
        # Create guides directory if it doesn't exist
        $guidesDir = Split-Path -Path $guidePath -Parent
        if (-not (Test-Path -Path $guidesDir)) {
            New-Item -Path $guidesDir -ItemType Directory -Force | Out-Null
        }
        
        # Create basic guide content
        $guideContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>$GuideName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2, h3 { color: #0078D4; }
        .section { margin: 20px 0; padding: 10px; border-left: 5px solid #0078D4; background-color: #f8f8f8; }
    </style>
</head>
<body>
    <h1>$GuideName</h1>
    <div class="section">
        <h2>Guide Content</h2>
        <p>This is a placeholder for the $GuideName.</p>
        <p>Please contact support for assistance.</p>
    </div>
</body>
</html>
"@
        
        # Save the placeholder guide
        $guideContent | Out-File -FilePath $guidePath -Encoding utf8
    }
    
    try {
        if ($OutputPath) {
            # Save to specified location
            $targetPath = Join-Path -Path $OutputPath -ChildPath "$GuideName.html"
            Copy-Item -Path $guidePath -Destination $targetPath -Force
            Start-Process $targetPath
        } else {
            # Open in default browser
            Start-Process $guidePath
        }
        
        Write-Log -Message "Migration guide displayed: $GuideName" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to display migration guide: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Collects user feedback about the migration process.
    
.DESCRIPTION
    Displays a feedback form to the user and stores the responses
    for later analysis and improvement of the migration process.
    
.PARAMETER UserEmail
    The user's email address.
    
.PARAMETER Silent
    Operate in silent mode, which skips feedback collection.
    
.EXAMPLE
    Get-MigrationFeedback -UserEmail "user@contoso.com"
    
.OUTPUTS
    System.Boolean. Returns $true if feedback was collected successfully.
#>
function Get-MigrationFeedback {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$UserEmail,
        
        [Parameter(Mandatory = $false)]
        [switch]$Silent = $false
    )
    
    if ($Silent) {
        Write-Log -Message "Skipping feedback collection in silent mode" -Level Information
        return $true
    }
    
    try {
        # Create feedback directory if it doesn't exist
        if (-not (Test-Path -Path $script:FeedbackPath)) {
            New-Item -Path $script:FeedbackPath -ItemType Directory -Force | Out-Null
        }
        
        # In a full implementation, this would display a WPF or HTML form
        # For this version, we'll just create a placeholder for the feedback
        
        # Ask simple questions using Read-Host if in interactive mode
        if (-not [System.Environment]::UserInteractive) { return $false }
        
        $feedback = @{
            UserEmail = $UserEmail
            ComputerName = $env:COMPUTERNAME
            Timestamp = Get-Date
            Satisfaction = Read-Host "On a scale of 1-5 (5 being highest), how satisfied are you with the migration process?"
            Comments = Read-Host "Do you have any additional comments about the migration process?"
            Issues = Read-Host "Did you experience any issues during the migration? (Yes/No)"
        }
        
        if ($feedback.Issues -eq "Yes") {
            $feedback.IssueDetails = Read-Host "Please describe the issues you experienced"
        }
        
        # Save feedback to a JSON file
        $feedbackFile = Join-Path -Path $script:FeedbackPath -ChildPath "Feedback_$($env:USERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $feedback | ConvertTo-Json | Out-File -FilePath $feedbackFile -Encoding utf8
        
        Write-Log -Message "User feedback collected and saved to $feedbackFile" -Level Information
        
        # Send a notification thanking the user
        Send-MigrationNotification -Type "MigrationComplete" -UserEmail $UserEmail
        
        return $true
    }
    catch {
        Write-Log -Message "Failed to collect user feedback: $_" -Level Error
        return $false
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Set-NotificationConfig, Send-MigrationNotification, Show-MigrationProgress, Show-MigrationGuide, Get-MigrationFeedback 