<# POSTMIGRATE.PS1
Synopsis
PostMigrate.ps1 is run after the migration reboots have completed and the user signs into the PC.
DESCRIPTION
This script is used to update the device group tag in Entra ID and set the primary user in Intune and migrate the bitlocker recovery key.
USE
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
    Write-Error "Failed to initialize logging: <# POSTMIGRATE.PS1
Synopsis
PostMigrate.ps1 is run after the migration reboots have completed and the user signs into the PC.
DESCRIPTION
This script is used to update the device group tag in Entra ID and set the primary user in Intune and migrate the bitlocker recovery key.
USE
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

# disable post migrate task
function disablePostMigrateTask()
{
    Param(
        [string]$taskName = "postMigrate"
    )
    Write-Log -Message "Disabling postMigrate task..." -Level INFO
    Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Log -Message "postMigrate task disabled" -Level INFO
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

# newDeviceObject function
function newDeviceObject()
{
    Param(
        [string]$serialNumber = (Get-WmiObject -Class Win32_Bios).serialNumber,
        [string]$hostname = $env:COMPUTERNAME,
        [string]$intuneId = ((Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -match "Microsoft Intune MDM Device CA"} | Select-Object Subject).Subject).TrimStart("CN="),
        [string]$entraDeviceId = ((Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -match "MS-Organization-Access"} | Select-Object Subject).Subject).TrimStart("CN=")
    )    
    
    $entraObjectId = (Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$($entraDeviceId)'" -Headers $headers).value.id
    if([string]::IsNullOrEmpty($groupTag))
    {
        try
        {
            $groupTag = (Get-ItemProperty -Path "HKLM:\SOFTWARE\IntuneMigration" -Name "OG_groupTag").OG_groupTag
        }
        catch
        {
            $groupTag = $null
        }
    }
    else
    {
        $groupTag = $groupTag
    }
    $pc = @{
        serialNumber = $serialNumber
        hostname = $hostname
        intuneId = $intuneId
        groupTag = $groupTag
        entraObjectId = $entraObjectId
    }
    return $pc
}


# set primary user
function setPrimaryUser()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$intuneID = $pc.intuneId,
        [string]$upn = (Get-ItemPropertyValue -Path $regKey -Name "UPN"),
        [string]$intuneDeviceRefUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneID/users/`$ref",
		[string]$entraId = (Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/beta/users/$($upn)" -Headers $headers).id,
		[string]$userUri = "https://graph.microsoft.com/beta/users/$entraId"
    )
    Write-Log -Message "Setting primary user..." -Level INFO
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

# migrate bitlocker function
function migrateBitlockerKey()
{
    Param(
        [string]$mountPoint = "C:",
        [PSCustomObject]$bitLockerVolume = (Get-BitLockerVolume -MountPoint $mountPoint),
        [string]$keyProtectorId = ($bitLockerVolume.KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}).KeyProtectorId
    )
    Write-Log -Message "Migrating Bitlocker key..." -Level INFO
    if($bitLockerVolume.KeyProtector.count -gt 0)
    {
        BackupToAAD-BitLockerKeyProtector -MountPoint $mountPoint -KeyProtectorId $keyProtectorId
        Write-Log -Message "Bitlocker key migrated" -Level INFO
    }
    else
    {
        Write-Log -Message "Bitlocker key not migrated" -Level INFO
    }
}

# decrypt drive
function decryptDrive()
{
    Param(
        [string]$mountPoint = "C:"
    )
    Disable-BitLocker -MountPoint $mountPoint
    Write-Log -Message "Drive $mountPoint decrypted" -Level INFO
}

# manage bitlocker
function manageBitlocker()
{
    Param(
        [string]$bitlockerMethod = $settings.bitlockerMethod
    )
    Write-Log -Message "Getting bitlocker action..." -Level INFO
    if($bitlockerMethod -eq "Migrate")
    {
        migrateBitlockerKey
    }
    elseif($bitlockerMethod -eq "Decrypt")
    {
        decryptDrive
    }
    else
    {
        Write-Log -Message "Bitlocker method not set. Skipping..." -Level INFO
    }
}

# reset legal notice policy
function resetLockScreenCaption()
{
    Param(
        [string]$lockScreenRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$lockScreenCaption = "legalnoticecaption",
        [string]$lockScreenText = "legalnoticetext"
    )
    Write-Log -Message "Resetting lock screen caption..." -Level INFO
    Remove-ItemProperty -Path $lockScreenRegPath -Name $lockScreenCaption -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $lockScreenRegPath -Name $lockScreenText -ErrorAction SilentlyContinue
    Write-Log -Message "Lock screen caption reset" -Level INFO
}

# remove migration user
function removeMigrationUser()
{
    Param(
        [string]$migrationUser = "MigrationInProgress"
    )
    Remove-LocalUser -Name $migrationUser -ErrorAction Stop
    Write-Log -Message "Migration user removed" -Level INFO
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

# disable post migrate task
try
{
    disablePostMigrateTask
    Write-Log -Message "Post migrate task disabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Post migrate task not disabled: $message" -Level INFO
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


# manage bitlocker
try
{
    manageBitlocker
    Write-Log -Message "Bitlocker managed" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Bitlocker not managed: $message" -Level INFO
    Write-Log -Message "WARNING: Bitlocker not managed- try setting policy manually in Intune" -Level INFO
}

# run newDeviceObject
Write-Log -Message "Running newDeviceObject..." -Level INFO
try
{
    $pc = newDeviceObject
    Write-Log -Message "newDeviceObject completed" -Level INFO

}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to run newDeviceObject: $message" -Level INFO
    Write-Log -Message "Exiting script..." -Level INFO
    exitScript -exitCode 4 -functionName "newDeviceObject"
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

# reset lock screen caption
try
{
    resetLockScreenCaption
    Write-Log -Message "Lock screen caption reset" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Lock screen caption not reset: $message" -Level INFO
    Write-Log -Message "WARNING: Lock screen caption not reset- try setting manually" -Level INFO
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

# disable post migrate task
function disablePostMigrateTask()
{
    Param(
        [string]$taskName = "postMigrate"
    )
    Write-Log -Message "Disabling postMigrate task..." -Level INFO
    Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Log -Message "postMigrate task disabled" -Level INFO
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

# newDeviceObject function
function newDeviceObject()
{
    Param(
        [string]$serialNumber = (Get-WmiObject -Class Win32_Bios).serialNumber,
        [string]$hostname = $env:COMPUTERNAME,
        [string]$intuneId = ((Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -match "Microsoft Intune MDM Device CA"} | Select-Object Subject).Subject).TrimStart("CN="),
        [string]$entraDeviceId = ((Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -match "MS-Organization-Access"} | Select-Object Subject).Subject).TrimStart("CN=")
    )    
    
    $entraObjectId = (Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$($entraDeviceId)'" -Headers $headers).value.id
    if([string]::IsNullOrEmpty($groupTag))
    {
        try
        {
            $groupTag = (Get-ItemProperty -Path "HKLM:\SOFTWARE\IntuneMigration" -Name "OG_groupTag").OG_groupTag
        }
        catch
        {
            $groupTag = $null
        }
    }
    else
    {
        $groupTag = $groupTag
    }
    $pc = @{
        serialNumber = $serialNumber
        hostname = $hostname
        intuneId = $intuneId
        groupTag = $groupTag
        entraObjectId = $entraObjectId
    }
    return $pc
}


# set primary user
function setPrimaryUser()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$intuneID = $pc.intuneId,
        [string]$upn = (Get-ItemPropertyValue -Path $regKey -Name "UPN"),
        [string]$intuneDeviceRefUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneID/users/`$ref",
		[string]$entraId = (Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/beta/users/$($upn)" -Headers $headers).id,
		[string]$userUri = "https://graph.microsoft.com/beta/users/$entraId"
    )
    Write-Log -Message "Setting primary user..." -Level INFO
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

