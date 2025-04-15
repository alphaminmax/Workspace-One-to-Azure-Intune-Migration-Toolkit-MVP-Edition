<# AUTOPILOTREGISTRATION.PS1
Synopsis
AutopilotRegistration.ps1 is the last script in the device migration process.
DESCRIPTION
This script is used to register the PC in the destination tenant Autopilot environment.  Will use a group tag if available.
USE
.\AutopilotRegistration.ps1
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

# Import logging module
$loggingModulePath = "$PSScriptRoot\LoggingModule.psm1"
if (Test-Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
} else {
    Write-Error "Logging module not found at $loggingModulePath"
    Exit 1
}

# SCRIPT FUNCTIONS

# get json settings
function getSettingsJSON()
{
    Param(
        [string]$json = "settings.json"
    )
    
    $taskName = "Reading Settings JSON"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        $global:settings = Get-Content -Path "$($PSScriptRoot)\$($json)" | ConvertFrom-Json
        Write-Log -Message "Settings loaded successfully from $json" -Level INFO
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
        return $settings
    }
    catch {
        Write-Log -Message "Failed to load settings from $json. Error: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# initialize script
function initializeScript()
{
    Param(
        [string]$logPath = $settings.logPath,
        [string]$logName = "autopilotRegistration.log",
        [string]$localPath = $settings.localPath
    )
    
    $taskName = "Initializing Script"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
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
        
        # Gather system information for troubleshooting
        Write-SystemInfo
        
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
        return $localPath
    }
    catch {
        Write-Log -Message "Failed to initialize script. Error: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# disable scheduled task
function disableAutopilotRegistrationTask()
{
    Param(
        [string]$taskName = "AutopilotRegistration"
    )
    
    $logTaskName = "Disabling AutopilotRegistration Task"
    $taskStartTime = Start-LogTask -Name $logTaskName
    
    try {
        Disable-ScheduledTask -TaskName $taskName
        Write-Log -Message "AutopilotRegistration task disabled" -Level INFO
        Complete-LogTask -Name $logTaskName -StartTime $taskStartTime -Success $true
    }
    catch {
        Write-Log -Message "Failed to disable AutopilotRegistration task: $_" -Level ERROR
        Complete-LogTask -Name $logTaskName -StartTime $taskStartTime -Success $false
        throw $_
    }   
}

# install modules
function installModules()
{
    Param(
        [string]$nuget = "NuGet",
        [string[]]$modules = @(
            "Microsoft.Graph.Intune",
            "WindowsAutoPilotIntune"
        )
    )
    
    $taskName = "Installing Required Modules"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Checking for NuGet..." -Level INFO
        $installedNuGet = Get-PackageProvider -Name $nuget -ListAvailable -ErrorAction SilentlyContinue
        if(-not($installedNuGet))
        {      
            Write-Log -Message "Installing NuGet package provider..." -Level INFO
            Install-PackageProvider -Name $nuget -Confirm:$false -Force
            Write-Log -Message "NuGet successfully installed" -Level INFO    
        }
        else
        {
            Write-Log -Message "NuGet already installed" -Level INFO
        }
        
        Write-Log -Message "Checking for required modules..." -Level INFO
        foreach($module in $modules)
        {
            Write-Log -Message "Checking for $module..." -Level INFO
            $installedModule = Get-Module -Name $module -ErrorAction SilentlyContinue
            if(-not($installedModule))
            {
                Write-Log -Message "Installing module $module..." -Level INFO
                Install-Module -Name $module -Confirm:$false -Force
                Import-Module $module
                Write-Log -Message "$module successfully installed" -Level INFO
            }
            else
            {
                Import-Module $module
                Write-Log -Message "$module already installed" -Level INFO
            }
        }
        
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
    }
    catch {
        Write-Log -Message "Failed to install modules: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# authenticate ms graph
function msGraphAuthenticate()
{
    Param(
        [string]$tenant = $settings.targetTenant.tenantName,
        [string]$clientId = $settings.targetTenant.clientId,
        [string]$clientSecret = $settings.targetTenant.clientSecret,
        [string]$tenantId = $settings.targetTenant.tenantId
    )
    
    $taskName = "Authenticating to Microsoft Graph"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Authenticating to Microsoft Graph for tenant $tenant..." -Level INFO
        $clientSecureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
        $clientSecretCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $clientId,$clientSecureSecret
        Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $clientSecretCredential
        Write-Log -Message "Authenticated to $($tenant) Microsoft Graph" -Level INFO
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
    }
    catch {
        Write-Log -Message "Failed to authenticate to Microsoft Graph: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# get autopilot info
function getAutopilotInfo()
{
    Param(
        [string]$serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber,
        [string]$hardwareIdentifier = ((Get-WmiObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData)
    )
    
    $taskName = "Getting Autopilot Device Info"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Collecting Autopilot device info..." -Level INFO
        if([string]::IsNullOrWhiteSpace($serialNumber)) 
        { 
            $serialNumber = $env:COMPUTERNAME
            Write-Log -Message "Serial number was empty, using computer name: $serialNumber" -Level WARNING
        }
        
        if([string]::IsNullOrWhiteSpace($hardwareIdentifier)) {
            Write-Log -Message "Hardware identifier is null or empty, this may cause registration to fail" -Level WARNING
        } else {
            Write-Log -Message "Hardware identifier successfully retrieved" -Level DEBUG
        }
        
        $global:autopilotInfo = @{
            serialNumber = $serialNumber
            hardwareIdentifier = $hardwareIdentifier
        }
        
        Write-Log -Message "Autopilot device info collected: Serial=$serialNumber" -Level INFO
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
        return $autopilotInfo    
    }
    catch {
        Write-Log -Message "Failed to collect Autopilot device info: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# register autopilot device
function autopilotRegister()
{
    Param(
        [string]$regPath = $settings.regPath,
        [string]$regKey = "Registry::$regPath",
        [string]$serialNumber = $autopilotInfo.serialNumber,
        [string]$hardwareIdentifier = $autopilotInfo.hardwareIdentifier,
        [string]$groupTag = (Get-ItemPropertyValue -Path $regKey -Name "GroupTag")
    )
    
    $taskName = "Registering Device in Autopilot"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Registering Autopilot device..." -Level INFO
        
        if([string]::IsNullOrWhiteSpace($groupTag))
        {
            Write-Log -Message "No group tag found, registering without group tag" -Level INFO
            Add-AutopilotImportedDevice -serialNumber $serialNumber -hardwareIdentifier $hardwareIdentifier
            Write-Log -Message "Autopilot device registered" -Level INFO
        }
        else 
        {
            Write-Log -Message "Registering with group tag: $groupTag" -Level INFO
            Add-AutopilotImportedDevice -serialNumber $serialNumber -hardwareIdentifier $hardwareIdentifier -groupTag $groupTag
            Write-Log -Message "Autopilot device registered with group tag $groupTag" -Level INFO
        }
        
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
    }
    catch {
        Write-Log -Message "Failed to register Autopilot device: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# END SCRIPT FUNCTIONS

# START SCRIPT

# Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "autopilotRegistration.log" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
    Write-Log -Message "========== Starting AutopilotRegistration.ps1 ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: $_"
    Exit 1
}

# get settings
try 
{
    getSettingsJSON
    Write-Log -Message "Settings retrieved" -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Error getting settings: $message" -Level ERROR
    Write-Log -Message "Exiting script" -Level ERROR
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
    Write-Log -Message "Error initializing script: $message" -Level ERROR
    Write-Log -Message "Exiting script" -Level ERROR
    Exit 1    
}

# disable scheduled task
try 
{
    disableAutopilotRegistrationTask
    Write-Log -Message "AutopilotRegistration task disabled" -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "AutopilotRegistration task not disabled: $message" -Level ERROR
    Write-Log -Message "Exiting script" -Level ERROR
    Exit 1
}

# install modules
try 
{
    installModules
    Write-Log -Message "Modules installed" -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Error installing modules: $message" -Level ERROR
    Write-Log -Message "Exiting script" -Level ERROR
    Exit 1
}

# authenticate ms graph
try 
{
    msGraphAuthenticate
    Write-Log -Message "Authenticated to Microsoft Graph" -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Error authenticating to Microsoft Graph: $message" -Level ERROR
    Write-Log -Message "Exiting script" -Level ERROR
    Exit 1
}

# get autopilot info
try 
{
    getAutopilotInfo
    Write-Log -Message "Autopilot device info collected" -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Error collecting Autopilot device info: $message" -Level ERROR
    Write-Log -Message "Exiting script" -Level ERROR
    Exit 1
}

# register autopilot device
try 
{
    autopilotRegister
    Write-Log -Message "Autopilot device registered" -Level INFO
}
catch 
{
    $message = $_.Exception.Message
    Write-Log -Message "Error registering Autopilot device: $message" -Level WARNING
    Write-Log -Message "WARNING: Try to manually register the device in Autopilot" -Level WARNING
}

# END SCRIPT

# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
# Script completion
Write-Log -Message "========== Script completed ==========" -Level INFO
Stop-Transcript
