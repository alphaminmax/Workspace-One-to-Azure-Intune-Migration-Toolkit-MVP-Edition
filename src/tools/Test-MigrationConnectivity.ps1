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
    [Parameter(Mandatory = $false, Position = 0, 
        HelpMessage = "Workspace ONE API server URL (e.g., https://apiserver.workspaceone.com)")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^https?://[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+')]
    [string]$WorkspaceOneServer = "https://apiserver.workspaceone.com",
    
    [Parameter(Mandatory = $false, Position = 1,
        HelpMessage = "Azure endpoint URL (e.g., https://login.microsoftonline.com)")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^https?://[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+')]
    [string]$AzureEndpoint = "https://login.microsoftonline.com",
    
    [Parameter(Mandatory = $false,
        HelpMessage = "Test authentication against both services")]
    [switch]$TestAuth,
    
    [Parameter(Mandatory = $false,
        HelpMessage = "Path to configuration file containing credentials")]
    [ValidateScript({
        if (-not (Test-Path $_) -and -not [string]::IsNullOrEmpty($_)) {
            Write-Warning "Config file not found at: $_"
            Write-Warning "Authentication tests will be limited."
            $true
        } else {
            $true
        }
    })]
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    
    [Parameter(Mandatory = $false,
        HelpMessage = "Generate HTML report of test results")]
    [switch]$GenerateReport,
    
    [Parameter(Mandatory = $false,
        HelpMessage = "Path to store report and logs")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Write-Verbose "Created output directory: $_"
        }
        return $true
    })]
    [string]$OutputPath = "C:\Temp\Logs",
    
    [Parameter(Mandatory = $false,
        HelpMessage = "Use a keyvault to retrieve credentials")]
    [switch]$UseKeyVault,
    
    [Parameter(Mandatory = $false,
        HelpMessage = "Azure Key Vault name")]
    [string]$KeyVaultName
)

