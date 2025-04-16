# Remote Administration Runbook: WS1 to Azure/Intune Migration Toolkit

## 1. Overview

This runbook provides technical procedures for remote deployment, monitoring, and troubleshooting of the Workspace ONE to Azure/Intune Migration Toolkit. It is designed for IT administrators who need to manage the migration process remotely across multiple endpoints.

## 2. Prerequisites

- Admin access to:
  - Azure tenant and Intune environment
  - Workspace ONE UEM console
  - Azure Key Vault (for credential management)
  - Target devices (via remote management tools)
- PowerShell 5.1 or later on all systems
- Required modules:
  - Microsoft.Graph.Intune
  - Azure.Identity
  - Az.KeyVault
  - VMware.Horizon.RESTAPI (for Workspace ONE)
- Certificate for secure authentication (stored in Azure Key Vault)

## 3. Permission Model and Authentication

### 3.1 Execution Model

All scripts in the migration toolkit are designed to run with local administrator privileges. This eliminates the need for end-user authentication and ensures consistent execution across devices.

```powershell
# Check if running as administrator
function Test-AdminPrivileges {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Ensure script is running as administrator
if (-not (Test-AdminPrivileges)) {
    Write-Error "This script must be run as Administrator. Please restart with elevated privileges."
    exit 1
}
```

### 3.2 Certificate-Based Authentication

The toolkit uses certificate-based authentication to Azure services instead of username/password credentials:

```powershell
# Configure certificate-based authentication
function Initialize-CertificateAuth {
    param (
        [Parameter(Mandatory=$true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory=$true)]
        [string]$CertificateName,
        
        [Parameter(Mandatory=$true)]
        [string]$ApplicationId
    )
    
    try {
        # Connect to Key Vault using Managed Identity
        Connect-AzAccount -Identity

        # Get certificate from Key Vault
        $certSecret = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName
        $cert = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $certSecret.Name -AsPlainText
        
        # Convert to certificate object
        $certBytes = [System.Convert]::FromBase64String($cert)
        $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
        $certCollection.Import($certBytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        
        # Save certificate to local store for use by other functions
        $certificatePath = Join-Path -Path $env:TEMP -ChildPath "MigrationCert.pfx"
        [System.IO.File]::WriteAllBytes($certificatePath, $certBytes)
        
        # Connect to Microsoft Graph with certificate
        Connect-MgGraph -CertificateName $certSecret.Name -TenantId (Get-AzContext).Tenant.Id -AppId $ApplicationId
        
        return @{
            Success = $true
            CertificatePath = $certificatePath
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
```

### 3.3 Azure Key Vault Integration

All credentials and secrets are stored and retrieved from Azure Key Vault:

```powershell
# Configure and validate Key Vault access
function Test-KeyVaultAccess {
    param (
        [Parameter(Mandatory=$true)]
        [string]$KeyVaultName
    )
    
    try {
        # Connect using Managed Identity
        Connect-AzAccount -Identity
        
        # Test Key Vault access
        $keyVaultTest = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop
        
        if ($keyVaultTest) {
            Write-Output "Successfully connected to Key Vault: $KeyVaultName"
            return $true
        }
    }
    catch {
        Write-Error "Failed to access Key Vault: $_"
        return $false
    }
}
```

## 4. Remote Deployment

### 4.1 Preparation

```powershell
# Verify remote PS session capabilities on target device
Test-WSMan -ComputerName <device_name>

# Get certificate from Key Vault for authentication
$certAuthParams = @{
    KeyVaultName = "MigrationKeyVault"
    CertificateName = "RemoteAdminCert"
    ApplicationId = "12345678-1234-1234-1234-123456789012" # Your Azure AD app registration ID
}
$certResult = Initialize-CertificateAuth @certAuthParams

# Create PS credentials for remote connection (using local admin account)
$adminCred = New-Object System.Management.Automation.PSCredential(".\administrator", (ConvertTo-SecureString "LocalAdminPassword" -AsPlainText -Force))

# Test connection to target device
Test-Connection -ComputerName <device_name> -Count 2
```

### 4.2 Toolkit Deployment

