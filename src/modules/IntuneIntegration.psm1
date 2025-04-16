################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Initializes the Intune integration module.                                                                            #
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
    This module provides functions to interact with Microsoft Intune via Graph API
    for device enrollment, profile import, and application deployment.
.NOTES
    File Name  : IntuneIntegration.psm1
    Author     : Workspace ONE to Intune Migration Team
    Version    : 1.0.0
    Requires   : PowerShell 5.1 or later
                Microsoft.Graph.Intune module
                Microsoft.Graph.Authentication module
#>

#Region Module Variables
# Module-level variables
$script:AuthToken = $null
$script:GraphEndpoint = "https://graph.microsoft.com/beta"
$script:LogEnabled = $true
$script:LogPath = "$env:ProgramData\WS1_Migration\Logs"
$script:UseVerboseLogging = $false
#EndRegion

#Region Module Functions

function Initialize-IntuneIntegration {
    <#
    .SYNOPSIS
        Initializes the Intune integration module.
    .DESCRIPTION
        Sets up the connection to Microsoft Graph API for Intune operations.
    .PARAMETER TenantId
        The Azure AD tenant ID.
    .PARAMETER ClientId
        The application (client) ID for authentication.
    .PARAMETER ClientSecret
        The client secret for authentication.
    .PARAMETER Credential
        PSCredential object containing admin credentials.
    .PARAMETER LogPath
        Path to store log files.
    .PARAMETER EnableVerboseLogging
        Enable detailed logging for API operations.
    .EXAMPLE
        Initialize-IntuneIntegration -TenantId "00000000-0000-0000-0000-000000000000" -ClientId "11111111-1111-1111-1111-111111111111" -ClientSecret $secret
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [securestring]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "$env:ProgramData\WS1_Migration\Logs",

        [Parameter(Mandatory = $false)]
        [switch]$EnableVerboseLogging
    )

    # Set module variables
    $script:LogPath = $LogPath
    $script:UseVerboseLogging = $EnableVerboseLogging

    # Ensure log directory exists
    if (-not (Test-Path -Path $script:LogPath)) {
        New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
    }

    Write-Log -Message "Initializing Intune integration" -Level Info

    # Check for required modules
    $requiredModules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Intune")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Write-Log -Message "Required module $module is not installed. Installing..." -Level Warning
            try {
                Install-Module -Name $module -Scope CurrentUser -Force
                Import-Module -Name $module -Force
            }
            catch {
                Write-Log -Message ('Failed to install required module {0}: {1}' -f $module, $_) -Level Error
                return $false
            }
        }
        else {
            Import-Module -Name $module -Force
        }
    }

    # Authenticate to Microsoft Graph
    try {
        Write-Log -Message "Authenticating to Microsoft Graph API" -Level Info

        # Determine authentication method
        if ($ClientId -and $ClientSecret) {
            # App-only authentication
            Write-Log -Message "Using application authentication" -Level Info
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        }
        elseif ($Credential) {
            # User credential authentication
            Write-Log -Message "Using user credential authentication" -Level Info
            Connect-MgGraph -TenantId $TenantId -Credential $Credential
        }
        else {
            # Interactive authentication
            Write-Log -Message "Using interactive authentication" -Level Info
            Connect-MgGraph -TenantId $TenantId -Scopes "DeviceManagementApps.ReadWrite.All", "DeviceManagementConfiguration.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All"
        }

        # Verify connection
        try {
            $organization = Invoke-MgGraphRequest -Uri "$script:GraphEndpoint/organization" -Method GET
            Write-Log -Message "Successfully authenticated to Microsoft Graph API for tenant: $($organization.value[0].displayName)" -Level Info
            return $true
        }
        catch {
            Write-Log -Message "Failed to verify Microsoft Graph API connection: $_" -Level Error
            return $false
        }
    }
    catch {
        Write-Log -Message "Failed to authenticate to Microsoft Graph API: $_" -Level Error
        return $false
    }
}

