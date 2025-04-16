################################################################################################################################
# Written by Jared Griego | Crayon | 4.16.2025 | Rev 1.0 | jared.griego@crayon.com                                              #
#                                                                                                                              #
# Creates a temporary local administrator account with a randomly generated secure password.                            #
# PowerShell 5.1 x32/x64                                                                                                       #
#                                                                                                                              #
################################################################################################################################

################################################################################################################################
#                                                                                                                              #
#      ██████╗██████╗  █████╗ ██╗   ██╗ ██████╗ ███╗   ██╗    ██╗   ██╗███████╗ █████╗                                        #
#     ██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗████╗  ██║    ██║   ██║██╔════╝██╔══██╗                                       #
#     ██║     ██████╔╝███████║ ╚████╔╝ ██║   ██║██╔██╗ ██║    ██║   ██║███████╗███████║                                       #
#     ██║     ██╔══██╗██╔══██║  ╚██╔╝  ██║   ██║██║╚██╗██║    ██║   ██║╚════██║██╔══██║                                       #
#     ╚██████╗██║  ██║██║  ██║   ██║   ╚██████╔╝██║ ╚████║    ╚██████╔╝███████║██║  ██║                                       #
#      ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝     ╚═════╝ ╚══════╝╚═╝  ╚═╝                                       #
#                                                                                                                              #
################################################################################################################################
    Creates a temporary local administrator account with a randomly generated secure password.
.DESCRIPTION
    This script creates a temporary local administrator account with a complex random password
    for use during elevated operations that require administrative privileges. The account
    is intended to be used temporarily and then removed after operations are complete.
    
    This tool is part of the Workspace One to Azure/Intune migration process and is used
    for privilege elevation when required. It is typically called by the PrivilegeManagement
    module but can also be used standalone for scripted deployments.
    
    After creating a temporary admin account, the migration process can use these credentials
    to perform operations that require elevated privileges, and then remove the account when done.
.PARAMETER Prefix
    A prefix for the username (default: "WS1Mig").
.PARAMETER PasswordLength
    The length of the generated password (default: 20).
.PARAMETER OutputFile
    Optional path to save the credential information to a secure file.
.EXAMPLE
    .\New-TemporaryAdminAccount.ps1 -Prefix "Migration"
.NOTES
    Part of the Workspace One to Azure/Intune Migration Toolkit
    
    Workflow:
    1. Use this script to create a temporary admin account
    2. Use the account for elevated operations
    3. Remove the account after operations are complete
    
    Security considerations:
    - The account is created with a complex password
    - The account should be removed immediately after use
    - Credential information is only saved to a file if explicitly requested
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Prefix = "WS1Mig",
    
    [Parameter()]
    [int]$PasswordLength = 20,
    
    [Parameter()]
    [string]$OutputFile = ""
)

# Import logging module if available
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "modules\LoggingModule.psm1"

if (Test-Path -Path $modulePath) {
    Import-Module $modulePath -Force
    $logPath = "C:\Temp\Logs\AdminAccount_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (-not (Test-Path -Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -Force | Out-Null
    }
    Initialize-Logging -LogPath $logPath -Level INFO
    $loggingImported = $true
} else {
    # Create a basic logging function if module not available
    function Write-LogMessage {
        param (
            [string]$Message,
            [string]$Level = "INFO"
        )
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Write to console
        switch ($Level) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            default { Write-Host $logMessage }
        }
    }
    $loggingImported = $false
}

