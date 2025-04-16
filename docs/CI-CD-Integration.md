![Crayon Logo](../assests/img/Crayon-Logo-RGB-Negative.svg)

# CI/CD Integration for Migration Project

This document outlines how the Workspace ONE to Azure/Intune migration project integrates with CI/CD pipelines to ensure consistent, automated testing and deployment.

## Overview

The migration solution incorporates CI/CD practices to:

- Validate component functionality through automated testing
- Ensure consistent builds across environments
- Enable reliable, repeatable deployments
- Provide visibility into build and test status
- Support rapid iteration during development

## CI/CD Pipeline Architecture

The CI/CD pipeline for this migration solution consists of the following stages:

1. **Source Control**: Code stored in Git repository
2. **Build**: Components are built and packaged
3. **Test**: Automated tests validate functionality
4. **Validation**: Pre-deployment validation in test environment
5. **Deployment**: Controlled rollout to production
6. **Monitoring**: Post-deployment verification

## Pipeline Implementation

### Azure DevOps Pipeline

```yaml
trigger:
  branches:
    include:
    - main
    - develop
  paths:
    include:
    - src/**
    - tests/**

pool:
  vmImage: 'windows-latest'

stages:
- stage: Build
  jobs:
  - job: BuildPackage
    steps:
    - task: PowerShell@2
      displayName: 'Install Required Modules'
      inputs:
        targetType: 'inline'
        script: |
          Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
          Install-Module -Name Pester -Force -Scope CurrentUser
          Install-Module -Name IntuneBackupAndRestore -Force -Scope CurrentUser
    
    - task: PowerShell@2
      displayName: 'Run PSScriptAnalyzer'
      inputs:
        targetType: 'inline'
        script: |
          $results = Invoke-ScriptAnalyzer -Path $(Build.SourcesDirectory)/src -Recurse
          $errorCount = ($results | Where-Object { $_.Severity -eq 'Error' }).Count
          if ($errorCount -gt 0) {
            Write-Error "PSScriptAnalyzer found $errorCount errors"
            $results | Format-Table -AutoSize
            exit 1
          }
          $results | Format-Table -AutoSize
    
    - task: PowerShell@2
      displayName: 'Create Migration Solution Package'
      inputs:
        targetType: 'filePath'
        filePath: '$(Build.SourcesDirectory)/tools/Build-MigrationPackage.ps1'
        arguments: '-OutputPath "$(Build.ArtifactStagingDirectory)/MigrationSolution" -Version "$(Build.BuildNumber)"'
    
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Migration Solution Package'
      inputs:
        pathToPublish: '$(Build.ArtifactStagingDirectory)/MigrationSolution'
        artifactName: 'MigrationSolution'

- stage: Test
  dependsOn: Build
  jobs:
  - job: UnitTests
    steps:
    - task: DownloadBuildArtifacts@0
      inputs:
        buildType: 'current'
        downloadType: 'single'
        artifactName: 'MigrationSolution'
        downloadPath: '$(System.ArtifactsDirectory)'
    
    - task: PowerShell@2
      displayName: 'Run Unit Tests'
      inputs:
        targetType: 'filePath'
        filePath: '$(Build.SourcesDirectory)/tests/Invoke-UnitTests.ps1'
        arguments: '-ArtifactPath "$(System.ArtifactsDirectory)/MigrationSolution"'
    
    - task: PublishTestResults@2
      inputs:
        testResultsFormat: 'NUnit'
        testResultsFiles: '$(Build.SourcesDirectory)/tests/TestResults/UnitTests.xml'
        mergeTestResults: true
        testRunTitle: 'Unit Tests'

  - job: IntegrationTests
    steps:
    - task: DownloadBuildArtifacts@0
      inputs:
        buildType: 'current'
        downloadType: 'single'
        artifactName: 'MigrationSolution'
        downloadPath: '$(System.ArtifactsDirectory)'
    
    - task: PowerShell@2
      displayName: 'Run Integration Tests'
      inputs:
        targetType: 'filePath'
        filePath: '$(Build.SourcesDirectory)/tests/Test-AllHighPriorityComponents.ps1'
        arguments: '-Mock -LogPath "$(Build.ArtifactStagingDirectory)/TestLogs" -ReportPath "$(Build.ArtifactStagingDirectory)/TestReports"'
        errorActionPreference: 'Continue'
    
    - task: PublishTestResults@2
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '$(Build.ArtifactStagingDirectory)/TestReports/*.xml'
        mergeTestResults: true
        testRunTitle: 'Integration Tests'
    
    - task: PublishBuildArtifacts@1
      inputs:
        pathToPublish: '$(Build.ArtifactStagingDirectory)/TestReports'
        artifactName: 'TestReports'

- stage: Validation
  dependsOn: Test
  condition: succeeded()
  jobs:
  - job: DeployToTest
    steps:
    - task: DownloadBuildArtifacts@0
      inputs:
        buildType: 'current'
        downloadType: 'single'
        artifactName: 'MigrationSolution'
        downloadPath: '$(System.ArtifactsDirectory)'
    
    - task: PowerShell@2
      displayName: 'Deploy to Test Environment'
      inputs:
        targetType: 'filePath'
        filePath: '$(Build.SourcesDirectory)/tools/Deploy-MigrationSolution.ps1'
        arguments: '-PackagePath "$(System.ArtifactsDirectory)/MigrationSolution" -Environment "Test" -ConfigPath "$(Build.SourcesDirectory)/config/test.json"'
    
    - task: PowerShell@2
      displayName: 'Run Validation Tests'
      inputs:
        targetType: 'filePath'
        filePath: '$(Build.SourcesDirectory)/tests/Test-AllHighPriorityComponents.ps1'
        arguments: '-ComputerName "$(TestServer)" -ReportPath "$(Build.ArtifactStagingDirectory)/ValidationReports"'
    
    - task: PublishBuildArtifacts@1
      inputs:
        pathToPublish: '$(Build.ArtifactStagingDirectory)/ValidationReports'
        artifactName: 'ValidationReports'

- stage: Production
  dependsOn: Validation
  condition: succeeded()
  jobs:
  - deployment: DeployToProduction
    environment: Production
    strategy:
      runOnce:
        deploy:
          steps:
          - task: DownloadBuildArtifacts@0
            inputs:
              buildType: 'current'
              downloadType: 'single'
              artifactName: 'MigrationSolution'
              downloadPath: '$(System.ArtifactsDirectory)'
          
          - task: PowerShell@2
            displayName: 'Deploy to Production'
            inputs:
              targetType: 'filePath'
              filePath: '$(Build.SourcesDirectory)/tools/Deploy-MigrationSolution.ps1'
              arguments: '-PackagePath "$(System.ArtifactsDirectory)/MigrationSolution" -Environment "Production" -ConfigPath "$(Build.SourcesDirectory)/config/prod.json"'
```