function Get-IntuneDevices {
    <#
    .SYNOPSIS
        Retrieves devices from Intune.
    .DESCRIPTION
        Gets managed device information from Intune.
    .PARAMETER Filter
        Optional filter to limit devices returned.
    .EXAMPLE
        Get-IntuneDevices -Filter "contains(operatingSystem, 'Windows')"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    try {
        Write-Log -Message "Retrieving devices from Intune" -Level Info
        
        $uri = "$script:GraphEndpoint/deviceManagement/managedDevices"
        if ($Filter) {
            $uri += "?`$filter=$Filter"
        }
        
        $devices = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        Write-Log -Message "Successfully retrieved $($devices.value.Count) devices" -Level Info
        return $devices.value
    }
    catch {
        Write-Log -Message "Failed to retrieve devices from Intune: $_" -Level Error
        return $null
    }
}

function Import-IntuneDeviceConfigurationProfile {
    <#
    .SYNOPSIS
        Imports a device configuration profile into Intune.
    .DESCRIPTION
        Creates a new device configuration profile in Intune based on provided settings.
    .PARAMETER ProfileName
        Name of the profile to create.
    .PARAMETER Description
        Description of the profile.
    .PARAMETER PlatformType
        Platform type (e.g., Windows10, iOS, Android).
    .PARAMETER Settings
        Hashtable containing the profile settings.
    .EXAMPLE
        Import-IntuneDeviceConfigurationProfile -ProfileName "Windows10-Security" -Description "Security settings for Windows 10 devices" -PlatformType "Windows10" -Settings $settings
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $true)]
        [ValidateSet("Windows10", "iOS", "Android")]
        [string]$PlatformType,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    try {
        Write-Log -Message "Importing device configuration profile '$ProfileName' for platform $PlatformType" -Level Info
        
        # Create profile body based on platform type
        $profileBody = @{
            "@odata.type" = "#microsoft.graph.windows10GeneralConfiguration"
            displayName = $ProfileName
            description = $Description
        }
        
        # Set profile type based on platform
        switch ($PlatformType) {
            "Windows10" {
                $profileBody["@odata.type"] = "#microsoft.graph.windows10GeneralConfiguration"
            }
            "iOS" {
                $profileBody["@odata.type"] = "#microsoft.graph.iosGeneralDeviceConfiguration"
            }
            "Android" {
                $profileBody["@odata.type"] = "#microsoft.graph.androidDeviceOwnerGeneralDeviceConfiguration"
            }
        }
        
        # Add settings to profile body
        foreach ($key in $Settings.Keys) {
            $profileBody[$key] = $Settings[$key]
        }
        
        # Convert to JSON
        $profileJson = ConvertTo-Json -InputObject $profileBody -Depth 20
        
        # Create profile
        $uri = "$script:GraphEndpoint/deviceManagement/deviceConfigurations"
        $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $profileJson -ContentType "application/json"
        
        Write-Log -Message "Successfully created device configuration profile with ID: $($response.id)" -Level Info
        return $response
    }
    catch {
        Write-Log -Message "Failed to create device configuration profile: $_" -Level Error
        return $null
    }
}

# Helper function
function Test-MgGraph {
    <#
    .SYNOPSIS
        Tests if connected to Microsoft Graph API.
    .DESCRIPTION
        Verifies if the current session is authenticated to Microsoft Graph API.
    #>
    try {
        $context = Get-MgContext
        return ($null -ne $context)
    }
    catch {
        return $false
    }
}

#Region Application Deployment Functions

function Get-IntuneApplications {
    <#
    .SYNOPSIS
        Retrieves applications from Intune.
    .DESCRIPTION
        Gets mobile applications defined in Intune.
    .PARAMETER Filter
        Optional filter to limit applications returned.
    .EXAMPLE
        Get-IntuneApplications -Filter "contains(displayName, 'Office')"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    try {
        Write-Log -Message "Retrieving applications from Intune" -Level Info
        
        $uri = "$script:GraphEndpoint/deviceAppManagement/mobileApps"
        if ($Filter) {
            $uri += "?`$filter=$Filter"
        }
        
        $apps = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        Write-Log -Message "Successfully retrieved $($apps.value.Count) applications" -Level Info
        return $apps.value
    }
    catch {
        Write-Log -Message "Failed to retrieve applications from Intune: $_" -Level Error
        return $null
    }
}

