# Enhanced Logging Module for Migration Scripts

## Overview

The `LoggingModule.psm1` provides standardized, robust logging capabilities for all scripts in the Intune Migration project. It offers structured logging with various log levels, console output with colored formatting, file logging, and optional Windows Event Log integration.

## Features

- **Multiple Log Levels**: DEBUG, INFO, WARNING, ERROR, and CRITICAL
- **Automatic Timestamping**: All log entries include precise timestamps
- **Color-Coded Console Output**: Different colors for different log levels
- **File Logging**: Persistent logs saved to files
- **Windows Event Log Integration**: Optional logging to Windows Event Log
- **Transcript Support**: Automatic PowerShell transcript generation
- **System Information Logging**: Ability to capture detailed system information for troubleshooting
- **Task Duration Tracking**: Measure and log the duration of operations

## Installation

The module is automatically imported by all migration scripts. If you need to manually import it:

```powershell
Import-Module "$PSScriptRoot\LoggingModule.psm1" -Force
```

## Usage

### Initializing Logging

Before using any logging functions, initialize the logging system:

```powershell
Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "myScript.log" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
```

Parameters:
- `LogPath`: Directory where log files will be saved
- `LogFileName`: Name of the log file (optional, defaults to script name with timestamp)
- `Level`: Minimum log level to record (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- `EnableConsoleOutput`: Whether to display logs in the console
- `EnableEventLog`: Whether to write to Windows Event Log
- `StartTranscript`: Whether to start a PowerShell transcript

### Writing Log Messages

```powershell
Write-Log -Message "Operation completed successfully" -Level INFO
Write-Log -Message "Warning: Resource not found" -Level WARNING
Write-Log -Message "Error accessing file: Access denied" -Level ERROR
```

### Tracking Tasks

```powershell
# Start a task and get the start time
$taskStartTime = Start-LogTask -Name "Creating User Profile" -Description "Creating a new user profile for migration"

try {
    # Your code here
    
    # Complete the task successfully
    Complete-LogTask -Name "Creating User Profile" -StartTime $taskStartTime -Success $true
}
catch {
    # Log the failure
    Write-Log -Message "Failed to create user profile: $_" -Level ERROR
    Complete-LogTask -Name "Creating User Profile" -StartTime $taskStartTime -Success $false
    throw $_
}
```

### Logging System Information

To capture detailed system information for troubleshooting:

```powershell
Write-SystemInfo
```

This will log OS version, computer model, memory, disk space, and network configuration.

### Changing Log Level

You can change the log level during script execution:

```powershell
Set-LoggingLevel -Level DEBUG  # Show more detailed logs
Set-LoggingLevel -Level ERROR  # Show only errors and critical issues
```

## Best Practices

1. **Initialize Logging Early**: Call Initialize-Logging at the beginning of your script
2. **Use Appropriate Levels**:
   - DEBUG: Detailed debugging information
   - INFO: General information about script progress
   - WARNING: Potential issues that don't stop execution
   - ERROR: Errors that allow the script to continue
   - CRITICAL: Severe errors that will likely cause the script to fail
3. **Track Tasks**: Use Start-LogTask and Complete-LogTask for important operations
4. **Capture Exceptions**: Always log exceptions with proper context
5. **Include Relevant Data**: Include important identifiers in log messages

## Updating Scripts to Use Enhanced Logging

The `UpdateScriptsWithLogging.ps1` utility script can automatically update all PowerShell scripts in the project to use the enhanced logging module:

```powershell
.\UpdateScriptsWithLogging.ps1
```

This will:
1. Add the module import to each script
2. Replace basic log function calls with enhanced logging calls
3. Add proper error handling and task tracking
4. Create backups of all modified files 