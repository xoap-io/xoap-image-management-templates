<#
.SYNOPSIS
    Install Chocolatey Package Manager

.DESCRIPTION
    Installs Chocolatey package manager on Windows 10/11.
    Uses native compression for faster installation.

.NOTES
    File Name      : windows11-install_chocolatey.ps1
    Prerequisite   : PowerShell 5.1 or higher
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-install_chocolatey.ps1
    Installs Chocolatey package manager
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$env:chocolateyUseWindowsCompression = 'false'
$chocoScript = 'C:\Windows\Temp\choco.ps1'
$chocoUrl = 'https://chocolatey.org/install.ps1'

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
    Write-Host "[$timestamp] [$prefix] [Chocolatey] $Message"
}

# Main script execution
try {
    Write-Log "Starting Chocolatey installation..."
    
    # Check if Chocolatey is already installed
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    if ($chocoCmd) {
        Write-Log "Chocolatey is already installed at: $($chocoCmd.Source)"
        exit 0
    }
    
    # Download Chocolatey installation script
    Write-Log "Downloading Chocolatey install script from: $chocoUrl"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($chocoUrl, $chocoScript)
    
    if (-not (Test-Path $chocoScript)) {
        throw "Failed to download Chocolatey installation script"
    }
    
    # Execute installation script
    Write-Log "Executing Chocolatey installation script..."
    & $chocoScript
    
    # Verify installation
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $chocoCmd) {
        throw "Chocolatey installation completed but 'choco' command not found"
    }
    
    Write-Log "Chocolatey installed successfully at: $($chocoCmd.Source)"
    
    # Cleanup
    if (Test-Path $chocoScript) {
        Remove-Item $chocoScript -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up installation script"
    }
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
