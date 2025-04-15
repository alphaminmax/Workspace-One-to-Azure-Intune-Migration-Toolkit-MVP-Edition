################################################################################################################################
# Written by Jared Griego | Crayon | 4.15.2025 | Rev 1.0 |jared.griego@crayon.com                                          #
#                                                                                                                              #
# Azure PowerShell Script to allow migration from Workspace One to Azure Intune via Auto-enrollment                            #
# PowerShell 5.1 x32/x64                                                                                                       #
#                                                                                                                              #
################################################################################################################################

################################################################################################################################
#     ______ .______          ___   ____    ____  ______   .__   __.     __    __       _______.     ___                       #
#    /      ||   _  \        /   \  \   \  /   / /  __  \  |  \ |  |    |  |  |  |     /       |    /   \                      #
#   |  ,----'|  |_)  |      /  ^  \  \   \/   / |  |  |  | |   \|  |    |  |  |  |    |   (----`   /  ^  \                     #
#   |  |     |      /      /  /_\  \  \_    _/  |  |  |  | |  . `  |    |  |  |  |     \   \      /  /_\  \                    #
#   |  `----.|  |\  \----./  _____  \   |  |    |  `--'  | |  |\   |    |  `--'  | .----)   |    /  _____  \                   #
#    \______|| _| `._____/__/     \__\  |__|     \______/  |__| \__|     \______/  |_______/    /__/     \__\                  #
#                                                                                                                              #
################################################################################################################################

<#
.SYNOPSIS
    Module for handling user profile migration during Workspace One to Azure/Intune migration.
.DESCRIPTION
    The ProfileTransfer module provides functions to transfer user profiles between management
    systems, handling SID mapping, permissions, registry settings, and special folders.
    
    This module is used after the PrivilegeManagement module to ensure profile data is 
    preserved during the migration process from Workspace One to Azure/Intune.
    
    After profile transfer is complete, proceed with executing the MS Graph API module
    for connecting to and registering with Azure AD.
.NOTES
    Part of the Workspace One to Azure/Intune Migration Toolkit
    
    Common usage scenarios:
    - Transfer user profiles between domains or local accounts
    - Preserve user data during migration
    - Copy registry settings between profile hives
    - Restore profiles from backups if issues occur
#>

# Module variables
$script:LogPath = "C:\Temp\Logs\ProfileTransfer_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$script:ProfilesPath = "C:\Users"
$script:RegistryUserHive = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$script:SpecialFolders = @(
    "Desktop",
    "Documents",
    "Downloads",
    "Pictures",
    "Music",
    "Videos",
    "Favorites",
    "AppData"
)

# Import logging module if available
$loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath "LoggingModule.psm1"
if (Test-Path -Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
    # Initialize logging if not already initialized
    if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        Initialize-Logging -LogPath $script:LogPath -Level INFO
    }
} else {
    # Create a basic logging function if module not available
    function Write-LogMessage {
        param (
            [string]$Message,
            [string]$Level = "INFO"
        )
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Write to console
        switch ($Level) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            default { Write-Host $logMessage }
        }
        
        # Write to log file
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        
        $logFile = Join-Path -Path $script:LogPath -ChildPath "ProfileTransfer.log"
        Add-Content -Path $logFile -Value $logMessage
    }
}

function Initialize-ProfileTransfer {
    <#
    .SYNOPSIS
        Initializes the profile transfer module.
    .DESCRIPTION
        Sets up necessary variables and verifies prerequisites for profile transfer operations.
    .EXAMPLE
        Initialize-ProfileTransfer
    #>
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "Initializing Profile Transfer module" -Level INFO
    
    # Check if running with administrative privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage -Message "Profile transfer operations require administrative privileges" -Level WARNING
    }
    
    # Check if user profiles directory exists
    if (-not (Test-Path -Path $script:ProfilesPath)) {
        Write-LogMessage -Message "User profiles directory not found at $script:ProfilesPath" -Level ERROR
        throw "User profiles directory not found"
    }
    
    # Check if registry profile list exists
    if (-not (Test-Path -Path $script:RegistryUserHive)) {
        Write-LogMessage -Message "Registry profile list not found at $script:RegistryUserHive" -Level ERROR
        throw "Registry profile list not found"
    }
    
    Write-LogMessage -Message "Profile Transfer module initialized successfully" -Level INFO
}

