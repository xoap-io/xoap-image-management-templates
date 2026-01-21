<#
.SYNOPSIS
    Disable System Restore

.DESCRIPTION
    Disables System Restore on Windows 10/11 desktop editions to reduce image size
    and improve performance. Server editions don't have System Restore.

.NOTES
    File Name      : windows11-Disable_System_Restore.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Disable_System_Restore.ps1
    Disables System Restore on desktop editions
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

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
    Write-Host "[$timestamp] [$prefix] [SysRestore] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    
    # ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
    if ($osInfo.ProductType -eq 1) {
        Write-Log "Desktop edition detected - disabling System Restore..."
        Disable-ComputerRestore -Drive 'C:\' -ErrorAction Stop
        Write-Log "System Restore disabled successfully"
    } else {
        Write-Log "Server edition detected - System Restore not available, skipping"
    }
    
} catch {
    Write-Log "Failed to disable System Restore: $($_.Exception.Message)" -Level Error
    exit 1
}
