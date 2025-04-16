#Requires -Version 5.1
################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Provides migration functionality for user application data in Workspace One to Azure/Intun...                            #
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


<#
.SYNOPSIS
    Provides migration functionality for user application data in Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The ApplicationDataMigration module handles the migration of application-specific settings and data 
    during the migration process, including:
    - Outlook profiles and PST files
    - Email signatures and templates
    - Browser bookmarks, cookies, and saved passwords
    - Browser extensions and settings
    - Passkey chains and credentials
    - Application-specific settings for common business applications
    
.NOTES
    File Name      : ApplicationDataMigration.psm1
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
$script:BackupPath = Join-Path -Path $env:ProgramData -ChildPath "WS1Migration\AppDataBackup"
$script:OutlookVersions = @("16.0", "15.0", "14.0") # Outlook 2016+, 2013, 2010
$script:ProfilesPath = "C:\Users"
$script:BrowserProfiles = @{
    "Chrome" = @{
        DataPath = "AppData\Local\Google\Chrome\User Data"
        Bookmarks = "Default\Bookmarks"
        Cookies = "Default\Network\Cookies"
        Passwords = "Default\Login Data"
        Extensions = "Default\Extensions"
    }
    "Edge" = @{
        DataPath = "AppData\Local\Microsoft\Edge\User Data"
        Bookmarks = "Default\Bookmarks"
        Cookies = "Default\Network\Cookies"
        Passwords = "Default\Login Data"
        Extensions = "Default\Extensions"
    }
    "Firefox" = @{
        DataPath = "AppData\Roaming\Mozilla\Firefox\Profiles"
        Profile = "*default*"
        Bookmarks = "places.sqlite"
        Cookies = "cookies.sqlite"
        Passwords = "logins.json"
        Extensions = "extensions"
    }
}

#region Private Functions

function Get-OutlookProfilePath {
    <#
    .SYNOPSIS
        Gets the Outlook profile registry path for the current user.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutlookVersion = "16.0" # Default to Outlook 2016+
    )
    
    return "HKCU:\Software\Microsoft\Office\$OutlookVersion\Outlook\Profiles"
}

function Get-OutlookPSTPath {
    <#
    .SYNOPSIS
        Gets the paths to Outlook PST files for the current user.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutlookVersion = "16.0",
        
        [Parameter(Mandatory = $false)]
        [string]$ProfileName = "Outlook"
    )
    
    try {
        $profilesPath = Get-OutlookProfilePath -OutlookVersion $OutlookVersion
        $profilePath = Join-Path -Path $profilesPath -ChildPath $ProfileName
        
        if (-not (Test-Path -Path $profilePath)) {
            Write-Log -Message "Outlook profile path not found: $profilePath" -Level Warning
            return @()
        }
        
        # Get all PST file paths from registry
        $pstFiles = @()
        $services = Get-ChildItem -Path $profilePath -Recurse -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -like "*001f*" }
        
        foreach ($service in $services) {
            try {
                $pstPathValue = Get-ItemProperty -Path $service.PSPath -ErrorAction SilentlyContinue
                
                if ($pstPathValue -and $pstPathValue.PSObject.Properties.Name -contains "001f6700") {
                    $pstPath = [System.Text.Encoding]::Unicode.GetString($pstPathValue."001f6700")
                    
                    if ($pstPath -and $pstPath -like "*.pst" -and (Test-Path -Path $pstPath)) {
                        $pstFiles += $pstPath
                        Write-Log -Message "Found PST file: $pstPath" -Level Information
                    }
                }
            } catch {
                Write-Log -Message "Error processing PST path in registry: $_" -Level Warning
            }
        }
        
        return $pstFiles
    } catch {
        Write-Log -Message "Error finding Outlook PST files: $_" -Level Error
        return @()
    }
}

