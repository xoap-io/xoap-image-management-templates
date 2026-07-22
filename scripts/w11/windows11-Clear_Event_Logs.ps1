<#
.SYNOPSIS
    Clears Windows Event Logs on Windows 10/11

.DESCRIPTION
    This script clears all Windows Event Logs to ensure a clean state for imaging or compliance on Windows 10/11.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows11-Clear_Event_Logs.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Clear_Event_Logs.ps1
    Clears all Windows Event Logs

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Setup local file logging to C:\xoap-logs
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [EventLog] Transcript unavailable: $($_.Exception.Message)" }

# Simple logging function
function Write-Log {
    param(
        $Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [EventLog] $Message"
}

trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

try {
    Write-Log '===== Clear_Event_Logs starting ====='
    $startTime = Get-Date
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
    Write-Log "===== Clear_Event_Logs complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
