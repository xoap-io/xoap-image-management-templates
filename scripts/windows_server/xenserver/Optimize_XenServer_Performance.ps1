<#
.SYNOPSIS
    Optimize Windows for XenServer/Citrix Hypervisor Performance

.DESCRIPTION
    Applies comprehensive optimizations for Windows running on XenServer/Citrix Hypervisor.
    Includes registry tweaks, service optimizations, and performance tuning specific
    to XenServer virtualization platform.
    
    Optimizations include:
    - XenServer-specific registry settings
    - Virtual machine detection and configuration
    - Network and storage performance tuning
    - Memory and processor optimizations
    - Power management configuration

.NOTES
    File Name      : Optimize_XenServer_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER SkipPowerSettings
    Skip power plan optimization

.PARAMETER SkipNetworkOptimization
    Skip network adapter optimization

.PARAMETER SkipStorageOptimization
    Skip storage performance optimization

.EXAMPLE
    .\Optimize_XenServer_Performance.ps1
    Applies all XenServer optimizations

.EXAMPLE
    .\Optimize_XenServer_Performance.ps1 -SkipPowerSettings
    Applies optimizations except power settings

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [switch]$SkipPowerSettings,
    [switch]$SkipNetworkOptimization,
    [switch]$SkipStorageOptimization
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = 'xenserver-optimize'
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
    $logMessage = "[$timestamp] [$prefix] [XenOpt] $Message"
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
    Write-Log "XenServer Performance Optimization"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log ""
    
    # Detect XenServer
    Write-Log "Detecting virtualization platform..."
    
    $isXenServer = $false
    $manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
    
    if ($manufacturer -like '*Xen*' -or $manufacturer -like '*Citrix*') {
        Write-Log "✓ XenServer/Citrix Hypervisor detected"
        $isXenServer = $true
    }
    else {
        Write-Log "Warning: XenServer not detected. Manufacturer: $manufacturer" -Level Warning
        Write-Log "Continuing with optimizations anyway..."
    }
    
    # Power settings optimization
    if (-not $SkipPowerSettings) {
        Write-Log ""
        Write-Log "Optimizing power settings..."
        
        try {
            # Set to High Performance
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
            
            # Disable hibernate
            powercfg /hibernate off
            Write-Log "✓ Disabled hibernation"
            $script:OptimizationsApplied++
            
            # Disable sleep timeout
            powercfg /change standby-timeout-ac 0
            powercfg /change standby-timeout-dc 0
            Write-Log "✓ Disabled sleep timeouts"
            $script:OptimizationsApplied++
            
        }
        catch {
            Write-Log "Power optimization failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Network optimization
    if (-not $SkipNetworkOptimization) {
        Write-Log ""
        Write-Log "Applying network optimizations..."
        
        try {
            # TCP/IP registry optimizations
            $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
            
            $tcpOptimizations = @{
                'TcpTimedWaitDelay' = 30
                'MaxUserPort' = 65534
                'TcpAckFrequency' = 1
                'TCPNoDelay' = 1
                'TcpDelAckTicks' = 0
            }
            
            foreach ($opt in $tcpOptimizations.GetEnumerator()) {
                Set-ItemProperty -Path $tcpipPath -Name $opt.Key -Value $opt.Value -Type DWord -Force
                Write-Log "✓ Set $($opt.Key) = $($opt.Value)"
                $script:OptimizationsApplied++
            }
            
            # Disable IPv6 (optional - can improve performance)
            Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | 
                Disable-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled IPv6"
            $script:OptimizationsApplied++
            
        }
        catch {
            Write-Log "Network optimization failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Storage optimization
    if (-not $SkipStorageOptimization) {
        Write-Log ""
        Write-Log "Applying storage optimizations..."
        
        try {
            # Disable defragmentation schedule
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled scheduled defragmentation"
            $script:OptimizationsApplied++
            
            # Optimize disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "✓ Set disk timeout to 60 seconds"
            $script:OptimizationsApplied++
            
            # Disable System Restore
            Disable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled System Restore"
            $script:OptimizationsApplied++
            
        }
        catch {
            Write-Log "Storage optimization failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Virtual machine specific optimizations
    Write-Log ""
    Write-Log "Applying VM-specific optimizations..."
    
    try {
        # Disable unnecessary services
        $servicesToDisable = @(
            'TabletInputService',  # Touch keyboard
            'WSearch',             # Windows Search (optional)
            'Superfetch',          # Superfetch/SysMain
            'Themes'               # Themes service
        )
        
        foreach ($service in $servicesToDisable) {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                try {
                    Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
                    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                    Write-Log "✓ Disabled service: $service"
                    $script:OptimizationsApplied++
                }
                catch {
                    Write-Log "Failed to disable $service : $($_.Exception.Message)" -Level Warning
                }
            }
        }
        
    }
    catch {
        Write-Log "Service optimization failed: $($_.Exception.Message)" -Level Warning
        $script:OptimizationsFailed++
    }
    
    # Memory and processor optimizations
    Write-Log ""
    Write-Log "Applying memory and processor optimizations..."
    
    try {
        $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        
        # Disable paging executive
        Set-ItemProperty -Path $mmPath -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
        Write-Log "✓ Disabled paging executive"
        $script:OptimizationsApplied++
        
        # Clear page file at shutdown (optional - slower shutdown)
        # Set-ItemProperty -Path $mmPath -Name 'ClearPageFileAtShutdown' -Value 1 -Type DWord -Force
        
        # Multimedia system responsiveness
        $multiPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Set-ItemProperty -Path $multiPath -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $multiPath -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -Force
        Write-Log "✓ Optimized system responsiveness"
        $script:OptimizationsApplied++
        
    }
    catch {
        Write-Log "Memory/processor optimization failed: $($_.Exception.Message)" -Level Warning
        $script:OptimizationsFailed++
    }
    
    # Visual effects optimization
    Write-Log ""
    Write-Log "Optimizing visual effects..."
    
    try {
        $visualPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (-not (Test-Path $visualPath)) {
            New-Item -Path $visualPath -Force | Out-Null
        }
        Set-ItemProperty -Path $visualPath -Name 'VisualFXSetting' -Value 2 -Type DWord -Force
        Write-Log "✓ Set visual effects to performance mode"
        $script:OptimizationsApplied++
        
    }
    catch {
        Write-Log "Visual effects optimization failed: $($_.Exception.Message)" -Level Warning
        $script:OptimizationsFailed++
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "XenServer Performance Optimization Summary"
    Write-Log "========================================================="
    Write-Log "XenServer detected: $isXenServer"
    Write-Log "Optimizations applied: $script:OptimizationsApplied"
    Write-Log "Optimizations failed: $script:OptimizationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    Write-Log "Optimization completed successfully!"
    Write-Log ""
    Write-Log "Note: A system restart is recommended for all changes to take effect."
    
} catch {
    Write-Log "Optimization failed: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
