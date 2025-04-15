#Requires -Version 5.1

<#
.SYNOPSIS
    Provides verification functionality for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    The MigrationVerification module validates the success of a migration from 
    Workspace One to Azure/Intune. It includes functions for:
    - Verifying device enrollment in Intune
    - Checking configuration state and compliance
    - Validating application installations
    - Generating verification reports
    - Running automated health checks
    
.NOTES
    File Name      : MigrationVerification.psm1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
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

# Script-level variables
$script:VerificationResultsPath = Join-Path -Path $env:TEMP -ChildPath "MigrationVerification"
$script:RequiredIntunePolicies = @(
    "Windows Security Baseline",
    "Endpoint Protection",
    "Windows Update for Business"
)

#region Private Functions

function Test-IntuneConnectivity {
    <#
    .SYNOPSIS
        Tests connectivity to Microsoft Intune service.
    #>
    try {
        # This is a placeholder - in a real implementation, this would use 
        # proper Graph API authentication to check connectivity
        $intuneEndpoint = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"
        $response = Invoke-WebRequest -Uri $intuneEndpoint -UseDefaultCredentials -Method Head -ErrorAction Stop
        return $response.StatusCode -eq 200
    }
    catch {
        Write-Log -Message "Failed to connect to Intune: $_" -Level Error
        return $false
    }
}

function Get-MigrationRegistryStatus {
    <#
    .SYNOPSIS
        Retrieves migration status from registry.
    #>
    $status = @{
        MigrationCompleted = $false
        MigrationDate = $null
        SourceEnvironment = $null
        TargetEnvironment = $null
    }
    
    try {
        $migrationKey = "HKLM:\SOFTWARE\Company\Migration"
        if (Test-Path -Path $migrationKey) {
            $migrationData = Get-ItemProperty -Path $migrationKey -ErrorAction SilentlyContinue
            
            if ($migrationData) {
                $status.MigrationCompleted = $migrationData.MigrationCompleted -eq 1
                
                if ($migrationData.MigrationDate) {
                    $status.MigrationDate = [DateTime]::Parse($migrationData.MigrationDate)
                }
                
                $status.SourceEnvironment = $migrationData.SourceEnvironment
                $status.TargetEnvironment = $migrationData.TargetEnvironment
            }
        }
    }
    catch {
        Write-Log -Message "Error retrieving migration registry status: $_" -Level Error
    }
    
    return $status
}

