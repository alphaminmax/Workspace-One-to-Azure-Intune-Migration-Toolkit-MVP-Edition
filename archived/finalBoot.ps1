<# FINALBOOT.PS1
Synopsis
Finalboot.ps1 is the last script that automatically reboots the PC.
DESCRIPTION
This script is used to change ownership of the original user profile to the destination user and then reboot the machine.  It is executed by the 'finalBoot' scheduled task.
USE
.\finalBoot.ps1
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
        [string]$logName = "finalBoot.log",
        [string]$localPath = $settings.localPath
    )
    # Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
    Write-Log -Message "========== Starting .ps1 ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: <# FINALBOOT.PS1
Synopsis
Finalboot.ps1 is the last script that automatically reboots the PC.
DESCRIPTION
This script is used to change ownership of the original user profile to the destination user and then reboot the machine.  It is executed by the 'finalBoot' scheduled task.
USE
.\finalBoot.ps1
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
        [string]$logName = "finalBoot.log",
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

# disable finalBoot task
function disableFinalBootTask()
{
    Param(
        [string]$taskName = "finalBoot"
    )
    Write-Host "Disabling finalBoot task..."
    try 
    {
        Disable-ScheduledTask -TaskName $taskName
        Write-Host "finalBoot task disabled"    
    }
    catch 
    {
        $message = $_.Exception.Message
        Write-Host "finalBoot task not disabled: $message"
    }
}

# enable auto logon
function disableAutoLogon()
{
    Param(
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoAdminLogon = "AutoAdminLogon",
        [int]$autoAdminLogonValue = 0
    )
    Write-Log -Message "Disabling auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoAdminLogon /t REG_SZ /d $autoAdminLogonValue /f | Out-Host
    Write-Log -Message "Auto logon disabled" -Level INFO
}

# get user info from registry
function getUserInfo()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [array]$userArray = @("OriginalUserSID", "OriginalUserName", "OriginalProfilePath", "NewUserSID")
    )
    Write-Log -Message "Getting user info from registry..." -Level INFO
    foreach($user in $userArray)
    {
        $value = Get-ItemPropertyValue -Path $regKey -Name $user
        if(![string]::IsNullOrEmpty($value))
        {
            New-Variable -Name $user -Value $value -Scope Global -Force
            Write-Log -Message "$($user): $value" -Level INFO
        }
    }
}

# remove AAD.Broker.Plugin from original profile
function removeAADBrokerPlugin()
{
    Param(
        [string]$originalProfilePath = $OriginalProfilePath,
        [string]$aadBrokerPlugin = "Microsoft.AAD.BrokerPlugin_*"
    )
    Write-Log -Message "Removing AAD.Broker.Plugin from original profile..." -Level INFO
    $aadBrokerPath = (Get-ChildItem -Path "$($originalProfilePath)\AppData\Local\Packages" -Recurse | Where-Object {$_.Name -match $aadBrokerPlugin} | Select-Object FullName).FullName
    if([string]::IsNullOrEmpty($aadBrokerPath))
    {
        Write-Log -Message "AAD.Broker.Plugin not found" -Level INFO
    }
    else
    {
        Remove-Item -Path $aadBrokerPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log -Message "AAD.Broker.Plugin removed" -Level INFO 
    }
}

# delete new user profile
function deleteNewUserProfile()
{
    Param(
        [string]$newUserSID = $NewUserSID
    )
    Write-Log -Message "Deleting new user profile..." -Level INFO
    $newProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {$_.SID -eq $newUserSID}
    Remove-CimInstance -InputObject $newProfile -Verbose | Out-Null
    Write-Log -Message "New user profile deleted" -Level INFO
}

# change ownership of original profile
function changeOriginalProfileOwner()
{
    Param(
        [string]$originalUserSID = $OriginalUserSID,
        [string]$newUserSID = $NewUserSID
    )
    Write-Log -Message "Changing ownership of original profile..." -Level INFO
    $originalProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {$_.SID -eq $originalUserSID}
    $changeArguments = @{
        NewOwnerSID = $newUserSID
        Flags = 0
    }
    $originalProfile | Invoke-CimMethod -MethodName ChangeOwner -Arguments $changeArguments
    Start-Sleep -Seconds 1
}

