# Migration Progress Monitoring

This document outlines the monitoring capabilities for the Workspace ONE to Azure/Intune migration process.

## Overview

The migration solution provides comprehensive monitoring capabilities that allow administrators to track the progress of migrations, identify issues, and generate reports. The monitoring system spans multiple components:

1. **Migration Dashboard**: Real-time visual interface
2. **Analytics Module**: Data collection and reporting engine
3. **Event Logging**: Detailed activity recording
4. **Verification Reporting**: Post-migration validation
5. **User Communication**: Status notifications for end users

## Migration Dashboard

The Migration Dashboard (`New-MigrationDashboard.ps1`) provides a real-time visual interface for monitoring migration progress.

### Dashboard Features

* **Real-time Status Overview**: At-a-glance view of migration progress
* **Device Migration Status**: See status of all devices being migrated
* **Component Health Indicators**: Status of key migration components
* **Error and Warning Display**: Quick identification of issues
* **Timeline View**: History of migration events
* **Filtering and Sorting**: Focus on specific devices or statuses

### Using the Dashboard

```powershell
# Launch the dashboard with default settings
.\src\scripts\New-MigrationDashboard.ps1

# Launch with custom refresh interval and data source
.\src\scripts\New-MigrationDashboard.ps1 -RefreshInterval 30 -DataSource "C:\MigrationData"

# Launch with network port for remote access
.\src\scripts\New-MigrationDashboard.ps1 -Port 8080 -AllowRemote
```

### Dashboard Components

1. **Status Summary Panel**: Overall progress statistics
2. **Device Grid**: Table of all devices with their current status
3. **Timeline Chart**: Visual representation of migration events over time
4. **Component Status**: Health indicators for migration components
5. **Recent Events**: Latest migration activities and issues
6. **Action Panel**: Controls for interacting with the migration process

## Analytics Module

The Migration Analytics module (`MigrationAnalytics.psm1`) collects, processes, and reports on migration data.

### Key Metrics Tracked

* **Success Rate**: Percentage of successful migrations
* **Failure Categories**: Types and frequency of failures
* **Duration Analytics**: Time spent in each migration phase
* **Component Performance**: Metrics on each component's reliability
* **Device Characteristics**: Correlations between device properties and migration outcomes

### Generating Analytics Reports

```powershell
# Generate a basic migration summary report
New-MigrationReport -OutputPath "C:\Reports"

# Generate a detailed report with all metrics
New-MigrationReport -OutputPath "C:\Reports" -Detailed -IncludeRawData

# Generate a report focusing on specific issues
New-MigrationReport -OutputPath "C:\Reports" -FilterByErrorType "NetworkConnectivity"
```

### Power BI Integration

For advanced analytics, the monitoring system can export data to Power BI:

1. Use `Export-MigrationAnalytics -Format PowerBI` to export data
2. Import the data into Power BI using the provided template
3. Refresh the data connection to update the visualizations

## Event Logging

The logging system captures detailed information about all migration activities.

### Log Sources

* **Migration Orchestrator Logs**: High-level migration process events
* **Component-Specific Logs**: Detailed logs from each module
* **Windows Event Logs**: System-level events related to migration
* **Application-Specific Logs**: Logs from migrated applications

### Accessing Logs

Logs are available in multiple locations:

* **File System**: `C:\ProgramData\WS1Migration\Logs` (default location)
* **Migration Dashboard**: Log viewer tab in the dashboard
* **Log Commands**: PowerShell cmdlets for log retrieval

```powershell
# Get recent migration logs
Get-MigrationLog -Last 100

# Get logs for a specific device
Get-MigrationLog -ComputerName "PC001" -Last 200

# Get logs for a specific error type
Get-MigrationLog -ErrorType "AuthenticationFailure"
```

### Log Consolidation

For environments with multiple devices, logs can be consolidated:

```powershell
# Collect logs from multiple devices
Invoke-LogCollection -ComputerList "devices.txt" -OutputPath "C:\ConsolidatedLogs"

# Export consolidated logs to CSV
Export-MigrationLog -Path "C:\ConsolidatedLogs" -Format CSV
```

## Verification Reporting

After migration, the verification system generates reports on migration success.

