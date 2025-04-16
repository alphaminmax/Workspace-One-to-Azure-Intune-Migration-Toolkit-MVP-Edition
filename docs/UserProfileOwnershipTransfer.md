# User Profile Ownership Transfer

## Overview

The User Profile Ownership Transfer module provides functionality to safely transfer ownership and permissions of user profiles between different users. This is a critical component of the Workspace ONE to Azure/Intune migration process, allowing user data to be preserved while transitioning between management systems.

## Key Features

- **Complete Profile ACL Management**: Comprehensive handling of file system Access Control Lists (ACLs) for all profile components
- **Registry Hive Ownership Transitions**: Secure transfer of registry hive ownership between accounts
- **Profile Backup & Restore**: Built-in backup capabilities to ensure data integrity
- **Verification Mechanisms**: Automated verification of successful ownership transfer
- **Error Handling**: Robust error handling for permission issues with detailed logging
- **Special Folder Handling**: Special treatment for critical user folders (Documents, Desktop, etc.)

## Module Functions

### Core Functions

#### Transfer-UserProfile

Transfers a user profile from one user to another, handling basic ownership and permissions.

```powershell
Transfer-UserProfile -SourceSID "S-1-5-21-1234567890-1234567890-1234567890-1001" `
                     -TargetSID "S-1-5-21-1234567890-1234567890-1234567890-1002" `
                     -CreateBackup
```

Parameters:
- `SourceSID`: The SID of the source user profile
- `TargetSID`: The SID of the target user profile
- `CreateBackup`: Whether to create a backup of the source profile

#### Complete-ProfileOwnershipTransfer

Performs a complete profile ownership transfer with enhanced handling for ACLs, registry, and verification.

```powershell
Complete-ProfileOwnershipTransfer -SourceSID "S-1-5-21-1234567890-1234567890-1234567890-1001" `
                                 -TargetSID "S-1-5-21-1234567890-1234567890-1234567890-1002" `
                                 -IncludeRegistry `
                                 -CreateBackup
```

Parameters:
- `SourceSID`: The SID of the source user profile
- `TargetSID`: The SID of the target user profile
- `CreateBackup`: Whether to create a backup of the source profile
- `IncludeRegistry`: Whether to include registry hive ownership transfer
- `Force`: Force the transfer even if verification fails

### Supporting Functions

#### Set-ProfileFolderAcl

Recursively processes ACLs for a user profile folder and its contents.

```powershell
Set-ProfileFolderAcl -FolderPath "C:\Users\john.doe" -TargetSID "S-1-5-21-..." -PreserveExistingPermissions
```

#### Transfer-RegistryHiveOwnership

Transfers ownership of user registry hives between accounts.

```powershell
Transfer-RegistryHiveOwnership -SourceSID "S-1-5-21-..." -TargetSID "S-1-5-21-..."
```

#### Test-OwnershipTransfer

Verifies that profile ownership has been successfully transferred.

```powershell
Test-OwnershipTransfer -ProfilePath "C:\Users\john.doe" -TargetSID "S-1-5-21-..."
```

#### Copy-UserRegistryHive

Copies registry settings from one user's hive to another.

```powershell
Copy-UserRegistryHive -SourceSID "S-1-5-21-..." -TargetSID "S-1-5-21-..." -KeyPaths @("Software\Microsoft\Office")
```

#### Restore-UserProfile

Restores a user profile from a backup.

```powershell
Restore-UserProfile -TargetSID "S-1-5-21-..." -BackupPath "C:\Users\john.doe.bak_20230101_120000"
```

### Utility Functions

#### Get-UserProfileSID

Gets a user's SID from their username or profile path.

```powershell
Get-UserProfileSID -Username "john.doe"
```

or

```powershell
Get-UserProfileSID -ProfilePath "C:\Users\john.doe"
```

#### Get-UserProfilePath

Gets a user's profile path from their SID or username.

```powershell
Get-UserProfilePath -SID "S-1-5-21-..."
```

or

```powershell
Get-UserProfilePath -Username "john.doe"
```

## Usage Examples

### Basic Profile Transfer

```powershell
# Import the module
Import-Module .\src\modules\ProfileTransfer.psm1

