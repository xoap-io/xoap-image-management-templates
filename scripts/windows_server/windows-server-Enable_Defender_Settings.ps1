<#
.SYNOPSIS
    Enables and configures Windows Defender settings on Windows Server 2025

.DESCRIPTION
    This script enables and configures Windows Defender security features for Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Enable_Defender_Settings.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Enable_Defender_Settings.ps1
    Enables and configures Windows Defender

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
    Write-Log 'Starting Windows Defender configuration'

    # Check if Windows Defender service (WinDefend) is running
    $defenderService = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
    if ($defenderService -and $defenderService.Status -eq 'Running') {
        Write-Log 'Windows Defender service is running, configuring settings...'
        try {
            Write-Log 'Enabling real-time protection...'
            Set-MpPreference -DisableRealtimeMonitoring $false
            Write-Log 'Real-time protection enabled'
        } catch {
            Write-Log "Warning: Could not enable real-time protection: $($_.Exception.Message)"
        }
        try {
            Write-Log 'Configuring cloud protection...'
            Set-MpPreference -MAPSReporting Advanced
            Set-MpPreference -SubmitSamplesConsent SendAllSamples
            Write-Log 'Cloud protection configured'
        } catch {
            Write-Log "Warning: Could not configure cloud protection: $($_.Exception.Message)"
        }
        try {
            Write-Log 'Starting signature update...'
            Update-MpSignature
            Write-Log 'Signature update completed'
        } catch {
            Write-Log "Warning: Could not update signatures: $($_.Exception.Message)"
        }
    } else {
        Write-Log 'Warning: Windows Defender service is not running or not available on this system. Skipping Defender configuration.'
    }

    Write-Log "Windows Defender configuration completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
