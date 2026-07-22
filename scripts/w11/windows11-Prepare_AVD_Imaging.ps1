<#
.SYNOPSIS
    Prepare Azure Virtual Desktop Image

.DESCRIPTION
    Prepares a Windows Server or Windows 10/11 image for Azure Virtual Desktop (AVD) customization.
    Disables Windows Defender real-time scanning and Windows Store updates.

.NOTES
    File Name      : windows11-Prepare_AVD_Imaging.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.EXAMPLE
    .\windows11-Prepare_AVD_Imaging.ps1
    Prepares image for AVD customization
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[CmdletBinding()]
Param ()

function Write-Log {
    param(
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [AVD-Prep] $Message"
}

$ErrorActionPreference = 'Stop'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [AVD-Prep] Transcript unavailable: $($_.Exception.Message)" }

try {
    $startTime = Get-Date
    Write-Log "===== Prepare_AVD_Imaging starting ====="
    Write-Log "Disabling Windows Defender real-time scan..."
    Set-MpPreference -DisableRealtimeMonitoring $true
    Write-Log "Disabling Windows Store updates..."
    REG add HKLM\Software\Policies\Microsoft\Windows\CloudContent /v "DisableWindowsConsumerFeatures" /d 1 /t "REG_DWORD" /f
    REG add HKLM\Software\Policies\Microsoft\WindowsStore /v "AutoDownload" /d 2 /t "REG_DWORD" /f
    Write-Log "Image preparation complete."
    Write-Log "===== Prepare_AVD_Imaging complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} catch {
    Write-Log "Error: $($_.Exception.Message)"
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
