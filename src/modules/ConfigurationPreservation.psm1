################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Module for preserving user configurations during Workspace One to Azure/Intune migration.                             #
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
    Module for preserving user configurations during Workspace One to Azure/Intune migration.
.DESCRIPTION
    The ConfigurationPreservation module provides functions to selectively export and import
    user configurations without directly copying the entire user profile. This includes application
    settings, registry keys, and special folder contents.
    
    This module is designed to operate alongside the ProfileTransfer module but can be used
    in scenarios where a full profile transfer is not possible or desirable.
    
    Unlike ProfileTransfer.psm1, this module can run without administrative privileges and
    is suitable for standard user migration scenarios.
.NOTES
    Part of the Workspace One to Azure/Intune Migration Toolkit
    
    Common usage scenarios:
    - Preserve user application settings
    - Migrate browser bookmarks and settings
    - Transfer Office application configurations
    - Maintain user preferences across migrations
#>

# Module variables
$script:LogPath = "C:\Temp\Logs\ConfigPreservation_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$script:BackupPath = "C:\Temp\UserConfigBackup"
$script:SpecialFolders = @{
    "Desktop" = [Environment]::GetFolderPath("Desktop")
    "Documents" = [Environment]::GetFolderPath("MyDocuments")
    "Downloads" = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
    "Pictures" = [Environment]::GetFolderPath("MyPictures")
    "Music" = [Environment]::GetFolderPath("MyMusic")
    "Videos" = [Environment]::GetFolderPath("MyVideos")
    "Favorites" = [Environment]::GetFolderPath("Favorites")
    "AppData" = [Environment]::GetFolderPath("ApplicationData")
    "LocalAppData" = [Environment]::GetFolderPath("LocalApplicationData")
}

# Registry paths to be migrated
$script:RegistryPaths = @(
    "HKCU:\Software\Microsoft\Office",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Internet Explorer\Main",
    "HKCU:\Software\Google\Chrome\PreferenceMACs",
    "HKCU:\Software\Microsoft\Edge",
    "HKCU:\Control Panel\Desktop",
    "HKCU:\Control Panel\International",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
    "HKCU:\Environment"
)

# Selective AppData folders to migrate (to avoid large cache directories)
$script:AppDataFolders = @(
    "Microsoft\Signatures",
    "Microsoft\Templates",
    "Microsoft\Outlook",
    "Microsoft\Internet Explorer\Quick Launch",
    "Google\Chrome\User Data\Default\Bookmarks",
    "Microsoft\Edge\User Data\Default\Bookmarks",
    "Mozilla\Firefox\Profiles"
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
        
        $logFile = Join-Path -Path $script:LogPath -ChildPath "ConfigPreservation.log"
        Add-Content -Path $logFile -Value $logMessage
    }
}

function Initialize-ConfigPreservation {
    <#
    .SYNOPSIS
        Initializes the configuration preservation module.
    .DESCRIPTION
        Sets up necessary paths and verifies prerequisites for configuration preservation operations.
    .PARAMETER BackupPath
        The path where user configuration backups will be stored.
    .EXAMPLE
        Initialize-ConfigPreservation -BackupPath "C:\Temp\UserConfigBackup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BackupPath = $script:BackupPath
    )
    
    Write-LogMessage -Message "Initializing Configuration Preservation module" -Level INFO
    
    # Update backup path if specified
    if ($BackupPath -ne $script:BackupPath) {
        $script:BackupPath = $BackupPath
        Write-LogMessage -Message "Backup path set to: $script:BackupPath" -Level INFO
    }
    
    # Ensure backup directory exists
    if (-not (Test-Path -Path $script:BackupPath)) {
        try {
            New-Item -Path $script:BackupPath -ItemType Directory -Force | Out-Null
            Write-LogMessage -Message "Created backup directory at $script:BackupPath" -Level INFO
        } catch {
            Write-LogMessage -Message "Failed to create backup directory: $_" -Level ERROR
            throw "Failed to create backup directory"
        }
    }
    
    # Verify special folders
    $invalidFolders = @()
    foreach ($folderName in $script:SpecialFolders.Keys) {
        $folderPath = $script:SpecialFolders[$folderName]
        if (-not (Test-Path -Path $folderPath)) {
            $invalidFolders += $folderName
            Write-LogMessage -Message "Special folder not found: $folderName at $folderPath" -Level WARNING
        }
    }
    
    if ($invalidFolders.Count -gt 0) {
        Write-LogMessage -Message "Some special folders could not be located: $($invalidFolders -join ', ')" -Level WARNING
    }
    
    Write-LogMessage -Message "Configuration Preservation module initialized successfully" -Level INFO
    return $true
}

