<#
.SYNOPSIS
    Install Evergreen PowerShell Module

.DESCRIPTION
    Installs and updates the Evergreen module for application version management on Windows Server 2025.

.NOTES
    File Name      : windows-server-install_module_evergreen.ps1
    Prerequisite   : PowerShell 5.1 or higher, Internet connection
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_module_evergreen
    Installs the Evergreen module
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
    Write-Host "[$timestamp] [$prefix] [Evergreen] $Message"
}

# Main script execution
try {
    Write-Log "Starting Evergreen module installation..."
    
    # Check if module is already installed
    $existingModule = Get-Module -ListAvailable -Name Evergreen
    if ($existingModule) {
        Write-Log "Evergreen module already installed (Version: $($existingModule.Version))"
        Write-Log "Updating to latest version..."
        Update-Module -Name Evergreen -Force -ErrorAction Stop
    } else {
        Write-Log "Installing Evergreen module from PSGallery..."
        Install-Module -Name Evergreen -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
    }
    
    # Import and verify
    Write-Log "Importing Evergreen module..."
    Import-Module -Name Evergreen -Force -ErrorAction Stop
    
    # Get installed version
    $module = Get-Module -Name Evergreen
    if ($module) {
        Write-Log "Evergreen module ready (Version: $($module.Version))"
    } else {
        throw "Module import verification failed"
    }
    
    Write-Log "Evergreen module installation completed successfully"
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
