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
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    Write-Log "Disabling screensaver for current user..."
    
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' `
        -Name ScreenSaveActive -Type DWORD -Value 0
    
    Write-Log "Screensaver disabled successfully"
    
} catch {
    Write-Log "Failed to disable screensaver: $($_.Exception.Message)" -Level Error
    exit 1
}
