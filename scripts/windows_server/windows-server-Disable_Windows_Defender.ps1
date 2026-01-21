<#
.SYNOPSIS
    Disables Windows Defender on Windows Server 2025.

.DESCRIPTION
    This script disables Windows Defender using feature removal for server editions,
    or registry and preference changes for client editions.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Disable_Windows_Defender.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Disable_Windows_Defender
    Disables Windows Defender

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
    $LogFile = $null
}

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
    Write-Log 'Disabling Windows Defender...'
    if (Get-Command -ErrorAction SilentlyContinue Uninstall-WindowsFeature) {
        # For Windows Server
        try {
            Get-WindowsFeature 'Windows-Defender*' | Uninstall-WindowsFeature -ErrorAction Stop
            Write-Log 'Windows Defender features uninstalled successfully.'
        } catch {
            Write-Log "Warning: Could not uninstall Windows Defender features: $($_.Exception.Message)"
        }
    } else {
        # For Windows Client
        try {
            Set-MpPreference -DisableRealtimeMonitoring $true -ExclusionPath @('C:\', 'D:\')
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name DisableAntiSpyware -Value 1
            Write-Log 'Windows Defender disabled via preferences and registry.'
        } catch {
            Write-Log "Warning: Could not disable Windows Defender: $($_.Exception.Message)"
        }
    }
    Write-Log 'Windows Defender disable script completed.'
} finally {
    try { Stop-Transcript | Out-Null } catch {
        Write-Log "Failed to stop transcript logging: $($_.Exception.Message)"
    }
}
