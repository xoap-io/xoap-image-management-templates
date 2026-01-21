<#
.SYNOPSIS
    Disable Windows Defender

.DESCRIPTION
    Disables Windows Defender antivirus on Windows 10/11 to improve build performance.

.NOTES
    File Name      : windows11-Disable_Windows_Defender.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Disable_Windows_Defender.ps1
    Disables or removes Windows Defender
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
    Write-Host "[$timestamp] [$prefix] [Defender] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    Write-Log "Disabling Windows Defender..."
    
    if (Get-Command -Name Uninstall-WindowsFeature -ErrorAction SilentlyContinue) {
        # Windows Server - uninstall features
        Write-Log "Server edition detected - uninstalling Windows Defender features"
        Get-WindowsFeature -Name 'Windows-Defender*' | Uninstall-WindowsFeature
        Write-Log "Windows Defender features uninstalled"
    } else {
        # Windows Client - disable via preferences and registry
        Write-Log "Client edition detected - disabling Windows Defender"
        
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -ExclusionPath @('C:\', 'D:\') -ErrorAction SilentlyContinue
        
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name DisableAntiSpyware -Value 1
        
        Write-Log "Windows Defender disabled"
    }
    
    Write-Log "Windows Defender configuration completed"
    
} catch {
    Write-Log "Failed to disable Windows Defender: $($_.Exception.Message)" -Level Warning
    # Don't exit with error - Defender might already be removed
}
