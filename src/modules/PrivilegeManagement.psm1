################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# PowerShell module providing Write-LogMessage function for Workspace ONE to Azure/Intune mi...                            #
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
$script:TaskPath = "\WS1Migration\"
$script:ElevatedOperationTimeout = 600 # seconds
$script:TempScriptPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "WS1Migration")
$script:LogPath = "C:\Temp\Logs\PrivilegeOps_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Import the logging module if available
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
    # Create a basic logging function if the module is not available
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
        
        $logFile = Join-Path -Path $script:LogPath -ChildPath "PrivilegeOps.log"
        Add-Content -Path $logFile -Value $logMessage
    }
}

function Initialize-PrivilegeManagement {
    <#
    .SYNOPSIS
        Initializes the privilege management module.
    .DESCRIPTION
        Sets up necessary paths and validates the environment for privilege elevation operations.
    .EXAMPLE
        Initialize-PrivilegeManagement
    #>
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "Initializing Privilege Management module" -Level INFO
    
    # Ensure temp directory exists
    if (-not (Test-Path -Path $script:TempScriptPath)) {
        try {
            New-Item -Path $script:TempScriptPath -ItemType Directory -Force | Out-Null
            Write-LogMessage -Message "Created temporary script directory: $script:TempScriptPath" -Level INFO
        } catch {
            Write-LogMessage -Message "Failed to create temporary script directory: $_" -Level ERROR
            throw
        }
    }
    
    # Check if Task Scheduler service is running
    $schedulerService = Get-Service -Name "Schedule"
    if ($schedulerService.Status -ne "Running") {
        Write-LogMessage -Message "Task Scheduler service is not running. Attempting to start..." -Level WARNING
        try {
            Start-Service -Name "Schedule"
            Write-LogMessage -Message "Task Scheduler service started successfully" -Level INFO
        } catch {
            Write-LogMessage -Message "Failed to start Task Scheduler service: $_" -Level ERROR
            throw "Cannot proceed with privilege elevation as Task Scheduler service cannot be started."
        }
    }
    
    Write-LogMessage -Message "Privilege Management module initialized successfully" -Level INFO
}

