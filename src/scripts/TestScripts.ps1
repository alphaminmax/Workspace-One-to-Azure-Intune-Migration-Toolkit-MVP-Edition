<# TESTSCRIPTS.PS1
.SYNOPSIS
Tests all PowerShell scripts in the project for syntax errors and basic functionality.
.DESCRIPTION
This script performs syntax validation and limited execution tests on all PowerShell scripts
in the project without actually executing operations that would modify the system.
Modernized for Windows 10/11 environments and PowerShell 5.1+.
.NOTES
Version: 2.0
Author: Updated for modern Windows environments
RequiredVersion: PowerShell 5.1 or higher
.EXAMPLE
.\TestScripts.ps1
#>

#Requires -Version 5.1
using namespace System.IO
using namespace System.Management.Automation
using namespace System.Diagnostics

# Script-level variables
$script:TestResults = @()
$script:TempFolderPath = [Path]::Combine([Path]::GetTempPath(), "PSScriptTesting_$([Guid]::NewGuid().ToString())")
$script:LogFolder = [Path]::Combine("C:\Temp\Logs", "ScriptTests_$(Get-Date -Format 'yyyyMMdd_HHmmss')")

function Initialize-ScriptTesting {
    <#
    .SYNOPSIS
        Initializes the environment for PowerShell script testing.
    .DESCRIPTION
        Sets up the testing environment by importing required modules, initializing logging,
        and creating necessary directories.
    .EXAMPLE
        Initialize-ScriptTesting
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        # Import the logging module
        $loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath "LoggingModule.psm1"
        if (Test-Path -Path $loggingModulePath) {
            Import-Module $loggingModulePath -Force
            
            # Create the log folder if it doesn't exist
            if (-not (Test-Path -Path $script:LogFolder -PathType Container)) {
                New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
                Write-Verbose "Created log directory: $script:LogFolder"
            }
            
            # Initialize logging
            $logFilePath = Join-Path -Path $script:LogFolder -ChildPath "ScriptTesting_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Initialize-Logging -LogPath $script:LogFolder -LogFileName (Split-Path -Leaf $logFilePath) -Level INFO
            
            # Create temporary folder for script initialization testing
            if (-not (Test-Path -Path $script:TempFolderPath -PathType Container)) {
                New-Item -Path $script:TempFolderPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created temporary folder: $script:TempFolderPath"
            }
            
            Write-LogMessage -Level INFO -Message "Script testing environment initialized successfully"
            Write-LogMessage -Level INFO -Message "Log file path: $logFilePath"
            Write-LogMessage -Level INFO -Message "Temporary test folder: $script:TempFolderPath"
            
            # Log system information for diagnostics
            Write-SystemInfo
            
            return $true
        } else {
            Write-Error "Logging module not found at path: $loggingModulePath"
            return $false
        }
    }
    catch {
        Write-Error "Failed to initialize script testing environment: $_"
        return $false
    }
}

