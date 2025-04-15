<# VALIDATESCRIPTS.PS1
Synopsis
Validates PowerShell scripts in the project for Windows 10/11 compatibility issues.
DESCRIPTION
This script analyzes all PowerShell scripts in the project for potential compatibility issues with Windows 10 and Windows 11.
It checks for cmdlet compatibility, module requirements, registry paths, administrative requirements, and other common issues.
USE
.\ValidateScripts.ps1
.OWNER
Created for script validation
.CONTRIBUTORS

#>

#Requires -Version 5.1

# Import logging module
$loggingModulePath = "$PSScriptRoot\LoggingModule.psm1"
if (Test-Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
} else {
    Write-Error "Logging module not found at $loggingModulePath"
    Exit 1
}

# Initialize logging
try {
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "ScriptValidation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" -Level INFO -EnableConsoleOutput $true -EnableEventLog $false -StartTranscript $true
    Write-Log -Message "========== Starting Script Validation ==========" -Level INFO
} catch {
    Write-Error "Failed to initialize logging: $_"
    Exit 1
}

# Global arrays to store issues
$script:CriticalIssues = @()
$script:WarningIssues = @()
$script:InfoItems = @()

# List of PowerShell cmdlets potentially not available or behaving differently in Windows 10/11
$script:PotentialProblemCmdlets = @{
    # Specific cmdlets with version requirements
    "Add-AppxPackage" = "May require different parameters in different Windows versions"
    "Get-AppxPackage" = "May return different results in different Windows versions"
    "Get-WindowsCapability" = "Behavior may vary between Windows 10 and Windows 11"
    "Get-WindowsOptionalFeature" = "Feature availability varies between Windows versions"
    "Enable-WindowsOptionalFeature" = "Feature availability varies between Windows versions"
    "Install-WindowsFeature" = "May not be available in all Windows 10 editions"
    "Add-WindowsCapability" = "May require Windows 10 version 1709 or later"
    "Get-CimInstance" = "Some CIM classes vary between Windows versions"
    "Set-ItemProperty" = "Registry paths may vary between Windows versions"
    "Get-ItemProperty" = "Registry paths may vary between Windows versions"
    "dsregcmd.exe" = "Output format may vary between Windows versions"
    "Get-ScheduledTask" = "Task availability and behavior may vary between Windows versions"
    "DISM" = "Parameter requirements may vary between Windows versions"
    "Mount-WindowsImage" = "May require specific Windows features to be installed"
}

# List of registry paths that may vary between Windows 10/11
$script:ProblematicRegistryPaths = @(
    "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
    "HKLM:\\SOFTWARE\\Microsoft\\WindowsUpdate",
    "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate",
    "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\ProfileList",
    "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Authentication"
)

# List of modules that may have compatibility issues
$script:PotentialProblemModules = @{
    "Microsoft.Graph.Intune" = "Requires PowerShell 5.1 or later and may have version-specific dependencies"
    "WindowsAutoPilotIntune" = "May have version-specific dependencies and require specific Azure AD modules"
    "Provisioning" = "May not be available in all Windows 10/11 editions"
    "Microsoft.Graph" = "Requires PowerShell 5.1 or later and may have version-specific authentication methods"
}

