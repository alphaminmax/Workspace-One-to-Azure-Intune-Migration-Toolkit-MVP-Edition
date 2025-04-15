<# NEWPROFILE.PS1
Synopsis
Newprofile.ps1 runs after the user signs in with their target account.
DESCRIPTION
This script is used to capture the SID of the destination user account after sign in.  The SID is then written to the registry.
USE
This script is intended to be run as a scheduled task.  The task is created by the startMigrate.ps1 script and is disabled by this script.
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
        [string]$logName = "newProfile.log",
        [string]$localPath = $settings.localPath
    )
    # Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
    Write-Log -Message "========== Starting .ps1 ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: <# NEWPROFILE.PS1
Synopsis
Newprofile.ps1 runs after the user signs in with their target account.
DESCRIPTION
This script is used to capture the SID of the destination user account after sign in.  The SID is then written to the registry.
USE
This script is intended to be run as a scheduled task.  The task is created by the startMigrate.ps1 script and is disabled by this script.
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
        [string]$logName = "newProfile.log",
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

# get new user SID
function getNewUserSID()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$newUser = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty UserName),
        [string]$newUserSID = (New-Object System.Security.Principal.NTAccount($newUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    )
    Write-Log -Message "New user: $newUser" -Level INFO
    if(![string]::IsNullOrEmpty($newUserSID))
    {
        reg.exe add $regPath /v "NewUserSID" /t REG_SZ /d $newUserSID /f | Out-Host
        Write-Log -Message "SID written to registry" -Level INFO
    
    }
    else
    {
        Write-Log -Message "New user SID not found" -Level INFO
    }
}

# disable newProfile task
function disableNewProfileTask()
{
    Param(
        [string]$taskName = "newProfile"
    )
    Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Log -Message "newProfile task disabled" -Level INFO    
}

# revoke logon provider
function revokeLogonProvider()
{
    Param(
        [string]$logonProviderPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}",
        [string]$logonProviderName = "Disabled",
        [int]$logonProviderValue = 1
    )
    reg.exe add $logonProviderPath /v $logonProviderName /t REG_DWORD /d $logonProviderValue /f | Out-Host
    Write-Log -Message "Revoked logon provider." -Level INFO
}

# set lock screen caption
function setLockScreenCaption()
{
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalNoticeRegPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalNoticeCaption = "legalnoticecaption",
        [string]$legalNoticeCaptionValue = "Almost there...",
        [string]$legalNoticeText = "legalnoticetext",
        [string]$legalNoticeTextValue = "Your PC will restart one more time to join the $($targetTenantName) environment."
    )
    Write-Log -Message "Setting lock screen caption..." -Level INFO
    reg.exe add $legalNoticeRegPath /v $legalNoticeCaption /t REG_SZ /d $legalNoticeCaptionValue /f | Out-Host
    reg.exe add $legalNoticeRegPath /v $legalNoticeText /t REG_SZ /d $legalNoticeTextValue /f | Out-Host
    Write-Log -Message "Set lock screen caption." -Level INFO
}

# enable auto logon
function enableAutoLogon()
{
    Param(
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoLogonName = "AutoAdminLogon",
        [string]$autoLogonValue = 1
    )
    Write-Log -Message "Enabling auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoLogonName /t REG_SZ /d $autoLogonValue /f | Out-Host
    Write-Log -Message "Auto logon enabled." -Level INFO
}