function New-IntuneWin32App {
    <#
    .SYNOPSIS
        Creates a new Win32 application in Intune.
    .DESCRIPTION
        Creates a new Win32 application in Intune from an .intunewin file.
    .PARAMETER DisplayName
        Display name of the application.
    .PARAMETER Description
        Description of the application.
    .PARAMETER Publisher
        Publisher of the application.
    .PARAMETER FilePath
        Path to the .intunewin file.
    .PARAMETER InstallCommandLine
        Command line to install the application.
    .PARAMETER UninstallCommandLine
        Command line to uninstall the application.
    .PARAMETER DetectionRules
        Detection rules to determine if the application is installed.
    .PARAMETER RequirementRule
        Requirement rules for the application.
    .PARAMETER AppCategory
        Application category.
    .PARAMETER IconPath
        Path to an icon file for the application.
    .EXAMPLE
        New-IntuneWin32App -DisplayName "Adobe Reader DC" -Description "PDF Reader" -Publisher "Adobe" -FilePath "C:\Temp\AdobeReaderDC.intunewin" -InstallCommandLine "install.cmd" -UninstallCommandLine "uninstall.cmd" -DetectionRules $detectionRules -RequirementRule $requirementRule
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string]$Publisher = "",

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$InstallCommandLine,

        [Parameter(Mandatory = $true)]
        [string]$UninstallCommandLine,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DetectionRules,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$RequirementRule,

        [Parameter(Mandatory = $false)]
        [string]$AppCategory = "",

        [Parameter(Mandatory = $false)]
        [string]$IconPath = ""
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    # Validate file path
    if (-not (Test-Path -Path $FilePath)) {
        Write-Log -Message "IntuneWin file not found at path: $FilePath" -Level Error
        return $null
    }

    try {
        Write-Log -Message "Creating Win32 application '$DisplayName' in Intune" -Level Info
        
        # Create Win32 app
        Write-Log -Message "Creating Win32 app..." -Level Info
        $win32AppBody = @{
            "@odata.type" = "#microsoft.graph.win32LobApp"
            displayName = $DisplayName
            description = $Description
            publisher = $Publisher
            isFeatured = $false
            installCommandLine = $InstallCommandLine
            uninstallCommandLine = $UninstallCommandLine
            installExperience = @{
                runAsAccount = "system"
                deviceRestartBehavior = "basedOnReturnCode"
            }
        }

        if ($AppCategory) {
            $win32AppBody["category"] = $AppCategory
        }
        
        # Convert to JSON
        $win32AppJson = ConvertTo-Json -InputObject $win32AppBody -Depth 20
        
        # Create application
        $uri = "$script:GraphEndpoint/deviceAppManagement/mobileApps"
        $app = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $win32AppJson -ContentType "application/json"
        
        # Add icon if specified
        if ($IconPath -and (Test-Path -Path $IconPath)) {
            Write-Log -Message "Adding icon to Win32 app..." -Level Info
            $iconUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/icon"
            $iconContent = [System.IO.File]::ReadAllBytes($IconPath)
            $iconContentBase64 = [System.Convert]::ToBase64String($iconContent)
            $iconBody = @{
                "value" = $iconContentBase64
            }
            $iconJson = ConvertTo-Json -InputObject $iconBody
            Invoke-MgGraphRequest -Uri $iconUri -Method POST -Body $iconJson -ContentType "application/json"
        }
        
        # Upload the .intunewin file
        Write-Log -Message "Uploading IntuneWin file..." -Level Info
        $contentVersionUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/contentVersions"
        $contentVersion = Invoke-MgGraphRequest -Uri $contentVersionUri -Method POST -ContentType "application/json"
        
        # Create a file upload session
        $contentFileUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/contentVersions/$($contentVersion.id)/files"
        $fileName = Split-Path -Path $FilePath -Leaf
        $size = (Get-Item -Path $FilePath).Length
        $fileBody = @{
            "@odata.type" = "#microsoft.graph.mobileAppContentFile"
            name = $fileName
            size = $size
            sizeEncrypted = $size
            manifest = $null
            isDependency = $false
        }
        $fileBodyJson = ConvertTo-Json -InputObject $fileBody
        $contentFile = Invoke-MgGraphRequest -Uri $contentFileUri -Method POST -Body $fileBodyJson -ContentType "application/json"
        
        # Get file upload URL
        $uploadUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/contentVersions/$($contentVersion.id)/files/$($contentFile.id)/getUploadUrl"
        $uploadUrl = Invoke-MgGraphRequest -Uri $uploadUri -Method POST -ContentType "application/json"
        
        # Upload the file
        try {
            Write-Log -Message "Uploading file content..." -Level Info
            $fileContent = [System.IO.File]::ReadAllBytes($FilePath)
            $uploadResponse = Invoke-RestMethod -Uri $uploadUrl.uploadUrl -Method PUT -Body $fileContent -ContentType "application/octet-stream"
            
            # Commit the file
            $commitUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/contentVersions/$($contentVersion.id)/files/$($contentFile.id)/commit"
            $fileEncryptionInfo = @{
                fileEncryptionInfo = @{
                    encryptionKey = $null
                    macKey = $null
                    initializationVector = $null
                    mac = $null
                    profileIdentifier = "ProfileVersion1"
                    fileDigest = $null
                    fileDigestAlgorithm = "SHA256"
                }
            }
            $fileEncryptionInfoJson = ConvertTo-Json -InputObject $fileEncryptionInfo
            Invoke-MgGraphRequest -Uri $commitUri -Method POST -Body $fileEncryptionInfoJson -ContentType "application/json"
            
            # Poll for file upload status
            $fileStatusUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/contentVersions/$($contentVersion.id)/files/$($contentFile.id)"
            $attempts = 0
            do {
                $attempts++
                Start-Sleep -Seconds 5
                $fileStatus = Invoke-MgGraphRequest -Uri $fileStatusUri -Method GET
                Write-Log -Message "File upload status: $($fileStatus.uploadState)" -Level Info
            } until (($fileStatus.uploadState -eq "commitFileSuccess") -or ($attempts -ge 10))
        }
        catch {
            Write-Log -Message "Error uploading file: $_" -Level Error
            return $null
        }
        
        # Commit the content version
        Write-Log -Message "Committing content version..." -Level Info
        $commitContentUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/contentVersions/$($contentVersion.id)/commit"
        Invoke-MgGraphRequest -Uri $commitContentUri -Method POST -ContentType "application/json"
        
        # Add detection rules
        Write-Log -Message "Adding detection rules..." -Level Info
        $detectionRulesUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/detectionRules"
        $detectionRulesJson = ConvertTo-Json -InputObject $DetectionRules -Depth 20
        Invoke-MgGraphRequest -Uri $detectionRulesUri -Method POST -Body $detectionRulesJson -ContentType "application/json"
        
        # Add requirement rules if specified
        if ($RequirementRule) {
            Write-Log -Message "Adding requirement rules..." -Level Info
            $requirementRulesUri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$($app.id)/microsoft.graph.win32LobApp/requirementRules"
            $requirementRuleJson = ConvertTo-Json -InputObject $RequirementRule -Depth 20
            Invoke-MgGraphRequest -Uri $requirementRulesUri -Method POST -Body $requirementRuleJson -ContentType "application/json"
        }
        
        Write-Log -Message "Successfully created Win32 application with ID: $($app.id)" -Level Info
        return $app
    }
    catch {
        Write-Log -Message "Failed to create Win32 application: $_" -Level Error
        return $null
    }
}

