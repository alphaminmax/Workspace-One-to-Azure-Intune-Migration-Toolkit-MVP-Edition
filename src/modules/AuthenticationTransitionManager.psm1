#Requires -Version 5.1

<#
.SYNOPSIS
    Manages authentication transition during Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The AuthenticationTransitionManager module handles credential provider manipulation,
    authentication method configuration, and identity provider transitions during
    the migration from Workspace One to Azure/Intune.
    
.NOTES
    File Name      : AuthenticationTransitionManager.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 0.2.0
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

# Import SecurityFoundation for credential management
if (-not (Get-Module -Name 'SecurityFoundation' -ListAvailable)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SecurityFoundation.psm1'
    if (Test-Path -Path $modulePath) {
        Import-Module -Name $modulePath -Force
    } else {
        throw "Required module SecurityFoundation.psm1 not found in $PSScriptRoot"
    }
}

# Script-level variables
$script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\config\settings.json"
$script:Config = $null
$script:CredProvRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
$script:AzureAdRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{8AF662BF-65A0-4D0A-A540-A338A999D36F}"
$script:MsaRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}"

#region Private Functions

function Initialize-Module {
    <#
    .SYNOPSIS
        Initializes the Authentication Transition Manager module.
    #>
    try {
        # Check if configuration file exists
        if (-not (Test-Path -Path $script:ConfigPath)) {
            Write-Log -Message "Configuration file not found at $script:ConfigPath" -Level WARNING
            return $false
        }
        
        # Load configuration
        $script:Config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        
        if (-not $script:Config) {
            Write-Log -Message "Failed to load configuration" -Level ERROR
            return $false
        }
        
        return $true
    }
    catch {
        Write-Log -Message "Error initializing Authentication Transition Manager: $_" -Level ERROR
        return $false
    }
}

function Get-CredentialProviders {
    <#
    .SYNOPSIS
        Gets the currently enabled credential providers.
    #>
    try {
        $providers = @()
        
        if (Test-Path -Path $script:CredProvRegPath) {
            $providerGUIDs = Get-ChildItem -Path $script:CredProvRegPath | Select-Object -ExpandProperty PSChildName
            
            foreach ($guid in $providerGUIDs) {
                $providerPath = Join-Path -Path $script:CredProvRegPath -ChildPath $guid
                $displayName = (Get-ItemProperty -Path $providerPath -ErrorAction SilentlyContinue).DisplayName
                $enabled = -not (Get-ItemProperty -Path $providerPath -Name "Disabled" -ErrorAction SilentlyContinue)
                
                $providers += [PSCustomObject]@{
                    GUID = $guid
                    DisplayName = $displayName
                    Enabled = $enabled
                    RegistryPath = $providerPath
                }
            }
        }
        
        return $providers
    }
    catch {
        Write-Log -Message "Error getting credential providers: $_" -Level ERROR
        return @()
    }
}

function Get-CurrentIdentityProvider {
    <#
    .SYNOPSIS
        Determines the currently active identity provider.
    #>
    try {
        # Check for Azure AD join status
        $dsregCmd = Start-Process -FilePath "dsregcmd.exe" -ArgumentList "/status" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\dsregstatus.txt"
        $dsregOutput = Get-Content -Path "$env:TEMP\dsregstatus.txt" -Raw
        Remove-Item -Path "$env:TEMP\dsregstatus.txt" -Force
        
        $isAzureAdJoined = $dsregOutput -match "AzureAdJoined : YES"
        $isEnterpriseJoined = $dsregOutput -match "EnterpriseJoined : YES"
        $isDomainJoined = $dsregOutput -match "DomainJoined : YES"
        
        if ($isAzureAdJoined) {
            return "AzureAD"
        }
        elseif ($isDomainJoined) {
            return "ActiveDirectory"
        }
        elseif ($isEnterpriseJoined) {
            return "WorkspaceOne"
        }
        else {
            return "LocalAccount"
        }
    }
    catch {
        Write-Log -Message "Error determining current identity provider: $_" -Level ERROR
        return "Unknown"
    }
}

