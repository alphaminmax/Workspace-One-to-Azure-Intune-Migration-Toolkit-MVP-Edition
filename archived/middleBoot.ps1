<# MIDDLEBOOT.PS1
Synopsis
Middleboot.ps1 is the second script in the migration process.
DESCRIPTION
This script is used to automatically restart the computer immediately after the installation of the startMigrate.ps1 script and change the lock screen text.  The password logon credential provider is also enabled to allow the user to log in with their new credentials.
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
        [string]$logName = "middleBoot.log",
        [string]$localPath = $settings.localPath
    )
    # Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
    Write-Log -Message "========== Starting .ps1 ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: <# MIDDLEBOOT.PS1
Synopsis
Middleboot.ps1 is the second script in the migration process.
DESCRIPTION
This script is used to automatically restart the computer immediately after the installation of the startMigrate.ps1 script and change the lock screen text.  The password logon credential provider is also enabled to allow the user to log in with their new credentials.
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
        [string]$logName = "middleBoot.log",
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

# restore logon credential provider
function restoreLogonProvider()
{
    Param(
        [string]$logonProviderPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}",
        [string]$logonProviderName = "Disabled",
        [int]$logonProviderValue = 0
    )
    reg.exe add $logonProviderPath /v $logonProviderName /t REG_DWORD /d $logonProviderValue /f | Out-Host
    Write-Log -Message "Logon credential provider restored" -Level INFO
}

# set legal notice
function setLockScreenCaption()
{
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalCaptionName = "legalnoticecaption",
        [string]$legalCaptionValue = "Join $($targetTenantName)",
        [string]$legalTextName = "legalnoticetext",
        [string]$text = "Sign in with your new $($targetTenantName) email address and password to start the migration process. Once you sign in, do not do anything else as the device will reboot quickly after login."
    )
    Write-Log -Message "Setting lock screen caption..." -Level INFO
    reg.exe add $legalPath /v $legalCaptionName /t REG_SZ /d $legalCaptionValue /f | Out-Host
    reg.exe add $legalPath /v $legalTextName /t REG_SZ /d $text /f | Out-Host
    Write-Log -Message "Lock screen caption set" -Level INFO
}

# disable auto logon
function disableAutoLogon()
{
    Param(
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoLogonName = "AutoAdminLogon",
        [string]$autoLogonValue = 0
    )
    Write-Log -Message "Disabling auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoLogonName /t REG_SZ /d $autoLogonValue /f | Out-Host
    Write-Log -Message "Auto logon disabled" -Level INFO
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

# disable middleBoot task
function disableTask()
{
    Param(
        [string]$taskName = "middleBoot"
    )
    Write-Log -Message "Disabling middleBoot task..." -Level INFO
    Disable-ScheduledTask -TaskName $taskName
    Write-Log -Message "middleBoot task disabled" -Level INFO    
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# run get settings function
try
{
    getSettingsJSON
    Write-Log -Message "Retrieved settings JSON" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get settings JSON: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run initialize script function
try
{
    initializeScript
    Write-Log -Message "Initialized script" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to initialize script: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run set lock screen caption function
try
{
    setLockScreenCaption
    Write-Log -Message "Set lock screen caption" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set lock screen caption: $message" -Level INFO
    Write-Log -Message "WARNING: Lock screen caption not set" -Level INFO
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

# run disable task function
try
{
    disableTask
    Write-Log -Message "Disabled middleBoot task" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to disable middleBoot task: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# END SCRIPT
Write-Log -Message "Restarting computer..." -Level INFO
shutdown -r -t 5

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

# restore logon credential provider
function restoreLogonProvider()
{
    Param(
        [string]$logonProviderPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}",
        [string]$logonProviderName = "Disabled",
        [int]$logonProviderValue = 0
    )
    reg.exe add $logonProviderPath /v $logonProviderName /t REG_DWORD /d $logonProviderValue /f | Out-Host
    Write-Log -Message "Logon credential provider restored" -Level INFO
}

# set legal notice
function setLockScreenCaption()
{
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalCaptionName = "legalnoticecaption",
        [string]$legalCaptionValue = "Join $($targetTenantName)",
        [string]$legalTextName = "legalnoticetext",
        [string]$text = "Sign in with your new $($targetTenantName) email address and password to start the migration process. Once you sign in, do not do anything else as the device will reboot quickly after login."
    )
    Write-Log -Message "Setting lock screen caption..." -Level INFO
    reg.exe add $legalPath /v $legalCaptionName /t REG_SZ /d $legalCaptionValue /f | Out-Host
    reg.exe add $legalPath /v $legalTextName /t REG_SZ /d $text /f | Out-Host
    Write-Log -Message "Lock screen caption set" -Level INFO
}

# disable auto logon
function disableAutoLogon()
{
    Param(
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoLogonName = "AutoAdminLogon",
        [string]$autoLogonValue = 0
    )
    Write-Log -Message "Disabling auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoLogonName /t REG_SZ /d $autoLogonValue /f | Out-Host
    Write-Log -Message "Auto logon disabled" -Level INFO
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

# disable middleBoot task
function disableTask()
{
    Param(
        [string]$taskName = "middleBoot"
    )
    Write-Log -Message "Disabling middleBoot task..." -Level INFO
    Disable-ScheduledTask -TaskName $taskName
    Write-Log -Message "middleBoot task disabled" -Level INFO    
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# run get settings function
try
{
    getSettingsJSON
    Write-Log -Message "Retrieved settings JSON" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get settings JSON: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run initialize script function
try
{
    initializeScript
    Write-Log -Message "Initialized script" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to initialize script: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run set lock screen caption function
try
{
    setLockScreenCaption
    Write-Log -Message "Set lock screen caption" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set lock screen caption: $message" -Level INFO
    Write-Log -Message "WARNING: Lock screen caption not set" -Level INFO
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

# run disable task function
try
{
    disableTask
    Write-Log -Message "Disabled middleBoot task" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to disable middleBoot task: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# END SCRIPT
Write-Log -Message "Restarting computer..." -Level INFO
shutdown -r -t 5

# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