# Function to parse scripts and identify issues
function Find-ScriptIssues {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )
    
    $taskName = "Analyzing $([System.IO.Path]::GetFileName($ScriptPath))"
    $taskStartTime = Start-LogTask -Name $taskName
    $scriptIssues = @()
    
    try {
        Write-Log -Message "Parsing script file: $ScriptPath" -Level INFO
        
        # Get script content
        $scriptContent = Get-Content -Path $ScriptPath -Raw
        $scriptName = [System.IO.Path]::GetFileName($ScriptPath)
        
        # Check PowerShell version requirements
        if ($scriptContent -match "#Requires\s+-Version\s+(\d+\.\d+)") {
            $requiredVersion = [version]$Matches[1]
            if ($requiredVersion -gt [version]"5.1") {
                $message = "Script requires PowerShell version $requiredVersion, which may not be available on all Windows 10/11 systems"
                $script:WarningIssues += [PSCustomObject]@{
                    ScriptName = $scriptName
                    IssueType = "PowerShell Version"
                    Description = $message
                    LineNumber = (($scriptContent -split "`n") | Select-String -Pattern "#Requires\s+-Version").LineNumber
                    Severity = "Warning"
                }
                Write-Log -Message $message -Level WARNING
            }
        }
        
        # Check for problematic cmdlets
        foreach ($cmdlet in $script:PotentialProblemCmdlets.Keys) {
            $lineNumbers = @()
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "\b$cmdlet\b"
            
            if ($matches) {
                $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
                $message = "Script uses '$cmdlet', which $($script:PotentialProblemCmdlets[$cmdlet])"
                $script:WarningIssues += [PSCustomObject]@{
                    ScriptName = $scriptName
                    IssueType = "Cmdlet Compatibility"
                    Description = $message
                    LineNumber = ($lineNumbers -join ', ')
                    Severity = "Warning"
                }
                Write-Log -Message $message -Level WARNING
            }
        }
        
        # Check for registry paths that may vary
        foreach ($regPath in $script:ProblematicRegistryPaths) {
            $escapedPath = [regex]::Escape($regPath).Replace('\\', '\\')
            $matches = ($scriptContent -split "`n") | Select-String -Pattern $escapedPath
            
            if ($matches) {
                $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
                $message = "Script references registry path '$regPath', which may vary between Windows 10/11 versions"
                $script:WarningIssues += [PSCustomObject]@{
                    ScriptName = $scriptName
                    IssueType = "Registry Path"
                    Description = $message
                    LineNumber = ($lineNumbers -join ', ')
                    Severity = "Warning"
                }
                Write-Log -Message $message -Level WARNING
            }
        }
        
        # Check for problematic modules
        foreach ($module in $script:PotentialProblemModules.Keys) {
            $modulePattern = "Import-Module\s+$module|using\s+module\s+$module"
            $matches = ($scriptContent -split "`n") | Select-String -Pattern $modulePattern
            
            if ($matches) {
                $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
                $message = "Script imports module '$module', which $($script:PotentialProblemModules[$module])"
                $script:WarningIssues += [PSCustomObject]@{
                    ScriptName = $scriptName
                    IssueType = "Module Dependency"
                    Description = $message
                    LineNumber = ($lineNumbers -join ', ')
                    Severity = "Warning"
                }
                Write-Log -Message $message -Level WARNING
            }
        }
        
        # Check for administrative requirements
        if ($scriptContent -match "Administrator|RunAs|elevated|admin") {
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "Administrator|RunAs|elevated|admin"
            $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
            $message = "Script may require administrative privileges, which requires UAC elevation on Windows 10/11"
            $script:InfoItems += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = "Administrative Rights"
                Description = $message
                LineNumber = ($lineNumbers -join ', ')
                Severity = "Info"
            }
            Write-Log -Message $message -Level INFO
        }
        
        # Check for hardcoded file paths that might vary across Windows versions
        if ($scriptContent -match "C:\\Windows\\System32|C:\\Program Files|C:\\ProgramData") {
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "C:\\Windows\\System32|C:\\Program Files|C:\\ProgramData"
            $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
            $message = "Script contains hardcoded system paths that might vary across Windows versions"
            $script:WarningIssues += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = "Hardcoded Paths"
                Description = $message
                LineNumber = ($lineNumbers -join ', ')
                Severity = "Warning"
            }
            Write-Log -Message $message -Level WARNING
        }
        
        # Check for WMI queries that might behave differently
        if ($scriptContent -match "Get-WmiObject|Invoke-WmiMethod|WmiClass") {
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "Get-WmiObject|Invoke-WmiMethod|WmiClass"
            $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
            $message = "Script uses WMI cmdlets which are deprecated in newer PowerShell versions. Consider using CIM cmdlets instead."
            $script:WarningIssues += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = "Deprecated WMI Usage"
                Description = $message
                LineNumber = ($lineNumbers -join ', ')
                Severity = "Warning"
            }
            Write-Log -Message $message -Level WARNING
        }
        
        # Check for .NET Framework dependencies
        if ($scriptContent -match "\[System\.Net\.WebClient\]|\[System\.IO\.File\]|\[System\.Reflection\.Assembly\]::Load") {
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "\[System\.Net\.WebClient\]|\[System\.IO\.File\]|\[System\.Reflection\.Assembly\]::Load"
            $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
            $message = "Script uses .NET Framework classes which may have version-specific behaviors"
            $script:InfoItems += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = ".NET Dependencies"
                Description = $message
                LineNumber = ($lineNumbers -join ', ')
                Severity = "Info"
            }
            Write-Log -Message $message -Level INFO
        }
        
        # Check for potential file encoding issues
        $encoding = Get-FileEncoding -Path $ScriptPath
        if ($encoding -ne "UTF8" -and $encoding -ne "ASCII") {
            $message = "Script uses $encoding encoding, which might cause issues with special characters"
            $script:WarningIssues += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = "File Encoding"
                Description = $message
                LineNumber = "N/A"
                Severity = "Warning"
            }
            Write-Log -Message $message -Level WARNING
        }
        
        # Check for execution policy settings
        if ($scriptContent -match "Set-ExecutionPolicy|ExecutionPolicy\s+Bypass") {
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "Set-ExecutionPolicy|ExecutionPolicy\s+Bypass"
            $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
            $message = "Script modifies execution policy, which might require different permissions across Windows versions"
            $script:WarningIssues += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = "Execution Policy"
                Description = $message
                LineNumber = ($lineNumbers -join ', ')
                Severity = "Warning"
            }
            Write-Log -Message $message -Level WARNING
        }
        
        # Check for scheduled task creation/modification
        if ($scriptContent -match "Register-ScheduledTask|New-ScheduledTask|schtasks\.exe") {
            $matches = ($scriptContent -split "`n") | Select-String -Pattern "Register-ScheduledTask|New-ScheduledTask|schtasks\.exe"
            $lineNumbers = $matches | ForEach-Object { $_.LineNumber }
            $message = "Script creates or modifies scheduled tasks, which might require different syntax across Windows versions"
            $script:WarningIssues += [PSCustomObject]@{
                ScriptName = $scriptName
                IssueType = "Scheduled Tasks"
                Description = $message
                LineNumber = ($lineNumbers -join ', ')
                Severity = "Warning"
            }
            Write-Log -Message $message -Level WARNING
        }
        
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
    }
    catch {
        $message = "Error analyzing script '$ScriptPath': $_"
        $script:CriticalIssues += [PSCustomObject]@{
            ScriptName = $scriptName
            IssueType = "Analysis Error"
            Description = $message
            LineNumber = "N/A"
            Severity = "Error"
        }
        Write-Log -Message $message -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
    }
}

