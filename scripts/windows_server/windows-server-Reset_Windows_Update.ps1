<#
.SYNOPSIS
    Resets Windows Update components on Windows Server 2025

.DESCRIPTION
    This script resets Windows Update components and clears update cache for Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
        
.NOTES
    File Name      : windows-server-Reset_Windows_Update.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Reset_Windows_Update.ps1
    Resets Windows Update components and cache

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$script:Component = 'WindowsUpdate'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

# Setup local file logging to C:\xoap-logs
try {
    $LogDir = 'C:\xoap-logs'
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

    Start-Transcript -Path $LogFile -Append | Out-Null
} catch {
    Write-Log "Transcript unavailable: $($_.Exception.Message)" -Level WARN
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$started = Get-Date

try {
    Write-Log '===== Reset_Windows_Update starting ====='

    Write-Log 'Stopping Windows Update services...'
    $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    foreach ($service in $services) {
        try {
            Write-Log "Stopping service: $service"
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Write-Log "Successfully stopped: $service"
        } catch {
            Write-Log "Could not stop service $service`: $($_.Exception.Message)" -Level WARN
        }
    }

    Write-Log 'Clearing Windows Update cache...'
    $cachePaths = @(
        'C:\Windows\SoftwareDistribution\Download',
        'C:\Windows\System32\catroot2'
    )

    foreach ($path in $cachePaths) {
        try {
            if (Test-Path $path) {
                Write-Log "Clearing cache: $path"
                Get-ChildItem -Path $path -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                Write-Log "Successfully cleared: $path"
            }
        } catch {
            Write-Log "Could not clear cache $path`: $($_.Exception.Message)" -Level WARN
        }
    }

    Write-Log 'Starting Windows Update services...'
    foreach ($service in $services) {
        try {
            Write-Log "Starting service: $service"
            Start-Service -Name $service -ErrorAction SilentlyContinue
            Write-Log "Successfully started: $service"
        } catch {
            Write-Log "Could not start service $service`: $($_.Exception.Message)" -Level WARN
        }
    }

    Write-Log "===== Reset_Windows_Update complete in $([int]((Get-Date) - $started).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit 0