function Invoke-ElevatedOperation {
    <#
    .SYNOPSIS
        Executes a scriptblock with elevated privileges.
    .DESCRIPTION
        Uses Task Scheduler to run a scriptblock with SYSTEM privileges.
    .PARAMETER ScriptBlock
        The scriptblock to execute with elevated privileges.
    .PARAMETER ArgumentList
        Optional arguments to pass to the scriptblock.
    .PARAMETER Timeout
        Timeout in seconds for the operation (default: 600).
    .EXAMPLE
        Invoke-ElevatedOperation -ScriptBlock { Install-WindowsFeature -Name RSAT }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [object[]]$ArgumentList,
        
        [Parameter()]
        [int]$Timeout = $script:ElevatedOperationTimeout
    )
    
    Write-LogMessage -Message "Preparing to execute operation with elevated privileges" -Level INFO
    
    # Create a unique identifier for this operation
    $operationId = [guid]::NewGuid().ToString()
    $taskName = "$script:ElevationTaskName-$operationId"
    
    # Create scripts directory if it doesn't exist
    if (-not (Test-Path -Path $script:TempScriptPath)) {
        New-Item -Path $script:TempScriptPath -ItemType Directory -Force | Out-Null
    }
    
    # Create a script file with the operation
    $scriptPath = Join-Path -Path $script:TempScriptPath -ChildPath "$operationId.ps1"
    $statusPath = Join-Path -Path $script:TempScriptPath -ChildPath "$operationId-status.xml"
    
    try {
        # Create the script file
        $scriptContent = @"
`$ErrorActionPreference = 'Stop'
`$statusPath = '$statusPath'

try {
    # Implement the script block
    `$result = & {
        $ScriptBlock
    } $($ArgumentList -join ' ')
    
    # Save the result
    `$status = @{
        Success = `$true
        Result = `$result
        Error = `$null
    }
    Export-Clixml -Path `$statusPath -InputObject `$status -Force
} catch {
    # Save the error information
    `$status = @{
        Success = `$false
        Result = `$null
        Error = `$_.Exception.Message
        ErrorRecord = `$_
    }
    Export-Clixml -Path `$statusPath -InputObject `$status -Force
}
"@
        
        Set-Content -Path $scriptPath -Value $scriptContent -Force
        Write-LogMessage -Message "Created temporary script file: $scriptPath" -Level INFO
        
        # Create the scheduled task
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -StartWhenAvailable
        
        # Create the task
        $taskExists = Get-ScheduledTask -TaskName $taskName -TaskPath $script:TaskPath -ErrorAction SilentlyContinue
        if ($taskExists) {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $script:TaskPath -Confirm:$false | Out-Null
        }
        
        # Create task folder if it doesn't exist
        $taskFolder = Get-ScheduledTaskFolder -Path $script:TaskPath -ErrorAction SilentlyContinue
        if (-not $taskFolder) {
            $scheduleService = New-Object -ComObject "Schedule.Service"
            $scheduleService.Connect()
            $rootFolder = $scheduleService.GetFolder("\")
            $rootFolder.CreateFolder($script:TaskPath.TrimStart("\").TrimEnd("\"))
        }
        
        $task = Register-ScheduledTask -TaskName $taskName -TaskPath $script:TaskPath -Action $action -Principal $principal -Settings $settings -Force
        Write-LogMessage -Message "Registered scheduled task: $($script:TaskPath)$taskName" -Level INFO
        
        # Start the task
        Start-ScheduledTask -TaskName $taskName -TaskPath $script:TaskPath
        Write-LogMessage -Message "Started scheduled task" -Level INFO
        
        # Wait for the task to complete or timeout
        $startTime = Get-Date
        $statusCreated = $false
        
        while (((Get-Date) - $startTime).TotalSeconds -lt $Timeout) {
            # Check if the task has completed
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $script:TaskPath
            if ($taskInfo.LastTaskResult -ne 267009) { # 267009 = Task is still running
                Write-LogMessage -Message "Task completed with result code: $($taskInfo.LastTaskResult)" -Level INFO
                break
            }
            
            # Check if the status file has been created
            if (Test-Path -Path $statusPath) {
                $statusCreated = $true
                break
            }
            
            Start-Sleep -Seconds 1
        }
        
        # Check if the operation timed out
        if (((Get-Date) - $startTime).TotalSeconds -ge $Timeout) {
            Write-LogMessage -Message "Operation timed out after $Timeout seconds" -Level WARNING
            throw "Elevated operation timed out after $Timeout seconds"
        }
        
        # Read the status file
        if ($statusCreated) {
            $status = Import-Clixml -Path $statusPath
            
            if ($status.Success) {
                Write-LogMessage -Message "Elevated operation completed successfully" -Level INFO
                return $status.Result
            } else {
                Write-LogMessage -Message "Elevated operation failed: $($status.Error)" -Level ERROR
                throw $status.Error
            }
        } else {
            Write-LogMessage -Message "Status file was not created. The operation may have failed silently." -Level ERROR
            throw "Elevated operation did not produce a status file. Check system logs for details."
        }
    } finally {
        # Cleanup
        if (Test-Path -Path $scriptPath) {
            Remove-Item -Path $scriptPath -Force
        }
        
        if (Test-Path -Path $statusPath) {
            Remove-Item -Path $statusPath -Force
        }
        
        # Unregister the task
        try {
            $taskExists = Get-ScheduledTask -TaskName $taskName -TaskPath $script:TaskPath -ErrorAction SilentlyContinue
            if ($taskExists) {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath $script:TaskPath -Confirm:$false | Out-Null
                Write-LogMessage -Message "Unregistered scheduled task" -Level INFO
            }
        } catch {
            Write-LogMessage -Message "Failed to unregister scheduled task: $_" -Level WARNING
        }
    }
}

function Get-ScheduledTaskFolder {
    <#
    .SYNOPSIS
        Checks if a scheduled task folder exists.
    .DESCRIPTION
        Uses the Schedule.Service COM object to check if a task folder exists.
    .PARAMETER Path
        The path of the task folder to check.
    .EXAMPLE
        Get-ScheduledTaskFolder -Path "\MyFolder\"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $scheduleService = New-Object -ComObject "Schedule.Service"
    $scheduleService.Connect()
    
    try {
        $folder = $scheduleService.GetFolder($Path)
        return $folder
    } catch {
        return $null
    }
}

function New-TemporaryAdminAccount {
    <#
    .SYNOPSIS
        Creates a temporary local administrator account.
    .DESCRIPTION
        Creates a temporary local administrator account with a complex random password.
    .PARAMETER Prefix
        A prefix for the username (default: "WS1Mig").
    .PARAMETER PasswordLength
        The length of the generated password (default: 20).
    .EXAMPLE
        $adminCreds = New-TemporaryAdminAccount -Prefix "Migration"
    #>
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter()]
        [string]$Prefix = "WS1Mig",
        
        [Parameter()]
        [int]$PasswordLength = 20
    )
    
    Write-LogMessage -Message "Creating temporary admin account" -Level INFO
    
    # Generate a random username with prefix
    $randomSuffix = [guid]::NewGuid().ToString().Substring(0, 8)
    $username = "$Prefix-$randomSuffix"
    
    # Generate a complex random password
    $charSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}|;:',<.>/?"
    $securePassword = New-Object System.Security.SecureString
    
    $random = New-Object System.Random
    
    # Ensure password meets complexity requirements
    $hasLower = $false
    $hasUpper = $false
    $hasDigit = $false
    $hasSpecial = $false
    
    for ($i = 0; $i -lt $PasswordLength; $i++) {
        $randomIndex = $random.Next(0, $charSet.Length)
        $randomChar = $charSet[$randomIndex]
        $securePassword.AppendChar($randomChar)
        
        if ($randomChar -cmatch '[a-z]') { $hasLower = $true }
        if ($randomChar -cmatch '[A-Z]') { $hasUpper = $true }
        if ($randomChar -cmatch '[0-9]') { $hasDigit = $true }
        if ($randomChar -match '[^a-zA-Z0-9]') { $hasSpecial = $true }
    }
    
    # Ensure we meet complexity requirements
    if (-not ($hasLower -and $hasUpper -and $hasDigit -and $hasSpecial)) {
        # If not, generate a new password that meets requirements
        $securePassword = New-Object System.Security.SecureString
        
        $securePassword.AppendChar('P') # Uppercase
        $securePassword.AppendChar('a') # Lowercase
        $securePassword.AppendChar('5') # Digit
        $securePassword.AppendChar('!') # Special
        
        for ($i = 4; $i -lt $PasswordLength; $i++) {
            $randomIndex = $random.Next(0, $charSet.Length)
            $securePassword.AppendChar($charSet[$randomIndex])
        }
    }
    
    # Create credential object
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    
    # Create the account
    try {
        $createAccountScript = {
            param($Username, $Password)
            
            # Convert from secure string
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            
            # Create the user account
            $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
            $user = $computer.Create("User", $Username)
            $user.SetPassword($plainPassword)
            $user.SetInfo()
            
            # Set account properties
            $user.Description = "Temporary admin account for Workspace One to Azure migration"
            $user.UserFlags = 66049 # ADS_UF_DONT_EXPIRE_PASSWD + ADS_UF_SCRIPT
            $user.SetInfo()
            
            # Add to administrators group
            $group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
            $group.Add("WinNT://$env:COMPUTERNAME/$Username,user")
            
            # Return success
            return $true
        }
        
        # Create the account with elevated privileges
        $result = Invoke-ElevatedOperation -ScriptBlock $createAccountScript -ArgumentList @($credential.UserName, $credential.Password)
        
        if ($result) {
            Write-LogMessage -Message "Successfully created temporary admin account: $($credential.UserName)" -Level INFO
            return $credential
        } else {
            throw "Failed to create temporary admin account"
        }
    } catch {
        Write-LogMessage -Message "Error creating temporary admin account: $_" -Level ERROR
        throw
    }
}

