<#
.SYNOPSIS
    Disables telemetry and data collection on Windows 10/11

.DESCRIPTION
    This script disables Windows telemetry and data collection features for privacy and compliance on Windows 10/11.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows11-Disable_Telemetry.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Disable_Telemetry.ps1
    Disables Windows telemetry and data collection

.LINK
    https://github.com/xoap-io/xoap-packer-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Setup local file logging to C:\xoap-logs
try {
    $LogDir = 'C:\xoap-logs'
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Host "Logging to: $LogFile"
} catch {
    Write-Warning "Failed to start transcript logging to C:\xoap-logs: $($_.Exception.Message)"
}

# Simple logging function
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

try {
    Write-Log 'Starting telemetry disabling'

    # Disable Windows telemetry
    $telemetrySettings = @(
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            Name = 'AllowTelemetry'
            Value = 0
            Type = 'DWORD'
            Description = 'Disable telemetry collection'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
            Name = 'AllowTelemetry'
            Value = 0
            Type = 'DWORD'
            Description = 'Disable telemetry collection (alternative path)'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
            Name = 'AITEnable'
            Value = 0
            Type = 'DWORD'
            Description = 'Disable Application Impact Telemetry'
        }
    )

    Write-Log "Applying $($telemetrySettings.Count) telemetry settings"

    foreach ($setting in $telemetrySettings) {
        try {
            Write-Log "Applying: $($setting.Description)"

            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
                Write-Log "Created registry path: $($setting.Path)"
            }

            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type
            Write-Log "Successfully applied: $($setting.Description)"
        } catch {
            Write-Log "Warning: Could not apply setting $($setting.Description): $($_.Exception.Message)"
        }
    }

    # Disable telemetry services
    $telemetryServices = @('DiagTrack', 'dmwappushservice')

    foreach ($service in $telemetryServices) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Log "Disabling telemetry service: $service"
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled
                Write-Log "Successfully disabled service: $service"
            }
        } catch {
            Write-Log "Warning: Could not disable service $service`: $($_.Exception.Message)"
        }
    }

    Write-Log "Telemetry disabling completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