function Get-UserProfileSID {
    <#
    .SYNOPSIS
        Gets a user's SID from their username or profile path.
    .DESCRIPTION
        Retrieves the Security Identifier (SID) for a user based on their username or profile path.
    .PARAMETER Username
        The username to look up.
    .PARAMETER ProfilePath
        The profile path to look up.
    .EXAMPLE
        Get-UserProfileSID -Username "john.doe"
    .EXAMPLE
        Get-UserProfileSID -ProfilePath "C:\Users\john.doe"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Username')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Username')]
        [string]$Username,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'ProfilePath')]
        [string]$ProfilePath
    )
    
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Username') {
            Write-LogMessage -Message "Looking up SID for username: $Username" -Level INFO
            
            # Try to get SID from local account first
            try {
                $objUser = New-Object System.Security.Principal.NTAccount($Username)
                $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier]).Value
                Write-LogMessage -Message "Found SID for local user ${Username}: ${strSID}" -Level INFO
                return $strSID
            } catch {
                Write-LogMessage -Message "Could not find local account for $Username, checking registry" -Level WARNING
            }
            
            # Check registry if local account lookup failed
            $profiles = Get-ChildItem -Path $script:RegistryUserHive
            
            foreach ($profile in $profiles) {
                $profileProperties = Get-ItemProperty -Path $profile.PSPath
                
                if ($profileProperties.ProfileImagePath -like "*\$Username") {
                    $sid = Split-Path -Leaf $profile.PSPath
                    Write-LogMessage -Message "Found SID in registry for ${Username}: ${sid}" -Level INFO
                    return $sid
                }
            }
            
            Write-LogMessage -Message "Could not find SID for username: $Username" -Level ERROR
            return $null
        } else {
            Write-LogMessage -Message "Looking up SID for profile path: $ProfilePath" -Level INFO
            
            $profiles = Get-ChildItem -Path $script:RegistryUserHive
            
            foreach ($profile in $profiles) {
                $profileProperties = Get-ItemProperty -Path $profile.PSPath
                
                if ($profileProperties.ProfileImagePath -eq $ProfilePath) {
                    $sid = Split-Path -Leaf $profile.PSPath
                    Write-LogMessage -Message "Found SID for profile path ${ProfilePath}: ${sid}" -Level INFO
                    return $sid
                }
            }
            
            # If not found, try to extract username from path and look up by username
            $username = Split-Path -Leaf $ProfilePath
            if ($username) {
                return Get-UserProfileSID -Username $username
            }
            
            Write-LogMessage -Message "Could not find SID for profile path: $ProfilePath" -Level ERROR
            return $null
        }
    } catch {
        Write-LogMessage -Message "Error looking up SID: $_" -Level ERROR
        return $null
    }
}

function Get-UserProfilePath {
    <#
    .SYNOPSIS
        Gets a user's profile path from their SID or username.
    .DESCRIPTION
        Retrieves the profile path for a user based on their SID or username.
    .PARAMETER SID
        The SID to look up.
    .PARAMETER Username
        The username to look up.
    .EXAMPLE
        Get-UserProfilePath -SID "S-1-5-21-1234567890-1234567890-1234567890-1001"
    .EXAMPLE
        Get-UserProfilePath -Username "john.doe"
    #>
    [CmdletBinding(DefaultParameterSetName = 'SID')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SID')]
        [string]$SID,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Username')]
        [string]$Username
    )
    
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Username') {
            $SID = Get-UserProfileSID -Username $Username
            if (-not $SID) {
                return $null
            }
        }
        
        Write-LogMessage -Message "Looking up profile path for SID: $SID" -Level INFO
        
        $profileKey = Join-Path -Path $script:RegistryUserHive -ChildPath $SID
        if (Test-Path -Path $profileKey) {
            $profileProperties = Get-ItemProperty -Path $profileKey
            $profilePath = $profileProperties.ProfileImagePath
            
            if ($profilePath -and (Test-Path -Path $profilePath)) {
                Write-LogMessage -Message "Found profile path for SID ${SID}: ${profilePath}" -Level INFO
                return $profilePath
            } else {
                Write-LogMessage -Message "Profile path for SID $SID does not exist: $profilePath" -Level WARNING
                return $null
            }
        } else {
            Write-LogMessage -Message "Could not find registry key for SID: $SID" -Level ERROR
            return $null
        }
    } catch {
        Write-LogMessage -Message "Error looking up profile path: $_" -Level ERROR
        return $null
    }
}

