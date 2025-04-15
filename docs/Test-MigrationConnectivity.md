# Test-MigrationConnectivity

## Overview
The `Test-MigrationConnectivity.ps1` script is a comprehensive testing tool designed to validate connectivity requirements for the Workspace ONE to Azure migration project. It checks prerequisites, connectivity, and authentication capabilities for both environments.

## Features
- Tests system requirements (PowerShell version, admin rights, required modules)
- Verifies connectivity to Workspace ONE endpoints
- Verifies connectivity to Azure endpoints
- Optional authentication testing for both platforms
- Generates detailed HTML reports with recommendations
- Color-coded status indicators for easy review

## Usage

### Basic Connectivity Testing
```powershell
.\Test-MigrationConnectivity.ps1
```

### With HTML Report Generation
```powershell
.\Test-MigrationConnectivity.ps1 -GenerateReport
```

### With Authentication Testing
```powershell
.\Test-MigrationConnectivity.ps1 -TestAuth -ConfigPath "path\to\config.json"
```

### With Custom Endpoints
```powershell
.\Test-MigrationConnectivity.ps1 -WorkspaceOneServer "https://yourapiserver.workspaceone.com" -AzureEndpoint "https://login.microsoftonline.com"
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| WorkspaceOneServer | String | Specifies the Workspace ONE API server URL |
| AzureEndpoint | String | Specifies the Azure service endpoint to test |
| TestAuth | Switch | Enables authentication testing |
| ConfigPath | String | Path to configuration file with auth credentials |
| GenerateReport | Switch | Generates an HTML report of test results |

## Configuration File Format
When using the `-TestAuth` parameter, create a JSON configuration file with the following structure:

```json
{
  "WorkspaceOne": {
    "Username": "admin",
    "Password": "secure_password"
  },
  "Azure": {
    "TenantId": "tenant-guid",
    "ClientId": "app-guid",
    "ClientSecret": "client-secret"
  }
}
```

## Output
The script provides:
1. Console output with color-coded status indicators
2. Optional HTML report with detailed test results
3. Specific recommendations for addressing any connectivity issues

## Example Report
The HTML report includes:
- Overall migration readiness status
- System requirements validation
- Workspace ONE connectivity tests
- Azure connectivity tests 
- Endpoint-specific connectivity results
- Recommendations for addressing any issues

## Integration
This tool is part of the Workspace ONE to Azure migration toolkit and can be used:
- During the pre-migration assessment phase
- To troubleshoot connectivity issues during migration
- As a validation tool in automated CI/CD pipelines

## Requirements
- PowerShell 5.1 or higher
- Administrator privileges (recommended)
- Network access to Workspace ONE and Azure environments
- Microsoft.Graph.Intune module (for advanced functionality)
- Az.Accounts module (for advanced functionality) 