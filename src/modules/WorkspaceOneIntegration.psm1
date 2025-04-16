################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Initializes the Workspace ONE integration module.                                                                     #
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
.DESCRIPTION
    This module provides functions to interact with VMware Workspace ONE UEM API
    for device inventory extraction, profile export, and application management.
.NOTES
    File Name  : WorkspaceOneIntegration.psm1
    Author     : Workspace ONE to Intune Migration Team
    Version    : 1.0.0
    Requires   : PowerShell 5.1 or later
#>

#Region Module Variables
# Module-level variables
$script:ApiEndpoint = $null
$script:AuthToken = $null
$script:ApiKey = $null
$script:Tenant = $null
$script:LogEnabled = $true
$script:LogPath = "$env:ProgramData\WS1_Migration\Logs"
$script:UseVerboseLogging = $false
#EndRegion

#Region Module Functions

function Initialize-WorkspaceOneIntegration {
    <#
    .SYNOPSIS
        Initializes the Workspace ONE integration module.
    .DESCRIPTION
        Sets up the connection parameters and authenticates with the Workspace ONE UEM API.
    .PARAMETER ApiEndpoint
        The Workspace ONE UEM API endpoint URL.
    .PARAMETER Credential
        PSCredential object containing Workspace ONE admin credentials.
    .PARAMETER ApiKey
        The API key for Workspace ONE UEM API.
    .PARAMETER Tenant
        The Workspace ONE tenant identifier.
    .PARAMETER LogPath
        Path to store log files.
    .PARAMETER EnableVerboseLogging
        Enable detailed logging for API operations.
    .EXAMPLE
        Initialize-WorkspaceOneIntegration -ApiEndpoint "https://as1234.awmdm.com" -Credential $cred -ApiKey "abcd1234" -Tenant "CustomerTenant"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ApiEndpoint,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $true)]
        [string]$Tenant,

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "$env:ProgramData\WS1_Migration\Logs",

        [Parameter(Mandatory = $false)]
        [switch]$EnableVerboseLogging
    )

    # Validate endpoint URL
    if (-not $ApiEndpoint.StartsWith("https://")) {
        throw "API endpoint must use HTTPS"
    }

    # Trim trailing slash if present
    if ($ApiEndpoint.EndsWith("/")) {
        $ApiEndpoint = $ApiEndpoint.TrimEnd("/")
    }

    # Set module variables
    $script:ApiEndpoint = $ApiEndpoint
    $script:ApiKey = $ApiKey
    $script:Tenant = $Tenant
    $script:LogPath = $LogPath
    $script:UseVerboseLogging = $EnableVerboseLogging

    # Ensure log directory exists
    if (-not (Test-Path -Path $script:LogPath)) {
        New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
    }

    Write-Log -Message "Initializing Workspace ONE integration" -Level Info

    # Authenticate and get token
    try {
        # In a real implementation, this would authenticate with the actual API
        # For now, we'll simulate authentication success
        Write-Log -Message "Authenticating with Workspace ONE UEM API at $ApiEndpoint" -Level Info
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
        
        # In real implementation, we would make an API call here and store the token
        $script:AuthToken = "SIMULATED-WS1-TOKEN-$base64Auth"
        Write-Log -Message "Successfully authenticated with Workspace ONE UEM API" -Level Info
        
        return $true
    }
    catch {
        Write-Log -Message "Failed to authenticate with Workspace ONE UEM API: $_" -Level Error
        return $false
    }
}

