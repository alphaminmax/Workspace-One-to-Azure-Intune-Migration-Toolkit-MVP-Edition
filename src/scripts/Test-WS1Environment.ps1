<# TEST-WS1ENVIRONMENT.PS1
.SYNOPSIS
    Verifies the environment is correctly configured for Workspace One enrollment.
.DESCRIPTION
    Checks various aspects of the Windows 10/11 environment to ensure it's ready
    for Workspace One enrollment with Intune integration.
.NOTES
    Version: 1.0
    Author: Modern Windows Management
    RequiredVersion: PowerShell 5.1 or higher
.EXAMPLE
    .\Test-WS1Environment.ps1
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$GenerateReport,
    
    [Parameter()]
    [string]$ReportPath = "C:\Temp\Logs\WS1_EnvReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
)

# Import the Workspace One wizard module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "WorkspaceOneWizard.psm1"
if (Test-Path -Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Error "Workspace One Wizard module not found at path: $modulePath"
    Exit 1
}

# Initialize variables
$results = @{
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    WindowsVersion = $null
    PowerShellVersion = $null
    AdminRights = $false
    NetworkConnectivity = $false
    EnrollmentServerReachable = $false
    MDMEnrollmentStatus = "Not Enrolled"
    RegistryPermissions = $false
    WMIAccess = $false
    SystemIssues = @()
    Recommendations = @()
}

# Output function
function Write-TestResult {
    [CmdletBinding()]
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message
    )
    
    $statusIcon = if ($Success) { "[✓]" } else { "[✗]" }
    $statusColor = if ($Success) { "Green" } else { "Red" }
    
    Write-Host "$statusIcon " -ForegroundColor $statusColor -NoNewline
    Write-Host "$TestName: " -NoNewline
    Write-Host $Message
}

# Check Windows version
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $windowsVersion = if ($osInfo.BuildNumber -match '^10\d{3}$') {
        "Windows 10 (Build $($osInfo.BuildNumber))"
    } elseif ($osInfo.BuildNumber -match '^22[0-9]{3}$') {
        "Windows 11 (Build $($osInfo.BuildNumber))"
    } else {
        "Unsupported Windows version (Build $($osInfo.BuildNumber))"
    }
    
    $results.WindowsVersion = "$($osInfo.Caption) $($osInfo.Version) (Build $($osInfo.BuildNumber))"
    
    $isSupported = $osInfo.BuildNumber -match '^10\d{3}$|^22[0-9]{3}$'
    
    Write-TestResult -TestName "Windows Version" -Success $isSupported -Message $results.WindowsVersion
    
    if (-not $isSupported) {
        $results.SystemIssues += "Unsupported Windows version: $($results.WindowsVersion)"
        $results.Recommendations += "Upgrade to a supported Windows 10/11 version"
    }
} catch {
    Write-TestResult -TestName "Windows Version" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Failed to determine Windows version: $_"
}

# Check PowerShell version
try {
    $psVersion = $PSVersionTable.PSVersion
    $results.PowerShellVersion = "$($psVersion.Major).$($psVersion.Minor).$($psVersion.Build)"
    $isPSSupported = $psVersion.Major -ge 5 -and $psVersion.Minor -ge 1
    
    Write-TestResult -TestName "PowerShell Version" -Success $isPSSupported -Message $results.PowerShellVersion
    
    if (-not $isPSSupported) {
        $results.SystemIssues += "PowerShell version below minimum required (5.1): $($results.PowerShellVersion)"
        $results.Recommendations += "Upgrade PowerShell to version 5.1 or higher"
    }
} catch {
    Write-TestResult -TestName "PowerShell Version" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Failed to determine PowerShell version: $_"
}