function Import-IntuneApplication {
    <#
    .SYNOPSIS
        Imports an application into Intune from a migration package.
    .DESCRIPTION
        Processes a migration package created by Export-WorkspaceOneApplication and imports it into Intune.
    .PARAMETER PackagePath
        Path to the application migration package.
    .PARAMETER IntuneWinAppUtilPath
        Path to the Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe).
    .EXAMPLE
        Import-IntuneApplication -PackagePath "C:\Temp\Apps\APP-001" -IntuneWinAppUtilPath "C:\Tools\IntuneWinAppUtil.exe"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$IntuneWinAppUtilPath
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    # Validate paths
    if (-not (Test-Path -Path $PackagePath)) {
        Write-Log -Message "Package path not found: $PackagePath" -Level Error
        return $null
    }

    if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
        Write-Log -Message "IntuneWinAppUtil.exe not found at path: $IntuneWinAppUtilPath" -Level Error
        return $null
    }

    try {
        Write-Log -Message "Importing application from package: $PackagePath" -Level Info
        
        # Load metadata
        $metadataPath = Join-Path -Path $PackagePath -ChildPath "metadata.json"
        if (-not (Test-Path -Path $metadataPath)) {
            Write-Log -Message "Metadata file not found at path: $metadataPath" -Level Error
            return $null
        }
        
        $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
        
        # Check for Intune definition
        $intuneDefinitionPath = Join-Path -Path $PackagePath -ChildPath "intune_app_definition.json"
        if (Test-Path -Path $intuneDefinitionPath) {
            $intuneDefinition = Get-Content -Path $intuneDefinitionPath -Raw | ConvertFrom-Json
        }
        else {
            $intuneDefinition = $null
        }
        
        # Find .intunewin file
        $intunewinFile = Get-ChildItem -Path $PackagePath -Filter "*.intunewin" | Select-Object -First 1
        if (-not $intunewinFile) {
            # Create .intunewin file
            Write-Log -Message "No .intunewin file found. Creating..." -Level Info
            
            $setupFolder = Join-Path -Path $PackagePath -ChildPath "setup"
            if (-not (Test-Path -Path $setupFolder)) {
                Write-Log -Message "Setup folder not found at path: $setupFolder" -Level Error
                return $null
            }
            
            $installerFile = $metadata.Files[0].FileName
            $installerPath = Join-Path -Path $setupFolder -ChildPath $installerFile
            if (-not (Test-Path -Path $installerPath)) {
                Write-Log -Message "Installer file not found at path: $installerPath" -Level Error
                return $null
            }
            
            # Create .intunewin file
            $intunewinFilePath = Join-Path -Path $PackagePath -ChildPath "$($metadata.ApplicationName.Replace(' ', '_')).intunewin"
            
            # Run IntuneWinAppUtil.exe
            $intunewinProcess = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList "-c `"$setupFolder`" -s `"$installerFile`" -o `"$PackagePath`"" -NoNewWindow -PassThru -Wait
            
            if ($intunewinProcess.ExitCode -ne 0) {
                Write-Log -Message "Failed to create .intunewin file. Exit code: $($intunewinProcess.ExitCode)" -Level Error
                return $null
            }
            
            $intunewinFile = Get-ChildItem -Path $PackagePath -Filter "*.intunewin" | Select-Object -First 1
            if (-not $intunewinFile) {
                Write-Log -Message "Failed to create .intunewin file" -Level Error
                return $null
            }
        }
        
        # Create detection rules
        $detectionRulePath = Join-Path -Path $PackagePath -ChildPath "detect.ps1"
        if (Test-Path -Path $detectionRulePath) {
            $detectionScript = Get-Content -Path $detectionRulePath -Raw
            $detectionRules = @{
                "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
                enforceSignatureCheck = $false
                runAs32Bit = $false
                scriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScript))
            }
        }
        else {
            # Create default file-based detection rule
            $detectionRules = @{
                "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                path = $metadata.InstallLocationPath ?? "C:\Program Files\$($metadata.ApplicationName)"
                fileOrFolderName = $metadata.Files[0].FileName ?? "*.*"
                detectionType = "exists"
                operator = "notConfigured"
            }
        }
        
        # Create requirement rule for OS version
        $requirementRule = @{
            "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRequirement"
            displayName = "Operating System Requirement"
            requirementName = "OS"
            operator = "equal"
            detectionValue = "true"
            runAs32Bit = $false
            enforceSignatureCheck = $false
            runAsAccount = "system"
            scriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(@"
# Check if OS is compatible (Windows 10 or later)
`$osInfo = Get-WmiObject -Class Win32_OperatingSystem
`$osVersion = [System.Version](`$osInfo.Version)
if (`$osVersion.Major -ge 10) {
    Write-Output "true"
    exit 0
} else {
    Write-Output "false"
    exit 1
}
"@))
        }
        
        # Create Win32 app
        $params = @{
            DisplayName = $metadata.ApplicationName
            Description = $metadata.Description ?? "Migrated from Workspace ONE"
            Publisher = $metadata.Developer ?? "Unknown"
            FilePath = $intunewinFile.FullName
            InstallCommandLine = $intuneDefinition?.installCommandLine ?? "install.cmd"
            UninstallCommandLine = $intuneDefinition?.uninstallCommandLine ?? "uninstall.cmd"
            DetectionRules = $detectionRules
            RequirementRule = $requirementRule
            AppCategory = $metadata.Category ?? ""
        }
        
        # Check for icon
        $iconPath = Join-Path -Path $PackagePath -ChildPath "icon.png"
        if (Test-Path -Path $iconPath) {
            $params["IconPath"] = $iconPath
        }
        
        # Create the application
        $app = New-IntuneWin32App @params
        
        if ($null -eq $app) {
            Write-Log -Message "Failed to create application in Intune" -Level Error
            return $null
        }
        
        # Assign to groups if specified
        if ($metadata.AssignedGroups -and $metadata.AssignedGroups.Count -gt 0) {
            Write-Log -Message "Application assignment would be done here in a production environment" -Level Info
            # In a real implementation, this would create assignments using the AssignedGroups from metadata
        }
        
        Write-Log -Message "Successfully imported application $($metadata.ApplicationName) into Intune" -Level Info
        return $app
    }
    catch {
        Write-Log -Message "Failed to import application: $_" -Level Error
        return $null
    }
}

