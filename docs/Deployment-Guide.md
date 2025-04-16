![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# Deployment Guide: Workspace ONE to Azure/Intune Migration Solution

This guide provides detailed instructions for deploying the Workspace ONE to Azure/Intune migration solution in your environment.

## Prerequisites

Before deploying the migration solution, ensure your environment meets the following requirements:

* Windows 10 1909 or later
* PowerShell 5.1 or PowerShell 7.2+
* Administrative access to target machines (for installation only)
* Network connectivity to Microsoft Graph API endpoints
* Azure AD application registration with necessary permissions:
  * DeviceManagementApps.ReadWrite.All
  * DeviceManagementConfiguration.ReadWrite.All
  * DeviceManagementManagedDevices.ReadWrite.All
  * Directory.Read.All
* Workspace ONE API access credentials (if performing data extraction)

## Deployment Methods

The migration solution can be deployed using several methods:

### Method 1: Manual Deployment

1. Download the latest migration solution package from the releases page
2. Extract the package to a local directory
3. Run the `Install-MigrationSolution.ps1` script with administrator privileges:

```powershell
.\Install-MigrationSolution.ps1 -InstallPath "C:\Program Files\WS1Migration" -ConfigPath ".\config.json"
```

### Method 2: Microsoft Intune Deployment

1. Create a Win32 app in Microsoft Intune
2. Upload the migration solution package (.intunewin)
3. Configure the following install command:

```
powershell.exe -ExecutionPolicy Bypass -File .\Install-MigrationSolution.ps1 -Silent -ConfigPath ".\config.json"
```

4. Configure the following uninstall command:

```
powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-MigrationSolution.ps1 -Silent
```

5. Set detection rules to check for the presence of:
   * File: `C:\Program Files\WS1Migration\migrationcomplete.marker`
   * Registry key: `HKLM:\SOFTWARE\WS1Migration\Installed`

### Method 3: SCCM Deployment

1. Create a new application in SCCM
2. Add the migration solution package as the deployment type
3. Configure the deployment type with the following settings:
   * Content location: Network share containing the migration package
   * Installation program: `powershell.exe -ExecutionPolicy Bypass -File .\Install-MigrationSolution.ps1 -Silent -ConfigPath ".\config.json"`
   * Uninstall program: `powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-MigrationSolution.ps1 -Silent`
4. Configure detection method using the same criteria as Method 2
5. Deploy to your target collection

### Method 4: PowerShell Deployment Script

For automated deployments across multiple machines:

```powershell
$computers = "Computer1", "Computer2", "Computer3"
$sourceDir = "\\server\share\MigrationSolution"
$destDir = "C:\Program Files\WS1Migration"

foreach ($computer in $computers) {
    # Create destination directory
    Invoke-Command -ComputerName $computer -ScriptBlock {
        param($dest)
        if (-not (Test-Path $dest)) {
            New-Item -Path $dest -ItemType Directory -Force
        }
    } -ArgumentList $destDir

    # Copy files
    Copy-Item -Path "$sourceDir\*" -Destination "\\$computer\c$\Program Files\WS1Migration" -Recurse -Force

    # Run installation
    Invoke-Command -ComputerName $computer -ScriptBlock {
        param($dest)
        Set-Location $dest
        .\Install-MigrationSolution.ps1 -Silent -ConfigPath ".\config.json"
    } -ArgumentList $destDir
}
```

## Configuration

The migration solution is configured using a JSON configuration file. Here's a sample configuration:

```json
{
  "General": {
    "LogPath": "C:\\ProgramData\\WS1Migration\\Logs",
    "TelemetryEnabled": true,
    "TelemetryUrl": "https://your-app-insights-url",
    "SilentMode": false
  },
  "Azure": {
    "TenantId": "00000000-0000-0000-0000-000000000000",
    "ClientId": "00000000-0000-0000-0000-000000000000",
    "ClientSecret": "",
    "UseClientCertificate": false,
    "ClientCertificatePath": "",
    "ClientCertificatePassword": ""
  },
  "WorkspaceOne": {
    "ApiUrl": "https://your-ws1-api-url",
    "ApiKey": "",
    "ApiUsername": "",
    "ApiPassword": ""
  },
  "Migration": {
    "PreserveLegacyAgent": false,
    "CreateSystemRestorePoint": true,
    "BackupRegistryKeys": true,
    "RetentionDays": 30,
    "PostMigrationVerification": true
  },
  "UserExperience": {
    "ShowProgressDialog": true,
    "NotifyUserBeforeMigration": true,
    "AllowUserPostponement": true,
    "PostponementMaxDays": 5,
    "PostMigrationNotification": true
  },
  "HighPriorityComponents": {
    "RollbackEnabled": true,
    "VerificationLevel": "Comprehensive",
    "UserCommunicationMode": "Toast"
  }
}
```

## Deployment Scenarios

### Scenario 1: Basic Migration

For a basic migration with default settings:

1. Install the migration solution
2. Configure the minimum required settings (Azure and WorkspaceOne credentials)
3. Run the migration:

```powershell
Start-Migration -ComputerName $env:COMPUTERNAME
```

### Scenario 2: Phased Migration

For a phased migration across multiple devices:

1. Install the migration solution on all target devices
2. Create device groups in a CSV file:

```csv
ComputerName,MigrationGroup,MigrationDate
COMPUTER1,Phase1,2023-06-01
COMPUTER2,Phase1,2023-06-01
COMPUTER3,Phase2,2023-06-08
```

3. Run the phased migration:

```powershell
Import-Csv .\migration-groups.csv | Invoke-PhasedMigration -ConfigPath .\config.json
```

### Scenario 3: Silent Background Migration

For a completely silent migration:

1. Install the migration solution
2. Create a silent configuration:

```json
{
  "General": {
    "SilentMode": true
  },
  "UserExperience": {
    "ShowProgressDialog": false,
    "NotifyUserBeforeMigration": false,
    "PostMigrationNotification": true
  }
}
```

3. Run the silent migration:

```powershell
Start-Migration -ConfigPath .\silent-config.json -RunAsSilentTask
```

## Post-Deployment Verification

After deploying the migration solution, verify the installation:

1. Check for successful installation logs in the configured log directory
2. Verify the existence of the Windows service: "WS1MigrationService"
3. Run the verification tool:

```powershell
Test-MigrationDeployment -ComputerName $env:COMPUTERNAME
```

## Troubleshooting

Common deployment issues and their solutions:

### Issue: Installation fails with access denied

**Solution**: Ensure you're running the installation script with administrative privileges.

### Issue: Azure authentication fails

**Solution**: Verify the Azure AD application credentials and permissions. Run:

```powershell
Test-AzureConnectivity -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
```

### Issue: Workspace ONE API connection fails

**Solution**: Validate the Workspace ONE API credentials and URL. Run:

```powershell
Test-WorkspaceOneConnectivity -ApiUrl $apiUrl -ApiKey $apiKey -Username $username -Password $password
```

### Issue: Migration process starts but fails to complete

**Solution**: Check the migration logs for specific errors. Common causes include:

1. Insufficient permissions
2. Network connectivity issues
3. Device health issues

Run the diagnostic tool:

```powershell
Get-MigrationDiagnostics -LogPath "C:\ProgramData\WS1Migration\Logs" -ExportPath "C:\Temp\MigrationDiagnostics"
```

## Uninstallation

To uninstall the migration solution:

```powershell
.\Uninstall-MigrationSolution.ps1 -RemoveData $true -RemoveLogs $false
```

## Security Considerations

The migration solution implements the following security measures:

1. **Encryption**: All credentials are encrypted at rest
2. **Least Privilege**: The solution operates with minimal required permissions
3. **Temporary Elevation**: Admin operations use temporary elevation
4. **Audit Logging**: All actions are logged for security auditing

## Updating the Solution

To update to a newer version:

1. Download the latest version
2. Run the update script:

```powershell
.\Update-MigrationSolution.ps1 -PackagePath ".\MigrationSolution-v2.0.zip" -PreserveConfig $true
```

## Support and Maintenance

For ongoing support of the migration solution:

1. **Logs**: Review logs at the configured log path
2. **Telemetry**: Monitor telemetry data if enabled
3. **Updates**: Check for updates monthly
4. **Backups**: The solution maintains backups at:
   * Registry: `C:\ProgramData\WS1Migration\Backups\Registry`
   * Configuration: `C:\ProgramData\WS1Migration\Backups\Config`

## Appendix

### A. Command Reference

| Command | Description |
|---------|-------------|
| `Install-MigrationSolution` | Installs the migration solution |
| `Start-Migration` | Begins the migration process |
| `Test-MigrationPrerequisites` | Checks if prerequisites are met |
| `Get-MigrationStatus` | Reports current migration status |
| `Invoke-Rollback` | Rolls back a failed migration |
| `New-MigrationReport` | Generates a migration report |

### B. Registry Keys

The migration solution uses the following registry keys:

* `HKLM:\SOFTWARE\WS1Migration\Installed` - Installation status
* `HKLM:\SOFTWARE\WS1Migration\Config` - Configuration settings
* `HKLM:\SOFTWARE\WS1Migration\Status` - Migration status information

### C. File Locations

Key file locations:

* Executables: `C:\Program Files\WS1Migration\`
* Configuration: `C:\ProgramData\WS1Migration\Config\`
* Logs: `C:\ProgramData\WS1Migration\Logs\`
* Backups: `C:\ProgramData\WS1Migration\Backups\`
* Temp files: `C:\ProgramData\WS1Migration\Temp\` 
