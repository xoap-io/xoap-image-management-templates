<#
.SYNOPSIS
    Disables Windows User Account Control (UAC) for Windows Server 2025.

.DESCRIPTION
    This script disables UAC by setting relevant registry keys.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Disable_Windows_UAC.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Disable_Windows_UAC.ps1
    Disables User Account Control

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
    $LogFile = $null
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
    Write-Log 'Disabling Windows UAC...'

    $regPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $settings = @{
        ConsentPromptBehaviorAdmin     = 0
        PromptOnSecureDesktop         = 0
        EnableLUA                     = 0
        LocalAccountTokenFilterPolicy = 1
    }

    foreach ($name in $settings.Keys) {
        try {
            Set-ItemProperty -Path $regPath -Name $name -Type DWORD -Value $settings[$name]
            Write-Log "Set $name to $($settings[$name])"
        } catch {
            Write-Log "Warning: Could not set $name : $($_.Exception.Message)"
        }
    }

    Write-Log 'Windows UAC disabled successfully.'
} finally {
    try { Stop-Transcript | Out-Null } catch {
        Write-Log "Failed to stop transcript logging: $($_.Exception.Message)"
    }
}
