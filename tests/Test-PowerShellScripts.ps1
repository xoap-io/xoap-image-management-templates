<#
.SYNOPSIS
    Automated test runner for all PowerShell scripts

.DESCRIPTION
    Validates PowerShell scripts for syntax errors, executes dry-run tests,
    and reports any failures. Designed for CI/CD pipelines and local testing.

.PARAMETER Path
    Root path to search for PowerShell scripts (default: repository root)

.PARAMETER SkipExecution
    Only validate syntax, don't attempt execution

.PARAMETER ExcludePatterns
    Patterns to exclude from testing

.PARAMETER Verbose
    Show detailed output

.EXAMPLE
    .\Test-PowerShellScripts.ps1
    Tests all scripts in repository

.EXAMPLE
    .\Test-PowerShellScripts.ps1 -Path scripts/windows_server -SkipExecution
    Syntax check only for Windows Server scripts
#>

[CmdletBinding()]
param(
    [string]$Path = (Split-Path -Parent $PSScriptRoot),
    [switch]$SkipExecution,
    [string[]]$ExcludePatterns = @('*\node_modules\*', '*\.git\*', '*\build\*'),
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Setup logging
try {
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
        $LogDir = 'C:\xoap-logs'
    } else {
        $LogDir = Join-Path $HOME 'xoap-logs'
    }
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Host "${colors.Cyan}Logging to: $LogFile${colors.Reset}"
} catch { 
    Write-Warning "Failed to start transcript logging: $($_.Exception.Message)" 
}

# Test results tracking
$script:TotalScripts = 0
$script:PassedSyntax = 0
$script:FailedSyntax = 0
$script:PassedExecution = 0
$script:FailedExecution = 0
$script:SkippedExecution = 0
$script:TestResults = @()

# ANSI color codes
$colors = @{
    Green  = "`e[32m"
    Red    = "`e[31m"
    Yellow = "`e[33m"
    Blue   = "`e[34m"
    Cyan   = "`e[36m"
    Reset  = "`e[0m"
}

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $color = switch ($Level) {
        'Success' { $colors.Green }
        'Error'   { $colors.Red }
        'Warning' { $colors.Yellow }
        default   { $colors.Reset }
    }
    
    Write-Host "${color}${Message}$($colors.Reset)"
}

function Test-PowerShellSyntax {
    param([string]$ScriptPath)
    
    try {
        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $ScriptPath -Raw), [ref]$errors)
        
        if ($errors.Count -gt 0) {
            return @{
                Success = $false
                Errors = $errors
            }
        }
        
        # Also try to parse with AST for deeper validation
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$errors)
        
        if ($errors.Count -gt 0) {
            return @{
                Success = $false
                Errors = $errors
            }
        }
        
        return @{
            Success = $true
            Errors = @()
        }
    } catch {
        return @{
            Success = $false
            Errors = @($_)
        }
    }
}

