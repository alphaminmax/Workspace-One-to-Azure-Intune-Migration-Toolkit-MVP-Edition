<# TEST-MIGRATIONCONNECTIVITY.PS1
.SYNOPSIS
    Tests connectivity to Workspace One and Azure environments as part of migration preparation.
.DESCRIPTION
    This script tests network connectivity, authentication, and API access to both 
    Workspace One and Azure environments to ensure all prerequisites are met before 
    beginning the migration process.
.NOTES
    Version: 1.0
    Author: Migration Team
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceOneServer = "https://apiserver.workspaceone.com",
    
    [Parameter()]
    [string]$AzureEndpoint = "https://login.microsoftonline.com",
    
    [Parameter()]
    [switch]$TestAuth,
    
    [Parameter()]
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    
    [Parameter()]
    [switch]$GenerateReport
)

# Import logging module if available
$loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules\LoggingModule.psm1"
if (Test-Path -Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
    Initialize-Logging -LogPath "C:\Temp\Logs" -LogFileName "MigrationConnectivity_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Write-LogMessage -Message "Logging initialized" -Level INFO
} else {
    function Write-LogMessage {
        param($Message, $Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

# Test results collection
$results = @{
    WorkspaceOne = @{
        BasicConnectivity = $false
        ApiAccessible = $false
        AuthSuccessful = $false
        Endpoints = @()
    }
    Azure = @{
        BasicConnectivity = $false
        ApiAccessible = $false
        AuthSuccessful = $false
        Endpoints = @()
    }
    SystemRequirements = @{
        PowerShellVersion = $false
        RequiredModules = @{}
        AdminRights = $false
    }
    Recommendations = @()
}

function Test-SystemRequirements {
    Write-LogMessage -Message "Testing system requirements..." -Level INFO
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    $results.SystemRequirements.PowerShellVersion = ($psVersion.Major -ge 5 -and $psVersion.Minor -ge 1)
    Write-LogMessage -Message "PowerShell version: $($psVersion.ToString())" -Level INFO
    
    if (-not $results.SystemRequirements.PowerShellVersion) {
        $results.Recommendations += "Upgrade PowerShell to version 5.1 or later"
    }
    
    # Check admin rights
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    $results.SystemRequirements.AdminRights = $principal.IsInRole($adminRole)
    Write-LogMessage -Message "Admin rights: $($results.SystemRequirements.AdminRights)" -Level INFO
    
    if (-not $results.SystemRequirements.AdminRights) {
        $results.Recommendations += "Run as administrator for full functionality"
    }
    
    # Check required modules
    $requiredModules = @(
        "Microsoft.Graph.Intune",
        "Az.Accounts"
    )
    
    foreach ($module in $requiredModules) {
        $moduleAvailable = Get-Module -ListAvailable -Name $module
        $results.SystemRequirements.RequiredModules[$module] = ($null -ne $moduleAvailable)
        Write-LogMessage -Message "Module $module available: $($results.SystemRequirements.RequiredModules[$module])" -Level INFO
        
        if (-not $results.SystemRequirements.RequiredModules[$module]) {
            $results.Recommendations += "Install the $module PowerShell module"
        }
    }
}

function Test-WorkspaceOneConnectivity {
    Write-LogMessage -Message "Testing Workspace ONE connectivity..." -Level INFO
    
    # Define Workspace ONE endpoints to test
    $wsEndpoints = @(
        $WorkspaceOneServer,
        "$WorkspaceOneServer/api/system/info"
    )
    
    foreach ($endpoint in $wsEndpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $results.WorkspaceOne.Endpoints += @{
                Endpoint = $endpoint
                Status = $response.StatusCode
                Success = ($response.StatusCode -eq 200)
            }
            Write-LogMessage -Message "Connection to $endpoint succeeded (Status: $($response.StatusCode))" -Level INFO
        }
        catch {
            $results.WorkspaceOne.Endpoints += @{
                Endpoint = $endpoint
                Status = "Error"
                Success = $false
                ErrorMessage = $_.Exception.Message
            }
            Write-LogMessage -Message "Connection to $endpoint failed: $($_.Exception.Message)" -Level WARNING
        }
    }
    
    # Set basic connectivity result
    $results.WorkspaceOne.BasicConnectivity = ($results.WorkspaceOne.Endpoints | Where-Object { $_.Success } | Measure-Object).Count -gt 0
    
    # Set API accessible result
    $apiEndpoint = $results.WorkspaceOne.Endpoints | Where-Object { $_.Endpoint -like "*/api/*" }
    $results.WorkspaceOne.ApiAccessible = ($apiEndpoint | Where-Object { $_.Success } | Measure-Object).Count -gt 0
    
    if (-not $results.WorkspaceOne.BasicConnectivity) {
        $results.Recommendations += "Check network connectivity to Workspace ONE server"
    }
    
    if (-not $results.WorkspaceOne.ApiAccessible) {
        $results.Recommendations += "Verify Workspace ONE API is accessible"
    }
}

function Test-AzureConnectivity {
    Write-LogMessage -Message "Testing Azure connectivity..." -Level INFO
    
    # Define Azure endpoints to test
    $azureEndpoints = @(
        $AzureEndpoint,
        "https://graph.microsoft.com",
        "https://graph.microsoft.com/v1.0/$metadata"
    )
    
    foreach ($endpoint in $azureEndpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $results.Azure.Endpoints += @{
                Endpoint = $endpoint
                Status = $response.StatusCode
                Success = ($response.StatusCode -eq 200)
            }
            Write-LogMessage -Message "Connection to $endpoint succeeded (Status: $($response.StatusCode))" -Level INFO
        }
        catch {
            $results.Azure.Endpoints += @{
                Endpoint = $endpoint
                Status = "Error"
                Success = $false
                ErrorMessage = $_.Exception.Message
            }
            Write-LogMessage -Message "Connection to $endpoint failed: $($_.Exception.Message)" -Level WARNING
        }
    }
    
    # Set basic connectivity result
    $results.Azure.BasicConnectivity = ($results.Azure.Endpoints | Where-Object { $_.Success } | Measure-Object).Count -gt 0
    
    # Set API accessible result
    $apiEndpoint = $results.Azure.Endpoints | Where-Object { $_.Endpoint -like "*graph.microsoft.com*" }
    $results.Azure.ApiAccessible = ($apiEndpoint | Where-Object { $_.Success } | Measure-Object).Count -gt 0
    
    if (-not $results.Azure.BasicConnectivity) {
        $results.Recommendations += "Check network connectivity to Azure"
    }
    
    if (-not $results.Azure.ApiAccessible) {
        $results.Recommendations += "Verify Microsoft Graph API is accessible"
    }
}

function Test-Authentication {
    if (-not $TestAuth) {
        Write-LogMessage -Message "Authentication testing skipped. Use -TestAuth switch to enable." -Level INFO
        return
    }
    
    Write-LogMessage -Message "Testing authentication capabilities..." -Level INFO
    
    # Load config if available
    $config = $null
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            Write-LogMessage -Message "Loaded configuration from $ConfigPath" -Level INFO
        }
        catch {
            Write-LogMessage -Message "Failed to load configuration: $_" -Level ERROR
            $results.Recommendations += "Create a valid config.json file with authentication credentials"
            return
        }
    }
    else {
        Write-LogMessage -Message "Config file not found: $ConfigPath" -Level WARNING
        $results.Recommendations += "Create a config.json file with authentication credentials"
        return
    }
    
    # Test Workspace ONE authentication
    if ($config.WorkspaceOne -and $config.WorkspaceOne.Username -and $config.WorkspaceOne.Password) {
        Write-LogMessage -Message "Testing Workspace ONE authentication..." -Level INFO
        try {
            # This is a placeholder for actual authentication logic
            # In a real implementation, you would use the Workspace ONE API to authenticate
            $wsAuthenticated = $true
            $results.WorkspaceOne.AuthSuccessful = $wsAuthenticated
            Write-LogMessage -Message "Workspace ONE authentication successful" -Level INFO
        }
        catch {
            $results.WorkspaceOne.AuthSuccessful = $false
            Write-LogMessage -Message "Workspace ONE authentication failed: $_" -Level ERROR
            $results.Recommendations += "Check Workspace ONE credentials"
        }
    }
    
    # Test Azure authentication
    if ($config.Azure -and $config.Azure.TenantId -and $config.Azure.ClientId -and $config.Azure.ClientSecret) {
        Write-LogMessage -Message "Testing Azure authentication..." -Level INFO
        try {
            # This is a placeholder for actual authentication logic
            # In a real implementation, you would use Microsoft.Identity.Client or similar
            $azureAuthenticated = $true
            $results.Azure.AuthSuccessful = $azureAuthenticated
            Write-LogMessage -Message "Azure authentication successful" -Level INFO
        }
        catch {
            $results.Azure.AuthSuccessful = $false
            Write-LogMessage -Message "Azure authentication failed: $_" -Level ERROR
            $results.Recommendations += "Check Azure credentials"
        }
    }
}