# Function to determine file encoding
function Get-FileEncoding {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        
        # Check for BOM
        if ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) { return "UTF32BE" }
        if ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) { return "UTF32" }
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return "UTF8" }
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { return "Unicode BE" }
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return "Unicode" }
        
        # No BOM - check content
        $isUTF8 = $true
        $isASCII = $true
        
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            # Check for valid UTF-8 continuation byte pattern
            if ($bytes[$i] -gt 127) {
                $isASCII = $false
                
                if ($bytes[$i] -ge 194 -and $bytes[$i] -le 223 -and $i+1 -lt $bytes.Length -and $bytes[$i+1] -ge 128 -and $bytes[$i+1] -le 191) {
                    $i++
                    continue
                }
                elseif ($bytes[$i] -ge 224 -and $bytes[$i] -le 239 -and $i+2 -lt $bytes.Length -and 
                        $bytes[$i+1] -ge 128 -and $bytes[$i+1] -le 191 -and 
                        $bytes[$i+2] -ge 128 -and $bytes[$i+2] -le 191) {
                    $i += 2
                    continue
                }
                elseif ($bytes[$i] -ge 240 -and $bytes[$i] -le 244 -and $i+3 -lt $bytes.Length -and 
                        $bytes[$i+1] -ge 128 -and $bytes[$i+1] -le 191 -and 
                        $bytes[$i+2] -ge 128 -and $bytes[$i+2] -le 191 -and 
                        $bytes[$i+3] -ge 128 -and $bytes[$i+3] -le 191) {
                    $i += 3
                    continue
                }
                else {
                    $isUTF8 = $false
                    break
                }
            }
        }
        
        if ($isASCII) { return "ASCII" }
        if ($isUTF8) { return "UTF8" }
        
        return "ANSI or other"
    }
    catch {
        Write-Log -Message "Error determining file encoding for '$Path': $_" -Level ERROR
        return "Unknown"
    }
}

