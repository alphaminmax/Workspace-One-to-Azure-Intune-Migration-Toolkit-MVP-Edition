<# DEPLOY-WS1ENROLLMENTTOOLS.PS1
.SYNOPSIS
    Deploys Workspace One enrollment tools to endpoints.
.DESCRIPTION
    Creates deployment packages and configurations for Workspace One enrollment tools
    to be deployed via Intune, SCCM/MECM, or GPO.
.NOTES
    Version: 1.0
    Author: Modern Windows Management
    RequiredVersion: PowerShell 5.1 or higher
.EXAMPLE
    .\Deploy-WS1EnrollmentTools.ps1 -DeploymentType Intune
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Intune", "SCCM", "GPO")]
    [string]$DeploymentType,
    
    [Parameter()]
    [string]$OutputPath = "C:\Temp\WS1_Deployment",
    
    [Parameter()]
    [string]$EnrollmentServer = "https://ws1.example.com",
    
    [Parameter()]
    [string]$OrganizationName = "Example Corporation",
    
    [Parameter()]
    [switch]$EnableSilentMode
)

# Create output directory
if (!(Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Create the config file with provided parameters
$configContent = @{
    EnrollmentServer = $EnrollmentServer
    IntuneIntegrationEnabled = $true
    OrganizationName = $OrganizationName
    SilentMode = $EnableSilentMode.IsPresent
}

# Convert to JSON and save
$configContent | ConvertTo-Json | Out-File -FilePath "$OutputPath\WS1Config.json" -Force

# Copy all script files
$scriptFiles = @(
    "WorkspaceOneWizard.psm1",
    "LoggingModule.psm1",
    "TestScripts.ps1",
    "Invoke-WorkspaceOneSetup.ps1",
    "Test-WS1Environment.ps1"
)

foreach ($file in $scriptFiles) {
    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $file
    $destPath = Join-Path -Path $OutputPath -ChildPath $file
    
    if (Test-Path -Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        Write-Host "Copied $file to deployment package." -ForegroundColor Green
    } else {
        Write-Warning "Could not find $file in the current directory."
    }
}

# Generate deployment-specific files
switch ($DeploymentType) {
    "Intune" {
        # Create Intune Win32 app detection script
        $detectionScript = @"
# Intune Detection Script for Workspace One Enrollment Tools
try {
    # Check if the main module file exists
    `$modulePath = "`$env:ProgramData\WS1_EnrollmentTools\WorkspaceOneWizard.psm1"
    if (Test-Path -Path `$modulePath) {
        # Check module version
        `$moduleContent = Get-Content -Path `$modulePath -Raw
        if (`$moduleContent -match "Version: 1.0") {
            # Success - app is installed
            Write-Host "Workspace One Enrollment Tools detected."
            exit 0
        }
    }
    # Not installed or wrong version
    exit 1
} catch {
    # Error occurred
    exit 1
}
"@
        $detectionScript | Out-File -FilePath "$OutputPath\IntuneDetection.ps1" -Force
        
        # Create Intune deployment script
        $deploymentScript = @"
# Intune Deployment Script for Workspace One Enrollment Tools
try {
    # Create program directory
    `$targetDir = "`$env:ProgramData\WS1_EnrollmentTools"
    if (!(Test-Path -Path `$targetDir)) {
        New-Item -Path `$targetDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy files from package
    Copy-Item -Path "`$PSScriptRoot\*" -Destination `$targetDir -Recurse -Force
    
    # Create Start Menu shortcut
    `$shortcutPath = "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Workspace One Enrollment.lnk"
    `$shell = New-Object -ComObject WScript.Shell
    `$shortcut = `$shell.CreateShortcut(`$shortcutPath)
    `$shortcut.TargetPath = "powershell.exe"
    `$shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"`$targetDir\Invoke-WorkspaceOneSetup.ps1`""
    `$shortcut.WorkingDirectory = `$targetDir
    `$shortcut.Description = "Workspace One Enrollment Wizard"
    `$shortcut.IconLocation = "shell32.dll,43"
    `$shortcut.Save()
    
    exit 0
} catch {
    Write-Error "Failed to deploy Workspace One tools: ${_}"
    exit 1
}
"@
        $deploymentScript | Out-File -FilePath "$OutputPath\IntuneInstall.ps1" -Force
        
        # Package files
        $intunePackagePath = "$OutputPath\WS1_EnrollmentTools.intunewin"
        Write-Host "To create Intune package: Use the Microsoft Win32 Content Prep Tool to package the files." -ForegroundColor Cyan
        Write-Host "Sample command: IntuneWinAppUtil.exe -c '$OutputPath' -s 'IntuneInstall.ps1' -o '$OutputPath'" -ForegroundColor Yellow
        
        # Write instructions
        $intuneInstructions = @"
=== Intune Deployment Instructions ===

1. Create a new Win32 app in Intune with these settings:
   - Name: Workspace One Enrollment Tools
   - Description: Tools for facilitating Workspace One enrollment
   - Publisher: $OrganizationName
   - Package file: $intunePackagePath

2. Program settings:
   - Install command: powershell.exe -ExecutionPolicy Bypass -File IntuneInstall.ps1
   - Uninstall command: powershell.exe -ExecutionPolicy Bypass -Command "Remove-Item -Path '$env:ProgramData\WS1_EnrollmentTools' -Recurse -Force"
   
3. Detection rule:
   - Rule type: Custom script
   - Script file: IntuneDetection.ps1

4. Assignments:
   - Assign to the appropriate user or device groups

"@
        $intuneInstructions | Out-File -FilePath "$OutputPath\IntuneDeploymentInstructions.txt" -Force
    }
    
    "SCCM" {
        # Create SCCM deployment script
        $sccmScript = @"
# SCCM Deployment Script for Workspace One Enrollment Tools
try {
    # Create program directory
    `$targetDir = "`$env:ProgramData\WS1_EnrollmentTools"
    if (!(Test-Path -Path `$targetDir)) {
        New-Item -Path `$targetDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy files from package
    Copy-Item -Path "`$PSScriptRoot\*" -Destination `$targetDir -Recurse -Force
    
    # Create Start Menu shortcut
    `$shortcutPath = "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Workspace One Enrollment.lnk"
    `$shell = New-Object -ComObject WScript.Shell
    `$shortcut = `$shell.CreateShortcut(`$shortcutPath)
    `$shortcut.TargetPath = "powershell.exe"
    `$shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"`$targetDir\Invoke-WorkspaceOneSetup.ps1`""
    `$shortcut.WorkingDirectory = `$targetDir
    `$shortcut.Description = "Workspace One Enrollment Wizard"
    `$shortcut.IconLocation = "shell32.dll,43"
    `$shortcut.Save()
    
    # Create registry key for detection
    New-Item -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools" -Name "Version" -Value "1.0" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools" -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd") -PropertyType String -Force | Out-Null
    
    exit 0
} catch {
    Write-Error "Failed to deploy Workspace One tools: ${_}"
    exit 1
}
"@
        $sccmScript | Out-File -FilePath "$OutputPath\SCCMInstall.ps1" -Force
        
        # Create uninstall script
        $uninstallScript = @"
# Uninstall script for Workspace One Enrollment Tools
try {
    # Remove Start Menu shortcut
    `$shortcutPath = "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Workspace One Enrollment.lnk"
    if (Test-Path -Path `$shortcutPath) {
        Remove-Item -Path `$shortcutPath -Force
    }
    
    # Remove program directory
    `$targetDir = "`$env:ProgramData\WS1_EnrollmentTools"
    if (Test-Path -Path `$targetDir) {
        Remove-Item -Path `$targetDir -Recurse -Force
    }
    
    # Remove registry key
    if (Test-Path -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools") {
        Remove-Item -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools" -Recurse -Force
    }
    
    exit 0
} catch {
    Write-Error "Failed to uninstall Workspace One tools: ${_}"
    exit 1
}
"@
        $uninstallScript | Out-File -FilePath "$OutputPath\SCCMUninstall.ps1" -Force
        
        # Write instructions
        $sccmInstructions = @"
=== SCCM/MECM Deployment Instructions ===

1. Create an application in SCCM:
   - Name: Workspace One Enrollment Tools
   - Publisher: $OrganizationName
   - Software version: 1.0
   - Installation program: powershell.exe -ExecutionPolicy Bypass -File SCCMInstall.ps1
   - Uninstall program: powershell.exe -ExecutionPolicy Bypass -File SCCMUninstall.ps1
   
2. Detection method:
   - Setting type: Registry
   - Hive: HKEY_LOCAL_MACHINE
   - Key: SOFTWARE\\$OrganizationName\\WS1EnrollmentTools
   - Value: Version
   - Data type: String
   - Operator: Equals
   - Value: 1.0

3. Create a deployment:
   - Deploy to a collection of computers or users
   - Purpose: Available or Required based on your needs
   - Schedule: As needed

"@
        $sccmInstructions | Out-File -FilePath "$OutputPath\SCCMDeploymentInstructions.txt" -Force
    }
    
    "GPO" {
        # Create GPO startup script
        $gpoScript = @"
# GPO Startup/Logon Script for Workspace One Enrollment Tools
try {
    # Create program directory
    `$targetDir = "`$env:ProgramData\WS1_EnrollmentTools"
    if (!(Test-Path -Path `$targetDir)) {
        New-Item -Path `$targetDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy files from network share to local machine
    `$sourceFiles = Join-Path -Path `$PSScriptRoot -ChildPath "WS1_EnrollmentTools\*"
    Copy-Item -Path `$sourceFiles -Destination `$targetDir -Recurse -Force
    
    # Create Start Menu shortcut
    `$shortcutPath = "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Workspace One Enrollment.lnk"
    `$shell = New-Object -ComObject WScript.Shell
    `$shortcut = `$shell.CreateShortcut(`$shortcutPath)
    `$shortcut.TargetPath = "powershell.exe"
    `$shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"`$targetDir\Invoke-WorkspaceOneSetup.ps1`""
    `$shortcut.WorkingDirectory = `$targetDir
    `$shortcut.Description = "Workspace One Enrollment Wizard"
    `$shortcut.IconLocation = "shell32.dll,43"
    `$shortcut.Save()
    
    # Create registry key for detection
    New-Item -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\$OrganizationName\WS1EnrollmentTools" -Name "Version" -Value "1.0" -PropertyType String -Force | Out-Null
    
    exit 0
} catch {
    Write-Error "Failed to deploy Workspace One tools: ${_}"
    exit 1
}
"@
        $gpoScript | Out-File -FilePath "$OutputPath\GPOScript.ps1" -Force
        
        # Create a sub-folder for GPO files
        $gpoFolder = Join-Path -Path $OutputPath -ChildPath "WS1_EnrollmentTools"
        if (!(Test-Path -Path $gpoFolder)) {
            New-Item -Path $gpoFolder -ItemType Directory -Force | Out-Null
        }
        
        # Copy all files to the GPO folder
        foreach ($file in $scriptFiles) {
            $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $file
            $destPath = Join-Path -Path $gpoFolder -ChildPath $file
            
            if (Test-Path -Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
            }
        }
        
        # Also copy the config file
        Copy-Item -Path "$OutputPath\WS1Config.json" -Destination "$gpoFolder\WS1Config.json" -Force
        
        # Write instructions
        $gpoInstructions = @"
=== GPO Deployment Instructions ===

1. Copy the WS1_EnrollmentTools folder to a network share accessible to your target computers
   For example: \\domain\netlogon\WS1_EnrollmentTools

2. Create a new Group Policy Object:
   - Name: Workspace One Enrollment Tools Deployment
   
3. Configure a Startup or Logon script:
   - For computer-based deployment: Computer Configuration > Policies > Windows Settings > Scripts > Startup
   - For user-based deployment: User Configuration > Policies > Windows Settings > Scripts > Logon
   - Add PowerShell script: \\domain\netlogon\GPOScript.ps1
   
4. Configure PowerShell execution policy (if needed):
   Computer Configuration > Policies > Administrative Templates > Windows Components > Windows PowerShell
   - Set "Turn on Script Execution" to "Enabled" and select "Allow all scripts"
   
5. Link the GPO to the appropriate organizational unit (OU) containing your target computers/users.

6. For testing, run: gpupdate /force on a client machine, then reboot to apply the startup script.

"@
        $gpoInstructions | Out-File -FilePath "$OutputPath\GPODeploymentInstructions.txt" -Force
    }
}

# Create README file
$readmeContent = @"
# Workspace One Enrollment Tools Deployment Package

This package contains tools for facilitating Workspace One enrollment in Windows 10/11 environments,
with integration for Microsoft Intune.

## Package Contents

- WorkspaceOneWizard.psm1: GUI wizard for Workspace One enrollment
- LoggingModule.psm1: Logging functions
- TestScripts.ps1: Script testing functionality
- Invoke-WorkspaceOneSetup.ps1: Main integration script
- Test-WS1Environment.ps1: Environment validation tool
- WS1Config.json: Configuration file

## Deployment Method

This package is configured for deployment via $DeploymentType.
See the ${DeploymentType}DeploymentInstructions.txt file for detailed instructions.

## Configuration

The WS1Config.json file contains the following settings:
- Enrollment Server: $EnrollmentServer
- Organization: $OrganizationName
- Silent Mode: $($EnableSilentMode.IsPresent)

## Support

For assistance, contact your IT support team.

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

$readmeContent | Out-File -FilePath "$OutputPath\README.md" -Force

# Done
Write-Host "`nWorkspace One Enrollment Tools deployment package created successfully!" -ForegroundColor Green
Write-Host "Package location: $OutputPath" -ForegroundColor Cyan
Write-Host "Deployment method: $DeploymentType" -ForegroundColor Cyan
Write-Host "`nReview the ${DeploymentType}DeploymentInstructions.txt file for next steps." -ForegroundColor Yellow 