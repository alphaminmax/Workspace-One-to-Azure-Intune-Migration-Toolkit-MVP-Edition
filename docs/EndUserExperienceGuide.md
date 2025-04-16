![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# End User Experience Guide: WS1 to Azure/Intune Migration

## 1. Overview

This guide details the end user experience during the migration from VMware Workspace ONE to Microsoft Azure/Intune. It provides a walkthrough of what users will experience, how to configure the experience as an administrator, and how to troubleshoot common user-facing issues during migration.

## 2. End User Journey Overview

The migration process is designed to be minimally disruptive to end users while keeping them informed throughout the process. The typical user journey includes:

1. **Pre-Migration Notification**: Users receive advance notice about the upcoming migration
2. **Day of Migration**: Users are guided through the migration process
3. **Migration Progress**: Visual indicators show migration status
4. **Completion**: Users are notified of successful migration
5. **Post-Migration Support**: Resources for getting help with the new environment

## 3. User Communication Framework

### 3.1 Communication Channels

The toolkit supports multiple communication channels to ensure users are well-informed:

| Channel | Purpose | Timing |
|---------|---------|--------|
| Email | Detailed information and instructions | 3 days before, day of, and after migration |
| Toast Notifications | Brief alerts and status updates | Day of migration |
| Lock Screen | Progress indicators and critical messages | During migration |
| Calendar Invites | Schedule the migration window | Optional, 3-7 days before |

### 3.2 Notification Configuration

Administrators can configure all aspects of user notifications:

```powershell
# Configure user notifications
Import-Module "C:\MigrationToolkit\src\modules\UserCommunicationFramework.psm1"

$notificationParams = @{
    CompanyName = "Contoso Ltd"
    NotificationEmail = "migration-support@contoso.com"
    SupportContact = "IT Help Desk (x1234)"
    EnableEmailNotifications = $true
    EnableToastNotifications = $true
    EnableCalendarInvites = $true
    NotificationSchedule = @{
        PreMigration = 72  # Hours before migration
        Reminder = 24      # Hours before migration
        PostMigration = 2   # Hours after completion
    }
    BrandingLogoPath = "C:\MigrationToolkit\assets\company_logo.png"
}

Set-NotificationConfig @notificationParams
```

## 4. Detailed User Experience Walkthrough

### 4.1 Pre-Migration (3 Days Before)

#### What the User Sees:

1. **Email Notification**:
   - Subject: "Important: Your device will be migrated to Microsoft Intune"
   - Content includes:
     - Migration date and time window
     - Brief explanation of the migration benefits
     - Preparation instructions (save work, ensure device is charged)
     - FAQ section addressing common concerns
     - Support contact information

2. **Calendar Invite** (Optional):
   - Calendar block for the migration window
   - Reminder set for 1 hour before migration
   - Description includes key information from the email

#### Administrator Configuration:

```powershell
# Send pre-migration notifications
$preNotifyParams = @{
    UserEmail = "user@contoso.com"
    MigrationDate = (Get-Date).AddDays(3)
    MigrationWindow = "6:00 PM - 9:00 PM"
    AddToCalendar = $true
    IncludePreparationSteps = $true
    IncludeFAQ = $true
}

Send-MigrationNotification -Stage "PreMigration" @preNotifyParams
```

### 4.2 Migration Day Reminder (4 Hours Before)

#### What the User Sees:

1. **Toast Notification**:
   - "Reminder: Your device migration begins at [TIME]"
   - "Please save all work and keep your device connected to power and network"

2. **Email Reminder**:
   - Brief reminder about the upcoming migration
   - Instructions for last-minute preparation
   - Option to reschedule if available

#### Administrator Configuration:

```powershell
# Send day-of reminder
$reminderParams = @{
    UserEmail = "user@contoso.com"
    MigrationStartTime = (Get-Date).AddHours(4)
    AllowReschedule = $false  # Set to true if rescheduling is an option
}

Send-MigrationNotification -Stage "Reminder" @reminderParams
```

### 4.3 Migration Start

#### What the User Sees:

1. **Toast Notification**:
   - "Migration to Microsoft Intune is starting now"
   - "Your device may restart several times during this process"
   - "Estimated completion time: [TIME]"

2. **Option Dialog** (if enabled):
   - "Would you like to start migration now or defer for [X] hours?"
   - Buttons: "Start now" or "Defer for [X] hours"

3. **Lock Screen Update**:
   - Company logo and branding
   - "Migration in progress"
   - "Please do not turn off your computer"

#### Administrator Configuration:

```powershell
# Configure migration start experience
Import-Module "C:\MigrationToolkit\src\modules\LockScreenGuidance.psm1"

# Allow deferral option (optional)
$deferralOptions = @{
    AllowDeferral = $true
    MaxDeferralHours = 4
    MaxDeferralCount = 2
}

# Start migration process for user
Start-UserMigration -UserName "user@contoso.com" -DeferralOptions $deferralOptions

# Update lock screen
Update-MigrationLockScreen -Stage "Starting" -EstimatedMinutesRemaining 60
```

### 4.4 Migration In Progress

#### What the User Sees:

1. **Lock Screen Progress**:
   - Progress bar showing completion percentage
   - Current stage (e.g., "Backing up data", "Installing new management agent")
   - Estimated time remaining
   - Company branding and messaging

2. During restarts, users see:
   - "Please do not turn off your computer"
   - "Restart [X] of [Y] in progress"

#### Administrator Configuration:

```powershell
# Update migration progress on lock screen
$migrationStages = @(
    @{ Name = "Backup"; Description = "Backing up your data and settings..." },
    @{ Name = "Uninstalling"; Description = "Removing previous management software..." },
    @{ Name = "Installing"; Description = "Installing Microsoft Intune management..." },
    @{ Name = "Configuring"; Description = "Configuring your device..." },
    @{ Name = "Finalizing"; Description = "Finalizing migration..." }
)

foreach ($index in 0..($migrationStages.Count-1)) {
    $stage = $migrationStages[$index]
    $percentComplete = [math]::Round((($index + 1) / $migrationStages.Count) * 100)
    $remaining = 60 - (($index + 1) / $migrationStages.Count * 60)
    
    # Update lock screen with current stage and progress
    Set-LockScreenProgress -Stage $stage.Name -Description $stage.Description `
                          -PercentComplete $percentComplete `
                          -EstimatedMinutesRemaining $remaining
}
```

### 4.5 Migration Complete

#### What the User Sees:

1. **Lock Screen Completion**:
   - "Migration Complete!"
   - "Your device is now managed by Microsoft Intune"
   - "You may log in to continue"

2. **Toast Notification** (after login):
   - "Migration to Microsoft Intune completed successfully"
   - "New features available! Click to learn more"

3. **Email**:
   - Confirmation of successful migration
   - Overview of new features and capabilities
   - Resources for learning about the new environment
   - Support contact information

#### Administrator Configuration:

```powershell
# Complete migration and restore normal experience
Import-Module "C:\MigrationToolkit\src\modules\LockScreenGuidance.psm1"

# Update lock screen with completion message
Update-MigrationLockScreen -Stage "Complete"

# Restore original lock screen when user logs in
Register-LogonScript -ScriptBlock {
    Restore-OriginalLockScreen
    
    # Show toast notification about completion
    Show-MigrationToast -Title "Migration Complete" `
                       -Message "Your device has been successfully migrated to Microsoft Intune" `
                       -ActionButton "Learn More" `
                       -ActionLink "https://contoso.com/intune-guide"
}

