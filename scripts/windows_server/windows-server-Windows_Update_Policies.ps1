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
    https://github.com/xoap-io/xoap-image-management-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$script:Component = 'WindowsUpdate'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

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
} catch {
    Write-Log "Transcript unavailable: $($_.Exception.Message)" -Level WARN
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$started = Get-Date

try {
    Write-Log '===== Windows_Update_Policies starting ====='

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
            Write-Log "Could not apply policy $($policy.Description): $($_.Exception.Message)" -Level WARN
        }
    }

    Write-Log "===== Windows_Update_Policies complete in $([int]((Get-Date) - $started).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit 0
