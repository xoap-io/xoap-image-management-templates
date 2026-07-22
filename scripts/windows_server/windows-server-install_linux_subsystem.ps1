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

$script:Component = 'WSL'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [WSL] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

# Main script execution
try {
    $startTime = Get-Date
    Write-Log "===== install_linux_subsystem starting ====="
    Write-Log "Enabling Windows Subsystem for Linux feature..."
    Enable-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online -NoRestart | Out-Null
    Write-Log "WSL feature enabled successfully"
    Write-Log "Install your preferred Linux distribution from the Microsoft Store" -Level WARN
    Write-Log "After installing Linux, run these commands inside your Linux shell to install PowerShell:" -Level INFO
    Write-Log "  sudo apt-get update"
    Write-Log "  sudo apt-get install curl apt-transport-https"
    Write-Log "  curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -"
    Write-Log "  sudo sh -c 'echo \"deb https://packages.microsoft.com/repos/microsoft-debian-stretch-prod stretch main\" > /etc/apt/sources.list.d/microsoft.list'"
    Write-Log "  sudo apt-get update"
    Write-Log "  sudo apt-get install -y powershell"
    Write-Log "  pwsh"
    Write-Log "===== install_linux_subsystem complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
