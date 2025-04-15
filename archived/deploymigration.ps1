# Import logging module
$loggingModulePath = "$PSScriptRoot\LoggingModule.psm1"
if (Test-Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
} else {
    Write-Error "Logging module not found at $loggingModulePath"
    Exit 1
}
<#
.SYNOPSIS
    Workspace ONE UEM Deployment Script
.DESCRIPTION
    Extracts Payload.zip, runs MasterScript.ps1, and logs output.
#>

# Configurable variables
$TempPath       = "$env:ProgramData\UEMDeploy"
$ZipFile        = "$PSScriptRoot\WS1MigrationTool.zip"
$ExtractedPath  = "$TempPath\WS1MigrationTool"
$LogFolder      = "$TempPath\Logs"
$LogFile        = "$LogFolder\Deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$MasterScript   = "startMigrate.ps1"  # Change this if your script has a different name
$RunCleanup     = $true               # Set to $false if you want to preserve extracted files

# Ensure logging directory exists
New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null

Function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$timestamp : $Message"
    Write-Host $Message
}

Function Extract-ZipFile {
    param (
        [string]$zipFile,
        [string]$destination
    )
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $destination)
        Write-Write-Log -Message "Successfully extracted $zipFile to $destination" -Level INFO
        return $true
    } catch {
        Write-Write-Log -Message "ERROR: Failed to extract ZIP: $_" -Level INFO
        return $false
    }
}

Function Run-MasterScript {
    param (
        [string]$scriptPath
    )
    try {
        if (Test-Path $scriptPath) {
            Write-Write-Log -Message "Running master script: $scriptPath" -Level INFO
            powershell.exe -ExecutionPolicy Bypass -File $scriptPath *>> $LogFile
            Write-Write-Log -Message "Master script execution completed." -Level INFO
            return $true
        } else {
            Write-Write-Log -Message "ERROR: Master script not found at: $scriptPath" -Level INFO
            return $false
        }
    } catch {
        Write-Write-Log -Message "ERROR: Exception while running master script: $_" -Level INFO
        return $false
    }
}

# Main Execution
Write-Write-Log -Message "===== Workspace ONE UEM Deploy Script Started =====" -Level INFO
Write-Write-Log -Message "Zip file: $ZipFile" -Level INFO
Write-Write-Log -Message "Temp extract path: $ExtractedPath" -Level INFO

# Create extraction folder
try {
    New-Item -ItemType Directory -Path $ExtractedPath -Force | Out-Null
} catch {
    Write-Write-Log -Message "ERROR: Failed to create temp folder: $_" -Level INFO
    exit 1
}

# Extract zip
if (-not (Extract-ZipFile -zipFile $ZipFile -destination $ExtractedPath)) {
    Write-Write-Log -Message "ERROR: Extraction failed. Exiting." -Level INFO
    exit 1
}

# Execute the master script
$scriptToRun = Join-Path $ExtractedPath $MasterScript
if (-not (Run-MasterScript -scriptPath $scriptToRun)) {
    Write-Write-Log -Message "ERROR: Master script execution failed." -Level INFO
    exit 1
}

# Optional Cleanup
if ($RunCleanup -and (Test-Path $ExtractedPath)) {
    try {
        Remove-Item -Path $ExtractedPath -Recurse -Force
        Write-Write-Log -Message "Cleanup successful: Removed extracted files." -Level INFO
    } catch {
        Write-Write-Log -Message "WARNING: Cleanup failed: $_" -Level INFO
    }
}

Write-Write-Log -Message "===== Deployment Completed Successfully =====" -Level INFO
exit 0
