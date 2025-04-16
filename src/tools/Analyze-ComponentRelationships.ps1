<#
.SYNOPSIS
    Analyzes component relationships and generates insights and recommendations.

.DESCRIPTION
    This script analyzes the relationships between components in the migration solution,
    identifying potential issues, optimization opportunities, and generating reports
    based on the ComponentRelationships.json configuration.

.PARAMETER ConfigPath
    Path to the ComponentRelationships.json configuration file.
    Default: "..\config\ComponentRelationships.json"

.PARAMETER OutputPath
    Path where analysis reports will be saved.
    Default: "$env:TEMP\ComponentAnalysis"

.PARAMETER ReportTypes
    Types of reports to generate: DependencyGraph, RiskMatrix, PerformanceAnalysis, 
    OptimizationRecommendations, or All.
    Default: "All"

.EXAMPLE
    .\Analyze-ComponentRelationships.ps1
    Analyzes all component relationships and generates all report types.

.EXAMPLE
    .\Analyze-ComponentRelationships.ps1 -ReportTypes DependencyGraph,RiskMatrix
    Generates only dependency graph and risk matrix reports.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config\ComponentRelationships.json"),
    
    [Parameter()]
    [string]$OutputPath = "$env:TEMP\ComponentAnalysis",
    
    [Parameter()]
    [ValidateSet("DependencyGraph", "RiskMatrix", "PerformanceAnalysis", "OptimizationRecommendations", "All")]
    [string[]]$ReportTypes = @("All")
)

#region Helper Functions
function Initialize-AnalysisEnvironment {
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created output directory: $OutputPath"
    }
    
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Error "Configuration file not found: $ConfigPath"
        return $false
    }
    
    try {
        $script:Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded configuration from: $ConfigPath"
        return $true
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        return $false
    }
}

function Get-ComponentByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    return $script:Config.components | Where-Object { $_.name -eq $Name }
}

function Get-RelationshipByComponents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComponentA,
        
        [Parameter(Mandatory=$true)]
        [string]$ComponentB
    )
    
    return $script:Config.relationships | Where-Object { 
        ($_.componentA -eq $ComponentA -and $_.componentB -eq $ComponentB) -or
        ($_.componentA -eq $ComponentB -and $_.componentB -eq $ComponentA)
    }
}

function Get-ComponentDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComponentName
    )
    
    $component = Get-ComponentByName -Name $ComponentName
    if (-not $component) { return @() }
    
    $explicitDependencies = $component.dependencies
    
    $implicitDependencies = $script:Config.relationships | 
        Where-Object { $_.componentA -eq $ComponentName } | 
        ForEach-Object { $_.componentB }
    
    return ($explicitDependencies + $implicitDependencies) | Select-Object -Unique
}

function Get-HighRiskRelationships {
    [CmdletBinding()]
    param()
    
    return $script:Config.relationships | Where-Object { 
        ($_.ics -ge 7) -or ($_.fip -eq "High")
    } | Sort-Object -Property { [int]$_.ics } -Descending
}

function Get-PerformanceCriticalComponents {
    [CmdletBinding()]
    param()
    
    # Components in sync relationships with high ICS are often performance-critical
    $syncComponents = $script:Config.relationships | 
        Where-Object { $_.rtd -eq "Sync" -and $_.ics -ge 5 } | 
        ForEach-Object { $_.componentA, $_.componentB } | 
        Select-Object -Unique
    
    # Add components explicitly marked in performance critical paths
    $pathComponents = $script:Config.riskAssessment.performanceCriticalPaths | 
        ForEach-Object { $_.path } | 
        ForEach-Object { $_ }
    
    return ($syncComponents + $pathComponents) | Select-Object -Unique
}

function Convert-FIPToNumeric {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FIP
    )
    
    switch ($FIP) {
        "Low" { return 1 }
        "Medium" { return 2 }
        "High" { return 3 }
        default { return 0 }
    }
}

