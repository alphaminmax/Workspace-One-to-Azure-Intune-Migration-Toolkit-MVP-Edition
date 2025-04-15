<# INVOKE-WORKSPACEONESETUP.PS1
.SYNOPSIS
    Integrates script testing with Workspace One enrollment for Windows 10/11.
.DESCRIPTION
    Automates the testing of PowerShell scripts and provides a GUI wizard for Workspace One
    enrollment with Intune integration when automated methods fail.
.NOTES
    Version: 1.0
    Author: Modern Windows Management
    RequiredVersion: PowerShell 5.1 or higher
.EXAMPLE
    .\Invoke-WorkspaceOneSetup.ps1
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$TestScriptsOnly,
    
    [Parameter()]
    [switch]$EnrollmentOnly,
    
    [Parameter()]
    [switch]$NoGUI
)

# Import required modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "WorkspaceOneWizard.psm1"
if (Test-Path -Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Error "Workspace One Wizard module not found at path: $modulePath"
    Exit 1
}

# Initialize variables
$logPath = Join-Path -Path "C:\Temp\Logs" -ChildPath "WS1_Setup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$testScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "TestScripts.ps1"

function Initialize-Environment {
    [CmdletBinding()]
    param()
    
    try {
        # Create log directory
        if (-not (Test-Path -Path $logPath -PathType Container)) {
            New-Item -Path $logPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created log directory: $logPath"
        }
        
        # Start transcript
        $transcriptPath = Join-Path -Path $logPath -ChildPath "Setup_Transcript.log"
        Start-Transcript -Path $transcriptPath -Force
        
        Write-Host "=== Workspace One Setup and Script Testing ===" -ForegroundColor Cyan
        Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "Log path: $logPath" -ForegroundColor Cyan
        Write-Host "=============================================" -ForegroundColor Cyan
        
        # Check operating system
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $windowsVersion = switch -Regex ($osInfo.BuildNumber) {
            '^10\d{3}$' { "Windows 10" }
            '^22[0-9]{3}$' { "Windows 11" }
            default { "Windows (Build $($osInfo.BuildNumber))" }
        }
        
        Write-Host "Operating System: $windowsVersion $(($osInfo.Caption -replace 'Microsoft ', ''))" -ForegroundColor Yellow
        
        # Check PowerShell version
        $psVersion = $PSVersionTable.PSVersion
        Write-Host "PowerShell Version: $($psVersion.Major).$($psVersion.Minor).$($psVersion.Build)" -ForegroundColor Yellow
        
        # Check admin rights
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
        $isAdmin = $principal.IsInRole($adminRole)
        
        Write-Host "Running as Administrator: $isAdmin" -ForegroundColor Yellow
        
        if (-not $isAdmin) {
            Write-Warning "Some operations may require administrative privileges."
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to initialize environment: $_"
        if ($transcriptStarted) {
            Stop-Transcript
        }
        return $false
    }
}

function Test-ScriptsEnvironment {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`n=== Testing Scripts Environment ===" -ForegroundColor Cyan
        
        # Check if test scripts exist
        if (-not (Test-Path -Path $testScriptPath)) {
            Write-Error "Test script not found at path: $testScriptPath"
            return $false
        }
        
        # Execute script testing
        Write-Host "Running script tests..." -ForegroundColor Yellow
        $testReportPath = & $testScriptPath
        
        if ($testReportPath -and (Test-Path -Path $testReportPath)) {
            Write-Host "Script testing completed successfully." -ForegroundColor Green
            Write-Host "Test report available at: $testReportPath" -ForegroundColor Cyan
            return $true
        } else {
            Write-Error "Script testing failed or did not produce a report."
            return $false
        }
    }
    catch {
        Write-Error "Error during script testing: $_"
        return $false
    }
}

function Test-EnrollmentReadiness {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`n=== Testing Enrollment Readiness ===" -ForegroundColor Cyan
        
        # Check prerequisites for enrollment
        $prereqs = Test-EnrollmentPrerequisites
        
        if ($prereqs.Success) {
            Write-Host "Device is ready for Workspace One enrollment." -ForegroundColor Green
            
            foreach ($key in $prereqs.PSObject.Properties.Name) {
                if ($key -notin @('Success', 'Issues')) {
                    Write-Host "$key`: $($prereqs.$key)" -ForegroundColor Yellow
                }
            }
            
            return $true
        } else {
            Write-Warning "Device is not ready for Workspace One enrollment."
            Write-Host "Issues found:" -ForegroundColor Yellow
            
            foreach ($issue in $prereqs.Issues) {
                Write-Host "- $issue" -ForegroundColor Red
            }
            
            return $false
        }
    }
    catch {
        Write-Error "Error testing enrollment readiness: $_"
        return $false
    }
}

function Start-WorkspaceOneEnrollment {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$UseGUI
    )
    
    try {
        Write-Host "`n=== Starting Workspace One Enrollment ===" -ForegroundColor Cyan
        
        if ($UseGUI) {
            Write-Host "Launching Workspace One enrollment wizard..." -ForegroundColor Yellow
            Show-EnrollmentWizard
        } else {
            Write-Host "Running silent enrollment process..." -ForegroundColor Yellow
            
            # Prompt for credentials if running in console mode
            $email = Read-Host "Enter your company email"
            $domain = Read-Host "Enter your domain"
            $server = Read-Host "Enter the enrollment server URL"
            
            # Start enrollment process
            $result = Start-EnrollmentProcess -Username $email -Domain $domain -Server $server
            
            if ($result) {
                Write-Host "Enrollment completed successfully." -ForegroundColor Green
                return $true
            } else {
                Write-Error "Enrollment failed."
                return $false
            }
        }
    }
    catch {
        Write-Error "Error during enrollment: $_"
        return $false
    }
}

# Main execution
try {
    # Initialize environment
    if (-not (Initialize-Environment)) {
        Exit 1
    }
    
    # Test scripts if not skipped
    if (-not $EnrollmentOnly) {
        $scriptsResult = Test-ScriptsEnvironment
        if (-not $scriptsResult) {
            Write-Warning "Script testing completed with issues."
        }
    }
    
    # Perform enrollment if not skipped
    if (-not $TestScriptsOnly) {
        $enrollmentReady = Test-EnrollmentReadiness
        
        if ($enrollmentReady) {
            if ($NoGUI) {
                Start-WorkspaceOneEnrollment
            } else {
                Start-WorkspaceOneEnrollment -UseGUI
            }
        } else {
            Write-Warning "Enrollment prerequisites not met. Please resolve issues before enrolling."
        }
    }
    
    Write-Host "`n=== Setup Process Completed ===" -ForegroundColor Cyan
    Write-Host "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
}
catch {
    Write-Error "Unhandled error in setup process: $_"
    Exit 1
}
finally {
    # Ensure transcript is stopped
    try {
        Stop-Transcript
    } catch {
        # Transcript might not be running
    }
} 