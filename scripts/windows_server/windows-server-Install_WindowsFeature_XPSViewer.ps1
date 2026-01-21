<#
.SYNOPSIS
    Install XPS Viewer Windows Feature

.DESCRIPTION
    Installs the XPS Viewer feature on Windows Server 2025.
    This script checks if the feature is available and installs it if needed.

.NOTES
    File Name      : windows-server-Install_WindowsFeature_XPSViewer.ps1
    Prerequisite   : PowerShell 5.1 or higher, ServerManager module
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Install_WindowsFeature_XPSViewer.ps1
    Installs the XPS Viewer feature
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$WindowsFeature = 'XPS-Viewer'

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
    Write-Host "[$timestamp] [$prefix] [XPSViewer] $Message"
}

# Main script execution
try {
    Write-Log "Starting XPS Viewer installation check..."
    
    # Verify ServerManager module is available
    if (-not (Get-Module -ListAvailable -Name ServerManager)) {
        throw "ServerManager module is not available on this system"
    }
    
    Import-Module ServerManager -ErrorAction Stop
    
    # Check feature status
    $feature = Get-WindowsFeature -Name $WindowsFeature -ErrorAction Stop
    
    if (-not $feature) {
        Write-Log "Feature '$WindowsFeature' does not exist on this system" -Level Warning
        exit 0
    }
    
    switch ($feature.InstallState) {
        'Installed' {
            Write-Log "Feature '$WindowsFeature' is already installed"
            exit 0
        }
        'Available' {
            Write-Log "Installing feature '$WindowsFeature'..."
            $result = Install-WindowsFeature -Name $WindowsFeature -IncludeAllSubFeature -ErrorAction Stop
            
            if ($result.Success) {
                Write-Log "Feature '$WindowsFeature' installed successfully"
                if ($result.RestartNeeded -eq 'Yes') {
                    Write-Log "A system restart is required to complete the installation" -Level Warning
                }
            } else {
                throw "Installation failed with exit code: $($result.ExitCode)"
            }
        }
        default {
            Write-Log "Feature '$WindowsFeature' is in state: $($feature.InstallState)" -Level Warning
        }
    }
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