## GitHub Actions Workflow

For projects using GitHub Actions instead of Azure DevOps:

```yaml
name: Migration Solution CI/CD

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'src/**'
      - 'tests/**'
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Install PowerShell modules
        shell: pwsh
        run: |
          Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
          Install-Module -Name Pester -Force -Scope CurrentUser
          Install-Module -Name IntuneBackupAndRestore -Force -Scope CurrentUser
      
      - name: Run PSScriptAnalyzer
        shell: pwsh
        run: |
          $results = Invoke-ScriptAnalyzer -Path ./src -Recurse
          $errorCount = ($results | Where-Object { $_.Severity -eq 'Error' }).Count
          if ($errorCount -gt 0) {
            Write-Error "PSScriptAnalyzer found $errorCount errors"
            $results | Format-Table -AutoSize
            exit 1
          }
          $results | Format-Table -AutoSize
      
      - name: Build package
        shell: pwsh
        run: ./tools/Build-MigrationPackage.ps1 -OutputPath "./artifacts" -Version "${{ github.run_number }}"
      
      - name: Upload artifact
        uses: actions/upload-artifact@v2
        with:
          name: MigrationSolution
          path: ./artifacts
  
  test:
    needs: build
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Download artifact
        uses: actions/download-artifact@v2
        with:
          name: MigrationSolution
          path: ./artifacts
      
      - name: Run unit tests
        shell: pwsh
        run: ./tests/Invoke-UnitTests.ps1 -ArtifactPath "./artifacts"
      
      - name: Run integration tests
        shell: pwsh
        run: ./tests/Test-AllHighPriorityComponents.ps1 -Mock -LogPath "./logs" -ReportPath "./reports"
      
      - name: Upload test results
        uses: actions/upload-artifact@v2
        with:
          name: TestReports
          path: ./reports
  
  deploy-test:
    if: github.ref == 'refs/heads/develop'
    needs: test
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Download artifact
        uses: actions/download-artifact@v2
        with:
          name: MigrationSolution
          path: ./artifacts
      
      - name: Deploy to test
        shell: pwsh
        run: ./tools/Deploy-MigrationSolution.ps1 -PackagePath "./artifacts" -Environment "Test" -ConfigPath "./config/test.json"
  
  deploy-prod:
    if: github.ref == 'refs/heads/main'
    needs: test
    runs-on: windows-latest
    environment: production
    steps:
      - uses: actions/checkout@v2
      
      - name: Download artifact
        uses: actions/download-artifact@v2
        with:
          name: MigrationSolution
          path: ./artifacts
      
      - name: Deploy to production
        shell: pwsh
        run: ./tools/Deploy-MigrationSolution.ps1 -PackagePath "./artifacts" -Environment "Production" -ConfigPath "./config/prod.json"
```