# set finalBoot task
function setFinalBootTask()
{
    Param(
        [string]$taskName = "finalBoot",
        [string]$taskXML = "$($localPath)\$($taskName).xml"
    )
    Write-Log -Message "Setting $($taskName) task..." -Level INFO
    if($taskXML)
    {
        schtasks.exe /Create /TN $taskName /XML $taskXML
        Write-Log -Message "$($taskName) task set." -Level INFO
    }
    else
    {
        Write-Log -Message "Failed to set $($taskName) task: $taskXML not found" -Level INFO
    }
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# get settings
try
{
    getSettingsJSON
    Write-Log -Message "Settings retrieved" -Level INFO
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
    Write-Log -Message "Failed to initialize script: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# get new user SID
try
{
    getNewUserSID
    Write-Log -Message "New user SID retrieved" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get new user SID: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# disable newProfile task
try
{
    disableNewProfileTask
    Write-Log -Message "newProfile task disabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to disable newProfile task: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# revoke logon provider
try
{
    revokeLogonProvider
    Write-Log -Message "Logon provider revoked" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to revoke logon provider: $message" -Level INFO
    Write-Log -Message "WARNING: Logon provider not revoked" -Level INFO
}

# set lock screen caption
try
{
    setLockScreenCaption
    Write-Log -Message "Lock screen caption set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set lock screen caption: $message" -Level INFO
    Write-Log -Message "WARNING: Lock screen caption not set" -Level INFO
}

# enable auto logon
try
{
    enableAutoLogon
    Write-Log -Message "Auto logon enabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to enable auto logon: $message" -Level INFO
    Write-Log -Message "WARNING: Auto logon not enabled" -Level INFO
}

# set finalBoot task
try
{
    setFinalBootTask
    Write-Log -Message "finalBoot task set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set finalBoot task: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

Start-Sleep -Seconds 2
Write-Log -Message "rebooting computer" -Level INFO

shutdown -r -t 00
# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
"
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

# get new user SID
function getNewUserSID()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$newUser = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty UserName),
        [string]$newUserSID = (New-Object System.Security.Principal.NTAccount($newUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    )
    Write-Log -Message "New user: $newUser" -Level INFO
    if(![string]::IsNullOrEmpty($newUserSID))
    {
        reg.exe add $regPath /v "NewUserSID" /t REG_SZ /d $newUserSID /f | Out-Host
        Write-Log -Message "SID written to registry" -Level INFO
    
    }
    else
    {
        Write-Log -Message "New user SID not found" -Level INFO
    }
}

# disable newProfile task
function disableNewProfileTask()
{
    Param(
        [string]$taskName = "newProfile"
    )
    Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Log -Message "newProfile task disabled" -Level INFO    
}

# revoke logon provider
function revokeLogonProvider()
{
    Param(
        [string]$logonProviderPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}",
        [string]$logonProviderName = "Disabled",
        [int]$logonProviderValue = 1
    )
    reg.exe add $logonProviderPath /v $logonProviderName /t REG_DWORD /d $logonProviderValue /f | Out-Host
    Write-Log -Message "Revoked logon provider." -Level INFO
}

# set lock screen caption
function setLockScreenCaption()
{
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalNoticeRegPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalNoticeCaption = "legalnoticecaption",
        [string]$legalNoticeCaptionValue = "Almost there...",
        [string]$legalNoticeText = "legalnoticetext",
        [string]$legalNoticeTextValue = "Your PC will restart one more time to join the $($targetTenantName) environment."
    )
    Write-Log -Message "Setting lock screen caption..." -Level INFO
    reg.exe add $legalNoticeRegPath /v $legalNoticeCaption /t REG_SZ /d $legalNoticeCaptionValue /f | Out-Host
    reg.exe add $legalNoticeRegPath /v $legalNoticeText /t REG_SZ /d $legalNoticeTextValue /f | Out-Host
    Write-Log -Message "Set lock screen caption." -Level INFO
}

# enable auto logon
function enableAutoLogon()
{
    Param(
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoLogonName = "AutoAdminLogon",
        [string]$autoLogonValue = 1
    )
    Write-Log -Message "Enabling auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoLogonName /t REG_SZ /d $autoLogonValue /f | Out-Host
    Write-Log -Message "Auto logon enabled." -Level INFO
}

# set finalBoot task
function setFinalBootTask()
{
    Param(
        [string]$taskName = "finalBoot",
        [string]$taskXML = "$($localPath)\$($taskName).xml"
    )
    Write-Log -Message "Setting $($taskName) task..." -Level INFO
    if($taskXML)
    {
        schtasks.exe /Create /TN $taskName /XML $taskXML
        Write-Log -Message "$($taskName) task set." -Level INFO
    }
    else
    {
        Write-Log -Message "Failed to set $($taskName) task: $taskXML not found" -Level INFO
    }
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# get settings
try
{
    getSettingsJSON
    Write-Log -Message "Settings retrieved" -Level INFO
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
    Write-Log -Message "Failed to initialize script: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# get new user SID
try
{
    getNewUserSID
    Write-Log -Message "New user SID retrieved" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get new user SID: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# disable newProfile task
try
{
    disableNewProfileTask
    Write-Log -Message "newProfile task disabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to disable newProfile task: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# revoke logon provider
try
{
    revokeLogonProvider
    Write-Log -Message "Logon provider revoked" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to revoke logon provider: $message" -Level INFO
    Write-Log -Message "WARNING: Logon provider not revoked" -Level INFO
}

# set lock screen caption
try
{
    setLockScreenCaption
    Write-Log -Message "Lock screen caption set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set lock screen caption: $message" -Level INFO
    Write-Log -Message "WARNING: Lock screen caption not set" -Level INFO
}

# enable auto logon
try
{
    enableAutoLogon
    Write-Log -Message "Auto logon enabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to enable auto logon: $message" -Level INFO
    Write-Log -Message "WARNING: Auto logon not enabled" -Level INFO
}

# set finalBoot task
try
{
    setFinalBootTask
    Write-Log -Message "finalBoot task set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set finalBoot task: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

Start-Sleep -Seconds 2
Write-Log -Message "rebooting computer" -Level INFO

shutdown -r -t 00
# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript

