<# Workspace ONE UEM to Intune Migration
Synopsis
This solution will automate the migration of devices from Workspace ONE UEM to Intune.  Devices can be hybrid AD Joined or Azure AD Joined.
DESCRIPTION
Intune Migration Solution leverages the Microsoft Graph API to automate the migration of devices from Workspace ONE UEM to Intune.   
USE
This script is packaged along with the other files into a zip.  The zip file is then uploaded to Workspace One UEM and assigned to a group of devices.  The script is then run on the device to start the migration process.

NOTES
When deploying with Workspace One UEM, the install command must be "powershell.exe -ExecutionPolicy Bypass -File" to ensure the script runs in 64-bit mode.
.OWNER
Michael Weisberg
.CONTRIBUTORS

#>

# # Ensure the script runs in 64-bit PowerShell
# if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
#     Write-Error "This script must be run in 64-bit PowerShell."
#     exit 1
# }

# Attempt to import the Provisioning module
try {
    Import-Module Provisioning -ErrorAction Stop
} catch {
    Write-Error "Failed to import Provisioning module: $_"
    exit 1
}

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
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$message
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss tt"
    Write-Output "$ts $message"
}

# get dsreg status
function joinStatus()
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$joinType
    )
    $dsregStatus = dsregcmd.exe /status
    $status = ($dsregStatus | Select-String $joinType).ToString().Split(":")[1].Trim()
    return $status
}

# function get admin status
function getAdminStatus()
{
    Param(
        [string]$adminUser = "Administrator"
    )
    $adminStatus = (Get-LocalUser -Name $adminUser).Enabled
    Write-Log -Message "Administrator account is $($adminStatus)." -Level INFO
    return $adminStatus
}

# generate random password
function generatePassword {
    Param(
        [int]$length = 12
    )
    
    # Define the character set for the password
    $charSet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:',<.>/?"
    
    # Create a secure string to store the password
    $securePassword = New-Object -TypeName System.Security.SecureString
    
    # Generate random characters and add to secure string
    for ($i = 1; $i -le $length; $i++) {
        $randomIndex = Get-Random -Minimum 0 -Maximum $charSet.Length
        $randomChar = $charSet[$randomIndex]
        $securePassword.AppendChar($randomChar)
    }
    
    return $securePassword
}



# END CMDLET FUNCTIONS

# SCRIPT FUNCTIONS START

#  get json settings
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
        [string]$localPath = $settings.localPath,
        [string]$logPath = $settings.logPath,
        [string]$installTag = "$($localPath)\install.tag",
        [string]$logName = "startMigrate.log"
    )
    try {
        Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName $logName -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
        Write-Log -Message "========== Starting startMigrate.ps1 ==========" -Level INFO
        
        if(!(Test-Path $localPath))
        {
            mkdir $localPath
            Write-Log -Message "Created $($localPath)." -Level INFO
        }
        else
        {
            Write-Log -Message "$($localPath) already exists." -Level INFO
        }
        $global:localPath = $localPath
        $context = whoami
        Write-Log -Message "Running as $($context)." -Level INFO
        New-Item -Path $installTag -ItemType file -Force
        Write-Log -Message "Created $($installTag)." -Level INFO
        return $localPath
    } catch {
        Write-Error "Failed to initialize logging: $_"
        Exit 1
    }
}

# copy package files
function copyPackageFiles()
{
    Param(
        [string]$destination = $localPath
    )
    Copy-Item -Path "$($PSScriptRoot)\*" -Destination $destination -Recurse -Force
    Write-Log -Message "Copied files to $($destination)." -Level INFO
}

# authenticate to source tenant
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

# get device info
function getDeviceInfo()
{
    Param(
        [string]$hostname = $env:COMPUTERNAME,
        [string]$serialNumber = (Get-WmiObject -Class Win32_BIOS | Select-Object SerialNumber).SerialNumber,
        [string]$osBuild = (Get-WmiObject -Class Win32_OperatingSystem | Select-Object BuildNumber).BuildNumber
    )
    $global:deviceInfo = @{
        "hostname" = $hostname
        "serialNumber" = $serialNumber
        "osBuild" = $osBuild
    }
    foreach($key in $deviceInfo.Keys)
    {
        Write-Log -Message "$($key): $($deviceInfo[$key])" -Level INFO
    }
}

# get user info
function getUserInfo()
{
    [CmdletBinding()]
    param (
        [string]$Username = $settings.ws1username,
        [string]$ApiKey = $settings.ws1apikey,
        [string]$Password = $settings.ws1password,
		[string]$regPath = $settings.regPath,
        [string]$ws1host = $settings.ws1host
    )

    # Set TLS 1.2 protocol
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


    # Convert the password to a secure string
    $PasswordSecureString = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($Username, $PasswordSecureString)

    # Retrieve the serial number of the device
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

        # Encode credentials to Base64 for Basic Auth
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Credential.UserName + ':' + $Credential.GetNetworkCredential().Password)
    $base64Cred = [Convert]::ToBase64String($bytes)

    # Prepare the header for the REST call
    $header = @{
        "Authorization"  = "Basic $base64cred";
        "aw-tenant-code" = $ApiKey;
        "Accept"         = "application/json;version=1";
       # "Accept"         = "application/json;version=2";
        "Content-Type"   = "application/json";
    }

     # Invoke the REST API to get user information
   $deviceuri = "https://$ws1host/API/mdm/devices?id=$serialNumber&searchby=Serialnumber"
   $deviceresult = Invoke-RestMethod -Method Get -Uri $deviceuri -Header $header
   $email = $deviceresult.UserEmailAddress
   $username = $deviceresult.UserName
  
        $UserInfo = @{
            "UPN" = $email
            "userName" = $username
        }

        # Set registry keys
 foreach($key in $UserInfo.Keys)
    {
        New-Variable -Name $key -Value $UserInfo[$key] -Scope Global -Force
        if([string]::IsNullOrEmpty($UserInfo[$key]))
        {
            Write-Log -Message "Failed to set $($key) to registry." -Level INFO
        }
        else 
        {
            reg.exe add $regPath /v "$($key)" /t REG_SZ /d "$($UserInfo[$key])" /f | Out-Host
            Write-Log -Message "Set $($key) to $($UserInfo[$key]) at $regPath." -Level INFO
        }
    }
    }
     
# get device info from source tenant
function getDeviceGraphInfo()
{
    Param(
        [string]$hostname = $deviceInfo.hostname,
        [string]$serialNumber = $deviceInfo.serialNumber,
        [string]$regPath = $settings.regPath,
        [string]$groupTag = $settings.groupTag,
        [string]$intuneUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices",
        [string]$autopilotUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
    )
    Write-Log -Message "Getting Intune object for $($hostname)..." -Level INFO
    $intuneObject = Invoke-RestMethod -Uri "$($intuneUri)?`$filter=contains(serialNumber,'$($serialNumber)')" -Headers $headers -Method Get
    if(($intuneObject.'@odata.count') -eq 1)
    {
        $intuneID = $intuneObject.value.id
        Write-Log -Message "Intune ID: $($intuneID)" -Level INFO
    }
    else
    {
        Write-Log -Message "Failed to get Intune object for $($hostname)." -Level INFO
    }
    Write-Log -Message "Getting Autopilot object for $($hostname)..." -Level INFO
    $autopilotObject = Invoke-RestMethod -Uri "$($autopilotUri)?`$filter=contains(serialNumber,'$($serialNumber)')" -Headers $headers -Method Get
    if(($autopilotObject.'@odata.count') -eq 1)
    {
        $autopilotID = $autopilotObject.value.id
        Write-Log -Message "Autopilot ID: $($autopilotID)" -Level INFO
    }
    else
    {
        Write-Log -Message "Failed to get Autopilot object for $($hostname)." -Level INFO
    }
    if([string]::IsNullOrEmpty($groupTag))
    {
        Write-Log -Message "Group tag is not set in JSON; getting from graph..." -Level INFO
        $groupTag = $autopilotObject.value.groupTag
    }
    else 
    {
        Write-Log -Message "Group tag is set in JSON; using $($groupTag)." -Level INFO
    }
    $global:deviceGraphInfo = @{
        "intuneID" = $intuneID
        "autopilotID" = $autopilotID
        "groupTag" = $groupTag
    }
    foreach($key in $global:deviceGraphInfo.Keys)
    {
        if([string]::IsNullOrEmpty($global:deviceGraphInfo[$key]))
        {
            Write-Log -Message "Failed to set $($key) to registry." -Level INFO
        }
        else 
        {
            reg.exe add $regPath /v "$($key)" /t REG_SZ /d "$($global:deviceGraphInfo[$key])" /f | Out-Host
            Write-Log -Message "Set $($key) to $($global:deviceGraphInfo[$key]) at $regPath." -Level INFO
        }
    }
}

