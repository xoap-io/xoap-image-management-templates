<#
.SYNOPSIS
    Clears Windows Event Logs on Windows Server 2025

.DESCRIPTION
    This script clears all Windows Event Logs to ensure a clean state for imaging or compliance on Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Clear_Event_Logs.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Clear_Event_Logs.ps1
    Clears all Windows Event Logs

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
    Write-Log 'Starting event log cleanup'

    Write-Log 'Getting list of event logs...'
    $logs = Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 }
    Write-Log "Found $($logs.Count) logs with events"

    foreach ($log in $logs) {
        try {
            Write-Log "Clearing log: $($log.LogName) (Records: $($log.RecordCount))"
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
            Write-Log "Successfully cleared: $($log.LogName)"
        } catch {
            Write-Log "Warning: Could not clear log $($log.LogName): $($_.Exception.Message)"
        }
    }

    Write-Log "Event log cleanup completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