function Transfer-UserProfile {
    <#
    .SYNOPSIS
        Transfers a user profile from one user to another.
    .DESCRIPTION
        Transfers ownership and permissions of a user profile from one user to another,
        preserving all data and settings.
    .PARAMETER SourceSID
        The SID of the source user profile.
    .PARAMETER TargetSID
        The SID of the target user profile.
    .PARAMETER CreateBackup
        Whether to create a backup of the source profile before transfer.
    .EXAMPLE
        Transfer-UserProfile -SourceSID "S-1-5-21-..." -TargetSID "S-1-5-21-..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceSID,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetSID,
        
        [Parameter()]
        [switch]$CreateBackup = $false
    )
    
    Write-LogMessage -Message "Starting user profile transfer from $SourceSID to $TargetSID" -Level INFO
    
    # Check if running with administrative privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage -Message "Profile transfer requires administrative privileges" -Level ERROR
        throw "Administrative privileges required for profile transfer"
    }
    
    # Get profile paths
    $sourceProfilePath = Get-UserProfilePath -SID $SourceSID
    if (-not $sourceProfilePath) {
        Write-LogMessage -Message "Source profile not found for SID: $SourceSID" -Level ERROR
        throw "Source profile not found"
    }
    
    $targetProfilePath = Get-UserProfilePath -SID $TargetSID
    if (-not $targetProfilePath) {
        Write-LogMessage -Message "Target profile not found for SID: $TargetSID" -Level ERROR
        throw "Target profile not found"
    }
    
    Write-LogMessage -Message "Source profile path: $sourceProfilePath" -Level INFO
    Write-LogMessage -Message "Target profile path: $targetProfilePath" -Level INFO
    
    # Create backup if requested
    if ($CreateBackup) {
        $backupPath = "$sourceProfilePath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-LogMessage -Message "Creating backup of source profile at: $backupPath" -Level INFO
        
        try {
            Copy-Item -Path $sourceProfilePath -Destination $backupPath -Recurse -Force
            Write-LogMessage -Message "Backup created successfully" -Level INFO
        } catch {
            Write-LogMessage -Message "Failed to create backup: $_" -Level ERROR
            throw "Failed to create profile backup"
        }
    }
    
    # Transfer ownership and permissions
    try {
        # Get security principal for target user
        $targetAccount = New-Object System.Security.Principal.SecurityIdentifier($TargetSID)
        $targetNTAccount = $targetAccount.Translate([System.Security.Principal.NTAccount])
        
        Write-LogMessage -Message "Transferring ownership to: $($targetNTAccount.Value)" -Level INFO
        
        # Get ACL of source profile
        $sourceDirACL = Get-Acl -Path $sourceProfilePath
        
        # Set owner to target user
        $sourceDirACL.SetOwner($targetAccount)
        Set-Acl -Path $sourceProfilePath -AclObject $sourceDirACL
        
        # Add full control permission for target user
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $targetAccount,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        
        $sourceDirACL.AddAccessRule($accessRule)
        Set-Acl -Path $sourceProfilePath -AclObject $sourceDirACL
        
        Write-LogMessage -Message "Ownership and permissions transferred successfully" -Level INFO
        
        # Transfer special folders
        foreach ($folder in $script:SpecialFolders) {
            $sourceFolderPath = Join-Path -Path $sourceProfilePath -ChildPath $folder
            if (Test-Path -Path $sourceFolderPath) {
                Write-LogMessage -Message "Transferring permissions for special folder: $folder" -Level INFO
                
                $folderACL = Get-Acl -Path $sourceFolderPath
                $folderACL.SetOwner($targetAccount)
                Set-Acl -Path $sourceFolderPath -AclObject $folderACL
                
                $folderACL.AddAccessRule($accessRule)
                Set-Acl -Path $sourceFolderPath -AclObject $folderACL
            }
        }
        
        Write-LogMessage -Message "Special folders permissions transferred successfully" -Level INFO
        
        return $true
    } catch {
        Write-LogMessage -Message "Failed to transfer profile ownership: $_" -Level ERROR
        throw "Failed to transfer profile ownership and permissions"
    }
}