function Backup-CredentialProviderSettings {
    <#
    .SYNOPSIS
        Backs up current credential provider settings.
    #>
    param (
        [Parameter(Mandatory = $false)]
        [string]$BackupPath = (Join-Path -Path $env:TEMP -ChildPath "CredProvBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg")
    )
    
    try {
        if (Test-Path -Path $script:CredProvRegPath) {
            # Export registry settings
            $exportResult = Start-Process -FilePath "reg.exe" -ArgumentList "export", "`"$script:CredProvRegPath`"", "`"$BackupPath`"", "/y" -NoNewWindow -Wait -PassThru
            
            if ($exportResult.ExitCode -eq 0) {
                Write-Log -Message "Credential provider settings backed up to $BackupPath" -Level INFO
                return $BackupPath
            }
        }
        
        Write-Log -Message "Failed to back up credential provider settings" -Level WARNING
        return $null
    }
    catch {
        Write-Log -Message "Error backing up credential provider settings: $_" -Level ERROR
        return $null
    }
}

#endregion

#region Public Functions

function Initialize-AuthenticationTransition {
    <#
    .SYNOPSIS
        Initializes the Authentication Transition Manager.
    
    .DESCRIPTION
        Sets up the Authentication Transition Manager module by loading
        configuration and preparing for credential provider manipulation.
        
    .PARAMETER ConfigPath
        Optional path to a JSON configuration file.
        
    .EXAMPLE
        Initialize-AuthenticationTransition -ConfigPath "C:\config.json"
        
    .OUTPUTS
        System.Boolean. Returns True if initialization is successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $script:ConfigPath
    )
    
    Write-Log -Message "Initializing Authentication Transition Manager" -Level INFO
    
    if ($ConfigPath -ne $script:ConfigPath) {
        $script:ConfigPath = $ConfigPath
    }
    
    try {
        # Initialize module
        if (-not (Initialize-Module)) {
            Write-Log -Message "Failed to initialize Authentication Transition Manager" -Level ERROR
            return $false
        }
        
        # Check for required permissions
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Log -Message "Authentication Transition Manager requires administrator privileges" -Level WARNING
        }
        
        Write-Log -Message "Authentication Transition Manager initialized successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Error during Authentication Transition Manager initialization: $_" -Level ERROR
        return $false
    }
}

function Get-AuthenticationStatus {
    <#
    .SYNOPSIS
        Gets the current authentication status.
    
    .DESCRIPTION
        Retrieves information about the current authentication state,
        including active credential providers and identity providers.
        
    .EXAMPLE
        Get-AuthenticationStatus
        
    .OUTPUTS
        PSCustomObject. Returns authentication status information.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    Write-Log -Message "Getting authentication status" -Level INFO
    
    try {
        # Initialize if needed
        if (-not $script:Config) {
            Initialize-Module
        }
        
        # Get credential providers
        $credProviders = Get-CredentialProviders
        
        # Get current identity provider
        $identityProvider = Get-CurrentIdentityProvider
        
        # Check Azure AD credentials
        $azureAdCredAvailable = Test-Path -Path $script:AzureAdRegPath
        
        # Check Microsoft Account credentials
        $msaCredAvailable = Test-Path -Path $script:MsaRegPath
        
        # Create result object
        $result = [PSCustomObject]@{
            IdentityProvider = $identityProvider
            CredentialProviders = $credProviders
            AzureAdCredentialsAvailable = $azureAdCredAvailable
            MsaCredentialsAvailable = $msaCredAvailable
            Timestamp = Get-Date
        }
        
        return $result
    }
    catch {
        Write-Log -Message "Error getting authentication status: $_" -Level ERROR
        
        # Return minimal status on error
        return [PSCustomObject]@{
            IdentityProvider = "Unknown"
            CredentialProviders = @()
            AzureAdCredentialsAvailable = $false
            MsaCredentialsAvailable = $false
            Timestamp = Get-Date
            Error = $_
        }
    }
}

