<#
.SYNOPSIS
    Ejects removable media volumes on Windows Server 2025.

.DESCRIPTION
    This script ejects all removable media volumes except fixed drives.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Eject_Media.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Eject_Media.ps1
    Ejects all removable media

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
    Write-Host "[$timestamp] [$Level] [Media] $Message"
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
    Write-Log '===== Eject_Media starting ====='

    # Enable TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    Write-Log 'Ejecting removable media volumes...'
    $volList = Get-Volume | Where-Object { $_.DriveType -ne 'Fixed' -and $_.DriveLetter }

    foreach ($vol in $volList) {
        $volLetter = $vol.DriveLetter
        Write-Log "Ejecting drive ${volLetter}:"
        try {
            $Eject = New-Object -ComObject Shell.Application
            $Eject.NameSpace(17).ParseName("${volLetter}:").InvokeVerb("Eject")
            Write-Log "Drive ${volLetter}: ejected successfully."
        } catch {
            Write-Log "Warning: Could not eject drive ${volLetter}: $($_.Exception.Message)" -Level WARN
        } finally {
            if ($Eject) {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Eject) | Out-Null
            }
        }
    }
    Write-Log "===== Eject_Media complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {
        Write-Log "Failed to stop transcript logging: $($_.Exception.Message)" -Level WARN
    }
}

exit 0