function Import-IntuneApplications {
    <#
    .SYNOPSIS
        Imports multiple applications into Intune from a migration export.
    .DESCRIPTION
        Processes application migration exports from Workspace ONE and imports them into Intune.
    .PARAMETER ExportPath
        Path to the application exports folder.
    .PARAMETER IntuneWinAppUtilPath
        Path to the Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe).
    .EXAMPLE
        Import-IntuneApplications -ExportPath "C:\Temp\Apps" -IntuneWinAppUtilPath "C:\Tools\IntuneWinAppUtil.exe"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExportPath,

        [Parameter(Mandatory = $true)]
        [string]$IntuneWinAppUtilPath
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    # Validate paths
    if (-not (Test-Path -Path $ExportPath)) {
        Write-Log -Message "Export path not found: $ExportPath" -Level Error
        return $null
    }

    if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
        Write-Log -Message "IntuneWinAppUtil.exe not found at path: $IntuneWinAppUtilPath" -Level Error
        return $null
    }

    try {
        Write-Log -Message "Importing applications from export: $ExportPath" -Level Info
        
        # Check for summary file
        $summaryPath = Join-Path -Path $ExportPath -ChildPath "export_summary.json"
        if (Test-Path -Path $summaryPath) {
            $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json
        }
        else {
            # No summary file, look for application folders directly
            $appFolders = Get-ChildItem -Path $ExportPath -Directory | Where-Object { $_.Name -match "^APP-" }
            if ($appFolders.Count -eq 0) {
                Write-Log -Message "No application folders found in export path" -Level Error
                return $null
            }
            
            $summary = $appFolders | ForEach-Object {
                [PSCustomObject]@{
                    ApplicationId = $_.Name
                    ApplicationName = $_.Name
                    ExportPath = $_.FullName
                    ExportSuccess = $true
                }
            }
        }
        
        $results = @()
        foreach ($app in $summary) {
            if (-not $app.ExportSuccess) {
                Write-Log -Message "Skipping application $($app.ApplicationName) due to failed export" -Level Warning
                continue
            }
            
            $appPath = $app.ExportPath
            if (-not (Test-Path -Path $appPath)) {
                $appPath = Join-Path -Path $ExportPath -ChildPath $app.ApplicationId
                if (-not (Test-Path -Path $appPath)) {
                    Write-Log -Message "Application path not found for $($app.ApplicationName)" -Level Warning
                    continue
                }
            }
            
            Write-Log -Message "Importing application: $($app.ApplicationName)" -Level Info
            $importResult = Import-IntuneApplication -PackagePath $appPath -IntuneWinAppUtilPath $IntuneWinAppUtilPath
            
            $results += [PSCustomObject]@{
                ApplicationId = $app.ApplicationId
                ApplicationName = $app.ApplicationName
                IntuneAppId = $importResult?.id
                ImportSuccess = ($null -ne $importResult)
            }
        }
        
        # Create import summary
        $importSummaryPath = Join-Path -Path $ExportPath -ChildPath "intune_import_summary.json"
        $results | ConvertTo-Json -Depth 5 | Set-Content -Path $importSummaryPath -Encoding UTF8
        
        $importedCount = ($results | Where-Object { $_.ImportSuccess } | Measure-Object).Count
        $totalCount = $results.Count
        
        Write-Log -Message "Successfully imported $importedCount out of $totalCount applications into Intune" -Level Info
        return $results
    }
    catch {
        Write-Log -Message "Failed to import applications: $_" -Level Error
        return $null
    }
}