function Calculate-RelationshipRiskScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Relationship
    )
    
    $icsWeight = 0.3
    $fipWeight = 0.5
    $complexityWeight = 0.2
    
    $ics = [int]$Relationship.ics
    $fipFactor = Convert-FIPToNumeric -FIP $Relationship.fip
    
    # Estimate complexity based on integration points
    $complexityFactor = if ($Relationship.integrationPoints.Count -le 1) { 1 }
                         elseif ($Relationship.integrationPoints.Count -le 3) { 2 }
                         else { 3 }
    
    $riskScore = ($ics / 10 * $icsWeight) + 
                 ($fipFactor / 3 * $fipWeight) + 
                 ($complexityFactor / 3 * $complexityWeight)
    
    return [math]::Round($riskScore * 3, 1) # Scale to 0-3 range
}
#endregion

#region Report Generation Functions
function Generate-DependencyGraphReport {
    [CmdletBinding()]
    param()
    
    $reportPath = Join-Path -Path $OutputPath -ChildPath "DependencyGraph.txt"
    
    # Generate dependency graph in text format
    $graph = "Component Dependency Graph`n"
    $graph += "========================`n`n"
    
    foreach ($component in $script:Config.components) {
        $dependencies = Get-ComponentDependencies -ComponentName $component.name
        
        $graph += "$($component.name) [Critical Level: $($component.criticalLevel)]`n"
        
        if ($dependencies.Count -gt 0) {
            $graph += "  Dependencies:`n"
            foreach ($dep in $dependencies) {
                $relationship = Get-RelationshipByComponents -ComponentA $component.name -ComponentB $dep
                $description = if ($relationship) { " - $($relationship.description)" } else { "" }
                $graph += "    ├─ $dep$description`n"
            }
        } else {
            $graph += "  Dependencies: None`n"
        }
        
        # Find components that depend on this one
        $dependents = $script:Config.components | 
            Where-Object { $_.dependencies -contains $component.name } | 
            ForEach-Object { $_.name }
        
        $implicitDependents = $script:Config.relationships | 
            Where-Object { $_.componentB -eq $component.name } | 
            ForEach-Object { $_.componentA }
        
        $allDependents = ($dependents + $implicitDependents) | Select-Object -Unique
        
        if ($allDependents.Count -gt 0) {
            $graph += "  Dependents:`n"
            foreach ($dep in $allDependents) {
                $graph += "    ├─ $dep`n"
            }
        } else {
            $graph += "  Dependents: None`n"
        }
        
        $graph += "`n"
    }
    
    # Add cyclic dependency analysis
    $graph += "Cyclic Dependency Analysis`n"
    $graph += "==========================`n`n"
    
    $cycles = @()
    
    # Simple cycle detection (for direct A->B->A cycles)
    foreach ($componentA in $script:Config.components.name) {
        $depA = Get-ComponentDependencies -ComponentName $componentA
        
        foreach ($componentB in $depA) {
            $depB = Get-ComponentDependencies -ComponentName $componentB
            
            if ($depB -contains $componentA) {
                $cycles += "$componentA <-> $componentB"
            }
        }
    }
    
    if ($cycles.Count -gt 0) {
        $graph += "Potential cyclic dependencies detected:`n"
        foreach ($cycle in $cycles) {
            $graph += "  $cycle`n"
        }
    } else {
        $graph += "No cyclic dependencies detected.`n"
    }
    
    $graph | Out-File -FilePath $reportPath -Encoding utf8
    
    Write-Host "Dependency graph report generated: $reportPath"
    
    return $reportPath
}

