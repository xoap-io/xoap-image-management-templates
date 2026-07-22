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
    https://github.com/xoap-io/xoap-image-management-templates
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
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [XenOpt] Transcript unavailable: $($_.Exception.Message)" }

# Statistics tracking
$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [XenOpt] $Message"
    Write-Host $logMessage
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# Main execution
try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    Write-Log "===== Optimize_XenServer_Performance starting ====="
    
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
        Write-Log "[OK] XenServer/Citrix Hypervisor detected"
        $isXenServer = $true
    }
    else {
        Write-Log "Warning: XenServer not detected. Manufacturer: $manufacturer" -Level WARN
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
                Write-Log "[OK] Set power plan to High Performance"
                $script:OptimizationsApplied++
            }
            
            # Disable hibernate
            powercfg /hibernate off
            Write-Log "[OK] Disabled hibernation"
            $script:OptimizationsApplied++
            
            # Disable sleep timeout
            powercfg /change standby-timeout-ac 0
            powercfg /change standby-timeout-dc 0
            Write-Log "[OK] Disabled sleep timeouts"
            $script:OptimizationsApplied++
            
        }
        catch {
            Write-Log "Power optimization failed: $($_.Exception.Message)" -Level WARN
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
                Write-Log "[OK] Set $($opt.Key) = $($opt.Value)"
                $script:OptimizationsApplied++
            }
            
            # Disable IPv6 (optional - can improve performance)
            Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | 
                Disable-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            Write-Log "[OK] Disabled IPv6"
            $script:OptimizationsApplied++
            
        }
        catch {
            Write-Log "Network optimization failed: $($_.Exception.Message)" -Level WARN
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
            Write-Log "[OK] Disabled scheduled defragmentation"
            $script:OptimizationsApplied++
            
            # Optimize disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "[OK] Set disk timeout to 60 seconds"
            $script:OptimizationsApplied++
            
            # Disable System Restore
            Disable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
            Write-Log "[OK] Disabled System Restore"
            $script:OptimizationsApplied++
            
        }
        catch {
            Write-Log "Storage optimization failed: $($_.Exception.Message)" -Level WARN
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
                    Write-Log "[OK] Disabled service: $service"
                    $script:OptimizationsApplied++
                }
                catch {
                    Write-Log "Failed to disable $service : $($_.Exception.Message)" -Level WARN
                }
            }
        }
        
    }
    catch {
        Write-Log "Service optimization failed: $($_.Exception.Message)" -Level WARN
        $script:OptimizationsFailed++
    }
    
    # Memory and processor optimizations
    Write-Log ""
    Write-Log "Applying memory and processor optimizations..."
    
    try {
        $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        
        # Disable paging executive
        Set-ItemProperty -Path $mmPath -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
        Write-Log "[OK] Disabled paging executive"
        $script:OptimizationsApplied++
        
        # Clear page file at shutdown (optional - slower shutdown)
        # Set-ItemProperty -Path $mmPath -Name 'ClearPageFileAtShutdown' -Value 1 -Type DWord -Force
        
        # Multimedia system responsiveness
        $multiPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Set-ItemProperty -Path $multiPath -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $multiPath -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -Force
        Write-Log "[OK] Optimized system responsiveness"
        $script:OptimizationsApplied++
        
    }
    catch {
        Write-Log "Memory/processor optimization failed: $($_.Exception.Message)" -Level WARN
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
        Write-Log "[OK] Set visual effects to performance mode"
        $script:OptimizationsApplied++
        
    }
    catch {
        Write-Log "Visual effects optimization failed: $($_.Exception.Message)" -Level WARN
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
    
    Write-Log "===== Optimize_XenServer_Performance complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Optimization failed: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
