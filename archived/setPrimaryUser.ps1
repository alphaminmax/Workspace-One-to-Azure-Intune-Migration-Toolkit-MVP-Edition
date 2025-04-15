<# SETPRIMARYUSER.PS1
Synopsis
SetPrimaryUser.ps1 is run 60 minutes after the migration completes.
DESCRIPTION
This script is used to update the device group tag in Entra ID and set the primary user in Intune. We stagger it to allow for replication.
.\postMigrate.ps1
.OWNER
Michael Weisberg
.CONTRIBUTORS

#>

$ErrorActionPreference = "SilentlyContinue"

# Import logging module
$loggingModulePath = "$PSScriptRoot\LoggingModule.psm1"
if (Test-Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
} else {
    Write-Error "Logging module not found at $loggingModulePath"
    Exit 1
}
# CMDLET FUNCTIONS

# set log function
function log()
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$message
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss tt"
    Write-Output "$ts $message"
}

# CMDLET FUNCTIONS

# START SCRIPT FUNCTIONS

# get json settings
function getSettingsJSON()
{
    param(
        [string]$json = "settings.json"
    )
    $global:settings = Get-Content -Path "$($PSScriptRoot)\$($json)" | ConvertFrom-Json
    return $settings
}

# initialize script
function initializeScript()
{
    Param(
        [string]$logPath = $settings.logPath,
        [string]$logName = "postMigrate.log",
        [string]$localPath = $settings.localPath
    )
    # Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
    Write-Log -Message "========== Starting .ps1 ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: <# SETPRIMARYUSER.PS1
Synopsis
SetPrimaryUser.ps1 is run 60 minutes after the migration completes.
DESCRIPTION
This script is used to update the device group tag in Entra ID and set the primary user in Intune. We stagger it to allow for replication.
.\postMigrate.ps1
.OWNER
Michael Weisberg
.CONTRIBUTORS

#>

$ErrorActionPreference = "SilentlyContinue"

# Import logging module
$loggingModulePath = "$PSScriptRoot\LoggingModule.psm1"
if (Test-Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
} else {
    Write-Error "Logging module not found at $loggingModulePath"
    Exit 1
}
# CMDLET FUNCTIONS

# set log function
function log()
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$message
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss tt"
    Write-Output "$ts $message"
}

# CMDLET FUNCTIONS

# START SCRIPT FUNCTIONS

# get json settings
function getSettingsJSON()
{
    param(
        [string]$json = "settings.json"
    )
    $global:settings = Get-Content -Path "$($PSScriptRoot)\$($json)" | ConvertFrom-Json
    return $settings
}

# initialize script
function initializeScript()
{
    Param(
        [string]$logPath = $settings.logPath,
        [string]$logName = "postMigrate.log",
        [string]$localPath = $settings.localPath
    )
    Start-Transcript -Path "$logPath\$logName" -Verbose
    Write-Log -Message "Initializing script..." -Level INFO
    if(!(Test-Path $localPath))
    {
        mkdir $localPath
        Write-Log -Message "Local path created: $localPath" -Level INFO
    }
    else
    {
        Write-Log -Message "Local path already exists: $localPath" -Level INFO
    }
    $global:localPath = $localPath
    $context = whoami
    Write-Log -Message "Running as $($context)" -Level INFO
    Write-Log -Message "Script initialized" -Level INFO
    return $localPath
}

# get device info
function getDeviceInfo()
{
    Param(
        [string]$hostname = $env:COMPUTERNAME,
        [string]$serialNumber = (Get-WmiObject -Class Win32_BIOS | Select-Object SerialNumber).SerialNumber
    )
    $global:deviceInfo = @{
        "hostname" = $hostname
        "serialNumber" = $serialNumber
    }
    foreach($key in $deviceInfo.Keys)
    {
        Write-Log -Message "$($key): $($deviceInfo[$key])" -Level INFO
    }
}

# authenticate to MS Graph
function msGraphAuthenticate()
{
    Param(
        [string]$tenant = $settings.targetTenant.tenantName,
        [string]$clientId = $settings.targetTenant.clientId,
        [string]$clientSecret = $settings.targetTenant.clientSecret
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")

    $body = "grant_type=client_credentials&scope=https://graph.microsoft.com/.default"
    $body += -join ("&client_id=" , $clientId, "&client_secret=", $clientSecret)

    $response = Invoke-RestMethod "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token" -Method 'POST' -Headers $headers -Body $body

    #Get Token form OAuth.
    $token = -join ("Bearer ", $response.access_token)

    #Reinstantiate headers.
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $token)
    $headers.Add("Content-Type", "application/json")
    Write-Log -Message "MS Graph Authenticated" -Level INFO
    $global:headers = $headers
}