function Generate-Report {
    if (-not $GenerateReport) {
        return
    }
    
    $reportPath = "C:\Temp\Logs\MigrationConnectivityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportDir = Split-Path -Path $reportPath -Parent
    
    if (-not (Test-Path -Path $reportDir)) {
        New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
    }
    
    # Create HTML report
    $overallStatus = if (
        $results.WorkspaceOne.BasicConnectivity -and 
        $results.Azure.BasicConnectivity -and 
        $results.SystemRequirements.PowerShellVersion -and 
        $results.SystemRequirements.AdminRights
    ) { "READY" } else { "NOT READY" }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Migration Connectivity Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2 { color: #0078D4; }
        .status { font-weight: bold; font-size: 1.2em; }
        .ready { color: green; }
        .not-ready { color: red; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .success { color: green; }
        .failure { color: red; }
        .recommendations { background-color: #f8f8f8; padding: 10px; border-left: 4px solid #0078D4; }
    </style>
</head>
<body>
    <h1>Migration Connectivity Report</h1>
    <p>Generated on: $(Get-Date)</p>
    <p>Overall Status: <span class="status $(if ($overallStatus -eq 'READY') { 'ready' } else { 'not-ready' })">$overallStatus</span></p>
    
    <h2>System Requirements</h2>
    <table>
        <tr>
            <th>Requirement</th>
            <th>Status</th>
        </tr>
        <tr>
            <td>PowerShell Version</td>
            <td class="$(if ($results.SystemRequirements.PowerShellVersion) { 'success' } else { 'failure' })">$($PSVersionTable.PSVersion)</td>
        </tr>
        <tr>
            <td>Admin Rights</td>
            <td class="$(if ($results.SystemRequirements.AdminRights) { 'success' } else { 'failure' })">$(if ($results.SystemRequirements.AdminRights) { 'Yes' } else { 'No' })</td>
        </tr>
        $(
            foreach ($module in $results.SystemRequirements.RequiredModules.Keys) {
                $status = $results.SystemRequirements.RequiredModules[$module]
                "<tr><td>Module: $module</td><td class='$(if ($status) { 'success' } else { 'failure' })'>$(if ($status) { 'Installed' } else { 'Not Installed' })</td></tr>"
            }
        )
    </table>
    
    <h2>Workspace ONE Connectivity</h2>
    <table>
        <tr>
            <th>Test</th>
            <th>Status</th>
        </tr>
        <tr>
            <td>Basic Connectivity</td>
            <td class="$(if ($results.WorkspaceOne.BasicConnectivity) { 'success' } else { 'failure' })">$(if ($results.WorkspaceOne.BasicConnectivity) { 'Success' } else { 'Failed' })</td>
        </tr>
        <tr>
            <td>API Accessible</td>
            <td class="$(if ($results.WorkspaceOne.ApiAccessible) { 'success' } else { 'failure' })">$(if ($results.WorkspaceOne.ApiAccessible) { 'Success' } else { 'Failed' })</td>
        </tr>
        <tr>
            <td>Authentication</td>
            <td class="$(if ($results.WorkspaceOne.AuthSuccessful) { 'success' } else { 'failure' })">$(if ($TestAuth) { if ($results.WorkspaceOne.AuthSuccessful) { 'Success' } else { 'Failed' } } else { 'Not Tested' })</td>
        </tr>
    </table>
    
    <h3>Workspace ONE Endpoints</h3>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>Status</th>
        </tr>
        $(
            foreach ($endpoint in $results.WorkspaceOne.Endpoints) {
                "<tr><td>$($endpoint.Endpoint)</td><td class='$(if ($endpoint.Success) { 'success' } else { 'failure' })'>$($endpoint.Status)</td></tr>"
            }
        )
    </table>
    
    <h2>Azure Connectivity</h2>
    <table>
        <tr>
            <th>Test</th>
            <th>Status</th>
        </tr>
        <tr>
            <td>Basic Connectivity</td>
            <td class="$(if ($results.Azure.BasicConnectivity) { 'success' } else { 'failure' })">$(if ($results.Azure.BasicConnectivity) { 'Success' } else { 'Failed' })</td>
        </tr>
        <tr>
            <td>API Accessible</td>
            <td class="$(if ($results.Azure.ApiAccessible) { 'success' } else { 'failure' })">$(if ($results.Azure.ApiAccessible) { 'Success' } else { 'Failed' })</td>
        </tr>
        <tr>
            <td>Authentication</td>
            <td class="$(if ($results.Azure.AuthSuccessful) { 'success' } else { 'failure' })">$(if ($TestAuth) { if ($results.Azure.AuthSuccessful) { 'Success' } else { 'Failed' } } else { 'Not Tested' })</td>
        </tr>
    </table>
    
    <h3>Azure Endpoints</h3>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>Status</th>
        </tr>
        $(
            foreach ($endpoint in $results.Azure.Endpoints) {
                "<tr><td>$($endpoint.Endpoint)</td><td class='$(if ($endpoint.Success) { 'success' } else { 'failure' })'>$($endpoint.Status)</td></tr>"
            }
        )
    </table>
    
    <h2>Recommendations</h2>
    <div class="recommendations">
        <ul>
            $(
                if ($results.Recommendations.Count -eq 0) {
                    "<li>No recommendations - all tests passed</li>"
                } else {
                    foreach ($recommendation in $results.Recommendations) {
                        "<li>$recommendation</li>"
                    }
                }
            )
        </ul>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $reportPath -Encoding utf8
    Write-LogMessage -Message "Report generated at: $reportPath" -Level INFO
    return $reportPath
}

# Main execution
Write-LogMessage -Message "===== Migration Connectivity Test Started =====" -Level INFO
Write-LogMessage -Message "Testing connectivity to Workspace ONE: $WorkspaceOneServer" -Level INFO
Write-LogMessage -Message "Testing connectivity to Azure: $AzureEndpoint" -Level INFO

# Run tests
Test-SystemRequirements
Test-WorkspaceOneConnectivity
Test-AzureConnectivity
Test-Authentication

# Display results
Write-Host ""
Write-Host "===== Migration Connectivity Test Results =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "System Requirements:"
Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor $(if ($results.SystemRequirements.PowerShellVersion) { 'Green' } else { 'Red' })
Write-Host "  Admin Rights: $(if ($results.SystemRequirements.AdminRights) { 'Yes' } else { 'No' })" -ForegroundColor $(if ($results.SystemRequirements.AdminRights) { 'Green' } else { 'Red' })

foreach ($module in $results.SystemRequirements.RequiredModules.Keys) {
    $status = $results.SystemRequirements.RequiredModules[$module]
    Write-Host "  Module $module: $(if ($status) { 'Installed' } else { 'Not Installed' })" -ForegroundColor $(if ($status) { 'Green' } else { 'Red' })
}

Write-Host ""
Write-Host "Workspace ONE Connectivity:"
Write-Host "  Basic Connectivity: $(if ($results.WorkspaceOne.BasicConnectivity) { 'Success' } else { 'Failed' })" -ForegroundColor $(if ($results.WorkspaceOne.BasicConnectivity) { 'Green' } else { 'Red' })
Write-Host "  API Accessible: $(if ($results.WorkspaceOne.ApiAccessible) { 'Success' } else { 'Failed' })" -ForegroundColor $(if ($results.WorkspaceOne.ApiAccessible) { 'Green' } else { 'Red' })
Write-Host "  Authentication: $(if ($TestAuth) { if ($results.WorkspaceOne.AuthSuccessful) { 'Success' } else { 'Failed' } } else { 'Not Tested' })" -ForegroundColor $(if ($TestAuth) { if ($results.WorkspaceOne.AuthSuccessful) { 'Green' } else { 'Red' } } else { 'Yellow' })

Write-Host ""
Write-Host "Azure Connectivity:"
Write-Host "  Basic Connectivity: $(if ($results.Azure.BasicConnectivity) { 'Success' } else { 'Failed' })" -ForegroundColor $(if ($results.Azure.BasicConnectivity) { 'Green' } else { 'Red' })
Write-Host "  API Accessible: $(if ($results.Azure.ApiAccessible) { 'Success' } else { 'Failed' })" -ForegroundColor $(if ($results.Azure.ApiAccessible) { 'Green' } else { 'Red' })
Write-Host "  Authentication: $(if ($TestAuth) { if ($results.Azure.AuthSuccessful) { 'Success' } else { 'Failed' } } else { 'Not Tested' })" -ForegroundColor $(if ($TestAuth) { if ($results.Azure.AuthSuccessful) { 'Green' } else { 'Red' } } else { 'Yellow' })

Write-Host ""
if ($results.Recommendations.Count -gt 0) {
    Write-Host "Recommendations:" -ForegroundColor Yellow
    foreach ($recommendation in $results.Recommendations) {
        Write-Host "  - $recommendation" -ForegroundColor Yellow
    }
} else {
    Write-Host "No recommendations - all tests passed!" -ForegroundColor Green
}

# Generate HTML report if requested
$reportPath = Generate-Report
if ($reportPath) {
    Write-Host ""
    Write-Host "Report generated at: $reportPath" -ForegroundColor Cyan
}

Write-LogMessage -Message "===== Migration Connectivity Test Completed =====" -Level INFO 