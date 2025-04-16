# Add-CrayonHeader.ps1
# Adds the Crayon ASCII header to all PowerShell scripts and modules in the project

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$BasePath = (Join-Path -Path $PSScriptRoot -ChildPath ".."),
    
    [Parameter(Mandatory = $false)]
    [string]$Author = "Jared Griego",
    
    [Parameter(Mandatory = $false)]
    [string]$Email = "jared.griego@crayon.com",
    
    [Parameter(Mandatory = $false)]
    [string]$RevisionNumber = "1.0",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

function Get-ScriptDescription {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )
    
    # Read the first 50 lines of the file to look for description
    $firstLines = Get-Content -Path $FilePath -TotalCount 50
    
    # Try to find comment-based help with synopsis or description
    $synopsisIndex = $firstLines | Select-String -Pattern "\.SYNOPSIS" | Select-Object -First 1 -ExpandProperty LineNumber
    if ($synopsisIndex) {
        $synopsisLine = $firstLines[$synopsisIndex]
        $nextLine = $firstLines[$synopsisIndex..($synopsisIndex+5)] | Where-Object { $_ -match "\S" -and $_ -notmatch "\.SYNOPSIS" } | Select-Object -First 1
        if ($nextLine -and $nextLine.Trim() -ne "") {
            return $nextLine.Trim()
        }
    }
    
    $descriptionIndex = $firstLines | Select-String -Pattern "\.DESCRIPTION" | Select-Object -First 1 -ExpandProperty LineNumber
    if ($descriptionIndex) {
        $descriptionLine = $firstLines[$descriptionIndex]
        $nextLine = $firstLines[$descriptionIndex..($descriptionIndex+5)] | Where-Object { $_ -match "\S" -and $_ -notmatch "\.DESCRIPTION" } | Select-Object -First 1
        if ($nextLine -and $nextLine.Trim() -ne "") {
            return $nextLine.Trim()
        }
    }

    # Check for function definitions and their names
    $functionMatch = $firstLines | Select-String -Pattern "function\s+(\w+-\w+)" | Select-Object -First 1
    if ($functionMatch) {
        $functionName = $functionMatch.Matches[0].Groups[1].Value
        return "PowerShell module providing $functionName function for Workspace ONE to Azure/Intune migration"
    }
    
    # Look for comment in first 5 lines
    $comment = $firstLines[0..5] | Where-Object { $_ -match "^#\s*[^#]" } | Select-Object -First 1
    if ($comment -and $comment -notmatch "#!/usr/bin/env") {
        return $comment.TrimStart("#").Trim()
    }
    
    # Default description based on filename
    switch -Regex ($ScriptName) {
        "AutopilotIntegration" { return "PowerShell module for registering devices with Microsoft Autopilot during migration" }
        "SecurityFoundation" { return "PowerShell module providing security functions for the migration toolkit" }
        "MigrationEngine" { return "PowerShell module for orchestrating the Workspace ONE to Azure/Intune migration" }
        "GraphAPIIntegration" { return "PowerShell module for interacting with Microsoft Graph API during migration" }
        "LoggingModule" { return "PowerShell module for centralized logging throughout the migration toolkit" }
        "BitLockerManager" { return "PowerShell module for managing BitLocker encryption during migration" }
        "UserProfileManager" { return "PowerShell module for handling user profiles during migration" }
        "^Test-" { return "PowerShell script for testing $($ScriptName -replace 'Test-', '') during migration" }
        "^Get-" { return "PowerShell script for retrieving $($ScriptName -replace 'Get-', '') during migration" }
        "^Set-" { return "PowerShell script for configuring $($ScriptName -replace 'Set-', '') during migration" }
        "^Invoke-" { return "PowerShell script for executing $($ScriptName -replace 'Invoke-', '') operations during migration" }
        default { return "PowerShell script for Workspace ONE to Azure/Intune migration" }
    }
}

function Add-HeaderToFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
    )
    
    $fileName = Split-Path -Path $FilePath -Leaf
    $fileContent = Get-Content -Path $FilePath -Raw
    
    # Check if the file already has a Crayon header
    if ($fileContent -match "Written by .* \| Crayon \|" -and -not $Force) {
        Write-Host "Skipping $fileName - header already exists (use -Force to replace)" -ForegroundColor Yellow
        return $false
    }
    
    # Create the header
    $currentDate = Get-Date -Format "M.dd.yyyy"
    
    $headerText = @"