# get user graph info
function getGraphInfo()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$serialNumber = $deviceInfo.serialNumber,
        [string]$intuneUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices",
        [string]$userUri = "https://graph.microsoft.com/beta/users",
        [string]$upn = (Get-ItemPropertyValue -Path $regKey -Name "UPN")
    )
    Write-Log -Message "Getting graph info..." -Level INFO
    $intuneObject = Invoke-RestMethod -Uri "$($intuneUri)?`$filter=contains(serialNumber,'$($serialNumber)')" -Headers $headers -Method Get
    if(($intuneObject.'@odata.count') -eq 1)
    {
        $global:intuneID = $intuneObject.value.id
        $global:aadDeviceID = $intuneObject.value.azureADDeviceId
        Write-Log -Message "Intune Device ID: $intuneID, Azure AD Device ID: $aadDeviceID, User ID: $userID" -Level INFO
    }
    else
    {
        Write-Log -Message "Intune object not found" -Level INFO
    }
    $userObject = Invoke-RestMethod -Uri "$userUri/$upn" -Headers $headers -Method Get
    if(![string]::IsNullOrEmpty($userObject.id))
    {
        $global:userID = $userObject.id
        Write-Log -Message "User ID: $userID" -Level INFO
    }
    else
    {
        Write-Log -Message "User object not found" -Level INFO
    }
}