# set account creation policy
function setAccountConnection()
{
    Param(
        [string]$regPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Accounts",
        [string]$regKey = "Registry::$regPath",
        [string]$regName = "AllowMicrosoftAccountConnection",
        [int]$regValue = 1
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

# Function to prevent display of last username on login screen
function dontDisplayLastUsername() {
    Param(
        [string]$regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$regKey = "Registry::$regPath",
        [string]$regName = "DontDisplayLastUserName",
        [int]$regValue = 1
    )
    
    $taskName = "Configuring Login Screen Settings"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        $currentRegValue = Get-ItemPropertyValue -Path $regKey -Name $regName -ErrorAction SilentlyContinue
        
        if ($currentRegValue -eq $regValue) {
            Write-Log -Message "$regName is already set to $regValue." -Level INFO
        } else {
            Write-Log -Message "Setting $regName to $regValue..." -Level INFO
            reg.exe add $regPath /v $regName /t REG_DWORD /d $regValue /f | Out-Null
            Write-Log -Message "Successfully set $regName to $regValue at $regPath." -Level INFO
        }
        
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
        return $true
    } catch {
        Write-Log -Message "Error configuring login screen settings: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        return $false
    }
}

# remove mdm certificate
function removeMDMCertificate()
{
    Param(
        [string]$certPath = 'Cert:\LocalMachine\My',
        [string]$issuer = "Microsoft Intune MDM Device CA"
    )
    Get-ChildItem -Path $certPath | Where-Object { $_.Issuer -match $issuer } | Remove-Item -Force
    Write-Log -Message "Removed $($issuer) certificate." -Level INFO
}

# remove mdm enrollment
function removeMDMEnrollments()
{
    Param(
        [string]$enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments\"
    )
    $enrollments = Get-ChildItem -Path $enrollmentPath
    foreach($enrollment in $enrollments)
    {
        $object = Get-ItemProperty Registry::$enrollment
        $discovery = $object."DiscoveryServiceFullURL"
        if($discovery -eq "https://ds1380.awmdm.com/DeviceServices/discovery.aws")
        {
            $enrollPath = $enrollmentPath + $object.PSChildName
            Remove-Item -Path $enrollPath -Recurse
            Write-Log -Message "Removed $($enrollPath)." -Level INFO
        }
    }
    $global:enrollID = $enrollPath.Split("\")[-1]
    $additionaPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\Provinsioning\OMADM\Accounts\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions\$($enrollID)"
    )
    foreach($path in $additionaPaths)
    {
        Remove-Item -Path $path -Recurse
        Write-Log -Message "Removed $($path)." -Level INFO
    }
}

# remove mdm scheduled tasks
function removeMDMTasks()
{
    Param(
        [string]$taskPath = "\Microsoft\Windows\EnterpriseMgmt",
        [string]$enrollID = $enrollID
    )
    $mdmTasks = Get-ScheduledTask -TaskPath "$($taskPath)\$($enrollID)\" -ErrorAction Ignore
    if($mdmTasks -gt 0)
    {
        foreach($task in $mdmTasks)
        {
            Write-Log -Message "Removing $($task.Name)..." -Level INFO
            try
            {
                Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false
                Write-Log -Message "Removed $($task.Name)." -Level INFO
            }
            catch
            {
                $message = $_.Exception.Message
                Write-Log -Message "Failed to remove $($task.Name): $($message)." -Level INFO
            }
        }
    }
    else
    {
        Write-Log -Message "No MDM tasks found." -Level INFO
    }
}
# set post migration tasks
function setPostMigrationTasks()
{
    Param(
        [string]$localPath = $localPath,
        [array]$tasks = @("middleboot")
    )
    foreach($task in $tasks)
    {
        $taskPath = "$($localPath)\$($task).xml"
        if($taskPath)
        {
            schtasks.exe /Create /TN $task /XML $taskPath
            Write-Log -Message "Created $($task) task." -Level INFO
        }
        else
        {
            Write-Log -Message "Failed to create $($task) task: $taskPath not found." -Level INFO
        }     
    }
}

# check for AAD join and remove
function leaveAazureADJoin() {
    param (
        [string]$joinType = "AzureAdJoined",
        [string]$hostname = $deviceInfo.hostname,
        [string]$dsregCmd = "C:\Windows\System32\dsregcmd.exe"
    )
    Write-Log -Message "Checking for Azure AD join..." -Level INFO
    $joinStatus = joinStatus -joinType $joinType
    if($joinStatus -eq "YES")
    {
        Write-Log -Message "$hostname is Azure AD joined: leaving..." -Level INFO
        Start-Process -FilePath $dsregCmd -ArgumentList "/leave"
        Write-Log -Message "Left Azure AD join." -Level INFO
    }
    else
    {
        Write-Log -Message "$hostname is not Azure AD joined." -Level INFO
    }
}

# check for domain join and remove
function unjoinDomain()
{
    Param(
        [string]$joinType = "DomainJoined",
        [string]$hostname = $deviceInfo.hostname
    )
    Write-Log -Message "Checking for domain join..." -Level INFO
    $joinStatus = joinStatus -joinType $joinType
    if($joinStatus -eq "YES")
    {
        $password = generatePassword -length 12
        Write-Log -Message "Checking for local admin account..." -Level INFO
        $adminStatus = getAdminStatus
        if($adminStatus -eq $false)
        {
            Write-Log -Message "Admin account is disabled; setting password and enabling..." -Level INFO
            Set-LocalUser -Name "Administrator" -Password $password -PasswordNeverExpires $true
            Get-LocalUser -Name "Administrator" | Enable-LocalUser
            Write-Log -Message "Enabled Administrator account and set password." -Level INFO
        }
        else 
        {
            Write-Log -Message "Admin account is enabled; setting password..." -Level INFO
            Set-LocalUser -Name "Administrator" -Password $password -PasswordNeverExpires $true
            Write-Log -Message "Set Administrator password." -Level INFO
        }
        $cred = New-Object System.Management.Automation.PSCredential ("$hostname\Administrator", $password)
        Write-Log -Message "Unjoining domain..." -Level INFO
        Remove-Computer -UnjoinDomainCredential $cred -Force -PassThru -Verbose
        Write-Log -Message "$hostname unjoined domain." -Level INFO    
    }
    else
    {
        Write-Log -Message "$hostname is not domain joined." -Level INFO
    }
}

##Delete WS1 Device

function DeleteWS1Device {
    param(
        [string]$Username = $settings.ws1username,
        [string]$ApiKey = $settings.ws1apikey,
        [string]$Password = $settings.ws1password,
        [string]$ws1host = $settings.ws1host
    )

    # Securely convert the password
    $PasswordSecureString = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($Username, $PasswordSecureString)

    # Get the serial number of the device
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

    # Encode credentials to Base64 for Basic Auth
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Credential.UserName + ":" + $Credential.GetNetworkCredential().Password)
    $base64Cred = [Convert]::ToBase64String($bytes)
    
    # Headers
    $headers = @{
        Authorization  = "Basic $base64Cred"
        "aw-tenant-code" = $ApiKey
        Accept         = "application/json;version=1"
        "Content-Type" = "application/json"
    }

    Write-Log -Message "Getting device details from WS1..." -Level INFO
    
    # Invoke Rest Method to get Device ID and Enterprise Wipe Device while retaining apps
    try {
        $deviceuri = "https://$ws1host/API/mdm/devices?id=$serialNumber&searchby=SerialNumber"
        $deviceresult = Invoke-RestMethod -Method Get -Uri $deviceuri -Headers $headers
        $deviceid = $deviceresult.Id.value
        
        Write-Log -Message "Found device ID: $deviceid" -Level INFO
        
        invoke-restmethod "https://$ws1host/API/mdm/devices/$deviceid/commands?command=EnterpriseWipe&reason=Migration&keep_apps_on_device=true" -Headers $headers -Method Post
        Write-Log -Message "Enterprise wipe command sent, waiting until WS1 wipe completes..." -Level INFO
        
        Start-Sleep -s 10
        while(Get-Process -Name AWACMClient -ErrorAction SilentlyContinue){
            Write-Log -Message "WS1 still active..." -Level INFO
            Start-Sleep -s 10
        }
        Write-Log -Message "WS1 wipe completed" -Level INFO
    }
    catch {
        Write-Log -Message "Error during WS1 device wipe: $_" -Level ERROR
        throw $_
    }
}