function New-TempAdmin {
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter()]
        [string]$Prefix = "WS1Mig",
        
        [Parameter()]
        [int]$PasswordLength = 20
    )
    
    Write-LogMessage -Message "Creating temporary admin account" -Level INFO
    
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage -Message "This script requires administrative privileges" -Level ERROR
        throw "Administrative privileges required to create a local admin account"
    }
    
    # Generate a random username with prefix
    $randomSuffix = [guid]::NewGuid().ToString().Substring(0, 8)
    $username = "$Prefix-$randomSuffix"
    
    # Generate a complex random password
    $charSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}|;:',<.>/?"
    $securePassword = New-Object System.Security.SecureString
    
    $random = New-Object System.Random
    
    # Ensure password meets complexity requirements
    $hasLower = $false
    $hasUpper = $false
    $hasDigit = $false
    $hasSpecial = $false
    
    for ($i = 0; $i -lt $PasswordLength; $i++) {
        $randomIndex = $random.Next(0, $charSet.Length)
        $randomChar = $charSet[$randomIndex]
        $securePassword.AppendChar($randomChar)
        
        if ($randomChar -cmatch '[a-z]') { $hasLower = $true }
        if ($randomChar -cmatch '[A-Z]') { $hasUpper = $true }
        if ($randomChar -cmatch '[0-9]') { $hasDigit = $true }
        if ($randomChar -match '[^a-zA-Z0-9]') { $hasSpecial = $true }
    }
    
    # Ensure we meet complexity requirements
    if (-not ($hasLower -and $hasUpper -and $hasDigit -and $hasSpecial)) {
        # If not, generate a new password that meets requirements
        $securePassword = New-Object System.Security.SecureString
        
        $securePassword.AppendChar('P') # Uppercase
        $securePassword.AppendChar('a') # Lowercase
        $securePassword.AppendChar('5') # Digit
        $securePassword.AppendChar('!') # Special
        
        for ($i = 4; $i -lt $PasswordLength; $i++) {
            $randomIndex = $random.Next(0, $charSet.Length)
            $securePassword.AppendChar($charSet[$randomIndex])
        }
    }
    
    # Create credential object
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    
    # Create the account
    try {
        # Convert from secure string for account creation
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        
        # Create the user account
        $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
        $user = $computer.Create("User", $username)
        $user.SetPassword($plainPassword)
        $user.SetInfo()
        
        # Set account properties
        $user.Description = "Temporary admin account for Workspace One to Azure migration"
        $user.UserFlags = 66049 # ADS_UF_DONT_EXPIRE_PASSWD + ADS_UF_SCRIPT
        $user.SetInfo()
        
        # Add to administrators group
        $group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
        $group.Add("WinNT://$env:COMPUTERNAME/$username,user")
        
        Write-LogMessage -Message "Successfully created temporary admin account: $username" -Level INFO
        return $credential
    } catch {
        Write-LogMessage -Message "Error creating temporary admin account: ${_}" -Level ERROR
        throw
    }
}

function Remove-TempAdmin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )
    
    Write-LogMessage -Message "Removing temporary admin account: $($Credential.UserName)" -Level INFO
    
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage -Message "This script requires administrative privileges" -Level ERROR
        throw "Administrative privileges required to remove a local admin account"
    }
    
    try {
        # Remove the user
        $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
        $computer.Delete("User", $Credential.UserName)
        Write-LogMessage -Message "Successfully removed temporary admin account: $($Credential.UserName)" -Level INFO
        return $true
    } catch {
        Write-LogMessage -Message "Error removing temporary admin account: ${_}" -Level ERROR
        throw
    }
}

# Main script execution
try {
    # Create the temporary admin account
    $tempAdmin = New-TempAdmin -Prefix $Prefix -PasswordLength $PasswordLength
    
    # Output the username
    Write-Output "Created temporary admin account: $($tempAdmin.UserName)"
    
    # Save to file if specified
    if ($OutputFile) {
        try {
            $exportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
            $tempAdmin | Export-Clixml -Path $exportPath -Force
            Write-LogMessage -Message "Saved credential information to: $exportPath" -Level INFO
            Write-Output "Saved credential information to: $exportPath"
            Write-Output "To retrieve: `$credential = Import-Clixml -Path '$exportPath'"
        } catch {
            Write-LogMessage -Message "Failed to save credential information: ${_}" -Level ERROR
        }
    }
    
    # Return the credential for use in scripts
    return $tempAdmin
} catch {
    Write-LogMessage -Message "Failed to create temporary admin account: ${_}" -Level ERROR
    throw
} 