# Send completion email
Send-MigrationNotification -Stage "PostMigration" -IncludeNewFeaturesList $true
```

### 4.6 Post-Migration Feedback

#### What the User Sees:

1. **Feedback Request** (24 hours after completion):
   - Email or toast notification asking for feedback
   - Link to brief survey about the migration experience
   - Option to report any issues encountered

2. **Feedback Form**:
   - Rating scale for migration experience
   - Open text field for comments
   - Checkbox list of potential issues encountered
   - Option to be contacted by IT support

#### Administrator Configuration:

```powershell
# Request and configure feedback collection
$feedbackParams = @{
    UserEmail = "user@contoso.com"
    DelayHours = 24
    IncludeSatisfactionRating = $true
    IncludeCommentField = $true
    IncludeIssueReporting = $true
    OfferSupportContact = $true
}

Send-FeedbackRequest @feedbackParams

# Process received feedback
$feedbackResults = Get-MigrationFeedback -Since (Get-Date).AddDays(-7)
foreach ($feedback in $feedbackResults) {
    # Create tickets for reported issues
    if ($feedback.ReportedIssues -and $feedback.RequestSupport) {
        New-SupportTicket -UserEmail $feedback.UserEmail `
                         -Description $feedback.Comments `
                         -IssueType $feedback.ReportedIssues `
                         -Priority "Medium"
    }
}
```

## 5. Customizing the User Experience

### 5.1 Company Branding

All visual elements can be customized with company branding:

```powershell
# Set company branding
$brandingParams = @{
    CompanyName = "Contoso Ltd"
    PrimaryColor = "#0078D4"
    SecondaryColor = "#FFFFFF"
    LogoPath = "C:\MigrationToolkit\assets\company_logo.png"
    BackgroundImagePath = "C:\MigrationToolkit\assets\background.jpg"
}

Set-MigrationBranding @brandingParams
```

### 5.2 Message Customization

Customize the text and messaging throughout the migration:

```powershell
# Customize messages
$messageParams = @{
    WelcomeMessage = "Contoso is upgrading your device management to enhance security"
    CompletionMessage = "Your device is now secured with Microsoft Intune"
    SupportMessage = "Need help? Contact the IT Help Desk at x1234"
}

Set-MigrationMessages @messageParams

# Advanced: Customize all templates
$templates = Get-ChildItem -Path "C:\MigrationToolkit\templates" -Filter "*.html"
foreach ($template in $templates) {
    $content = Get-Content -Path $template.FullName -Raw
    $content = $content.Replace('{{DEFAULT_COMPANY_NAME}}', 'Contoso Ltd')
    $content = $content.Replace('{{DEFAULT_SUPPORT_CONTACT}}', 'IT Help Desk (x1234)')
    Set-Content -Path $template.FullName -Value $content
}
```

## 6. Troubleshooting User Experience Issues

### 6.1 User Receiving No Notifications

**Possible Causes:**
- Email delivery issues
- Toast notification permissions
- User profile issues
- Incorrect email address

**Resolution Steps:**
```powershell
# Verify and fix notification delivery
Import-Module "C:\MigrationToolkit\src\modules\UserCommunicationFramework.psm1"

# Check notification configuration
$config = Get-NotificationConfig

# Test direct toast notification
if ($config.EnableToastNotifications) {
    Test-ToastNotification -UserSID (Get-UserSID -Username "user@contoso.com")
}

# Test email delivery
if ($config.EnableEmailNotifications) {
    Test-EmailDelivery -ToAddress "user@contoso.com"
}

# Update notification settings if needed
Set-NotificationConfig -EnableToastNotifications $true -EnableEmailNotifications $true
```

### 6.2 Lock Screen Not Showing Migration Status

**Possible Causes:**
- Group Policy restrictions
- Permission issues
- Failed lock screen customization
- Windows lock screen service issues

**Resolution Steps:**
```powershell
# Diagnose and fix lock screen issues
Import-Module "C:\MigrationToolkit\src\modules\LockScreenGuidance.psm1"

# Check lock screen configuration
$lockScreenConfig = Get-LockScreenConfig

# Test lock screen update capability
Test-LockScreenPermissions

# Check for Group Policy restrictions
$personalizationKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (Test-Path $personalizationKey) {
    $lockScreenPolicy = Get-ItemProperty -Path $personalizationKey -ErrorAction SilentlyContinue
    
    # If Group Policy blocks customization, use alternative approach
    if ($lockScreenPolicy.LockScreenOverlaysDisabled -eq 1) {
        # Use alternative notification method
        Enable-AlternativeLockScreenNotification
    }
}

# Repair lock screen service if needed
Repair-LockScreenService
```

### 6.3 User Unable to Defer Migration

**Possible Causes:**
- Deferral not enabled in configuration
- User already deferred maximum number of times
- Critical migration that cannot be deferred
- Dialog not appearing correctly

**Resolution Steps:**
```powershell
# Check and fix deferral issues
Import-Module "C:\MigrationToolkit\src\modules\MigrationEngine.psm1"

# Check deferral configuration
$migrationConfig = Get-MigrationConfig
$deferralHistory = Get-UserDeferralHistory -UserName "user@contoso.com"

# Show current deferral status
Write-Output "Deferral enabled: $($migrationConfig.AllowDeferral)"
Write-Output "Max deferrals: $($migrationConfig.MaxDeferralCount)"
Write-Output "User deferrals used: $($deferralHistory.Count)"

# Reset deferral count if needed
if ($deferralHistory.Count -ge $migrationConfig.MaxDeferralCount) {
    Reset-UserDeferralCount -UserName "user@contoso.com"
    Write-Output "User deferral count has been reset"
}

# Force enable deferral for a specific user
Set-UserDeferralOption -UserName "user@contoso.com" -AllowDeferral $true -MaxDeferralHours 4
```

## 7. Best Practices for User Experience

### 7.1 User Communication Timeline

| Timing | Communication | Channel | Purpose |
|--------|---------------|---------|---------|
| 1-2 weeks before | Initial announcement | Email + Intranet | Create awareness |
| 3 days before | Detailed instructions | Email + Calendar | Prepare users |
| 1 day before | Reminder | Email + Toast | Final preparation |
| 4 hours before | Final reminder | Toast | Immediate preparation |
| Start of migration | Notification | Toast + Lock screen | Inform of start |
| During migration | Progress updates | Lock screen | Keep users informed |
| Completion | Success notification | Lock screen + Toast + Email | Confirm completion |
| 1 day after | Feedback request | Email + Toast | Collect feedback |
| 1 week after | Follow-up | Email | Address any issues |

### 7.2 Reducing User Disruption

1. **Schedule appropriately:**
   - Target off-hours or lower activity periods
   - Consider time zones for global deployments
   - Avoid business-critical periods

2. **Provide options:**
   - Allow reasonable deferrals when possible
   - Offer alternative devices during migration if critical
   - Create escalation path for urgent situations

3. **Set clear expectations:**
   - Provide accurate time estimates
   - Explain what will and won't change
   - Detail any actions required before/after

4. **Mitigate anxiety:**
   - Assure users that data will be preserved
   - Provide FAQ addressing common concerns
   - Offer multiple support channels

## 8. Administrative Controls and Reports

### 8.1 User Experience Dashboard

Administrators can monitor the end user experience across the organization:

```powershell
# Generate user experience report
$report = New-UserExperienceReport -LastDays 7

# Key metrics
Write-Output "Notifications sent: $($report.NotificationsSent)"
Write-Output "Average satisfaction rating: $($report.AverageSatisfaction)"
Write-Output "Users reporting issues: $($report.UsersReportingIssues)"
Write-Output "Average migration duration: $($report.AverageMigrationDuration) minutes"

# Export detailed report
$report.DetailedResults | Export-Csv -Path "C:\MigrationToolkit\reports\user_experience.csv" -NoTypeInformation
```

### 8.2 User Experience Controls

Control the user experience across your organization:

```powershell
# Update organization-wide user experience settings
$orgSettings = @{
    AllowDeferral = $true
    MaxDeferralHours = 12
    ShowProgressBar = $true
    ShowEstimatedTime = $true
    FeedbackEnabled = $true
    NotifyCompletion = $true
}

Set-OrganizationExperienceSettings @orgSettings

# Apply custom settings for specific groups
Set-GroupExperienceSettings -GroupName "Executives" -AllowDeferral $true -MaxDeferralHours 48
Set-GroupExperienceSettings -GroupName "Field Staff" -AfterHoursOnly $true
```

## 9. References and Resources

### 9.1 User Communication Templates

All templates are located at:
- `C:\MigrationToolkit\templates\`

Key templates include:
- `email_pre_migration.html` - Initial notification email
- `email_reminder.html` - Reminder email
- `email_completion.html` - Completion notification
- `toast_notification.xml` - Toast notification templates
- `lockscreen_templates.json` - Lock screen layouts and messaging

### 9.2 Customization Reference

Refer to the following resources for advanced customization:
- Company branding guide: `docs/BrandingGuide.md`
- Message customization: `docs/MessageCustomization.md`
- Advanced template editing: `docs/TemplateReference.md`

### 9.3 Sample Scripts

For common user experience tasks:
- Bulk notification sender: `scripts/Send-BulkNotifications.ps1`
- Custom feedback collector: `scripts/Export-UserFeedback.ps1`
- User experience tester: `scripts/Test-UserExperience.ps1` 