function Export-UserConfiguration {
    <#
    .SYNOPSIS
        Exports user configuration settings to a backup location.
    .DESCRIPTION
        Selectively exports registry settings, application configurations, and special folder 
        contents for preservation during migration.
    .PARAMETER UserName
        The username whose configuration will be exported.
    .PARAMETER BackupPath
        The path where configuration will be backed up.
    .PARAMETER IncludeRegistryKeys
        Array of registry keys to include in the backup (defaults to predefined list).
    .PARAMETER IncludeAppDataFolders
        Array of AppData folders to include in the backup (defaults to predefined list).
    .PARAMETER IncludeSpecialFolders
        Array of special folders to include in the backup (defaults to predefined list).
    .EXAMPLE
        Export-UserConfiguration -UserName "john.doe" -BackupPath "C:\Temp\JohnConfig"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UserName = $env:USERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$BackupPath = $script:BackupPath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$IncludeRegistryKeys = $script:RegistryPaths,
        
        [Parameter(Mandatory = $false)]
        [string[]]$IncludeAppDataFolders = $script:AppDataFolders,
        
        [Parameter(Mandatory = $false)]
        [string[]]$IncludeSpecialFolders = $script:SpecialFolders.Keys
    )
    
    Write-LogMessage -Message "Starting configuration export for user: $UserName" -Level INFO
    
    # Create user-specific backup folder
    $userBackupPath = Join-Path -Path $BackupPath -ChildPath $UserName
    if (-not (Test-Path -Path $userBackupPath)) {
        New-Item -Path $userBackupPath -ItemType Directory -Force | Out-Null
    }
    
    # Export config metadata
    $configMetadata = @{
        ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        UserName = $UserName
        ComputerName = $env:COMPUTERNAME
        OSVersion = [System.Environment]::OSVersion.VersionString
        PSVersion = $PSVersionTable.PSVersion.ToString()
        RegistryKeys = $IncludeRegistryKeys
        AppDataFolders = $IncludeAppDataFolders
        SpecialFolders = $IncludeSpecialFolders
    }
    
    $metadataPath = Join-Path -Path $userBackupPath -ChildPath "ConfigMetadata.json"
    $configMetadata | ConvertTo-Json | Out-File -FilePath $metadataPath -Encoding UTF8
    Write-LogMessage -Message "Exported configuration metadata to: $metadataPath" -Level INFO
    
    # Export registry keys
    $registryBackupPath = Join-Path -Path $userBackupPath -ChildPath "Registry"
    if (-not (Test-Path -Path $registryBackupPath)) {
        New-Item -Path $registryBackupPath -ItemType Directory -Force | Out-Null
    }
    
    foreach ($regPath in $IncludeRegistryKeys) {
        $regName = ($regPath -replace "HKCU:\\", "") -replace "\\", "_"
        $regFile = Join-Path -Path $registryBackupPath -ChildPath "$regName.reg"
        
        try {
            # Use reg.exe to export which works even for non-admin users
            $regPathForExport = $regPath -replace "HKCU:\\", "HKCU\"
            
            # Run reg export command
            $regExportOutput = & reg.exe export $regPathForExport $regFile /y 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage -Message "Successfully exported registry key: $regPath to $regFile" -Level INFO
            } else {
                Write-LogMessage -Message "Failed to export registry key: $regPath. Error: $regExportOutput" -Level WARNING
            }
        } catch {
            Write-LogMessage -Message "Error exporting registry key: $regPath. $_" -Level ERROR
        }
    }
    
    # Export AppData folders
    $appDataBackupPath = Join-Path -Path $userBackupPath -ChildPath "AppData"
    if (-not (Test-Path -Path $appDataBackupPath)) {
        New-Item -Path $appDataBackupPath -ItemType Directory -Force | Out-Null
    }
    
    foreach ($folder in $IncludeAppDataFolders) {
        $sourcePath = Join-Path -Path ($script:SpecialFolders["AppData"]) -ChildPath $folder
        $targetPath = Join-Path -Path $appDataBackupPath -ChildPath $folder
        
        # Create parent directories if they don't exist
        $targetParent = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path -Path $targetParent)) {
            New-Item -Path $targetParent -ItemType Directory -Force | Out-Null
        }
        
        if (Test-Path -Path $sourcePath) {
            try {
                if ((Get-Item -Path $sourcePath) -is [System.IO.DirectoryInfo]) {
                    # It's a directory, so copy recursively
                    Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force -ErrorAction Stop
                    Write-LogMessage -Message "Copied AppData folder: $folder" -Level INFO
                } else {
                    # It's a file
                    Copy-Item -Path $sourcePath -Destination $targetPath -Force -ErrorAction Stop
                    Write-LogMessage -Message "Copied AppData file: $folder" -Level INFO
                }
            } catch {
                Write-LogMessage -Message "Error copying AppData item: $folder. $_" -Level ERROR
            }
        } else {
            Write-LogMessage -Message "AppData path not found: $sourcePath" -Level WARNING
        }
    }
    
    # Export special folders
    foreach ($folderName in $IncludeSpecialFolders) {
        # Skip AppData as it's handled separately with selective content
        if ($folderName -eq "AppData" -or $folderName -eq "LocalAppData") {
            continue
        }
        
        if (-not $script:SpecialFolders.ContainsKey($folderName)) {
            Write-LogMessage -Message "Unknown special folder: $folderName" -Level WARNING
            continue
        }
        
        $sourcePath = $script:SpecialFolders[$folderName]
        $targetPath = Join-Path -Path $userBackupPath -ChildPath $folderName
        
        if (Test-Path -Path $sourcePath) {
            try {
                # Create directory if it doesn't exist
                if (-not (Test-Path -Path $targetPath)) {
                    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                }
                
                # For Documents, Desktop, etc. - copy only if size is reasonable
                $folderSize = Get-ChildItem -Path $sourcePath -Recurse -File -ErrorAction SilentlyContinue | 
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                
                $sizeInMB = [Math]::Round(($folderSize.Sum / 1MB), 2)
                
                if ($sizeInMB -gt 500) {
                    Write-LogMessage -Message "Skipping $folderName folder (size: $sizeInMB MB exceeds reasonable limit)" -Level WARNING
                } else {
                    # Copy folder contents (but not the folder itself)
                    Get-ChildItem -Path $sourcePath | Copy-Item -Destination $targetPath -Recurse -Force -ErrorAction Stop
                    Write-LogMessage -Message "Copied $folderName folder (size: $sizeInMB MB)" -Level INFO
                }
            } catch {
                Write-LogMessage -Message "Error copying special folder $folderName. $_" -Level ERROR
            }
        } else {
            Write-LogMessage -Message "Special folder not found: $sourcePath" -Level WARNING
        }
    }
    
    # Create a summary file
    $summaryPath = Join-Path -Path $userBackupPath -ChildPath "ExportSummary.txt"
    $summaryContent = @"
