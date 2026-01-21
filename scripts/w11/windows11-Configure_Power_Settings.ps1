<#
.SYNOPSIS
    Configures power settings for Windows 10/11

.DESCRIPTION
    This script sets the High Performance power plan and configures power-related options for Windows 10/11.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.

.NOTES
    File Name      : windows11-Configure_Power_Settings.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Configure_Power_Settings.ps1
    Configures High Performance power plan

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
    Write-Log 'Starting power settings configuration for Windows 10/11'

    # Set power plan to High Performance (use powercfg only)
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

    # Disable sleep
    try {
        Write-Log 'Disabling sleep timeouts...'
        & powercfg.exe /change standby-timeout-ac 0
        & powercfg.exe /change standby-timeout-dc 0
        Write-Log 'Sleep timeouts disabled'
    } catch {
        Write-Log "Warning: Could not disable sleep: $($_.Exception.Message)"
    }

    # Set monitor timeout
    try {
        Write-Log 'Setting monitor timeout to never...'
        & powercfg.exe /change monitor-timeout-ac 0
        & powercfg.exe /change monitor-timeout-dc 0
        Write-Log 'Monitor timeout set to never'
    } catch {
        Write-Log "Warning: Could not set monitor timeout: $($_.Exception.Message)"
    }

    # Disable disk timeout
    try {
        Write-Log 'Setting disk timeout to never...'
        & powercfg.exe /change disk-timeout-ac 0
        & powercfg.exe /change disk-timeout-dc 0
        Write-Log 'Disk timeout set to never'
    } catch {
        Write-Log "Warning: Could not set disk timeout: $($_.Exception.Message)"
    }

    # Disable USB selective suspend
    try {
        Write-Log 'Disabling USB selective suspend...'
        & powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        & powercfg.exe /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        Write-Log 'USB selective suspend disabled'
    } catch {
        Write-Log "Warning: Could not disable USB selective suspend: $($_.Exception.Message)"
    }

    Write-Log 'Power settings configuration completed successfully.'
} finally {
    try { Stop-Transcript | Out-Null } catch {
        Write-Log "Failed to stop transcript logging: $($_.Exception.Message)"
    }
}
