#Requires -Version 5.1

<#
.SYNOPSIS
    Provides basic validation capabilities for Workspace One to Azure/Intune migration.
    
.DESCRIPTION
    This module implements simple validation functions for migration prerequisites,
    connection testing, and post-migration verification.
    
.NOTES
    File Name      : ValidationModule.psm1
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

# Global variables
$script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\config\WS1Config.json"

#region Public Functions

<#
.SYNOPSIS
    Tests prerequisites for a successful migration.
    
.DESCRIPTION
    Verifies that the device meets all requirements for migration from
    Workspace One to Azure/Intune.
    
.EXAMPLE
    Test-MigrationPrerequisites
    
.OUTPUTS
    PSCustomObject with Success flag and detailed results.
#>
function Test-MigrationPrerequisites {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $results = [PSCustomObject]@{
        Success = $true
        WindowsVersion = $null
        PowerShellVersion = $null
        AdminRights = $false
        WorkspaceOneAgent = $false
        NetworkConnectivity = $false
        DiskSpace = $false
        Issues = @()
    }
    
    try {
        # Log start of validation
        Write-LogMessage -Message "Starting migration prerequisite validation" -Level INFO
        
        # Check Windows version
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $results.WindowsVersion = "$($osInfo.Caption) $($osInfo.Version) Build $($osInfo.BuildNumber)"
        
        if ($osInfo.BuildNumber -lt 17763) { # Windows 10 1809
            $results.Issues += "Windows version not supported. Minimum required: Windows 10 1809 (Build 17763)"
            $results.Success = $false
        }
        
        # Check PowerShell version
        $results.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            $results.Issues += "PowerShell version not supported. Minimum required: 5.1"
            $results.Success = $false
        }
        
        # Check for admin rights
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        $results.AdminRights = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $results.AdminRights) {
            $results.Issues += "Script must be run with administrator privileges"
            $results.Success = $false
        }
        
        # Check for Workspace One Agent
        $awAgent = Get-Service -Name "AWService" -ErrorAction SilentlyContinue
        $results.WorkspaceOneAgent = ($null -ne $awAgent)
        
        if (-not $results.WorkspaceOneAgent) {
            $results.Issues += "Workspace One agent not found on the device"
            $results.Success = $false
        }
        
        # Check network connectivity
        $wsConfig = $null
        if (Test-Path -Path $script:ConfigPath) {
            try {
                $wsConfig = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
            } catch {
                Write-LogMessage -Message "Failed to load configuration file: $_" -Level ERROR
            }
        }
        
        $connectivityTests = @(
            @{Name = "Workspace ONE"; URL = $wsConfig.EnrollmentServer ?? "https://ws1.example.com" }
            @{Name = "Microsoft Login"; URL = "https://login.microsoftonline.com" }
            @{Name = "Intune"; URL = "https://graph.microsoft.com" }
        )
        
        $allConnectivity = $true
        foreach ($test in $connectivityTests) {
            try {
                $request = [System.Net.WebRequest]::Create($test.URL)
                $request.Method = "HEAD"
                $request.Timeout = 5000
                $response = $request.GetResponse()
                $response.Close()
                Write-LogMessage -Message "Connectivity to $($test.Name) successful" -Level INFO
            } catch {
                $allConnectivity = $false
                $results.Issues += "Cannot connect to $($test.Name) ($($test.URL))"
                Write-LogMessage -Message "Cannot connect to $($test.Name) ($($test.URL)): $_" -Level WARNING
            }
        }
        $results.NetworkConnectivity = $allConnectivity
        
        # Check disk space
        $systemDrive = Get-PSDrive -Name C
        $freeSpaceGB = [math]::Round($systemDrive.Free / 1GB, 2)
        $results.DiskSpace = ($freeSpaceGB -ge 5)
        
        if (-not $results.DiskSpace) {
            $results.Issues += "Insufficient disk space. Required: 5 GB, Available: $freeSpaceGB GB"
            $results.Success = $false
        }
        
        # Log result
        if ($results.Success) {
            Write-LogMessage -Message "Prerequisite validation successful" -Level INFO
        } else {
            Write-LogMessage -Message "Prerequisite validation failed with ${$results.Issues.Count} issues" -Level WARNING
            foreach ($issue in $results.Issues) {
                Write-LogMessage -Message "Validation issue: $issue" -Level WARNING
            }
        }
        
        return $results
    }
    catch {
        Write-LogMessage -Message "Error during prerequisite validation: $_" -Level ERROR
        $results.Success = $false
        $results.Issues += "Unhandled error during validation: $_"
        return $results
    }
}

<#
.SYNOPSIS
    Validates a migrated device to ensure successful migration.
    
.DESCRIPTION
    Performs basic checks to verify that a device has been successfully migrated
    from Workspace One to Azure/Intune.
    
.EXAMPLE
    Test-MigratedDevice
    
.OUTPUTS
    PSCustomObject with Success flag and detailed results.
#>
function Test-MigratedDevice {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $results = [PSCustomObject]@{
        Success = $true
        EnrolledToIntuneOrAzure = $false
        WorkspaceOneRemoved = $false
        PoliciesApplied = $false
        RequiredAppsInstalled = $false
        Issues = @()
    }
    
    try {
        # Log start of validation
        Write-LogMessage -Message "Starting post-migration validation" -Level INFO
        
        # Check if device is enrolled to Intune/Azure
        $dsregCmd = dsregcmd /status
        $intuneRegistered = $dsregCmd | Select-String "AzureAdJoined : YES" -Quiet
        $results.EnrolledToIntuneOrAzure = $intuneRegistered
        
        if (-not $results.EnrolledToIntuneOrAzure) {
            $results.Issues += "Device is not properly joined to Azure AD"
            $results.Success = $false
        }
        
        # Check if Workspace One has been removed
        $awAgent = Get-Service -Name "AWService" -ErrorAction SilentlyContinue
        $results.WorkspaceOneRemoved = ($null -eq $awAgent)
        
        if (-not $results.WorkspaceOneRemoved) {
            $results.Issues += "Workspace One agent is still present on the device"
            $results.Success = $false
        }
        
        # Check if policies are applied
        $mdmInfo = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device" -ErrorAction SilentlyContinue
        $results.PoliciesApplied = ($null -ne $mdmInfo -and $mdmInfo.Count -gt 0)
        
        if (-not $results.PoliciesApplied) {
            $results.Issues += "No Intune policies found on the device"
            $results.Success = $false
        }
        
        # Check for required apps
        $companyPortal = Get-AppxPackage -Name "Microsoft.CompanyPortal" -ErrorAction SilentlyContinue
        $results.RequiredAppsInstalled = ($null -ne $companyPortal)
        
        if (-not $results.RequiredAppsInstalled) {
            $results.Issues += "Company Portal app not found"
            $results.Success = $false
        }
        
        # Log result
        if ($results.Success) {
            Write-LogMessage -Message "Post-migration validation successful" -Level INFO
        } else {
            Write-LogMessage -Message "Post-migration validation failed with ${$results.Issues.Count} issues" -Level WARNING
            foreach ($issue in $results.Issues) {
                Write-LogMessage -Message "Validation issue: $issue" -Level WARNING
            }
        }
        
        return $results
    }
    catch {
        Write-LogMessage -Message "Error during post-migration validation: $_" -Level ERROR
        $results.Success = $false
        $results.Issues += "Unhandled error during validation: $_"
        return $results
    }
}

# Export functions
Export-ModuleMember -Function Test-MigrationPrerequisites, Test-MigratedDevice 