function Test-PowerShellExecution {
    param([string]$ScriptPath)
    
    try {
        # Read script content
        $scriptContent = Get-Content $ScriptPath -Raw
        
        # Check if script requires parameters
        $paramBlock = [regex]::Match($scriptContent, 'param\s*\([\s\S]*?\)')
        $requiresParams = $paramBlock.Success -and $scriptContent -match '\[Parameter\(Mandatory\s*=\s*\$true'
        
        if ($requiresParams) {
            return @{
                Success = $null
                Message = "Skipped: Requires mandatory parameters"
            }
        }
        
        # Check for elevation requirement
        $requiresAdmin = $scriptContent -match 'Prerequisite.*Administrator' -or 
                        $scriptContent -match 'RequireAdministrator' -or
                        $scriptContent -match '#Requires -RunAsAdministrator'
        
        # Cross-platform admin check
        $isAdmin = $false
        if ($requiresAdmin) {
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                } catch {
                    # Windows API not available on macOS/Linux
                    try { $isAdmin = (id -u 2>$null) -eq 0 } catch { $isAdmin = $false }
                }
            } else {
                # Unix-like systems (macOS/Linux)
                try { $isAdmin = (id -u 2>$null) -eq 0 } catch { $isAdmin = $false }
            }
        }
        
        if ($requiresAdmin -and -not $isAdmin) {
            return @{
                Success = $null
                Message = "Skipped: Requires administrator privileges"
            }
        }
        
        # Check for cloud-specific scripts (AWS/Azure/GCP)
        $cloudScript = $scriptContent -match '169\.254\.169\.254' -or 
                      $scriptContent -match 'metadata\.google\.internal' -or
                      $scriptContent -match 'EC2Launch|AzureMonitorAgent|GCEAgent'
        
        if ($cloudScript) {
            return @{
                Success = $null
                Message = "Skipped: Cloud-specific script (requires cloud environment)"
            }
        }
        
        # Try to execute with -WhatIf or help parameter if available
        if ($scriptContent -match '\[CmdletBinding\(SupportsShouldProcess') {
            $result = & $ScriptPath -WhatIf -ErrorAction Stop 2>&1
            return @{
                Success = $true
                Message = "Executed successfully with -WhatIf"
            }
        }
        
        # Check for -Help parameter
        if ($scriptContent -match 'param.*\[switch\]\$Help') {
            $result = & $ScriptPath -Help -ErrorAction Stop 2>&1
            return @{
                Success = $true
                Message = "Executed successfully with -Help"
            }
        }
        
        # For scripts without safe execution options, just validate they can be dot-sourced
        $null = . $ScriptPath -ErrorAction Stop 2>&1
        return @{
            Success = $true
            Message = "Script dot-sourced successfully"
        }
        
    } catch {
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# Main execution
Write-TestLog "========================================" -Level Info
Write-TestLog "PowerShell Script Test Runner" -Level Info
Write-TestLog "========================================" -Level Info
Write-Host ""
Write-TestLog "Search path: $Path" -Level Info
Write-TestLog "Skip execution: $SkipExecution" -Level Info
Write-Host ""

# Find all PowerShell scripts
Write-TestLog "Discovering PowerShell scripts..." -Level Info
$scripts = Get-ChildItem -Path $Path -Filter *.ps1 -Recurse | Where-Object {
    $include = $true
    foreach ($pattern in $ExcludePatterns) {
        if ($_.FullName -like $pattern) {
            $include = $false
            break
        }
    }
    $include
}

$script:TotalScripts = $scripts.Count
Write-TestLog "Found $($script:TotalScripts) PowerShell scripts" -Level Success
Write-Host ""

# Test each script
$testStartTime = Get-Date
foreach ($scriptFile in $scripts) {
    $relativePath = $scriptFile.FullName.Replace("$Path\", "")
    Write-Host "$($colors.Cyan)Testing: $relativePath$($colors.Reset)"
    
    $testResult = @{
        Script = $relativePath
        SyntaxCheck = $null
        ExecutionTest = $null
        Errors = @()
    }
    
    # Syntax validation
    Write-Host "  ├─ Syntax check... " -NoNewline
    $syntaxResult = Test-PowerShellSyntax -ScriptPath $scriptFile.FullName
    
    if ($syntaxResult.Success) {
        Write-Host "$($colors.Green)✓ PASS$($colors.Reset)"
        $script:PassedSyntax++
        $testResult.SyntaxCheck = "PASS"
    } else {
        Write-Host "$($colors.Red)✗ FAIL$($colors.Reset)"
        $script:FailedSyntax++
        $testResult.SyntaxCheck = "FAIL"
        $testResult.Errors = $syntaxResult.Errors
        
        foreach ($error in $syntaxResult.Errors) {
            Write-Host "  │  $($colors.Red)Error: $error$($colors.Reset)"
        }
    }
    
    # Execution test (only if syntax passed and not skipped)
    if ($syntaxResult.Success -and -not $SkipExecution) {
        Write-Host "  └─ Execution test... " -NoNewline
        $execResult = Test-PowerShellExecution -ScriptPath $scriptFile.FullName
        
        if ($execResult.Success -eq $true) {
            Write-Host "$($colors.Green)✓ PASS$($colors.Reset)"
            $script:PassedExecution++
            $testResult.ExecutionTest = "PASS"
            if ($VerboseOutput) {
                Write-Host "  │  $($execResult.Message)"
            }
        } elseif ($execResult.Success -eq $false) {
            Write-Host "$($colors.Red)✗ FAIL$($colors.Reset)"
            $script:FailedExecution++
            $testResult.ExecutionTest = "FAIL"
            $testResult.Errors += $execResult.Message
            Write-Host "  │  $($colors.Red)$($execResult.Message)$($colors.Reset)"
        } else {
            Write-Host "$($colors.Yellow)⊘ SKIP$($colors.Reset)"
            $script:SkippedExecution++
            $testResult.ExecutionTest = "SKIP"
            if ($VerboseOutput) {
                Write-Host "  │  $($execResult.Message)"
            }
        }
    } elseif (-not $syntaxResult.Success) {
        Write-Host "  └─ Execution test... $($colors.Yellow)⊘ SKIP (syntax errors)$($colors.Reset)"
        $script:SkippedExecution++
        $testResult.ExecutionTest = "SKIP"
    } else {
        $script:SkippedExecution++
        $testResult.ExecutionTest = "SKIP"
    }
    
    $script:TestResults += $testResult
    Write-Host ""
}

# Summary
$testEndTime = Get-Date
$duration = ($testEndTime - $testStartTime).TotalSeconds

Write-Host ""
Write-TestLog "========================================" -Level Info
Write-TestLog "Test Summary" -Level Info
Write-TestLog "========================================" -Level Info
Write-Host ""
Write-Host "Total scripts: $script:TotalScripts"
Write-Host ""
Write-Host "Syntax Validation:"
Write-Host "  $($colors.Green)✓ Passed: $script:PassedSyntax$($colors.Reset)"
Write-Host "  $($colors.Red)✗ Failed: $script:FailedSyntax$($colors.Reset)"
Write-Host ""

if (-not $SkipExecution) {
    Write-Host "Execution Tests:"
    Write-Host "  $($colors.Green)✓ Passed: $script:PassedExecution$($colors.Reset)"
    Write-Host "  $($colors.Red)✗ Failed: $script:FailedExecution$($colors.Reset)"
    Write-Host "  $($colors.Yellow)⊘ Skipped: $script:SkippedExecution$($colors.Reset)"
    Write-Host ""
}

Write-Host "Duration: $([math]::Round($duration, 2))s"
Write-Host ""

# Failed scripts detail
if ($script:FailedSyntax -gt 0 -or $script:FailedExecution -gt 0) {
    Write-TestLog "Failed Scripts:" -Level Error
    Write-Host ""
    
    $failedScripts = $script:TestResults | Where-Object { 
        $_.SyntaxCheck -eq "FAIL" -or $_.ExecutionTest -eq "FAIL" 
    }
    
    foreach ($failed in $failedScripts) {
        Write-Host "$($colors.Red)✗ $($failed.Script)$($colors.Reset)"
        foreach ($error in $failed.Errors) {
            Write-Host "  └─ $error"
        }
    }
    Write-Host ""
}

# Export results to JSON for CI/CD
$resultsFile = Join-Path $PSScriptRoot "test-results.json"
$script:TestResults | ConvertTo-Json -Depth 10 | Out-File $resultsFile
Write-TestLog "Results exported to: $resultsFile" -Level Info

# Exit code
$exitCode = if ($script:FailedSyntax -gt 0 -or $script:FailedExecution -gt 0) { 1 } else { 0 }

if ($exitCode -eq 0) {
    Write-TestLog "All tests passed! ✓" -Level Success
} else {
    Write-TestLog "Some tests failed! ✗" -Level Error
}

Write-Host ""
exit $exitCode