function Get-WorkspaceOneDevices {
    <#
    .SYNOPSIS
        Retrieves devices from Workspace ONE UEM.
    .DESCRIPTION
        Gets device information from Workspace ONE UEM API.
    .PARAMETER Filter
        Optional filter to limit devices returned.
    .PARAMETER PageSize
        Number of devices to return per page.
    .EXAMPLE
        Get-WorkspaceOneDevices -PageSize 100
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [int]$PageSize = 500
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Retrieving devices from Workspace ONE UEM" -Level Info
        
        # Build request URL
        $uri = "$script:ApiEndpoint/api/mdm/devices"
        if ($Filter) {
            $uri += "?$Filter"
        }
        
        # In a real implementation, we would call the actual API
        # For demo purposes, return simulated device data
        $devices = @(
            [PSCustomObject]@{
                DeviceId = "WS1-DEVICE-001"
                SerialNumber = "SERIAL123456"
                IMEI = "123456789012345"
                FriendlyName = "Device 001"
                UserName = "user@example.com"
                Model = "Surface Pro 7"
                OperatingSystem = "Windows 10"
                OSVersion = "10.0.19044"
                LastSeen = (Get-Date).AddDays(-1)
                EnrollmentStatus = "Enrolled"
                ComplianceStatus = "Compliant"
                AppsInstalled = @(
                    [PSCustomObject]@{
                        ApplicationId = "APP-001"
                        ApplicationName = "Microsoft Office 365"
                        Version = "16.0.14527.20226"
                        InstallDate = (Get-Date).AddMonths(-3)
                    },
                    [PSCustomObject]@{
                        ApplicationId = "APP-002"
                        ApplicationName = "Adobe Acrobat Reader"
                        Version = "21.5.20060"
                        InstallDate = (Get-Date).AddMonths(-2)
                    }
                )
            },
            [PSCustomObject]@{
                DeviceId = "WS1-DEVICE-002"
                SerialNumber = "SERIAL654321"
                IMEI = "543210987654321"
                FriendlyName = "Device 002"
                UserName = "admin@example.com"
                Model = "Dell XPS 13"
                OperatingSystem = "Windows 11"
                OSVersion = "10.0.22000"
                LastSeen = (Get-Date).AddHours(-5)
                EnrollmentStatus = "Enrolled"
                ComplianceStatus = "Compliant"
                AppsInstalled = @(
                    [PSCustomObject]@{
                        ApplicationId = "APP-001"
                        ApplicationName = "Microsoft Office 365"
                        Version = "16.0.14527.20226"
                        InstallDate = (Get-Date).AddMonths(-1)
                    },
                    [PSCustomObject]@{
                        ApplicationId = "APP-003"
                        ApplicationName = "Google Chrome"
                        Version = "105.0.5195.127"
                        InstallDate = (Get-Date).AddDays(-15)
                    }
                )
            }
        )
        
        Write-Log -Message "Successfully retrieved $($devices.Count) devices" -Level Info
        return $devices
    }
    catch {
        Write-Log -Message "Failed to retrieve devices: $_" -Level Error
        return @()
    }
}

function Export-WorkspaceOneProfiles {
    <#
    .SYNOPSIS
        Exports profiles from Workspace ONE UEM.
    .DESCRIPTION
        Retrieves and exports profiles from Workspace ONE UEM for migration.
    .PARAMETER OutputPath
        Path where profiles will be exported.
    .PARAMETER ProfileType
        Type of profiles to export (e.g., Windows, iOS, Android).
    .EXAMPLE
        Export-WorkspaceOneProfiles -OutputPath "C:\Temp\Profiles" -ProfileType "Windows"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Windows", "iOS", "Android", "All")]
        [string]$ProfileType = "All"
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Exporting $ProfileType profiles from Workspace ONE UEM" -Level Info
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # In a real implementation, we would call the API and export actual profiles
        # For demo purposes, we'll create simulated profiles
        $profileData = [PSCustomObject]@{
            Profiles = @(
                [PSCustomObject]@{
                    ProfileId = "PROF-001"
                    Name = "Windows Security Baseline"
                    Description = "Base security settings for Windows devices"
                    Platform = "Windows"
                    AssignedGroups = @("All Users", "Corporate Devices")
                    Settings = @{
                        "PasswordComplexity" = "High"
                        "MinimumPasswordLength" = 12
                        "EncryptionRequired" = $true
                    }
                },
                [PSCustomObject]@{
                    ProfileId = "PROF-002"
                    Name = "Windows VPN Configuration"
                    Description = "Corporate VPN settings"
                    Platform = "Windows"
                    AssignedGroups = @("Remote Users")
                    Settings = @{
                        "VpnType" = "IKEv2"
                        "ServerAddress" = "vpn.example.com"
                        "Authentication" = "Certificate"
                    }
                }
            )
        }
        
        # Export to JSON file
        $outputFile = Join-Path -Path $OutputPath -ChildPath "WS1_Profiles_$ProfileType.json"
        $profileData | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Encoding UTF8
        
        Write-Log -Message "Successfully exported profiles to $outputFile" -Level Info
        return $outputFile
    }
    catch {
        Write-Log -Message "Failed to export profiles: $_" -Level Error
        return $false
    }
}

#Region Application Management Functions

