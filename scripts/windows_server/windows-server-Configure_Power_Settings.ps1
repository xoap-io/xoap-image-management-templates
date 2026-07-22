<#
.SYNOPSIS
    Configures power settings for Windows Server 2025

.DESCRIPTION
    This script sets the High Performance power plan and configures power-related options for Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Configure_Power_Settings.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Configure_Power_Settings
    Configures High Performance power plan

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [Power] $Message"
}

trap {
    Write-Log "ERROR: $_" -Level ERROR
    Write-Log "ERROR: $($_.ScriptStackTrace)" -Level ERROR
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log '===== Configure_Power_Settings starting ====='

    # Set power plan to High Performance (use powercfg only, WMI not supported)
    try {
        Write-Log 'Setting power plan to High Performance using powercfg...'
        & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        Write-Log 'High performance power plan activated'
    } catch {
        Write-Log "Warning: Could not set power plan: $($_.Exception.Message)"
    }

    # Disable hibernate
    try {
        Write-Log 'Disabling hibernation...'
        & powercfg.exe /hibernate off
        Write-Log 'Hibernation disabled'
    } catch {
        Write-Log "Warning: Could not disable hibernation: $($_.Exception.Message)"
    }

    # Set monitor and disk timeouts
    try {
        Write-Log 'Configuring power timeouts...'
        & powercfg.exe /change monitor-timeout-ac 0
        & powercfg.exe /change monitor-timeout-dc 0
        & powercfg.exe /change disk-timeout-ac 0
        & powercfg.exe /change disk-timeout-dc 0
        Write-Log 'Power timeouts configured'
    } catch {
        Write-Log "Warning: Could not configure power timeouts: $($_.Exception.Message)"
    }

    Write-Log "===== Configure_Power_Settings complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit 0
