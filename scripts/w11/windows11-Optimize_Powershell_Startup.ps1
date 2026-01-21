<#
.SYNOPSIS
    Optimize PowerShell Startup Performance

.DESCRIPTION
    Optimizes PowerShell startup by reducing JIT compile time using ngen.exe.
    This script compiles PowerShell assemblies to native code for faster loading.
    Based on work by BornToBeRoot with XOAP optimizations.

.NOTES
    File Name      : windows11-optimize_powershell_startup.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    Original       : BornToBeRoot (https://github.com/BornToBeRoot)
    
.EXAMPLE
    .\windows11-optimize_powershell_startup.ps1
    Optimizes PowerShell startup performance
    
.LINK
    https://github.com/BornToBeRoot/PowerShell/blob/master/Documentation/Script/OptimizePowerShellStartup.README.md
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        default   { 'INFO' }
    }
    Write-Host "[$timestamp] [$prefix] [PSOptimize] $Message"
}

# Main script execution
try {
    Write-Log "Starting PowerShell startup optimization..."
    
    # Check for administrator privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log "Script requires administrator privileges" -Level Error
        throw "Please run this script as Administrator"
    }
    
    # Locate ngen.exe
    Write-Log "Locating ngen.exe..."
    $ngenBasePath = Join-Path -Path $env:windir -ChildPath "Microsoft.NET"
    
    if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
        $ngenPath = Join-Path -Path $ngenBasePath -ChildPath "Framework64"
    } else {
        $ngenPath = Join-Path -Path $ngenBasePath -ChildPath "Framework"
    }
    
    $ngenExe = Get-ChildItem -Path $ngenPath -Filter "ngen.exe" -Recurse -ErrorAction SilentlyContinue | 
               Where-Object { $_.Length -gt 0 } | 
               Select-Object -Last 1
    
    if (-not $ngenExe) {
        throw "ngen.exe not found in: $ngenPath"
    }
    
    Write-Log "Found ngen.exe at: $($ngenExe.FullName)"
    Set-Alias -Name ngen -Value $ngenExe.FullName
    
    # Optimize loaded assemblies
    Write-Log "Optimizing loaded PowerShell assemblies..."
    $assemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
    $count = 0
    $total = $assemblies.Count
    
    foreach ($assembly in $assemblies) {
        $count++
        try {
            if ($assembly.Location) {
                Write-Log "[$count/$total] Processing: $($assembly.GetName().Name)"
                & ngen install $assembly.Location /nologo | Out-Null
            }
        } catch {
            Write-Log "Warning: Failed to process $($assembly.GetName().Name): $($_.Exception.Message)" -Level Warning
        }
    }
    
    Write-Log "PowerShell startup optimization completed successfully"
    Write-Log "Processed $count assemblies"
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
