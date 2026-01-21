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
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    Write-Log "Enabling Remote Desktop..."
    
    Write-Log "Setting fDenyTSConnections to 0 (allow RDP)"
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name fDenyTSConnections -Value 0
    
    Write-Log "Enabling Remote Desktop firewall rules"
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
    
    Write-Log "Remote Desktop enabled successfully"
    
} catch {
    Write-Log "Failed to enable Remote Desktop: $($_.Exception.Message)" -Level Error
    exit 1
}