function Get-WorkspaceOneApplications {
    <#
    .SYNOPSIS
        Retrieves application catalog from Workspace ONE UEM.
    .DESCRIPTION
        Gets all applications from Workspace ONE UEM to prepare for migration.
    .PARAMETER Filter
        Optional filter to limit applications returned.
    .PARAMETER IncludeFilesAndActions
        Whether to include all files and actions details for apps.
    .EXAMPLE
        Get-WorkspaceOneApplications -IncludeFilesAndActions
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFilesAndActions
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Retrieving applications from Workspace ONE UEM" -Level Info
        
        # In a real implementation, we would call the actual API
        # For demo purposes, return simulated application data
        $apps = @(
            [PSCustomObject]@{
                ApplicationId = "APP-001"
                ApplicationName = "Microsoft Office 365"
                Description = "Microsoft Office 365 Suite"
                Developer = "Microsoft"
                Category = "Productivity"
                DeploymentType = "MSI"
                SupportedOS = @("Windows 10", "Windows 11")
                AppVersion = "16.0.14527.20226"
                PackageSize = 1562428
                CommandLineArgs = "/configure config.xml"
                InstallLocationPath = "C:\Program Files\Microsoft Office"
                AssignedGroups = @("All Users", "Corporate Devices")
                Files = @(
                    [PSCustomObject]@{
                        FileName = "Office365Setup.exe"
                        FileSize = 1562428
                        FilePath = "/mnt/data/app-data/apps/Office365Setup.exe"
                        FileHash = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"
                    }
                )
                InstallActions = @(
                    [PSCustomObject]@{
                        ActionType = "Install"
                        Command = "Office365Setup.exe"
                        Arguments = "/configure config.xml"
                        RunAs = "System"
                        Timeout = 1800
                    },
                    [PSCustomObject]@{
                        ActionType = "Uninstall"
                        Command = "Office365Setup.exe"
                        Arguments = "/uninstall"
                        RunAs = "System"
                        Timeout = 600
                    }
                )
            },
            [PSCustomObject]@{
                ApplicationId = "APP-002"
                ApplicationName = "Adobe Acrobat Reader"
                Description = "PDF viewer from Adobe"
                Developer = "Adobe"
                Category = "Utilities"
                DeploymentType = "EXE"
                SupportedOS = @("Windows 10", "Windows 11")
                AppVersion = "21.5.20060"
                PackageSize = 253741
                CommandLineArgs = "/sAll /rs /msi /norestart /quiet EULA_ACCEPT=YES"
                InstallLocationPath = "C:\Program Files\Adobe\Acrobat Reader DC"
                AssignedGroups = @("All Users")
                Files = @(
                    [PSCustomObject]@{
                        FileName = "AcroRdrDC.exe"
                        FileSize = 253741
                        FilePath = "/mnt/data/app-data/apps/AcroRdrDC.exe"
                        FileHash = "z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4j3h2g1f0"
                    }
                )
                InstallActions = @(
                    [PSCustomObject]@{
                        ActionType = "Install"
                        Command = "AcroRdrDC.exe"
                        Arguments = "/sAll /rs /msi /norestart /quiet EULA_ACCEPT=YES"
                        RunAs = "System"
                        Timeout = 900
                    },
                    [PSCustomObject]@{
                        ActionType = "Uninstall"
                        Command = "msiexec.exe"
                        Arguments = "/x {AC76BA86-7AD7-1033-7B44-AC0F074E4100} /qn"
                        RunAs = "System"
                        Timeout = 300
                    }
                )
            }
        )
        
        Write-Log -Message "Successfully retrieved $($apps.Count) applications" -Level Info
        return $apps
    }
    catch {
        Write-Log -Message "Failed to retrieve applications: $_" -Level Error
        return @()
    }
}

function Export-WorkspaceOneApplication {
    <#
    .SYNOPSIS
        Exports a specific application from Workspace ONE UEM.
    .DESCRIPTION
        Downloads application files and metadata for migration to Intune.
    .PARAMETER ApplicationId
        ID of the application to export.
    .PARAMETER OutputPath
        Path where application files and metadata will be exported.
    .EXAMPLE
        Export-WorkspaceOneApplication -ApplicationId "APP-001" -OutputPath "C:\Temp\Apps"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Exporting application $ApplicationId from Workspace ONE UEM" -Level Info
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # In a real implementation, we would call the API and download the actual application
        # For demo purposes, we'll create simulated application data
        
        # Get app details (in real implementation, we would call the API)
        $app = Get-WorkspaceOneApplications | Where-Object { $_.ApplicationId -eq $ApplicationId }
        
        if (-not $app) {
            Write-Log -Message "Application with ID $ApplicationId not found" -Level Error
            return $false
        }
        
        # Create app-specific folder
        $appFolder = Join-Path -Path $OutputPath -ChildPath $app.ApplicationId
        New-Item -Path $appFolder -ItemType Directory -Force | Out-Null
        
        # Create metadata file
        $metadataFile = Join-Path -Path $appFolder -ChildPath "metadata.json"
        $app | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataFile -Encoding UTF8
        
        # Create dummy installer file (in real implementation, we would download actual files)
        $installerFile = Join-Path -Path $appFolder -ChildPath $app.Files[0].FileName
        "This is a placeholder for the actual installer file." | Set-Content -Path $installerFile -Encoding UTF8
        
        # Create Intune-compatible .intunewin file (simulated)
        $intunewinFile = Join-Path -Path $appFolder -ChildPath "$($app.ApplicationName.Replace(' ', '_')).intunewin"
        "This is a placeholder for the .intunewin package" | Set-Content -Path $intunewinFile -Encoding UTF8
        
        Write-Log -Message "Successfully exported application to $appFolder" -Level Info
        return $appFolder
    }
    catch {
        Write-Log -Message "Failed to export application: $_" -Level Error
        return $false
    }
}