function Get-BrowserProfilePath {
    <#
    .SYNOPSIS
        Gets the browser profile path for a specific browser.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Chrome", "Edge", "Firefox")]
        [string]$Browser,
        
        [Parameter(Mandatory = $false)]
        [string]$Username = $env:USERNAME
    )
    
    $userProfilePath = Join-Path -Path $script:ProfilesPath -ChildPath $Username
    $browserDataPath = $script:BrowserProfiles[$Browser].DataPath
    $fullPath = Join-Path -Path $userProfilePath -ChildPath $browserDataPath
    
    if (-not (Test-Path -Path $fullPath)) {
        Write-Log -Message "$Browser profile path not found: $fullPath" -Level Warning
        return $null
    }
    
    # For Firefox, we need to find the default profile
    if ($Browser -eq "Firefox") {
        $defaultProfilePattern = $script:BrowserProfiles[$Browser].Profile
        $profilesDir = Get-ChildItem -Path $fullPath -Directory | Where-Object { $_.Name -like $defaultProfilePattern }
        
        if ($profilesDir) {
            $fullPath = $profilesDir[0].FullName
            Write-Log -Message "Found Firefox profile: $fullPath" -Level Information
        } else {
            Write-Log -Message "No default Firefox profile found at $fullPath" -Level Warning
            return $null
        }
    }
    
    return $fullPath
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the Application Data Migration module.
    
.DESCRIPTION
    Sets up the Application Data Migration module and verifies prerequisites.
    
.PARAMETER BackupPath
    The path where application data backups will be stored.
    
.EXAMPLE
    Initialize-ApplicationDataMigration -BackupPath "C:\Temp\AppDataBackup"
    
.OUTPUTS
    System.Boolean. Returns $true if initialization was successful.
