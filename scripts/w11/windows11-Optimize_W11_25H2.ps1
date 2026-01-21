<#
.SYNOPSIS
    Optimize Windows 11 25H2 for Performance and Imaging

.DESCRIPTION
    Comprehensive optimization script for Windows 11 version 25H2 including:
    - Service optimization and disabling unnecessary services
    - Scheduled task management
    - Windows trace and telemetry reduction
    - Registry optimizations for performance
    - Disk cleanup and Windows Defender optimization
    - Network and power settings optimization
    - UI and visual effects optimization
    - Prepared for imaging and deployment scenarios

.NOTES
    File Name      : windows11-Optimize_W11_25H2.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Optimize_W11_25H2.ps1
    Runs full optimization with default settings
    
.EXAMPLE
    .\windows11-Optimize_W11_25H2.ps1 -SkipDefender -SkipDiskCleanup
    Runs optimization while skipping Windows Defender and disk cleanup
    
.PARAMETER SkipDefender
    Skip Windows Defender optimization and scanning
    
.PARAMETER SkipDiskCleanup
    Skip disk cleanup operations
    
.PARAMETER SkipServices
    Skip service optimization
    
.PARAMETER SkipScheduledTasks
    Skip scheduled task optimization
#>

[CmdletBinding()]
param(
    [switch]$SkipDefender,
    [switch]$SkipDiskCleanup,
    [switch]$SkipServices,
    [switch]$SkipScheduledTasks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = "$env:SystemDrive\Temp"
$scriptName = 'windows11-optimize-25h2'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [W11-25H2] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

# Main execution
try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    Write-Log "========================================================="
    Write-Log "Windows 11 25H2 Optimization Script"
    Write-Log "========================================================="
    Write-Log "OS Version: $([Environment]::OSVersion.Version)"
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log ""
    
    # Enable TLS 1.2
    Write-Log "Enabling TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    
    #region Service Optimization
    if (-not $SkipServices) {
        Write-Log "Optimizing Windows services..."
        
        $ServicesToDisable = @(
            "autotimesvc",              # Auto Time Zone Updater
            "BcastDVRUserService",      # GameDVR and Broadcast
            "CDPSvc",                   # Connected Devices Platform
            "CDPUserSvc",               # Connected Devices Platform User
            "CscService",               # Offline Files
            "defragsvc",                # Optimize Drives (manual is better)
            "DiagTrack",                # Connected User Experiences and Telemetry
            "DsmSvc",                   # Device Setup Manager
            "DusmSvc",                  # Data Usage
            "icssvc",                   # Windows Mobile Hotspot
            "lfsvc",                    # Geolocation
            "MapsBroker",               # Downloaded Maps Manager
            "MessagingService",         # Messaging Service
            "OneSyncSvc",               # Sync Host
            "PimIndexMaintenanceSvc",   # Contact Data
            "RetailDemo",               # Retail Demo Service
            "SharedRealitySvc",         # Spatial Data Service
            "Spooler",                  # Print Spooler (disable if no printers)
            "SSDPSRV",                  # SSDP Discovery
            "SysMain",                  # Superfetch/SysMain
            "TabletInputService",       # Touch Keyboard and Handwriting
            "WalletService",            # WalletService
            "WbioSrvc",                 # Windows Biometric Service (if not using)
            "WerSvc",                   # Windows Error Reporting
            "wisvc",                    # Windows Insider Service
            "WMPNetworkSvc",            # Windows Media Player Network Sharing
            "WSearch"                   # Windows Search (consider keeping for users)
        )
        
        foreach ($service in $ServicesToDisable) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc) {
                    if ($svc.StartType -ne 'Disabled') {
                        Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
                        Write-Log "✓ Disabled service: $service"
                        $script:OptimizationsApplied++
                    }
                    if ($svc.Status -eq 'Running') {
                        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                Write-Log "Failed to disable service $service : $($_.Exception.Message)" -Level Warning
                $script:OptimizationsFailed++
            }
        }
    } else {
        Write-Log "Skipping service optimization (SkipServices specified)"
    }
    #endregion

    #region Scheduled Tasks Optimization
    if (-not $SkipScheduledTasks) {
        Write-Log "Optimizing scheduled tasks..."
        
        $TasksToDisable = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\PcaPatchDbTask",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Application Experience\StartupAppTask",
            "\Microsoft\Windows\Autochk\Proxy",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\Defrag\ScheduledDefrag",
            "\Microsoft\Windows\Device Information\Device",
            "\Microsoft\Windows\DiskCleanup\SilentCleanup",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
            "\Microsoft\Windows\Feedback\Siuf\DmClient",
            "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
            "\Microsoft\Windows\Location\Notifications",
            "\Microsoft\Windows\Location\WindowsActionDialog",
            "\Microsoft\Windows\Maps\MapsToastTask",
            "\Microsoft\Windows\Maps\MapsUpdateTask",
            "\Microsoft\Windows\Mobile Broadband Accounts\MNO Metadata Parser",
            "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
            "\Microsoft\Windows\Shell\FamilySafetyMonitor",
            "\Microsoft\Windows\Shell\FamilySafetyRefreshTask",
            "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
            "\Microsoft\Windows\WindowsUpdate\Scheduled Start"
        )
        
        foreach ($task in $TasksToDisable) {
            try {
                $schTask = Get-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
                if ($schTask -and $schTask.State -ne 'Disabled') {
                    Disable-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop | Out-Null
                    Write-Log "✓ Disabled scheduled task: $task"
                    $script:OptimizationsApplied++
                }
            } catch {
                Write-Log "Failed to disable scheduled task $task : $($_.Exception.Message)" -Level Warning
                $script:OptimizationsFailed++
            }
        }
    } else {
        Write-Log "Skipping scheduled task optimization (SkipScheduledTasks specified)"
    }
    #endregion

    #region Windows Traces and Autologgers
    Write-Log "Disabling Windows traces and autologgers..."
    
    $AutologgersToDisable = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AppModel",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\CloudExperienceHostOOBE",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DiagLog",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\ReadyBoot",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WDIContextLog",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiDriverIHVSession",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiSession",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Cellcore",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WinPhoneCritical"
    )
    
    foreach ($autologger in $AutologgersToDisable) {
        try {
            if (Test-Path $autologger) {
                New-ItemProperty -Path $autologger -Name "Start" -PropertyType DWORD -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
                Write-Log "✓ Disabled autologger: $(Split-Path $autologger -Leaf)"
                $script:OptimizationsApplied++
            }
        } catch {
            Write-Log "Failed to disable autologger $autologger : $($_.Exception.Message)" -Level Warning
        }
    }
    #endregion

    #region Registry Optimizations
    Write-Log "Applying registry optimizations..."
    
    $RegistryOptimizations = @(
        # Disable Windows Consumer Features
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Value=1},
        
        # Disable Cortana
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name='AllowCortana'; Value=0},
        
        # Disable Web Search in Start Menu
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name='DisableWebSearch'; Value=1},
        
        # Disable Windows Tips
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableSoftLanding'; Value=1},
        
        # Disable Activity History
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='EnableActivityFeed'; Value=0},
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='PublishUserActivities'; Value=0},
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='UploadUserActivities'; Value=0},
        
        # Disable Advertising ID
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name='DisabledByGroupPolicy'; Value=1},
        
        # Disable GameDVR
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name='AllowGameDVR'; Value=0},
        
        # Disable Delivery Optimization
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name='DODownloadMode'; Value=0},
        
        # Network Throttling Index - Improves network performance
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='NetworkThrottlingIndex'; Value=4294967295},
        
        # System Responsiveness - Prioritize foreground apps
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='SystemResponsiveness'; Value=0},
        
        # Disable Auto Reboot with Logged On Users
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name='NoAutoRebootWithLoggedOnUsers'; Value=1},
        
        # Disable Timeline
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='EnableActivityFeed'; Value=0},
        
        # Visual Effects - Performance mode
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name='VisualFXSetting'; Value=2}
    )
    
    foreach ($reg in $RegistryOptimizations) {
        try {
            if (-not (Test-Path $reg.Path)) {
                New-Item -Path $reg.Path -Force | Out-Null
            }
            New-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -PropertyType DWORD -Force -ErrorAction Stop | Out-Null
            Write-Log "✓ Applied registry optimization: $($reg.Path)\$($reg.Name)"
            $script:OptimizationsApplied++
        } catch {
            Write-Log "Failed to apply registry optimization $($reg.Path)\$($reg.Name) : $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    #endregion

    #region Windows Defender Optimization
    if (-not $SkipDefender) {
        Write-Log "Optimizing Windows Defender..."
        
        try {
            # Update definitions
            Write-Log "Updating Windows Defender definitions..."
            Update-MpSignature -ErrorAction SilentlyContinue
            
            # Quick scan
            Write-Log "Running Windows Defender quick scan..."
            Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue
            
            Write-Log "✓ Windows Defender optimization completed"
            $script:OptimizationsApplied++
        } catch {
            Write-Log "Windows Defender optimization failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    } else {
        Write-Log "Skipping Windows Defender optimization (SkipDefender specified)"
    }
    #endregion

    #region Disk Cleanup
    if (-not $SkipDiskCleanup) {
        Write-Log "Running disk cleanup..."
        
        try {
            # Clean temp files
            $tempPaths = @(
                "$env:SystemRoot\Temp",
                "$env:TEMP",
                "$env:SystemRoot\SoftwareDistribution\Download",
                "$env:SystemRoot\Prefetch"
            )
            
            foreach ($tempPath in $tempPaths) {
                if (Test-Path $tempPath) {
                    Write-Log "Cleaning: $tempPath"
                    Get-ChildItem -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue | 
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            
            # Run Disk Cleanup
            Write-Log "Running Disk Cleanup utility..."
            Start-Process -FilePath cleanmgr.exe -ArgumentList "/sagerun:1" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            
            Write-Log "✓ Disk cleanup completed"
            $script:OptimizationsApplied++
        } catch {
            Write-Log "Disk cleanup failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    } else {
        Write-Log "Skipping disk cleanup (SkipDiskCleanup specified)"
    }
    #endregion

    #region Power Settings
    Write-Log "Configuring power settings for performance..."
    
    try {
        # Set to High Performance power plan
        $highPerf = powercfg /list | Select-String -Pattern "High performance" | ForEach-Object { 
            if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { 
                $matches[0] 
            } 
        }
        
        if ($highPerf) {
            powercfg /setactive $highPerf
            Write-Log "✓ Set power plan to High Performance"
            $script:OptimizationsApplied++
        }
        
        # Disable hibernation
        powercfg /hibernate off
        Write-Log "✓ Disabled hibernation"
        $script:OptimizationsApplied++
        
    } catch {
        Write-Log "Power settings configuration failed: $($_.Exception.Message)" -Level Warning
        $script:OptimizationsFailed++
    }
    #endregion

    #region Network Optimization
    Write-Log "Optimizing network settings..."
    
    try {
        # Disable IPv6
        Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | 
            Disable-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        
        # Disable Large Send Offload
        Get-NetAdapterAdvancedProperty -DisplayName "Large Send Offload V2 (IPv4)" -ErrorAction SilentlyContinue | 
            Set-NetAdapterAdvancedProperty -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        
        Write-Log "✓ Network settings optimized"
        $script:OptimizationsApplied++
    } catch {
        Write-Log "Network optimization failed: $($_.Exception.Message)" -Level Warning
        $script:OptimizationsFailed++
    }
    #endregion

    #region Windows Store Apps Cleanup
    Write-Log "Cleaning up Windows Store apps cache..."
    
    try {
        WSReset.exe
        Start-Sleep -Seconds 5
        Get-Process WSReset -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "✓ Windows Store cache cleared"
        $script:OptimizationsApplied++
    } catch {
        Write-Log "Windows Store cleanup failed: $($_.Exception.Message)" -Level Warning
    }
    #endregion

    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Windows 11 25H2 Optimization Summary"
    Write-Log "========================================================="
    Write-Log "Optimizations applied: $script:OptimizationsApplied"
    Write-Log "Optimizations failed: $script:OptimizationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    Write-Log "Optimization completed successfully!"
    Write-Log ""
    Write-Log "Note: Some changes may require a system restart to take effect."
    Write-Log "Log file: $LogFile"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