################################################################################################################################
# Written by $Author | Crayon | $currentDate | Rev $RevisionNumber | $Email                                              #
#                                                                                                                              #
# $Description                            #
# PowerShell 5.1 x32/x64                                                                                                       #
#                                                                                                                              #
################################################################################################################################

################################################################################################################################
#     ______ .______          ___   ____    ____  ______   .__   __.     __    __       _______.     ___                       #
#    /      ||   _  \        /   \  \   \  /   / /  __  \  |  \ |  |    |  |  |  |     /       |    /   \                      #
#   |  ,----'|  |_)  |      /  ^  \  \   \/   / |  |  |  | |   \|  |    |  |  |  |    |   (----`   /  ^  \                     #
#   |  |     |      /      /  /_\  \  \_    _/  |  |  |  | |  . `  |    |  |  |  |     \   \      /  /_\  \                    #
#   |  `----.|  |\  \----./  _____  \   |  |    |  `--'  | |  |\   |    |  `--'  | .----)   |    /  _____  \                   #
#    \______|| _| `._____/__/     \__\  |__|     \______/  |__| \__|     \______/  |_______/    /__/     \__\                  #
#                                                                                                                              #
################################################################################################################################

"@

    # Handle special cases
    # Check if file starts with shebang (#!) or Requires for PowerShell
    $hasShebang = $fileContent -match "^#!"
    $hasRequires = $fileContent -match "^#Requires"
    
    $newContent = ""
    if ($hasShebang -or $hasRequires) {
        # Extract the first line(s)
        $lines = $fileContent -split "`n"
        $specialLines = @()
        
        foreach ($line in $lines) {
            if ($line -match "^#!" -or $line -match "^#Requires") {
                $specialLines += $line
            }
            else {
                break
            }
        }
        
        # Rebuild content with shebang/requires first, then header, then rest of file
        $specialContent = $specialLines -join "`n"
        $restOfContent = $fileContent.Substring($specialContent.Length)
        $newContent = $specialContent + "`n" + $headerText + $restOfContent
    }
    else {
        # Simply prepend header to file
        $newContent = $headerText + $fileContent
    }
    
    # Apply the changes or show what would change
    if ($WhatIf) {
        Write-Host "Would update header in: $fileName" -ForegroundColor Cyan
        Write-Host "New description: $Description" -ForegroundColor Cyan
    }
    else {
        try {
            Set-Content -Path $FilePath -Value $newContent -Encoding UTF8
            Write-Host "Updated header in: $fileName" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Error updating $fileName`: $_" -ForegroundColor Red
            return $false
        }
    }
    
    return $true
}

# Find all PowerShell files
$scriptFiles = Get-ChildItem -Path $BasePath -Include "*.ps1", "*.psm1" -Recurse | 
               Where-Object { $_.FullName -notmatch "\\\.git\\" -and $_.Name -ne "Add-CrayonHeader.ps1" }

Write-Host "Found $($scriptFiles.Count) PowerShell files to process" -ForegroundColor Blue

$processed = 0
$updated = 0

foreach ($file in $scriptFiles) {
    $processed++
    Write-Progress -Activity "Processing PowerShell Files" -Status "$processed of $($scriptFiles.Count)" -PercentComplete (($processed / $scriptFiles.Count) * 100)
    
    $fileName = $file.Name
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    
    # Get description for the script
    $description = Get-ScriptDescription -FilePath $file.FullName -ScriptName $scriptName
    
    # Make sure description is not too long (fits in header)
    if ($description.Length -gt 90) {
        $description = $description.Substring(0, 90) + "..."
    }
    
    # Pad the description to match the header width
    $paddedDescription = $description.PadRight(90)
    
    # Add header to the file
    $result = Add-HeaderToFile -FilePath $file.FullName -Description $paddedDescription -Force:$Force -WhatIf:$WhatIf
    if ($result) {
        $updated++
    }
}

Write-Progress -Activity "Processing PowerShell Files" -Completed

Write-Host "`nSummary:" -ForegroundColor Blue
Write-Host "Total files processed: $processed" -ForegroundColor White
Write-Host "Files updated: $updated" -ForegroundColor Green
Write-Host "Files skipped: $($processed - $updated)" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "`nThis was a simulation. Use without -WhatIf to apply changes." -ForegroundColor Cyan
} 