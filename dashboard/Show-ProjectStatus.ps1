#Requires -Version 5.1

<#
.SYNOPSIS
    Displays the project status dashboard for Workspace ONE to Azure/Intune Migration Toolkit.
    
.DESCRIPTION
    This script reads the index.json file and displays a comprehensive dashboard 
    showing module implementation status, progress percentages, and dependencies.
    It provides a visual representation of the current project state.
    
.PARAMETER IndexPath
    Path to the index.json file. Default is '../config/index.json'.
    
.PARAMETER ShowExtendedComponents
    Switch to show all components including those not in the MVP.
    
.PARAMETER OutputFormat
    The output format. Options: Console, HTML, JSON. Default is Console.
    
.PARAMETER OutputPath
    Path to save the output if format is HTML or JSON.
    
.EXAMPLE
    .\Show-ProjectStatus.ps1
    
.EXAMPLE
    .\Show-ProjectStatus.ps1 -ShowExtendedComponents -OutputFormat HTML -OutputPath 'C:\Reports\status.html'
    
.NOTES
    File Name      : Show-ProjectStatus.ps1
    Author         : Migration Team
    Prerequisite   : PowerShell 5.1
    Version        : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$IndexPath = "..\config\index.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowExtendedComponents,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'Console',
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

# Try multiple paths if needed
$possiblePaths = @(
    $IndexPath,
    "..\config\index.json",
    "..\..\config\index.json",
    "C:\Users\jargrieg\PycharmProjects\WS1_scripts\config\index.json"
)

$indexFileFound = $false
foreach ($path in $possiblePaths) {
    if (Test-Path -Path $path) {
        $IndexPath = $path
        $indexFileFound = $true
        Write-Host "Using index file: $IndexPath"
        break
    }
}

if (-not $indexFileFound) {
    Write-Error "Could not find index.json file in any of the expected locations"
    exit 1
}

function Write-ColorOutput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [Parameter(Mandatory = $true)]
        [System.ConsoleColor]$ForegroundColor
    )
    
    $originalColor = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Text
    $host.UI.RawUI.ForegroundColor = $originalColor
}

function Get-StatusColor {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Status
    )
    
    switch ($Status) {
        'Implemented' { return 'Green' }
        'Partial' { return 'Yellow' }
        'Planned' { return 'Cyan' }
        default { return 'Gray' }
    }
}

function Show-ProgressBar {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Percent,
        
        [Parameter(Mandatory = $false)]
        [int]$Width = 50
    )
    
    $completedWidth = [math]::Floor($Width * ($Percent / 100))
    $remainingWidth = $Width - $completedWidth
    
    $progressBar = '[' + ('█' * $completedWidth) + (' ' * $remainingWidth) + ']'
    return $progressBar
}

function Get-ComponentList {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$IndexData,
        
        [Parameter(Mandatory = $false)]
        [switch]$MVPOnly
    )
    
    $components = @()
    
    # Add modules
    foreach ($moduleName in $IndexData.modules.PSObject.Properties.Name) {
        $module = $IndexData.modules.$moduleName
        if (-not $MVPOnly -or $module.inMVP) {
            $components += [PSCustomObject]@{
                Name = $moduleName
                Type = 'Module'
                Path = $module.path
                Status = $module.status
                InMVP = $module.inMVP
                Description = $module.description
                Dependencies = $module.dependencies -join ', '
            }
        }
    }
    
    # Add scripts
    foreach ($scriptName in $IndexData.scripts.PSObject.Properties.Name) {
        $script = $IndexData.scripts.$scriptName
        if (-not $MVPOnly -or $script.inMVP) {
            $components += [PSCustomObject]@{
                Name = $scriptName
                Type = 'Script'
                Path = $script.path
                Status = $script.status
                InMVP = $script.inMVP
                Description = $script.description
                Dependencies = $script.dependencies -join ', '
            }
        }
    }
    
    # Add documentation
    foreach ($docName in $IndexData.docs.PSObject.Properties.Name) {
        $doc = $IndexData.docs.$docName
        if (-not $MVPOnly -or $doc.inMVP) {
            $components += [PSCustomObject]@{
                Name = $docName
                Type = 'Documentation'
                Path = $doc.path
                Status = $doc.status
                InMVP = $doc.inMVP
                Description = ''
                Dependencies = ''
            }
        }
    }
    
    return $components
}