function Generate-RiskMatrixReport {
    [CmdletBinding()]
    param()
    
    $reportPath = Join-Path -Path $OutputPath -ChildPath "RiskMatrix.txt"
    
    # Generate risk matrix report
    $matrix = "Component Relationship Risk Matrix`n"
    $matrix += "==============================`n`n"
    
    # Calculate risk scores for all relationships
    $relationshipsWithRisk = $script:Config.relationships | ForEach-Object {
        $riskScore = Calculate-RelationshipRiskScore -Relationship $_
        
        [PSCustomObject]@{
            ComponentA = $_.componentA
            ComponentB = $_.componentB
            ICS = $_.ics
            FIP = $_.fip
            RTD = $_.rtd
            RiskScore = $riskScore
            Description = $_.description
        }
    } | Sort-Object -Property RiskScore -Descending
    
    # High risk relationships (score >= 2.0)
    $matrix += "High Risk Relationships (Risk Score >= 2.0)`n"
    $matrix += "----------------------------------------`n"
    $highRisk = $relationshipsWithRisk | Where-Object { $_.RiskScore -ge 2.0 }
    
    if ($highRisk.Count -gt 0) {
        foreach ($rel in $highRisk) {
            $matrix += "[$($rel.ComponentA)] <-> [$($rel.ComponentB)]`n"
            $matrix += "  Risk Score: $($rel.RiskScore) | ICS: $($rel.ICS) | FIP: $($rel.FIP) | RTD: $($rel.RTD)`n"
            $matrix += "  Description: $($rel.Description)`n"
            
            # Add mitigation from risk assessment if available
            $riskInfo = $script:Config.riskAssessment.highRiskRelationships | 
                Where-Object { $_.relationship -eq "$($rel.ComponentA)-$($rel.ComponentB)" -or 
                               $_.relationship -eq "$($rel.ComponentB)-$($rel.ComponentA)" }
            
            if ($riskInfo) {
                $matrix += "  Mitigation: $($riskInfo.mitigationStrategy)`n"
            } else {
                $matrix += "  Mitigation: No specific strategy defined`n"
            }
            
            $matrix += "`n"
        }
    } else {
        $matrix += "  No high risk relationships found.`n`n"
    }
    
    # Medium risk relationships (1.0 <= score < 2.0)
    $matrix += "Medium Risk Relationships (1.0 <= Risk Score < 2.0)`n"
    $matrix += "-----------------------------------------------`n"
    $mediumRisk = $relationshipsWithRisk | Where-Object { $_.RiskScore -ge 1.0 -and $_.RiskScore -lt 2.0 }
    
    if ($mediumRisk.Count -gt 0) {
        foreach ($rel in $mediumRisk) {
            $matrix += "[$($rel.ComponentA)] <-> [$($rel.ComponentB)]`n"
            $matrix += "  Risk Score: $($rel.RiskScore) | ICS: $($rel.ICS) | FIP: $($rel.FIP) | RTD: $($rel.RTD)`n"
            $matrix += "  Description: $($rel.Description)`n`n"
        }
    } else {
        $matrix += "  No medium risk relationships found.`n`n"
    }
    
    # Risk summary by component
    $matrix += "Risk Summary by Component`n"
    $matrix += "------------------------`n"
    
    foreach ($component in $script:Config.components) {
        $componentRelationships = $relationshipsWithRisk | Where-Object { 
            $_.ComponentA -eq $component.name -or $_.ComponentB -eq $component.name 
        }
        
        $averageRisk = if ($componentRelationships.Count -gt 0) {
            [math]::Round(($componentRelationships | Measure-Object -Property RiskScore -Average).Average, 2)
        } else {
            0
        }
        
        $highestRisk = if ($componentRelationships.Count -gt 0) {
            ($componentRelationships | Measure-Object -Property RiskScore -Maximum).Maximum
        } else {
            0
        }
        
        $matrix += "$($component.name)`n"
        $matrix += "  Critical Level: $($component.criticalLevel)`n"
        $matrix += "  Average Risk Score: $averageRisk`n"
        $matrix += "  Highest Risk Relationship: $highestRisk`n"
        $matrix += "  Number of Relationships: $($componentRelationships.Count)`n`n"
    }
    
    $matrix | Out-File -FilePath $reportPath -Encoding utf8
    
    Write-Host "Risk matrix report generated: $reportPath"
    
    return $reportPath
}

