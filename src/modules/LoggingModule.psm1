################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# This module provides standardized logging functions that can be used across all scripts in...                            #
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
This module provides standardized logging functions that can be used across all scripts in the project.
.EXAMPLE
Import-Module "$PSScriptRoot\LoggingModule.psm1"
.NOTES
Version: 1.0
Author: Modern Windows Management
RequiredVersion: PowerShell 5.1 or higher
#>

# Log levels
enum LogLevel {
    DEBUG = 0
    INFO = 1
    WARNING = 2
    ERROR = 3
    CRITICAL = 4
}

# Global variables
$script:LogLevel = [LogLevel]::INFO
$script:LogFile = $null
$script:LogPath = $null
$script:ConsoleOutput = $true
$script:LogToEventLog = $false
$script:EventLogSource = "WS1_Enrollment"
$script:EventLogName = "Application"

# Initialize logging
function Initialize-Logging {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$LogPath = "C:\Temp\Logs",
        
        [Parameter()]
        [string]$LogFileName = $null,
        
        [Parameter()]
        [LogLevel]$Level = [LogLevel]::INFO,
        
        [Parameter()]
        [bool]$EnableConsoleOutput = $true,
        
        [Parameter()]
        [bool]$EnableEventLog = $false,
        
        [Parameter()]
        [bool]$StartTranscript = $true
    )
    
    # Create log directory if it doesn't exist
    if (!(Test-Path $LogPath)) {
        try {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Output "Created log directory: $LogPath"
        } catch {
            Write-Error "Failed to create log directory: $LogPath. Error: $_"
            return $false
        }
    }
    
    # Set default log filename if not provided
    if ([string]::IsNullOrEmpty($LogFileName)) {
        $scriptName = Split-Path -Leaf $MyInvocation.PSCommandPath
        if ([string]::IsNullOrEmpty($scriptName)) {
            $scriptName = "script"
        }
        $LogFileName = "$($scriptName.Replace('.ps1', ''))_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
    
    # Set global variables
    $script:LogLevel = $Level
    $script:LogFile = Join-Path $LogPath $LogFileName
    $script:LogPath = $LogPath
    $script:ConsoleOutput = $EnableConsoleOutput
    $script:LogToEventLog = $EnableEventLog
    
    # Create initial log entry
    Write-LogMessage -Message "Logging initialized. Log file: $($script:LogFile)" -Level INFO
    
    # Start transcript if enabled
    if ($StartTranscript) {
        Start-Transcript -Path "$LogPath\$($LogFileName.Replace('.log', '_transcript.log'))" -Verbose -Force
        Write-LogMessage -Message "Transcript started" -Level INFO
    }
    
    # Create event log source if needed
    if ($EnableEventLog) {
        try {
            if (![System.Diagnostics.EventLog]::SourceExists($script:EventLogSource)) {
                [System.Diagnostics.EventLog]::CreateEventSource($script:EventLogSource, $script:EventLogName)
                Write-LogMessage -Message "Event log source created: $($script:EventLogSource)" -Level INFO
            }
        } catch {
            Write-LogMessage -Message "Failed to create event log source: $($script:EventLogSource). Error: $_" -Level ERROR
            $script:LogToEventLog = $false
        }
    }
    
    # Return success
    return $true
}

# Write to log file
function Write-LogMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [LogLevel]$Level = [LogLevel]::INFO,
        
        [Parameter()]
        [string]$Component = $(Split-Path -Leaf $MyInvocation.PSCommandPath)
    )
    
    # Skip logging if level is below threshold
    if ([int]$Level -lt [int]$script:LogLevel) {
        return
    }
    
    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    
    # Format message
    $logMessage = "[$timestamp] [$Level] [$Component] $Message"
    
    # Write to file if log file is defined
    if ($null -ne $script:LogFile) {
        try {
            Add-Content -Path $script:LogFile -Value $logMessage -Force
        } catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
    
    # Write to console if enabled
    if ($script:ConsoleOutput) {
        switch ($Level) {
            ([LogLevel]::DEBUG) { Write-Host $logMessage -ForegroundColor Gray }
            ([LogLevel]::INFO) { Write-Host $logMessage -ForegroundColor White }
            ([LogLevel]::WARNING) { Write-Host $logMessage -ForegroundColor Yellow }
            ([LogLevel]::ERROR) { Write-Host $logMessage -ForegroundColor Red }
            ([LogLevel]::CRITICAL) { Write-Host $logMessage -ForegroundColor Red -BackgroundColor Black }
        }
    }
    
    # Write to event log if enabled
    if ($script:LogToEventLog) {
        try {
            $eventType = switch ($Level) {
                ([LogLevel]::DEBUG) { "Information" }
                ([LogLevel]::INFO) { "Information" }
                ([LogLevel]::WARNING) { "Warning" }
                ([LogLevel]::ERROR) { "Error" }
                ([LogLevel]::CRITICAL) { "Error" }
            }
            
            Write-EventLog -LogName $script:EventLogName -Source $script:EventLogSource -EntryType $eventType -EventId (1000 + [int]$Level) -Message $Message
        } catch {
            Write-Warning "Failed to write to event log: $_"
        }
    }
}

