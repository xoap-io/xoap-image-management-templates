<#
.SYNOPSIS
    Disables SMBv1 and legacy protocols on Windows 10/11

.DESCRIPTION
    This script disables SMBv1 and other legacy protocols to improve security on Windows 10/11.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows11-Disable_SMBv1_Legacy.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Disable_SMBv1_Legacy
    Disables SMBv1 and legacy protocols for security

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
    Write-Log 'Starting SMBv1 and legacy protocol disabling'

    # Disable SMBv1
    try {
        Write-Log 'Checking SMBv1 status...'
        $smbv1Status = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue

        if ($smbv1Status -and $smbv1Status.State -eq 'Enabled') {
            Write-Log 'SMBv1 is enabled, disabling...'
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
            Write-Log 'SMBv1 disabled successfully'
        } else {
            Write-Log 'SMBv1 is already disabled or not available'
        }
    } catch {
        Write-Log "Warning: Could not disable SMBv1: $($_.Exception.Message)"
    }

    # Disable SMBv1 via registry
    try {
        Write-Log 'Applying SMBv1 registry settings...'
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters'

        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        Set-ItemProperty -Path $regPath -Name 'SMB1' -Value 0 -Type DWORD
        Write-Log 'SMBv1 registry settings applied'
    } catch {
        Write-Log "Warning: Could not apply SMBv1 registry settings: $($_.Exception.Message)"
    }

    # Disable weak authentication protocols
    try {
        Write-Log 'Disabling weak authentication protocols...'
        $authPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

        Set-ItemProperty -Path $authPath -Name 'LmCompatibilityLevel' -Value 5 -Type DWORD
        Write-Log 'Weak authentication protocols disabled'
    } catch {
        Write-Log "Warning: Could not disable weak authentication protocols: $($_.Exception.Message)"
    }

    Write-Log "SMBv1 and legacy protocol disabling completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
