<#
.SYNOPSIS
    Applies CIS Benchmark settings for Windows Server 2025

.DESCRIPTION
    This script configures recommended CIS Benchmark registry and system settings for Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Apply_CIS_Benchmarks.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Apply_CIS_Benchmarks.ps1
    Applies CIS Benchmark security settings

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

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
    $LogFile = $null
}

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [CIS] $Message"
}

trap {
    Write-Log "ERROR: $_" -Level ERROR
    Write-Log "ERROR: $($_.ScriptStackTrace)" -Level ERROR
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log '===== Apply_CIS_Benchmarks starting ====='

    # CIS Benchmark registry settings
    $cisSettings = @(
        @{
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            Name = 'EnableLUA'
            Value = 1
            Type = 'DWORD'
            Description = 'Enable User Account Control'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            Name = 'ConsentPromptBehaviorAdmin'
            Value = 2
            Type = 'DWORD'
            Description = 'UAC Admin Consent Prompt'
        },
        @{
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
            Name = 'RequireSecuritySignature'
            Value = 1
            Type = 'DWORD'
            Description = 'Require SMB Security Signatures'
        }
    )

    Write-Log "Applying $($cisSettings.Count) CIS Benchmark settings"

    foreach ($setting in $cisSettings) {
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

    Write-Log "===== Apply_CIS_Benchmarks complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit 0