function Generate-PerformanceAnalysisReport {
    [CmdletBinding()]
    param()
    
    $reportPath = Join-Path -Path $OutputPath -ChildPath "PerformanceAnalysis.txt"
    
    # Generate performance analysis report
    $analysis = "Component Performance Analysis`n"
    $analysis += "============================`n`n"
    
    # Identify performance-critical components
    $perfComponents = Get-PerformanceCriticalComponents
    
    $analysis += "Performance-Critical Components`n"
    $analysis += "-----------------------------`n"
    
    foreach ($component in $perfComponents) {
        $componentInfo = Get-ComponentByName -Name $component
        $analysis += "$component`n"
        
        # Get synchronous relationships
        $syncRelationships = $script:Config.relationships | Where-Object { 
            ($_.componentA -eq $component -or $_.componentB -eq $component) -and
            $_.rtd -eq "Sync"
        }
        
        if ($syncRelationships.Count -gt 0) {
            $analysis += "  Synchronous Relationships:`n"
            foreach ($rel in $syncRelationships) {
                $otherComponent = if ($rel.componentA -eq $component) { $rel.componentB } else { $rel.componentA }
                $analysis += "    ├─ With $otherComponent (ICS: $($rel.ics))`n"
            }
        }
        
        # Find in critical paths
        $criticalPaths = $script:Config.riskAssessment.performanceCriticalPaths | 
            Where-Object { $_.path -contains $component }
        
        if ($criticalPaths.Count -gt 0) {
            $analysis += "  Critical Paths:`n"
            foreach ($path in $criticalPaths) {
                $pathStr = $path.path -join " -> "
                $analysis += "    ├─ $pathStr`n"
                $analysis += "      Optimization: $($path.optimizationOpportunities)`n"
            }
        }
        
        $analysis += "`n"
    }
    
    # Performance test coverage
    $analysis += "Performance Test Coverage`n"
    $analysis += "-----------------------`n"
    
    foreach ($test in $script:Config.testCoverage.performanceTests) {
        $analysis += "$($test.name)`n"
        $analysis += "  Description: $($test.description)`n"
        $analysis += "  Thresholds:`n"
        
        foreach ($threshold in $test.thresholds.PSObject.Properties) {
            $analysis += "    ├─ $($threshold.Name): $($threshold.Value)`n"
        }
        
        $analysis += "`n"
    }
    
    # Response time dependencies analysis
    $analysis += "Response Time Dependencies`n"
    $analysis += "------------------------`n"
    
    $syncCount = ($script:Config.relationships | Where-Object { $_.rtd -eq "Sync" }).Count
    $asyncCount = ($script:Config.relationships | Where-Object { $_.rtd -eq "Async" }).Count
    $hybridCount = ($script:Config.relationships | Where-Object { $_.rtd -eq "Hybrid" }).Count
    
    $analysis += "Synchronous Relationships: $syncCount`n"
    $analysis += "Asynchronous Relationships: $asyncCount`n"
    $analysis += "Hybrid Relationships: $hybridCount`n`n"
    
    $analysis += "Synchronous Chain Analysis:`n"
    
    # Identify chains of synchronous dependencies
    $chains = @()
    $visited = @{}
    
    foreach ($component in $script:Config.components.name) {
        $visited.Clear()
        $chain = @($component)
        Find-SyncChain -Component $component -Chain $chain -Visited $visited -Chains ([ref]$chains)
    }
    
    # Sort chains by length (longest first)
    $sortedChains = $chains | Sort-Object -Property { $_.Count } -Descending
    
    foreach ($chain in $sortedChains | Select-Object -First 5) {
        $analysis += "  " + ($chain -join " -> ") + "`n"
    }
    
    $analysis | Out-File -FilePath $reportPath -Encoding utf8
    
    Write-Host "Performance analysis report generated: $reportPath"
    
    return $reportPath
}

function Find-SyncChain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Component,
        
        [Parameter(Mandatory=$true)]
        [string[]]$Chain,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Visited,
        
        [Parameter(Mandatory=$true)]
        [ref]$Chains
    )
    
    $Visited[$Component] = $true
    
    $syncDependencies = $script:Config.relationships | 
        Where-Object { 
            $_.componentA -eq $Component -and 
            $_.rtd -eq "Sync" -and 
            -not $Visited.ContainsKey($_.componentB)
        } | 
        ForEach-Object { $_.componentB }
    
    if ($syncDependencies.Count -eq 0) {
        # End of chain
        if ($Chain.Count -gt 1) {
            $Chains.Value += ,@($Chain)
        }
    } else {
        foreach ($dep in $syncDependencies) {
            $newChain = $Chain + $dep
            Find-SyncChain -Component $dep -Chain $newChain -Visited $Visited -Chains $Chains
        }
    }
    
    # Remove from visited to allow exploration of other paths
    $Visited.Remove($Component)
}

