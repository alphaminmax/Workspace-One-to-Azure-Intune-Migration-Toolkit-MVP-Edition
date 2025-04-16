[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', 'Module', Justification='False positive in comment-based help')]
param()

################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Module for registering devices with Microsoft Autopilot during migration from Workspace ON...                            #
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
    Module for registering devices with Microsoft Autopilot during migration from Workspace ONE to Azure/Intune.
.DESCRIPTION
    The AutopilotIntegration module provides functions to register devices with Microsoft Autopilot
    as part of the migration process from Workspace ONE to Azure/Intune. This module leverages
    the Autopilot-Manager solution for device registration and integrates with privilege elevation
    mechanisms to enable non-admin users to execute admin-level operations.
    
    This module should be used after the ConfigurationPreservation module has backed up user settings
    and before the final migration to Azure/Intune.
.NOTES
    Part of the Workspace One to Azure/Intune Migration Toolkit
    
    Common usage scenarios:
    * Register device with Microsoft Autopilot during migration
    * Validate migration status before Autopilot registration
    * Securely handle credentials for Autopilot registration
    * Enable non-admin users to trigger admin-level operations
#>

# Module variables
$script:LogPath = "C:\Temp\Logs\AutopilotIntegration_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\config\AutopilotConfig.json"
$script:ApiBaseUrl = "https://autopilotmanager.azurewebsites.net/api"
$script:ValidateUrl = "$script:ApiBaseUrl/validate"
$script:RegisterUrl = "$script:ApiBaseUrl/registerdevice"
$script:ApprovalUrl = "$script:ApiBaseUrl/approval"

# Import required modules
$loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath "LoggingModule.psm1"
if (Test-Path -Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
    # Initialize logging if not already initialized
    if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        Initialize-Logging -LogPath $script:LogPath -Level INFO
    }
} else {
    # Create a basic logging function if module not available
    function Write-LogMessage {
        param (
            [string]$Message,
            [string]$Level = "INFO"
        )
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Write to console
        switch ($Level) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            default { Write-Host $logMessage }
        }
        
        # Write to log file
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        
        $logFile = Join-Path -Path $script:LogPath -ChildPath "AutopilotIntegration.log"
        Add-Content -Path $logFile -Value $logMessage
    }
}

# Try to import PrivilegeManagement module for elevation
$privMgmtPath = Join-Path -Path $PSScriptRoot -ChildPath "PrivilegeManagement.psm1"
$script:PrivilegeManagementAvailable = $false
if (Test-Path -Path $privMgmtPath) {
    try {
        Import-Module $privMgmtPath -Force
        $script:PrivilegeManagementAvailable = $true
        Write-LogMessage -Message "PrivilegeManagement module loaded successfully" -Level INFO
    } catch {
        Write-LogMessage -Message "Failed to load PrivilegeManagement module: $_" -Level WARNING
    }
}