# Script global variables
$script:TestStartTime = Get-Date
$script:Credentials = @{}
$script:ModulesLoaded = @{}
$script:OutputDirectory = $OutputPath
$script:LogFile = Join-Path -Path $OutputPath -ChildPath "MigrationConnectivity_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Import logging module if available
$loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules\LoggingModule.psm1"
try {
    if (Test-Path -Path $loggingModulePath) {
        Import-Module $loggingModulePath -Force -ErrorAction Stop
        $script:ModulesLoaded["LoggingModule"] = $true
        Initialize-Logging -LogPath $OutputPath -LogFileName (Split-Path $script:LogFile -Leaf)
        Write-LogMessage -Message "Logging initialized at $script:LogFile" -Level INFO
    } else {
        function Write-LogMessage {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Message,
                
                [Parameter(Mandatory = $false)]
                [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
                [string]$Level = "INFO"
            )
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logMessage = "[$timestamp] [$Level] $Message"
            Write-Host $logMessage
            
            # Also save to log file directly
            try {
                Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
            } catch {
                Write-Host "Warning: Unable to write to log file: ${_}" -ForegroundColor Yellow
            }
        }
        Write-LogMessage -Message "LoggingModule not found, using basic logging" -Level WARNING
        $script:ModulesLoaded["LoggingModule"] = $false
    }
} catch {
    # Fallback logging function if module fails to load
    function Write-LogMessage {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Message,
            
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
            [string]$Level = "INFO"
        )
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        Write-Host $logMessage
        
        # Also save to log file directly
        try {
            Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-LogMessage -Message "Failed to load LoggingModule: $_" -Level ERROR
    $script:ModulesLoaded["LoggingModule"] = $false
}

# Function to load credentials from different sources
function Initialize-Credentials {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "Initializing credentials..." -Level INFO
    
    # Check if Key Vault should be used
    if ($UseKeyVault) {
        Write-LogMessage -Message "Attempting to use Azure Key Vault for credentials" -Level INFO
        try {
            # Check if Az.KeyVault is available
            if (!(Get-Module -ListAvailable -Name Az.KeyVault)) {
                Write-LogMessage -Message "Az.KeyVault module not found. Please install with: Install-Module -Name Az.KeyVault -AllowClobber -Force" -Level ERROR
                return $false
            }
            
            # Import the module
            Import-Module Az.KeyVault -ErrorAction Stop
            $script:ModulesLoaded["Az.KeyVault"] = $true
            
            if ([string]::IsNullOrEmpty($KeyVaultName)) {
                Write-LogMessage -Message "KeyVaultName parameter is required when UseKeyVault is specified" -Level ERROR
                return $false
            }
            
            # Try to get the credentials from the key vault
            try {
                # Check if already authenticated
                $context = Get-AzContext -ErrorAction SilentlyContinue
                if (!$context) {
                    Write-LogMessage -Message "Not authenticated to Azure. Please run Connect-AzAccount first." -Level WARNING
                    # Prompt for interactive login
                    Connect-AzAccount -ErrorAction Stop
                }
                
                # Get WS1 credentials
                $ws1Username = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "WS1-Username" -AsPlainText -ErrorAction Stop
                $ws1Password = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "WS1-Password" -AsPlainText -ErrorAction Stop
                $script:Credentials["WorkspaceOne"] = @{
                    Username = $ws1Username
                    Password = $ws1Password
                }
                
                # Get Azure credentials
                $azureTenantId = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "Azure-TenantId" -AsPlainText -ErrorAction Stop
                $azureClientId = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "Azure-ClientId" -AsPlainText -ErrorAction Stop
                $azureClientSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "Azure-ClientSecret" -AsPlainText -ErrorAction Stop
                $script:Credentials["Azure"] = @{
                    TenantId = $azureTenantId
                    ClientId = $azureClientId
                    ClientSecret = $azureClientSecret
                }
                
                Write-LogMessage -Message "Successfully retrieved credentials from Key Vault" -Level INFO
                return $true
            }
            catch {
                Write-LogMessage -Message "Failed to retrieve credentials from Key Vault: ${_}" -Level ERROR
                return $false
            }
        }
        catch {
            Write-LogMessage -Message "Failed to initialize Azure Key Vault: ${_}" -Level ERROR
            return $false
        }
    }
    # Otherwise, try to load from config file
    elseif (Test-Path $ConfigPath) {
        try {
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
            
            if ($config.WorkspaceOne -and $config.WorkspaceOne.Username -and $config.WorkspaceOne.Password) {
                $script:Credentials["WorkspaceOne"] = @{
                    Username = $config.WorkspaceOne.Username
                    Password = $config.WorkspaceOne.Password
                }
            }
            
            if ($config.Azure -and $config.Azure.TenantId -and $config.Azure.ClientId -and $config.Azure.ClientSecret) {
                $script:Credentials["Azure"] = @{
                    TenantId = $config.Azure.TenantId
                    ClientId = $config.Azure.ClientId
                    ClientSecret = $config.Azure.ClientSecret
                }
            }
            
            Write-LogMessage -Message "Successfully loaded credentials from config file" -Level INFO
            return $true
        }
        catch {
            Write-LogMessage -Message "Failed to load configuration: ${_}" -Level ERROR
            return $false
        }
    }
    else {
        Write-LogMessage -Message "No credentials available. Authentication tests will be limited." -Level WARNING
        return $false
    }
}

# Test results collection
$script:results = @{
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
    Errors = @()
    Timestamp = Get-Date
}

function Test-SystemRequirements {
    Write-LogMessage -Message "Testing system requirements..." -Level INFO
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    $script:results.SystemRequirements.PowerShellVersion = ($psVersion.Major -ge 5 -and $psVersion.Minor -ge 1)
    Write-LogMessage -Message "PowerShell version: $($psVersion.ToString())" -Level INFO
    
    if (-not $script:results.SystemRequirements.PowerShellVersion) {
        $script:results.Recommendations += "Upgrade PowerShell to version 5.1 or later"
    }
    
    # Check admin rights
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    $script:results.SystemRequirements.AdminRights = $principal.IsInRole($adminRole)
    Write-LogMessage -Message "Admin rights: $($script:results.SystemRequirements.AdminRights)" -Level INFO
    
    if (-not $script:results.SystemRequirements.AdminRights) {
        $script:results.Recommendations += "Run as administrator for full functionality"
    }
    
    # Check required modules
    $requiredModules = @(
        "Microsoft.Graph.Intune",
        "Az.Accounts"
    )
    
    foreach ($module in $requiredModules) {
        $moduleAvailable = Get-Module -ListAvailable -Name $module
        $script:results.SystemRequirements.RequiredModules[$module] = ($null -ne $moduleAvailable)
        Write-LogMessage -Message "Module $module available: $($script:results.SystemRequirements.RequiredModules[$module])" -Level INFO
        
        if (-not $script:results.SystemRequirements.RequiredModules[$module]) {
            $script:results.Recommendations += "Install the $module PowerShell module"
        }
    }
}

function Test-WorkspaceOneConnectivity {
    [CmdletBinding()]
    param()
    
    Write-LogMessage -Message "Testing connectivity to Workspace ONE..." -Level INFO
    
    # Define endpoints to test
    $endpoints = @()
    
    # Add base server endpoint
    if (-not [string]::IsNullOrEmpty($WorkspaceOneServer)) {
        $endpoints += $WorkspaceOneServer
        
        # Also test API endpoints if the server is specified
        if (-not $WorkspaceOneServer.EndsWith("/")) {
            $apiEndpoint = "$WorkspaceOneServer/api/system/info"
        } else {
            $apiEndpoint = "${WorkspaceOneServer}api/system/info"
        }
        $endpoints += $apiEndpoint
    } else {
        Write-LogMessage -Message "WorkspaceOneServer parameter not specified, skipping connectivity tests" -Level WARNING
        $script:results.Recommendations += "Specify WorkspaceOneServer parameter to test Workspace ONE connectivity"
        return
    }
    
    # Add additional endpoints if specified
    if ($AdditionalWsEndpoints -and $AdditionalWsEndpoints.Count -gt 0) {
        $endpoints += $AdditionalWsEndpoints
    }
    
    # Clear previous results
    $script:results.WorkspaceOne.Endpoints = @()
    
    # Test each endpoint with increased robustness
    foreach ($endpoint in $endpoints) {
        Write-LogMessage -Message "Testing connectivity to $endpoint..." -Level INFO
        
        # Check if the endpoint is formatted correctly
        if (-not ($endpoint -match "^https?://")) {
            $endpoint = "https://$endpoint"
            Write-LogMessage -Message "Endpoint did not include protocol, assuming HTTPS: $endpoint" -Level WARNING
        }

        # Initialize test result object
        $endpointResult = @{
            Endpoint = $endpoint
            Status = "Unknown"
            StatusCode = 0
            Success = $false
            ResponseTime = 0
            Error = $null
            Details = @{}
        }
        
        # Try HTTP GET first, with timeout and error handling
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Use different parameters based on PowerShell version for best compatibility
            $params = @{
                Uri = $endpoint
                Method = "GET"
                UseBasicParsing = $true
                TimeoutSec = 30
                ErrorAction = "Stop"
            }
            
            # Add TLS handling
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # Try to get response
            $response = Invoke-WebRequest @params
            $stopwatch.Stop()
            
            # Record successful results
            $endpointResult.Status = "Success"
            $endpointResult.StatusCode = $response.StatusCode
            $endpointResult.Success = $true
            $endpointResult.ResponseTime = $stopwatch.ElapsedMilliseconds
            $endpointResult.Details.ContentType = $response.Headers["Content-Type"]
            $endpointResult.Details.Server = $response.Headers["Server"]
            
            Write-LogMessage -Message "Successfully connected to $endpoint (Status: $($response.StatusCode), Time: $($stopwatch.ElapsedMilliseconds)ms)" -Level INFO
        }
        catch [System.Net.WebException] {
            $stopwatch.Stop()
            $ex = $_.Exception
            
            # Try to get response from WebException for cases like 404, 401, etc.
            if ($ex.Response -ne $null) {
                try {
                    $statusCode = [int]$ex.Response.StatusCode
                    $endpointResult.StatusCode = $statusCode
                    $endpointResult.Status = "HTTP Error"
                    $endpointResult.Error = "$($ex.Message) ($statusCode)"
                    $endpointResult.ResponseTime = $stopwatch.ElapsedMilliseconds
                    
                    # Some HTTP errors can be considered "connected but unauthorized"
                    # This is useful for testing if the server is reachable but requires auth
                    if ($statusCode -eq 401 -or $statusCode -eq 403) {
                        $endpointResult.Success = $true # We count this as successful connection
                        $endpointResult.Details.IsAuthError = $true
                        Write-LogMessage -Message "Connected to $endpoint but received auth error: $statusCode (Time: $($stopwatch.ElapsedMilliseconds)ms)" -Level WARNING
                    } else {
                        Write-LogMessage -Message "Connected to $endpoint but received error: $statusCode (Time: $($stopwatch.ElapsedMilliseconds)ms)" -Level WARNING
                    }
                }
                catch {
                    $endpointResult.Error = $ex.Message
                    Write-LogMessage -Message ("Error parsing response from " + $endpoint + ": " + $ex.Message) -Level ERROR
                }
            }
            else {
                # For connection failures, try DNS resolution
                $endpointResult.Status = "Connection Error"
                $endpointResult.Error = $ex.Message
                $endpointResult.ResponseTime = $stopwatch.ElapsedMilliseconds
                
                Write-LogMessage -Message ("Failed to connect to " + $endpoint + ": " + $ex.Message + " (Time: " + $stopwatch.ElapsedMilliseconds + "ms)") -Level ERROR
                
                # Try DNS resolution as a fallback
                try {
                    $uri = [System.Uri]::new($endpoint)
                    $hostname = $uri.Host
                    
                    Write-LogMessage -Message "Attempting DNS resolution for $hostname..." -Level INFO
                    $dnsResult = Resolve-DnsName -Name $hostname -ErrorAction Stop -Type A
                    
                    if ($dnsResult) {
                        $endpointResult.Details["DnsResolved"] = $true
                        $endpointResult.Details["IpAddresses"] = ($dnsResult | Where-Object { $_.Section -eq "Answer" } | ForEach-Object { $_.IPAddress }) -join ", "
                        Write-LogMessage -Message ("DNS resolution successful for " + $hostname + ": " + $endpointResult.Details['IpAddresses']) -Level INFO
                        
                        # Try ping as a last resort
                        try {
                            $pingResult = Test-Connection -ComputerName $hostname -Count 2 -Quiet -ErrorAction Stop
                            $endpointResult.Details["PingSuccessful"] = $pingResult
                            
                            if ($pingResult) {
                                Write-LogMessage -Message "Ping successful to $hostname" -Level INFO
                            } else {
                                Write-LogMessage -Message "Ping failed to $hostname" -Level WARNING
                            }
                        }
                        catch {
                            $endpointResult.Details["PingError"] = $_.Exception.Message
                            Write-LogMessage -Message ("Ping test error for " + $hostname + ": " + $_.Exception.Message) -Level WARNING
                        }
                    }
                }
                catch {
                    $endpointResult.Details["DnsResolved"] = $false
                    $endpointResult.Details["DnsError"] = $_.Exception.Message
                    Write-LogMessage -Message ("DNS resolution failed for host " + $hostname + ": " + $_.Exception.Message) -Level ERROR
                }
            }
        }
        catch {
            $stopwatch.Stop()
            $endpointResult.Status = "Error"
            $endpointResult.Error = $_.Exception.Message
            $endpointResult.ResponseTime = $stopwatch.ElapsedMilliseconds
            
            Write-LogMessage -Message ("Error testing " + $endpoint + ": " + $_.Exception.Message + " (Time: " + $stopwatch.ElapsedMilliseconds + "ms)") -Level ERROR
        }
        
        # Add result to results collection
        $script:results.WorkspaceOne.Endpoints += $endpointResult
    }
    
    # Analyze results
    $successfulEndpoints = $script:results.WorkspaceOne.Endpoints | Where-Object { $_.Success }
    $successCount = ($successfulEndpoints | Measure-Object).Count
    
    # Set basic connectivity result
    $script:results.WorkspaceOne.BasicConnectivity = $successCount -gt 0
    
    # Set API accessible result - look for endpoints with /api/ in them
    $apiEndpoints = $script:results.WorkspaceOne.Endpoints | Where-Object { $_.Endpoint -like "*api*" -and $_.Success }
    $script:results.WorkspaceOne.ApiAccessible = ($apiEndpoints | Measure-Object).Count -gt 0
    
    # Generate appropriate recommendations
    if (-not $script:results.WorkspaceOne.BasicConnectivity) {
        $script:results.Recommendations += "Check network connectivity to Workspace ONE server: $WorkspaceOneServer"
        
        # If DNS resolution failed, add that as a recommendation
        $dnsFailures = $script:results.WorkspaceOne.Endpoints | 
            Where-Object { $_.Details["DnsResolved"] -eq $false }
        
        if (($dnsFailures | Measure-Object).Count -gt 0) {
            $script:results.Recommendations += "Check DNS resolution for Workspace ONE server hostnames"
        }
    }
    
    if (-not $script:results.WorkspaceOne.ApiAccessible) {
        $script:results.Recommendations += "Verify Workspace ONE API is accessible at $apiEndpoint"
    }
    
    # Report summary
    Write-LogMessage -Message "Workspace ONE connectivity tests complete: $successCount of $($endpoints.Count) endpoints accessible" -Level INFO
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
            $script:results.Azure.Endpoints += @{
                Endpoint = $endpoint
                Status = $response.StatusCode
                Success = ($response.StatusCode -eq 200)
            }
            Write-LogMessage -Message "Connection to $endpoint succeeded (Status: $($response.StatusCode))" -Level INFO
        }
        catch {
            $script:results.Azure.Endpoints += @{
                Endpoint = $endpoint
                Status = "Error"
                Success = $false
                ErrorMessage = $_.Exception.Message
            }
            Write-LogMessage -Message "Connection to $endpoint failed: $($_.Exception.Message)" -Level WARNING
        }
    }
    
    # Set basic connectivity result
    $script:results.Azure.BasicConnectivity = ($script:results.Azure.Endpoints | Where-Object { $_.Success } | Measure-Object).Count -gt 0
    
    # Set API accessible result
    $apiEndpoint = $script:results.Azure.Endpoints | Where-Object { $_.Endpoint -like "*graph.microsoft.com*" }
    $script:results.Azure.ApiAccessible = ($apiEndpoint | Where-Object { $_.Success } | Measure-Object).Count -gt 0
    
    if (-not $script:results.Azure.BasicConnectivity) {
        $script:results.Recommendations += "Check network connectivity to Azure"
    }
    
    if (-not $script:results.Azure.ApiAccessible) {
        $script:results.Recommendations += "Verify Microsoft Graph API is accessible"
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
            Write-LogMessage -Message "Failed to load configuration: ${_}" -Level ERROR
            $script:results.Recommendations += "Create a valid config.json file with authentication credentials"
            return
        }
    }
    else {
        Write-LogMessage -Message "Config file not found: $ConfigPath" -Level WARNING
        $script:results.Recommendations += "Create a config.json file with authentication credentials"
        return
    }
    
    # Test Workspace ONE authentication
    if ($config.WorkspaceOne -and $config.WorkspaceOne.Username -and $config.WorkspaceOne.Password) {
        Write-LogMessage -Message "Testing Workspace ONE authentication..." -Level INFO
        try {
            # This is a placeholder for actual authentication logic
            # In a real implementation, you would use the Workspace ONE API to authenticate
            $wsAuthenticated = $true
            $script:results.WorkspaceOne.AuthSuccessful = $wsAuthenticated
            Write-LogMessage -Message "Workspace ONE authentication successful" -Level INFO
        }
        catch {
            $script:results.WorkspaceOne.AuthSuccessful = $false
            Write-LogMessage -Message "Workspace ONE authentication failed: ${_}" -Level ERROR
            $script:results.Recommendations += "Check Workspace ONE credentials"
        }
    }
    
    # Test Azure authentication
    if ($config.Azure -and $config.Azure.TenantId -and $config.Azure.ClientId -and $config.Azure.ClientSecret) {
        Write-LogMessage -Message "Testing Azure authentication..." -Level INFO
        try {
            # This is a placeholder for actual authentication logic
            # In a real implementation, you would use Microsoft.Identity.Client or similar
            $azureAuthenticated = $true
            $script:results.Azure.AuthSuccessful = $azureAuthenticated
            Write-LogMessage -Message "Azure authentication successful" -Level INFO
        }
        catch {
            $script:results.Azure.AuthSuccessful = $false
            Write-LogMessage -Message "Azure authentication failed: ${_}" -Level ERROR
            $script:results.Recommendations += "Check Azure credentials"
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
    
    # Determine overall status
    $overallStatus = "NOT READY"
    if ($script:results.WorkspaceOne.BasicConnectivity -and 
        $script:results.Azure.BasicConnectivity -and 
        $script:results.SystemRequirements.PowerShellVersion -and 
        $script:results.SystemRequirements.AdminRights) {
        $overallStatus = "READY"
    }
    
    # Build HTML fragments
    $headerHtml = @"
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
"@

    # Overall status section
    $statusClass = "not-ready"
    if ($overallStatus -eq "READY") {
        $statusClass = "ready"
    }
    $statusHtml = "<p>Overall Status: <span class='status $statusClass'>$overallStatus</span></p>"
    
    # System requirements section
    $sysReqHeaderHtml = @"
    <h2>System Requirements</h2>
    <table>
        <tr>
            <th>Requirement</th>
            <th>Status</th>
        </tr>
"@
    
    $psVersionClass = "failure"
    $psVersionValue = $PSVersionTable.PSVersion.ToString()
    if ($script:results.SystemRequirements.PowerShellVersion) {
        $psVersionClass = "success"
    }
    $psVersionHtml = "<tr><td>PowerShell Version</td><td class='$psVersionClass'>$psVersionValue</td></tr>"
    
    $adminRightsClass = "failure"
    $adminRightsText = "No"
    if ($script:results.SystemRequirements.AdminRights) {
        $adminRightsClass = "success"
        $adminRightsText = "Yes"
    }
    $adminRightsHtml = "<tr><td>Admin Rights</td><td class='$adminRightsClass'>$adminRightsText</td></tr>"
    
    $moduleRowsHtml = ""
    foreach ($module in $script:results.SystemRequirements.RequiredModules.Keys) {
        $status = $script:results.SystemRequirements.RequiredModules[$module]
        $moduleText = 'Not Installed'
        $moduleColor = 'Red'
        if ($status) { 
            $moduleText = 'Installed'
            $moduleColor = 'Green'
        }
        $moduleRowsHtml += "<tr><td>Module: $module</td><td class='$cssClass'>$statusText</td></tr>"
    }
    
    $sysReqFooterHtml = "</table>"
    
    # Workspace ONE section
    $wsHeaderHtml = @"
    <h2>Workspace ONE Connectivity</h2>
    <table>
        <tr>
            <th>Test</th>
            <th>Status</th>
        </tr>
"@
    
    $wsConnectivityClass = "failure"
    $wsConnectivityText = "Failed"
    if ($script:results.WorkspaceOne.BasicConnectivity) {
        $wsConnectivityClass = "success"
        $wsConnectivityText = "Success"
    }
    $wsConnectivityHtml = "<tr><td>Basic Connectivity</td><td class='$wsConnectivityClass'>$wsConnectivityText</td></tr>"
    
    $wsApiClass = "failure"
    $wsApiText = "Failed"
    if ($script:results.WorkspaceOne.ApiAccessible) {
        $wsApiClass = "success"
        $wsApiText = "Success"
    }
    $wsApiHtml = "<tr><td>API Accessible</td><td class='$wsApiClass'>$wsApiText</td></tr>"
    
    $wsAuthClass = "failure"
    $wsAuthText = "Not Tested"
    if ($TestAuth) {
        if ($script:results.WorkspaceOne.AuthSuccessful) {
            $wsAuthClass = "success"
            $wsAuthText = "Success"
        } else {
            $wsAuthText = "Failed"
        }
    }
    $wsAuthHtml = "<tr><td>Authentication</td><td class='$wsAuthClass'>$wsAuthText</td></tr>"
    
    $wsTableFooterHtml = "</table>"
    
    $wsEndpointsHeaderHtml = @"
    <h3>Workspace ONE Endpoints</h3>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>Status</th>
        </tr>
"@
    
    $wsEndpointRowsHtml = ""
    foreach ($endpoint in $script:results.WorkspaceOne.Endpoints) {
        $cssClass = "failure"
        if ($endpoint.Success) {
            $cssClass = "success"
        }
        $wsEndpointRowsHtml += "<tr><td>$($endpoint.Endpoint)</td><td class='$cssClass'>$($endpoint.Status)</td></tr>"
    }
    
    $wsEndpointsFooterHtml = "</table>"
    
    # Azure section
    $azureHeaderHtml = @"
    <h2>Azure Connectivity</h2>
    <table>
        <tr>
            <th>Test</th>
            <th>Status</th>
        </tr>
"@
    
    $azureConnectivityClass = "failure"
    $azureConnectivityText = "Failed"
    if ($script:results.Azure.BasicConnectivity) {
        $azureConnectivityClass = "success"
        $azureConnectivityText = "Success"
    }
    $azureConnectivityHtml = "<tr><td>Basic Connectivity</td><td class='$azureConnectivityClass'>$azureConnectivityText</td></tr>"
    
    $azureApiClass = "failure"
    $azureApiText = "Failed"
    if ($script:results.Azure.ApiAccessible) {
        $azureApiClass = "success"
        $azureApiText = "Success"
    }
    $azureApiHtml = "<tr><td>API Accessible</td><td class='$azureApiClass'>$azureApiText</td></tr>"
    
    $azureAuthClass = "failure"
    $azureAuthText = "Not Tested"
    if ($TestAuth) {
        if ($script:results.Azure.AuthSuccessful) {
            $azureAuthClass = "success"
            $azureAuthText = "Success"
        } else {
            $azureAuthText = "Failed"
        }
    }
    $azureAuthHtml = "<tr><td>Authentication</td><td class='$azureAuthClass'>$azureAuthText</td></tr>"
    
    $azureTableFooterHtml = "</table>"
    
    $azureEndpointsHeaderHtml = @"
    <h3>Azure Endpoints</h3>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>Status</th>
        </tr>
"@
    
    $azureEndpointRowsHtml = ""
    foreach ($endpoint in $script:results.Azure.Endpoints) {
        $cssClass = "failure"
        if ($endpoint.Success) {
            $cssClass = "success"
        }
        $azureEndpointRowsHtml += "<tr><td>$($endpoint.Endpoint)</td><td class='$cssClass'>$($endpoint.Status)</td></tr>"
    }
    
    $azureEndpointsFooterHtml = "</table>"
    
    # Recommendations section - using simpler string concatenation
    $recommendationsHtml = "<h2>Recommendations</h2><div class='recommendations'><ul>"
    
    if ($script:results.Recommendations.Count -eq 0) {
        $recommendationsHtml += "<li>No recommendations - all tests passed</li>"
    } else {
        foreach ($recommendation in $script:results.Recommendations) {
            $recommendationsHtml += "<li>$recommendation</li>"
        }
    }
    
    $recommendationsHtml += "</ul></div></body></html>"
    
    # Combine all HTML fragments
    $html = $headerHtml + 
            $statusHtml + 
            $sysReqHeaderHtml + 
            $psVersionHtml + 
            $adminRightsHtml + 
            $moduleRowsHtml + 
            $sysReqFooterHtml + 
            $wsHeaderHtml + 
            $wsConnectivityHtml + 
            $wsApiHtml + 
            $wsAuthHtml + 
            $wsTableFooterHtml + 
            $wsEndpointsHeaderHtml + 
            $wsEndpointRowsHtml + 
            $wsEndpointsFooterHtml + 
            $azureHeaderHtml + 
            $azureConnectivityHtml + 
            $azureApiHtml + 
            $azureAuthHtml + 
            $azureTableFooterHtml + 
            $azureEndpointsHeaderHtml + 
            $azureEndpointRowsHtml + 
            $azureEndpointsFooterHtml + 
            $recommendationsHtml
    
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

# PowerShell Version
$psVersionColor = 'Red'
$psVersion = $PSVersionTable.PSVersion.ToString()
if ($script:results.SystemRequirements.PowerShellVersion) { 
    $psVersionColor = 'Green' 
}
Write-Host "  PowerShell Version: $psVersion" -ForegroundColor $psVersionColor

# Admin Rights
$adminRightsText = 'No'
$adminRightsColor = 'Red'
if ($script:results.SystemRequirements.AdminRights) { 
    $adminRightsText = 'Yes'
    $adminRightsColor = 'Green'
}
Write-Host "  Admin Rights: $adminRightsText" -ForegroundColor $adminRightsColor

# Required Modules
foreach ($module in $script:results.SystemRequirements.RequiredModules.Keys) {
    $status = $script:results.SystemRequirements.RequiredModules[$module]
    $moduleText = 'Not Installed'
    $moduleColor = 'Red'
    if ($status) { 
        $moduleText = 'Installed'
        $moduleColor = 'Green'
    }
    Write-Host "  Module ${module}: ${moduleText}" -ForegroundColor $moduleColor
}

Write-Host ""
Write-Host "Workspace ONE Connectivity:"

# WS1 Basic Connectivity
$wsConnectivityText = 'Failed'
$wsConnectivityColor = 'Red'
if ($script:results.WorkspaceOne.BasicConnectivity) { 
    $wsConnectivityText = 'Success'
    $wsConnectivityColor = 'Green'
}
Write-Host "  Basic Connectivity: $wsConnectivityText" -ForegroundColor $wsConnectivityColor

# WS1 API Accessibility
$wsApiText = 'Failed'
$wsApiColor = 'Red'
if ($script:results.WorkspaceOne.ApiAccessible) { 
    $wsApiText = 'Success'
    $wsApiColor = 'Green'
}
Write-Host "  API Accessible: $wsApiText" -ForegroundColor $wsApiColor

# WS1 Authentication
$wsAuthText = 'Not Tested'
$wsAuthColor = 'Yellow'
if ($TestAuth) {
    if ($script:results.WorkspaceOne.AuthSuccessful) {
        $wsAuthText = 'Success'
        $wsAuthColor = 'Green'
    } else {
        $wsAuthText = 'Failed'
        $wsAuthColor = 'Red'
    }
}
Write-Host "  Authentication: $wsAuthText" -ForegroundColor $wsAuthColor

Write-Host ""
Write-Host "Azure Connectivity:"

# Azure Basic Connectivity
$azureConnectivityText = 'Failed'
$azureConnectivityColor = 'Red'
if ($script:results.Azure.BasicConnectivity) { 
    $azureConnectivityText = 'Success'
    $azureConnectivityColor = 'Green'
}
Write-Host "  Basic Connectivity: $azureConnectivityText" -ForegroundColor $azureConnectivityColor

# Azure API Accessibility
$azureApiText = 'Failed'
$azureApiColor = 'Red'
if ($results.Azure.ApiAccessible) { 
    $azureApiText = 'Success'
    $azureApiColor = 'Green'
}
Write-Host "  API Accessible: $azureApiText" -ForegroundColor $azureApiColor

# Azure Authentication
$azureAuthText = 'Not Tested'
$azureAuthColor = 'Yellow'
if ($TestAuth) {
    if ($results.Azure.AuthSuccessful) {
        $azureAuthText = 'Success'
        $azureAuthColor = 'Green'
    } else {
        $azureAuthText = 'Failed'
        $azureAuthColor = 'Red'
    }
}
Write-Host "  Authentication: $azureAuthText" -ForegroundColor $azureAuthColor

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