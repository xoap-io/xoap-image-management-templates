<#
.SYNOPSIS
    Install PowerShellGet Module

.DESCRIPTION
    Installs and updates the PowerShellGet module and NuGet package provider on Windows 10/11.

.NOTES
    File Name      : windows11-install_powershellget.ps1
    Prerequisite   : PowerShell 5.1 or higher
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-install_powershellget.ps1
    Installs PowerShellGet and NuGet provider
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
    Write-Host "[$timestamp] [$prefix] [PSGet] $Message"
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [PSGet] Transcript unavailable: $($_.Exception.Message)" }

# Main script execution
try {
    $startTime = Get-Date
    Write-Log '===== Install_PowerShellGet starting ====='
    Write-Log "Starting PowerShellGet installation..."
    
    # Set execution policy
    Write-Log "Setting execution policy to RemoteSigned..."
    Set-ExecutionPolicy RemoteSigned -Force -Scope LocalMachine
    
    # Install NuGet package provider first
    Write-Log "Installing NuGet package provider..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
    
    # Check if PowerShellGet is already installed
    $existingModule = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
    if ($existingModule) {
        Write-Log "PowerShellGet already installed (Version: $($existingModule.Version))"
        Write-Log "Updating to latest version..."
        Update-Module -Name PowerShellGet -Force -ErrorAction Stop
    } else {
        Write-Log "Installing PowerShellGet module..."
        Install-Module -Name PowerShellGet -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
    }
    
    # Verify installation
    $module = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
    if ($module) {
        Write-Log "PowerShellGet ready (Version: $($module.Version))"
    } else {
        throw "PowerShellGet installation verification failed"
    }
    
    Write-Log "PowerShellGet installation completed successfully"

    Write-Log "===== Install_PowerShellGet complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