function Initialize-AutopilotIntegration {
    <#
    .SYNOPSIS
        Initializes the Autopilot Integration module.
    .DESCRIPTION
        Sets up necessary configurations for Autopilot Integration, including
        loading API endpoints, authentication settings, and validating prerequisites.
    .PARAMETER ConfigPath
        Optional path to a JSON configuration file with Autopilot settings.
    .EXAMPLE
        Initialize-AutopilotIntegration -ConfigPath "C:\Path\To\AutopilotConfig.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $script:ConfigPath
    )
    
    Write-LogMessage -Message "Initializing Autopilot Integration module" -Level INFO
    
    # Check if configuration file exists
    if (Test-Path -Path $ConfigPath) {
        try {
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            
            # Update endpoints if specified
            if ($config.ApiBaseUrl) {
                $script:ApiBaseUrl = $config.ApiBaseUrl
                $script:ValidateUrl = "$script:ApiBaseUrl/validate"
                $script:RegisterUrl = "$script:ApiBaseUrl/registerdevice"
                $script:ApprovalUrl = "$script:ApiBaseUrl/approval"
                Write-LogMessage -Message "API endpoints set to: $script:ApiBaseUrl" -Level INFO
            }
            
            Write-LogMessage -Message "Configuration loaded successfully from: $ConfigPath" -Level INFO
            return $true
        } catch {
            Write-LogMessage -Message "Error loading configuration: $_" -Level WARNING
            Write-LogMessage -Message "Using default configuration" -Level INFO
        }
    } else {
        Write-LogMessage -Message "Configuration file not found at: $ConfigPath. Using default values." -Level WARNING
    }
    
    # Check for required PowerShell modules
    $requiredModules = @("Microsoft.Graph.Intune", "WindowsAutopilotIntune")
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-LogMessage -Message "Missing required PowerShell modules: $($missingModules -join ', ')" -Level WARNING
        Write-LogMessage -Message "Some functionality may be limited" -Level WARNING
    }
    
    # Validate privilege elevation capability
    if (-not $script:PrivilegeManagementAvailable) {
        Write-LogMessage -Message "PrivilegeManagement module not available. Autopilot registration may require administrator privileges." -Level WARNING
    }
    
    return $true
}

function Get-DeviceAutopilotInfo {
    <#
    .SYNOPSIS
        Retrieves device hardware information required for Autopilot registration.
    .DESCRIPTION
        Collects hardware information including serial number, hardware hash, and 
        Windows Product ID required for registering a device with Microsoft Autopilot.
    .EXAMPLE
        $deviceInfo = Get-DeviceAutopilotInfo
    #>
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "Retrieving device Autopilot information" -Level INFO
    
    try {
        # This operation requires admin privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            if ($script:PrivilegeManagementAvailable) {
                Write-LogMessage -Message "Using privilege elevation for device info collection" -Level INFO
                $result = Invoke-ElevatedOperation -ScriptBlock {
                    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
                    $manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
                    $model = (Get-WmiObject -Class Win32_ComputerSystem).Model
                    
                    # Try to get the hardware hash
                    $hardwareHash = $null
                    try {
                        # Use Get-WindowsAutoPilotInfo if available
                        if (Get-Command Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue) {
                            $tempFile = [System.IO.Path]::GetTempFileName() + ".csv"
                            Get-WindowsAutoPilotInfo -OutputFile $tempFile
                            $autopilotInfo = Import-Csv -Path $tempFile
                            $hardwareHash = $autopilotInfo.DeviceHash
                            Remove-Item -Path $tempFile -Force
                        } else {
                            # Fallback to manual collection
                            $hardwareHash = (Get-WmiObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
                        }
                    } catch {
                        # Hardware hash collection might fail - log warning
                        Write-LogMessage -Message "Failed to collect hardware hash: $_" -Level WARNING
                    }
                    
                    $deviceInfo = @{
                        SerialNumber = $serialNumber
                        Manufacturer = $manufacturer
                        Model = $model
                        HardwareHash = $hardwareHash
                        ComputerName = $env:COMPUTERNAME
                        Windows10Version = [System.Environment]::OSVersion.Version.ToString()
                    }
                    
                    return $deviceInfo
                }
                
                return $result
            } else {
                Write-LogMessage -Message "Administrator privileges required for collecting device hash" -Level ERROR
                throw "Administrator privileges required for collecting device hash"
            }
        } else {
            # Already running as admin, collect directly
            $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
            $manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
            $model = (Get-WmiObject -Class Win32_ComputerSystem).Model
            
            # Try to get the hardware hash
            $hardwareHash = $null
            try {
                # Use Get-WindowsAutoPilotInfo if available
                if (Get-Command Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue) {
                    $tempFile = [System.IO.Path]::GetTempFileName() + ".csv"
                    Get-WindowsAutoPilotInfo -OutputFile $tempFile
                    $autopilotInfo = Import-Csv -Path $tempFile
                    $hardwareHash = $autopilotInfo.DeviceHash
                    Remove-Item -Path $tempFile -Force
                } else {
                    # Fallback to manual collection
                    $hardwareHash = (Get-WmiObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
                }
            } catch {
                # Hardware hash collection might fail - log warning
                Write-LogMessage -Message "Failed to collect hardware hash: $_" -Level WARNING
            }
            
            $deviceInfo = @{
                SerialNumber = $serialNumber
                Manufacturer = $manufacturer
                Model = $model
                HardwareHash = $hardwareHash
                ComputerName = $env:COMPUTERNAME
                Windows10Version = [System.Environment]::OSVersion.Version.ToString()
            }
            
            return $deviceInfo
        }
    } catch {
        Write-LogMessage -Message "Failed to retrieve device Autopilot information: $_" -Level ERROR
        throw "Failed to retrieve device Autopilot information: $_"
    }
}

