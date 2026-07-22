<#
.SYNOPSIS
    Enable Remote Desktop

.DESCRIPTION
    Enables Remote Desktop Protocol (RDP) connections on Windows 10/11 and configures firewall
    rules to allow remote access for troubleshooting and management.

.NOTES
    File Name      : windows11-Enable_Remote_Desktop.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Enable_Remote_Desktop.ps1
    Enables Remote Desktop and firewall rules
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
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [RDP] Transcript unavailable: $($_.Exception.Message)" }

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
    Write-Host "[$timestamp] [$prefix] [RDP] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log "===== Enable_Remote_Desktop starting ====="
    Write-Log "Enabling Remote Desktop..."
    
    Write-Log "Setting fDenyTSConnections to 0 (allow RDP)"
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name fDenyTSConnections -Value 0
    
    Write-Log "Enabling Remote Desktop firewall rules"
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
    
    Write-Log "Remote Desktop enabled successfully"
    Write-Log "===== Enable_Remote_Desktop complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Failed to enable Remote Desktop: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