# Function to generate a validation report
function New-ValidationReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$ReportPath = "C:\Temp\Logs\ScriptValidationReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    )
    
    $taskName = "Generating Validation Report"
    $taskStartTime = Start-LogTask -Name $taskName
    
    try {
        Write-Log -Message "Generating validation report at $ReportPath" -Level INFO
        
        # Get Windows version information
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $osVersion = $osInfo.Version
        $osBuild = $osInfo.BuildNumber
        $osName = $osInfo.Caption
        
        # Create HTML report
        $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>PowerShell Script Validation Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; }
        h1, h2, h3 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th { background-color: #0078d4; color: white; text-align: left; padding: 8px; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .critical { background-color: #ffcccc; }
        .warning { background-color: #fff4cc; }
        .info { background-color: #e6f9ff; }
        .summary { font-size: 16px; margin-bottom: 20px; }
        .details { margin-top: 10px; font-size: 14px; }
    </style>
</head>
<body>
    <h1>PowerShell Script Validation Report</h1>
    <div class="details">
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Current OS:</strong> $osName (Version: $osVersion, Build: $osBuild)</p>
        <p><strong>Validation Target:</strong> Windows 10/11 Compatibility</p>
    </div>
"@
        
        # Summary section
        $criticalCount = $script:CriticalIssues.Count
        $warningCount = $script:WarningIssues.Count
        $infoCount = $script:InfoItems.Count
        $totalIssues = $criticalCount + $warningCount + $infoCount
        
        $htmlSummary = @"
    <h2>Summary</h2>
    <div class="summary">
        <p>Total Issues: $totalIssues</p>
        <ul>
            <li>Critical Issues: $criticalCount</li>
            <li>Warnings: $warningCount</li>
            <li>Information Items: $infoCount</li>
        </ul>
    </div>
"@
        
        # Create HTML tables for issues
        $htmlCritical = ""
        if ($criticalCount -gt 0) {
            $htmlCritical = @"
    <h2>Critical Issues</h2>
    <table>
        <tr>
            <th>Script</th>
            <th>Issue Type</th>
            <th>Description</th>
            <th>Line Number(s)</th>
        </tr>
"@
            foreach ($issue in $script:CriticalIssues) {
                $htmlCritical += @"
        <tr class="critical">
            <td>$($issue.ScriptName)</td>
            <td>$($issue.IssueType)</td>
            <td>$($issue.Description)</td>
            <td>$($issue.LineNumber)</td>
        </tr>
"@
            }
            $htmlCritical += "</table>"
        }
        
        $htmlWarning = ""
        if ($warningCount -gt 0) {
            $htmlWarning = @"
    <h2>Warnings</h2>
    <table>
        <tr>
            <th>Script</th>
            <th>Issue Type</th>
            <th>Description</th>
            <th>Line Number(s)</th>
        </tr>
"@
            foreach ($issue in $script:WarningIssues) {
                $htmlWarning += @"
        <tr class="warning">
            <td>$($issue.ScriptName)</td>
            <td>$($issue.IssueType)</td>
            <td>$($issue.Description)</td>
            <td>$($issue.LineNumber)</td>
        </tr>
"@
            }
            $htmlWarning += "</table>"
        }
        
        $htmlInfo = ""
        if ($infoCount -gt 0) {
            $htmlInfo = @"
    <h2>Information Items</h2>
    <table>
        <tr>
            <th>Script</th>
            <th>Issue Type</th>
            <th>Description</th>
            <th>Line Number(s)</th>
        </tr>
"@
            foreach ($issue in $script:InfoItems) {
                $htmlInfo += @"
        <tr class="info">
            <td>$($issue.ScriptName)</td>
            <td>$($issue.IssueType)</td>
            <td>$($issue.Description)</td>
            <td>$($issue.LineNumber)</td>
        </tr>
"@
            }
            $htmlInfo += "</table>"
        }
        
        # Recommendations section
        $htmlRecommendations = @"
    <h2>Recommendations</h2>
    <ul>
        <li>Test scripts on both Windows 10 and Windows 11 target environments.</li>
        <li>Use environment variables instead of hardcoded paths where possible.</li>
        <li>Replace deprecated WMI commands with CIM equivalents.</li>
        <li>Check if required modules are available on target systems.</li>
        <li>Validate registry paths exist before attempting to access them.</li>
        <li>Implement proper error handling for OS-specific features.</li>
        <li>Consider using PowerShell 5.1 compatible syntax for maximum compatibility.</li>
    </ul>
"@
        
        $htmlFooter = @"
</body>
</html>
"@
        
        # Combine all HTML sections
        $htmlReport = $htmlHeader + $htmlSummary + $htmlCritical + $htmlWarning + $htmlInfo + $htmlRecommendations + $htmlFooter
        
        # Save report to file
        $htmlReport | Out-File -FilePath $ReportPath -Encoding utf8
        
        Write-Log -Message "Validation report saved to $ReportPath" -Level INFO
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
        
        return $ReportPath
    }
    catch {
        Write-Log -Message "Error generating validation report: $_" -Level ERROR
        Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
        throw $_
    }
}

# Main script execution starts here
$taskName = "Script Validation"
$taskStartTime = Start-LogTask -Name $taskName -Description "Validating all PowerShell scripts for Windows 10/11 compatibility"

try {
    # Get all PowerShell scripts in the current directory and subdirectories
    $scriptFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -Recurse
    Write-Log -Message "Found $($scriptFiles.Count) PowerShell scripts to validate" -Level INFO
    
    # Get Windows version for context
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Log -Message "Current OS: $($osInfo.Caption) (Version: $($osInfo.Version), Build: $($osInfo.BuildNumber))" -Level INFO
    
    # Log system information for context
    Write-SystemInfo
    
    # Process each script
    foreach ($file in $scriptFiles) {
        Find-ScriptIssues -ScriptPath $file.FullName
    }
    
    # Generate validation report
    $reportFolder = "C:\Temp\Logs"
    if (-not (Test-Path $reportFolder)) {
        New-Item -Path $reportFolder -ItemType Directory -Force | Out-Null
    }
    $reportPath = New-ValidationReport -ReportPath "$reportFolder\ScriptValidationReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    
    # Summary of findings
    $totalIssues = $script:CriticalIssues.Count + $script:WarningIssues.Count + $script:InfoItems.Count
    Write-Log -Message "Validation complete. Found $totalIssues issues ($($script:CriticalIssues.Count) critical, $($script:WarningIssues.Count) warnings, $($script:InfoItems.Count) info items)" -Level INFO
    Write-Log -Message "Full report available at: $reportPath" -Level INFO
    
    Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $true
    
    # Launch the report in the default browser
    if ($totalIssues -gt 0) {
        Write-Log -Message "Opening report in default browser..." -Level INFO
        Invoke-Item $reportPath
    }
}
catch {
    Write-Log -Message "Error during script validation: $_" -Level ERROR
    Complete-LogTask -Name $taskName -StartTime $taskStartTime -Success $false
}

# Script completion
Write-Log -Message "========== Script validation completed ==========" -Level INFO
Stop-Transcript 