# User Communication Framework

## Overview

The User Communication Framework module (`UserCommunicationFramework.psm1`) provides comprehensive user interaction functionality for the Workspace One to Azure/Intune migration process. This module is designed to keep users informed throughout the migration, collect feedback, and provide guidance.

## Key Features

- **Multi-channel Notifications**: Support for Windows toast notifications, email, and potential for Microsoft Teams integration
- **Migration Progress Display**: Visual and notification-based progress updates
- **User Guides**: HTML-based documentation for common migration scenarios
- **Feedback Collection**: Mechanisms to gather user input on migration experience

## Module Functions

### Set-NotificationConfig

Configures notification settings with company branding and notification channel preferences.

```powershell
Set-NotificationConfig -CompanyName "Contoso" -SupportEmail "help@contoso.com" -SupportPhone "555-123-4567" -EnableEmail $true -SMTPServer "smtp.contoso.com" -FromAddress "migration@contoso.com"
```

#### Parameters

- `CompanyName`: Organization name for branding
- `SupportEmail`: Contact email for support
- `SupportPhone`: Contact phone number for support
- `SMTPServer`: Email server for notifications
- `FromAddress`: Sender email address
- `EnableEmail`: Toggle email notifications ($true/$false)
- `EnableTeams`: Toggle Teams notifications ($true/$false)
- `EnableToast`: Toggle Windows toast notifications ($true/$false)
- `TemplatesPath`: Custom path for notification templates

### Send-MigrationNotification

Sends status notifications to users through configured channels.

```powershell
Send-MigrationNotification -Type "MigrationStart" -UserEmail "user@contoso.com"
```

#### Parameters

- `Type`: Notification type (MigrationStart, MigrationProgress, MigrationComplete, MigrationFailed, ActionRequired)
- `UserEmail`: Recipient email address
- `Parameters`: Additional parameters for template placeholders

### Show-MigrationProgress

Displays migration progress with visual indicators.

```powershell
Show-MigrationProgress -PercentComplete 50 -StatusMessage "Installing Intune client..."
```

#### Parameters

- `PercentComplete`: Progress percentage (0-100)
- `StatusMessage`: Current activity description
- `Silent`: Run without UI interaction ($true/$false)
- `UserEmail`: User email for notifications in silent mode

### Show-MigrationGuide

Presents HTML-based documentation to guide users.

```powershell
Show-MigrationGuide -GuideName "PostMigrationSteps"
```

#### Parameters

- `GuideName`: Specific guide to display (WelcomeGuide, PreMigrationSteps, PostMigrationSteps, TroubleshootingGuide)
- `OutputPath`: Optional path to save guide file

### Get-MigrationFeedback

Collects user feedback on the migration experience.

```powershell
Get-MigrationFeedback -UserEmail "user@contoso.com"
```

#### Parameters

- `UserEmail`: User's email address
- `Silent`: Skip feedback collection ($true/$false)

## Notification Templates

The module uses HTML-based templates for notifications, stored in the `templates\notifications` directory. Default templates include:

- MigrationStart.html
- MigrationProgress.html
- MigrationComplete.html
- MigrationFailed.html
- ActionRequired.html

## Integration

The User Communication Framework depends on the LoggingModule.psm1 module for activity logging and integrates with the overall migration workflow.

## Dependencies

- PowerShell 5.1+
- Windows 10/11 for toast notifications
- LoggingModule.psm1

## File Structure

```
/src/modules/
  ├── UserCommunicationFramework.psm1
  └── LoggingModule.psm1
/src/templates/
  ├── notifications/
  │   ├── MigrationStart.html
  │   ├── MigrationProgress.html
  │   ├── MigrationComplete.html
  │   ├── MigrationFailed.html
  │   └── ActionRequired.html
  └── guides/
      ├── WelcomeGuide.html
      ├── PreMigrationSteps.html
      ├── PostMigrationSteps.html
      └── TroubleshootingGuide.html
``` 