function Remove-TemporaryAdminAccount {
    <#
    .SYNOPSIS
        Removes a temporary local administrator account.
    .DESCRIPTION
        Safely removes a temporary local administrator account created by New-TemporaryAdminAccount.
    .PARAMETER Credential
        The credential object for the account to remove.
    .EXAMPLE
        Remove-TemporaryAdminAccount -Credential $adminCreds
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )
    
    Write-LogMessage -Message "Removing temporary admin account: $($Credential.UserName)" -Level INFO
    
    try {
        $removeAccountScript = {
            param($Username)
            
            try {
                # Remove the user
                $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
                $computer.Delete("User", $Username)
                return $true
            } catch {
                return $false
            }
        }
        
        # Remove the account with elevated privileges
        $result = Invoke-ElevatedOperation -ScriptBlock $removeAccountScript -ArgumentList @($Credential.UserName)
        
        if ($result) {
            Write-LogMessage -Message "Successfully removed temporary admin account: $($Credential.UserName)" -Level INFO
            return $true
        } else {
            Write-LogMessage -Message "Failed to remove temporary admin account: $($Credential.UserName)" -Level WARNING
            return $false
        }
    } catch {
        Write-LogMessage -Message "Error removing temporary admin account: $_" -Level ERROR
        throw
    }
}