function Copy-UserRegistryHive {
    <#
    .SYNOPSIS
        Copies registry settings from one user's hive to another.
    .DESCRIPTION
        Transfers specific registry keys and values from one user's hive to another.
    .PARAMETER SourceSID
        The SID of the source user.
    .PARAMETER TargetSID
        The SID of the target user.
    .PARAMETER KeyPaths
        Array of registry key paths to copy (relative to HKCU).
    .EXAMPLE
        Copy-UserRegistryHive -SourceSID "S-1-5-21-..." -TargetSID "S-1-5-21-..." -KeyPaths @("Software\Microsoft\Office")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceSID,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetSID,
        
        [Parameter()]
        [string[]]$KeyPaths = @(
            "Software\Microsoft\Office",
            "Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
            "Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders",
            "Software\Microsoft\Windows\CurrentVersion\Run",
            "Control Panel\Desktop",
            "Environment"
        )
    )
    
    Write-LogMessage -Message "Starting registry hive transfer from $SourceSID to $TargetSID" -Level INFO
    
    try {
        # Load source user hive
        $sourceHivePath = "HKLM\TEMP_SOURCE_HIVE"
        $sourcePath = Join-Path -Path (Get-UserProfilePath -SID $SourceSID) -ChildPath "NTUSER.DAT"
        
        if (-not (Test-Path -Path $sourcePath)) {
            Write-LogMessage -Message "Source user hive not found at: $sourcePath" -Level ERROR
            throw "Source user hive not found"
        }
        
        Write-LogMessage -Message "Loading source user hive from: $sourcePath" -Level INFO
        $result = Start-Process -FilePath "reg.exe" -ArgumentList "load `"HKLM\TEMP_SOURCE_HIVE`" `"$sourcePath`"" -NoNewWindow -Wait -PassThru
        if ($result.ExitCode -ne 0) {
            Write-LogMessage -Message "Failed to load source hive. Exit code: $($result.ExitCode)" -Level ERROR
            throw "Failed to load source user hive"
        }
        
        # Load target user hive
        $targetHivePath = "HKLM\TEMP_TARGET_HIVE"
        $targetPath = Join-Path -Path (Get-UserProfilePath -SID $TargetSID) -ChildPath "NTUSER.DAT"
        
        if (-not (Test-Path -Path $targetPath)) {
            Write-LogMessage -Message "Target user hive not found at: $targetPath" -Level ERROR
            
            # Unload source hive
            Start-Process -FilePath "reg.exe" -ArgumentList "unload `"HKLM\TEMP_SOURCE_HIVE`"" -NoNewWindow -Wait
            
            throw "Target user hive not found"
        }
        
        Write-LogMessage -Message "Loading target user hive from: $targetPath" -Level INFO
        $result = Start-Process -FilePath "reg.exe" -ArgumentList "load `"HKLM\TEMP_TARGET_HIVE`" `"$targetPath`"" -NoNewWindow -Wait -PassThru
        if ($result.ExitCode -ne 0) {
            Write-LogMessage -Message "Failed to load target hive. Exit code: $($result.ExitCode)" -Level ERROR
            
            # Unload source hive
            Start-Process -FilePath "reg.exe" -ArgumentList "unload `"HKLM\TEMP_SOURCE_HIVE`"" -NoNewWindow -Wait
            
            throw "Failed to load target user hive"
        }
        
        # Copy registry keys
        foreach ($keyPath in $KeyPaths) {
            $sourceKey = "HKLM\TEMP_SOURCE_HIVE\$keyPath"
            $targetKey = "HKLM\TEMP_TARGET_HIVE\$keyPath"
            
            Write-LogMessage -Message "Copying registry key: $keyPath" -Level INFO
            
            if (Test-Path -Path "Registry::$sourceKey") {
                # Ensure target key parent path exists
                $targetParent = Split-Path -Parent $targetKey
                if (-not (Test-Path -Path "Registry::$targetParent")) {
                    New-Item -Path "Registry::$targetParent" -Force | Out-Null
                }
                
                # Copy key
                $result = Start-Process -FilePath "reg.exe" -ArgumentList "copy `"$sourceKey`" `"$targetKey`" /s /f" -NoNewWindow -Wait -PassThru
                if ($result.ExitCode -ne 0) {
                    Write-LogMessage -Message "Failed to copy registry key $keyPath. Exit code: $($result.ExitCode)" -Level WARNING
                }
            } else {
                Write-LogMessage -Message "Source registry key not found: $keyPath" -Level WARNING
            }
        }
        
        Write-LogMessage -Message "Registry hive transfer completed" -Level INFO
        
        return $true
    } catch {
        Write-LogMessage -Message "Error transferring registry hive: $_" -Level ERROR
        return $false
    } finally {
        # Unload hives
        Write-LogMessage -Message "Unloading registry hives" -Level INFO
        
        Start-Process -FilePath "reg.exe" -ArgumentList "unload `"HKLM\TEMP_SOURCE_HIVE`"" -NoNewWindow -Wait
        Start-Process -FilePath "reg.exe" -ArgumentList "unload `"HKLM\TEMP_TARGET_HIVE`"" -NoNewWindow -Wait
    }
}