function New-IntuneAppAssignment {
    <#
    .SYNOPSIS
        Creates an application assignment in Intune.
    .DESCRIPTION
        Assigns an Intune application to Azure AD groups.
    .PARAMETER AppId
        ID of the application to assign.
    .PARAMETER GroupId
        ID of the Azure AD group to assign the application to.
    .PARAMETER Intent
        Assignment intent (Required, Available, Uninstall).
    .PARAMETER IncludeExclude
        Whether this is an include or exclude assignment.
    .EXAMPLE
        New-IntuneAppAssignment -AppId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321" -Intent "required" -IncludeExclude "include"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("required", "available", "uninstall")]
        [string]$Intent,

        [Parameter(Mandatory = $false)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExclude = "include"
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $false
    }

    try {
        Write-Log -Message "Creating assignment for application $AppId to group $GroupId with intent $Intent" -Level Info
        
        $uri = "$script:GraphEndpoint/deviceAppManagement/mobileApps/$AppId/assignments"
        
        $assignmentBody = @{
            "@odata.type" = "#microsoft.graph.mobileAppAssignment"
            intent = $Intent
            target = @{
                "@odata.type" = $IncludeExclude -eq "include" ? "#microsoft.graph.groupAssignmentTarget" : "#microsoft.graph.exclusionGroupAssignmentTarget"
                groupId = $GroupId
            }
            settings = $null
        }
        
        $assignmentJson = ConvertTo-Json -InputObject $assignmentBody -Depth 5
        $assignment = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $assignmentJson -ContentType "application/json"
        
        Write-Log -Message "Successfully created application assignment" -Level Info
        return $assignment
    }
    catch {
        Write-Log -Message "Failed to create application assignment: $_" -Level Error
        return $false
    }
}