# migrate bitlocker function
function migrateBitlockerKey()
{
    Param(
        [string]$mountPoint = "C:",
        [PSCustomObject]$bitLockerVolume = (Get-BitLockerVolume -MountPoint $mountPoint),
        [string]$keyProtectorId = ($bitLockerVolume.KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}).KeyProtectorId
    )
    Write-Log -Message "Migrating Bitlocker key..." -Level INFO
    if($bitLockerVolume.KeyProtector.count -gt 0)
    {
        BackupToAAD-BitLockerKeyProtector -MountPoint $mountPoint -KeyProtectorId $keyProtectorId
        Write-Log -Message "Bitlocker key migrated" -Level INFO
    }
    else
    {
        Write-Log -Message "Bitlocker key not migrated" -Level INFO
    }
}

# decrypt drive
function decryptDrive()
{
    Param(
        [string]$mountPoint = "C:"
    )
    Disable-BitLocker -MountPoint $mountPoint
    Write-Log -Message "Drive $mountPoint decrypted" -Level INFO
}

# manage bitlocker
function manageBitlocker()
{
    Param(
        [string]$bitlockerMethod = $settings.bitlockerMethod
    )
    Write-Log -Message "Getting bitlocker action..." -Level INFO
    if($bitlockerMethod -eq "Migrate")
    {
        migrateBitlockerKey
    }
    elseif($bitlockerMethod -eq "Decrypt")
    {
        decryptDrive
    }
    else
    {
        Write-Log -Message "Bitlocker method not set. Skipping..." -Level INFO
    }
}

# reset legal notice policy
function resetLockScreenCaption()
{
    Param(
        [string]$lockScreenRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$lockScreenCaption = "legalnoticecaption",
        [string]$lockScreenText = "legalnoticetext"
    )
    Write-Log -Message "Resetting lock screen caption..." -Level INFO
    Remove-ItemProperty -Path $lockScreenRegPath -Name $lockScreenCaption -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $lockScreenRegPath -Name $lockScreenText -ErrorAction SilentlyContinue
    Write-Log -Message "Lock screen caption reset" -Level INFO
}

# remove migration user
function removeMigrationUser()
{
    Param(
        [string]$migrationUser = "MigrationInProgress"
    )
    Remove-LocalUser -Name $migrationUser -ErrorAction Stop
    Write-Log -Message "Migration user removed" -Level INFO
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

# disable post migrate task
try
{
    disablePostMigrateTask
    Write-Log -Message "Post migrate task disabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Post migrate task not disabled: $message" -Level INFO
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


# manage bitlocker
try
{
    manageBitlocker
    Write-Log -Message "Bitlocker managed" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Bitlocker not managed: $message" -Level INFO
    Write-Log -Message "WARNING: Bitlocker not managed- try setting policy manually in Intune" -Level INFO
}

# run newDeviceObject
Write-Log -Message "Running newDeviceObject..." -Level INFO
try
{
    $pc = newDeviceObject
    Write-Log -Message "newDeviceObject completed" -Level INFO

}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to run newDeviceObject: $message" -Level INFO
    Write-Log -Message "Exiting script..." -Level INFO
    exitScript -exitCode 4 -functionName "newDeviceObject"
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

# reset lock screen caption
try
{
    resetLockScreenCaption
    Write-Log -Message "Lock screen caption reset" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Lock screen caption not reset: $message" -Level INFO
    Write-Log -Message "WARNING: Lock screen caption not reset- try setting manually" -Level INFO
}

# END SCRIPT


# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