# cleanup identity store cache
function cleanupLogonCache()
{
    Param(
        [string]$logonCache = "HKLM:\SOFTWARE\Microsoft\IdentityStore\LogonCache",
        [string]$oldUserName = $OriginalUserName
    )
    Write-Log -Message "Cleaning up identity store cache..." -Level INFO
    $logonCacheGUID = (Get-ChildItem -Path $logonCache | Select-Object Name | Split-Path -Leaf).trim('{}')
    foreach($GUID in $logonCacheGUID)
    {
        $subKeys = Get-ChildItem -Path "$logonCache\$GUID" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Split-Path -Leaf
        if(!($subKeys))
        {
            Write-Log -Message "No subkeys found for $GUID" -Level INFO
            continue
        }
        else
        {
            $subKeys = $subKeys.trim('{}')
            foreach($subKey in $subKeys)
            {
                if($subKey -eq "Name2Sid" -or $subKey -eq "SAM_Name" -or $subKey -eq "Sid2Name")
                {
                    $subFolders = Get-ChildItem -Path "$logonCache\$GUID\$subKey" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Split-Path -Leaf
                    if(!($subFolders))
                    {
                        Write-Log -Message "Error - no sub folders found for $subKey" -Level INFO
                        continue
                    }
                    else
                    {
                        $subFolders = $subFolders.trim('{}')
                        foreach($subFolder in $subFolders)
                        {
                            $cacheUsername = Get-ItemPropertyValue -Path "$logonCache\$GUID\$subKey\$subFolder" -Name "IdentityName" -ErrorAction SilentlyContinue
                            if($cacheUsername -eq $oldUserName)
                            {
                                Remove-Item -Path "$logonCache\$GUID\$subKey\$subFolder" -Recurse -Force
                                Write-Log -Message "Registry key deleted: $logonCache\$GUID\$subKey\$subFolder" -Level INFO
                                continue                                       
                            }
                        }
                    }
                }
            }
        }
    }
}

# cleanup identity store cache
function cleanupIdentityStore()
{
    Param(
        [string]$idCache = "HKLM:\Software\Microsoft\IdentityStore\Cache",
        [string]$oldUserName = $OriginalUserName
    )
    Write-Log -Message "Cleaning up identity store cache..." -Level INFO
    $idCacheKeys = (Get-ChildItem -Path $idCache | Select-Object Name | Split-Path -Leaf).trim('{}')
    foreach($key in $idCacheKeys)
    {
        $subKeys = Get-ChildItem -Path "$idCache\$key" -ErrorAction SilentlyContinue | Select-Object Name | Split-Path -Leaf
        if(!($subKeys))
        {
            Write-Log -Message "No keys listed under " -Level INFO$idCache\$key' - skipping..."
            continue
        }
        else
        {
            $subKeys = $subKeys.trim('{}')
            foreach($subKey in $subKeys)
            {
                $subFolders = Get-ChildItem -Path "$idCache\$key\$subKey" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Split-Path -Leaf
                if(!($subFolders))
                {
                    Write-Log -Message "No subfolders detected for $subkey- skipping..." -Level INFO
                    continue
                }
                else
                {
                    $subFolders = $subFolders.trim('{}')
                    foreach($subFolder in $subFolders)
                    {
                        $idCacheUsername = Get-ItemPropertyValue -Path "$idCache\$key\$subKey\$subFolder" -Name "UserName" -ErrorAction SilentlyContinue
                        if($idCacheUsername -eq $oldUserName)
                        {
                            Remove-Item -Path "$idCache\$key\$subKey\$subFolder" -Recurse -Force
                            Write-Log -Message "Registry path deleted: $idCache\$key\$subKey\$subFolder" -Level INFO
                            continue
                        }
                    }
                }
            }
        }
    }
}

# set display last user name policy
function displayLastUsername()
{
    Param(
        [string]$regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$regKey = "Registry::$regPath",
        [string]$regName = "DontDisplayLastUserName",
        [int]$regValue = 0
    )
    $currentRegValue = Get-ItemPropertyValue -Path $regKey -Name $regName
    if($currentRegValue -eq $regValue)
    {
        Write-Log -Message "$($regName) is already set to $($regValue)." -Level INFO
    }
    else
    {
        reg.exe add $regPath /v $regName /t REG_DWORD /d $regValue /f | Out-Host
        Write-Log -Message "Set $($regName) to $($regValue) at $regPath." -Level INFO
    }
}