# Check admin rights
try {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    $results.AdminRights = $principal.IsInRole($adminRole)
    
    Write-TestResult -TestName "Admin Rights" -Success $results.AdminRights -Message $(if ($results.AdminRights) { "Yes" } else { "No" })
    
    if (-not $results.AdminRights) {
        $results.SystemIssues += "User does not have administrator rights"
        $results.Recommendations += "Run with administrator privileges for full enrollment functionality"
    }
} catch {
    Write-TestResult -TestName "Admin Rights" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Failed to check administrator rights: $_"
}

# Check network connectivity
try {
    $results.NetworkConnectivity = Test-NetConnection -ComputerName "www.microsoft.com" -InformationLevel Quiet -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    
    Write-TestResult -TestName "Internet Connectivity" -Success $results.NetworkConnectivity -Message $(if ($results.NetworkConnectivity) { "Online" } else { "Offline" })
    
    if (-not $results.NetworkConnectivity) {
        $results.SystemIssues += "No internet connectivity detected"
        $results.Recommendations += "Connect to the internet to enable enrollment"
    }
} catch {
    Write-TestResult -TestName "Internet Connectivity" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Failed to check network connectivity: $_"
}

# Check enrollment server connectivity
try {
    # Import config to get the server URL
    Import-WS1Config -ErrorAction SilentlyContinue
    
    $serverHost = $script:EnrollmentServer -replace "https://", "" -replace "/.*", ""
    $results.EnrollmentServerReachable = Test-NetConnection -ComputerName $serverHost -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    
    Write-TestResult -TestName "Enrollment Server" -Success $results.EnrollmentServerReachable -Message "$(if ($results.EnrollmentServerReachable) { "Reachable" } else { "Unreachable" }): $script:EnrollmentServer"
    
    if (-not $results.EnrollmentServerReachable) {
        $results.SystemIssues += "Cannot reach enrollment server: $script:EnrollmentServer"
        $results.Recommendations += "Verify enrollment server URL and network connectivity"
    }
} catch {
    Write-TestResult -TestName "Enrollment Server" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Failed to check enrollment server: $_"
}

# Check MDM enrollment status
try {
    $enrollments = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\" -ErrorAction SilentlyContinue
    
    if ($enrollments.Count -gt 0) {
        $results.MDMEnrollmentStatus = "Already Enrolled ($($enrollments.Count) enrollments found)"
        Write-TestResult -TestName "MDM Status" -Success $false -Message $results.MDMEnrollmentStatus
        $results.SystemIssues += "Device appears to be already enrolled in MDM"
        $results.Recommendations += "Unenroll from current MDM before attempting new enrollment"
    } else {
        $results.MDMEnrollmentStatus = "Not Enrolled"
        Write-TestResult -TestName "MDM Status" -Success $true -Message $results.MDMEnrollmentStatus
    }
} catch {
    Write-TestResult -TestName "MDM Status" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Failed to check MDM enrollment status: $_"
}

# Check registry permissions
try {
    $testRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MDM"
    $hasAccess = $true
    
    if (-not (Test-Path -Path $testRegPath)) {
        New-Item -Path $testRegPath -Force -ErrorAction Stop | Out-Null
    }
    
    # Test write access by creating a temporary value
    $testValue = "WS1TestValue"
    Set-ItemProperty -Path $testRegPath -Name $testValue -Value "Test" -ErrorAction Stop
    Remove-ItemProperty -Path $testRegPath -Name $testValue -ErrorAction Stop
    
    $results.RegistryPermissions = $true
    Write-TestResult -TestName "Registry Permissions" -Success $true -Message "Success"
} catch {
    $results.RegistryPermissions = $false
    Write-TestResult -TestName "Registry Permissions" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Insufficient registry permissions: $_"
    $results.Recommendations += "Ensure user has administrative permissions to HKLM registry hive"
}

# Check WMI access
try {
    Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Out-Null
    $results.WMIAccess = $true
    Write-TestResult -TestName "WMI Access" -Success $true -Message "Success"
} catch {
    $results.WMIAccess = $false
    Write-TestResult -TestName "WMI Access" -Success $false -Message "Error: $_"
    $results.SystemIssues += "Insufficient WMI access: $_"
    $results.Recommendations += "Verify WMI permissions and service status"
}