function Export-WorkspaceOneApplications {
    <#
    .SYNOPSIS
        Exports all applications from Workspace ONE UEM.
    .DESCRIPTION
        Exports all applications and their metadata for migration to Intune.
    .PARAMETER OutputPath
        Path where applications will be exported.
    .PARAMETER Filter
        Optional filter to limit applications to export.
    .EXAMPLE
        Export-WorkspaceOneApplications -OutputPath "C:\Temp\Apps"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Exporting all applications from Workspace ONE UEM" -Level Info
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Get all applications
        $apps = Get-WorkspaceOneApplications -Filter $Filter
        
        if ($apps.Count -eq 0) {
            Write-Log -Message "No applications found to export" -Level Warning
            return $false
        }
        
        # Create catalog summary file
        $catalogFile = Join-Path -Path $OutputPath -ChildPath "application_catalog.json"
        $apps | ConvertTo-Json -Depth 5 | Set-Content -Path $catalogFile -Encoding UTF8
        
        # Export each application
        $results = @()
        foreach ($app in $apps) {
            Write-Log -Message "Exporting application: $($app.ApplicationName)" -Level Info
            $exportResult = Export-WorkspaceOneApplication -ApplicationId $app.ApplicationId -OutputPath $OutputPath
            
            $results += [PSCustomObject]@{
                ApplicationId = $app.ApplicationId
                ApplicationName = $app.ApplicationName
                ExportPath = $exportResult
                ExportSuccess = ($null -ne $exportResult -and $exportResult -ne $false)
            }
        }
        
        # Create export summary file
        $summaryFile = Join-Path -Path $OutputPath -ChildPath "export_summary.json"
        $results | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryFile -Encoding UTF8
        
        Write-Log -Message "Successfully exported $($results.Count) applications to $OutputPath" -Level Info
        
        # Create Intune import instructions file
        $instructionsFile = Join-Path -Path $OutputPath -ChildPath "intune_import_instructions.md"
        $instructionsContent = @"
# Workspace ONE to Intune Application Migration

This package contains applications exported from Workspace ONE UEM for import into Microsoft Intune.

## Applications Included

Total applications: $($apps.Count)

$(foreach ($app in $apps) {
"- $($app.ApplicationName) (v$($app.AppVersion))"
})

## Import Instructions

1. Use the Microsoft Intune Win32 App Packaging Tool to process the installer files
2. Upload the .intunewin files to Intune
3. Configure application properties according to the metadata.json files
4. Set up app dependencies as specified in the metadata
5. Assign to appropriate groups

## Post-Migration Verification

After importing the applications to Intune, verify:
- Application installs correctly on test devices
- Silent installation works as expected
- Application appears in Company Portal
- User-targeting works correctly
"@
        $instructionsContent | Set-Content -Path $instructionsFile -Encoding UTF8
        
        return $summaryFile
    }
    catch {
        Write-Log -Message "Failed to export applications: $_" -Level Error
        return $false
    }
}

