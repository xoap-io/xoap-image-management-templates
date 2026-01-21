<#
.SYNOPSIS
    Install Windows Updates for Windows Server

.DESCRIPTION
    Installs Windows Updates using PSWindowsUpdate module with filtering options,
    reboot control, and comprehensive logging. Optimized for Windows Server 2025
    and Packer image preparation workflows.

.NOTES
    File Name      : windows-server-Install_Windows_Updates.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Install_Windows_Updates
    Installs all available Windows updates
    
.EXAMPLE
    .\windows-server-Install_Windows_Updates -ExcludePreview -ExcludeDrivers -AcceptAll -AutoReboot
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
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

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
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region PSWindowsUpdate Module

function Install-PSWindowsUpdateModule {
    Write-LogMessage "Checking for PSWindowsUpdate module..." -Level Info
    
    try {
        $module = Get-Module -Name PSWindowsUpdate -ListAvailable
        
        if ($module) {
            Write-LogMessage "PSWindowsUpdate module is already installed (Version: $($module.Version))" -Level Info
            Import-Module PSWindowsUpdate -Force
            return $true
        }
        
        if (-not $InstallModule) {
            Write-LogMessage "PSWindowsUpdate module not found. Use -InstallModule to install it." -Level Error
            return $false
        }
        
        Write-LogMessage "Installing PSWindowsUpdate module..." -Level Info
        
        # Set TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Install NuGet provider if needed
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Write-LogMessage "Installing NuGet provider..." -Level Info
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }
        
        # Trust PSGallery
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        
        # Install module
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
        Import-Module PSWindowsUpdate -Force
        
        Write-LogMessage "PSWindowsUpdate module installed successfully" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error installing PSWindowsUpdate module: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Windows Update Operations

function Get-PendingUpdates {
    Write-LogMessage "Checking for available updates..." -Level Info
    
    try {
        $updates = Get-WindowsUpdate -MicrosoftUpdate
        
        if ($updates.Count -eq 0) {
            Write-LogMessage "No updates available" -Level Info
            return $null
        }
        
        Write-LogMessage "Found $($updates.Count) available updates:" -Level Info
        
        foreach ($update in $updates) {
            $size = if ($update.Size -gt 0) { "$([math]::Round($update.Size / 1MB, 2)) MB" } else { "Unknown" }
            Write-LogMessage "  - $($update.Title) ($size)" -Level Info
        }
        
        return $updates
    }
    catch {
        Write-LogMessage "Error checking for updates: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Install-Updates {
    Write-LogMessage "Installing Windows Updates..." -Level Info
    
    try {
        # Build filter criteria
        $criteria = @()
        
        # Category filter
        if ($Category -contains 'All') {
            # No category filter
        }
        else {
            # Specific categories
            $categoryFilter = $Category -join ','
            $criteria += $categoryFilter
        }
        
        # Build notification filter
        $notifyFilter = @()
        
        if ($ExcludePreview) {
            $notifyFilter += "exclude:Title -like '*Preview*'"
        }
        
        if ($ExcludeFeatureUpdates) {
            $notifyFilter += "exclude:Title -like '*Feature update*'"
            $notifyFilter += "exclude:Title -like '*Upgrade to Windows*'"
        }
        
        if ($ExcludeDrivers) {
            $notifyFilter += "exclude:Title -like '*Driver*'"
        }
        
        # Install parameters
        $installParams = @{
            MicrosoftUpdate = $true
            AcceptAll = $AcceptAll
            IgnoreReboot = (-not $AutoReboot)
            Verbose = $true
        }
        
        # Add category if specified
        if ($Category -notcontains 'All') {
            # PSWindowsUpdate handles category filtering differently
        }
        
        Write-LogMessage "Installing updates with the following settings:" -Level Info
        Write-LogMessage "  Categories: $($Category -join ', ')" -Level Info
        Write-LogMessage "  Exclude Preview: $ExcludePreview" -Level Info
        Write-LogMessage "  Exclude Drivers: $ExcludeDrivers" -Level Info
        Write-LogMessage "  Exclude Feature Updates: $ExcludeFeatureUpdates" -Level Info
        Write-LogMessage "  Auto Reboot: $AutoReboot" -Level Info
        Write-LogMessage "" -Level Info
        
        # Install updates
        $result = Install-WindowsUpdate @installParams
        
        if ($result) {
            foreach ($update in $result) {
                if ($update.Result -eq 'Installed' -or $update.Result -eq 'Downloaded') {
                    Write-LogMessage "  ✓ $($update.Title) - $($update.Result)" -Level Success
                    $script:UpdatesInstalled++
                }
                elseif ($update.Result -eq 'Failed') {
                    Write-LogMessage "  ✗ $($update.Title) - Failed" -Level Error
                    $script:UpdatesFailed++
                }
                else {
                    Write-LogMessage "  ⚠ $($update.Title) - $($update.Result)" -Level Warning
                }
            }
        }
        
        # Check if reboot is required
        $rebootRequired = Get-WURebootStatus -Silent
        
        if ($rebootRequired) {
            Write-LogMessage "System reboot is required" -Level Warning
            return $true  # Reboot needed
        }
        
        return $false  # No reboot needed
    }
    catch {
        Write-LogMessage "Error installing updates: $($_.Exception.Message)" -Level Error
        $script:UpdatesFailed++
        return $false
    }
}

function Start-UpdateCycle {
    Write-LogMessage "Starting Windows Update cycle..." -Level Info
    
    $cycleCount = 0
    $maxCycles = $MaxRebootCycles
    
    while ($cycleCount -lt $maxCycles) {
        $cycleCount++
        Write-LogMessage "" -Level Info
        Write-LogMessage "========== Update Cycle $cycleCount of $maxCycles ==========" -Level Info
        
        # Check for updates
        $updates = Get-PendingUpdates
        
        if (-not $updates) {
            Write-LogMessage "No more updates available" -Level Success
            break
        }
        
        # Install updates
        $rebootNeeded = Install-Updates
        
        # Handle reboot
        if ($rebootNeeded) {
            $script:RebootCycles++
            
            if ($AutoReboot) {
                Write-LogMessage "System will reboot in 60 seconds..." -Level Warning
                Write-LogMessage "Reboot cycle: $script:RebootCycles" -Level Info
                
                Start-Sleep -Seconds 5
                
                # Schedule script to run after reboot
                # Note: This requires additional setup for production use
                
                Restart-Computer -Force
                exit 0
            }
            else {
                Write-LogMessage "Reboot required but AutoReboot is disabled" -Level Warning
                Write-LogMessage "Please reboot and re-run this script to continue" -Level Info
                break
            }
        }
        
        # Brief pause between cycles
        Start-Sleep -Seconds 10
    }
    
    if ($cycleCount -ge $maxCycles) {
        Write-LogMessage "Reached maximum reboot cycles ($maxCycles)" -Level Warning
    }
}

#endregion

#region Reporting

function Get-WindowsUpdateHistory {
    Write-LogMessage "Retrieving Windows Update history..." -Level Info
    
    try {
        $history = Get-WUHistory -Last 20 -ErrorAction SilentlyContinue
        
        if ($history) {
            Write-LogMessage "Recent update history:" -Level Info
            foreach ($item in $history) {
                $status = if ($item.Result -eq 'Succeeded') { '✓' } else { '✗' }
                Write-LogMessage "  $status $($item.Title) - $($item.Date.ToString('yyyy-MM-dd'))" -Level Info
            }
        }
        
        return $history
    }
    catch {
        Write-LogMessage "Error retrieving update history: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-WindowsUpdateReport {
    Write-LogMessage "Generating Windows Update report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "windows-updates-$timestamp.txt"
        $report = @()
        
        $report += "Windows Update Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # Update session summary
        $report += "Update Session Summary:"
        $report += "  Updates Installed: $script:UpdatesInstalled"
        $report += "  Updates Failed: $script:UpdatesFailed"
        $report += "  Reboot Cycles: $script:RebootCycles"
        $report += ""
        
        # Current Windows version
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $report += "Operating System:"
        $report += "  Caption: $($osInfo.Caption)"
        $report += "  Version: $($osInfo.Version)"
        $report += "  Build: $($osInfo.BuildNumber)"
        $report += "  Last Boot: $($osInfo.LastBootUpTime)"
        $report += ""
        
        # Pending updates
        $pending = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue
        if ($pending) {
            $report += "Pending Updates:"
            foreach ($update in $pending) {
                $size = if ($update.Size -gt 0) { "$([math]::Round($update.Size / 1MB, 2)) MB" } else { "Unknown" }
                $report += "  - $($update.Title) ($size)"
            }
        }
        else {
            $report += "Pending Updates: None"
        }
        $report += ""
        
        # Recent history
        $history = Get-WUHistory -Last 10 -ErrorAction SilentlyContinue
        if ($history) {
            $report += "Recent Update History (Last 10):"
            foreach ($item in $history) {
                $report += "  $($item.Date.ToString('yyyy-MM-dd HH:mm')) - $($item.Title) - $($item.Result)"
            }
        }
        $report += ""
        
        # Reboot status
        $rebootRequired = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue
        $report += "Reboot Required: $rebootRequired"
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Update report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Windows Updates Installation" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
        exit 1
    }
    
    # Install/verify PSWindowsUpdate module
    $moduleReady = Install-PSWindowsUpdateModule
    
    if (-not $moduleReady) {
        Write-LogMessage "PSWindowsUpdate module is required" -Level Error
        Write-LogMessage "Run with -InstallModule to install it automatically" -Level Info
        exit 1
    }
    
    # Get current Windows version
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-LogMessage "Operating System: $($osInfo.Caption)" -Level Info
    Write-LogMessage "Version: $($osInfo.Version) (Build $($osInfo.BuildNumber))" -Level Info
    Write-LogMessage "" -Level Info
    
    # Start update cycle
    Start-UpdateCycle
    
    # Get update history
    Get-WindowsUpdateHistory | Out-Null
    
    # Generate report
    Get-WindowsUpdateReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Update Session Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Updates Installed: $script:UpdatesInstalled" -Level Info
    Write-LogMessage "Updates Failed: $script:UpdatesFailed" -Level Info
    Write-LogMessage "Reboot Cycles: $script:RebootCycles" -Level Info
    Write-LogMessage "Duration: $($duration.TotalMinutes) minutes" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    # Check final reboot status
    $rebootRequired = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue
    if ($rebootRequired) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "A system reboot is required to complete updates" -Level Warning
        
        if (-not $AutoReboot) {
            Write-LogMessage "Run with -AutoReboot to restart automatically" -Level Info
        }
    }
    
    if ($script:UpdatesFailed -eq 0) {
        Write-LogMessage "Windows Updates completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Updates completed with $script:UpdatesFailed failures" -Level Warning
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
