<#
.SYNOPSIS
    Disable Windows Screensaver

.DESCRIPTION
    Disables the screensaver for the current user on Windows 10/11 to prevent interruptions
    during Packer builds and automated deployments.

.NOTES
    File Name      : windows11-Disable_Screensaver.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Disable_Screensaver.ps1
    Disables the screensaver
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Screensaver] Transcript unavailable: $($_.Exception.Message)" }

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        default   { 'INFO' }
    }
    Write-Host "[$timestamp] [$prefix] [Screensaver] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log "===== Disable_Screensaver starting ====="
    Write-Log "Disabling screensaver for current user..."
    
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' `
        -Name ScreenSaveActive -Type DWORD -Value 0
    
    Write-Log "Screensaver disabled successfully"
    Write-Log "===== Disable_Screensaver complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Failed to disable screensaver: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
