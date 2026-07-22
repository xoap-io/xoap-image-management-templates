<#
.SYNOPSIS
    Enables time-zone redirection for Azure Virtual Desktop session hosts.

.DESCRIPTION
    Sets HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\fEnableTimeZoneRedirection = 1
    so that AVD / RDSH sessions inherit the local time zone of the connecting client instead of
    the session host's time zone. Small, focused, and idempotent.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes (0 success,
    non-zero failure), idempotent, non-interactive. Developed for the XOAP Image Management
    module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Configure_Timezone_Redirection.ps1
    Enables time-zone redirection.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'TZ-Redirect'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [TZ-Redirect] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date
Write-Log '===== Configure_Timezone_Redirection starting ====='

$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Write-Log "Setting $key\fEnableTimeZoneRedirection = 1"
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name 'fEnableTimeZoneRedirection' -Value 1 -PropertyType DWord -Force | Out-Null
Write-Log '[OK] Time-zone redirection enabled'

Write-Log "===== Configure_Timezone_Redirection complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

try { Stop-Transcript | Out-Null } catch {}
exit 0
