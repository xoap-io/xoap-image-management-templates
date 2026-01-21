<#
.SYNOPSIS
    Configure Power Settings for Windows Server

.DESCRIPTION
    Sets power configuration to High Performance and disables power-saving features
    for Windows Server 2025. Optimized for Packer image builds.

.NOTES
    File Name      : windows-server-set_power_config.ps1
    Prerequisite   : PowerShell 5.1 or higher
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-set_power_config.ps1
    Configures power settings for optimal performance
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogPath = 'C:\Windows\Temp'
$LogName = 'set-power-config.log'
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName

# Logging function
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
    $logMessage = "[$timestamp] [$prefix] [Power] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Main script execution
try {
    # Ensure log directory exists
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Starting power configuration..."
    Start-Transcript -Path $LogFile -Append | Out-Null
    
    # Set power plan to High Performance (SCHEME_MIN)
    Write-Log "Setting power plan to High Performance..."
    $result = powercfg /setactive SCHEME_MIN 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Warning: powercfg setactive returned code: $LASTEXITCODE" -Level Warning
    } else {
        Write-Log "High Performance power plan activated"
    }
    
    # Disable monitor timeout for AC power
    Write-Log "Disabling monitor timeout for AC power..."
    powercfg /Change -monitor-timeout-ac 0
    
    # Disable monitor timeout for DC power (battery)
    Write-Log "Disabling monitor timeout for DC power..."
    powercfg /Change -monitor-timeout-dc 0
    
    # Disable disk timeout for AC power
    Write-Log "Disabling disk timeout for AC power..."
    powercfg /Change -disk-timeout-ac 0
    
    # Disable sleep timeout for AC power
    Write-Log "Disabling sleep timeout for AC power..."
    powercfg /Change -standby-timeout-ac 0
    
    # Disable hibernate
    Write-Log "Disabling hibernation..."
    powercfg /hibernate OFF
    
    # Verify current power scheme
    $currentScheme = powercfg /getactivescheme
    Write-Log "Current active power scheme: $currentScheme"
    
    Write-Log "Power configuration completed successfully"
    
    Stop-Transcript | Out-Null
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}