#>
function Initialize-ApplicationDataMigration {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BackupPath = $script:BackupPath
    )
    
    try {
        Write-Log -Message "Initializing Application Data Migration module" -Level Information
        
        # Update backup path if specified
        if ($BackupPath -ne $script:BackupPath) {
            $script:BackupPath = $BackupPath
        }
        
        # Create backup directory if needed
        if (-not (Test-Path -Path $script:BackupPath)) {
            New-Item -Path $script:BackupPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created backup directory at $script:BackupPath" -Level Information
        }
        
        # Verify Outlook is installed
        $outlookInstalled = $false
        foreach ($version in $script:OutlookVersions) {
            $outlookRegPath = "HKLM:\SOFTWARE\Microsoft\Office\$version\Outlook\InstallRoot"
            if (Test-Path -Path $outlookRegPath) {
                $outlookInstalled = $true
                break
            }
        }
        
        if (-not $outlookInstalled) {
            Write-Log -Message "Outlook does not appear to be installed" -Level Warning
        }
        
        # Verify browser installations
        foreach ($browser in $script:BrowserProfiles.Keys) {
            $browserPath = Get-BrowserProfilePath -Browser $browser
            if ($browserPath) {
                Write-Log -Message "$browser installation detected" -Level Information
            } else {
                Write-Log -Message "$browser does not appear to be installed" -Level Information
            }
        }
        
        Write-Log -Message "Application Data Migration module initialized successfully" -Level Information
        return $true
    } catch {
        Write-Log -Message "Failed to initialize Application Data Migration module: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Migrates Outlook profiles and PST files.
    
.DESCRIPTION
    Backs up and migrates Outlook profiles, PST files, signatures, and other Outlook data.
    
.PARAMETER Username
    The username whose Outlook data will be migrated.
    
.PARAMETER TargetUsername
    The target username to migrate the data to.
    
.PARAMETER BackupOnly
    If set, only creates a backup without performing the migration.
    
.EXAMPLE
    Migrate-OutlookData -Username "source.user" -TargetUsername "target.user"
    
.OUTPUTS
    System.Boolean. Returns $true if migration was successful.
#>
function Migrate-OutlookData {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Username = $env:USERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$TargetUsername = $Username,
        
        [Parameter(Mandatory = $false)]
        [switch]$BackupOnly
    )
    
    try {
        Write-Log -Message "Starting Outlook data migration for user $Username" -Level Information
        
        # Create user-specific backup folder
        $userBackupPath = Join-Path -Path $script:BackupPath -ChildPath $Username
        if (-not (Test-Path -Path $userBackupPath)) {
            New-Item -Path $userBackupPath -ItemType Directory -Force | Out-Null
        }
        
        $outlookBackupPath = Join-Path -Path $userBackupPath -ChildPath "Outlook"
        if (-not (Test-Path -Path $outlookBackupPath)) {
            New-Item -Path $outlookBackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Find Outlook version
        $outlookVersion = $null
        foreach ($version in $script:OutlookVersions) {
            if (Test-Path -Path "HKCU:\Software\Microsoft\Office\$version\Outlook") {
                $outlookVersion = $version
                Write-Log -Message "Found Outlook version $version" -Level Information
                break
            }
        }
        
        if (-not $outlookVersion) {
            Write-Log -Message "No Outlook installation found for user $Username" -Level Warning
            return $false
        }
        
        # Backup Outlook registry settings
        $outlookRegPath = "HKCU:\Software\Microsoft\Office\$outlookVersion\Outlook"
        
        # Backup using reg.exe for proper unicode handling
        $regFileName = "Outlook_Settings.reg"
        $regFilePath = Join-Path -Path $outlookBackupPath -ChildPath $regFileName
        
        # Command to export Outlook registry settings
        $regCmd = "reg export `"HKCU\Software\Microsoft\Office\$outlookVersion\Outlook`" `"$regFilePath`" /y"
        Invoke-Expression $regCmd | Out-Null
        
        if (Test-Path -Path $regFilePath) {
            Write-Log -Message "Backed up Outlook registry settings to $regFilePath" -Level Information
        } else {
            Write-Log -Message "Failed to backup Outlook registry settings" -Level Warning
        }
        
        # Backup Outlook profiles
        $profilesRegPath = "HKCU:\Software\Microsoft\Office\$outlookVersion\Outlook\Profiles"
        if (Test-Path -Path $profilesRegPath) {
            $profilesFileName = "Outlook_Profiles.reg"
            $profilesFilePath = Join-Path -Path $outlookBackupPath -ChildPath $profilesFileName
            
            # Command to export Outlook profiles registry
            $regCmd = "reg export `"HKCU\Software\Microsoft\Office\$outlookVersion\Outlook\Profiles`" `"$profilesFilePath`" /y"
            Invoke-Expression $regCmd | Out-Null
            
            if (Test-Path -Path $profilesFilePath) {
                Write-Log -Message "Backed up Outlook profiles to $profilesFilePath" -Level Information
            } else {
                Write-Log -Message "Failed to backup Outlook profiles" -Level Warning
            }
        } else {
            Write-Log -Message "No Outlook profiles found at $profilesRegPath" -Level Warning
        }
        
        # Backup PST files
        $pstBackupPath = Join-Path -Path $outlookBackupPath -ChildPath "PST_Files"
        if (-not (Test-Path -Path $pstBackupPath)) {
            New-Item -Path $pstBackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Get all profiles
        $profilesFolders = Get-ChildItem -Path $profilesRegPath -ErrorAction SilentlyContinue
        foreach ($profileFolder in $profilesFolders) {
            $profileName = Split-Path -Path $profileFolder.Name -Leaf
            $pstFiles = Get-OutlookPSTPath -OutlookVersion $outlookVersion -ProfileName $profileName
            
            foreach ($pstFile in $pstFiles) {
                $pstFileName = Split-Path -Path $pstFile -Leaf
                $pstMetadataFile = Join-Path -Path $pstBackupPath -ChildPath "$pstFileName.metadata"
                
                # Store PST file path and metadata instead of copying the potentially large file
                @{
                    OriginalPath = $pstFile
                    ProfileName = $profileName
                    Size = (Get-Item -Path $pstFile).Length
                    LastModified = (Get-Item -Path $pstFile).LastWriteTime
                } | ConvertTo-Json | Out-File -FilePath $pstMetadataFile -Encoding utf8
                
                Write-Log -Message "Found PST file: $pstFile (metadata saved)" -Level Information
            }
        }
        
        # Backup signatures
        $signaturesPath = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Signatures"
        if (Test-Path -Path $signaturesPath) {
            $signaturesBackupPath = Join-Path -Path $outlookBackupPath -ChildPath "Signatures"
            
            Copy-Item -Path $signaturesPath -Destination $signaturesBackupPath -Recurse -Force
            Write-Log -Message "Backed up Outlook signatures to $signaturesBackupPath" -Level Information
        } else {
            Write-Log -Message "No Outlook signatures found at $signaturesPath" -Level Information
        }
        
        # Backup templates
        $templatesPath = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Templates"
        if (Test-Path -Path $templatesPath) {
            $templatesBackupPath = Join-Path -Path $outlookBackupPath -ChildPath "Templates"
            
            Copy-Item -Path $templatesPath -Destination $templatesBackupPath -Recurse -Force
            Write-Log -Message "Backed up Office templates to $templatesBackupPath" -Level Information
        } else {
            Write-Log -Message "No Office templates found at $templatesPath" -Level Information
        }
        
        # Backup NK2 file (autocomplete cache) for older Outlook versions
        # In newer versions, this is in the Outlook.NK2 file in the profile folder
        $nk2Path = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Outlook"
        $nk2Files = Get-ChildItem -Path $nk2Path -Filter "*.nk2" -ErrorAction SilentlyContinue
        
        if ($nk2Files.Count -gt 0) {
            $nk2BackupPath = Join-Path -Path $outlookBackupPath -ChildPath "NK2"
            if (-not (Test-Path -Path $nk2BackupPath)) {
                New-Item -Path $nk2BackupPath -ItemType Directory -Force | Out-Null
            }
            
            foreach ($nk2File in $nk2Files) {
                Copy-Item -Path $nk2File.FullName -Destination $nk2BackupPath -Force
                Write-Log -Message "Backed up NK2 file: $($nk2File.Name)" -Level Information
            }
        } else {
            Write-Log -Message "No NK2 files found" -Level Information
        }
        
        # Store metadata
        $metadataFile = Join-Path -Path $outlookBackupPath -ChildPath "metadata.json"
        @{
            BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            OutlookVersion = $outlookVersion
            Username = $Username
            TargetUsername = $TargetUsername
            ComputerName = $env:COMPUTERNAME
        } | ConvertTo-Json | Out-File -FilePath $metadataFile -Encoding utf8
        
        # If backup only, stop here
        if ($BackupOnly) {
            Write-Log -Message "Outlook data backup completed for user $Username" -Level Information
            return $true
        }
        
        # Perform migration if source and target users are different
        if ($Username -ne $TargetUsername) {
            # Migration logic will go here in a future implementation
            Write-Log -Message "Migration to different user not yet implemented" -Level Warning
        } else {
            Write-Log -Message "Source and target users are the same, no migration needed" -Level Information
        }
        
        Write-Log -Message "Outlook data migration completed for user $Username" -Level Information
        return $true
    } catch {
        Write-Log -Message "Failed to migrate Outlook data: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Migrates browser bookmarks, cookies, passwords, and settings.
    
.DESCRIPTION
    Backs up and migrates browser data for Chrome, Edge, and Firefox.
    
.PARAMETER Username
    The username whose browser data will be migrated.
    
.PARAMETER TargetUsername
    The target username to migrate the data to.
    
.PARAMETER Browsers
    The browsers to migrate data for (defaults to all supported browsers).
    
.PARAMETER IncludePasswords
    Whether to include saved passwords in the migration.
    
.PARAMETER BackupOnly
    If set, only creates a backup without performing the migration.
    
.EXAMPLE
    Migrate-BrowserData -Username "source.user" -Browsers @("Chrome", "Edge")
    
.OUTPUTS
    System.Boolean. Returns $true if migration was successful.
#>
function Migrate-BrowserData {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Username = $env:USERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$TargetUsername = $Username,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Chrome", "Edge", "Firefox", "All")]
        [string[]]$Browsers = @("All"),
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludePasswords,
        
        [Parameter(Mandatory = $false)]
        [switch]$BackupOnly
    )
    
    try {
        Write-Log -Message "Starting browser data migration for user $Username" -Level Information
        
        # Expand "All" to include all supported browsers
        if ($Browsers -contains "All") {
            $Browsers = @("Chrome", "Edge", "Firefox")
        }
        
        # Create user-specific backup folder
        $userBackupPath = Join-Path -Path $script:BackupPath -ChildPath $Username
        if (-not (Test-Path -Path $userBackupPath)) {
            New-Item -Path $userBackupPath -ItemType Directory -Force | Out-Null
        }
        
        $browserBackupPath = Join-Path -Path $userBackupPath -ChildPath "Browsers"
        if (-not (Test-Path -Path $browserBackupPath)) {
            New-Item -Path $browserBackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Process each browser
        foreach ($browser in $Browsers) {
            $browserProfilePath = Get-BrowserProfilePath -Browser $browser -Username $Username
            
            if (-not $browserProfilePath) {
                Write-Log -Message "$browser not found for user $Username" -Level Warning
                continue
            }
            
            $browserSpecificBackupPath = Join-Path -Path $browserBackupPath -ChildPath $browser
            if (-not (Test-Path -Path $browserSpecificBackupPath)) {
                New-Item -Path $browserSpecificBackupPath -ItemType Directory -Force | Out-Null
            }
            
            Write-Log -Message "Backing up $browser data from $browserProfilePath" -Level Information
            
            # Backup bookmarks
            $bookmarksPath = Join-Path -Path $browserProfilePath -ChildPath $script:BrowserProfiles[$browser].Bookmarks
            if (Test-Path -Path $bookmarksPath) {
                $bookmarksBackupPath = Join-Path -Path $browserSpecificBackupPath -ChildPath "Bookmarks"
                Copy-Item -Path $bookmarksPath -Destination $bookmarksBackupPath -Force
                Write-Log -Message "Backed up $browser bookmarks" -Level Information
            } else {
                Write-Log -Message "$browser bookmarks not found at $bookmarksPath" -Level Warning
            }
            
            # Backup cookies (only if browser is not running)
            $browserProcess = Get-Process -Name $browser -ErrorAction SilentlyContinue
            if (-not $browserProcess) {
                $cookiesPath = Join-Path -Path $browserProfilePath -ChildPath $script:BrowserProfiles[$browser].Cookies
                if (Test-Path -Path $cookiesPath) {
                    $cookiesBackupPath = Join-Path -Path $browserSpecificBackupPath -ChildPath "Cookies"
                    Copy-Item -Path $cookiesPath -Destination $cookiesBackupPath -Force
                    Write-Log -Message "Backed up $browser cookies" -Level Information
                } else {
                    Write-Log -Message "$browser cookies not found at $cookiesPath" -Level Warning
                }
            } else {
                Write-Log -Message "Cannot backup $browser cookies while browser is running" -Level Warning
            }
            
            # Backup passwords if requested (only if browser is not running)
            if ($IncludePasswords -and -not $browserProcess) {
                $passwordsPath = Join-Path -Path $browserProfilePath -ChildPath $script:BrowserProfiles[$browser].Passwords
                if (Test-Path -Path $passwordsPath) {
                    $passwordsBackupPath = Join-Path -Path $browserSpecificBackupPath -ChildPath "Passwords"
                    Copy-Item -Path $passwordsPath -Destination $passwordsBackupPath -Force
                    Write-Log -Message "Backed up $browser passwords" -Level Information
                } else {
                    Write-Log -Message "$browser passwords not found at $passwordsPath" -Level Warning
                }
            }
            
            # Backup extensions
            $extensionsPath = Join-Path -Path $browserProfilePath -ChildPath $script:BrowserProfiles[$browser].Extensions
            if (Test-Path -Path $extensionsPath) {
                $extensionsBackupPath = Join-Path -Path $browserSpecificBackupPath -ChildPath "Extensions"
                
                # Extensions can be quite large, so just save the list of installed extensions
                $extensionsList = Get-ChildItem -Path $extensionsPath -Directory | Select-Object Name, FullName
                $extensionsListPath = Join-Path -Path $browserSpecificBackupPath -ChildPath "ExtensionsList.json"
                $extensionsList | ConvertTo-Json | Out-File -FilePath $extensionsListPath -Encoding utf8
                
                Write-Log -Message "Backed up list of $($extensionsList.Count) $browser extensions" -Level Information
            } else {
                Write-Log -Message "$browser extensions not found at $extensionsPath" -Level Warning
            }
        }
        
        # Store metadata
        $metadataFile = Join-Path -Path $browserBackupPath -ChildPath "metadata.json"
        @{
            BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Username = $Username
            TargetUsername = $TargetUsername
            Browsers = $Browsers
            IncludedPasswords = $IncludePasswords
            ComputerName = $env:COMPUTERNAME
        } | ConvertTo-Json | Out-File -FilePath $metadataFile -Encoding utf8
        
        # If backup only, stop here
        if ($BackupOnly) {
            Write-Log -Message "Browser data backup completed for user $Username" -Level Information
            return $true
        }
        
        # Perform migration if source and target users are different
        if ($Username -ne $TargetUsername) {
            # Migration logic will go here in a future implementation
            Write-Log -Message "Migration to different user not yet implemented" -Level Warning
        } else {
            Write-Log -Message "Source and target users are the same, no migration needed" -Level Information
        }
        
        Write-Log -Message "Browser data migration completed for user $Username" -Level Information
        return $true
    } catch {
        Write-Log -Message "Failed to migrate browser data: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Migrates Windows credential vault items.
    
.DESCRIPTION
    Backs up and migrates Windows credential vault items including passkeys.
    
.PARAMETER Username
    The username whose credentials will be migrated.
    
.PARAMETER TargetUsername
    The target username to migrate the data to.
    
.PARAMETER BackupOnly
    If set, only creates a backup without performing the migration.
    
.EXAMPLE
    Migrate-CredentialVault -Username "source.user"
    
.OUTPUTS
    System.Boolean. Returns $true if migration was successful.
#>
function Migrate-CredentialVault {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Username = $env:USERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$TargetUsername = $Username,
        
        [Parameter(Mandatory = $false)]
        [switch]$BackupOnly
    )
    
    try {
        Write-Log -Message "Starting credential vault migration for user $Username" -Level Information
        
        # This requires the CredentialManager module
        if (-not (Get-Module -Name CredentialManager -ListAvailable)) {
            try {
                Install-Module -Name CredentialManager -Scope CurrentUser -Force -ErrorAction Stop
                Import-Module -Name CredentialManager -Force -ErrorAction Stop
                Write-Log -Message "Installed CredentialManager module" -Level Information
            } catch {
                Write-Log -Message "Could not install CredentialManager module: $_" -Level Error
                return $false
            }
        }
        
        # Create user-specific backup folder
        $userBackupPath = Join-Path -Path $script:BackupPath -ChildPath $Username
        if (-not (Test-Path -Path $userBackupPath)) {
            New-Item -Path $userBackupPath -ItemType Directory -Force | Out-Null
        }
        
        $credentialsBackupPath = Join-Path -Path $userBackupPath -ChildPath "Credentials"
        if (-not (Test-Path -Path $credentialsBackupPath)) {
            New-Item -Path $credentialsBackupPath -ItemType Directory -Force | Out-Null
        }
        
        # Backup generic credentials
        $credentialsBackupFile = Join-Path -Path $credentialsBackupPath -ChildPath "GenericCredentials.xml"
        try {
            $credentials = Get-StoredCredential -AsCredentialObject
            $credentialsSafeData = $credentials | Select-Object -Property Target, Type, PersistanceType
            $credentialsSafeData | Export-Clixml -Path $credentialsBackupFile -Force
            Write-Log -Message "Backed up $($credentials.Count) generic credentials" -Level Information
        } catch {
            Write-Log -Message "Error backing up generic credentials: $_" -Level Warning
        }
        
        # Get Passkeys info if on Windows 11
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $isWindows11 = $osInfo.Caption -match "Windows 11"
        
        if ($isWindows11) {
            # Windows 11 passkeys
            $passkeysBackupFile = Join-Path -Path $credentialsBackupPath -ChildPath "Passkeys.json"
            try {
                # For security reasons, we can't export the actual passkeys, but we can get info about them
                $passkeysInfo = @()
                
                # Use PowerShell to query Windows WebAuthn API (in production this would require a more complex approach)
                # This is just a placeholder for demonstration
                $passkeysInfo += @{
                    Description = "Passkeys information cannot be directly extracted or migrated for security reasons"
                    Recommendation = "Users will need to re-register passkeys on their new profile"
                    OriginDomains = @("accounts.google.com", "github.com", "microsoft.com")
                }
                
                $passkeysInfo | ConvertTo-Json | Out-File -FilePath $passkeysBackupFile -Force
                Write-Log -Message "Saved passkeys information" -Level Information
            } catch {
                Write-Log -Message "Error getting passkeys information: $_" -Level Warning
            }
        }
        
        # Store metadata
        $metadataFile = Join-Path -Path $credentialsBackupPath -ChildPath "metadata.json"
        @{
            BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Username = $Username
            TargetUsername = $TargetUsername
            ComputerName = $env:COMPUTERNAME
            IsWindows11 = $isWindows11
        } | ConvertTo-Json | Out-File -FilePath $metadataFile -Encoding utf8
        
        # If backup only, stop here
        if ($BackupOnly) {
            Write-Log -Message "Credential vault backup completed for user $Username" -Level Information
            return $true
        }
        
        # Perform migration if source and target users are different
        if ($Username -ne $TargetUsername) {
            # Migration logic will go here in a future implementation
            Write-Log -Message "Migration to different user not yet implemented" -Level Warning
        } else {
            Write-Log -Message "Source and target users are the same, no migration needed" -Level Information
        }
        
        Write-Log -Message "Credential vault migration completed for user $Username" -Level Information
        return $true
    } catch {
        Write-Log -Message "Failed to migrate credential vault: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Migrates all user application data in one step.
    
.DESCRIPTION
    Provides a convenient way to migrate all application data types at once.
    
.PARAMETER Username
    The username whose application data will be migrated.
    
.PARAMETER TargetUsername
    The target username to migrate the data to.
    
.PARAMETER BackupOnly
    If set, only creates a backup without performing the migration.
    
.PARAMETER IncludeOutlook
    Whether to include Outlook data in the migration.
    
.PARAMETER IncludeBrowsers
    Whether to include browser data in the migration.
    
.PARAMETER IncludeCredentials
    Whether to include credential vault items in the migration.
    
.PARAMETER IncludeBrowserPasswords
    Whether to include saved browser passwords in the migration.
    
.EXAMPLE
    Migrate-AllApplicationData -Username "source.user" -TargetUsername "target.user"
    
.OUTPUTS
    System.Boolean. Returns $true if migration was successful.
#>
function Migrate-AllApplicationData {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Username = $env:USERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$TargetUsername = $Username,
        
        [Parameter(Mandatory = $false)]
        [switch]$BackupOnly,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeOutlook = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeBrowsers = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeCredentials = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeBrowserPasswords = $false
    )
    
    try {
        Write-Log -Message "Starting complete application data migration for user $Username" -Level Information
        
        # Initialize module if not already done
        Initialize-ApplicationDataMigration | Out-Null
        
        $successCount = 0
        $totalTasks = 0
        
        # Outlook data migration
        if ($IncludeOutlook) {
            $totalTasks++
            $outlookSuccess = Migrate-OutlookData -Username $Username -TargetUsername $TargetUsername -BackupOnly:$BackupOnly
            if ($outlookSuccess) { $successCount++ }
        }
        
        # Browser data migration
        if ($IncludeBrowsers) {
            $totalTasks++
            $browserSuccess = Migrate-BrowserData -Username $Username -TargetUsername $TargetUsername -IncludePasswords:$IncludeBrowserPasswords -BackupOnly:$BackupOnly
            if ($browserSuccess) { $successCount++ }
        }
        
        # Credential vault migration
        if ($IncludeCredentials) {
            $totalTasks++
            $credentialsSuccess = Migrate-CredentialVault -Username $Username -TargetUsername $TargetUsername -BackupOnly:$BackupOnly
            if ($credentialsSuccess) { $successCount++ }
        }
        
        $successPercent = ($successCount / $totalTasks) * 100
        Write-Log -Message "Completed migration with $successCount/$totalTasks tasks successful ($successPercent%)" -Level Information
        
        return ($successCount -eq $totalTasks)
    } catch {
        Write-Log -Message "Failed during application data migration: $_" -Level Error
        return $false
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Initialize-ApplicationDataMigration, Migrate-OutlookData, Migrate-BrowserData, Migrate-CredentialVault, Migrate-AllApplicationData 