# Function to uninstall Workspace ONE Hub
function uninstallWS1Hub() {
    Param(
        [string]$appNamePattern = "Workspace ONE Intelligent Hub"
    )
    
    $taskName = "Uninstalling WS1 Hub"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Searching for $appNamePattern application..." -Level INFO
        $app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match $appNamePattern }
        
        if ($app) {
            Write-Log -Message "Found $($app.Name) version $($app.Version). Attempting to uninstall..." -Level INFO
            $uninstallResult = $app.Uninstall()
            
            if ($uninstallResult.ReturnValue -eq 0) {
                Write-Log -Message "$($app.Name) has been successfully uninstalled." -Level INFO
                Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
                return $true
            } else {
                Write-Log -Message "Failed to uninstall $($app.Name). Return code: $($uninstallResult.ReturnValue)" -Level ERROR
                Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
                return $false
            }
        } else {
            Write-Log -Message "No application matching '$appNamePattern' was found." -Level WARNING
            Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
            return $true
        }
    } catch {
        Write-Log -Message "Error during WS1 Hub uninstallation: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        return $false
    }
}

# Function to install provisioning package with better error handling
function InstallPPKGPackage() {
    Param(
        [string]$osBuild = $deviceInfo.osBuild,
        [string]$ppkg = (Get-ChildItem -Path $localPath -Filter "*.ppkg" -Recurse).FullName
    )
    
    $taskName = "Installing Provisioning Package"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        if ($ppkg) {
            Write-Log -Message "Found provisioning package: $ppkg" -Level INFO
            
            # Check if the Provisioning module is available
            if (Get-Command Install-ProvisioningPackage -ErrorAction SilentlyContinue) {
                $result = Install-ProvisioningPackage -PackagePath $ppkg -QuietInstall -ForceInstall
                Write-Log -Message "Provisioning package installed successfully." -Level INFO
                Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
                return $true
            } else {
                Write-Log -Message "Provisioning module not available. Attempting alternative installation..." -Level WARNING
                
                # Try alternative method using DISM
                if (Test-Path "C:\Windows\System32\Provisioning\Packages") {
                    Copy-Item -Path $ppkg -Destination "C:\Windows\System32\Provisioning\Packages" -Force
                    Write-Log -Message "Copied provisioning package to system folder." -Level INFO
                    Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
                    return $true
                } else {
                    Write-Log -Message "Failed to install provisioning package: Provisioning folder not found." -Level ERROR
                    Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
                    return $false
                }
            }
        } else {
            Write-Log -Message "Provisioning package not found." -Level WARNING
            Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
            return $false
        }
    } catch {
        Write-Log -Message "Error installing provisioning package: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        return $false
    }
}

