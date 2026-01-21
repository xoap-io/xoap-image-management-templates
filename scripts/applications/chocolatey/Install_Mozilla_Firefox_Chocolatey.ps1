<#
.SYNOPSIS
    Installs Mozilla Firefox using Chocolatey on Windows Server 2025

.DESCRIPTION
    This script installs Mozilla Firefox using Chocolatey.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. © RIS AG

.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-packer-templates

#>
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

try {
    $LogDir = 'C:\xoap-logs'
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Host "Logging to: $LogFile"
} catch { Write-Warning "Failed to start transcript logging to C:\xoap-logs: $($_.Exception.Message)" }

function Write-Log { param($Message); $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$timestamp] $Message" }

trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

try {
    # Check if Chocolatey is installed
    Write-Log "Checking for Chocolatey installation..."
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    
    if (-not $chocoCmd) {
        Write-Log "Chocolatey not found. Installing Chocolatey..."
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        
        # Verify installation
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
        if (-not $chocoCmd) {
            throw "Chocolatey installation failed"
        }
        Write-Log "Chocolatey installed successfully."
    } else {
        Write-Log "Chocolatey is already installed (version: $(choco --version))."
    }
    
    Write-Log "Installing Mozilla Firefox via Chocolatey..."
    choco install firefox -y --no-progress
    Write-Log "Mozilla Firefox installed successfully."
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
