<#
.SYNOPSIS
    Configures Windows Update policies for Windows Server 2025

.DESCRIPTION
    This script configures Windows Update policies and settings for Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
        
.NOTES
    File Name      : windows-server-Windows_Update_Policies.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Windows_Update_Policies.ps1
    Configures Windows Update policies

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
    Write-Log 'Starting Windows Update policy configuration'

    # Windows Update policy settings
    $updatePolicies = @(
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            Name = 'DoNotConnectToWindowsUpdateInternetLocations'
            Value = 1
            Type = 'DWORD'
            Description = 'Prevent connections to Windows Update internet locations'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            Name = 'NoAutoUpdate'
            Value = 0
            Type = 'DWORD'
            Description = 'Enable automatic updates'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            Name = 'AUOptions'
            Value = 4
            Type = 'DWORD'
            Description = 'Auto download and schedule install'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            Name = 'ScheduledInstallDay'
            Value = 0
            Type = 'DWORD'
            Description = 'Install updates every day'
        }
    )

    Write-Log "Applying $($updatePolicies.Count) Windows Update policies"

    foreach ($policy in $updatePolicies) {
        try {
            Write-Log "Applying: $($policy.Description)"

            if (-not (Test-Path $policy.Path)) {
                New-Item -Path $policy.Path -Force | Out-Null
                Write-Log "Created registry path: $($policy.Path)"
            }

            Set-ItemProperty -Path $policy.Path -Name $policy.Name -Value $policy.Value -Type $policy.Type
            Write-Log "Successfully applied: $($policy.Description)"
        } catch {
            Write-Log "Warning: Could not apply policy $($policy.Description): $($_.Exception.Message)"
        }
    }

    Write-Log "Windows Update policy configuration completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
