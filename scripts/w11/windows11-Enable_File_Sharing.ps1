<#
.SYNOPSIS
    Enable File and Printer Sharing

.DESCRIPTION
    Enables Windows 10/11 firewall rules for File and Printer Sharing to allow
    network file transfers during provisioning and testing.

.NOTES
    File Name      : windows11-Enable_File_Sharing.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Enable_File_Sharing.ps1
    Enables file and printer sharing firewall rules
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
    Write-Host "[$timestamp] [$prefix] [FileShare] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    Write-Log "Enabling File and Printer Sharing firewall rules..."
    
    Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction Stop
    
    Write-Log "File and Printer Sharing enabled successfully"
    
} catch {
    Write-Log "Failed to enable file sharing: $($_.Exception.Message)" -Level Error
    exit 1
}
