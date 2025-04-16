# Migration Analytics Documentation

## Overview

The MigrationAnalytics module collects, analyzes, and reports on migration metrics to provide insights into migration performance, success rates, and areas for improvement. This module integrates with other high-priority components to gather data and generate comprehensive reports and visualizations.

## Workflow Diagram

The migration analytics workflow diagram can be found in the following file:
[Migration Analytics Workflow Diagram](diagrams/migration-analytics.mmd)

## Key Features

- Initialization and configuration of metrics storage
- Registration of migration events (started, completed, failed)
- Component usage tracking
- Time metrics collection for migration phases
- Error categorization and analysis
- Migration summary statistics
- Comprehensive reporting in multiple formats (HTML, JSON, CSV)
- Visualizations and charts for analytics

## Module Functions

| Function | Description |
|----------|-------------|
| `Initialize-MigrationAnalytics` | Sets up the analytics module with custom paths |
| `Get-MigrationMetrics` | Retrieves all metrics data |
| `Save-MigrationMetrics` | Saves metrics data to storage |
| `Register-MigrationEvent` | Records a migration event with status and details |
| `New-MigrationAnalyticsReport` | Generates analytics reports in specified formats |
| `Register-ComponentUsage` | Records usage metrics for a specific component |
| `Register-MigrationPhaseTime` | Records time metrics for a migration phase |
| `Get-MigrationSummaryStats` | Retrieves quick summary statistics |
| `Clear-MigrationMetrics` | Clears all metrics data (for testing) |

## Usage Examples

### Initialize Analytics

```powershell
# Initialize with default settings
Initialize-MigrationAnalytics

# Initialize with custom paths
Initialize-MigrationAnalytics -MetricsPath "C:\MigrationData\Metrics" -ReportsPath "C:\MigrationData\Reports"
```

### Register Migration Events

```powershell
# Register a migration start
Register-MigrationEvent -DeviceName "LAPTOP001" -Status "Started"

# Register a successful migration with time metrics
$timeMetrics = @{
    Planning = 60
    Backup = 120
    WS1Removal = 180
    AzureSetup = 240
    IntuneEnrollment = 300
}
Register-MigrationEvent -DeviceName "LAPTOP001" -Status "Completed" -TimeMetrics $timeMetrics

# Register a failed migration with error details
Register-MigrationEvent -DeviceName "LAPTOP002" -Status "Failed" -ErrorCategory "Network" -ErrorMessage "Failed to connect to Azure AD"
```

### Record Component Usage

```powershell
# Record usage of the RollbackMechanism component
Register-ComponentUsage -ComponentName "RollbackMechanism" -Invocations 1 -Successes 1 -Failures 0

# Record multiple invocations
Register-ComponentUsage -ComponentName "SecurityFoundation" -Invocations 5 -Successes 4 -Failures 1
```

### Generate Reports

```powershell
# Generate HTML report with device details
New-MigrationAnalyticsReport -Format "HTML" -IncludeDeviceDetails

# Generate all report formats
New-MigrationAnalyticsReport -Format "All" -OutputPath "C:\Reports\MigrationAnalytics_$(Get-Date -Format 'yyyyMMdd')"
```

### Get Summary Statistics

```powershell
# Get quick summary statistics
$stats = Get-MigrationSummaryStats
Write-Host "Total migrations: $($stats.TotalMigrations), Success rate: $($stats.SuccessRate)%"
```

## Report Examples

### HTML Report Components

The HTML report includes several visualization sections:

1. **Migration Summary**
   - Total migrations with success/failure counts
   - Success rate percentage
   - Migration timeline information

2. **Component Performance**
   - Bar chart showing success and failure counts by component
   - Table with detailed component metrics

3. **Error Analysis**
   - Pie chart showing error categories distribution
   - Table with detailed error counts and percentages

4. **Device Details** (optional)
   - Table with per-device migration status
   - Success rates and attempt counts by device

5. **Time Distribution**
   - Horizontal bar chart showing average time per migration phase
   - Table with detailed timing metrics

## Integration with Other Modules

The MigrationAnalytics module integrates with:

- **LoggingModule**: For comprehensive logging
- **RollbackMechanism**: For tracking rollback events
- **MigrationVerification**: For validation statistics
- **UserCommunicationFramework**: For feedback collection
- **SecurityFoundation**: For tracking security-related events

## Data Storage

Analytics data is stored in JSON format for easy processing and analysis:

- **Metrics File**: Contains all raw migration metrics
- **Reports**: Generated in specified formats (HTML, JSON, CSV)
- **Visualizations**: Charts and graphs embedded in HTML reports

All data is stored locally by default but can be configured to use a network share for centralized analytics in enterprise environments. 