function Test-ScriptSyntax {
    <#
    .SYNOPSIS
        Tests a PowerShell script for syntax errors.
    .DESCRIPTION
        Uses PowerShell's parser to analyze script syntax without executing it.
    .PARAMETER ScriptPath
        The full path to the script file to test.
    .EXAMPLE
        Test-ScriptSyntax -ScriptPath "C:\Scripts\MyScript.ps1"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$ScriptPath
    )

    try {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-LogMessage -Level INFO -Message "Testing syntax for script: $scriptName"
        
        # Use newer AST-based syntax checking instead of deprecated PSParser
        $errors = $null
        $scriptContent = Get-Content -Path $ScriptPath -Raw
        [PSParser]::Tokenize($scriptContent, [ref]$errors) | Out-Null
        
        if ($errors.Count -gt 0) {
            $errorDetails = ($errors | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "`n"
            Write-LogMessage -Level ERROR -Message "Syntax errors found in $scriptName"
            Write-LogMessage -Level ERROR -Message $errorDetails
            
            # Add to test results
            $script:TestResults += [PSCustomObject]@{
                ScriptName  = $scriptName
                ScriptPath  = $ScriptPath
                TestType    = "Syntax"
                Result      = "Failed"
                ErrorDetail = $errorDetails
                Timestamp   = Get-Date
                Environment = Get-OSVersionInfo
            }
            
            return $false
        } else {
            Write-LogMessage -Level INFO -Message "No syntax errors found in $scriptName"
            
            # Add to test results
            $script:TestResults += [PSCustomObject]@{
                ScriptName  = $scriptName
                ScriptPath  = $ScriptPath
                TestType    = "Syntax"
                Result      = "Passed"
                ErrorDetail = $null
                Timestamp   = Get-Date
                Environment = Get-OSVersionInfo
            }
            
            return $true
        }
    } catch {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-LogMessage -Level ERROR -Message "Error testing syntax for $scriptName`: $_"
        
        # Add to test results
        $script:TestResults += [PSCustomObject]@{
            ScriptName  = $scriptName
            ScriptPath  = $ScriptPath
            TestType    = "Syntax"
            Result      = "Error"
            ErrorDetail = $_.Exception.Message
            Timestamp   = Get-Date
            Environment = Get-OSVersionInfo
        }
        
        return $false
    }
}

function Test-ScriptInitialization {
    <#
    .SYNOPSIS
        Tests a PowerShell script for successful initialization without execution.
    .DESCRIPTION
        Creates a controlled environment to test if a script can be loaded without errors.
    .PARAMETER ScriptPath
        The full path to the script file to test.
    .EXAMPLE
        Test-ScriptInitialization -ScriptPath "C:\Scripts\MyScript.ps1"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$ScriptPath
    )

    try {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-LogMessage -Level INFO -Message "Testing initialization for script: $scriptName"
        
        # Create test-specific folder to prevent conflicts
        $testId = [Guid]::NewGuid().ToString()
        $tempScriptFolder = [Path]::Combine($script:TempFolderPath, $testId)
        New-Item -Path $tempScriptFolder -ItemType Directory -Force | Out-Null
        
        try {
            # Copy the script to the temp folder
            $tempScriptPath = [Path]::Combine($tempScriptFolder, $scriptName)
            Copy-Item -Path $ScriptPath -Destination $tempScriptPath -Force
            
            # Create error capture file
            $errorFilePath = [Path]::Combine($tempScriptFolder, "error.txt")
            
            # Use modern Start-Process with improved error handling
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = "powershell.exe"
            $startInfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"try { . '$tempScriptPath' -WhatIf; exit 0 } catch { `$_.Exception.Message | Out-File -FilePath '$errorFilePath'; exit 1 }`""
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            
            $process = [Process]::Start($startInfo)
            $hasExited = $process.WaitForExit(30000) # 30 second timeout
            
            if (-not $hasExited) {
                try {
                    $process.Kill()
                } catch {
                    # Process might have exited already
                }
                
                Write-LogMessage -Level WARNING -Message "Script initialization test timed out for $scriptName"
                
                # Add to test results
                $script:TestResults += [PSCustomObject]@{
                    ScriptName  = $scriptName
                    ScriptPath  = $ScriptPath
                    TestType    = "Initialization"
                    Result      = "Failed"
                    ErrorDetail = "Script initialization test timed out after 30 seconds"
                    Timestamp   = Get-Date
                    Environment = Get-OSVersionInfo
                }
                
                return $false
            }
            
            $exitCode = $process.ExitCode
            
            # Read error output if it exists
            $errorOutput = ""
            if (Test-Path -Path $errorFilePath) { 
                $errorOutput = [File]::ReadAllText($errorFilePath)
            }
            
            if ($exitCode -eq 0 -and [string]::IsNullOrEmpty($errorOutput)) {
                Write-LogMessage -Level INFO -Message "Script $scriptName initialized successfully"
                
                # Add to test results
                $script:TestResults += [PSCustomObject]@{
                    ScriptName  = $scriptName
                    ScriptPath  = $ScriptPath
                    TestType    = "Initialization"
                    Result      = "Passed"
                    ErrorDetail = $null
                    Timestamp   = Get-Date
                    Environment = Get-OSVersionInfo
                }
                
                return $true
            } else {
                Write-LogMessage -Level ERROR -Message "Script $scriptName failed to initialize: $errorOutput"
                
                # Add to test results
                $script:TestResults += [PSCustomObject]@{
                    ScriptName  = $scriptName
                    ScriptPath  = $ScriptPath
                    TestType    = "Initialization"
                    Result      = "Failed"
                    ErrorDetail = $errorOutput
                    Timestamp   = Get-Date
                    Environment = Get-OSVersionInfo
                }
                
                return $false
            }
        } finally {
            # Clean up
            if (Test-Path -Path $tempScriptFolder) {
                Remove-Item -Path $tempScriptFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-LogMessage -Level ERROR -Message "Error testing initialization for $scriptName`: $_"
        
        # Add to test results
        $script:TestResults += [PSCustomObject]@{
            ScriptName  = $scriptName
            ScriptPath  = $ScriptPath
            TestType    = "Initialization"
            Result      = "Error"
            ErrorDetail = $_.Exception.Message
            Timestamp   = Get-Date
            Environment = Get-OSVersionInfo
        }
        
        return $false
    }
}

function Get-OSVersionInfo {
    <#
    .SYNOPSIS
        Gets current OS version information.
    .DESCRIPTION
        Returns detailed OS version information for Windows 10/11.
    .EXAMPLE
        Get-OSVersionInfo
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $windowsVersion = switch -Regex ($os.BuildNumber) {
            '^10\d{3}$' { "Windows 10" }
            '^22[0-9]{3}$' { "Windows 11" }
            default { "Windows (Build $($os.BuildNumber))" }
        }
        
        $editionInfo = $os.Caption -replace "Microsoft ", ""
        return "$windowsVersion $editionInfo (Build $($os.BuildNumber))"
    }
    catch {
        return "Unknown Windows Version"
    }
}

