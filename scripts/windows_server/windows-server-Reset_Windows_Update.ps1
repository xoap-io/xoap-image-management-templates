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
    https://github.com/xoap-io/xoap-packer-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

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
    Write-Host "Logging to: $LogFile"
} catch {
    Write-Warning "Failed to start transcript logging to C:\xoap-logs: $($_.Exception.Message)"
}

# Simple logging function
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

try {
    Write-Log 'Starting Windows Update reset'

    Write-Log 'Stopping Windows Update services...'
    $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    foreach ($service in $services) {
        try {
            Write-Log "Stopping service: $service"
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Write-Log "Successfully stopped: $service"
        } catch {
            Write-Log "Warning: Could not stop service $service`: $($_.Exception.Message)"
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
            Write-Log "Warning: Could not clear cache $path`: $($_.Exception.Message)"
        }
    }

    Write-Log 'Starting Windows Update services...'
    foreach ($service in $services) {
        try {
            Write-Log "Starting service: $service"
            Start-Service -Name $service -ErrorAction SilentlyContinue
            Write-Log "Successfully started: $service"
        } catch {
            Write-Log "Warning: Could not start service $service`: $($_.Exception.Message)"
        }
    }

    Write-Log "Windows Update reset completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