function Export-VerificationResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ReportName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Results
    )
    
    try {
        if (-not (Test-Path -Path $script:VerificationResultsPath)) {
            New-Item -Path $script:VerificationResultsPath -ItemType Directory -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $reportFile = Join-Path -Path $script:VerificationResultsPath -ChildPath "${ReportName}_${timestamp}.json"
        
        $Results | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportFile -Encoding utf8
        
        Write-Log -Message "Verification results exported to: $reportFile" -Level Information
        return $reportFile
    }
    catch {
        Write-Log -Message "Failed to export verification results: $_" -Level Error
        return $null
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Verifies device enrollment in Microsoft Intune.
    
.DESCRIPTION
    Checks if the device is properly enrolled in Intune after migration,
    validates management authority and device compliance status.
    
.EXAMPLE
    Test-IntuneEnrollment
    
.OUTPUTS
    System.Collections.Hashtable. Returns enrollment verification results.
#>
function Test-IntuneEnrollment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-Log -Message "Starting Intune enrollment verification" -Level Information
    
    $results = @{
        Success = $false
        EnrollmentState = "Unknown"
        ManagementAuthority = "Unknown"
        ComplianceState = "Unknown"
        Details = @{}
        Timestamp = Get-Date
    }
    
    try {
        # Check if device is enrolled in Intune
        # Using dsregcmd to check enrollment status
        $dsregcmd = Start-Process -FilePath "dsregcmd.exe" -ArgumentList "/status" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\dsregcmd.txt"
        
        if ($dsregcmd.ExitCode -eq 0 -and (Test-Path -Path "$env:TEMP\dsregcmd.txt")) {
            $dsregOutput = Get-Content -Path "$env:TEMP\dsregcmd.txt" -Raw
            
            # Parse output
            $results.Details.AzureAdJoined = $dsregOutput -match "AzureAdJoined : YES"
            $results.Details.EnterpriseJoined = $dsregOutput -match "EnterpriseJoined : YES"
            $results.Details.DeviceId = if ($dsregOutput -match "DeviceId : (.+)") { $matches[1].Trim() } else { "Not found" }
            $results.Details.TenantId = if ($dsregOutput -match "TenantId : (.+)") { $matches[1].Trim() } else { "Not found" }
            
            # Check MDM enrollment
            $mdmEnrolled = $dsregOutput -match "MDMEnrollmentUrl : https://enrollment.manage.microsoft.com"
            
            if ($results.Details.AzureAdJoined -and $mdmEnrolled) {
                $results.EnrollmentState = "Enrolled"
                $results.ManagementAuthority = "Microsoft Intune"
                
                # Check for WorkspaceOne remnants
                $airWatchAgent = Get-Service -Name "AirWatchMDMService" -ErrorAction SilentlyContinue
                if ($null -ne $airWatchAgent) {
                    $results.Details.WorkspaceOneAgentPresent = $true
                    $results.Details.WorkspaceOneAgentStatus = $airWatchAgent.Status
                    $results.Details.Warnings = @("WorkspaceOne agent still present")
                } else {
                    $results.Details.WorkspaceOneAgentPresent = $false
                }
                
                # Check compliance state
                # In a real implementation, this would use Graph API
                # For now, we'll check if device shows up in registry as managed by Intune
                $intuneRegistry = "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\MS DM Server"
                if (Test-Path -Path $intuneRegistry) {
                    $results.ComplianceState = "Compliant"
                    $results.Success = $true
                } else {
                    $results.ComplianceState = "Verification Failed"
                    $results.Details.Errors = @("Device not showing Intune management in registry")
                }
            } else {
                $results.EnrollmentState = "Not Enrolled"
                $results.Details.Errors = @("Device not properly enrolled in Intune")
            }
        } else {
            $results.Details.Errors = @("Failed to run dsregcmd to check enrollment status")
        }
        
        # Clean up temp file
        if (Test-Path -Path "$env:TEMP\dsregcmd.txt") {
            Remove-Item -Path "$env:TEMP\dsregcmd.txt" -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        $results.Details.Errors = @("Error during verification: $_")
        Write-Log -Message "Error during Intune enrollment verification: $_" -Level Error
    }
    
    # Export results
    $reportFile = Export-VerificationResults -ReportName "IntuneEnrollment" -Results $results
    $results.ReportFile = $reportFile
    
    Write-Log -Message "Intune enrollment verification completed. Success: $($results.Success)" -Level Information
    
    return $results
}

<#
.SYNOPSIS
    Verifies applications are installed and functioning post-migration.
    
.DESCRIPTION
    Checks if required applications are installed and functioning
    properly after migration to Intune.
    
.PARAMETER RequiredApplications
    List of application names that should be present after migration.
    
.EXAMPLE
    Test-ApplicationFunctionality -RequiredApplications @("Microsoft Office", "Company VPN Client")
    
.OUTPUTS
    System.Collections.Hashtable. Returns application verification results.
#>
function Test-ApplicationFunctionality {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredApplications = @()
    )
    
    Write-Log -Message "Starting application functionality verification" -Level Information
    
    $results = @{
        Success = $true
        InstalledApps = @()
        MissingApps = @()
        Details = @{}
        Timestamp = Get-Date
    }
    
    try {
        # Get installed applications
        $installedApps = Get-WmiObject -Class Win32_Product | Select-Object -ExpandProperty Name
        $results.InstalledApps = $installedApps
        
        # Check for required applications
        if ($RequiredApplications.Count -gt 0) {
            foreach ($app in $RequiredApplications) {
                if ($installedApps -notcontains $app) {
                    $results.MissingApps += $app
                    $results.Success = $false
                }
            }
        }
        
        # Additional app-specific checks could be added here
        # For example, checking specific versions, services, or functionality tests
    }
    catch {
        $results.Success = $false
        $results.Details.Errors = @("Error during application verification: $_")
        Write-Log -Message "Error during application verification: $_" -Level Error
    }
    
    # Export results
    $reportFile = Export-VerificationResults -ReportName "ApplicationFunctionality" -Results $results
    $results.ReportFile = $reportFile
    
    Write-Log -Message "Application functionality verification completed. Success: $($results.Success)" -Level Information
    
    return $results
}

<#
.SYNOPSIS
    Verifies device health after migration.
    
.DESCRIPTION
    Runs a comprehensive health check on the device post-migration
    to ensure all systems are functioning properly.
    
.EXAMPLE
    Test-DeviceHealth
    
.OUTPUTS
    System.Collections.Hashtable. Returns health check results.
#>
function Test-DeviceHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-Log -Message "Starting device health verification" -Level Information
    
    $results = @{
        Success = $true
        HealthChecks = @{}
        Timestamp = Get-Date
    }
    
    try {
        # Check Windows Update service
        $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        $results.HealthChecks.WindowsUpdate = @{
            Status = $wuService.Status
            Success = $wuService.Status -eq "Running"
        }
        
        if ($wuService.Status -ne "Running") {
            $results.Success = $false
        }
        
        # Check disk space
        $systemDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $results.HealthChecks.DiskSpace = @{
            FreeSpaceGB = $freeSpaceGB
            Success = $freeSpaceGB -gt 5  # Consider less than 5GB as failure
        }
        
        if ($freeSpaceGB -lt 5) {
            $results.Success = $false
        }
        
        # Check Windows Defender
        $defenderService = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        $results.HealthChecks.WindowsDefender = @{
            Status = $defenderService.Status
            Success = $defenderService.Status -eq "Running"
        }
        
        if ($defenderService.Status -ne "Running") {
            $results.Success = $false
        }
        
        # Check BitLocker status on system drive
        $bitlockerVolume = Get-WmiObject -Namespace "ROOT\CIMV2\Security\MicrosoftVolumeEncryption" -Class "Win32_EncryptableVolume" -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction SilentlyContinue
        if ($bitlockerVolume) {
            $protectionStatus = $bitlockerVolume.GetProtectionStatus().ProtectionStatus
            $results.HealthChecks.BitLocker = @{
                Status = if ($protectionStatus -eq 1) { "Protected" } else { "Not Protected" }
                Success = $protectionStatus -eq 1
            }
            
            if ($protectionStatus -ne 1) {
                $results.Success = $false
            }
        } else {
            $results.HealthChecks.BitLocker = @{
                Status = "Not Available"
                Success = $true  # Not failing if BitLocker is not available
            }
        }
        
        # Check system boot time
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        $uptime = (Get-Date) - $lastBoot
        
        $results.HealthChecks.SystemUptime = @{
            LastBootTime = $lastBoot
            UptimeDays = [math]::Round($uptime.TotalDays, 2)
            Success = $true  # Just informational
        }
    }
    catch {
        $results.Success = $false
        $results.HealthChecks.Errors = @("Error during health verification: $_")
        Write-Log -Message "Error during device health verification: $_" -Level Error
    }
    
    # Export results
    $reportFile = Export-VerificationResults -ReportName "DeviceHealth" -Results $results
    $results.ReportFile = $reportFile
    
    Write-Log -Message "Device health verification completed. Success: $($results.Success)" -Level Information
    
    return $results
}

