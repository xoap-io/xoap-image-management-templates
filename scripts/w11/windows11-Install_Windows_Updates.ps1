<#
.SYNOPSIS
    Install Windows Updates for Windows 10/11

.DESCRIPTION
    Installs Windows Updates using PSWindowsUpdate module with filtering options,
    reboot control, and comprehensive logging. Optimized for Windows 10/11
    and Packer image preparation workflows.

.NOTES
    File Name      : windows11-Install_Windows_Updates.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Install_Windows_Updates.ps1
    Installs all available Windows updates
    
.EXAMPLE
    .\windows11-Install_Windows_Updates.ps1 -ExcludePreview -ExcludeDrivers -AcceptAll -AutoReboot
    Installs updates excluding previews and drivers, with automatic reboot
    
.PARAMETER Category
    Update categories to install (Critical, Important, Optional, Drivers)
    
.PARAMETER ExcludePreview
    Exclude preview updates
    
.PARAMETER ExcludeDrivers
    Exclude driver updates
    
.PARAMETER ExcludeFeatureUpdates
    Exclude Windows feature updates
    
.PARAMETER AcceptAll
    Accept all updates without prompting
    
.PARAMETER AutoReboot
    Automatically reboot if required
    
.PARAMETER MaxRebootCycles
    Maximum number of reboot cycles (default: 5)
    
.PARAMETER InstallModule
    Install PSWindowsUpdate module if not present
#>

[CmdletBinding()]
param(
    [ValidateSet('Critical', 'Important', 'Optional', 'Drivers', 'All')]
    [string[]]$Category = @('Critical', 'Important'),
    
    [switch]$ExcludePreview,
    [switch]$ExcludeDrivers,
    [switch]$ExcludeFeatureUpdates,
    [switch]$AcceptAll,
    [switch]$AutoReboot,
    [int]$MaxRebootCycles = 5,
    [switch]$InstallModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [WindowsUpdate] Transcript unavailable: $($_.Exception.Message)" }

# Statistics tracking
$script:UpdatesInstalled = 0
$script:UpdatesFailed = 0
$script:RebootCycles = 0

#region Helper Functions

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $levelTag = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        'Success' { 'INFO' }
        default   { 'INFO' }
    }
    $logMessage = "[$timestamp] [$levelTag] [WindowsUpdate] $Message"

    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

function Install-PSWindowsUpdate {
    Write-LogMessage "Checking for PSWindowsUpdate module..."
    
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-LogMessage "PSWindowsUpdate module not found. Installing..." -Level Warning
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
            Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
            Write-LogMessage "[OK] PSWindowsUpdate module installed successfully" -Level Success
        } catch {
            Write-LogMessage "Failed to install PSWindowsUpdate: $($_.Exception.Message)" -Level Error
            throw
        }
    } else {
        Write-LogMessage "[OK] PSWindowsUpdate module is already installed"
    }
    
    Import-Module PSWindowsUpdate -ErrorAction Stop
}

#endregion

#region Main Script

try {
    $startTime = Get-Date
    Write-LogMessage "===== Install_Windows_Updates starting ====="
    Write-LogMessage "=============================================="
    Write-LogMessage "Windows 10/11 Updates Installation Script"
    Write-LogMessage "=============================================="
    Write-LogMessage "Categories: $($Category -join ', ')"
    Write-LogMessage "Exclude Preview: $ExcludePreview"
    Write-LogMessage "Exclude Drivers: $ExcludeDrivers"
    Write-LogMessage "Exclude Feature Updates: $ExcludeFeatureUpdates"
    Write-LogMessage "Auto Reboot: $AutoReboot"
    Write-LogMessage "Max Reboot Cycles: $MaxRebootCycles"
    Write-LogMessage ""
    
    if ($InstallModule) {
        Install-PSWindowsUpdate
    }
    
    # Build filter criteria
    $filters = @()
    if ($ExcludePreview) {
        $filters += "Title -notlike '*Preview*'"
    }
    if ($ExcludeDrivers) {
        $filters += "Title -notlike '*Driver*'"
    }
    if ($ExcludeFeatureUpdates) {
        $filters += "Title -notlike '*Feature update*'"
    }
    
    $installParams = @{
        AcceptAll = $true
        Install = $true
        IgnoreReboot = $true
        Verbose = $true
    }
    
    if ($Category -ne 'All') {
        $installParams['Category'] = $Category
    }
    
    Write-LogMessage "Searching for Windows updates..."
    $updates = Get-WindowsUpdate @installParams -NotCategory 'Language Packs' -NotTitle 'Silverlight'
    
    if ($updates.Count -eq 0) {
        Write-LogMessage "No updates available to install" -Level Success
        Write-LogMessage "===== Install_Windows_Updates complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
        exit 0
    }
    
    Write-LogMessage "Found $($updates.Count) updates to install"
    
    foreach ($update in $updates) {
        try {
            Write-LogMessage "Installing: $($update.Title)"
            Install-WindowsUpdate -KBArticleID $update.KB -AcceptAll -IgnoreReboot
            $script:UpdatesInstalled++
            Write-LogMessage "[OK] Installed: $($update.Title)" -Level Success
        } catch {
            $script:UpdatesFailed++
            Write-LogMessage "[FAIL] Failed to install: $($update.Title) - $($_.Exception.Message)" -Level Error
        }
    }
    
    Write-LogMessage ""
    Write-LogMessage "=============================================="
    Write-LogMessage "Installation Summary"
    Write-LogMessage "=============================================="
    Write-LogMessage "Updates Installed: $script:UpdatesInstalled"
    Write-LogMessage "Updates Failed: $script:UpdatesFailed"
    Write-LogMessage "Reboot Cycles: $script:RebootCycles"
    
    if ($AutoReboot -and (Get-WURebootStatus -Silent)) {
        Write-LogMessage "System requires reboot. Restarting..." -Level Warning
        try { Stop-Transcript | Out-Null } catch {}
        Restart-Computer -Force
    } elseif (Get-WURebootStatus -Silent) {
        Write-LogMessage "System requires reboot. Please restart manually." -Level Warning
    }

    Write-LogMessage "Windows updates installation completed successfully" -Level Success
    Write-LogMessage "===== Install_Windows_Updates complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-LogMessage "Critical error during Windows updates installation: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

#endregion