# set primary user
function setPrimaryUser()
{
    Param(
        [string]$intuneID = $intuneID,
        [string]$userID = $userID,
        [string]$userUri = "https://graph.microsoft.com/beta/users/$userID",
        [string]$intuneDeviceRefUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneID/users/`$ref"
    )
    $id = "@odata.id"
    $JSON = @{ $id="$userUri" } | ConvertTo-Json

    Invoke-RestMethod -Uri $intuneDeviceRefUri -Headers $headers -Method Post -Body $JSON
    Write-Log -Message "Primary user for $intuneID set to $userID" -Level INFO
}

# update device group tag
function updateGroupTag()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$groupTag = (Get-ItemPropertyValue -Path $regKey -Name "GroupTag" -ErrorAction Ignore),
        [string]$aadDeviceID = $aadDeviceID,
        [string]$deviceUri = "https://graph.microsoft.com/beta/devices"
    )
    Write-Log -Message "Updating device group tag..." -Level INFO
    if([string]::IsNullOrEmpty($groupTag))
    {
        Write-Log -Message "Group tag not found- will not be used." -Level INFO
    }
    else
    {
        $aadObject = Invoke-RestMethod -Method Get -Uri "$($deviceUri)?`$filter=deviceId eq '$($aadDeviceId)'" -Headers $headers
        $physicalIds = $aadObject.value.physicalIds
        $deviceId = $aadObject.value.id
        $groupTag = "[OrderID]:$($groupTag)"
        $physicalIds += $groupTag

        $body = @{
            physicalIds = $physicalIds
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$deviceUri/$deviceId" -Method Patch -Headers $headers -Body $body
        Write-Log -Message "Device group tag updated to $groupTag" -Level INFO      
    }
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# get settings
try
{
    getSettingsJSON
    Write-Log -Message "Retrieved settings" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Settings not loaded: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# initialize script
try
{
    initializeScript
    Write-Log -Message "Script initialized" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Script not initialized: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}



# get device info
try
{
    getDeviceInfo
    Write-Log -Message "Device info retrieved" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Device info not retrieved: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# authenticate to MS Graph
try
{
    msGraphAuthenticate
    Write-Log -Message "MS Graph authenticated" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "MS Graph not authenticated: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# get graph info
try
{
    getGraphInfo
    Write-Log -Message "Graph info retrieved" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Graph info not retrieved: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# set primary user
try
{
    setPrimaryUser
    Write-Log -Message "Primary user set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Primary user not set: $message" -Level INFO
    Write-Log -Message "WARNING: Primary user not set- try manually setting in Intune" -Level INFO
}

# update device group tag
try
{
    updateGroupTag
    Write-Log -Message "Device group tag updated if applicable" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Device group tag not updated: $message" -Level INFO
    Write-Log -Message "WARNING: Device group tag not updated- try manually updating in Intune" -Level INFO
}



# END SCRIPT


# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript"
    Exit 1
}
    Write-Log -Message "Initializing script..." -Level INFO
    if(!(Test-Path $localPath))
    {
        mkdir $localPath
        Write-Log -Message "Local path created: $localPath" -Level INFO
    }
    else
    {
        Write-Log -Message "Local path already exists: $localPath" -Level INFO
    }
    $global:localPath = $localPath
    $context = whoami
    Write-Log -Message "Running as $($context)" -Level INFO
    Write-Log -Message "Script initialized" -Level INFO
    return $localPath
}

# get device info
function getDeviceInfo()
{
    Param(
        [string]$hostname = $env:COMPUTERNAME,
        [string]$serialNumber = (Get-WmiObject -Class Win32_BIOS | Select-Object SerialNumber).SerialNumber
    )
    $global:deviceInfo = @{
        "hostname" = $hostname
        "serialNumber" = $serialNumber
    }
    foreach($key in $deviceInfo.Keys)
    {
        Write-Log -Message "$($key): $($deviceInfo[$key])" -Level INFO
    }
}

# authenticate to MS Graph
function msGraphAuthenticate()
{
    Param(
        [string]$tenant = $settings.targetTenant.tenantName,
        [string]$clientId = $settings.targetTenant.clientId,
        [string]$clientSecret = $settings.targetTenant.clientSecret
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")

    $body = "grant_type=client_credentials&scope=https://graph.microsoft.com/.default"
    $body += -join ("&client_id=" , $clientId, "&client_secret=", $clientSecret)

    $response = Invoke-RestMethod "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token" -Method 'POST' -Headers $headers -Body $body

    #Get Token form OAuth.
    $token = -join ("Bearer ", $response.access_token)

    #Reinstantiate headers.
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $token)
    $headers.Add("Content-Type", "application/json")
    Write-Log -Message "MS Graph Authenticated" -Level INFO
    $global:headers = $headers
}

# get user graph info
function getGraphInfo()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$serialNumber = $deviceInfo.serialNumber,
        [string]$intuneUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices",
        [string]$userUri = "https://graph.microsoft.com/beta/users",
        [string]$upn = (Get-ItemPropertyValue -Path $regKey -Name "UPN")
    )
    Write-Log -Message "Getting graph info..." -Level INFO
    $intuneObject = Invoke-RestMethod -Uri "$($intuneUri)?`$filter=contains(serialNumber,'$($serialNumber)')" -Headers $headers -Method Get
    if(($intuneObject.'@odata.count') -eq 1)
    {
        $global:intuneID = $intuneObject.value.id
        $global:aadDeviceID = $intuneObject.value.azureADDeviceId
        Write-Log -Message "Intune Device ID: $intuneID, Azure AD Device ID: $aadDeviceID, User ID: $userID" -Level INFO
    }
    else
    {
        Write-Log -Message "Intune object not found" -Level INFO
    }
    $userObject = Invoke-RestMethod -Uri "$userUri/$upn" -Headers $headers -Method Get
    if(![string]::IsNullOrEmpty($userObject.id))
    {
        $global:userID = $userObject.id
        Write-Log -Message "User ID: $userID" -Level INFO
    }
    else
    {
        Write-Log -Message "User object not found" -Level INFO
    }
}

# set primary user
function setPrimaryUser()
{
    Param(
        [string]$intuneID = $intuneID,
        [string]$userID = $userID,
        [string]$userUri = "https://graph.microsoft.com/beta/users/$userID",
        [string]$intuneDeviceRefUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneID/users/`$ref"
    )
    $id = "@odata.id"
    $JSON = @{ $id="$userUri" } | ConvertTo-Json

    Invoke-RestMethod -Uri $intuneDeviceRefUri -Headers $headers -Method Post -Body $JSON
    Write-Log -Message "Primary user for $intuneID set to $userID" -Level INFO
}

# update device group tag
function updateGroupTag()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$groupTag = (Get-ItemPropertyValue -Path $regKey -Name "GroupTag" -ErrorAction Ignore),
        [string]$aadDeviceID = $aadDeviceID,
        [string]$deviceUri = "https://graph.microsoft.com/beta/devices"
    )
    Write-Log -Message "Updating device group tag..." -Level INFO
    if([string]::IsNullOrEmpty($groupTag))
    {
        Write-Log -Message "Group tag not found- will not be used." -Level INFO
    }
    else
    {
        $aadObject = Invoke-RestMethod -Method Get -Uri "$($deviceUri)?`$filter=deviceId eq '$($aadDeviceId)'" -Headers $headers
        $physicalIds = $aadObject.value.physicalIds
        $deviceId = $aadObject.value.id
        $groupTag = "[OrderID]:$($groupTag)"
        $physicalIds += $groupTag

        $body = @{
            physicalIds = $physicalIds
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$deviceUri/$deviceId" -Method Patch -Headers $headers -Body $body
        Write-Log -Message "Device group tag updated to $groupTag" -Level INFO      
    }
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# get settings
try
{
    getSettingsJSON
    Write-Log -Message "Retrieved settings" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Settings not loaded: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# initialize script
try
{
    initializeScript
    Write-Log -Message "Script initialized" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Script not initialized: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}



# get device info
try
{
    getDeviceInfo
    Write-Log -Message "Device info retrieved" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Device info not retrieved: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# authenticate to MS Graph
try
{
    msGraphAuthenticate
    Write-Log -Message "MS Graph authenticated" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "MS Graph not authenticated: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# get graph info
try
{
    getGraphInfo
    Write-Log -Message "Graph info retrieved" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Graph info not retrieved: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# set primary user
try
{
    setPrimaryUser
    Write-Log -Message "Primary user set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Primary user not set: $message" -Level INFO
    Write-Log -Message "WARNING: Primary user not set- try manually setting in Intune" -Level INFO
}

# update device group tag
try
{
    updateGroupTag
    Write-Log -Message "Device group tag updated if applicable" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Device group tag not updated: $message" -Level INFO
    Write-Log -Message "WARNING: Device group tag not updated- try manually updating in Intune" -Level INFO
}



# END SCRIPT


# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