function Test-MigrationStatus {
    <#
    .SYNOPSIS
        Validates the migration status before proceeding with Autopilot registration.
    .DESCRIPTION
        Performs checks to determine if the device is ready for Autopilot registration
        as part of the Workspace ONE to Azure/Intune migration process.
    .EXAMPLE
        $isReady = Test-MigrationStatus
    #>
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "Validating migration status" -Level INFO
    
    try {
        # Check if Workspace ONE components are properly removed
        $ws1Components = @(
            "C:\Program Files (x86)\AirWatch\Agent",
            "C:\Program Files\AirWatch\Agent",
            "C:\Program Files (x86)\VMware\IntelligentHub",
            "C:\Program Files\VMware\IntelligentHub"
        )
        
        $foundComponents = $false
        foreach ($component in $ws1Components) {
            if (Test-Path -Path $component) {
                Write-LogMessage -Message "Workspace ONE component still present: $component" -Level WARNING
                $foundComponents = $true
            }
        }
        
        if ($foundComponents) {
            Write-LogMessage -Message "Workspace ONE components still present. Migration may not be complete." -Level WARNING
            return $false
        }
        
        # Check for user configuration backup
        $configBackupPath = "C:\Temp\UserConfigBackup"
        if (-not (Test-Path -Path $configBackupPath)) {
            Write-LogMessage -Message "User configuration backup not found at $configBackupPath" -Level WARNING
            return $false
        }
        
        # Check network connectivity to Microsoft services
        $msEndpoints = @(
            "login.microsoftonline.com",
            "graph.microsoft.com",
            "enrollmentserver.microsoft.com",
            "device.login.microsoftonline.com"
        )
        
        $connectivityIssues = $false
        foreach ($endpoint in $msEndpoints) {
            try {
                $testConnection = Test-NetConnection -ComputerName $endpoint -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
                if (-not $testConnection) {
                    Write-LogMessage -Message "Cannot reach Microsoft endpoint - ${endpoint}" -Level WARNING
                    $connectivityIssues = $true
                }
            } catch {
                Write-LogMessage -Message "Error testing connectivity to ${endpoint}: ${_}" -Level WARNING
                $connectivityIssues = $true
            }
        }
        
        if ($connectivityIssues) {
            Write-LogMessage -Message "Connectivity issues detected with Microsoft services" -Level WARNING
            return $false
        }
        
        # Validate registry keys for migration tracking
        $migrationRegPath = "HKLM:\SOFTWARE\CompanyName\Migration"
        if (Test-Path -Path $migrationRegPath) {
            try {
                $migrationStatus = Get-ItemPropertyValue -Path $migrationRegPath -Name "Status" -ErrorAction SilentlyContinue
                if ($migrationStatus -ne "ReadyForAutopilot") {
                    Write-LogMessage -Message "Migration status is not ready for Autopilot: $migrationStatus" -Level WARNING
                    return $false
                }
            } catch {
                Write-LogMessage -Message "Failed to read migration status from registry: $_" -Level WARNING
                return $false
            }
        } else {
            Write-LogMessage -Message "Migration registry path not found: $migrationRegPath" -Level WARNING
            return $false
        }
        
        Write-LogMessage -Message "Migration status validated successfully" -Level INFO
        return $true
    } catch {
        Write-LogMessage -Message "Error validating migration status: $_" -Level ERROR
        return $false
    }
}