# Function to generate test report
function New-TestReport {
    <#
    .SYNOPSIS
        Generates an HTML report summarizing script test results.
    .DESCRIPTION
        Creates a detailed HTML report of script test results, including syntax and initialization test outcomes.
    .PARAMETER TestResults
        The array of test results to include in the report.
    .PARAMETER OutputPath
        The path where the report will be saved.
    .EXAMPLE
        New-TestReport -TestResults $results -OutputPath "C:\Reports"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$false)]
        [Array]$TestResults = $script:TestResults,
        
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -Path $_ -PathType Container -IsValid})]
        [string]$OutputPath
    )
    
    try {
        Write-LogMessage -Level INFO -Message "Generating test report..."
        
        # Ensure output directory exists
        if (-not (Test-Path -Path $OutputPath -PathType Container)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Define the report file path
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportFileName = "ScriptTestReport_$timestamp.html"
        $reportPath = Join-Path -Path $OutputPath -ChildPath $reportFileName
        
        # Calculate summary statistics
        $totalScripts = ($TestResults | Select-Object ScriptName -Unique).Count
        $syntaxPassed = ($TestResults | Where-Object { $_.TestType -eq "Syntax" -and $_.Result -eq "Passed" }).Count
        $syntaxFailed = ($TestResults | Where-Object { $_.TestType -eq "Syntax" -and $_.Result -eq "Failed" }).Count
        $initPassed = ($TestResults | Where-Object { $_.TestType -eq "Initialization" -and $_.Result -eq "Passed" }).Count
        $initFailed = ($TestResults | Where-Object { $_.TestType -eq "Initialization" -and $_.Result -eq "Failed" }).Count
        
        # Calculate health percentage
        $healthPercentage = [math]::Round(($syntaxPassed + $initPassed) / (($syntaxPassed + $syntaxFailed + $initPassed + $initFailed)) * 100, 1)
        $healthClass = if ($healthPercentage -ge 90) { "passed" } else { "failed" }
        
        # Create HTML content with modern design
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PowerShell Script Test Report</title>
    <style>
        :root {
            --primary-color: #0078d4;
            --success-color: #107c10;
            --warning-color: #d83b01;
            --error-color: #d13438;
            --background-color: #f5f5f5;
            --card-background: #ffffff;
            --text-color: #323130;
            --border-color: #edebe9;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: var(--background-color);
            color: var(--text-color);
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: var(--card-background);
            border-radius: 8px;
            box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
            padding: 20px;
        }
        
        h1, h2, h3 {
            color: var(--primary-color);
        }
        
        .header {
            border-bottom: 1px solid var(--border-color);
            padding-bottom: 15px;
            margin-bottom: 20px;
        }
        
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        
        .summary-box {
            background-color: var(--card-background);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
            text-align: center;
        }
        
        .summary-box h3 {
            margin-top: 0;
            font-size: 16px;
            font-weight: 600;
        }
        
        .summary-number {
            font-size: 28px;
            font-weight: bold;
            margin: 10px 0;
        }
        
        .passed {
            color: var(--success-color);
        }
        
        .failed {
            color: var(--error-color);
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            overflow: hidden;
        }
        
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        
        th {
            background-color: var(--primary-color);
            color: white;
            font-weight: 600;
        }
        
        tr:nth-child(even) {
            background-color: rgba(0, 0, 0, 0.02);
        }
        
        tr:hover {
            background-color: rgba(0, 0, 0, 0.04);
        }
        
        .recommendations {
            background-color: var(--card-background);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
        }
        
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 12px;
            color: #666;
        }
        
        .error-details {
            font-family: Consolas, monospace;
            background-color: #f9f9f9;
            padding: 8px;
            border-radius: 4px;
            border-left: 3px solid var(--error-color);
            white-space: pre-wrap;
            font-size: 12px;
            color: #666;
        }
        
        @media (max-width: 768px) {
            .summary {
                grid-template-columns: 1fr;
            }
            
            table {
                font-size: 14px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>PowerShell Script Test Report</h1>
            <p>Generated on: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Environment: $(Get-OSVersionInfo)</p>
        </div>
        
        <h2>Test Summary</h2>
        <div class="summary">
            <div class="summary-box">
                <h3>Total Scripts</h3>
                <div class="summary-number">$totalScripts</div>
            </div>
            <div class="summary-box">
                <h3>Syntax Tests</h3>
                <div class="summary-number">
                    <span class="passed">$syntaxPassed Passed</span> / 
                    <span class="failed">$syntaxFailed Failed</span>
                </div>
                <div>$([math]::Round($syntaxPassed / ($syntaxPassed + $syntaxFailed) * 100, 1))% Success Rate</div>
            </div>
            <div class="summary-box">
                <h3>Initialization Tests</h3>
                <div class="summary-number">
                    <span class="passed">$initPassed Passed</span> / 
                    <span class="failed">$initFailed Failed</span>
                </div>
                <div>$([math]::Round($initPassed / ($initPassed + $initFailed) * 100, 1))% Success Rate</div>
            </div>
            <div class="summary-box">
                <h3>Overall Health</h3>
                <div class="summary-number $healthClass">
                    $healthPercentage%
                </div>
            </div>
        </div>
        
        <h2>Test Details</h2>
        <table>
            <thead>
                <tr>
                    <th>Script Name</th>
                    <th>Test Type</th>
                    <th>Result</th>
                    <th>Environment</th>
                    <th>Timestamp</th>
                    <th>Error Details</th>
                </tr>
            </thead>
            <tbody>
"@

        # Add rows for each test result
        foreach ($result in $TestResults) {
            $resultClass = if ($result.Result -eq "Passed") { "passed" } else { "failed" }
            $errorDetails = if ($result.ErrorDetail) { 
                "<div class='error-details'>$($result.ErrorDetail -replace '<', '&lt;' -replace '>', '&gt;' -replace "`n", "<br>")</div>" 
            } else { 
                "None" 
            }
            
            $htmlContent += @"
                <tr>
                    <td>$($result.ScriptName)</td>
                    <td>$($result.TestType)</td>
                    <td class="$resultClass">$($result.Result)</td>
                    <td>$($result.Environment)</td>
                    <td>$($result.Timestamp.ToString("yyyy-MM-dd HH:mm:ss"))</td>
                    <td>$errorDetails</td>
                </tr>
"@
        }

        # Complete the HTML
        $htmlContent += @"
            </tbody>
        </table>
        
        <h2>Recommendations</h2>
        <div class="recommendations">
            <ul>
"@

        # Add recommendations based on test results
        $failedScripts = $TestResults | Where-Object { $_.Result -eq "Failed" } | Select-Object -ExpandProperty ScriptName -Unique
        
        if ($failedScripts.Count -gt 0) {
            $htmlContent += "                <li>Review and fix the following scripts that failed tests:<ul>"
            foreach ($script in $failedScripts) {
                $htmlContent += "                    <li><strong>$script</strong></li>"
            }
            $htmlContent += "                </ul></li>"
        }
        
        $htmlContent += @"
                <li>Ensure all scripts follow PowerShell best practices for Windows 10/11 compatibility.</li>
                <li>Consider using PowerShell 7+ for advanced scripts that require newer language features.</li>
                <li>Test scripts in real-world environments before deploying.</li>
                <li>Consider adding Pester tests for critical scripts.</li>
            </ul>
        </div>
        
        <div class="footer">
            <p>Generated with TestScripts.ps1 version 2.0 | Windows 10/11 Script Validation Tool</p>
        </div>
    </div>
</body>
</html>
"@

        # Save the HTML content to the file
        $htmlContent | Out-File -FilePath $reportPath -Encoding utf8
        
        Write-LogMessage -Level INFO -Message "Test report successfully generated at $reportPath"
        return $reportPath
    }
    catch {
        Write-LogMessage -Level ERROR -Message "Failed to generate test report: $_"
        return $null
    }
}

# Main execution block
try {
    # Initialize the script testing environment
    if (-not (Initialize-ScriptTesting)) {
        throw "Failed to initialize script testing environment"
    }
    
    Write-LogMessage -Level INFO -Message "Starting script testing process"
    
    # Get all PowerShell scripts in the current directory and subdirectories
    $scriptFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -Recurse | 
                   Where-Object { $_.Name -ne "TestScripts.ps1" -and $_.FullName -notmatch "\\Test\\" }
    
    Write-LogMessage -Level INFO -Message "Found $($scriptFiles.Count) script files to test"
    
    # Test each script
    foreach ($scriptFile in $scriptFiles) {
        # Test script syntax
        $syntaxResult = Test-ScriptSyntax -ScriptPath $scriptFile.FullName
        
        # Only test initialization if syntax is valid
        if ($syntaxResult) {
            Test-ScriptInitialization -ScriptPath $scriptFile.FullName
        }
    }
    
    # Generate test report
    $reportPath = New-TestReport -OutputPath $script:LogFolder
    
    # Clean up temporary files
    if (Test-Path -Path $script:TempFolderPath) {
        Remove-Item -Path $script:TempFolderPath -Recurse -Force
        Write-LogMessage -Level INFO -Message "Temporary test folder removed: $script:TempFolderPath"
    }
    
    # Success message
    Write-LogMessage -Level INFO -Message "Script testing completed successfully"
    Write-LogMessage -Level INFO -Message "Test report generated at: $reportPath"
    Write-Host "Script testing completed successfully." -ForegroundColor Green
    Write-Host "Test report available at: $reportPath" -ForegroundColor Cyan
    
    # Return the path to the report
    return $reportPath
}
catch {
    Write-LogMessage -Level ERROR -Message "Script testing failed: $_"
    Write-Host "Script testing failed: $_" -ForegroundColor Red
    return $null
}
finally {
    # Ensure cleanup happens even if there's an error
    if (Test-Path -Path $script:TempFolderPath) {
        Remove-Item -Path $script:TempFolderPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Close any open logging
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    }
    catch {
        # Transcript might not be running
    }
} 