```powershell
# Establish remote PowerShell session with local admin account
$sessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
$session = New-PSSession -ComputerName <device_name> -Credential $adminCred -SessionOption $sessionOptions

# Copy migration toolkit to remote system
Copy-Item -Path "C:\MigrationToolkit\*" -Destination "C:\MigrationToolkit\" -ToSession $session -Recurse

# Verify file copy
Invoke-Command -Session $session -ScriptBlock {
    Test-Path -Path "C:\MigrationToolkit\src\scripts\Invoke-WorkspaceOneSetup.ps1"
}
```

### 4.3 Remote Configuration

```powershell
# Upload custom configuration file
Copy-Item -Path "config\customSettings.json" -Destination "C:\MigrationToolkit\config\" -ToSession $session

# Configure SecurityFoundation with Key Vault integration (certificate-based)
Invoke-Command -Session $session -ScriptBlock {
    param($certPath, $appId, $tenantId)
    
    Import-Module "C:\MigrationToolkit\src\modules\SecurityFoundation.psm1"
    
    # Set up certificate-based authentication
    Enable-KeyVaultIntegration -KeyVaultName "MigrationKeyVault" `
                              -CertificatePath $certPath `
                              -ApplicationId $appId `
                              -TenantId $tenantId
} -ArgumentList $certResult.CertificatePath, $certAuthParams.ApplicationId, (Get-AzContext).Tenant.Id

# Ensure execution as local admin for all subsequent operations
Invoke-Command -Session $session -ScriptBlock {
    # Set flag to use local admin for all operations
    Set-MigrationConfig -UseLocalAdmin $true -SkipUserPrompts $true
}
```

## 5. Remote Monitoring

### 5.1 Setting Up Monitoring

```powershell
# Configure central logging location
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\LoggingModule.psm1"
    Initialize-Logging -LogPath "\\central-server\logs\$env:COMPUTERNAME.log" -LogLevel "VERBOSE"
}

# Setup scheduled task for status reporting
Invoke-Command -Session $session -ScriptBlock {
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\MigrationToolkit\src\scripts\Send-StatusReport.ps1"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName "MigrationStatusReport" -Action $action -Trigger $trigger -RunLevel Highest
}
```

### 5.2 Real-time Monitoring

```powershell
# Stream logs in real-time from remote machine
Invoke-Command -Session $session -ScriptBlock {
    Get-Content -Path "C:\MigrationToolkit\logs\migration.log" -Tail 10 -Wait
}

