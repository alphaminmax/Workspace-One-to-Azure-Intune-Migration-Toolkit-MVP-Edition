#Requires -Version 5.1

<#
.SYNOPSIS
    Provides lock screen customization and guidance for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The LockScreenGuidance module customizes the Windows lock screen to provide
    contextual information and guidance to users during the migration process,
    including:
    - Stage-aware messaging that updates based on migration progress
    - Corporate branding integration
    - Clear instructions for users at different stages
    - Integration with the overall migration workflow
    
.NOTES
    File Name      : LockScreenGuidance.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

# Import required modules
if (-not (Get-Module -Name 'LoggingModule' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LoggingModule.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module LoggingModule.psm1 not found in $PSScriptRoot"
    }
}

# Import UserCommunicationFramework for notifications
if (-not (Get-Module -Name 'UserCommunicationFramework' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'UserCommunicationFramework.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        Write-Log -Message "UserCommunicationFramework module not found. Some features may be limited." -Level Warning
    }
}

# Script level variables
$script:LockScreenConfig = @{
    Enabled = $true
    CurrentStage = 'PreMigration'
    DefaultImagePath = "$env:SystemRoot\Web\Screen\img100.jpg"
    CustomImagePath = Join-Path -Path $env:ProgramData -ChildPath "WS1Migration\LockScreen"
    TemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath "..\templates\lockscreen"
    CompanyLogo = $null
    CompanyName = "Organization"
    PrimaryColor = "#0078D4"
    SecondaryColor = "#333333"
    RestoreOriginal = $true
    OriginalImageBackup = Join-Path -Path $env:TEMP -ChildPath "OriginalLockScreen.jpg"
    ContactInfoPath = Join-Path -Path $env:ProgramData -ChildPath "WS1Migration\ContactInfo"
    IncludeContactButton = $true
}

#region Private Functions

