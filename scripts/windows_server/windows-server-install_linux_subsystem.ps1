<#
.SYNOPSIS
    Install Windows Subsystem for Linux (WSL)

.DESCRIPTION
    Enables the Windows Subsystem for Linux feature on Windows Server 2025.
    After installation, Linux distributions can be installed from Microsoft Store.

.NOTES
    File Name      : windows-server-install_linux_subsystem.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_linux_subsystem.ps1
    Enables WSL feature
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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
    Write-Host "[$timestamp] [$prefix] [WSL] $Message"
}

# Main script execution
try {
    Write-Log "Enabling Windows Subsystem for Linux feature..."
    Enable-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online -NoRestart | Out-Null
    Write-Log "WSL feature enabled successfully"
    Write-Log "Install your preferred Linux distribution from the Microsoft Store" -Level Warning
    Write-Log "After installing Linux, run these commands inside your Linux shell to install PowerShell:" -Level Info
    Write-Log "  sudo apt-get update"
    Write-Log "  sudo apt-get install curl apt-transport-https"
    Write-Log "  curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -"
    Write-Log "  sudo sh -c 'echo \"deb https://packages.microsoft.com/repos/microsoft-debian-stretch-prod stretch main\" > /etc/apt/sources.list.d/microsoft.list'"
    Write-Log "  sudo apt-get update"
    Write-Log "  sudo apt-get install -y powershell"
    Write-Log "  pwsh"
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