function Generate-OptimizationRecommendationsReport {
    [CmdletBinding()]
    param()
    
    $reportPath = Join-Path -Path $OutputPath -ChildPath "OptimizationRecommendations.txt"
    
    # Generate optimization recommendations report
    $recommendations = "Component Relationship Optimization Recommendations`n"
    $recommendations += "=============================================`n`n"
    
    # High-level recommendations
    $recommendations += "High-Level Recommendations`n"
    $recommendations += "-------------------------`n"
    
    # Calculate metrics for analysis
    $syncCount = ($script:Config.relationships | Where-Object { $_.rtd -eq "Sync" }).Count
    $totalRelationships = $script:Config.relationships.Count
    $syncPercentage = [math]::Round(($syncCount / $totalRelationships) * 100, 1)
    
    $highICSCount = ($script:Config.relationships | Where-Object { [int]$_.ics -ge 7 }).Count
    $highICSPercentage = [math]::Round(($highICSCount / $totalRelationships) * 100, 1)
    
    $highFIPCount = ($script:Config.relationships | Where-Object { $_.fip -eq "High" }).Count
    $highFIPPercentage = [math]::Round(($highFIPCount / $totalRelationships) * 100, 1)
    
    # Provide overall assessment
    if ($syncPercentage -gt 50) {
        $recommendations += "1. Reduce Synchronous Dependencies (Currently $syncPercentage% of relationships)`n"
        $recommendations += "   - Consider converting appropriate synchronous operations to asynchronous where possible`n"
        $recommendations += "   - Implement message queuing for non-critical operations`n"
        $recommendations += "   - Use background processing for verification and reporting tasks`n`n"
    }
    
    if ($highICSPercentage -gt 30) {
        $recommendations += "2. Reduce Tight Coupling (Currently $highICSPercentage% with ICS >= 7)`n"
        $recommendations += "   - Implement well-defined interfaces between components`n"
        $recommendations += "   - Consider a mediator pattern for highly connected components`n"
        $recommendations += "   - Use event-based communication where appropriate`n`n"
    }
    
    if ($highFIPPercentage -gt 20) {
        $recommendations += "3. Mitigate Failure Propagation (Currently $highFIPPercentage% with High FIP)`n"
        $recommendations += "   - Add circuit breakers to prevent cascading failures`n"
        $recommendations += "   - Implement retry mechanisms with exponential backoff`n"
        $recommendations += "   - Create fallback mechanisms for critical operations`n`n"
    }
    
    # Component-specific recommendations
    $recommendations += "Component-Specific Recommendations`n"
    $recommendations += "-------------------------------`n"
    
    foreach ($component in $script:Config.components) {
        $componentRels = $script:Config.relationships | Where-Object { 
            $_.componentA -eq $component.name -or $_.componentB -eq $component.name 
        }
        
        $syncRels = $componentRels | Where-Object { $_.rtd -eq "Sync" }
        $highICSRels = $componentRels | Where-Object { [int]$_.ics -ge 7 }
        $highFIPRels = $componentRels | Where-Object { $_.fip -eq "High" }
        
        if ($syncRels.Count -gt 0 -or $highICSRels.Count -gt 0 -or $highFIPRels.Count -gt 0) {
            $recommendations += "$($component.name)`n"
            
            if ($syncRels.Count -gt 0) {
                $recommendations += "  Synchronous Relationship Recommendations:`n"
                foreach ($rel in $syncRels) {
                    $otherComponent = if ($rel.componentA -eq $component.name) { $rel.componentB } else { $rel.componentA }
                    $recommendations += "    ├─ With $otherComponent: "
                    
                    # Suggest appropriate optimizations based on the components involved
                    switch ("$($component.name)-$otherComponent") {
                        { $_ -like "*RollbackMechanism*" } {
                            $recommendations += "Consider asynchronous backup operations with transaction logging`n"
                        }
                        { $_ -like "*ProfileTransfer*" } {
                            $recommendations += "Implement staged transfers with progress callbacks rather than blocking calls`n"
                        }
                        { $_ -like "*Verification*" } {
                            $recommendations += "Move verification to a background process with status polling`n"
                        }
                        default {
                            $recommendations += "Evaluate for conversion to asynchronous pattern`n"
                        }
                    }
                }
            }
            
            if ($highICSRels.Count -gt 0) {
                $recommendations += "  Coupling Reduction Recommendations:`n"
                foreach ($rel in $highICSRels) {
                    $otherComponent = if ($rel.componentA -eq $component.name) { $rel.componentB } else { $rel.componentA }
                    $recommendations += "    ├─ With $otherComponent (ICS: $($rel.ics)): "
                    
                    # Suggest decoupling strategies
                    switch ("$($component.name)-$otherComponent") {
                        { $_ -like "*RollbackMechanism*ProfileTransfer*" } {
                            $recommendations += "Define clear transaction boundaries and standardized data contracts`n"
                        }
                        default {
                            $recommendations += "Consider interface-based design with looser coupling`n"
                        }
                    }
                }
            }
            
            $recommendations += "`n"
        }
    }
    
    # Architectural recommendations
    $recommendations += "Architectural Improvement Recommendations`n"
    $recommendations += "-------------------------------------`n"
    
    # Analyze module structure for architectural recommendations
    $centralComponents = $script:Config.components | 
        Where-Object { 
            ($script:Config.relationships | 
             Where-Object { $_.componentA -eq $_.name -or $_.componentB -eq $_.name }).Count -ge 3
        } | 
        ForEach-Object { $_.name }
    
    if ($centralComponents.Count -gt 0) {
        $recommendations += "Consider these architectural improvements:`n`n"
        
        $recommendations += "1. Message Bus / Event System`n"
        $recommendations += "   - Components with many relationships could benefit from event-based communication`n"
        $recommendations += "   - Central components that would benefit: $($centralComponents -join ', ')`n`n"
        
        $recommendations += "2. Mediator Pattern`n"
        $recommendations += "   - Reduce direct dependencies between components with a mediator`n"
        $recommendations += "   - Most beneficial for: $($centralComponents[0]), $($centralComponents[1])`n`n"
        
        $recommendations += "3. Enhanced Logging and Monitoring`n"
        $recommendations += "   - Add relationship-specific telemetry to track component interaction health`n"
        $recommendations += "   - Focus on high-risk relationships first`n`n"
    }
    
    $recommendations | Out-File -FilePath $reportPath -Encoding utf8
    
    Write-Host "Optimization recommendations report generated: $reportPath"
    
    return $reportPath
}
#endregion