function Restore-UserProfile {
    <#
    .SYNOPSIS
        Restores a user profile from backup.
    .DESCRIPTION
        Restores a user profile from a backup created during Transfer-UserProfile.
    .PARAMETER TargetSID
        The SID of the target profile to restore.
    .PARAMETER BackupPath
        Optional path to the backup. If not specified, will look for the latest backup.
    .EXAMPLE
        Restore-UserProfile -TargetSID "S-1-5-21-..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetSID,
        
        [Parameter()]
        [string]$BackupPath = ""
    )
    
    Write-LogMessage -Message "Starting user profile restoration for $TargetSID" -Level INFO
    
    # Check if running with administrative privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage -Message "Profile restoration requires administrative privileges" -Level ERROR
        throw "Administrative privileges required for profile restoration"
    }
    
    # Get target profile path
    $targetProfilePath = Get-UserProfilePath -SID $TargetSID
    if (-not $targetProfilePath) {
        Write-LogMessage -Message "Target profile not found for SID: $TargetSID" -Level ERROR
        throw "Target profile not found"
    }
    
    # Find backup if not specified
    if (-not $BackupPath) {
        Write-LogMessage -Message "Looking for latest backup of profile: $targetProfilePath" -Level INFO
        
        $backupPattern = "$targetProfilePath.bak_*"
        $backups = Get-ChildItem -Path (Split-Path -Parent $targetProfilePath) -Directory | Where-Object { $_.FullName -like $backupPattern } | Sort-Object LastWriteTime -Descending
        
        if ($backups -and $backups.Count -gt 0) {
            $BackupPath = $backups[0].FullName
            Write-LogMessage -Message "Found backup at: $BackupPath" -Level INFO
        } else {
            Write-LogMessage -Message "No backup found for profile: $targetProfilePath" -Level ERROR
            throw "No backup found for profile"
        }
    }
    
    # Verify backup exists
    if (-not (Test-Path -Path $BackupPath)) {
        Write-LogMessage -Message "Backup not found at: $BackupPath" -Level ERROR
        throw "Backup not found"
    }
    
    # Restore profile
    try {
        # Rename current profile to temporary name
        $tempPath = "$targetProfilePath.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-LogMessage -Message "Renaming current profile to: $tempPath" -Level INFO
        
        Rename-Item -Path $targetProfilePath -NewName (Split-Path -Leaf $tempPath) -Force
        
        # Copy backup to profile location
        Write-LogMessage -Message "Restoring backup to: $targetProfilePath" -Level INFO
        
        Copy-Item -Path $BackupPath -Destination $targetProfilePath -Recurse -Force
        
        # Transfer ownership back to target user
        Write-LogMessage -Message "Transferring ownership back to target user" -Level INFO
        
        $targetAccount = New-Object System.Security.Principal.SecurityIdentifier($TargetSID)
        $targetNTAccount = $targetAccount.Translate([System.Security.Principal.NTAccount])
        
        $dirACL = Get-Acl -Path $targetProfilePath
        $dirACL.SetOwner($targetAccount)
        Set-Acl -Path $targetProfilePath -AclObject $dirACL
        
        # Add full control permission for target user
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $targetAccount,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        
        $dirACL.AddAccessRule($accessRule)
        Set-Acl -Path $targetProfilePath -AclObject $dirACL
        
        Write-LogMessage -Message "Profile restored successfully" -Level INFO
        
        # Cleanup temporary profile
        Write-LogMessage -Message "Removing temporary profile: $tempPath" -Level INFO
        Remove-Item -Path $tempPath -Recurse -Force
        
        return $true
    } catch {
        Write-LogMessage -Message "Failed to restore profile: $_" -Level ERROR
        
        # Try to roll back if possible
        if (Test-Path -Path $tempPath) {
            Write-LogMessage -Message "Attempting to roll back profile restoration" -Level WARNING
            
            if (Test-Path -Path $targetProfilePath) {
                Remove-Item -Path $targetProfilePath -Recurse -Force
            }
            
            Rename-Item -Path $tempPath -NewName (Split-Path -Leaf $targetProfilePath) -Force
        }
        
        throw "Failed to restore user profile"
    }
}

# Initialize the module
Initialize-ProfileTransfer

# Export the module members
Export-ModuleMember -Function Get-UserProfileSID, Get-UserProfilePath, Transfer-UserProfile, Copy-UserRegistryHive, Restore-UserProfile 