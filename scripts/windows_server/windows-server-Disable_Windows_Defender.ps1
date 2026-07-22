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
    $LogFile = $null
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
    Write-Host "[$timestamp] [$Level] [Defender] $Message"
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
    Write-Log '===== Disable_Windows_Defender starting ====='
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
    Write-Log "===== Disable_Windows_Defender complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {
        Write-Log "Failed to stop transcript logging: $($_.Exception.Message)" -Level WARN
    }
}

exit 0
