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
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [SMBv1] Transcript unavailable: $($_.Exception.Message)" }

# Simple logging function
function Write-Log {
    param(
        $Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [SMBv1] $Message"
}

trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

try {
    Write-Log '===== Disable_SMBv1_Legacy starting ====='
    $startTime = Get-Date
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
    Write-Log "===== Disable_SMBv1_Legacy complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
