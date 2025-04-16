# Email Notification System

## Overview

The Email Notification System enables the migration toolkit to communicate effectively with users through email. 
Built into the UserCommunicationFramework module, it provides standardized email notifications
about migration status, alerts, and next steps.

## Key Features

- **Simple Interface**: Easy-to-use functions for sending emails
- **Template-based**: Configurable email templates for consistent messaging
- **Integration with Migration Status**: Automatic emails based on migration progress
- **Customizable Branding**: Organization-specific branding in email content
- **Recipient Management**: Supports both user-specific and admin notifications
- **Configurable SMTP Settings**: Flexible configuration for different email environments

## Core Functions

### Send-EmailNotification

The primary function for sending email notifications to users.

```powershell
Send-EmailNotification -EmailAddress "user@contoso.com" -Subject "Migration Complete" -Body "Your device has been successfully migrated"
```

**Parameters:**
- `EmailAddress` - The recipient's email address (optional if using Azure AD lookup)
- `Subject` - The email subject line
- `Body` - The email content (can be plain text or HTML)

### Configuration

Email settings are stored in the configuration and can include:

```json
{
  "EmailSettings": {
    "SMTPServer": "smtp.contoso.com",
    "Port": 587,
    "UseTLS": true,
    "From": "migration@contoso.com",
    "DefaultRecipients": ["itadmin@contoso.com"],
    "UseCredentials": true
  }
}
```

## Integration with Migration Workflow

The email notification system integrates with various migration stages:

1. **Pre-Migration Notification**: Informs users about upcoming migration
2. **Status Updates**: Provides progress updates during migration
3. **Completion Notification**: Confirms successful migration with next steps
4. **Failure Alerts**: Notifies users and admins about migration failures
5. **Follow-up Communication**: Sends post-migration surveys and documentation

## Customization

Email templates can be customized by modifying the HTML templates in the `src/templates/` directory:

- `PreMigration.html` - Template for pre-migration notifications
- `MigrationInProgress.html` - Template for status updates
- `MigrationComplete.html` - Template for completion notifications
- `MigrationFailed.html` - Template for failure notifications

## Implementation Details

The email system is implemented in `UserCommunicationFramework.psm1` and uses either:

1. PowerShell's `Send-MailMessage` cmdlet for simple deployments
2. Microsoft Graph API for Microsoft 365 environments
3. Custom SMTP implementation for specialized requirements

For production environments, credentials are securely managed through Azure Key Vault integration.

## Logging

All email operations are logged through the central logging system:

```
[2025-04-16 12:34:56] [INFO] Email notification sent to user@contoso.com with subject 'Migration Complete'
```

## See Also

- [User Communication Framework](UserCommunicationFramework.md)
- [Migration Progress Monitoring](Migration-Progress-Monitoring.md)
- [Enhanced Reporting](Enhanced-Reporting.md) 