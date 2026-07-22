<#
.SYNOPSIS
    Installs Mozilla Firefox using Chocolatey on Windows Server 2025

.DESCRIPTION
    This script installs Mozilla Firefox using Chocolatey.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

#>
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Chocolatey] Transcript unavailable: $($_.Exception.Message)" }

function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [Chocolatey] $Message"
}

trap {
    Write-Log "$_" -Level ERROR
    Write-Log "$($_.ScriptStackTrace)" -Level ERROR
    Write-Log "Exception: $($_.Exception.ToString())" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log "===== Install_Mozilla_Firefox_Chocolatey starting ====="
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
    # choco: 0 = success, 1641/3010 = reboot
    if ($LASTEXITCODE -notin @(0, 1641, 3010)) { throw "choco install failed (exit code $LASTEXITCODE)" }
    Write-Log "Mozilla Firefox installed successfully."
    Write-Log "===== Install_Mozilla_Firefox_Chocolatey complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit 0