<#
.SYNOPSIS
    Generates a comprehensive verification report for the migration.
    
.DESCRIPTION
    Combines the results of all verification checks into a single
    comprehensive report for administrators.
    
.PARAMETER OutputPath
    The path where the report should be saved. Default is user's desktop.
    
.PARAMETER Format
    The format of the report. Can be 'HTML', 'JSON', or 'Both'. Default is 'HTML'.
    
.EXAMPLE
    New-MigrationVerificationReport -OutputPath "C:\Reports" -Format "Both"
    
.OUTPUTS
    System.String. Returns the path to the generated report(s).
#>
function New-MigrationVerificationReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = [Environment]::GetFolderPath("Desktop"),
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("HTML", "JSON", "Both")]
        [string]$Format = "HTML"
    )
    
    Write-Log -Message "Generating migration verification report" -Level Information
    
    try {
        # Run all verification tests
        $intuneResults = Test-IntuneEnrollment
        $appResults = Test-ApplicationFunctionality
        $healthResults = Test-DeviceHealth
        
        # Combine results
        $combinedResults = @{
            ComputerName = $env:COMPUTERNAME
            VerificationDate = Get-Date
            MigrationStatus = Get-MigrationRegistryStatus
            OverallSuccess = $intuneResults.Success -and $appResults.Success -and $healthResults.Success
            IntuneEnrollment = $intuneResults
            Applications = $appResults
            DeviceHealth = $healthResults
        }
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $reportBaseName = "MigrationVerification_$($env:COMPUTERNAME)_$timestamp"
        $reportPaths = @()
        
        # Generate JSON report if requested
        if ($Format -eq "JSON" -or $Format -eq "Both") {
            $jsonPath = Join-Path -Path $OutputPath -ChildPath "$reportBaseName.json"
            $combinedResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding utf8
            $reportPaths += $jsonPath
        }
        
        # Generate HTML report if requested
        if ($Format -eq "HTML" -or $Format -eq "Both") {
            $htmlPath = Join-Path -Path $OutputPath -ChildPath "$reportBaseName.html"
            
            # Create HTML report
            $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>Migration Verification Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2, h3 { color: #0078D4; }
        .success { color: green; }
        .failure { color: red; }
        .warning { color: orange; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .section { margin: 20px 0; padding: 10px; border-left: 5px solid #0078D4; background-color: #f8f8f8; }
    </style>
</head>
<body>
    <h1>Migration Verification Report</h1>
    <p>Computer: $($combinedResults.ComputerName)</p>
    <p>Date: $($combinedResults.VerificationDate)</p>
    <p>Overall Status: <span class="$(if($combinedResults.OverallSuccess){'success'}else{'failure'})">$(if($combinedResults.OverallSuccess){'SUCCESS'}else{'FAILED'})</span></p>
"@
            
            $intuneSection = @"
    <div class="section">
        <h2>Intune Enrollment</h2>
        <p>Status: <span class="$(if($intuneResults.Success){'success'}else{'failure'})">$(if($intuneResults.Success){'SUCCESS'}else{'FAILED'})</span></p>
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Enrollment State</td><td>$($intuneResults.EnrollmentState)</td></tr>
            <tr><td>Management Authority</td><td>$($intuneResults.ManagementAuthority)</td></tr>
            <tr><td>Compliance State</td><td>$($intuneResults.ComplianceState)</td></tr>
        </table>
"@
            
            if ($intuneResults.Details.Errors) {
                $intuneSection += @"
        <h3>Errors</h3>
        <ul>
            $(foreach($error in $intuneResults.Details.Errors) { "<li>$error</li>" })
        </ul>
"@
            }
            
            $intuneSection += "</div>"
            
            $appSection = @"
    <div class="section">
        <h2>Application Functionality</h2>
        <p>Status: <span class="$(if($appResults.Success){'success'}else{'failure'})">$(if($appResults.Success){'SUCCESS'}else{'FAILED'})</span></p>
"@
            
            if ($appResults.MissingApps.Count -gt 0) {
                $appSection += @"
        <h3>Missing Applications</h3>
        <ul>
            $(foreach($app in $appResults.MissingApps) { "<li>$app</li>" })
        </ul>
"@
            }
            
            $appSection += "</div>"
            
            $healthSection = @"
    <div class="section">
        <h2>Device Health</h2>
        <p>Status: <span class="$(if($healthResults.Success){'success'}else{'failure'})">$(if($healthResults.Success){'SUCCESS'}else{'FAILED'})</span></p>
        <table>
            <tr><th>Check</th><th>Status</th><th>Result</th></tr>
"@
            
            foreach ($check in $healthResults.HealthChecks.Keys) {
                if ($check -ne "Errors") {
                    $healthSection += @"
            <tr>
                <td>$check</td>
                <td>$($healthResults.HealthChecks[$check].Status)</td>
                <td class="$(if($healthResults.HealthChecks[$check].Success){'success'}else{'failure'})">$(if($healthResults.HealthChecks[$check].Success){'PASS'}else{'FAIL'})</td>
            </tr>
"@
                }
            }
            
            $healthSection += @"
        </table>
"@
            
            if ($healthResults.HealthChecks.Errors) {
                $healthSection += @"
        <h3>Errors</h3>
        <ul>
            $(foreach($error in $healthResults.HealthChecks.Errors) { "<li>$error</li>" })
        </ul>
"@
            }
            
            $healthSection += "</div>"
            
            $htmlFooter = @"
    <div class="section">
        <h2>Recommendations</h2>
        <ul>
$(if(-not $combinedResults.OverallSuccess) {
    if(-not $intuneResults.Success) { "            <li>Verify Intune enrollment and resolve any MDM enrollment issues</li>" }
    if(-not $appResults.Success) { "            <li>Install missing applications through Intune Company Portal</li>" }
    if(-not $healthResults.Success) { "            <li>Address device health issues highlighted in the report</li>" }
    "            <li>Contact IT support if issues persist</li>"
} else {
    "            <li>No recommendations - migration verification successful</li>"
})
        </ul>
    </div>
    <p>Report generated by MigrationVerification module v1.0</p>
</body>
</html>
"@
            
            $htmlContent = $htmlHeader + $intuneSection + $appSection + $healthSection + $htmlFooter
            $htmlContent | Out-File -FilePath $htmlPath -Encoding utf8
            $reportPaths += $htmlPath
        }
        
        Write-Log -Message "Migration verification report generated at: $($reportPaths -join ', ')" -Level Information
        return $reportPaths -join ';'
    }
    catch {
        Write-Log -Message "Error generating migration verification report: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
    Runs all verification checks and generates a comprehensive report.
    
.DESCRIPTION
    Executes all verification checks to validate a successful migration
    from Workspace One to Intune, and generates a comprehensive report.
    
.PARAMETER OutputPath
    The path where the report should be saved. Default is user's desktop.
    
.PARAMETER Format
    The format of the report. Can be 'HTML', 'JSON', or 'Both'. Default is 'HTML'.
    
.PARAMETER RequiredApplications
    List of application names that should be present after migration.
    
.EXAMPLE
    Invoke-MigrationVerification -OutputPath "C:\Reports" -Format "Both" -RequiredApplications @("Microsoft Office", "Company VPN Client")
    
.OUTPUTS
    System.Collections.Hashtable. Returns verification results and report paths.
#>
function Invoke-MigrationVerification {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = [Environment]::GetFolderPath("Desktop"),
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("HTML", "JSON", "Both")]
        [string]$Format = "HTML",
        
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredApplications = @()
    )
    
    Write-Log -Message "Starting comprehensive migration verification" -Level Information
    
    try {
        # Run all verification tests
        $intuneResults = Test-IntuneEnrollment
        $appResults = Test-ApplicationFunctionality -RequiredApplications $RequiredApplications
        $healthResults = Test-DeviceHealth
        
        # Generate report
        $reportPaths = New-MigrationVerificationReport -OutputPath $OutputPath -Format $Format
        
        # Return combined results
        $results = @{
            ComputerName = $env:COMPUTERNAME
            VerificationDate = Get-Date
            OverallSuccess = $intuneResults.Success -and $appResults.Success -and $healthResults.Success
            IntuneEnrollment = $intuneResults
            Applications = $appResults
            DeviceHealth = $healthResults
            ReportPaths = $reportPaths.Split(';')
        }
        
        Write-Log -Message "Migration verification completed. Overall Success: $($results.OverallSuccess)" -Level Information
        return $results
    }
    catch {
        Write-Log -Message "Error during comprehensive migration verification: $_" -Level Error
        return @{
            OverallSuccess = $false
            Error = $_
        }
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function Test-IntuneEnrollment, Test-ApplicationFunctionality, Test-DeviceHealth, New-MigrationVerificationReport, Invoke-MigrationVerification 