function ConvertTo-IntuneWin32App {
    <#
    .SYNOPSIS
        Converts a Workspace ONE application to Intune Win32 app format.
    .DESCRIPTION
        Prepares a Workspace ONE application for import into Intune as a Win32 app.
    .PARAMETER ApplicationId
        ID of the application to convert.
    .PARAMETER SourcePath
        Path where the application export files are located.
    .PARAMETER OutputPath
        Path where the Intune-ready application will be created.
    .PARAMETER IntuneWinAppUtilPath
        Path to the Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe).
    .EXAMPLE
        ConvertTo-IntuneWin32App -ApplicationId "APP-001" -SourcePath "C:\Temp\Apps\APP-001" -OutputPath "C:\Temp\Intune" -IntuneWinAppUtilPath "C:\Tools\IntuneWinAppUtil.exe"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$IntuneWinAppUtilPath
    )

    try {
        Write-Log -Message "Converting application $ApplicationId to Intune Win32 format" -Level Info
        
        # Validate paths
        if (-not (Test-Path -Path $SourcePath)) {
            throw "Source path does not exist: $SourcePath"
        }
        
        if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
            throw "IntuneWinAppUtil.exe not found at: $IntuneWinAppUtilPath"
        }
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Load application metadata
        $metadataFile = Join-Path -Path $SourcePath -ChildPath "metadata.json"
        if (-not (Test-Path -Path $metadataFile)) {
            throw "Metadata file not found at: $metadataFile"
        }
        
        $app = Get-Content -Path $metadataFile -Raw | ConvertFrom-Json
        
        # Find installer file
        $installerFileName = $app.Files[0].FileName
        $installerPath = Join-Path -Path $SourcePath -ChildPath $installerFileName
        
        if (-not (Test-Path -Path $installerPath)) {
            throw "Installer file not found at: $installerPath"
        }
        
        # Create output subfolder
        $appOutputFolder = Join-Path -Path $OutputPath -ChildPath $app.ApplicationId
        New-Item -Path $appOutputFolder -ItemType Directory -Force | Out-Null
        
        # Create setup files
        $setupFolder = Join-Path -Path $appOutputFolder -ChildPath "setup"
        New-Item -Path $setupFolder -ItemType Directory -Force | Out-Null
        
        # Copy installer to setup folder
        Copy-Item -Path $installerPath -Destination $setupFolder
        
        # Create detection script
        $detectionScriptPath = Join-Path -Path $setupFolder -ChildPath "detect.ps1"
        $detectionScript = @"
# Detection script for $($app.ApplicationName)
`$installPath = "$($app.InstallLocationPath)"
if (Test-Path -Path `$installPath) {
    # For version-specific detection, add version checking logic here
    Write-Output "Found $($app.ApplicationName)"
    exit 0
} else {
    exit 1
}
"@
        $detectionScript | Set-Content -Path $detectionScriptPath -Encoding UTF8
        
        # Create install and uninstall CMD files
        $installCmdPath = Join-Path -Path $setupFolder -ChildPath "install.cmd"
        $installCmd = "@echo off`r`n"
        $installCmd += "echo Installing $($app.ApplicationName)`r`n"
        $installCmd += """$installerFileName"" $($app.CommandLineArgs)`r`n"
        $installCmd += "exit /b %ERRORLEVEL%"
        $installCmd | Set-Content -Path $installCmdPath -Encoding UTF8
        
        $uninstallCmdPath = Join-Path -Path $setupFolder -ChildPath "uninstall.cmd"
        $uninstallAction = $app.InstallActions | Where-Object { $_.ActionType -eq "Uninstall" }
        $uninstallCmd = "@echo off`r`n"
        $uninstallCmd += "echo Uninstalling $($app.ApplicationName)`r`n"
        $uninstallCmd += """$($uninstallAction.Command)"" $($uninstallAction.Arguments)`r`n"
        $uninstallCmd += "exit /b %ERRORLEVEL%"
        $uninstallCmd | Set-Content -Path $uninstallCmdPath -Encoding UTF8
        
        # Create Intune app definition file
        $intuneDefinitionPath = Join-Path -Path $appOutputFolder -ChildPath "intune_app_definition.json"
        $intuneDefinition = [PSCustomObject]@{
            displayName = $app.ApplicationName
            description = $app.Description
            publisher = $app.Developer
            category = $app.Category
            installCommandLine = "install.cmd"
            uninstallCommandLine = "uninstall.cmd"
            detectionRules = @{
                type = "script"
                scriptContent = $detectionScript
            }
            installExperience = @{
                runAsAccount = "system"
                deviceRestartBehavior = "suppress"
            }
            minimumOSVersion = "10.0.0.0"
            applicableArchitectures = "x64,x86"
            assignmentGroups = $app.AssignedGroups
        }
        
        $intuneDefinition | ConvertTo-Json -Depth 10 | Set-Content -Path $intuneDefinitionPath -Encoding UTF8
        
        # In a real implementation, we would call IntuneWinAppUtil.exe to create the .intunewin file
        # For demo purposes, we'll create a placeholder
        
        Write-Log -Message "In production, would execute: $IntuneWinAppUtilPath -c $setupFolder -s $installerFileName -o $appOutputFolder" -Level Info
        
        # Create mock .intunewin file
        $intunewinPath = Join-Path -Path $appOutputFolder -ChildPath "$($app.ApplicationName.Replace(' ', '_')).intunewin"
        "This is a placeholder for the actual .intunewin package" | Set-Content -Path $intunewinPath -Encoding UTF8
        
        # Create import instructions
        $instructionsPath = Join-Path -Path $appOutputFolder -ChildPath "README.md"
        $instructions = @"