function Import-ApplicationAssignments {
    <#
    .SYNOPSIS
        Imports application assignments from WS1 to Intune.
    .DESCRIPTION
        Maps Workspace ONE application assignments to Intune groups and creates assignments.
    .PARAMETER AssignmentsPath
        Path to the assignments data file.
    .PARAMETER GroupMappingPath
        Path to the group mapping file.
    .EXAMPLE
        Import-ApplicationAssignments -AssignmentsPath "C:\Temp\app_assignments.json" -GroupMappingPath "C:\Temp\group_mapping.json"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AssignmentsPath,

        [Parameter(Mandatory = $true)]
        [string]$GroupMappingPath
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $null
    }

    # Validate paths
    if (-not (Test-Path -Path $AssignmentsPath)) {
        Write-Log -Message "Assignments path not found: $AssignmentsPath" -Level Error
        return $null
    }

    if (-not (Test-Path -Path $GroupMappingPath)) {
        Write-Log -Message "Group mapping path not found: $GroupMappingPath" -Level Error
        return $null
    }

    try {
        Write-Log -Message "Importing application assignments" -Level Info
        
        # Load assignments data
        $assignments = Get-Content -Path $AssignmentsPath -Raw | ConvertFrom-Json
        
        # Load group mapping
        $groupMapping = Get-Content -Path $GroupMappingPath -Raw | ConvertFrom-Json
        
        # Load application mapping
        $appMappingPath = Split-Path -Path $AssignmentsPath -Parent
        $appMappingPath = Join-Path -Path $appMappingPath -ChildPath "intune_import_summary.json"
        
        if (Test-Path -Path $appMappingPath) {
            $appMapping = Get-Content -Path $appMappingPath -Raw | ConvertFrom-Json
        }
        else {
            Write-Log -Message "Application mapping file not found. Cannot continue." -Level Error
            return $null
        }
        
        $results = @()
        foreach ($app in $assignments) {
            # Find the Intune app ID
            $intuneApp = $appMapping | Where-Object { $_.ApplicationId -eq $app.ApplicationId }
            if (-not $intuneApp -or -not $intuneApp.ImportSuccess) {
                Write-Log -Message "Skipping assignments for $($app.ApplicationName): app not found in Intune or import failed" -Level Warning
                continue
            }
            
            foreach ($group in $app.AssignmentGroups) {
                # Find the Azure AD group ID
                $azureADGroup = $groupMapping | Where-Object { $_.SourceGroupName -eq $group.GroupName }
                if (-not $azureADGroup) {
                    Write-Log -Message "Skipping assignment for group $($group.GroupName): no mapping found" -Level Warning
                    continue
                }
                
                # Determine intent
                $intent = switch ($group.DeploymentMode) {
                    "Required" { "required" }
                    "Available" { "available" }
                    default { "available" }
                }
                
                # Create assignment
                $assignmentResult = New-IntuneAppAssignment -AppId $intuneApp.IntuneAppId -GroupId $azureADGroup.TargetGroupId -Intent $intent
                
                $results += [PSCustomObject]@{
                    ApplicationName = $app.ApplicationName
                    GroupName = $group.GroupName
                    TargetGroupName = $azureADGroup.TargetGroupName
                    Intent = $intent
                    Success = ($null -ne $assignmentResult)
                }
            }
        }
        
        # Create assignment summary
        $summaryPath = Join-Path -Path (Split-Path -Path $AssignmentsPath -Parent) -ChildPath "assignment_results.json"
        $results | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8
        
        $successCount = ($results | Where-Object { $_.Success } | Measure-Object).Count
        $totalCount = $results.Count
        
        Write-Log -Message "Successfully created $successCount out of $totalCount application assignments in Intune" -Level Info
        return $results
    }
    catch {
        Write-Log -Message "Failed to import application assignments: $_" -Level Error
        return $null
    }
}

