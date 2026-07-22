<#
.SYNOPSIS
    Configures TLS 1.2 for Windows Server 2025

.DESCRIPTION
    This script enables and enforces TLS 1.2 for both client and server protocols on Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Enable_TLS1_2.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Enable_TLS1_2.ps1
    Enables and enforces TLS 1.2 protocol

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
    Write-Host "[$timestamp] [$Level] [TLS] $Message"
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
    Write-Log '===== Enable_TLS1_2 starting ====='

    $basePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2'
    $clientPath = Join-Path $basePath 'Client'
    $serverPath = Join-Path $basePath 'Server'

    foreach ($path in @($clientPath, $serverPath)) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name 'Enabled' -Value 1 -Type DWORD
        Set-ItemProperty -Path $path -Name 'DisabledByDefault' -Value 0 -Type DWORD
        Write-Log "Configured TLS 1.2 at $path"
    }

    Write-Log "===== Enable_TLS1_2 complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {
        Write-Log "Failed to stop transcript logging: $($_.Exception.Message)" -Level WARN
    }
}

exit 0