Configuration Export Summary
===========================
Date: $(Get-Date)
User: $UserName
Computer: $env:COMPUTERNAME

Registry Keys Exported: $($IncludeRegistryKeys.Count)
AppData Folders Exported: $($IncludeAppDataFolders.Count)
Special Folders Exported: $($IncludeSpecialFolders.Count)

Export Location: $userBackupPath
"@
    
    $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-LogMessage -Message "Configuration export completed successfully for user: $UserName" -Level INFO
    
    return $userBackupPath
}

function Import-UserConfiguration {
    <#
    .SYNOPSIS
        Imports user configuration settings from a backup location.
    .DESCRIPTION
        Selectively imports registry settings, application configurations, and special folder 
        contents from a previous export.
    .PARAMETER UserName
        The username whose configuration will be imported.
    .PARAMETER BackupPath
        The path where configuration was backed up.
    .PARAMETER ImportRegistry
        Whether to import registry settings.
    .PARAMETER ImportAppData
        Whether to import AppData settings.
    .PARAMETER ImportSpecialFolders
        Whether to import special folder contents.
    .EXAMPLE
        Import-UserConfiguration -UserName "john.doe" -BackupPath "C:\Temp\JohnConfig"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UserName = $env:USERNAME,
        
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$ImportRegistry = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$ImportAppData = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$ImportSpecialFolders = $true
    )
    
    Write-LogMessage -Message "Starting configuration import for user: $UserName" -Level INFO
    
    # Verify backup path
    if (-not (Test-Path -Path $BackupPath)) {
        Write-LogMessage -Message "Backup path not found: $BackupPath" -Level ERROR
        throw "Backup path not found"
    }
    
    # Load metadata if available
    $metadataPath = Join-Path -Path $BackupPath -ChildPath "ConfigMetadata.json"
    $configMetadata = $null
    
    if (Test-Path -Path $metadataPath) {
        try {
            $configMetadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
            Write-LogMessage -Message "Loaded configuration metadata from: $metadataPath" -Level INFO
            Write-LogMessage -Message "Original export was for user: $($configMetadata.UserName) on $($configMetadata.ExportDate)" -Level INFO
        } catch {
            Write-LogMessage -Message "Error loading configuration metadata: $_" -Level WARNING
        }
    } else {
        Write-LogMessage -Message "Configuration metadata not found at: $metadataPath" -Level WARNING
    }
    
    # Import registry settings
    if ($ImportRegistry) {
        $registryBackupPath = Join-Path -Path $BackupPath -ChildPath "Registry"
        
        if (Test-Path -Path $registryBackupPath) {
            Write-LogMessage -Message "Importing registry settings from: $registryBackupPath" -Level INFO
            
            $regFiles = Get-ChildItem -Path $registryBackupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                try {
                    # Use reg.exe to import which works even for non-admin users
                    $regImportOutput = & reg.exe import $regFile.FullName 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage -Message "Successfully imported registry file: $($regFile.Name)" -Level INFO
                    } else {
                        Write-LogMessage -Message "Failed to import registry file: $($regFile.Name). Error: $regImportOutput" -Level WARNING
                    }
                } catch {
                    Write-LogMessage -Message "Error importing registry file: $($regFile.Name). $_" -Level ERROR
                }
            }
        } else {
            Write-LogMessage -Message "Registry backup path not found: $registryBackupPath" -Level WARNING
        }
    }
    
    # Import AppData folders
    if ($ImportAppData) {
        $appDataBackupPath = Join-Path -Path $BackupPath -ChildPath "AppData"
        
        if (Test-Path -Path $appDataBackupPath) {
            Write-LogMessage -Message "Importing AppData settings from: $appDataBackupPath" -Level INFO
            
            $appDataFolders = Get-ChildItem -Path $appDataBackupPath -Directory -Recurse
            foreach ($folder in $appDataFolders) {
                $relativePath = $folder.FullName.Substring($appDataBackupPath.Length + 1)
                $targetPath = Join-Path -Path ($script:SpecialFolders["AppData"]) -ChildPath $relativePath
                
                # Create target directory if it doesn't exist
                if (-not (Test-Path -Path $targetPath)) {
                    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                }
                
                # Copy files
                try {
                    Get-ChildItem -Path $folder.FullName -File | Copy-Item -Destination $targetPath -Force -ErrorAction Stop
                    Write-LogMessage -Message "Restored AppData files to: $relativePath" -Level INFO
                } catch {
                    Write-LogMessage -Message "Error restoring AppData files to: $relativePath. $_" -Level ERROR
                }
            }
            
            # Also copy any files at the root level
            $appDataRootFiles = Get-ChildItem -Path $appDataBackupPath -File
            foreach ($file in $appDataRootFiles) {
                $targetPath = Join-Path -Path ($script:SpecialFolders["AppData"]) -ChildPath $file.Name
                
                try {
                    Copy-Item -Path $file.FullName -Destination $targetPath -Force -ErrorAction Stop
                    Write-LogMessage -Message "Restored AppData root file: $($file.Name)" -Level INFO
                } catch {
                    Write-LogMessage -Message "Error restoring AppData root file: $($file.Name). $_" -Level ERROR
                }
            }
        } else {
            Write-LogMessage -Message "AppData backup path not found: $appDataBackupPath" -Level WARNING
        }
    }
    
    # Import special folders
    if ($ImportSpecialFolders) {
        Write-LogMessage -Message "Importing special folder contents" -Level INFO
        
        foreach ($folderName in $script:SpecialFolders.Keys) {
            # Skip AppData as it's handled separately with selective content
            if ($folderName -eq "AppData" -or $folderName -eq "LocalAppData") {
                continue
            }
            
            $sourcePath = Join-Path -Path $BackupPath -ChildPath $folderName
            $targetPath = $script:SpecialFolders[$folderName]
            
            if (Test-Path -Path $sourcePath) {
                try {
                    # Copy folder contents
                    Get-ChildItem -Path $sourcePath | Copy-Item -Destination $targetPath -Recurse -Force -ErrorAction Stop
                    Write-LogMessage -Message "Restored $folderName folder contents" -Level INFO
                } catch {
                    Write-LogMessage -Message "Error restoring $folderName folder contents. $_" -Level ERROR
                }
            } else {
                Write-LogMessage -Message "Special folder backup not found: $sourcePath" -Level WARNING
            }
        }
    }
    
    # Create a summary file
    $summaryPath = Join-Path -Path $BackupPath -ChildPath "ImportSummary.txt"
    $summaryContent = @"