#region Main Execution
# Initialize environment
$initialized = Initialize-AnalysisEnvironment
if (-not $initialized) {
    exit 1
}

# Generate selected reports
if ($ReportTypes -contains "All" -or $ReportTypes -contains "DependencyGraph") {
    $depGraphReport = Generate-DependencyGraphReport
}

if ($ReportTypes -contains "All" -or $ReportTypes -contains "RiskMatrix") {
    $riskMatrixReport = Generate-RiskMatrixReport
}

if ($ReportTypes -contains "All" -or $ReportTypes -contains "PerformanceAnalysis") {
    $perfReport = Generate-PerformanceAnalysisReport
}

if ($ReportTypes -contains "All" -or $ReportTypes -contains "OptimizationRecommendations") {
    $optReport = Generate-OptimizationRecommendationsReport
}

# Display summary
Write-Host "`nComponent Relationship Analysis Complete" -ForegroundColor Green
Write-Host "Reports generated in: $OutputPath"

# Return report paths
[PSCustomObject]@{
    DependencyGraph = if (Get-Variable -Name depGraphReport -ErrorAction SilentlyContinue) { $depGraphReport } else { $null }
    RiskMatrix = if (Get-Variable -Name riskMatrixReport -ErrorAction SilentlyContinue) { $riskMatrixReport } else { $null }
    PerformanceAnalysis = if (Get-Variable -Name perfReport -ErrorAction SilentlyContinue) { $perfReport } else { $null }
    OptimizationRecommendations = if (Get-Variable -Name optReport -ErrorAction SilentlyContinue) { $optReport } else { $null }
    OutputPath = $OutputPath
}
#endregion 