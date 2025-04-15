<# UPDATESCRIPTSWITHLOGGING.PS1
Synopsis
This script updates all PowerShell scripts in the project to use the new LoggingModule.psm1.
DESCRIPTION
This script automatically modifies all PowerShell scripts to use the enhanced logging module by:
1. Adding the module import at the beginning of each script
2. Replacing basic log() functions with Write-Log calls
3. Adding proper error handling and task tracking
USE
.\UpdateScriptsWithLogging.ps1
.OWNER
Created for enhanced logging implementation
.CONTRIBUTORS

#>

# Get all PowerShell scripts in the current directory and subdirectories
$scriptFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -Recurse | 
    Where-Object { $_.Name -ne "UpdateScriptsWithLogging.ps1" -and $_.Name -ne "LoggingModule.psm1" }

Write-Host "Found $($scriptFiles.Count) PowerShell scripts to update."

# Function to add logging module import to script
function Add-LoggingImport {
    param (
        [string]$Content
    )
    
    # Check if import already exists
    if ($Content -match "Import-Module.*LoggingModule\.psm1") {
        return $Content
    }
    
    # Find the insertion point after ErrorActionPreference but before the first function
    $errorActionIndex = $Content -match "\`$ErrorActionPreference\s*=\s*"
    $firstFunctionIndex = $Content -match "function\s+\w+"
    
    if ($errorActionIndex) {
        # Insert after $ErrorActionPreference
        $insertPosition = $Content.IndexOf("`$ErrorActionPreference") + $Matches[0].Length
        $nextNL = $insertPosition
        while ($nextNL -lt $Content.Length -and $Content[$nextNL] -ne "`n") {
            $nextNL++
        }
        if ($nextNL -lt $Content.Length) {
            $nextNL++
        }
        
        $importBlock = @"

# Import logging module
`$loggingModulePath = "`$PSScriptRoot\LoggingModule.psm1"
if (Test-Path `$loggingModulePath) {
    Import-Module `$loggingModulePath -Force
} else {
    Write-Error "Logging module not found at `$loggingModulePath"
    Exit 1
}

"@
        
        return $Content.Substring(0, $nextNL) + $importBlock + $Content.Substring($nextNL)
    }
    
    # If no ErrorActionPreference, insert after the comment block at the top
    $commentEndIndex = $Content -match "^#>"
    if ($commentEndIndex) {
        $insertPosition = $Content.IndexOf("#>") + 2
        $nextNL = $insertPosition
        while ($nextNL -lt $Content.Length -and $Content[$nextNL] -ne "`n") {
            $nextNL++
        }
        if ($nextNL -lt $Content.Length) {
            $nextNL++
        }
        
        $importBlock = @"

`$ErrorActionPreference = "SilentlyContinue"

# Import logging module
`$loggingModulePath = "`$PSScriptRoot\LoggingModule.psm1"
if (Test-Path `$loggingModulePath) {
    Import-Module `$loggingModulePath -Force
} else {
    Write-Error "Logging module not found at `$loggingModulePath"
    Exit 1
}

"@
        
        return $Content.Substring(0, $nextNL) + $importBlock + $Content.Substring($nextNL)
    }
    
    # If no comment block, insert at the beginning
    return @"
# Import logging module
`$loggingModulePath = "`$PSScriptRoot\LoggingModule.psm1"
if (Test-Path `$loggingModulePath) {
    Import-Module `$loggingModulePath -Force
} else {
    Write-Error "Logging module not found at `$loggingModulePath"
    Exit 1
}

"@ + $Content
}

# Function to replace basic log function with enhanced logging
function Replace-LogFunctionUsage {
    param (
        [string]$Content
    )
    
    # Remove the log function definition if it exists
    $Content = $Content -replace "(?ms)# set log function\s+function log\(\)\s*\{\s*\[CmdletBinding\(\)\]\s*Param\s*\(\s*\[Parameter\(Mandatory=\`$true\)\]\s*\[string\]\$message\s*\)\s*\$ts = Get-Date -Format [^}]+\s*\}", ""
    
    # Replace basic logging calls with enhanced logging
    $Content = $Content -replace "log\s+(?:\""|')(.+?)(?:\""|')", 'Write-Log -Message "$1" -Level INFO'
    
    # Replace Start-Transcript with Initialize-Logging
    if ($Content -match "Start-Transcript\s+-Path\s+(?:\""|')(.+?)(?:\""|')\s+-Verbose") {
        $logPath = $Matches[1] -replace '\$logPath\\(\$logName|\$?\w+\.log)', 'C:\Temp\Logs'
        $logName = $null
        if ($Content -match "\$logName\s*=\s*(?:\""|')(.+?)(?:\""|')") {
            $logName = $Matches[1]
        }
        
        # Get the script name
        $scriptNameMatch = $Content -match "(?<=\.ps1)"
        $scriptName = if ($scriptNameMatch) { $Matches[0] } else { "script" }
        
        $initLoggingBlock = @"
# Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "$logName" -Level INFO -EnableConsoleOutput `$true -EnableEventLog `$false -StartTranscript `$true
    Write-Log -Message "========== Starting $scriptName.ps1 ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: `$_"
    Exit 1
}
"@
        
        $Content = $Content -replace "Start-Transcript\s+-Path\s+(?:\""|')(.+?)(?:\""|')\s+-Verbose", $initLoggingBlock
    }
    
    # Add script completion log message
    if ($Content -match "Stop-Transcript") {
        $Content = $Content -replace "Stop-Transcript", "# Script completion`nWrite-Log -Message `"========== Script completed ==========`" -Level INFO`nStop-Transcript"
    }
    
    return $Content
}

# Process each script file
foreach ($file in $scriptFiles) {
    Write-Host "Processing $($file.Name)..."
    
    try {
        # Read the file content
        $content = Get-Content -Path $file.FullName -Raw
        
        # Add logging module import
        $content = Add-LoggingImport -Content $content
        
        # Replace basic logging with enhanced logging
        $content = Replace-LogFunctionUsage -Content $content
        
        # Backup the original file
        Copy-Item -Path $file.FullName -Destination "$($file.FullName).bak" -Force
        
        # Save the updated content
        Set-Content -Path $file.FullName -Value $content -Force
        
        Write-Host "  Updated $($file.Name) successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "  Error updating $($file.Name): $_" -ForegroundColor Red
    }
}

Write-Host "Script update complete. All scripts now use the enhanced logging module."
Write-Host "Original files have been backed up with .bak extension." 