function Register-DeviceInAutopilot {
    <#
    .SYNOPSIS
        Registers the current device with Microsoft Autopilot.
    .DESCRIPTION
        Collects device information and registers it with Microsoft Autopilot using
        the Autopilot-Manager service. This enables seamless enrollment to Intune after
        migrating from Workspace ONE.
    .PARAMETER GroupTag
        Optional group tag to assign to the device in Autopilot.
    .PARAMETER AssignedUser
        Optional UPN of the user to assign to the device in Autopilot.
    .PARAMETER ApiKey
        API key for authenticating with the Autopilot-Manager service.
        If not provided, will attempt to retrieve from Azure Key Vault or config file.
    .EXAMPLE
        Register-DeviceInAutopilot -GroupTag "Migration-Wave1" -AssignedUser "john.doe@contoso.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$GroupTag = "WS1Migration",
        
        [Parameter(Mandatory = $false)]
        [string]$AssignedUser,
        
        [Parameter(Mandatory = $false)]
        [string]$ApiKey
    )
    
    Write-LogMessage -Message "Starting Autopilot registration process" -Level INFO
    
    # First, validate migration status
    $migrationReady = Test-MigrationStatus
    if (-not $migrationReady) {
        Write-LogMessage -Message "Device not ready for Autopilot registration. Please complete migration prerequisites." -Level ERROR
        throw "Device not ready for Autopilot registration. Please complete migration prerequisites."
    }
    
    try {
        # Get device information (requires admin privileges)
        Write-LogMessage -Message "Collecting device hardware information" -Level INFO
        $deviceInfo = Get-DeviceAutopilotInfo
        
        if (-not $deviceInfo.HardwareHash) {
            Write-LogMessage -Message "Failed to retrieve hardware hash, required for Autopilot registration" -Level ERROR
            throw "Failed to retrieve hardware hash, required for Autopilot registration"
        }
        
        # Get API key if not provided
        if (-not $ApiKey) {
            # Try to load from config
            if (Test-Path -Path $script:ConfigPath) {
                try {
                    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
                    $ApiKey = $config.ApiKey
                } catch {
                    Write-LogMessage -Message "Failed to load API key from config: $_" -Level WARNING
                }
            }
            
            # If still no API key, try Azure Key Vault if available
            if ((-not $ApiKey) -and (Get-Command Get-SecureCredential -ErrorAction SilentlyContinue)) {
                try {
                    $keyVaultSecret = Get-SecureCredential -SecretName "AutopilotManagerApiKey"
                    if ($keyVaultSecret) {
                        $ApiKey = $keyVaultSecret.GetNetworkCredential().Password
                    }
                } catch {
                    Write-LogMessage -Message "Failed to retrieve API key from Key Vault: $_" -Level WARNING
                }
            }
            
            # If still no API key, prompt user if in interactive mode
            if (-not $ApiKey) {
                $interactive = [Environment]::UserInteractive
                if ($interactive) {
                    $secureApiKey = Read-Host -Prompt "Enter Autopilot-Manager API key" -AsSecureString
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
                    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
                } else {
                    Write-LogMessage -Message "No API key provided and not in interactive mode" -Level ERROR
                    throw "No API key provided for Autopilot-Manager"
                }
            }
        }
        
        # If still no API key, fail
        if (-not $ApiKey) {
            Write-LogMessage -Message "No API key available for Autopilot-Manager" -Level ERROR
            throw "No API key available for Autopilot-Manager"
        }
        
        # Prepare registration payload
        $registrationPayload = @{
            HardwareHash = $deviceInfo.HardwareHash
            SerialNumber = $deviceInfo.SerialNumber
            Manufacturer = $deviceInfo.Manufacturer
            Model = $deviceInfo.Model
            GroupTag = $GroupTag
            ComputerName = $deviceInfo.ComputerName
        }
        
        # Add assigned user if specified
        if ($AssignedUser) {
            $registrationPayload.AssignedUser = $AssignedUser
        }
        
        # Convert payload to JSON
        $jsonPayload = $registrationPayload | ConvertTo-Json
        
        # Set up headers with API key
        $headers = @{
            "Content-Type" = "application/json"
            "x-api-key" = $ApiKey
        }
        
        # Call the Autopilot-Manager API to register the device
        Write-LogMessage -Message "Sending registration request to Autopilot-Manager" -Level INFO
        
        $response = $null
        try {
            $response = Invoke-RestMethod -Uri $script:RegisterUrl -Method POST -Headers $headers -Body $jsonPayload
            
            if ($response.id) {
                Write-LogMessage -Message "Device successfully registered with request ID: $($response.id)" -Level INFO
                
                # If the service requires approval, provide information
                if ($response.requiresApproval) {
                    Write-LogMessage -Message "Registration requires approval before processing" -Level INFO
                    Write-LogMessage -Message "Approval status can be checked with request ID: $($response.id)" -Level INFO
                }
                
                # Store registration information in registry for tracking
                $regPath = "HKLM:\SOFTWARE\CompanyName\Migration\Autopilot"
                if (-not (Test-Path -Path $regPath)) {
                    if ($script:PrivilegeManagementAvailable) {
                        Invoke-ElevatedOperation -ScriptBlock {
                            param($Path)
                            New-Item -Path $Path -Force | Out-Null
                        } -ArgumentList $regPath
                    } else {
                        # Try directly if running as admin
                        New-Item -Path $regPath -Force | Out-Null
                    }
                }
                
                # Store registration info
                if (Test-Path -Path $regPath) {
                    if ($script:PrivilegeManagementAvailable) {
                        Invoke-ElevatedOperation -ScriptBlock {
                            param($Path, $RequestId, $TimeStamp)
                            Set-ItemProperty -Path $Path -Name "RequestId" -Value $RequestId
                            Set-ItemProperty -Path $Path -Name "RegistrationTime" -Value $TimeStamp
                            Set-ItemProperty -Path $Path -Name "Status" -Value "Pending"
                        } -ArgumentList $regPath, $response.id, (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    } else {
                        # Try directly if running as admin
                        Set-ItemProperty -Path $regPath -Name "RequestId" -Value $response.id
                        Set-ItemProperty -Path $regPath -Name "RegistrationTime" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        Set-ItemProperty -Path $regPath -Name "Status" -Value "Pending"
                    }
                }
                
                return $response
            } else {
                Write-LogMessage -Message "Unexpected response from Autopilot-Manager service" -Level WARNING
                Write-LogMessage -Message "Response: $response" -Level WARNING
                throw "Unexpected response from Autopilot-Manager service"
            }
        } catch {
            Write-LogMessage -Message "Failed to register device with Autopilot-Manager: $_" -Level ERROR
            
            # Try to extract more details from response if available
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd()
                    Write-LogMessage -Message "Error response: $responseBody" -Level ERROR
                } catch {
                    Write-LogMessage -Message "Could not read error response: $_" -Level ERROR
                }
            }
            
            throw "Failed to register device with Autopilot-Manager: $_"
        }
    } catch {
        Write-LogMessage -Message "Error during Autopilot registration process: $_" -Level ERROR
        throw "Error during Autopilot registration process: $_"
    }
}