function Invoke-ComObjectElevation {
    <#
    .SYNOPSIS
        Performs elevation using COM object methods.
    .DESCRIPTION
        Uses various COM objects to perform operations with elevated privileges.
    .PARAMETER ScriptBlock
        The scriptblock to execute with elevated privileges.
    .PARAMETER ComObjectName
        The COM object to use for elevation.
    .EXAMPLE
        Invoke-ComObjectElevation -ScriptBlock { Restart-Service -Name Spooler } -ComObjectName "Shell.Application"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [ValidateSet("Shell.Application", "WScript.Shell")]
        [string]$ComObjectName = "Shell.Application"
    )
    
    Write-LogMessage -Message "Using COM object elevation with $ComObjectName" -Level INFO
    
    # Create a temporary script file
    $scriptPath = Join-Path -Path $script:TempScriptPath -ChildPath "ComElevation_$([guid]::NewGuid().ToString()).ps1"
    
    try {
        # Create the script content
        $scriptContent = @"
`$ErrorActionPreference = 'Stop'
try {
    & {
        $ScriptBlock
    }
    exit 0
} catch {
    Write-Error `$_.Exception.Message
    exit 1
}
"@
        
        Set-Content -Path $scriptPath -Value $scriptContent -Force
        
        # Use the appropriate COM object for elevation
        switch ($ComObjectName) {
            "Shell.Application" {
                $shell = New-Object -ComObject "Shell.Application"
                $shell.ShellExecute("powershell.exe", "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`"", "", "runas", 1)
            }
            "WScript.Shell" {
                $wshell = New-Object -ComObject "WScript.Shell"
                $wshell.Run("powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`"", 1, $true)
            }
        }
        
        Write-LogMessage -Message "COM object elevation completed" -Level INFO
    } catch {
        Write-LogMessage -Message "COM object elevation failed: $_" -Level ERROR
        throw
    } finally {
        # Clean up the temporary script file
        if (Test-Path -Path $scriptPath) {
            Remove-Item -Path $scriptPath -Force
        }
    }
}

# Initialize the module
Initialize-PrivilegeManagement

# Export the module members
Export-ModuleMember -Function Invoke-ElevatedOperation, New-TemporaryAdminAccount, Remove-TemporaryAdminAccount, Invoke-ComObjectElevation 