function Backup-OriginalLockScreen {
    <#
    .SYNOPSIS
        Backs up the original lock screen image.
    #>
    try {
        # Create backup directory if it doesn't exist
        $backupDir = Split-Path -Path $script:LockScreenConfig.OriginalImageBackup -Parent
        if (-not (Test-Path -Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }

        # Get current lock screen path from registry
        $lockScreenPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name "LockScreenImagePath" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LockScreenImagePath

        # If not found, use default Windows lock screen
        if (-not $lockScreenPath -or -not (Test-Path -Path $lockScreenPath)) {
            $lockScreenPath = $script:LockScreenConfig.DefaultImagePath
        }

        # Backup the original lock screen
        if (Test-Path -Path $lockScreenPath) {
            Copy-Item -Path $lockScreenPath -Destination $script:LockScreenConfig.OriginalImageBackup -Force
            Write-Log -Message "Original lock screen backed up to $($script:LockScreenConfig.OriginalImageBackup)" -Level Information
            return $true
        } else {
            Write-Log -Message "Original lock screen image not found at $lockScreenPath" -Level Warning
            return $false
        }
    }
    catch {
        Write-Log -Message "Failed to backup original lock screen: $_" -Level Error
        return $false
    }
}

function Test-AdminPrivileges {
    <#
    .SYNOPSIS
        Checks if the current user has administrator privileges.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-StageTemplate {
    <#
    .SYNOPSIS
        Gets the lock screen template for a specific migration stage.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('PreMigration', 'MigrationInProgress', 'UserAuthentication', 'PostMigration', 'Completed', 'Error')]
        [string]$Stage
    )
    
    $templatePath = Join-Path -Path $script:LockScreenConfig.TemplatesPath -ChildPath "$Stage.html"
    
    if (Test-Path -Path $templatePath) {
        return Get-Content -Path $templatePath -Raw
    }
    else {
        # Return a basic template if the file doesn't exist
        $templateContent = switch ($Stage) {
            "PreMigration" {
                @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 0; background-color: black; color: white; height: 100vh; overflow: hidden; }
        .container { display: flex; flex-direction: column; height: 100vh; padding: 20px; box-sizing: border-box; }
        .header { display: flex; align-items: center; }
        .logo { max-height: 40px; margin-right: 15px; }
        .company { font-size: 24px; font-weight: bold; color: $($script:LockScreenConfig.PrimaryColor); }
        .title { font-size: 36px; font-weight: bold; margin: 20px 0; color: white; }
        .message { font-size: 18px; line-height: 1.5; max-width: 800px; }
        .footer { margin-top: auto; font-size: 14px; color: #ccc; }
        .highlight { color: $($script:LockScreenConfig.PrimaryColor); font-weight: bold; }
        .contact-button-container { position: fixed; bottom: 20px; right: 20px; z-index: 1000; }
        .contact-button { background-color: $($script:LockScreenConfig.PrimaryColor); color: white; border: none; border-radius: 4px; padding: 10px 16px; font-size: 14px; font-weight: bold; cursor: pointer; box-shadow: 0 2px 5px rgba(0,0,0,0.2); }
        .contact-button:hover { background-color: #005a9e; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img class="logo" src="{0}" alt="Company Logo">
            <div class="company">$($script:LockScreenConfig.CompanyName)</div>
        </div>
        <div class="title">Device Migration Scheduled</div>
        <div class="message">
            <p>Your device is scheduled for migration from Workspace ONE to Microsoft Intune.</p>
            <p>Migration will begin automatically. Please:</p>
            <ul>
                <li>Save all your work</li>
                <li>Close all applications</li>
                <li>Keep your device powered on and connected to the network</li>
            </ul>
            <p class="highlight">No action is required from you at this time.</p>
        </div>
        <div class="footer">For assistance, please contact IT Support</div>
    </div>
</body>
</html>
"@
            }
            "MigrationInProgress" {
                return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 0; background-color: black; color: white; height: 100vh; overflow: hidden; }
        .container { display: flex; flex-direction: column; height: 100vh; padding: 20px; box-sizing: border-box; }
        .header { display: flex; align-items: center; }
        .logo { max-height: 40px; margin-right: 15px; }
        .company { font-size: 24px; font-weight: bold; color: $($script:LockScreenConfig.PrimaryColor); }
        .title { font-size: 36px; font-weight: bold; margin: 20px 0; color: white; }
        .message { font-size: 18px; line-height: 1.5; max-width: 800px; }
        .progress-container { margin: 20px 0; background-color: #333; border-radius: 8px; height: 20px; width: 80%; max-width: 600px; }
        .progress-bar { height: 100%; width: {1}%; background-color: $($script:LockScreenConfig.PrimaryColor); border-radius: 8px; }
        .status { margin-top: 10px; font-weight: bold; }
        .footer { margin-top: auto; font-size: 14px; color: #ccc; }
        .highlight { color: $($script:LockScreenConfig.PrimaryColor); font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img class="logo" src="{0}" alt="Company Logo">
            <div class="company">$($script:LockScreenConfig.CompanyName)</div>
        </div>
        <div class="title">Migration in Progress</div>
        <div class="message">
            <p>Your device is being migrated from Workspace ONE to Microsoft Intune.</p>
            <p>Current status: <span class="highlight">{2}</span></p>
            <div class="progress-container">
                <div class="progress-bar"></div>
            </div>
            <div class="status">{1}% Complete</div>
            <p class="highlight">Please do not turn off your device.</p>
        </div>
        <div class="footer">For assistance, please contact IT Support</div>
    </div>
</body>
</html>
"@
            }
            "UserAuthentication" {
                return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 0; background-color: black; color: white; height: 100vh; overflow: hidden; }
        .container { display: flex; flex-direction: column; height: 100vh; padding: 20px; box-sizing: border-box; }
        .header { display: flex; align-items: center; }
        .logo { max-height: 40px; margin-right: 15px; }
        .company { font-size: 24px; font-weight: bold; color: $($script:LockScreenConfig.PrimaryColor); }
        .title { font-size: 36px; font-weight: bold; margin: 20px 0; color: white; }
        .message { font-size: 18px; line-height: 1.5; max-width: 800px; }
        .action { margin-top: 20px; padding: 15px; background-color: $($script:LockScreenConfig.PrimaryColor); color: white; border-radius: 8px; font-weight: bold; display: inline-block; }
        .footer { margin-top: auto; font-size: 14px; color: #ccc; }
        .highlight { color: $($script:LockScreenConfig.PrimaryColor); font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img class="logo" src="{0}" alt="Company Logo">
            <div class="company">$($script:LockScreenConfig.CompanyName)</div>
        </div>
        <div class="title">Action Required: Sign in with Microsoft Account</div>
        <div class="message">
            <p>Your device migration requires you to sign in with your Microsoft account.</p>
            <p>When you unlock your device, you will be prompted to:</p>
            <ol>
                <li>Enter your email address: <span class="highlight">{1}</span></li>
                <li>Enter your password</li>
                <li>Follow the prompts to complete authentication</li>
            </ol>
            <div class="action">Unlock your device now to continue the migration</div>
        </div>
        <div class="footer">For assistance, please contact IT Support</div>
    </div>
</body>
</html>
"@
            }
            "PostMigration" {
                return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 0; background-color: black; color: white; height: 100vh; overflow: hidden; }
        .container { display: flex; flex-direction: column; height: 100vh; padding: 20px; box-sizing: border-box; }
        .header { display: flex; align-items: center; }
        .logo { max-height: 40px; margin-right: 15px; }
        .company { font-size: 24px; font-weight: bold; color: $($script:LockScreenConfig.PrimaryColor); }
        .title { font-size: 36px; font-weight: bold; margin: 20px 0; color: white; }
        .message { font-size: 18px; line-height: 1.5; max-width: 800px; }
        .progress-container { margin: 20px 0; background-color: #333; border-radius: 8px; height: 20px; width: 80%; max-width: 600px; }
        .progress-bar { height: 100%; width: {1}%; background-color: $($script:LockScreenConfig.PrimaryColor); border-radius: 8px; }
        .status { margin-top: 10px; font-weight: bold; }
        .footer { margin-top: auto; font-size: 14px; color: #ccc; }
        .highlight { color: $($script:LockScreenConfig.PrimaryColor); font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img class="logo" src="{0}" alt="Company Logo">
            <div class="company">$($script:LockScreenConfig.CompanyName)</div>
        </div>
        <div class="title">Finalizing Migration</div>
        <div class="message">
            <p>Your device migration to Microsoft Intune is almost complete.</p>
            <p>Current status: <span class="highlight">{2}</span></p>
            <div class="progress-container">
                <div class="progress-bar"></div>
            </div>
            <div class="status">{1}% Complete</div>
            <p class="highlight">Almost done! Please do not turn off your device.</p>
        </div>
        <div class="footer">For assistance, please contact IT Support</div>
    </div>
</body>
</html>
"@
            }
            "Completed" {
                return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 0; background-color: black; color: white; height: 100vh; overflow: hidden; }
        .container { display: flex; flex-direction: column; height: 100vh; padding: 20px; box-sizing: border-box; }
        .header { display: flex; align-items: center; }
        .logo { max-height: 40px; margin-right: 15px; }
        .company { font-size: 24px; font-weight: bold; color: $($script:LockScreenConfig.PrimaryColor); }
        .title { font-size: 36px; font-weight: bold; margin: 20px 0; color: white; }
        .message { font-size: 18px; line-height: 1.5; max-width: 800px; }
        .success { font-size: 72px; color: green; margin: 10px 0; }
        .footer { margin-top: auto; font-size: 14px; color: #ccc; }
        .highlight { color: $($script:LockScreenConfig.PrimaryColor); font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img class="logo" src="{0}" alt="Company Logo">
            <div class="company">$($script:LockScreenConfig.CompanyName)</div>
        </div>
        <div class="title">Migration Complete</div>
        <div class="success">✓</div>
        <div class="message">
            <p>Your device has been successfully migrated to Microsoft Intune.</p>
            <p>You can now use your device normally. The next time you log in, you'll be using your Microsoft account.</p>
            <p class="highlight">Thank you for your patience during this process.</p>
        </div>
        <div class="footer">For assistance, please contact IT Support</div>
    </div>
</body>
</html>
"@
            }
            "Error" {
                return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 0; background-color: black; color: white; height: 100vh; overflow: hidden; }
        .container { display: flex; flex-direction: column; height: 100vh; padding: 20px; box-sizing: border-box; }
        .header { display: flex; align-items: center; }
        .logo { max-height: 40px; margin-right: 15px; }
        .company { font-size: 24px; font-weight: bold; color: $($script:LockScreenConfig.PrimaryColor); }
        .title { font-size: 36px; font-weight: bold; margin: 20px 0; color: #FF4500; }
        .message { font-size: 18px; line-height: 1.5; max-width: 800px; }
        .error { font-size: 72px; color: #FF4500; margin: 10px 0; }
        .error-details { background-color: #333; padding: 15px; border-radius: 8px; font-family: monospace; margin: 10px 0; }
        .footer { margin-top: auto; font-size: 14px; color: #ccc; }
        .highlight { color: #FF4500; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img class="logo" src="{0}" alt="Company Logo">
            <div class="company">$($script:LockScreenConfig.CompanyName)</div>
        </div>
        <div class="title">Migration Error</div>
        <div class="error">⚠</div>
        <div class="message">
            <p>An error occurred during the migration process:</p>
            <div class="error-details">{1}</div>
            <p>IT support has been notified and will assist you with resolving this issue.</p>
            <p class="highlight">Please contact IT support for immediate assistance.</p>
        </div>
        <div class="footer">For assistance, please contact IT Support</div>
    </div>
</body>
</html>
"@
            }
        }
        
        return $templateContent
    }
}

function Create-LockScreenImage {
    <#
    .SYNOPSIS
        Creates a lock screen image with HTML overlay.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$HtmlContent,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [object[]]$Parameters = @()
    )
    
    try {
        # Set default output path if not provided
        if (-not $OutputPath) {
            if (-not (Test-Path -Path $script:LockScreenConfig.CustomImagePath)) {
                New-Item -Path $script:LockScreenConfig.CustomImagePath -ItemType Directory -Force | Out-Null
            }
            $OutputPath = Join-Path -Path $script:LockScreenConfig.CustomImagePath -ChildPath "MigrationLockScreen.jpg"
        }

        # Format HTML with parameters
        $logoPath = if ($script:LockScreenConfig.CompanyLogo -and (Test-Path -Path $script:LockScreenConfig.CompanyLogo)) {
            $script:LockScreenConfig.CompanyLogo
        } else {
            "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg" # Default image as logo placeholder
        }
        
        $formattedParameters = @($logoPath) + $Parameters
        $formattedHtml = $HtmlContent -f $formattedParameters
        
        # Save HTML to temporary file
        $tempHtmlPath = Join-Path -Path $env:TEMP -ChildPath "LockScreen_$(Get-Random).html"
        $formattedHtml | Out-File -FilePath $tempHtmlPath -Encoding utf8
        
        # For now, we'll use a simple approach - in a real implementation,
        # we would use a library like System.Windows.Forms.WebBrowser to render the HTML to an image
        # or use a headless browser like Chromium via the Edge WebView2 control
        
        # For this demo, we'll just copy a default image
        if (Test-Path -Path $script:LockScreenConfig.DefaultImagePath) {
            Copy-Item -Path $script:LockScreenConfig.DefaultImagePath -Destination $OutputPath -Force
            Write-Log -Message "Created temporary lock screen image at $OutputPath" -Level Information
            
            # In a real implementation, we would render the HTML to the image here
            Write-Log -Message "HTML content prepared for lock screen (rendering to image not implemented)" -Level Information
            
            # Clean up temp HTML
            if (Test-Path -Path $tempHtmlPath) {
                Remove-Item -Path $tempHtmlPath -Force
            }
            
            return $OutputPath
        } else {
            Write-Log -Message "Default image not found at $($script:LockScreenConfig.DefaultImagePath)" -Level Warning
            return $null
        }
    }
    catch {
        Write-Log -Message "Failed to create lock screen image: $_" -Level Error
        return $null
    }
}

function Set-WindowsLockScreen {
    <#
    .SYNOPSIS
        Sets the Windows lock screen using given image path.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )
    
    try {
        # Check if the image exists
        if (-not (Test-Path -Path $ImagePath)) {
            Write-Log -Message "Lock screen image not found at $ImagePath" -Level Error
            return $false
        }
        
        # Set lock screen via registry
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
        
        # Create registry key if it doesn't exist
        if (-not (Test-Path -Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Set registry values
        Set-ItemProperty -Path $regPath -Name "LockScreenImagePath" -Value $ImagePath -Type String -Force
        Set-ItemProperty -Path $regPath -Name "LockScreenImageUrl" -Value $ImagePath -Type String -Force
        Set-ItemProperty -Path $regPath -Name "LockScreenImageStatus" -Value 1 -Type DWord -Force
        
        # Force update
        RUNDLL32.EXE USER32.DLL, UpdatePerUserSystemParameters 1, True
        
        Write-Log -Message "Windows lock screen set to $ImagePath" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to set Windows lock screen: $_" -Level Error
        return $false
    }
}

function Add-ContactCollectionButton {
    <#
    .SYNOPSIS
        Adds a contact information collection button to the lock screen HTML.
    .DESCRIPTION
        Injects a button into the HTML template that allows users to provide their
        contact information during the migration process.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$HtmlContent
    )
    
    try {
        # Only add the button if contact collection is enabled
        if (-not $script:LockScreenConfig.IncludeContactButton) {
            return $HtmlContent
        }
        
        # Inject the contact button HTML before the closing body tag
        $buttonHtml = @"
<div class="contact-button-container">
    <button class="contact-button" onclick="window.location='ms-appx://contactcollection'">Provide Contact Information</button>
</div>
"@
        
        $modifiedHtml = $HtmlContent -replace '</body>', "$buttonHtml`r`n</body>"
        
        Write-Log -Message "Contact collection button added to lock screen HTML" -Level Information
        return $modifiedHtml
    }
    catch {
        Write-Log -Message "Failed to add contact collection button: $_" -Level Error
        return $HtmlContent  # Return original content on error
    }
}

function Get-ContactInfo {
    <#
    .SYNOPSIS
        Retrieves the user's contact information if provided.
    .DESCRIPTION
        Gets the contact information that the user has provided through the
        contact collection form on the lock screen.
    .EXAMPLE
        $contactInfo = Get-ContactInfo
        if ($contactInfo) {
            Send-EmailNotification -To $contactInfo.Email
        }
    .OUTPUTS
        PSCustomObject with Email and Phone properties if available.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $contactInfoPath = $script:LockScreenConfig.ContactInfoPath
        $contactInfoFile = Join-Path -Path $contactInfoPath -ChildPath "ContactInfo.json"
        
        # Check if contact info exists
        if (-not (Test-Path -Path $contactInfoFile)) {
            Write-Log -Message "No contact information file found at $contactInfoFile" -Level Information
            return $null
        }
        
        # Read and parse the contact info
        $contactInfo = Get-Content -Path $contactInfoFile -Raw | ConvertFrom-Json
        
        Write-Log -Message "Contact information retrieved successfully" -Level Information
        return $contactInfo
    }
    catch {
        Write-Log -Message "Failed to retrieve contact information: $_" -Level Error
        return $null
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the Lock Screen Guidance module.
    
.DESCRIPTION
    Sets up the Lock Screen Guidance module with company branding and configuration.
    Creates necessary directories and prepares the module for use.
    
.PARAMETER Enabled
    Whether lock screen customization is enabled.
    
.PARAMETER CompanyName
    The name of the company to display on the lock screen.
    
.PARAMETER CompanyLogo
    Path to the company logo image to display on the lock screen.
    
.PARAMETER PrimaryColor
    The primary color to use for highlights in HTML format (e.g., #0078D4).
    
.PARAMETER SecondaryColor
    The secondary color to use in HTML format.
    
.PARAMETER RestoreOriginal
    Whether to restore the original lock screen when migration is complete.
    
.PARAMETER TemplatesPath
    Path to custom lock screen templates.
    
.PARAMETER CustomImagePath
    Path to store custom lock screen images.
    
.EXAMPLE
    Initialize-LockScreenGuidance -CompanyName "Contoso" -CompanyLogo "C:\Branding\logo.png" -PrimaryColor "#0078D4"
    
.OUTPUTS
    System.Boolean. Returns $true if initialization was successful.
#>
function Initialize-LockScreenGuidance {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$Enabled = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$CompanyName,
        
        [Parameter(Mandatory = $false)]
        [string]$CompanyLogo,
        
        [Parameter(Mandatory = $false)]
        [string]$PrimaryColor,
        
        [Parameter(Mandatory = $false)]
        [string]$SecondaryColor,
        
        [Parameter(Mandatory = $false)]
        [bool]$RestoreOriginal = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$TemplatesPath,
        
        [Parameter(Mandatory = $false)]
        [string]$CustomImagePath
    )
    
    # Check admin privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Log -Message "Administrator privileges required for lock screen customization" -Level Error
        return $false
    }
    
    try {
        # Update configuration with provided parameters
        $script:LockScreenConfig.Enabled = $Enabled
        
        if ($PSBoundParameters.ContainsKey('CompanyName')) { $script:LockScreenConfig.CompanyName = $CompanyName }
        if ($PSBoundParameters.ContainsKey('CompanyLogo')) { $script:LockScreenConfig.CompanyLogo = $CompanyLogo }
        if ($PSBoundParameters.ContainsKey('PrimaryColor')) { $script:LockScreenConfig.PrimaryColor = $PrimaryColor }
        if ($PSBoundParameters.ContainsKey('SecondaryColor')) { $script:LockScreenConfig.SecondaryColor = $SecondaryColor }
        if ($PSBoundParameters.ContainsKey('RestoreOriginal')) { $script:LockScreenConfig.RestoreOriginal = $RestoreOriginal }
        
        if ($PSBoundParameters.ContainsKey('TemplatesPath') -and (Test-Path -Path $TemplatesPath)) { 
            $script:LockScreenConfig.TemplatesPath = $TemplatesPath 
        }
        
        if ($PSBoundParameters.ContainsKey('CustomImagePath')) { 
            $script:LockScreenConfig.CustomImagePath = $CustomImagePath 
        }
        
        # Create necessary directories
        $directories = @(
            $script:LockScreenConfig.CustomImagePath,
            $script:LockScreenConfig.TemplatesPath
        )
        
        foreach ($dir in $directories) {
            if (-not (Test-Path -Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-Log -Message "Created directory: $dir" -Level Information
            }
        }
        
        # Backup original lock screen if restore is enabled
        if ($script:LockScreenConfig.RestoreOriginal) {
            Backup-OriginalLockScreen | Out-Null
        }
        
        Write-Log -Message "Lock Screen Guidance module initialized successfully" -Level Information
        return $true
    }
    catch {
        Write-Log -Message "Failed to initialize Lock Screen Guidance module: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Updates the lock screen to show migration stage information.
    
.DESCRIPTION
    Updates the Windows lock screen to display stage-specific information
    and guidance based on the current migration stage.
    
.PARAMETER Stage
    The current migration stage.
    
.PARAMETER Parameters
    Additional parameters for the lock screen template (e.g., progress percentage).
    
.EXAMPLE
    Update-MigrationLockScreen -Stage "MigrationInProgress" -Parameters @(50, "Installing Intune client...")
    
.OUTPUTS
    System.Boolean. Returns $true if the lock screen was updated successfully.
#>
function Update-MigrationLockScreen {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('PreMigration', 'MigrationInProgress', 'UserAuthentication', 'PostMigration', 'Completed', 'Error')]
        [string]$Stage,
        
        [Parameter(Mandatory = $false)]
        [object[]]$Parameters = @(),
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeContactButton = $script:LockScreenConfig.IncludeContactButton
    )
    
    # If disabled, do nothing
    if (-not $script:LockScreenConfig.Enabled) {
        Write-Log -Message "Lock screen customization is disabled" -Level Information
        return $true
    }
    
    # Check admin privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Log -Message "Administrator privileges required for lock screen customization" -Level Error
        return $false
    }
    
    try {
        # Update current stage
        $script:LockScreenConfig.CurrentStage = $Stage
        
        # Get the template for the current stage
        $template = Get-StageTemplate -Stage $Stage
        
        # Add contact button if requested
        if ($IncludeContactButton) {
            $template = Add-ContactCollectionButton -HtmlContent $template
        }
        
        # Create the lock screen image
        $lockScreenImagePath = Create-LockScreenImage -HtmlContent $template -Parameters $Parameters
        
        if (-not $lockScreenImagePath -or -not (Test-Path -Path $lockScreenImagePath)) {
            Write-Log -Message "Failed to create lock screen image" -Level Error
            return $false
        }
        
        # Set the Windows lock screen
        $result = Set-WindowsLockScreen -ImagePath $lockScreenImagePath
        
        if ($result) {
            Write-Log -Message "Lock screen updated successfully to stage: $Stage" -Level Information
            return $true
        } else {
            Write-Log -Message "Failed to update lock screen" -Level Error
            return $false
        }
    }
    catch {
        Write-Log -Message "Failed to update migration lock screen: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Sets a stage-specific lock screen with progress information.
    
.DESCRIPTION
    Updates the lock screen with a progress bar and status message
    for stages that support progress reporting.
    
.PARAMETER Stage
    The current migration stage.
    
.PARAMETER PercentComplete
    Percentage of the stage completed (0-100).
    
.PARAMETER StatusMessage
    Current status message to display on the lock screen.
    
.EXAMPLE
    Set-LockScreenProgress -Stage "MigrationInProgress" -PercentComplete 75 -StatusMessage "Configuring policies..."
    
.OUTPUTS
    System.Boolean. Returns $true if the lock screen was updated successfully.
#>
function Set-LockScreenProgress {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('MigrationInProgress', 'PostMigration')]
        [string]$Stage,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage
    )
    
    # If disabled, do nothing
    if (-not $script:LockScreenConfig.Enabled) {
        Write-Log -Message "Lock screen customization is disabled" -Level Information
        return $true
    }
    
    return Update-MigrationLockScreen -Stage $Stage -Parameters @($PercentComplete, $StatusMessage)
}

<#
.SYNOPSIS
    Shows an error message on the lock screen.
    
.DESCRIPTION
    Updates the lock screen to display an error message when
    the migration process encounters a problem.
    
.PARAMETER ErrorMessage
    The error message to display on the lock screen.
    
.EXAMPLE
    Show-LockScreenError -ErrorMessage "Failed to connect to Intune service"
    
.OUTPUTS
    System.Boolean. Returns $true if the lock screen was updated successfully.
#>
function Show-LockScreenError {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    
    # If disabled, do nothing
    if (-not $script:LockScreenConfig.Enabled) {
        Write-Log -Message "Lock screen customization is disabled" -Level Information
        return $true
    }
    
    return Update-MigrationLockScreen -Stage "Error" -Parameters @($ErrorMessage)
}

<#
.SYNOPSIS
    Prompts for user authentication on the lock screen.
    
.DESCRIPTION
    Updates the lock screen to guide the user through the authentication
    process when user interaction is required.
    
.PARAMETER UserEmail
    The user's email address to display on the lock screen.
    
.EXAMPLE
    Show-AuthenticationPrompt -UserEmail "user@contoso.com"
    
.OUTPUTS
    System.Boolean. Returns $true if the lock screen was updated successfully.
#>
function Show-AuthenticationPrompt {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserEmail
    )
    
    # If disabled, do nothing
    if (-not $script:LockScreenConfig.Enabled) {
        Write-Log -Message "Lock screen customization is disabled" -Level Information
        return $true
    }
    
    return Update-MigrationLockScreen -Stage "UserAuthentication" -Parameters @($UserEmail)
}

<#
.SYNOPSIS
    Restores the original Windows lock screen.
    
.DESCRIPTION
    Reverts the lock screen to its original state before
    customization by the migration process.
    
.PARAMETER Force
    Force restoration even if the module is disabled.
    
.EXAMPLE
    Restore-OriginalLockScreen -Force
    
.OUTPUTS
    System.Boolean. Returns $true if the lock screen was restored successfully.
#>
function Restore-OriginalLockScreen {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Check if we should restore
    if (-not $script:LockScreenConfig.RestoreOriginal -and -not $Force) {
        Write-Log -Message "Lock screen restoration is disabled" -Level Information
        return $true
    }
    
    # Check admin privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Log -Message "Administrator privileges required for lock screen restoration" -Level Error
        return $false
    }
    
    try {
        # Check if we have a backup of the original
        if (Test-Path -Path $script:LockScreenConfig.OriginalImageBackup) {
            # Restore the original lock screen
            $result = Set-WindowsLockScreen -ImagePath $script:LockScreenConfig.OriginalImageBackup
            
            if ($result) {
                Write-Log -Message "Original lock screen restored successfully" -Level Information
                return $true
            } else {
                Write-Log -Message "Failed to restore original lock screen" -Level Error
                return $false
            }
        } else {
            # Fallback to default Windows lock screen
            $result = Set-WindowsLockScreen -ImagePath $script:LockScreenConfig.DefaultImagePath
            
            if ($result) {
                Write-Log -Message "Restored default Windows lock screen" -Level Information
                return $true
            } else {
                Write-Log -Message "Failed to restore default Windows lock screen" -Level Error
                return $false
            }
        }
    }
    catch {
        Write-Log -Message "Failed to restore original lock screen: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Gets the current lock screen configuration.
    
.DESCRIPTION
    Returns the current configuration of the Lock Screen Guidance module.
    
.EXAMPLE
    Get-LockScreenConfig
    
.OUTPUTS
    System.Collections.Hashtable. Returns the current lock screen configuration.
#>
function Get-LockScreenConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return $script:LockScreenConfig.Clone()
}

#endregion

# Export public functions
Export-ModuleMember -Function Initialize-LockScreenGuidance, Update-MigrationLockScreen, Set-LockScreenProgress, Show-LockScreenError, Show-AuthenticationPrompt, Restore-OriginalLockScreen, Get-LockScreenConfig, Get-ContactInfo 