![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Lock Screen Guidance Module

## Overview

The Lock Screen Guidance module provides customized lock screen functionality during the Workspace ONE to Microsoft Intune migration process. It displays contextual information and guidance to users based on the current migration stage, helping to improve the user experience and reduce confusion during the migration process.

## Key Features

- **Stage-Aware Messaging**: Automatically updates lock screen content based on the current migration stage
- **Migration Progress Display**: Shows visual progress indicators during migration
- **Corporate Branding Integration**: Supports company logos and brand colors
- **User Action Guidance**: Provides clear instructions when user input is required
- **Error Notifications**: Clearly displays error information when issues occur
- **Seamless Integration**: Works with the broader migration process

## Prerequisites

- Windows 10/11 operating system
- PowerShell 5.1 or later
- Administrator privileges (required to modify the lock screen)
- LoggingModule.psm1 (for error tracking and logging)
- Optional: UserCommunicationFramework.psm1 (for additional notification capabilities)

## Module Functions

### Initialize-LockScreenGuidance

Sets up the Lock Screen Guidance module with company branding and configuration.

```powershell
Initialize-LockScreenGuidance -CompanyName "Contoso" -CompanyLogo "C:\Branding\logo.png" -PrimaryColor "#0078D4"
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Enabled | Boolean | Whether lock screen customization is enabled (default: $true) |
| CompanyName | String | The name of the company to display |
| CompanyLogo | String | Path to the company logo image file |
| PrimaryColor | String | The primary color to use in HTML format (e.g., #0078D4) |
| SecondaryColor | String | The secondary color to use in HTML format |
| RestoreOriginal | Boolean | Whether to restore the original lock screen when complete |
| TemplatesPath | String | Path to custom lock screen HTML templates |
| CustomImagePath | String | Path to store custom lock screen images |

### Update-MigrationLockScreen

Updates the lock screen to show migration stage information.

```powershell
Update-MigrationLockScreen -Stage "MigrationInProgress" -Parameters @(50, "Installing Intune client...")
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Stage | String | The current migration stage |
| Parameters | Array | Additional parameters for the lock screen template |

#### Available Stages

- **PreMigration**: Initial notification about upcoming migration
- **MigrationInProgress**: Shows during active migration with progress bar
- **UserAuthentication**: Prompts for user authentication with instructions
- **PostMigration**: Shows during final configuration steps
- **Completed**: Indicates successful migration completion
- **Error**: Displays when an error has occurred

### Set-LockScreenProgress

Sets a stage-specific lock screen with progress information.

```powershell
Set-LockScreenProgress -Stage "MigrationInProgress" -PercentComplete 75 -StatusMessage "Configuring policies..."
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Stage | String | The current migration stage |
| PercentComplete | Int | Percentage of the stage completed (0-100) |
| StatusMessage | String | Current status message to display |

### Show-LockScreenError

Shows an error message on the lock screen.

```powershell
Show-LockScreenError -ErrorMessage "Failed to connect to Intune service"
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| ErrorMessage | String | The error message to display |

### Show-AuthenticationPrompt

Prompts for user authentication on the lock screen.

```powershell
Show-AuthenticationPrompt -UserEmail "user@contoso.com"
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| UserEmail | String | The user's email address to display |

### Restore-OriginalLockScreen

Restores the original Windows lock screen.

```powershell
Restore-OriginalLockScreen -Force
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Force | Switch | Force restoration even if the module is disabled |

### Get-LockScreenConfig

Gets the current lock screen configuration.

```powershell
Get-LockScreenConfig
```

## Integration with Migration Process

The Lock Screen Guidance module integrates with the migration process at several key points:

1. **Before Migration**: Initialize the module at the start of the migration process
2. **During Preparation**: Display the PreMigration screen
3. **During Migration**: Update progress screens throughout the migration
4. **Authentication Required**: Display authentication prompt when user input is needed
5. **Migration Complete**: Show completion screen
6. **Error Handling**: Display error screen if issues occur
7. **Cleanup**: Restore original lock screen during cleanup

### Example Migration Integration

```powershell
# Initialize module at migration start
Initialize-LockScreenGuidance -CompanyName "Contoso" -CompanyLogo "C:\Branding\logo.png"

# Set initial screen
Update-MigrationLockScreen -Stage "PreMigration"

try {
    # Start migration
    # ...

    # Update progress
    Set-LockScreenProgress -Stage "MigrationInProgress" -PercentComplete 25 -StatusMessage "Removing Workspace ONE agent..."
    # ...

    # Prompt for authentication
    Show-AuthenticationPrompt -UserEmail "user@contoso.com"
    # ...

    # Update final progress
    Set-LockScreenProgress -Stage "PostMigration" -PercentComplete 90 -StatusMessage "Finalizing configuration..."
    # ...

    # Show completion
    Update-MigrationLockScreen -Stage "Completed"
}
catch {
    # Show error
    Show-LockScreenError -ErrorMessage $_.Exception.Message
}
finally {
    # Restore original lock screen
    Restore-OriginalLockScreen
}
```

## Customizing Templates

The module includes default HTML templates for each stage, but you can create custom templates for further personalization.

Create HTML files in the templates directory (`src/templates/lockscreen`) with the following naming convention:
- PreMigration.html
- MigrationInProgress.html
- UserAuthentication.html
- PostMigration.html
- Completed.html
- Error.html

### Template Parameters

Templates use formatting placeholders that are replaced at runtime:
- `{0}` - Company logo path
- Additional placeholders specific to each template type:
  - **MigrationInProgress/PostMigration**: `{1}` is the percentage complete, `{2}` is the status message
  - **UserAuthentication**: `{1}` is the user email address
  - **Error**: `{1}` is the error message

## Notes and Limitations

- Administrator privileges are required to modify the lock screen
- The module currently uses a simplified approach for rendering HTML content
- For optimal performance, keep HTML templates simple
- On Windows 10/11, changes to the lock screen may not appear immediately in some cases
- Restoring the original lock screen can sometimes require a system restart to take effect 