## Automated Tests in CI/CD

The pipeline includes several levels of testing:

1. **Static Analysis**: PSScriptAnalyzer checks code for quality issues
2. **Unit Tests**: Tests individual functions in isolation
3. **Integration Tests**: Tests interactions between components
4. **Mock Tests**: Tests using mock functions instead of real system changes
5. **Validation Tests**: Tests in a test environment simulating production

## Deployment Strategies

The solution supports multiple deployment strategies:

1. **Phased Rollout**: Deploy to increasingly larger groups of devices
2. **Blue/Green Deployment**: Maintain two environments and switch between them
3. **Canary Deployment**: Deploy to a small subset before full deployment

## Pipeline Variables and Secrets

The following variables should be configured in your CI/CD system:

| Variable | Description | Example |
|----------|-------------|---------|
| TestServer | Test server hostname | `migration-test-01` |
| ProdServers | Production server hostnames | `["migration-prod-01","migration-prod-02"]` |
| AzureClientId | Azure App Registration client ID | `00000000-0000-0000-0000-000000000000` |
| AzureClientSecret | Azure App Registration client secret | (Secure) |
| AzureTenantId | Azure tenant ID | `00000000-0000-0000-0000-000000000000` |

## Artifact Management

The CI/CD pipeline creates and manages the following artifacts:

1. **MigrationSolution Package**: The deployable solution package
2. **Unit Test Results**: Reports from unit tests
3. **Integration Test Reports**: Reports from integration tests
4. **Validation Reports**: Reports from validation tests

## Monitoring and Feedback

Post-deployment monitoring is integrated into the CI/CD pipeline:

1. **Telemetry Collection**: Solution sends telemetry to Azure Application Insights
2. **Error Monitoring**: Errors are collected and analyzed
3. **Usage Statistics**: Migration success rates and performance metrics

## Rollback Procedures

The CI/CD pipeline supports automated rollback if:

1. Tests fail in the validation environment
2. Monitoring detects migration failures above threshold
3. Manual approval for rollback is triggered

## Continuous Improvement

The CI/CD pipeline supports continuous improvement through:

1. **Test Coverage Reports**: Identify areas needing more tests
2. **Performance Metrics**: Identify performance bottlenecks
3. **Error Clustering**: Identify common failure patterns

## Conclusion

The CI/CD integration ensures that the migration solution is consistently tested, packaged, and deployed, reducing the risk of migration failures and providing a reliable pathway for introducing enhancements and fixes to the solution. 