function Sync-DeviceAppInstallStatus {
    <#
    .SYNOPSIS
        Synchronizes app installation status on devices.
    .DESCRIPTION
        Triggers a sync of app installation status on devices enrolled in Intune.
    .PARAMETER DeviceId
        ID of the device to sync (optional, sync all devices if not specified).
    .EXAMPLE
        Sync-DeviceAppInstallStatus -DeviceId "12345678-1234-1234-1234-123456789012"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DeviceId
    )

    # Validate authentication
    if (-not (Test-MgGraph)) {
        Write-Log -Message "Not authenticated to Microsoft Graph. Call Initialize-IntuneIntegration first." -Level Error
        return $false
    }

    try {
        if ($DeviceId) {
            Write-Log -Message "Syncing app installation status for device $DeviceId" -Level Info
            $uri = "$script:GraphEndpoint/deviceManagement/managedDevices/$DeviceId/syncDevice"
            Invoke-MgGraphRequest -Uri $uri -Method POST -ContentType "application/json"
            Write-Log -Message "Successfully triggered sync for device $DeviceId" -Level Info
            return $true
        }
        else {
            Write-Log -Message "Syncing app installation status for all devices" -Level Info
            $devicesUri = "$script:GraphEndpoint/deviceManagement/managedDevices"
            $devices = Invoke-MgGraphRequest -Uri $devicesUri -Method GET
            
            $syncedCount = 0
            foreach ($device in $devices.value) {
                try {
                    $uri = "$script:GraphEndpoint/deviceManagement/managedDevices/$($device.id)/syncDevice"
                    Invoke-MgGraphRequest -Uri $uri -Method POST -ContentType "application/json"
                    $syncedCount++
                }
                catch {
                    Write-Log -Message "Failed to sync device $($device.id): $_" -Level Warning
                }
            }
            
            Write-Log -Message "Successfully triggered sync for $syncedCount devices" -Level Info
            return $true
        }
    }
    catch {
        Write-Log -Message "Failed to sync app installation status: $_" -Level Error
        return $false
    }
}

#EndRegion Application Deployment Functions

#Region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message for the Intune integration module.
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
        $logFileName = "IntuneIntegration_$(Get-Date -Format 'yyyyMMdd').log"
        $logFile = Join-Path -Path $script:LogPath -ChildPath $logFileName
        $logMessage | Out-File -FilePath $logFile -Append -Encoding utf8
    }
}

#EndRegion Helper Functions

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-IntuneIntegration',
    'Get-IntuneDevices',
    'Import-IntuneDeviceConfigurationProfile',
    'Get-IntuneApplications',
    'New-IntuneWin32App',
    'Import-IntuneApplication',
    'Import-IntuneApplications',
    'New-IntuneAppAssignment',
    'Import-ApplicationAssignments',
    'Sync-DeviceAppInstallStatus'
) 