# Generate report if requested
if ($GenerateReport) {
    try {
        $reportFolder = Split-Path -Path $ReportPath -Parent
        if (-not (Test-Path -Path $reportFolder)) {
            New-Item -Path $reportFolder -ItemType Directory -Force | Out-Null
        }
        
        # Calculate overall readiness percentage
        $tests = @(
            $isSupported, 
            $isPSSupported, 
            $results.AdminRights, 
            $results.NetworkConnectivity, 
            $results.EnrollmentServerReachable, 
            ($enrollments.Count -eq 0), 
            $results.RegistryPermissions, 
            $results.WMIAccess
        )
        
        $passedTests = ($tests | Where-Object { $_ -eq $true }).Count
        $totalTests = $tests.Count
        $readinessPercentage = [math]::Round(($passedTests / $totalTests) * 100, 1)
        
        # Create HTML report
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Workspace One Environment Readiness Report</title>
    <style>
        :root {
            --primary-color: #0078d4;
            --success-color: #107c10;
            --warning-color: #d83b01;
            --error-color: #d13438;
            --background-color: #f5f5f5;
            --card-background: #ffffff;
            --text-color: #323130;
            --border-color: #edebe9;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: var(--background-color);
            color: var(--text-color);
        }
        
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background-color: var(--card-background);
            border-radius: 8px;
            box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
            padding: 20px;
        }
        
        h1, h2, h3 {
            color: var(--primary-color);
        }
        
        .header {
            border-bottom: 1px solid var(--border-color);
            padding-bottom: 15px;
            margin-bottom: 20px;
        }
        
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        
        .summary-box {
            background-color: var(--card-background);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
        }
        
        .summary-box h3 {
            margin-top: 0;
            font-size: 16px;
        }
        
        .summary-percentage {
            font-size: 36px;
            font-weight: bold;
            margin: 10px 0;
        }
        
        .passed {
            color: var(--success-color);
        }
        
        .failed {
            color: var(--error-color);
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        
        th, td {
            padding: a2px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        
        th {
            background-color: var(--primary-color);
            color: white;
        }
        
        tr:nth-child(even) {
            background-color: rgba(0, 0, 0, 0.02);
        }
        
        .status-success {
            color: var(--success-color);
        }
        
        .status-error {
            color: var(--error-color);
        }
        
        .recommendations {
            background-color: var(--card-background);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
        }
        
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Workspace One Environment Readiness Report</h1>
            <p>Generated on: $($results.Timestamp)</p>
        </div>
        
        <div class="summary">
            <div class="summary-box">
                <h3>Computer Name</h3>
                <div>$($results.ComputerName)</div>
            </div>
            <div class="summary-box">
                <h3>User Name</h3>
                <div>$($results.UserName)</div>
            </div>
            <div class="summary-box">
                <h3>Windows Version</h3>
                <div>$($results.WindowsVersion)</div>
            </div>
            <div class="summary-box">
                <h3>Overall Readiness</h3>
                <div class="summary-percentage $(if ($readinessPercentage -ge 80) { 'passed' } else { 'failed' })">
                    $readinessPercentage%
                </div>
            </div>
        </div>
        
        <h2>System Tests</h2>
        <table>
            <tr>
                <th>Test</th>
                <th>Status</th>
                <th>Details</th>
            </tr>
            <tr>
                <td>Windows Version</td>
                <td class="$(if ($isSupported) { 'status-success' } else { 'status-error' })">$(if ($isSupported) { '✓' } else { '✗' })</td>
                <td>$($results.WindowsVersion)</td>
            </tr>
            <tr>
                <td>PowerShell Version</td>
                <td class="$(if ($isPSSupported) { 'status-success' } else { 'status-error' })">$(if ($isPSSupported) { '✓' } else { '✗' })</td>
                <td>$($results.PowerShellVersion)</td>
            </tr>
            <tr>
                <td>Admin Rights</td>
                <td class="$(if ($results.AdminRights) { 'status-success' } else { 'status-error' })">$(if ($results.AdminRights) { '✓' } else { '✗' })</td>
                <td>$(if ($results.AdminRights) { 'Yes' } else { 'No' })</td>
            </tr>
            <tr>
                <td>Internet Connectivity</td>
                <td class="$(if ($results.NetworkConnectivity) { 'status-success' } else { 'status-error' })">$(if ($results.NetworkConnectivity) { '✓' } else { '✗' })</td>
                <td>$(if ($results.NetworkConnectivity) { 'Online' } else { 'Offline' })</td>
            </tr>
            <tr>
                <td>Enrollment Server</td>
                <td class="$(if ($results.EnrollmentServerReachable) { 'status-success' } else { 'status-error' })">$(if ($results.EnrollmentServerReachable) { '✓' } else { '✗' })</td>
                <td>$script:EnrollmentServer</td>
            </tr>
            <tr>
                <td>MDM Status</td>
                <td class="$(if ($enrollments.Count -eq 0) { 'status-success' } else { 'status-error' })">$(if ($enrollments.Count -eq 0) { '✓' } else { '✗' })</td>
                <td>$($results.MDMEnrollmentStatus)</td>
            </tr>
            <tr>
                <td>Registry Permissions</td>
                <td class="$(if ($results.RegistryPermissions) { 'status-success' } else { 'status-error' })">$(if ($results.RegistryPermissions) { '✓' } else { '✗' })</td>
                <td>$(if ($results.RegistryPermissions) { 'Success' } else { 'Insufficient' })</td>
            </tr>
            <tr>
                <td>WMI Access</td>
                <td class="$(if ($results.WMIAccess) { 'status-success' } else { 'status-error' })">$(if ($results.WMIAccess) { '✓' } else { '✗' })</td>
                <td>$(if ($results.WMIAccess) { 'Success' } else { 'Insufficient' })</td>
            </tr>
        </table>
        
        <h2>Issues</h2>
        <div class="recommendations">
            $(if ($results.SystemIssues.Count -eq 0) {
                "<p>No issues detected.</p>"
            } else {
                "<ul>" + ($results.SystemIssues | ForEach-Object { "<li>$_</li>" }) + "</ul>"
            })
        </div>
        
        <h2>Recommendations</h2>
        <div class="recommendations">
            $(if ($results.Recommendations.Count -eq 0) {
                "<p>No recommendations at this time.</p>"
            } else {
                "<ul>" + ($results.Recommendations | ForEach-Object { "<li>$_</li>" }) + "</ul>"
            })
        </div>
        
        <div class="footer">
            <p>Generated with Test-WS1Environment.ps1 | Workspace One Enrollment Tools</p>
        </div>
    </div>
</body>
</html>
"@
        
        # Generate HTML report file
        $htmlContent | Out-File -FilePath $ReportPath -Encoding utf8 -Force
        
        Write-Host "`nEnvironment readiness report generated at: $ReportPath" -ForegroundColor Cyan
    } catch {
        Write-Error "Failed to generate report: $_"
    }
}

# Summary
Write-Host "`n=== Environment Readiness Summary ===" -ForegroundColor Cyan
$overallReady = $results.SystemIssues.Count -eq 0

if ($overallReady) {
    Write-Host "Environment is READY for Workspace One enrollment." -ForegroundColor Green
} else {
    Write-Host "Environment requires attention before enrollment." -ForegroundColor Yellow
    Write-Host "Found $($results.SystemIssues.Count) issues that need to be resolved." -ForegroundColor Yellow
    
    if ($results.Recommendations.Count -gt 0) {
        Write-Host "`nRecommendations:" -ForegroundColor Cyan
        foreach ($recommendation in $results.Recommendations) {
            Write-Host "- $recommendation" -ForegroundColor White
        }
    }
} 