# set post migrate tasks
function setPostMigrateTasks()
{
    Param(
        [array]$tasks = @("postMigrate","AutopilotRegistration"),
        [string]$localPath = $localPath
    )
    Write-Log -Message "Setting post migrate tasks..." -Level INFO
    foreach($task in $tasks)
    {
        $taskPath = "$($localPath)\$($task).xml"
        if($taskPath)
        {
            schtasks.exe /Create /TN $task /XML $taskPath
            Write-Log -Message "$($task) task set." -Level INFO
        }
        else
        {
            Write-Log -Message "Failed to set $($task) task: $taskPath not found" -Level INFO
        }
    }
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

# set lock screen caption
function setLockScreenCaption()
{
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalNoticeRegPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalNoticeCaption = "legalnoticecaption",
        [string]$legalNoticeCaptionValue = "Welcome to $($targetTenantName)!",
        [string]$legalNoticeText = "legalnoticetext",
        [string]$legalNoticeTextValue = "Your PC is now part of $($targetTenantName).  Please sign in."
    )
    Write-Log -Message "Setting lock screen caption..." -Level INFO
    reg.exe add $legalNoticeRegPath /v $legalNoticeCaption /t REG_SZ /d $legalNoticeCaptionValue /f | Out-Host
    reg.exe add $legalNoticeRegPath /v $legalNoticeText /t REG_SZ /d $legalNoticeTextValue /f | Out-Host
    Write-Log -Message "Set lock screen caption." -Level INFO
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# run get settings
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

# run initialize script
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

# run disable finalBoot task
try
{
    disableFinalBootTask
    Write-Log -Message "finalBoot task disabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "finalBoot task not disabled: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run display last username
try
{
    displayLastUsername
    Write-Log -Message "Display last username set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Display last username not set: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run set post migrate tasks
try
{
    setPostMigrateTasks
    Write-Log -Message "Post migrate tasks set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Post migrate tasks not set: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run set lock screen caption
try
{
    setLockScreenCaption
    Write-Log -Message "Lock screen caption set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Lock screen caption not set: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# END SCRIPT
Write-Log -Message "Script completed" -Level INFO
Write-Log -Message "Rebooting machine..." -Level INFO

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

# disable finalBoot task
function disableFinalBootTask()
{
    Param(
        [string]$taskName = "finalBoot"
    )
    Write-Host "Disabling finalBoot task..."
    try 
    {
        Disable-ScheduledTask -TaskName $taskName
        Write-Host "finalBoot task disabled"    
    }
    catch 
    {
        $message = $_.Exception.Message
        Write-Host "finalBoot task not disabled: $message"
    }
}

# enable auto logon
function disableAutoLogon()
{
    Param(
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoAdminLogon = "AutoAdminLogon",
        [int]$autoAdminLogonValue = 0
    )
    Write-Log -Message "Disabling auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoAdminLogon /t REG_SZ /d $autoAdminLogonValue /f | Out-Host
    Write-Log -Message "Auto logon disabled" -Level INFO
}

# get user info from registry
function getUserInfo()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [array]$userArray = @("OriginalUserSID", "OriginalUserName", "OriginalProfilePath", "NewUserSID")
    )
    Write-Log -Message "Getting user info from registry..." -Level INFO
    foreach($user in $userArray)
    {
        $value = Get-ItemPropertyValue -Path $regKey -Name $user
        if(![string]::IsNullOrEmpty($value))
        {
            New-Variable -Name $user -Value $value -Scope Global -Force
            Write-Log -Message "$($user): $value" -Level INFO
        }
    }
}

# remove AAD.Broker.Plugin from original profile
function removeAADBrokerPlugin()
{
    Param(
        [string]$originalProfilePath = $OriginalProfilePath,
        [string]$aadBrokerPlugin = "Microsoft.AAD.BrokerPlugin_*"
    )
    Write-Log -Message "Removing AAD.Broker.Plugin from original profile..." -Level INFO
    $aadBrokerPath = (Get-ChildItem -Path "$($originalProfilePath)\AppData\Local\Packages" -Recurse | Where-Object {$_.Name -match $aadBrokerPlugin} | Select-Object FullName).FullName
    if([string]::IsNullOrEmpty($aadBrokerPath))
    {
        Write-Log -Message "AAD.Broker.Plugin not found" -Level INFO
    }
    else
    {
        Remove-Item -Path $aadBrokerPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log -Message "AAD.Broker.Plugin removed" -Level INFO 
    }
}

# delete new user profile
function deleteNewUserProfile()
{
    Param(
        [string]$newUserSID = $NewUserSID
    )
    Write-Log -Message "Deleting new user profile..." -Level INFO
    $newProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {$_.SID -eq $newUserSID}
    Remove-CimInstance -InputObject $newProfile -Verbose | Out-Null
    Write-Log -Message "New user profile deleted" -Level INFO
}

# change ownership of original profile
function changeOriginalProfileOwner()
{
    Param(
        [string]$originalUserSID = $OriginalUserSID,
        [string]$newUserSID = $NewUserSID
    )
    Write-Log -Message "Changing ownership of original profile..." -Level INFO
    $originalProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {$_.SID -eq $originalUserSID}
    $changeArguments = @{
        NewOwnerSID = $newUserSID
        Flags = 0
    }
    $originalProfile | Invoke-CimMethod -MethodName ChangeOwner -Arguments $changeArguments
    Start-Sleep -Seconds 1
}

# cleanup identity store cache
function cleanupLogonCache()
{
    Param(
        [string]$logonCache = "HKLM:\SOFTWARE\Microsoft\IdentityStore\LogonCache",
        [string]$oldUserName = $OriginalUserName
    )
    Write-Log -Message "Cleaning up identity store cache..." -Level INFO
    $logonCacheGUID = (Get-ChildItem -Path $logonCache | Select-Object Name | Split-Path -Leaf).trim('{}')
    foreach($GUID in $logonCacheGUID)
    {
        $subKeys = Get-ChildItem -Path "$logonCache\$GUID" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Split-Path -Leaf
        if(!($subKeys))
        {
            Write-Log -Message "No subkeys found for $GUID" -Level INFO
            continue
        }
        else
        {
            $subKeys = $subKeys.trim('{}')
            foreach($subKey in $subKeys)
            {
                if($subKey -eq "Name2Sid" -or $subKey -eq "SAM_Name" -or $subKey -eq "Sid2Name")
                {
                    $subFolders = Get-ChildItem -Path "$logonCache\$GUID\$subKey" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Split-Path -Leaf
                    if(!($subFolders))
                    {
                        Write-Log -Message "Error - no sub folders found for $subKey" -Level INFO
                        continue
                    }
                    else
                    {
                        $subFolders = $subFolders.trim('{}')
                        foreach($subFolder in $subFolders)
                        {
                            $cacheUsername = Get-ItemPropertyValue -Path "$logonCache\$GUID\$subKey\$subFolder" -Name "IdentityName" -ErrorAction SilentlyContinue
                            if($cacheUsername -eq $oldUserName)
                            {
                                Remove-Item -Path "$logonCache\$GUID\$subKey\$subFolder" -Recurse -Force
                                Write-Log -Message "Registry key deleted: $logonCache\$GUID\$subKey\$subFolder" -Level INFO
                                continue                                       
                            }
                        }
                    }
                }
            }
        }
    }
}

# cleanup identity store cache
function cleanupIdentityStore()
{
    Param(
        [string]$idCache = "HKLM:\Software\Microsoft\IdentityStore\Cache",
        [string]$oldUserName = $OriginalUserName
    )
    Write-Log -Message "Cleaning up identity store cache..." -Level INFO
    $idCacheKeys = (Get-ChildItem -Path $idCache | Select-Object Name | Split-Path -Leaf).trim('{}')
    foreach($key in $idCacheKeys)
    {
        $subKeys = Get-ChildItem -Path "$idCache\$key" -ErrorAction SilentlyContinue | Select-Object Name | Split-Path -Leaf
        if(!($subKeys))
        {
            Write-Log -Message "No keys listed under " -Level INFO$idCache\$key' - skipping..."
            continue
        }
        else
        {
            $subKeys = $subKeys.trim('{}')
            foreach($subKey in $subKeys)
            {
                $subFolders = Get-ChildItem -Path "$idCache\$key\$subKey" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Split-Path -Leaf
                if(!($subFolders))
                {
                    Write-Log -Message "No subfolders detected for $subkey- skipping..." -Level INFO
                    continue
                }
                else
                {
                    $subFolders = $subFolders.trim('{}')
                    foreach($subFolder in $subFolders)
                    {
                        $idCacheUsername = Get-ItemPropertyValue -Path "$idCache\$key\$subKey\$subFolder" -Name "UserName" -ErrorAction SilentlyContinue
                        if($idCacheUsername -eq $oldUserName)
                        {
                            Remove-Item -Path "$idCache\$key\$subKey\$subFolder" -Recurse -Force
                            Write-Log -Message "Registry path deleted: $idCache\$key\$subKey\$subFolder" -Level INFO
                            continue
                        }
                    }
                }
            }
        }
    }
}

# set display last user name policy
function displayLastUsername()
{
    Param(
        [string]$regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$regKey = "Registry::$regPath",
        [string]$regName = "DontDisplayLastUserName",
        [int]$regValue = 0
    )
    $currentRegValue = Get-ItemPropertyValue -Path $regKey -Name $regName
    if($currentRegValue -eq $regValue)
    {
        Write-Log -Message "$($regName) is already set to $($regValue)." -Level INFO
    }
    else
    {
        reg.exe add $regPath /v $regName /t REG_DWORD /d $regValue /f | Out-Host
        Write-Log -Message "Set $($regName) to $($regValue) at $regPath." -Level INFO
    }
}

# set post migrate tasks
function setPostMigrateTasks()
{
    Param(
        [array]$tasks = @("postMigrate","AutopilotRegistration"),
        [string]$localPath = $localPath
    )
    Write-Log -Message "Setting post migrate tasks..." -Level INFO
    foreach($task in $tasks)
    {
        $taskPath = "$($localPath)\$($task).xml"
        if($taskPath)
        {
            schtasks.exe /Create /TN $task /XML $taskPath
            Write-Log -Message "$($task) task set." -Level INFO
        }
        else
        {
            Write-Log -Message "Failed to set $($task) task: $taskPath not found" -Level INFO
        }
    }
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

# set lock screen caption
function setLockScreenCaption()
{
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalNoticeRegPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalNoticeCaption = "legalnoticecaption",
        [string]$legalNoticeCaptionValue = "Welcome to $($targetTenantName)!",
        [string]$legalNoticeText = "legalnoticetext",
        [string]$legalNoticeTextValue = "Your PC is now part of $($targetTenantName).  Please sign in."
    )
    Write-Log -Message "Setting lock screen caption..." -Level INFO
    reg.exe add $legalNoticeRegPath /v $legalNoticeCaption /t REG_SZ /d $legalNoticeCaptionValue /f | Out-Host
    reg.exe add $legalNoticeRegPath /v $legalNoticeText /t REG_SZ /d $legalNoticeTextValue /f | Out-Host
    Write-Log -Message "Set lock screen caption." -Level INFO
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# run get settings
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

# run initialize script
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

# run disable finalBoot task
try
{
    disableFinalBootTask
    Write-Log -Message "finalBoot task disabled" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "finalBoot task not disabled: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run display last username
try
{
    displayLastUsername
    Write-Log -Message "Display last username set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Display last username not set: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run set post migrate tasks
try
{
    setPostMigrateTasks
    Write-Log -Message "Post migrate tasks set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Post migrate tasks not set: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# run set lock screen caption
try
{
    setLockScreenCaption
    Write-Log -Message "Lock screen caption set" -Level INFO
}
catch
{
    $message = $_.Exception.Message
    Write-Log -Message "Lock screen caption not set: $message" -Level INFO
    Write-Log -Message "Exiting script" -Level INFO
    Exit 1
}

# END SCRIPT
Write-Log -Message "Script completed" -Level INFO
Write-Log -Message "Rebooting machine..." -Level INFO

shutdown -r -t 5

# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