Configuration Import Summary
===========================
Date: $(Get-Date)
User: $UserName
Computer: $env:COMPUTERNAME

Imported Registry: $ImportRegistry
Imported AppData: $ImportAppData
Imported Special Folders: $ImportSpecialFolders

Import Source: $BackupPath
"@
    
    $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-LogMessage -Message "Configuration import completed successfully for user: $UserName" -Level INFO
    
    return $true
}

function Get-ConfigurationBackupSummary {
    <#
    .SYNOPSIS
        Gets a summary of a user configuration backup.
    .DESCRIPTION
        Analyzes the content of a configuration backup and returns statistics and summary information.
    .PARAMETER BackupPath
        The path to the configuration backup.
    .EXAMPLE
        Get-ConfigurationBackupSummary -BackupPath "C:\Temp\UserConfigBackup\john.doe"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )
    
    Write-LogMessage -Message "Analyzing configuration backup at: $BackupPath" -Level INFO
    
    # Verify backup path
    if (-not (Test-Path -Path $BackupPath)) {
        Write-LogMessage -Message "Backup path not found: $BackupPath" -Level ERROR
        throw "Backup path not found"
    }
    
    # Initialize summary object
    $summary = @{
        BackupPath = $BackupPath
        CreationDate = $null
        ModificationDate = $null
        Size = 0
        HasRegistry = $false
        HasAppData = $false
        SpecialFolders = @()
        RegistryKeyCount = 0
        AppDataFolderCount = 0
        Metadata = $null
    }
    
    # Get backup folder information
    $backupFolder = Get-Item -Path $BackupPath
    $summary.CreationDate = $backupFolder.CreationTime
    $summary.ModificationDate = $backupFolder.LastWriteTime
    
    # Calculate total size
    $size = Get-ChildItem -Path $BackupPath -Recurse | Measure-Object -Property Length -Sum
    $summary.Size = [Math]::Round(($size.Sum / 1MB), 2)
    
    # Load metadata if available
    $metadataPath = Join-Path -Path $BackupPath -ChildPath "ConfigMetadata.json"
    if (Test-Path -Path $metadataPath) {
        try {
            $summary.Metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
        } catch {
            Write-LogMessage -Message "Error loading configuration metadata: $_" -Level WARNING
        }
    }
    
    # Check for registry backup
    $registryPath = Join-Path -Path $BackupPath -ChildPath "Registry"
    if (Test-Path -Path $registryPath) {
        $summary.HasRegistry = $true
        $regFiles = Get-ChildItem -Path $registryPath -Filter "*.reg"
        $summary.RegistryKeyCount = $regFiles.Count
    }
    
    # Check for AppData backup
    $appDataPath = Join-Path -Path $BackupPath -ChildPath "AppData"
    if (Test-Path -Path $appDataPath) {
        $summary.HasAppData = $true
        $appDataFolders = Get-ChildItem -Path $appDataPath -Directory -Recurse
        $summary.AppDataFolderCount = $appDataFolders.Count
    }
    
    # Check for special folders
    foreach ($folderName in $script:SpecialFolders.Keys) {
        if ($folderName -eq "AppData" -or $folderName -eq "LocalAppData") {
            continue
        }
        
        $folderPath = Join-Path -Path $BackupPath -ChildPath $folderName
        if (Test-Path -Path $folderPath) {
            $summary.SpecialFolders += $folderName
        }
    }
    
    Write-LogMessage -Message "Backup summary analysis completed" -Level INFO
    return $summary
}

# Initialize the module
Initialize-ConfigPreservation

# Export the module members
Export-ModuleMember -Function Export-UserConfiguration, Import-UserConfiguration, Get-ConfigurationBackupSummary, Initialize-ConfigPreservation 