# delete graph objects in source tenant
function deleteGraphObjects()
{
    Param(
        [string]$intuneID = $deviceGraphInfo.intuneID,
        [string]$autopilotID = $deviceGraphInfo.autopilotID,
        [string]$intuneUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices",
        [string]$autopilotUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
    )
    if(![string]::IsNullOrEmpty($intuneID))
    {
        Invoke-RestMethod -Uri "$($intuneUri)/$($intuneID)" -Headers $headers -Method Delete
        Start-Sleep -Seconds 2
        Write-Log -Message "Deleted Intune object." -Level INFO
    }
    else
    {
        Write-Log -Message "Intune object not found." -Level INFO
    }
    if(![string]::IsNullOrEmpty($autopilotID))
    {
        Invoke-RestMethod -Uri "$($autopilotUri)/$($autopilotID)" -Headers $headers -Method Delete
        Start-Sleep -Seconds 2
        Write-Log -Message "Deleted Autopilot object." -Level INFO   
    }
    else
    {
        Write-Log -Message "Autopilot object not found." -Level INFO
    }
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

# set auto logon policy
function setAutoLogon()
{
    Param(
        [string]$migrationAdmin = "MigrationInProgress",
        [string]$autoLogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
        [string]$autoLogonName = "AutoAdminLogon",
        [string]$autoLogonValue = 1,
        [string]$defaultUserName = "DefaultUserName",
        [string]$defaultPW = "DefaultPassword"
    )
    Write-Log -Message "Create migration admin account..." -Level INFO
    $migrationPassword = generatePassword
    New-LocalUser -Name $migrationAdmin -Password $migrationPassword
    Add-LocalGroupMember -Group "Administrators" -Member $migrationAdmin
    Write-Log -Message "Migration admin account created: $($migrationAdmin)." -Level INFO

    Write-Log -Message "Setting auto logon..." -Level INFO
    reg.exe add $autoLogonPath /v $autoLogonName /t REG_SZ /d $autoLogonValue /f | Out-Host
    reg.exe add $autoLogonPath /v $defaultUserName /t REG_SZ /d $migrationAdmin /f | Out-Host
    reg.exe add $autoLogonPath /v $defaultPW /t REG_SZ /d "@Password*123" /f | Out-Host
    Write-Log -Message "Set auto logon to $($migrationAdmin)." -Level INFO
}

# Function to set lock screen caption with legal notice
function setLockScreenCaption() {
    Param(
        [string]$targetTenantName = $settings.targetTenant.tenantName,
        [string]$legalNoticeRegPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        [string]$legalNoticeCaption = "legalnoticecaption",
        [string]$legalNoticeCaptionValue = "Migration in Progress...",
        [string]$legalNoticeText = "legalnoticetext",
        [string]$legalNoticeTextValue = "Your PC is being migrated to $targetTenantName and will reboot automatically within 30 seconds. Please do not turn off your PC."
    )
    
    $taskName = "Setting Lock Screen Caption"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Setting lock screen caption and legal notice text..." -Level INFO
        
        # Add caption
        reg.exe add $legalNoticeRegPath /v $legalNoticeCaption /t REG_SZ /d $legalNoticeCaptionValue /f | Out-Null
        Write-Log -Message "Lock screen caption set to: $legalNoticeCaptionValue" -Level INFO
        
        # Add text
        reg.exe add $legalNoticeRegPath /v $legalNoticeText /t REG_SZ /d $legalNoticeTextValue /f | Out-Null
        Write-Log -Message "Lock screen text set successfully." -Level INFO
        
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
        return $true
    } catch {
        Write-Log -Message "Error setting lock screen caption: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        return $false
    }
}