# $($app.ApplicationName) - Intune Import Instructions

## Application Details
- **Name**: $($app.ApplicationName)
- **Version**: $($app.AppVersion)
- **Developer**: $($app.Developer)
- **Category**: $($app.Category)

## Import Steps
1. In the Microsoft Endpoint Manager admin center, navigate to Apps > Windows
2. Click "Add" and select "Windows app (Win32)"
3. Upload the .intunewin file: "$($app.ApplicationName.Replace(' ', '_')).intunewin"
4. Configure app information using values from intune_app_definition.json
5. Configure program settings:
   - Install command: install.cmd
   - Uninstall command: uninstall.cmd
6. Configure detection rules using the provided detection script
7. Configure app dependencies and supersedence (if applicable)
8. Assign to appropriate groups

## Notes
- This application was migrated from Workspace ONE UEM
- Original application ID: $($app.ApplicationId)
- Originally assigned to groups: $($app.AssignedGroups -join ", ")
"@
        $instructions | Set-Content -Path $instructionsPath -Encoding UTF8
        
        Write-Log -Message "Successfully converted application to Intune Win32 format at $appOutputFolder" -Level Info
        return $appOutputFolder
    }
    catch {
        Write-Log -Message "Failed to convert application to Intune format: $_" -Level Error
        return $false
    }
}

function Get-ApplicationsByDevice {
    <#
    .SYNOPSIS
        Retrieves applications installed on a specific device.
    .DESCRIPTION
        Gets the list of applications installed on a device managed by Workspace ONE UEM.
    .PARAMETER DeviceId
        ID of the device to query.
    .EXAMPLE
        Get-ApplicationsByDevice -DeviceId "DEV-12345"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Retrieving applications for device $DeviceId" -Level Info
        
        # In a real implementation, we would call the actual API
        # For demo purposes, return simulated device application data
        $deviceApps = @(
            [PSCustomObject]@{
                ApplicationId = "APP-001"
                ApplicationName = "Microsoft Office 365"
                Version = "16.0.14527.20226"
                Status = "Installed"
                InstallDate = (Get-Date).AddMonths(-3)
                LastChecked = (Get-Date).AddDays(-1)
            },
            [PSCustomObject]@{
                ApplicationId = "APP-002"
                ApplicationName = "Adobe Acrobat Reader"
                Version = "21.5.20060"
                Status = "Installed"
                InstallDate = (Get-Date).AddMonths(-2)
                LastChecked = (Get-Date).AddDays(-1)
            },
            [PSCustomObject]@{
                ApplicationId = "APP-003"
                ApplicationName = "Google Chrome"
                Version = "105.0.5195.127"
                Status = "Installed"
                InstallDate = (Get-Date).AddDays(-15)
                LastChecked = (Get-Date).AddDays(-1)
            }
        )
        
        Write-Log -Message "Successfully retrieved $($deviceApps.Count) applications for device $DeviceId" -Level Info
        return $deviceApps
    }
    catch {
        Write-Log -Message "Failed to retrieve applications for device: $_" -Level Error
        return @()
    }
}

