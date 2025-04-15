# Windows 10/11 Script Validation Tool

## Overview

The Script Validation Tool (`ValidateScripts.ps1`) is designed to analyze PowerShell scripts for potential compatibility issues when running on Windows 10 and Windows 11 systems. It performs static code analysis to identify patterns, commands, and techniques that may behave differently across Windows versions.

## Purpose

This tool helps identify potential issues before deploying scripts to production environments by:

1. Detecting cmdlets that may behave differently across Windows versions
2. Identifying registry paths that may vary between OS versions
3. Highlighting module dependencies that may not be available on all systems
4. Checking for deprecated commands and techniques
5. Flagging hardcoded system paths that could cause issues
6. Identifying file encoding problems
7. Detecting administrative privilege requirements

## Usage

To use the validation tool:

```powershell
.\ValidateScripts.ps1
```

The tool will:
1. Scan all PowerShell scripts (*.ps1) in the current directory and subdirectories
2. Analyze each script for potential compatibility issues
3. Generate an HTML report with findings categorized by severity
4. Open the report in your default browser (if issues are found)

## Report Content

The HTML report includes:

- **System Information**: Details about the current OS version
- **Summary**: Total counts of critical issues, warnings, and information items
- **Issue Details**: Categorized tables of all detected issues
- **Recommendations**: Suggested best practices for Windows 10/11 compatibility

## Issue Categories

### Critical Issues

Critical issues are problems that will likely cause script execution failures:
- Analysis errors during script validation
- Syntax errors or invalid PowerShell constructs

### Warnings

Warnings are potential compatibility issues that might cause problems:
- Cmdlets with different behavior across Windows versions
- Registry paths that vary between Windows versions
- Module dependencies that may not be available
- Deprecated commands (like WMI cmdlets)
- Hardcoded system paths
- File encoding issues
- Execution policy modifications
- Scheduled task manipulations

### Information Items

Information items are notes about techniques that may require special consideration:
- Administrative privilege requirements
- .NET Framework dependencies
- PowerShell version requirements

## Validation Checks

The validation tool performs the following checks on each script:

### Cmdlet Compatibility

The tool checks for cmdlets that may behave differently across Windows versions, including:
- AppX package management commands (Add-AppxPackage, Get-AppxPackage)
- Windows feature management (Get-WindowsCapability, Get-WindowsOptionalFeature)
- CIM commands with OS-specific classes
- Registry manipulation commands

### Registry Path Validation

The tool checks for registry paths that are known to vary between Windows versions:
- Windows Update registry locations
- User profile registry paths
- Authentication-related registry paths

### Module Dependency Analysis

The tool checks for dependencies on modules that may have compatibility issues:
- Microsoft.Graph.Intune
- WindowsAutoPilotIntune
- Provisioning module
- Microsoft Graph authentication modules

### Code Pattern Analysis

The tool scans for coding patterns that may cause compatibility issues:
- WMI queries (deprecated in favor of CIM)
- Direct .NET Framework calls
- Hardcoded system paths
- Execution policy modifications
- Scheduled task manipulations

### File Analysis

The tool examines file properties that may affect compatibility:
- File encoding (checking for non-UTF8/ASCII encodings)
- PowerShell version requirements (#Requires statements)

## Recommendations for Cross-Version Compatibility

1. **Use environment variables instead of hardcoded paths**:
   ```powershell
   # Instead of:
   $systemRoot = "C:\Windows\System32"
   
   # Use:
   $systemRoot = "$env:SystemRoot\System32"
   ```

2. **Use CIM cmdlets instead of WMI**:
   ```powershell
   # Instead of:
   Get-WmiObject -Class Win32_OperatingSystem
   
   # Use:
   Get-CimInstance -ClassName Win32_OperatingSystem
   ```

3. **Check for feature/cmdlet availability before use**:
   ```powershell
   if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
       # Use Get-WindowsCapability
   } else {
       # Alternative approach
   }
   ```

4. **Validate registry paths before accessing**:
   ```powershell
   $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication"
   if (Test-Path $regPath) {
       # Access registry path
   }
   ```

5. **Add proper error handling for OS-specific features**:
   ```powershell
   try {
       # OS-specific operation
   } catch {
       Write-Log -Message "This operation is not supported on this Windows version: $_" -Level WARNING
       # Alternative approach
   }
   ```

6. **Use PowerShell 5.1 compatible syntax** for maximum compatibility across Windows 10/11 versions.

7. **Test scripts on all target Windows versions** before deployment.

## Integration with Logging Module

The validation tool integrates with the `LoggingModule.psm1` to provide detailed logging of the validation process. This includes:

- Logging of all detected issues
- Task-based tracking of script analysis
- System information capture for context
- Detailed error reporting

## Extending the Tool

To add additional validation checks:

1. Add new patterns to the appropriate global lists:
   - `$script:PotentialProblemCmdlets`
   - `$script:ProblematicRegistryPaths`
   - `$script:PotentialProblemModules`

2. Create new validation functions and add them to the `Find-ScriptIssues` function.

3. Update the HTML report generation if new issue categories are added.

## Troubleshooting

If the tool fails to run:

1. Ensure PowerShell 5.1 or later is installed
2. Check that the LoggingModule.psm1 file is in the same directory
3. Verify you have permission to create the log directory (C:\Temp\Logs by default)
4. Run PowerShell with administrator privileges if accessing restricted files 