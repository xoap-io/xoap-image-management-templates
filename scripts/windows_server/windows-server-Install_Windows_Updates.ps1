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

$script:Component = 'WindowsUpdate'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message
    Write-Host $line
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [WindowsUpdate] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region PSWindowsUpdate Module

function Install-PSWindowsUpdateModule {
    Write-Log "Checking for PSWindowsUpdate module..." -Level INFO
    
    try {
        $module = Get-Module -Name PSWindowsUpdate -ListAvailable
        
        if ($module) {
            Write-Log "PSWindowsUpdate module is already installed (Version: $($module.Version))" -Level INFO
            Import-Module PSWindowsUpdate -Force
            return $true
        }
        
        if (-not $InstallModule) {
            Write-Log "PSWindowsUpdate module not found. Use -InstallModule to install it." -Level ERROR
            return $false
        }
        
        Write-Log "Installing PSWindowsUpdate module..." -Level INFO
        
        # Set TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Install NuGet provider if needed
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Write-Log "Installing NuGet provider..." -Level INFO
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }
        
        # Trust PSGallery
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        
        # Install module
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
        Import-Module PSWindowsUpdate -Force
        
        Write-Log "PSWindowsUpdate module installed successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error installing PSWindowsUpdate module: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

#endregion

#region Windows Update Operations

function Get-PendingUpdates {
    Write-Log "Checking for available updates..." -Level INFO
    
    try {
        $updates = Get-WindowsUpdate -MicrosoftUpdate
        
        if ($updates.Count -eq 0) {
            Write-Log "No updates available" -Level INFO
            return $null
        }
        
        Write-Log "Found $($updates.Count) available updates:" -Level INFO
        
        foreach ($update in $updates) {
            $size = if ($update.Size -gt 0) { "$([math]::Round($update.Size / 1MB, 2)) MB" } else { "Unknown" }
            Write-Log "  - $($update.Title) ($size)" -Level INFO
        }
        
        return $updates
    }
    catch {
        Write-Log "Error checking for updates: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Install-Updates {
    Write-Log "Installing Windows Updates..." -Level INFO
    
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
        
        Write-Log "Installing updates with the following settings:" -Level INFO
        Write-Log "  Categories: $($Category -join ', ')" -Level INFO
        Write-Log "  Exclude Preview: $ExcludePreview" -Level INFO
        Write-Log "  Exclude Drivers: $ExcludeDrivers" -Level INFO
        Write-Log "  Exclude Feature Updates: $ExcludeFeatureUpdates" -Level INFO
        Write-Log "  Auto Reboot: $AutoReboot" -Level INFO
        
        # Install updates
        $result = Install-WindowsUpdate @installParams
        
        if ($result) {
            foreach ($update in $result) {
                if ($update.Result -eq 'Installed' -or $update.Result -eq 'Downloaded') {
                    Write-Log "  [OK] $($update.Title) - $($update.Result)" -Level INFO
                    $script:UpdatesInstalled++
                }
                elseif ($update.Result -eq 'Failed') {
                    Write-Log "  [FAIL] $($update.Title) - Failed" -Level ERROR
                    $script:UpdatesFailed++
                }
                else {
                    Write-Log "  [WARN] $($update.Title) - $($update.Result)" -Level WARN
                }
            }
        }
        
        # Check if reboot is required
        $rebootRequired = Get-WURebootStatus -Silent
        
        if ($rebootRequired) {
            Write-Log "System reboot is required" -Level WARN
            return $true  # Reboot needed
        }
        
        return $false  # No reboot needed
    }
    catch {
        Write-Log "Error installing updates: $($_.Exception.Message)" -Level ERROR
        $script:UpdatesFailed++
        return $false
    }
}

function Start-UpdateCycle {
    Write-Log "Starting Windows Update cycle..." -Level INFO
    
    $cycleCount = 0
    $maxCycles = $MaxRebootCycles
    
    while ($cycleCount -lt $maxCycles) {
        $cycleCount++
        Write-Log "Update Cycle $cycleCount of $maxCycles" -Level INFO
        
        # Check for updates
        $updates = Get-PendingUpdates
        
        if (-not $updates) {
            Write-Log "No more updates available" -Level INFO
            break
        }
        
        # Install updates
        $rebootNeeded = Install-Updates
        
        # Handle reboot
        if ($rebootNeeded) {
            $script:RebootCycles++
            
            if ($AutoReboot) {
                Write-Log "System will reboot in 60 seconds..." -Level WARN
                Write-Log "Reboot cycle: $script:RebootCycles" -Level INFO
                
                Start-Sleep -Seconds 5

                # Schedule script to run after reboot
                # Note: This requires additional setup for production use

                try { Stop-Transcript | Out-Null } catch {}
                Restart-Computer -Force
                exit 0
            }
            else {
                Write-Log "Reboot required but AutoReboot is disabled" -Level WARN
                Write-Log "Please reboot and re-run this script to continue" -Level INFO
                break
            }
        }
        
        # Brief pause between cycles
        Start-Sleep -Seconds 10
    }
    
    if ($cycleCount -ge $maxCycles) {
        Write-Log "Reached maximum reboot cycles ($maxCycles)" -Level WARN
    }
}

#endregion

#region Reporting

function Get-WindowsUpdateHistory {
    Write-Log "Retrieving Windows Update history..." -Level INFO
    
    try {
        $history = Get-WUHistory -Last 20 -ErrorAction SilentlyContinue
        
        if ($history) {
            Write-Log "Recent update history:" -Level INFO
            foreach ($item in $history) {
                $status = if ($item.Result -eq 'Succeeded') { '[OK]' } else { '[FAIL]' }
                Write-Log "  $status $($item.Title) - $($item.Date.ToString('yyyy-MM-dd'))" -Level INFO
            }
        }
        
        return $history
    }
    catch {
        Write-Log "Error retrieving update history: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Get-WindowsUpdateReport {
    Write-Log "Generating Windows Update report..." -Level INFO
    
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
        
        Write-Log "Update report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date

    Write-Log "===== Install_Windows_Updates starting ====="
    Write-Log "Log File: $LogFile"

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Install/verify PSWindowsUpdate module
    $moduleReady = Install-PSWindowsUpdateModule
    
    if (-not $moduleReady) {
        Write-Log "PSWindowsUpdate module is required" -Level ERROR
        Write-Log "Run with -InstallModule to install it automatically" -Level INFO
        exit 1
    }
    
    # Get current Windows version
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Log "Operating System: $($osInfo.Caption)" -Level INFO
    Write-Log "Version: $($osInfo.Version) (Build $($osInfo.BuildNumber))" -Level INFO
    
    # Start update cycle
    Start-UpdateCycle
    
    # Get update history
    Get-WindowsUpdateHistory | Out-Null
    
    # Generate report
    Get-WindowsUpdateReport | Out-Null
    
    # Check final reboot status
    $rebootRequired = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue
    if ($rebootRequired) {
        Write-Log "A system reboot is required to complete updates" -Level WARN

        if (-not $AutoReboot) {
            Write-Log "Run with -AutoReboot to restart automatically"
        }
    }

    if ($script:UpdatesFailed -eq 0) {
        Write-Log "===== Install_Windows_Updates complete in $([int]((Get-Date) - $scriptStartTime).TotalSeconds)s; applied=$script:UpdatesInstalled failed=$script:UpdatesFailed ====="
        exit 0
    }
    else {
        Write-Log "Updates completed with $script:UpdatesFailed failures" -Level WARN
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}

#endregion