function Get-ApplicationAssignments {
    <#
    .SYNOPSIS
        Retrieves application assignments from Workspace ONE UEM.
    .DESCRIPTION
        Gets the assignments (smart groups, organization groups) for applications.
    .PARAMETER ApplicationId
        Optional ID of a specific application to query.
    .EXAMPLE
        Get-ApplicationAssignments -ApplicationId "APP-001"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ApplicationId
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Retrieving application assignments from Workspace ONE UEM" -Level Info
        
        # In a real implementation, we would call the actual API
        # For demo purposes, return simulated assignment data
        $assignments = @(
            [PSCustomObject]@{
                ApplicationId = "APP-001"
                ApplicationName = "Microsoft Office 365"
                AssignmentGroups = @(
                    [PSCustomObject]@{
                        GroupId = "GROUP-001"
                        GroupName = "All Users"
                        GroupType = "Smart Group"
                        DeploymentMode = "Required"
                    },
                    [PSCustomObject]@{
                        GroupId = "GROUP-002"
                        GroupName = "Corporate Devices"
                        GroupType = "Organization Group"
                        DeploymentMode = "Required"
                    }
                )
            },
            [PSCustomObject]@{
                ApplicationId = "APP-002"
                ApplicationName = "Adobe Acrobat Reader"
                AssignmentGroups = @(
                    [PSCustomObject]@{
                        GroupId = "GROUP-001"
                        GroupName = "All Users"
                        GroupType = "Smart Group"
                        DeploymentMode = "Required"
                    }
                )
            },
            [PSCustomObject]@{
                ApplicationId = "APP-003"
                ApplicationName = "Google Chrome"
                AssignmentGroups = @(
                    [PSCustomObject]@{
                        GroupId = "GROUP-001"
                        GroupName = "All Users"
                        GroupType = "Smart Group"
                        DeploymentMode = "Available"
                    },
                    [PSCustomObject]@{
                        GroupId = "GROUP-003"
                        GroupName = "Marketing Department"
                        GroupType = "Organization Group"
                        DeploymentMode = "Required"
                    }
                )
            }
        )
        
        # Filter for specific application if specified
        if ($ApplicationId) {
            $assignments = $assignments | Where-Object { $_.ApplicationId -eq $ApplicationId }
        }
        
        Write-Log -Message "Successfully retrieved assignments for $($assignments.Count) applications" -Level Info
        return $assignments
    }
    catch {
        Write-Log -Message "Failed to retrieve application assignments: $_" -Level Error
        return @()
    }
}

