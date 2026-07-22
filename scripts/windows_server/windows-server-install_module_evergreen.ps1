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

$script:Component = 'Evergreen'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [Evergreen] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

# Main script execution
try {
    $startTime = Get-Date
    Write-Log "===== install_module_evergreen starting ====="
    
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
    
    Write-Log "===== install_module_evergreen complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