# Get source and target SIDs
$sourceSID = Get-UserProfileSID -Username "domain\old.user"
$targetSID = Get-UserProfileSID -Username "domain\new.user"

# Transfer profile
Transfer-UserProfile -SourceSID $sourceSID -TargetSID $targetSID -CreateBackup
```

### Complete Profile Transfer with Registry

```powershell
# Import the module
Import-Module .\src\modules\ProfileTransfer.psm1

# Get source and target SIDs
$sourceSID = Get-UserProfileSID -Username "domain\old.user"
$targetSID = Get-UserProfileSID -Username "domain\new.user"

# Perform complete transfer
$result = Complete-ProfileOwnershipTransfer -SourceSID $sourceSID -TargetSID $targetSID -IncludeRegistry -CreateBackup

# Check result
if ($result.Success) {
    Write-Host "Profile transfer completed successfully!"
} else {
    Write-Host "Profile transfer had issues:"
    foreach ($error in $result.Errors) {
        Write-Host "  - $error"
    }
}
```

### Verify Profile Transfer

```powershell
# Import the module
Import-Module .\src\modules\ProfileTransfer.psm1

# Get target SID
$targetSID = Get-UserProfileSID -Username "domain\new.user"
$profilePath = Get-UserProfilePath -SID $targetSID

# Test ownership
$verificationResult = Test-OwnershipTransfer -ProfilePath $profilePath -TargetSID $targetSID

# Display results
if ($verificationResult.Success) {
    Write-Host "Ownership verification successful!"
} else {
    Write-Host "Ownership verification failed:"
    foreach ($error in $verificationResult.Errors) {
        Write-Host "  - $error"
    }
}
```

## Best Practices

1. **Always Create Backups**: Enable the backup option when transferring profiles for the first time
2. **Verify Transfers**: Use the verification functions to confirm successful transfers
3. **Handle Locked Files**: Be aware that some files may be locked if users are logged in
4. **Registry Caution**: Registry transfers should be performed when the user is logged out if possible
5. **Administrative Rights**: All transfer operations require administrative privileges
6. **Security Context**: Run transfer operations in the SYSTEM context for best results
7. **Logging**: Review the detailed logs in case of issues

## Error Handling

The module implements comprehensive error handling:

- All major operations are wrapped in try/catch blocks
- Detailed error information is logged
- Operations continue with best-effort when possible
- Functions return detailed result objects with success status and error details
- Verification mechanisms confirm successful operations

## Integration with Other Modules

This module works closely with:

- **LoggingModule**: For detailed operation logging
- **SecurityFoundation**: For secure credential handling
- **PrivilegeManagement**: For elevation of privileges when needed
- **GraphAPIIntegration**: For connecting to Azure AD after profile transfer

## Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| Access Denied errors | Ensure script is running with administrative privileges |
| Cannot transfer registry | Make sure the user is logged out or use the Force parameter |
| Profile backup fails | Check disk space and permissions on the parent directory |
| Verification fails | Review detailed error messages and fix specific permissions |
| System files locked | Retry operation when system is less busy or after reboot |

## Advanced Scenarios

### Domain Migration

When migrating between domains, use the module to:

1. Identify old domain profile SID
2. Create new domain user account
3. Transfer profile ownership
4. Update registry references to old domain

### Multi-user Systems

For systems with multiple user profiles:

```powershell
# Get all user profiles
$profileList = Get-ChildItem -Path "C:\Users" | Where-Object { $_.PSIsContainer -and $_.Name -notin @("Public", "Default", "Default User") }

# Process each profile
foreach ($profile in $profileList) {
    $username = $profile.Name
    $sourceSID = Get-UserProfileSID -ProfilePath $profile.FullName
    
    # Determine target user (implementation specific)
    $targetUsername = "new\$username"
    $targetSID = Get-UserProfileSID -Username $targetUsername
    
    if ($sourceSID -and $targetSID) {
        # Transfer ownership
        Complete-ProfileOwnershipTransfer -SourceSID $sourceSID -TargetSID $targetSID -CreateBackup -IncludeRegistry
    }
}
``` 