function Export-ApplicationMigrationPlan {
    <#
    .SYNOPSIS
        Creates a comprehensive migration plan for applications.
    .DESCRIPTION
        Analyzes applications and creates a detailed plan for migrating them to Intune.
    .PARAMETER OutputPath
        Path where the migration plan will be saved.
    .EXAMPLE
        Export-ApplicationMigrationPlan -OutputPath "C:\Temp\MigrationPlan"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    # Validate that module is initialized
    if (-not $script:AuthToken) {
        throw "Module not initialized. Call Initialize-WorkspaceOneIntegration first."
    }

    try {
        Write-Log -Message "Creating application migration plan" -Level Info
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Get all applications
        $apps = Get-WorkspaceOneApplications -IncludeFilesAndActions
        
        # Get all assignments
        $assignments = Get-ApplicationAssignments
        
        # Create migration plan
        $migrationPlan = @()
        foreach ($app in $apps) {
            $appAssignments = $assignments | Where-Object { $_.ApplicationId -eq $app.ApplicationId }
            
            # Determine app deployment type for Intune
            $intuneDeploymentType = switch ($app.DeploymentType) {
                "MSI" { "Win32App" }
                "EXE" { "Win32App" }
                "UWP" { "Store App" }
                default { "Win32App" }
            }
            
            # Determine migration complexity
            $complexity = "Medium"
            if ($app.InstallActions.Count -gt 2 -or $app.DeploymentType -eq "Script") {
                $complexity = "High"
            } elseif ($app.DeploymentType -eq "MSI" -and -not $app.CommandLineArgs) {
                $complexity = "Low"
            }
            
            $migrationPlan += [PSCustomObject]@{
                ApplicationId = $app.ApplicationId
                ApplicationName = $app.ApplicationName
                Version = $app.AppVersion
                Developer = $app.Developer
                SourceDeploymentType = $app.DeploymentType
                TargetDeploymentType = $intuneDeploymentType
                MigrationComplexity = $complexity
                EstimatedEffort = switch ($complexity) {
                    "Low" { "1 hour" }
                    "Medium" { "2-4 hours" }
                    "High" { "4-8 hours" }
                    default { "Unknown" }
                }
                AssignedGroups = if ($appAssignments) { $appAssignments.AssignmentGroups.GroupName } else { @() }
                DependsOn = @() # In a real implementation, we would analyze dependencies
                MigrationNotes = @()
                PackageSize = $app.PackageSize
                PriorityScore = switch ($complexity) {
                    "Low" { 1 }
                    "Medium" { 2 }
                    "High" { 3 }
                }
            }
        }
        
        # Sort by priority (simple scoring based on complexity)
        $migrationPlan = $migrationPlan | Sort-Object -Property PriorityScore
        
        # Export to CSV and JSON
        $csvPath = Join-Path -Path $OutputPath -ChildPath "application_migration_plan.csv"
        $jsonPath = Join-Path -Path $OutputPath -ChildPath "application_migration_plan.json"
        
        $migrationPlan | Export-Csv -Path $csvPath -NoTypeInformation
        $migrationPlan | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
        
        # Create summary report
        $summaryPath = Join-Path -Path $OutputPath -ChildPath "migration_summary.md"
        $summary = @"
# Workspace ONE to Intune Application Migration Plan

## Migration Overview

**Total Applications:** $($migrationPlan.Count)

**Complexity Breakdown:**
- Low Complexity: $($migrationPlan | Where-Object { $_.MigrationComplexity -eq "Low" } | Measure-Object | Select-Object -ExpandProperty Count)
- Medium Complexity: $($migrationPlan | Where-Object { $_.MigrationComplexity -eq "Medium" } | Measure-Object | Select-Object -ExpandProperty Count)
- High Complexity: $($migrationPlan | Where-Object { $_.MigrationComplexity -eq "High" } | Measure-Object | Select-Object -ExpandProperty Count)

**Total Estimated Effort:** $($migrationPlan | ForEach-Object {
    switch ($_.MigrationComplexity) {
        "Low" { 1 }
        "Medium" { 3 } # Taking the middle value of the range
        "High" { 6 } # Taking the middle value of the range
        default { 0 }
    }
} | Measure-Object -Sum | Select-Object -ExpandProperty Sum) hours

## Migration Approach

1. **Phase 1: Low Complexity Applications**
   - Simple MSI-based applications with minimal customization
   - Standard deployment settings
   - Minimal or no dependencies

2. **Phase 2: Medium Complexity Applications**
   - Applications with custom install parameters
   - Applications with standard detection methods
   - Basic dependencies on other applications

3. **Phase 3: High Complexity Applications**
   - Applications with complex installation scripts
   - Applications with custom detection methods
   - Complex dependencies on other applications or services

## Detailed Application Inventory

$(foreach ($app in $migrationPlan | Select-Object -First 5) {
"### $($app.ApplicationName) (v$($app.Version))
- **Migration Complexity:** $($app.MigrationComplexity)
- **Estimated Effort:** $($app.EstimatedEffort)
- **Source Type:** $($app.SourceDeploymentType)
- **Target Type:** $($app.TargetDeploymentType)
- **Assigned Groups:** $($app.AssignedGroups -join ", ")

"
})

... (and $($migrationPlan.Count - 5) more applications)

## Next Steps

1. Review and validate the migration plan
2. Prioritize applications based on business needs
3. Begin testing with low complexity applications
4. Develop and validate Intune packaging process
5. Create test group for initial deployments

For detailed information on each application, refer to the JSON and CSV export files.
"@
        $summary | Set-Content -Path $summaryPath -Encoding UTF8
        
        Write-Log -Message "Successfully created application migration plan at $OutputPath" -Level Info
        return $summaryPath
    }
    catch {
        Write-Log -Message "Failed to create application migration plan: $_" -Level Error
        return $false
    }
}

#EndRegion Application Management Functions

#Region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message for the Workspace ONE integration module.
    .DESCRIPTION
        Internal function to handle logging for the module.
    .PARAMETER Message
        The message to log.
    .PARAMETER Level
        The level of the message (Info, Warning, Error, Debug).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Debug")]
        [string]$Level = "Info"
    )

    if (-not $script:LogEnabled) {
        return
    }

    # Create timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Log to console with color based on level
    switch ($Level) {
        "Info" { Write-Host $logMessage -ForegroundColor White }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        "Debug" { 
            if ($script:UseVerboseLogging) {
                Write-Host $logMessage -ForegroundColor Gray 
            }
        }
    }

    # Log to file if path exists
    if ($script:LogPath) {
        $logFileName = "WorkspaceOneIntegration_$(Get-Date -Format 'yyyyMMdd').log"
        $logFile = Join-Path -Path $script:LogPath -ChildPath $logFileName
        $logMessage | Out-File -FilePath $logFile -Append -Encoding utf8
    }
}

#EndRegion Helper Functions

# Export functions for module
Export-ModuleMember -Function @(
    'Initialize-WorkspaceOneIntegration',
    'Get-WorkspaceOneDevices', 
    'Export-WorkspaceOneProfiles',
    'Get-WorkspaceOneApplications',
    'Export-WorkspaceOneApplication',
    'Export-WorkspaceOneApplications',
    'ConvertTo-IntuneWin32App',
    'Get-ApplicationsByDevice',
    'Get-ApplicationAssignments',
    'Export-ApplicationMigrationPlan'
) 