# SCRIPT FUNCTIONS END

# run getSettingsJSON
try 
{
    getSettingsJSON
    Write-Log -Message "Retrieved settings JSON." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get settings JSON: $message." -Level INFO  
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1  
}

# run initializeScript
try 
{
    initializeScript
    Write-Log -Message "Initialized script." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to initialize script: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}
# run copyPackageFiles
try 
{
    copyPackageFiles
    Write-Log -Message "Copied package files." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to copy package files: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}

# run msGraphAuthenticate
try 
{
    msGraphAuthenticate
    Write-Log -Message "Authenticated to MS Graph." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to authenticate to MS Graph: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}

# run getDeviceInfo
try 
{
    getDeviceInfo
    Write-Log -Message "Got device info." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get device info: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}

# run getUserInfo
try 
{
    getUserInfo
    Write-Log -Message "Got original user info." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get original user info: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}

# run getDeviceGraphInfo
try 
{
    getDeviceGraphInfo
    Write-Log -Message "Got device graph info." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to get device graph info: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}

# run dontDisplayLastUsername
try 
{
    dontDisplayLastUsername
    Write-Log -Message "Set dont display last username." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set dont display last username: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}


# run removeMDMTasks
try 
{
    removeMDMTasks
    Write-Log -Message "Removed MDM tasks." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to remove MDM tasks: $message." -Level INFO
    Write-Log -Message "Warning: Validate device integrity post migration." -Level INFO
}


# run setPostMigrationTasks
try 
{
    setPostMigrationTasks
    Write-Log -Message "Set post migration tasks." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set post migration tasks: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}

# run AazureADJoin
try 
{
    leaveAazureADJoin
    Write-Log -Message "Unjoined Entra ID." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to unjoin Entra: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}

# run unjoinDomain
try 
{
    unjoinDomain
    Write-Log -Message "Unjoined domain." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to unjoin domain: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}

# run DeleteWS1Device 
try 
{
    DeleteWS1Device 
    Write-Log -Message "Deleted WS1 Device." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to delete graph objects: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}

# run InstallPPKGPackage
try 
{
    InstallPPKGPackage
    Write-Log -Message "Installed provisioning package." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to install provisioning package: $message." -Level INFO
    Write-Log -Message "Exiting script." -Level INFO
    Exit 1
}

# run setLockScreenCaption
try 
{
    setLockScreenCaption
    Write-Log -Message "Set lock screen caption." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to set lock screen caption: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}

# run uninstallWS1Hub
try 
{
    uninstallWS1Hub
    Write-Log -Message "Uninstalled WS1 Hub." -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Failed to uninstall WS1 Hub: $message." -Level INFO
    Write-Log -Message "WARNING: Validate device integrity post migration." -Level INFO
}

# run reboot
Write-Log -Message "Rebooting device..." -Level INFO
shutdown -r -t 30

# end transcript
# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