function Format-ConsoleOutput {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$IndexData,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowExtendedComponents
    )
    
    $components = Get-ComponentList -IndexData $IndexData -MVPOnly:(-not $ShowExtendedComponents)
    
    # Display project header
    Write-Output "`n========================================================="
    Write-Output "  $($IndexData.project.name) - v$($IndexData.project.version)"
    Write-Output "  Status: $($IndexData.project.status)"
    Write-Output "  Last Updated: $($IndexData.project.lastUpdated)"
    Write-Output "========================================================="
    
    # Display progress summary
    $progressData = if ($ShowExtendedComponents) { $IndexData.extendedProgress } else { $IndexData.mvpProgress }
    $progressBar = Show-ProgressBar -Percent $progressData.percentComplete
    Write-Output "`nOverall Progress: $progressBar $($progressData.percentComplete)%"
    Write-Output "Components: $($progressData.totalComponents) | Implemented: $($progressData.implemented) | Partial: $($progressData.partial) | Planned: $($progressData.planned)"
    
    # Display component list
    Write-Output "`nComponent List:"
    Write-Output "-----------------------------------------------------------"
    Write-Output "| Type | Name | Status | MVP | Description |"
    Write-Output "-----------------------------------------------------------"
    
    foreach ($component in $components) {
        $statusColor = Get-StatusColor -Status $component.Status
        $mvpIndicator = if ($component.InMVP) { "[X]" } else { "[ ]" }
        
        Write-Output "| $($component.Type.PadRight(12)) | $($component.Name.PadRight(20)) |" -NoNewline
        Write-ColorOutput " $($component.Status.PadRight(12)) " -ForegroundColor $statusColor
        Write-Output "| $mvpIndicator | $($component.Description) |"
    }
    
    Write-Output "-----------------------------------------------------------"
    
    # Display module details
    Write-Output "`nModule Details:"
    foreach ($moduleName in $IndexData.modules.PSObject.Properties.Name) {
        $module = $IndexData.modules.$moduleName
        if (-not $ShowExtendedComponents -and -not $module.inMVP) { continue }
        
        $statusColor = Get-StatusColor -Status $module.status
        Write-Output "`n[$moduleName]" -NoNewline
        Write-ColorOutput " ($($module.status))" -ForegroundColor $statusColor
        Write-Output "  Path: $($module.path)"
        Write-Output "  Description: $($module.description)"
        
        if ($module.dependencies.Count -gt 0) {
            Write-Output "  Dependencies: $($module.dependencies -join ', ')"
        }
        
        Write-Output "  Features:"
        foreach ($feature in $module.features) {
            $featureStatusColor = Get-StatusColor -Status $feature.status
            Write-Output "    - $($feature.name):" -NoNewline
            Write-ColorOutput " $($feature.status)" -ForegroundColor $featureStatusColor
        }
    }
}

