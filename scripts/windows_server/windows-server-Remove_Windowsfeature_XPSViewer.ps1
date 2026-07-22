<#
.SYNOPSIS
    Remove XPS Viewer Windows Feature

.DESCRIPTION
    Removes the XPS Viewer feature from Windows Server 2025.
    This script checks if the feature is installed and removes it if needed.

.NOTES
    File Name      : windows-server-remove_windowsfeature_XPSViewer.ps1
    Prerequisite   : PowerShell 5.1 or higher, ServerManager module
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-remove_windowsfeature_XPSViewer.ps1
    Removes the XPS Viewer feature
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$WindowsFeature = 'XPS-Viewer'

# Logging function
$script:Component = 'XPSViewer'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [XPSViewer] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

# Main script execution
$startTime = Get-Date

try {
    Write-Log "===== Remove_Windowsfeature_XPSViewer starting ====="

    # Verify ServerManager module is available
    if (-not (Get-Module -ListAvailable -Name ServerManager)) {
        throw "ServerManager module is not available on this system"
    }

    Import-Module ServerManager -ErrorAction Stop

    # Check feature status
    $feature = Get-WindowsFeature -Name $WindowsFeature -ErrorAction Stop

    if (-not $feature) {
        Write-Log "Feature '$WindowsFeature' does not exist on this system" -Level WARN
        Write-Log "===== Remove_Windowsfeature_XPSViewer complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
        exit 0
    }

    switch ($feature.InstallState) {
        'Available' {
            Write-Log "Feature '$WindowsFeature' is already removed"
        }
        'Installed' {
            Write-Log "Removing feature '$WindowsFeature'..."
            $result = Uninstall-WindowsFeature -Name $WindowsFeature -IncludeAllSubFeature -ErrorAction Stop

            if ($result.Success) {
                Write-Log "Feature '$WindowsFeature' removed successfully"
                if ($result.RestartNeeded -eq 'Yes') {
                    Write-Log "A system restart is required to complete the removal" -Level WARN
                }
            } else {
                throw "Removal failed with exit code: $($result.ExitCode)"
            }
        }
        default {
            Write-Log "Feature '$WindowsFeature' is in state: $($feature.InstallState)" -Level WARN
        }
    }

    Write-Log "===== Remove_Windowsfeature_XPSViewer complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
