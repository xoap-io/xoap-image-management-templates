<#
.SYNOPSIS
    Performs final cleanup and prepares Windows 10/11 for sysprep

.DESCRIPTION
    This script performs final cleanup tasks and prepares the system for sysprep and imaging on Windows 10/11.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows11-Final_Cleanup_Sysprep.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Final_Cleanup_Sysprep.ps1
    Performs final cleanup and sysprep preparation

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
    Write-Log 'Starting final cleanup and sysprep'

    # Final cleanup before sysprep
    Write-Log 'Performing final system cleanup...'

    # Clear additional temp locations
    $cleanupPaths = @(
        "C:\Windows\Logs\*",
        "C:\Windows\Panther\*",
        "C:\Windows\SoftwareDistribution\Download\*"
    )

    foreach ($path in $cleanupPaths) {
        try {
            if (Test-Path (Split-Path $path -Parent)) {
                $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                if ($items) {
                    Write-Log "Cleaning $path - $($items.Count) items"
                    $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Log "Warning: Could not clean $path`: $($_.Exception.Message)"
        }
    }

    # Clear event logs one final time
    Write-Log 'Clearing event logs...'
    try {
        Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
            } catch {
                # Some logs cannot be cleared
            }
        }
        Write-Log 'Event logs cleared'
    } catch {
        Write-Log "Warning: Could not clear all event logs"
    }

    # Defragment system drive
    Write-Log 'Optimizing system drive...'
    try {
        Optimize-Volume -DriveLetter C -Defrag -Verbose:$false
        Write-Log 'System drive optimization completed'
    } catch {
        Write-Log "Warning: Could not optimize system drive: $($_.Exception.Message)"
    }

    Write-Log 'Final cleanup completed, preparing for sysprep...'

    # Stop transcript before sysprep
    try { Stop-Transcript | Out-Null } catch {}

    # Prepare sysprep command
    $sysprepPath = Join-Path $env:WINDIR "System32\Sysprep\sysprep.exe"
    $sysprepArgs = @('/generalize', '/shutdown', '/quiet')

    Write-Log "Running sysprep with arguments: $($sysprepArgs -join ' ')"
    Write-Log "This will shutdown the system when complete"

    # Run sysprep
    & $sysprepPath $sysprepArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Log "Sysprep failed with exit code: $LASTEXITCODE"
        exit $LASTEXITCODE
    }

} catch {
    Write-Log "Critical error in final cleanup: $($_.Exception.Message)"
    try { Stop-Transcript | Out-Null } catch {}
    throw
}
