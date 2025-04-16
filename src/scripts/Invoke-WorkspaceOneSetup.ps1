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
    [switch]$NoGUI,

    [Parameter(Mandatory = $false)]
    [switch]$UseEnvFile,
    
    [Parameter(Mandatory = $false)]
    [string]$EnvFilePath = "./.env",
    
    [Parameter(Mandatory = $false)]
    [switch]$UseKeyVault,
    
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$StandardAdminAccount,
    
    [Parameter(Mandatory = $false)]
    [switch]$Silent,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoReboot,
    
    [Parameter(Mandatory = $false)]
    [string]$SettingsPath = "./config/settings.json"
)

# Define script paths at the beginning of the script
$scriptRoot = $PSScriptRoot
$moduleRoot = Join-Path -Path $scriptRoot -ChildPath "..\modules"
$settingsUpdateScript = Join-Path -Path $scriptRoot -ChildPath "Update-SettingsFromEnv.ps1"

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
        # Create log directory if needed
        if (-not (Test-Path -Path $logPath)) {
            New-Item -Path $logPath -ItemType Directory -Force | Out-Null
        }
        
        # Initialize logging
        Import-Module -Name "$PSScriptRoot\..\modules\LoggingModule.psm1" -Force
        Initialize-Logging -LogPath $logPath -LogFileName "WS1Setup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        
        Write-LogMessage -Message "Workspace One Setup starting..." -Level INFO
        Write-LogMessage -Message "Parameters: Mode=$Mode, EnrollmentServer=$EnrollmentServer, OrgName=$OrgName, SkipScriptTests=$SkipScriptTests" -Level INFO
        
        # Determine working directory
        $workingDirectory = $PSScriptRoot
        Write-LogMessage -Message "Working directory: $workingDirectory" -Level INFO
        
        return $true
    } catch {
        Write-Error "Failed to initialize environment: ${_}"
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
        Write-Error "Error during script testing: ${_}"
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
        Write-Error "Error testing enrollment readiness: ${_}"
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
        Write-Error "Error during enrollment: ${_}"
        return $false
    }
}

# Function to validate settings
function Test-Settings {
    param (
        [string]$SettingsPath
    )
    
    try {
        $settings = Get-Content -Path $SettingsPath -Raw | ConvertFrom-Json
        
        # Validate required settings
        $missingSettings = @()
        
        # Tenant settings
        if ([string]::IsNullOrEmpty($settings.targetTenant.clientID) -or $settings.targetTenant.clientID -match "YOUR_") {
            $missingSettings += "Target Tenant Client ID"
        }
        
        if ([string]::IsNullOrEmpty($settings.targetTenant.clientSecret) -or $settings.targetTenant.clientSecret -match "YOUR_") {
            $missingSettings += "Target Tenant Client Secret"
        }
        
        # Workspace ONE settings
        if ([string]::IsNullOrEmpty($settings.ws1host) -or $settings.ws1host -match "YOUR_") {
            $missingSettings += "Workspace ONE Host"
        }
        
        if ([string]::IsNullOrEmpty($settings.ws1username) -or $settings.ws1username -match "YOUR_") {
            $missingSettings += "Workspace ONE Username"
        }
        
        if ([string]::IsNullOrEmpty($settings.ws1password) -or $settings.ws1password -match "YOUR_") {
            $missingSettings += "Workspace ONE Password"
        }
        
        if ([string]::IsNullOrEmpty($settings.ws1apikey) -or $settings.ws1apikey -match "YOUR_") {
            $missingSettings += "Workspace ONE API Key"
        }
        
        # If missing settings, output error and return false
        if ($missingSettings.Count -gt 0) {
            Write-Error "The following settings are missing or using placeholder values:"
            foreach ($setting in $missingSettings) {
                Write-Error "  - $setting"
            }
            
            Write-Error "Please update your settings.json file or use environment variables/Key Vault to provide these values."
            return $false
        }
        
        # All settings validated successfully
        return $true
    }
    catch {
        Write-Error "Error validating settings: $_"
        return $false
    }
}

# Main execution
try {
    # Initialize environment
    if (-not (Initialize-Environment)) {
        Exit 1
    }
    
    # Early in the script, before other operations
    # If using .env file or Key Vault, update settings
    if ($UseEnvFile -or $UseKeyVault) {
        Write-Host "Updating settings from environment variables..." -ForegroundColor Cyan
        
        # Build parameters for settings update
        $updateParams = @{
            SettingsPath = $SettingsPath
        }
        
        if ($UseEnvFile) {
            $updateParams.EnvFilePath = $EnvFilePath
        }
        
        if ($UseKeyVault) {
            $updateParams.UseKeyVault = $true
            
            if (-not [string]::IsNullOrEmpty($KeyVaultName)) {
                $updateParams.KeyVaultName = $KeyVaultName
            }
        }
        
        # Run the settings update script
        try {
            & $settingsUpdateScript @updateParams
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to update settings from environment variables. Exit code: $LASTEXITCODE"
                exit $LASTEXITCODE
            }
        }
        catch {
            Write-Error "Error running settings update script: $_"
            exit 1
        }
    }

    # Validate settings before proceeding
    $settingsValid = Test-Settings -SettingsPath $SettingsPath
    if (-not $settingsValid) {
        Write-Error "Settings validation failed. Please update your settings and try again."
        exit 1
    }

    Write-Host "Settings validated successfully." -ForegroundColor Green

    # Initialize secure credential provider if using standard admin account
    if (-not [string]::IsNullOrEmpty($StandardAdminAccount)) {
        $secureEnvInitScript = Join-Path -Path $scriptRoot -ChildPath "Initialize-SecureEnvironment.ps1"
        
        # Build parameters for secure environment initialization
        $secureEnvParams = @{
            StandardAdminAccount = $StandardAdminAccount
            AllowInteractive     = (-not $Silent)
        }
        
        if ($UseKeyVault -and -not [string]::IsNullOrEmpty($KeyVaultName)) {
            $secureEnvParams.KeyVaultName = $KeyVaultName
        }
        else {
            $secureEnvParams.SkipKeyVault = $true
        }
        
        if ($UseEnvFile) {
            $secureEnvParams.EnvFilePath = $EnvFilePath
        }
        
        # Run the secure environment initialization script
        try {
            Write-Host "Initializing secure environment..." -ForegroundColor Cyan
            & $secureEnvInitScript @secureEnvParams
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to initialize secure environment. Exit code: $LASTEXITCODE"
                exit $LASTEXITCODE
            }
        }
        catch {
            Write-Error "Error initializing secure environment: $_"
            exit 1
        }
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
    Write-Error "Error during setup process: $_"
    return $false
} 