### Verification Reports Include

* **Enrollment Status**: Confirmation of successful Azure/Intune enrollment
* **Policy Application**: Verification that all policies are applied
* **Application Deployment**: Confirmation that applications are installed
* **Security Compliance**: Validation of security settings
* **Performance Metrics**: Before/after performance comparison

### Accessing Verification Reports

```powershell
# Get verification report for a single device
Get-VerificationReport -ComputerName "PC001"

# Get summary verification report for all devices
Get-VerificationReport -Summary

# Export verification reports to PDF
Export-VerificationReport -ComputerName "PC001" -Format PDF -OutputPath "C:\Reports"
```

### Failed Verification Handling

When verification fails, the system:

1. Records detailed information about the failure
2. Categorizes the failure type
3. Suggests remediation steps
4. Optionally triggers automatic remediation
5. Updates the dashboard with failure information

## User Communication

The monitoring system includes communication to end users about migration status.

### User Notifications

* **Pre-Migration**: Notifications about upcoming migrations
* **In-Progress**: Status updates during migration
* **Completion**: Notification of successful migration
* **Issue Alerts**: Notification when user action is required

### Notification Methods

* **Windows Toast Notifications**: Native Windows notifications
* **Email**: Email notifications to user's address
* **Custom Application**: Pop-up notifications from migration app
* **Teams/Slack**: Integration with messaging platforms

### Configuring User Notifications

```powershell
# Enable all user notifications
Set-UserCommunicationPreference -EnableAll

# Disable specific notification types
Set-UserCommunicationPreference -DisableNotificationType "InProgress"

# Set custom notification templates
Set-UserCommunicationTemplate -Type "Completion" -TemplatePath "C:\Templates\completion.html"
```

## Integration with External Systems

The monitoring capabilities can integrate with external systems:

### ServiceNow Integration

* Automatic ticket creation for failed migrations
* Ticket updates based on migration progress
* Knowledge article linking for common issues

### SCCM/Intune Integration

* Status reporting to SCCM/Intune console
* Compliance reporting integration
* Enforcement policy triggers

### Email/Teams Alerting

* Scheduled summary reports
* Threshold-based alerts
* Critical failure notifications

## Troubleshooting Common Monitoring Issues

| Issue | Possible Cause | Resolution |
|-------|----------------|------------|
| Dashboard not showing data | Log file location mismatch | Check configuration file for correct log path |
| Missing device data | Device not registered in monitoring | Run `Register-DeviceForMonitoring` |
| Inaccurate success rate | Verification timeout | Adjust verification timeout in settings |
| Report generation failure | Insufficient permissions | Run with administrative rights |
| Dashboard performance issues | Too much historical data | Use `-LimitData` parameter or archive old data |

## Best Practices for Migration Monitoring

1. **Set Up Before Migration**: Deploy monitoring before starting migrations
2. **Regular Report Reviews**: Schedule time to review migration reports
3. **Trend Analysis**: Look for patterns in failures or slow migrations
4. **Log Rotation**: Implement log archiving for long-term projects
5. **User Feedback**: Incorporate user experience feedback into monitoring
6. **Remediation Protocols**: Develop standard responses to common issues
7. **Knowledge Sharing**: Ensure all IT staff can access and understand reports

## Command Reference

| Command | Description |
|---------|-------------|
| `New-MigrationDashboard` | Creates and displays the migration dashboard |
| `Get-MigrationStatus` | Returns current migration status for devices |
| `Get-MigrationLog` | Retrieves migration log entries |
| `New-MigrationReport` | Generates migration reports |
| `Export-MigrationAnalytics` | Exports analytics data in various formats |
| `Register-MigrationEvent` | Records a migration event in the analytics system |
| `Get-VerificationReport` | Retrieves post-migration verification reports |
| `Set-UserCommunicationPreference` | Configures user notification settings |

## Additional Resources

* [Migration Dashboard User Guide](./MigrationDashboard.md)
* [Migration Analytics Reference](./MigrationAnalytics.md)
* [Verification Report Schema](./VerificationSchema.md)
* [Logging Configuration Guide](./LoggingConfiguration.md)
* [User Communication Framework](./UserCommunication.md) 