function Format-HtmlOutput {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$IndexData,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowExtendedComponents
    )
    
    $components = Get-ComponentList -IndexData $IndexData -MVPOnly:(-not $ShowExtendedComponents)
    $progressData = if ($ShowExtendedComponents) { $IndexData.extendedProgress } else { $IndexData.mvpProgress }
    
    $statusColors = @{
        'Implemented' = '#4CAF50'
        'Partial' = '#FFC107'
        'Planned' = '#2196F3'
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$($IndexData.project.name) - Project Status</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2, h3 { color: #333; }
        .header { background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .progress-container { width: 100%; background-color: #e0e0e0; border-radius: 5px; margin: 15px 0; }
        .progress-bar { height: 25px; background-color: #4CAF50; border-radius: 5px; text-align: center; color: white; line-height: 25px; }
        .summary { display: flex; justify-content: space-between; max-width: 600px; }
        .summary-item { padding: 10px; text-align: center; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .status-Implemented { background-color: #4CAF50; color: white; padding: 3px 8px; border-radius: 3px; }
        .status-Partial { background-color: #FFC107; padding: 3px 8px; border-radius: 3px; }
        .status-Planned { background-color: #2196F3; color: white; padding: 3px 8px; border-radius: 3px; }
        .mvp-true { color: green; font-weight: bold; }
        .mvp-false { color: gray; }
        .module-details { margin-top: 30px; }
        .module-header { background-color: #f5f5f5; padding: 10px; border-radius: 5px; margin-bottom: 10px; }
        .module-content { margin-left: 20px; margin-bottom: 20px; }
        .feature-list { margin-top: 10px; }
        .feature-item { margin: 5px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>$($IndexData.project.name) - v$($IndexData.project.version)</h1>
        <p><strong>Status:</strong> $($IndexData.project.status)</p>
        <p><strong>Last Updated:</strong> $($IndexData.project.lastUpdated)</p>
    </div>
    
    <h2>Overall Progress: $($progressData.percentComplete)%</h2>
    <div class="progress-container">
        <div class="progress-bar" style="width: $($progressData.percentComplete)%">$($progressData.percentComplete)%</div>
    </div>
    
    <div class="summary">
        <div class="summary-item"><strong>Total Components</strong><br>$($progressData.totalComponents)</div>
        <div class="summary-item" style="color: #4CAF50"><strong>Implemented</strong><br>$($progressData.implemented)</div>
        <div class="summary-item" style="color: #FFC107"><strong>Partial</strong><br>$($progressData.partial)</div>
        <div class="summary-item" style="color: #2196F3"><strong>Planned</strong><br>$($progressData.planned)</div>
    </div>
    
    <h2>Component List</h2>
    <table>
        <tr>
            <th>Type</th>
            <th>Name</th>
            <th>Status</th>
            <th>MVP</th>
            <th>Description</th>
        </tr>
"@

    foreach ($component in $components) {
        $mvpClass = if ($component.InMVP) { "mvp-true" } else { "mvp-false" }
        $mvpText = if ($component.InMVP) { "Yes" } else { "No" }
        
        $html += @"
        <tr>
            <td>$($component.Type)</td>
            <td>$($component.Name)</td>
            <td><span class="status-$($component.Status)">$($component.Status)</span></td>
            <td class="$mvpClass">$mvpText</td>
            <td>$($component.Description)</td>
        </tr>
"@
    }

    $html += @"
    </table>
    
    <h2>Module Details</h2>
    <div class="module-details">
"@

    foreach ($moduleName in $IndexData.modules.PSObject.Properties.Name) {
        $module = $IndexData.modules.$moduleName
        if (-not $ShowExtendedComponents -and -not $module.inMVP) { continue }
        
        $html += @"
        <div class="module-header">
            <h3>$moduleName <span class="status-$($module.status)">$($module.status)</span></h3>
        </div>
        <div class="module-content">
            <p><strong>Path:</strong> $($module.path)</p>
            <p><strong>Description:</strong> $($module.description)</p>
"@

        if ($module.dependencies.Count -gt 0) {
            $html += @"
            <p><strong>Dependencies:</strong> $($module.dependencies -join ', ')</p>
"@
        }

        $html += @"
            <div class="feature-list">
                <p><strong>Features:</strong></p>
                <ul>
"@

        foreach ($feature in $module.features) {
            $html += @"
                    <li class="feature-item">$($feature.name): <span class="status-$($feature.status)">$($feature.status)</span></li>
"@
        }

        $html += @"
                </ul>
            </div>
        </div>
"@
    }

    $html += @"
    </div>
</body>
</html>
"@

    return $html
}

# Main script execution
try {
    # Check if index file exists
    if (-not (Test-Path -Path $IndexPath)) {
        Write-Error "Index file not found at $IndexPath"
        exit 1
    }
    
    # Read index file
    $indexJson = Get-Content -Path $IndexPath -Raw
    $indexData = $indexJson | ConvertFrom-Json
    
    # Generate output based on format
    switch ($OutputFormat) {
        'Console' {
            Format-ConsoleOutput -IndexData $indexData -ShowExtendedComponents:$ShowExtendedComponents
        }
        'HTML' {
            $html = Format-HtmlOutput -IndexData $indexData -ShowExtendedComponents:$ShowExtendedComponents
            
            if ($OutputPath) {
                $html | Out-File -FilePath $OutputPath -Encoding utf8
                Write-Output "HTML report saved to $OutputPath"
            } else {
                $html
            }
        }
        'JSON' {
            if ($OutputPath) {
                $indexJson | Out-File -FilePath $OutputPath -Encoding utf8
                Write-Output "JSON report saved to $OutputPath"
            } else {
                $indexJson
            }
        }
    }
}
catch {
    Write-Error "Error generating project status: $_"
    exit 1
} 