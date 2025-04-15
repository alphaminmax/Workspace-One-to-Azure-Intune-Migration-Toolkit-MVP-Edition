# Initialize global variables
$script:TestResults = @()

# Function to test a script for syntax errors
function Test-ScriptSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    try {
        Write-Output "Testing syntax for script: $ScriptPath"
        
        # Create a temporary PowerShell instance to test the script
        $errors = $null
        $scriptContent = Get-Content -Path $ScriptPath -Raw
        $parsed = [System.Management.Automation.PSParser]::Tokenize($scriptContent, [ref]$errors)
        
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        
        if ($errors.Count -gt 0) {
            $errorDetails = ($errors | ForEach-Object { "$($_.Token.Line):$($_.Message)" }) -join "; "
            Write-Output "Syntax errors found in $scriptName`: $errorDetails"
            
            # Add to test results
            $script:TestResults += [PSCustomObject]@{
                ScriptName  = $scriptName
                ScriptPath  = $ScriptPath
                TestType    = "Syntax"
                Result      = "Failed"
                ErrorDetail = $errorDetails
                Timestamp   = Get-Date
            }
            
            return $false
        } else {
            Write-Output "No syntax errors found in $scriptName"
            
            # Add to test results
            $script:TestResults += [PSCustomObject]@{
                ScriptName  = $scriptName
                ScriptPath  = $ScriptPath
                TestType    = "Syntax"
                Result      = "Passed"
                ErrorDetail = $null
                Timestamp   = Get-Date
            }
            
            return $true
        }
    } catch {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-Output "Error testing syntax for $scriptName`: $_"
        
        # Add to test results
        $script:TestResults += [PSCustomObject]@{
            ScriptName  = $scriptName
            ScriptPath  = $ScriptPath
            TestType    = "Syntax"
            Result      = "Error"
            ErrorDetail = $_.Exception.Message
            Timestamp   = Get-Date
        }
        
        return $false
    }
}

# Function to test script initialization
function Test-ScriptInitialization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    try {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-Output "Testing initialization for script: $scriptName"
        
        # Create temporary environment for testing
        $tempFolder = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
        New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
        
        try {
            # Copy the script to the temp folder
            $tempScriptPath = [System.IO.Path]::Combine($tempFolder, $scriptName)
            Copy-Item -Path $ScriptPath -Destination $tempScriptPath -Force
            
            # Create a new PowerShell process to test initialization
            $powershellPath = (Get-Command powershell.exe).Source
            $errorFilePath = "$tempFolder\stderr.txt"
            $command = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"try { . '$tempScriptPath' -WhatIf; exit 0 } catch { `$_.Exception.Message | Out-File -FilePath '$errorFilePath'; exit 1 }`""
            
            $process = Start-Process -FilePath $powershellPath -ArgumentList $command -NoNewWindow -PassThru
            $hasExited = $process.WaitForExit(30000) # Wait up to 30 seconds
            
            if (-not $hasExited) {
                $process.Kill()
                Write-Output "Script initialization test timed out for $scriptName"
                
                # Add to test results
                $script:TestResults += [PSCustomObject]@{
                    ScriptName  = $scriptName
                    ScriptPath  = $ScriptPath
                    TestType    = "Initialization"
                    Result      = "Failed"
                    ErrorDetail = "Script initialization test timed out after 30 seconds"
                    Timestamp   = Get-Date
                }
                
                return $false
            }
            
            $exitCode = $process.ExitCode
            $errorOutput = ""
            if (Test-Path -Path $errorFilePath) { 
                $errorOutput = [System.IO.File]::ReadAllText($errorFilePath)
            }
            
            if ($exitCode -eq 0 -and [string]::IsNullOrEmpty($errorOutput)) {
                Write-Output "Script $scriptName initialized successfully"
                
                # Add to test results
                $script:TestResults += [PSCustomObject]@{
                    ScriptName  = $scriptName
                    ScriptPath  = $ScriptPath
                    TestType    = "Initialization"
                    Result      = "Passed"
                    ErrorDetail = $null
                    Timestamp   = Get-Date
                }
                
                return $true
            } else {
                Write-Output "Script $scriptName failed to initialize: $errorOutput"
                
                # Add to test results
                $script:TestResults += [PSCustomObject]@{
                    ScriptName  = $scriptName
                    ScriptPath  = $ScriptPath
                    TestType    = "Initialization"
                    Result      = "Failed"
                    ErrorDetail = $errorOutput
                    Timestamp   = Get-Date
                }
                
                return $false
            }
        } finally {
            # Clean up
            if (Test-Path -Path $tempFolder) {
                Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        $scriptName = Split-Path -Path $ScriptPath -Leaf
        Write-Output "Error testing initialization for $scriptName`: $_"
        
        # Add to test results
        $script:TestResults += [PSCustomObject]@{
            ScriptName  = $scriptName
            ScriptPath  = $ScriptPath
            TestType    = "Initialization"
            Result      = "Error"
            ErrorDetail = $_.Exception.Message
            Timestamp   = Get-Date
        }
        
        return $false
    }
}

# Test the functions with a sample script
$scriptPath = ".\ValidateScripts.ps1"
Write-Output "===== Testing Syntax ====="
Test-ScriptSyntax -ScriptPath $scriptPath

Write-Output "`n===== Testing Initialization ====="
Test-ScriptInitialization -ScriptPath $scriptPath

Write-Output "`n===== Test Results ====="
$script:TestResults | Format-Table ScriptName, TestType, Result 