# Check migration status
Invoke-Command -Session $session -ScriptBlock {
    $statusFile = "C:\MigrationToolkit\status\migrationStatus.json"
    if (Test-Path $statusFile) {
        Get-Content $statusFile | ConvertFrom-Json
    } else {
        Write-Output "Status file not found"
    }
}
```

### 5.3 Proactive Monitoring

```powershell
# Create alert for failed migrations
Invoke-Command -ComputerName "monitoring-server" -ScriptBlock {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'WS1Migration'
        Level = 2  # Error level
        StartTime = (Get-Date).AddHours(-1)
    }
    
    if ($events.Count -gt 0) {
        Send-MailMessage -To "admin@example.com" -From "alerts@example.com" `
            -Subject "Migration Errors Detected" `
            -Body "Migration errors detected on the following devices: $($events | Select-Object MachineName | Join-String -Separator ', ')" `
            -SmtpServer "smtp.example.com"
    }
}
```

## 6. Remote Troubleshooting

### 6.1 Diagnosing Issues

```powershell
# Get migration diagnostic info (runs as local admin)
Invoke-Command -Session $session -ScriptBlock {
    # Ensure running as admin
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Diagnostic collection requires administrator privileges"
        return $null
    }
    
    Import-Module "C:\MigrationToolkit\src\modules\MigrationVerification.psm1"
    $diagnosticInfo = Get-MigrationDiagnosticInfo -IncludePrivilegedInfo $true
    $diagnosticInfo | ConvertTo-Json -Depth 5 | Out-File "C:\MigrationToolkit\diagnostics\$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $diagnosticInfo
}

# Check for permission-related errors in logs
Invoke-Command -Session $session -ScriptBlock {
    $permissionPatterns = @(
        "Access denied",
        "Insufficient privileges",
        "Permission denied",
        "requires elevation",
        "administrator privileges required"
    )
    
    $logPath = "C:\MigrationToolkit\logs\migration.log"
    foreach ($pattern in $permissionPatterns) {
        $errors = Select-String -Path $logPath -Pattern $pattern
        if ($errors) {
            Write-Output "Found permission issues: $pattern"
            $errors | ForEach-Object { Write-Output "  $_" }
        }
    }
}
```

### 6.2 Common Issues and Resolutions

#### Authentication Failures

```powershell
# Reset authentication cache
Invoke-Command -Session $session -ScriptBlock {
    # Clear MSAL token cache
    $tokenCachePath = "$env:LOCALAPPDATA\MigrationToolkit\msal_token_cache.bin"
    if (Test-Path $tokenCachePath) { Remove-Item $tokenCachePath -Force }
    
    # Test authentication after cache reset
    Import-Module "C:\MigrationToolkit\src\modules\SecurityFoundation.psm1"
    Import-Module "C:\MigrationToolkit\src\modules\GraphAPIIntegration.psm1"
    
    $cred = Get-KeyVaultCredential -Name "IntuneGraphAPI"
    $authResult = Connect-MgGraph -Credential $cred
    $authResult
}
```

#### BitLocker Issues

```powershell
# Verify BitLocker status
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\BitLockerManager.psm1"
    
    # Get current BitLocker status
    $bitlockerStatus = Get-BitLockerStatus
    
    # If recovery keys need backup
    if ($bitlockerStatus.NeedsBackup) {
        # Force backup of recovery keys to Azure AD
        $backupResult = Backup-BitLockerToAzureAD -Force
        $backupResult
    }
}
```

#### Migration Engine Failures

```powershell
# Restart migration process from last checkpoint
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\MigrationEngine.psm1"
    
    # Get last checkpoint
    $checkpoint = Get-MigrationCheckpoint
    
    # Resume from last successful stage
    if ($checkpoint) {
        $resumeResult = Resume-Migration -FromCheckpoint $checkpoint -SkipVerification
        $resumeResult
    } else {
        Write-Error "No valid checkpoint found to resume migration"
    }
}
```

### 6.3 Remote Remediation Actions

```powershell
# Reset local configuration
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\ConfigurationManager.psm1"
    Reset-MigrationConfiguration -PreserveCredentials
}

# Force synchronization with Intune
Invoke-Command -Session $session -ScriptBlock {
    # Initiate forced MDM sync
    Start-Process -FilePath "DeviceEnroller.exe" -ArgumentList "/o" -NoNewWindow
}

# Repair WS1 uninstallation issues
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\WorkspaceOneIntegration.psm1"
    
    # Force clean uninstallation
    $uninstallResult = Remove-WorkspaceOneComponents -Force -CleanupRegistry
    $uninstallResult
}
```

## 7. Remote Rollback Procedures

### 7.1 Initiating Rollback

```powershell
# Trigger emergency rollback
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\RollbackMechanism.psm1"
    
    # Check if rollback is possible
    $canRollback = Test-RollbackAvailability
    
    if ($canRollback) {
        # Initiate full rollback to WS1
        $rollbackResult = Start-MigrationRollback -Reason "RemoteAdminInitiated" -Priority High
        $rollbackResult
    } else {
        Write-Error "Rollback is not available on this system. Backup may be missing or corrupted."
    }
}
```

### 7.2 Monitoring Rollback Progress

```powershell
# Check rollback status
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\RollbackMechanism.psm1"
    
    # Get current rollback status
    $rollbackStatus = Get-RollbackStatus
    
    # Output progress
    $rollbackStatus.Progress
    
    # Check if there are any blocking issues
    if ($rollbackStatus.BlockingIssues) {
        $rollbackStatus.BlockingIssues | ForEach-Object { Write-Output "Blocking Issue: $_" }
    }
}
```

### 7.3 Verifying Rollback Success

```powershell
# Verify WS1 is functional after rollback
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\WorkspaceOneIntegration.psm1"
    
    # Test WS1 agent functionality
    $ws1Status = Test-WorkspaceOneStatus
    
    # Output verification results
    if ($ws1Status.AgentInstalled -and $ws1Status.AgentRunning -and $ws1Status.EnrollmentActive) {
        Write-Output "Rollback successful: WS1 is fully functional"
    } else {
        Write-Error "Rollback verification failed. WS1 status: $($ws1Status | ConvertTo-Json)"
    }
}
```

## 8. Security Incidents

### 8.1 Credential Compromise Response

```powershell
# Rotate compromised credentials
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\SecurityFoundation.psm1"
    
    # Rotate Key Vault secrets
    $rotationResult = Invoke-CredentialRotation -CredentialName "IntuneGraphAPI" -GenerateNewPassword
    
    # Verify rotation
    if ($rotationResult.Success) {
        Write-Output "Credentials rotated successfully. Old credentials revoked."
    } else {
        Write-Error "Failed to rotate credentials: $($rotationResult.Error)"
    }
}
```

### 8.2 Audit Log Analysis

```powershell
# Collect security audit logs
Invoke-Command -Session $session -ScriptBlock {
    $securityAuditPath = Join-Path -Path $env:TEMP -ChildPath "WS1Migration\SecurityAudit"
    $auditLogs = Get-ChildItem -Path $securityAuditPath -Filter "SecurityAudit_*.log"
    
    # Parse and analyze logs
    $suspiciousEvents = @()
    foreach ($log in $auditLogs) {
        $content = Get-Content $log.FullName | ConvertFrom-Json
        # Look for suspicious patterns
        $suspiciousEvents += $content | Where-Object { 
            $_.Level -eq "Critical" -or
            $_.Message -like "*unauthorized*" -or
            $_.Message -like "*failed authentication*" -or
            ($_.Message -like "*elevated*" -and $_.Message -like "*privilege*")
        }
    }
    
    # Report findings
    if ($suspiciousEvents.Count -gt 0) {
        $suspiciousEvents | ConvertTo-Json -Depth 3 | 
            Out-File "C:\MigrationToolkit\security\suspicious_events.json"
        Write-Warning "Found $($suspiciousEvents.Count) suspicious security events!"
    }
}
```

## 9. Common Troubleshooting Scenarios

### 9.1 Failed Intune Enrollment

**Symptoms:**
- Device shows "Pending" in Intune console
- Error code 80180018 in MDM diagnostics
- Log entry: "Failed to join Azure AD"

**Resolution Steps:**
```powershell
Invoke-Command -Session $session -ScriptBlock {
    # Check Azure AD join status
    dsregcmd /status
    
    # Reset device enrollment
    Import-Module "C:\MigrationToolkit\src\modules\IntuneIntegration.psm1"
    Reset-IntuneEnrollment
    
    # Retry enrollment
    Join-AzureADDevice
}
```

### 9.2 Missing BitLocker Keys in Azure AD

**Symptoms:**
- BitLocker keys not visible in Azure portal
- Log entry: "Failed to backup BitLocker key to Azure AD"

**Resolution Steps:**
```powershell
Invoke-Command -Session $session -ScriptBlock {
    Import-Module "C:\MigrationToolkit\src\modules\BitLockerManager.psm1"
    
    # Get recovery keys
    $volumes = Get-BitLockerVolume
    foreach ($volume in $volumes) {
        $recoveryKey = ($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }).RecoveryPassword
        
        if ($recoveryKey) {
            # Manual backup to Azure AD
            BackupToAAD-BitLockerKeyProtector -MountPoint $volume.MountPoint -KeyProtectorId ($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }).KeyProtectorId
        }
    }
}
```

### 9.3 Workspace ONE Uninstallation Failures

**Symptoms:**
- WS1 agent still running after migration
- Policies from both WS1 and Intune applied
- Log entry: "Failed to remove Workspace ONE components"

**Resolution Steps:**
```powershell
Invoke-Command -Session $session -ScriptBlock {
    # Force stop WS1 services
    Stop-Service -Name "AirWatchAgent" -Force
    Stop-Service -Name "AWWindowsService" -Force
    
    # Uninstall using direct MSI commands with logging
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x {GUID-FOR-WS1-AGENT} /qn /l*v C:\temp\ws1_uninstall.log" -Wait
    
    # Clean up registry
    Remove-Item -Path "HKLM:\SOFTWARE\AirWatch" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\VMware, Inc." -Recurse -Force -ErrorAction SilentlyContinue
    
    # Clean up file system
    Remove-Item -Path "C:\Program Files (x86)\AirWatch" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Reboot if required
    Restart-Computer -Force
}
```

### 9.4 Permission and Elevation Issues

**Symptoms:**
- Scripts fail with "Access Denied" errors
- Error code 0x80070005 in logs
- Log entry: "The operation requires elevation"

**Resolution Steps:**
```powershell
Invoke-Command -Session $session -ScriptBlock {
    # Check current execution context
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output "Running as Administrator: $isAdmin"
    
    # Check if script execution policy is restricting execution
    $executionPolicy = Get-ExecutionPolicy
    Write-Output "Current Execution Policy: $executionPolicy"
    
    if (-not $isAdmin) {
        # Create a scheduled task to run the script with highest privileges
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\MigrationToolkit\src\scripts\Invoke-ElevatedAction.ps1"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $task = New-ScheduledTask -Action $action -Principal $principal
        Register-ScheduledTask -TaskName "MigrationElevatedAction" -InputObject $task
        
        # Start the task immediately
        Start-ScheduledTask -TaskName "MigrationElevatedAction"
        
        # Wait for completion
        while ((Get-ScheduledTask -TaskName "MigrationElevatedAction").State -ne 'Ready') {
            Start-Sleep -Seconds 1
        }
        
        # Get results
        $result = Get-Content "C:\MigrationToolkit\logs\elevated_action_result.json" | ConvertFrom-Json
        Write-Output "Elevated action completed with status: $($result.Status)"
    }
}
```

## 10. Remote Administration Contacts

For emergency escalation, contact:

- **Primary Contact**: Migration Team Lead
  - Email: migration-lead@example.com
  - Phone: +1-555-123-4567
  
- **Technical Support**:
  - Email: migration-support@example.com
  - Phone: +1-555-987-6543
  
- **Security Incident Response**:
  - Email: security@example.com
  - Phone: +1-555-111-2222

## 11. Appendices

### 11.1 Migration Status Codes

| Code | Description | Action Required |
|------|-------------|----------------|
| M001 | Migration initiated | None |
| M002 | Pre-migration assessment complete | Review assessment report |
| M003 | WS1 backup created | Verify backup integrity |
| M004 | WS1 components removed | None |
| M005 | Intune enrollment complete | Verify device in Intune console |
| M006 | BitLocker keys backed up | Verify in Azure AD |
| M007 | Migration complete | Perform post-migration verification |
| E001 | WS1 backup failed | Check storage and permissions |
| E002 | WS1 removal failed | See troubleshooting section 9.3 |
| E003 | Intune enrollment failed | See troubleshooting section 9.1 |
| E004 | BitLocker backup failed | See troubleshooting section 9.2 |
| R001 | Rollback initiated | None |
| R002 | Rollback complete | Verify WS1 functionality |

### 11.2 Required PowerShell Modules
```powershell
# Required modules for remote administration
$requiredModules = @(
    "Microsoft.Graph.Intune",
    "Microsoft.Graph.Authentication",
    "AzureAD",
    "Az.KeyVault",
    "VMware.Horizon.RESTAPI"
)

# Function to ensure all required modules are available
function Ensure-RequiredModules {
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Install-Module -Name $module -Scope CurrentUser -Force
        }
    }
}
```

### 11.3 Log File Locations

| Log Type | Location | Purpose |
|----------|----------|---------|
| Migration Log | C:\MigrationToolkit\logs\migration.log | Overall migration process |
| Security Audit | %TEMP%\WS1Migration\SecurityAudit\*.log | Security-related events |
| WS1 Uninstall | C:\temp\ws1_uninstall.log | Workspace ONE removal |
| MDM Diagnostics | Event Viewer: Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider | Intune enrollment issues |
| BitLocker | Event Viewer: Applications and Services Logs > Microsoft > Windows > BitLocker-API | BitLocker operations |

### 11.4 Setting Up Certificate-Based Authentication

To set up certificate-based authentication for remote administration:

1. Create an Azure AD app registration:
```powershell
# Create Azure AD application
$app = New-AzADApplication -DisplayName "WS1MigrationToolkit"

# Create a self-signed certificate
$cert = New-SelfSignedCertificate -Subject "CN=WS1MigrationCert" -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256

# Export certificate to PFX
$certPassword = ConvertTo-SecureString -String "CertPassword" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "C:\Temp\WS1MigrationCert.pfx" -Password $certPassword

# Convert certificate to Base64 string for Azure AD
$certBytes = [System.IO.File]::ReadAllBytes("C:\Temp\WS1MigrationCert.pfx")
$certBase64 = [System.Convert]::ToBase64String($certBytes)

# Add certificate to Azure AD application
New-AzADAppCredential -ApplicationId $app.AppId -CertValue $certBase64 -StartDate $cert.NotBefore -EndDate $cert.NotAfter

# Store certificate in Key Vault
Import-AzKeyVaultCertificate -VaultName "MigrationKeyVault" -Name "WS1MigrationCert" -FilePath "C:\Temp\WS1MigrationCert.pfx" -Password $certPassword

# Grant application necessary permissions (example for Microsoft Graph)
# For Microsoft Graph permissions, follow Azure portal instructions
```

2. Grant necessary API permissions to the application:
   - Microsoft Graph: DeviceManagementConfiguration.ReadWrite.All
   - Microsoft Graph: Directory.Read.All
   - Microsoft Intune API: All necessary permissions

3. Create a service principal and assign appropriate roles:
```powershell
# Create service principal for the application
New-AzADServicePrincipal -ApplicationId $app.AppId

# Assign contributor role to Key Vault
New-AzRoleAssignment -ApplicationId $app.AppId -RoleDefinitionName "Contributor" -ResourceName "MigrationKeyVault" -ResourceType "Microsoft.KeyVault/vaults" -ResourceGroupName "MigrationResourceGroup"
```

### 11.5 Local Administrator Provisioning

To ensure consistent local administrator access across all devices:

1. Create a secure local administrator account:
```powershell
# Create a complex password
$securePassword = ConvertTo-SecureString "ComplexP@ssw0rd!" -AsPlainText -Force

# Create local admin account on target device
Invoke-Command -ComputerName <device_name> -ScriptBlock {
    param($password)
    
    # Create the local administrator account
    $adminUser = "MigrationAdmin"
    
    # Check if user exists
    $userExists = Get-LocalUser -Name $adminUser -ErrorAction SilentlyContinue
    
    if (-not $userExists) {
        # Create new user
        New-LocalUser -Name $adminUser -Password $password -PasswordNeverExpires $true -Description "Migration Toolkit Administrator"
        
        # Add to administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $adminUser
    } else {
        # Reset password if user exists
        Set-LocalUser -Name $adminUser -Password $password
    }
    
    Write-Output "Local admin account '$adminUser' configured successfully"
} -ArgumentList $securePassword
```

2. Store credentials securely in Key Vault:
```powershell
# Store local admin credentials in Key Vault
$adminUser = "MigrationAdmin"
$adminPassword = "ComplexP@ssw0rd!"  # Should be generated and secured

# Create a secure credential object
$securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($adminUser, $securePassword)

# Convert to JSON
$credentialJSON = @{
    Username = $credential.UserName
    Password = $adminPassword  # Never store in clear text in production
} | ConvertTo-Json

# Store in Key Vault
$secretValue = ConvertTo-SecureString $credentialJSON -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName "MigrationKeyVault" -Name "LocalAdminCredential" -SecretValue $secretValue
```

3. Retrieve and use credentials from migration scripts:
```powershell
# Retrieve local admin credentials from Key Vault using certificate auth
Import-Module "C:\MigrationToolkit\src\modules\SecurityFoundation.psm1"

# Get credentials
$localAdminSecret = Get-KeyVaultSecret -Name "LocalAdminCredential"
$localAdminCreds = $localAdminSecret | ConvertFrom-Json

# Create credential object
$securePassword = ConvertTo-SecureString $localAdminCreds.Password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($localAdminCreds.Username, $securePassword)

# Use for connections
$session = New-PSSession -ComputerName <device_name> -Credential $credential
``` 