function Set-CredentialProviderState {
    <#
    .SYNOPSIS
        Enables or disables a credential provider.
    
    .DESCRIPTION
        Modifies the registry to enable or disable specific credential providers.
        
    .PARAMETER ProviderGUID
        The GUID of the credential provider to modify.
        
    .PARAMETER Enabled
        Whether to enable or disable the credential provider.
        
    .EXAMPLE
        Set-CredentialProviderState -ProviderGUID "{8AF662BF-65A0-4D0A-A540-A338A999D36F}" -Enabled $true
        
    .OUTPUTS
        System.Boolean. Returns True if successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProviderGUID,
        
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    
    Write-Log -Message "Setting credential provider $ProviderGUID state to: $($Enabled ? 'Enabled' : 'Disabled')" -Level INFO
    
    try {
        # Check admin rights
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Log -Message "Administrator privileges required" -Level ERROR
            return $false
        }
        
        # Backup current settings
        $backupPath = Backup-CredentialProviderSettings
        
        # Set provider state
        $providerPath = Join-Path -Path $script:CredProvRegPath -ChildPath $ProviderGUID
        
        if (-not (Test-Path -Path $providerPath)) {
            Write-Log -Message "Credential provider $ProviderGUID not found" -Level ERROR
            return $false
        }
        
        if ($Enabled) {
            # Enable provider by removing Disabled value
            Remove-ItemProperty -Path $providerPath -Name "Disabled" -ErrorAction SilentlyContinue
        }
        else {
            # Disable provider
            Set-ItemProperty -Path $providerPath -Name "Disabled" -Value 1 -Type DWord -Force
        }
        
        # Verify changes
        $isDisabled = (Get-ItemProperty -Path $providerPath -Name "Disabled" -ErrorAction SilentlyContinue) -ne $null
        $success = $Enabled -eq (-not $isDisabled)
        
        if ($success) {
            Write-Log -Message "Successfully set credential provider state" -Level INFO
        }
        else {
            Write-Log -Message "Failed to set credential provider state" -Level ERROR
            
            # Try to restore backup if available
            if ($backupPath -and (Test-Path -Path $backupPath)) {
                Write-Log -Message "Attempting to restore from backup" -Level WARNING
                $restoreResult = Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$backupPath`"" -NoNewWindow -Wait -PassThru
            }
        }
        
        return $success
    }
    catch {
        Write-Log -Message "Error setting credential provider state: $_" -Level ERROR
        return $false
    }
}

function Enable-AzureAdAuthentication {
    <#
    .SYNOPSIS
        Enables Azure AD authentication.
    
    .DESCRIPTION
        Configures the system to enable Azure AD authentication methods.
        
    .PARAMETER DisableAlternatives
        Whether to disable other authentication methods.
        
    .EXAMPLE
        Enable-AzureAdAuthentication -DisableAlternatives $false
        
    .OUTPUTS
        System.Boolean. Returns True if successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$DisableAlternatives = $false
    )
    
    Write-Log -Message "Enabling Azure AD authentication" -Level INFO
    
    try {
        # Check admin rights
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Log -Message "Administrator privileges required" -Level ERROR
            return $false
        }
        
        # Backup current settings
        $backupPath = Backup-CredentialProviderSettings
        
        # Enable Azure AD credential provider
        $azureAdProviderGuid = "{8AF662BF-65A0-4D0A-A540-A338A999D36F}"
        $success = Set-CredentialProviderState -ProviderGUID $azureAdProviderGuid -Enabled $true
        
        if (-not $success) {
            Write-Log -Message "Failed to enable Azure AD credential provider" -Level ERROR
            return $false
        }
        
        # Disable alternative methods if requested
        if ($DisableAlternatives) {
            # Get current providers
            $providers = Get-CredentialProviders
            
            foreach ($provider in $providers) {
                if ($provider.GUID -ne $azureAdProviderGuid -and $provider.Enabled) {
                    Write-Log -Message "Disabling alternative credential provider: $($provider.DisplayName)" -Level INFO
                    Set-CredentialProviderState -ProviderGUID $provider.GUID -Enabled $false
                }
            }
        }
        
        Write-Log -Message "Azure AD authentication enabled successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Error enabling Azure AD authentication: $_" -Level ERROR
        return $false
    }
}

function Set-FallbackAuthenticationMethod {
    <#
    .SYNOPSIS
        Configures fallback authentication methods.
    
    .DESCRIPTION
        Sets up fallback authentication methods for recovery scenarios.
        
    .PARAMETER EnableLocalAccounts
        Whether to enable local account authentication.
        
    .PARAMETER EnablePasswordRecovery
        Whether to enable password recovery options.
        
    .EXAMPLE
        Set-FallbackAuthenticationMethod -EnableLocalAccounts $true -EnablePasswordRecovery $true
        
    .OUTPUTS
        System.Boolean. Returns True if successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$EnableLocalAccounts = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnablePasswordRecovery = $true
    )
    
    Write-Log -Message "Setting fallback authentication methods" -Level INFO
    
    try {
        # Check admin rights
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Log -Message "Administrator privileges required" -Level ERROR
            return $false
        }
        
        # Enable local account credential provider if requested
        if ($EnableLocalAccounts) {
            # Local account provider GUID
            $localAccProviderGuid = "{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}"
            $success = Set-CredentialProviderState -ProviderGUID $localAccProviderGuid -Enabled $true
            
            if (-not $success) {
                Write-Log -Message "Failed to enable local account credential provider" -Level WARNING
            }
        }
        
        # Enable password recovery if requested
        if ($EnablePasswordRecovery) {
            # Enable password reset capability via registry
            $recoveryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{D6886603-9D2F-4EB2-B667-1971041FA96B}"
            
            if (-not (Test-Path -Path $recoveryPath)) {
                New-Item -Path $recoveryPath -Force | Out-Null
            }
            
            Set-ItemProperty -Path $recoveryPath -Name "Enabled" -Value 1 -Type DWord -Force
            
            # Verify
            $isEnabled = (Get-ItemProperty -Path $recoveryPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -eq 1
            
            if (-not $isEnabled) {
                Write-Log -Message "Failed to enable password recovery" -Level WARNING
            }
        }
        
        Write-Log -Message "Fallback authentication methods configured successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log -Message "Error setting fallback authentication methods: $_" -Level ERROR
        return $false
    }
}

function Start-IdentityProviderTransition {
    <#
    .SYNOPSIS
        Starts the transition from one identity provider to another.
    
    .DESCRIPTION
        Orchestrates the transition between identity providers while ensuring
        that authentication is maintained throughout the process.
        
    .PARAMETER TargetProvider
        The target identity provider to transition to.
        
    .PARAMETER PreserveCurrentProvider
        Whether to keep the current provider enabled alongside the new one.
        
    .EXAMPLE
        Start-IdentityProviderTransition -TargetProvider "AzureAD" -PreserveCurrentProvider $true
        
    .OUTPUTS
        PSCustomObject. Returns transition status information.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AzureAD", "ActiveDirectory", "LocalAccount")]
        [string]$TargetProvider,
        
        [Parameter(Mandatory = $false)]
        [bool]$PreserveCurrentProvider = $true
    )
    
    Write-Log -Message "Starting identity provider transition to $TargetProvider" -Level INFO
    
    try {
        # Get current authentication status
        $currentStatus = Get-AuthenticationStatus
        $currentProvider = $currentStatus.IdentityProvider
        
        Write-Log -Message "Current identity provider: $currentProvider" -Level INFO
        
        if ($currentProvider -eq $TargetProvider) {
            Write-Log -Message "Already using target identity provider $TargetProvider" -Level INFO
            return [PSCustomObject]@{
                Success = $true
                CurrentProvider = $currentProvider
                TargetProvider = $TargetProvider
                TransitionStatus = "AlreadyCompleted"
                Message = "Already using target identity provider"
            }
        }
        
        # Backup settings before making changes
        $backupPath = Backup-CredentialProviderSettings
        
        # Configure fallback authentication for safety
        Set-FallbackAuthenticationMethod -EnableLocalAccounts $true -EnablePasswordRecovery $true
        
        # Enable target provider based on selection
        $success = $false
        switch ($TargetProvider) {
            "AzureAD" {
                $success = Enable-AzureAdAuthentication -DisableAlternatives (-not $PreserveCurrentProvider)
            }
            "ActiveDirectory" {
                $adProviderGuid = "{6f45dc1e-5384-457a-bc13-2cd81b0d28ed}"
                $success = Set-CredentialProviderState -ProviderGUID $adProviderGuid -Enabled $true
                
                if ($success -and -not $PreserveCurrentProvider) {
                    # Get current providers and disable others
                    $providers = Get-CredentialProviders
                    foreach ($provider in $providers) {
                        if ($provider.GUID -ne $adProviderGuid -and $provider.Enabled) {
                            Set-CredentialProviderState -ProviderGUID $provider.GUID -Enabled $false
                        }
                    }
                }
            }
            "LocalAccount" {
                $localProviderGuid = "{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}"
                $success = Set-CredentialProviderState -ProviderGUID $localProviderGuid -Enabled $true
                
                if ($success -and -not $PreserveCurrentProvider) {
                    # Get current providers and disable others
                    $providers = Get-CredentialProviders
                    foreach ($provider in $providers) {
                        if ($provider.GUID -ne $localProviderGuid -and $provider.Enabled) {
                            Set-CredentialProviderState -ProviderGUID $provider.GUID -Enabled $false
                        }
                    }
                }
            }
        }
        
        # Get updated status
        $newStatus = Get-AuthenticationStatus
        
        # Create result object
        $result = [PSCustomObject]@{
            Success = $success
            CurrentProvider = $currentProvider
            TargetProvider = $TargetProvider
            TransitionStatus = $success ? "InProgress" : "Failed"
            CurrentProviderRemains = $PreserveCurrentProvider
            FallbackConfigured = $true
            BackupPath = $backupPath
            Message = $success ? "Transition initiated successfully" : "Failed to initiate transition"
            NewStatus = $newStatus
        }
        
        Write-Log -Message "Identity provider transition result: $($result.Message)" -Level INFO
        return $result
    }
    catch {
        Write-Log -Message "Error during identity provider transition: $_" -Level ERROR
        
        return [PSCustomObject]@{
            Success = $false
            CurrentProvider = $currentProvider
            TargetProvider = $TargetProvider
            TransitionStatus = "Failed"
            Message = "Exception: $_"
            Error = $_
        }
    }
}

function Restore-CredentialProviderSettings {
    <#
    .SYNOPSIS
        Restores credential provider settings from backup.
    
    .DESCRIPTION
        Restores previously backed up credential provider settings in case of issues.
        
    .PARAMETER BackupPath
        Path to the backup registry file.
        
    .EXAMPLE
        Restore-CredentialProviderSettings -BackupPath "C:\Temp\CredProvBackup.reg"
        
    .OUTPUTS
        System.Boolean. Returns True if successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )
    
    Write-Log -Message "Restoring credential provider settings from $BackupPath" -Level INFO
    
    try {
        # Check if backup file exists
        if (-not (Test-Path -Path $BackupPath)) {
            Write-Log -Message "Backup file not found: $BackupPath" -Level ERROR
            return $false
        }
        
        # Import backup
        $importResult = Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$BackupPath`"" -NoNewWindow -Wait -PassThru
        
        if ($importResult.ExitCode -eq 0) {
            Write-Log -Message "Credential provider settings restored successfully" -Level INFO
            return $true
        }
        else {
            Write-Log -Message "Failed to restore credential provider settings (Exit code: $($importResult.ExitCode))" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log -Message "Error restoring credential provider settings: $_" -Level ERROR
        return $false
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Initialize-AuthenticationTransition
Export-ModuleMember -Function Get-AuthenticationStatus
Export-ModuleMember -Function Set-CredentialProviderState
Export-ModuleMember -Function Enable-AzureAdAuthentication
Export-ModuleMember -Function Set-FallbackAuthenticationMethod
Export-ModuleMember -Function Start-IdentityProviderTransition
Export-ModuleMember -Function Restore-CredentialProviderSettings 