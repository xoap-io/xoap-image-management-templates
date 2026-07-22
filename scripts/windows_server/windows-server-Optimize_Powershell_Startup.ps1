<#
.SYNOPSIS
    Optimize PowerShell Startup Performance

.DESCRIPTION
    Optimizes PowerShell startup by reducing JIT compile time using ngen.exe.
    This script compiles PowerShell assemblies to native code for faster loading.
    Based on work by BornToBeRoot with XOAP optimizations.

.NOTES
    File Name      : windows-server-optimize_powershell_startup.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    Original       : BornToBeRoot (https://github.com/BornToBeRoot)
    
.EXAMPLE
    .\windows-server-optimize_powershell_startup.ps1
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
$script:Component = 'PSOptimize'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [PSOptimize] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

# Main script execution
try {
    $startTime = Get-Date
    Write-Log "===== Optimize_Powershell_Startup starting ====="
    
    # Check for administrator privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log "Script requires administrator privileges" -Level ERROR
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
            Write-Log "Warning: Failed to process $($assembly.GetName().Name): $($_.Exception.Message)" -Level WARN
        }
    }
    
    Write-Log "Processed $count assemblies"
    Write-Log "===== Optimize_Powershell_Startup complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