# Get current log level
function Get-LoggingLevel {
    return $script:LogLevel
}

# Set log level
function Set-LoggingLevel {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [LogLevel]$Level
    )
    
    $oldLevel = $script:LogLevel
    $script:LogLevel = $Level
    
    Write-LogMessage -Message "Log level changed from $oldLevel to $Level" -Level INFO
    return $Level
}

# Log system information for troubleshooting
function Write-SystemInfo {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "====== System Information ======" -Level INFO
    
    # OS Information
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        Write-LogMessage -Message "OS: $($os.Caption) $($os.Version) Build $($os.BuildNumber)" -Level INFO
        Write-LogMessage -Message "Last Boot: $($os.LastBootUpTime)" -Level INFO
    } catch {
        Write-LogMessage -Message "Failed to retrieve OS information: $_" -Level WARNING
    }
    
    # Computer Information
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        Write-LogMessage -Message "Computer: $($cs.Manufacturer) $($cs.Model)" -Level INFO
        Write-LogMessage -Message "RAM: $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB" -Level INFO
    } catch {
        Write-LogMessage -Message "Failed to retrieve computer information: $_" -Level WARNING
    }
    
    # CPU Information
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor
        Write-LogMessage -Message "CPU: $($cpu.Name)" -Level INFO
    } catch {
        Write-LogMessage -Message "Failed to retrieve CPU information: $_" -Level WARNING
    }
    
    # Network Information
    try {
        $network = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -ne $null }
        foreach ($adapter in $network) {
            Write-LogMessage -Message "Network Adapter: $($adapter.Description)" -Level INFO
            Write-LogMessage -Message "   IP Address: $($adapter.IPAddress[0])" -Level INFO
        }
    } catch {
        Write-LogMessage -Message "Failed to retrieve network information: $_" -Level WARNING
    }
    
    # Disk Information
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        foreach ($disk in $disks) {
            $freeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
            $totalSpace = [math]::Round($disk.Size / 1GB, 2)
            $percentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            Write-LogMessage -Message "Disk $($disk.DeviceID): Free: $freeSpace GB of $totalSpace GB ($percentFree% free)" -Level INFO
        }
    } catch {
        Write-LogMessage -Message "Failed to retrieve disk information: $_" -Level WARNING
    }
    
    Write-LogMessage -Message "====== End System Information ======" -Level INFO
}

# Helper function to log the start of a task
function Start-LogTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [string]$Description = ""
    )
    
    Write-LogMessage -Message "===== STARTING TASK: $Name =====" -Level INFO
    if (-not [string]::IsNullOrEmpty($Description)) {
        Write-LogMessage -Message "Description: $Description" -Level INFO
    }
    
    # Return start time for duration calculation
    return (Get-Date)
}

# Helper function to log the end of a task
function Complete-LogTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [DateTime]$StartTime = $null,
        
        [Parameter()]
        [bool]$Success = $true
    )
    
    if ($null -ne $StartTime) {
        $duration = (Get-Date) - $StartTime
        $durationStr = "{0:hh\:mm\:ss\.fff}" -f $duration
        
        if ($Success) {
            Write-LogMessage -Message "===== COMPLETED TASK: $Name (Duration: $durationStr) =====" -Level INFO
        } else {
            Write-LogMessage -Message "===== FAILED TASK: $Name (Duration: $durationStr) =====" -Level ERROR
        }
    } else {
        if ($Success) {
            Write-LogMessage -Message "===== COMPLETED TASK: $Name =====" -Level INFO
        } else {
            Write-LogMessage -Message "===== FAILED TASK: $Name =====" -Level ERROR
        }
    }
}

# Export all functions
Export-ModuleMember -Function Initialize-Logging, Write-LogMessage, Get-LoggingLevel, Set-LoggingLevel, Write-SystemInfo, Start-LogTask, Complete-LogTask 





