# Application Data Migration Module

## Overview

The Application Data Migration module provides functionality to migrate user application-specific data and settings during the migration from Workspace ONE to Microsoft Intune. This module focuses on preserving the user experience by ensuring that personal settings, profiles, and data are seamlessly transferred during the migration process.

## Key Features

- **Outlook Profile Migration**: Preserves PST files, email signatures, templates, and account settings
- **Browser Data Transfer**: Migrates bookmarks, cookies, extensions, and saved passwords
- **Credential Management**: Transfers Windows credential vault items and manages passkeys
- **Comprehensive Backup**: Creates detailed backups before migration for rollback capability
- **Cross-User Migration**: Supports migrating settings between different user accounts

## Prerequisites

- Windows 10 (1809 or later) or Windows 11
- PowerShell 5.1 or later
- Required for some features:
  - CredentialManager PowerShell module (automatically installed if needed)
  - Microsoft Outlook must be installed for Outlook migration features

## Module Functions

### Initialize-ApplicationDataMigration

Sets up the Application Data Migration module and verifies prerequisites.

```powershell
Initialize-ApplicationDataMigration -BackupPath "C:\Temp\AppDataBackup"
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| BackupPath | String | Optional path where application data backups will be stored |

### Migrate-OutlookData

Migrates Outlook profiles, PST files, signatures, and other Outlook-related data.

```powershell
Migrate-OutlookData -Username "johndoe" -TargetUsername "johndoe.new" -BackupOnly
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Username | String | Source username whose Outlook data will be migrated |
| TargetUsername | String | Target username to migrate the data to |
| BackupOnly | Switch | If set, only creates a backup without performing migration |

### Migrate-BrowserData

Migrates browser settings including bookmarks, cookies, and passwords from Chrome, Edge, and Firefox.

```powershell
Migrate-BrowserData -Browsers @("Chrome", "Edge") -IncludePasswords
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Username | String | Source username whose browser data will be migrated |
| TargetUsername | String | Target username to migrate the data to |
| Browsers | String[] | List of browsers to process (Chrome, Edge, Firefox, or All) |
| IncludePasswords | Switch | Whether to include saved passwords in the migration |
| BackupOnly | Switch | If set, only creates a backup without performing migration |

### Migrate-CredentialVault

Backs up and migrates Windows credential vault items including passkeys.

```powershell
Migrate-CredentialVault -Username "johndoe"
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Username | String | Source username whose credentials will be migrated |
| TargetUsername | String | Target username to migrate the data to |
| BackupOnly | Switch | If set, only creates a backup without performing migration |

### Migrate-AllApplicationData

Provides a one-step function to migrate all supported application data types.

```powershell
Migrate-AllApplicationData -IncludeOutlook -IncludeBrowsers -IncludeCredentials
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| Username | String | Source username whose application data will be migrated |
| TargetUsername | String | Target username to migrate the data to |
| BackupOnly | Switch | If set, only creates a backup without performing migration |
| IncludeOutlook | Switch | Whether to include Outlook data in the migration |
| IncludeBrowsers | Switch | Whether to include browser data in the migration |
| IncludeCredentials | Switch | Whether to include credential vault items in the migration |
| IncludeBrowserPasswords | Switch | Whether to include browser passwords in the migration |

## Integration with Migration Process

The Application Data Migration module integrates with the migration process at several key points:

1. **Pre-Migration Assessment**: Identify which application data to migrate
2. **Pre-Migration Backup**: Create backups of all user application data
3. **Migration Execution**: Transfer application settings to the new profile
4. **Post-Migration Verification**: Verify that application data was successfully migrated
5. **Rollback (if needed)**: Restore application data from backups if issues occur

## Implementation Example

Here's how to use the module in your migration script:

```powershell
# Import the module
Import-Module .\src\modules\ApplicationDataMigration.psm1

# Initialize the module
Initialize-ApplicationDataMigration

# Migrate all application data
Migrate-AllApplicationData -Username $env:USERNAME -BackupOnly:$false -IncludeBrowserPasswords:$false

# Or migrate specific application data
Migrate-OutlookData -Username $env:USERNAME
Migrate-BrowserData -Browsers @("Chrome", "Edge")
Migrate-CredentialVault
```

## Data Structure

The module creates a structured backup of application data in the following format:

```
WS1Migration\AppDataBackup\
├── Username\
│   ├── Outlook\
│   │   ├── metadata.json
│   │   ├── Outlook_Settings.reg
│   │   ├── Outlook_Profiles.reg
│   │   ├── PST_Files\
│   │   │   └── [PST file metadata]
│   │   ├── Signatures\
│   │   │   └── [Signature files]
│   │   ├── Templates\
│   │   │   └── [Template files]
│   │   └── NK2\
│   │       └── [Autocomplete files]
│   ├── Browsers\
│   │   ├── metadata.json
│   │   ├── Chrome\
│   │   │   ├── Bookmarks
│   │   │   ├── Cookies
│   │   │   ├── Passwords (if included)
│   │   │   └── ExtensionsList.json
│   │   ├── Edge\
│   │   │   └── [Edge data]
│   │   └── Firefox\
│   │       └── [Firefox data]
│   └── Credentials\
│       ├── metadata.json
│       ├── GenericCredentials.xml
│       └── Passkeys.json
```

## Security Considerations

- Passwords and credentials are handled securely.
- Browser passwords backup is optional and disabled by default.
- Passkeys can't be directly extracted due to security protections in Windows; users must re-register passkeys after migration.
- All backed-up sensitive data is stored in a secure location with limited access.

## Limitations

- Browser data migration requires browsers to be closed.
- Some browser settings may require manual reconfiguration after migration.
- Extremely large PST files are not directly copied but their locations are preserved.
- Windows 11 passkeys cannot be directly migrated due to security design; the module records their existence to inform users of the need to re-register them.
- Outlook profile migration works best within the same machine or domain.

## Troubleshooting

If you encounter issues with application data migration:

1. Check the logs in the default location: `C:\Temp\Logs`
2. Verify that the user has appropriate permissions to read/write the data
3. Ensure that applications (Outlook, browsers) are closed during migration
4. For Outlook issues, verify that the correct version is detected
5. For browser issues, ensure the browser profile paths are correct for your environment 