function Get-AutopilotRegistrationStatus {
    <#
    .SYNOPSIS
        Checks the status of an Autopilot registration request.
    .DESCRIPTION
        Queries the Autopilot-Manager service to retrieve the current status of
        a device registration request. This helps track the progress of a device
        through the Autopilot registration workflow.
    .PARAMETER RequestId
        The ID of the registration request to check.
    .PARAMETER ApiKey
        API key for authenticating with the Autopilot-Manager service.
        If not provided, will attempt to retrieve from Azure Key Vault or config file.
    .EXAMPLE
        Get-AutopilotRegistrationStatus -RequestId "12345678-1234-5678-1234-567812345678"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $false)]
        [string]$ApiKey
    )
    
    Write-LogMessage -Message "Checking Autopilot registration status for request ID: $RequestId" -Level INFO
    
    try {
        # Get API key if not provided (same logic as in Register-DeviceInAutopilot)
        if (-not $ApiKey) {
            # Try to load from config
            if (Test-Path -Path $script:ConfigPath) {
                try {
                    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
                    $ApiKey = $config.ApiKey
                } catch {
                    Write-LogMessage -Message "Failed to load API key from config: $_" -Level WARNING
                }
            }
            
            # If still no API key, try Azure Key Vault if available
            if ((-not $ApiKey) -and (Get-Command Get-SecureCredential -ErrorAction SilentlyContinue)) {
                try {
                    $keyVaultSecret = Get-SecureCredential -SecretName "AutopilotManagerApiKey"
                    if ($keyVaultSecret) {
                        $ApiKey = $keyVaultSecret.GetNetworkCredential().Password
                    }
                } catch {
                    Write-LogMessage -Message "Failed to retrieve API key from Key Vault: $_" -Level WARNING
                }
            }
            
            # If still no API key, prompt user if in interactive mode
            if (-not $ApiKey) {
                $interactive = [Environment]::UserInteractive
                if ($interactive) {
                    $secureApiKey = Read-Host -Prompt "Enter Autopilot-Manager API key" -AsSecureString
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
                    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
                } else {
                    Write-LogMessage -Message "No API key provided and not in interactive mode" -Level ERROR
                    throw "No API key provided for Autopilot-Manager"
                }
            }
        }
        
        # Set up headers with API key
        $headers = @{
            "Content-Type" = "application/json"
            "x-api-key" = $ApiKey
        }
        
        # Call the Autopilot-Manager API to check status
        $statusUrl = "$script:ApiBaseUrl/status/$RequestId"
        $response = Invoke-RestMethod -Uri $statusUrl -Method GET -Headers $headers
        
        # Process and return the status
        if ($response.id -eq $RequestId) {
            Write-LogMessage -Message "Registration status: $($response.status)" -Level INFO
            
            # Update registry if possible
            $regPath = "HKLM:\SOFTWARE\CompanyName\Migration\Autopilot"
            if (Test-Path -Path $regPath) {
                if ($script:PrivilegeManagementAvailable) {
                    Invoke-ElevatedOperation -ScriptBlock {
                        param($Path, $Status, $LastChecked)
                        Set-ItemProperty -Path $Path -Name "Status" -Value $Status
                        Set-ItemProperty -Path $Path -Name "LastChecked" -Value $LastChecked
                    } -ArgumentList $regPath, $response.status, (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                } else {
                    # Try directly if running as admin
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if ($isAdmin) {
                        Set-ItemProperty -Path $regPath -Name "Status" -Value $response.status
                        Set-ItemProperty -Path $regPath -Name "LastChecked" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                }
            }
            
            return $response
        } else {
            Write-LogMessage -Message "Unexpected response from Autopilot-Manager service" -Level WARNING
            Write-LogMessage -Message "Response: $response" -Level WARNING
            throw "Unexpected response from Autopilot-Manager service"
        }
    } catch {
        Write-LogMessage -Message "Failed to check Autopilot registration status: $_" -Level ERROR
        throw "Failed to check Autopilot registration status: $_"
    }
}

# Initialize the module
Initialize-AutopilotIntegration

# Export module members
Export-ModuleMember -Function Register-DeviceInAutopilot, Get-AutopilotRegistrationStatus, Test-MigrationStatus, Get-DeviceAutopilotInfo, Initialize-AutopilotIntegration 




