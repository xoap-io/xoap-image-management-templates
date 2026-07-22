<#
.SYNOPSIS
    Optimize Windows for Proxmox VE Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on Proxmox VE.
    Includes VirtIO driver configuration, QEMU guest agent optimization, and
    performance tuning specific to KVM/QEMU virtualization.

.NOTES
    File Name      : Optimize_Proxmox_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply VirtIO network adapter optimizations

.PARAMETER OptimizeStorage
    Apply VirtIO storage optimizations

.EXAMPLE
    .\Optimize_Proxmox_Performance.ps1
    Applies all Proxmox optimizations

.EXAMPLE
    .\Optimize_Proxmox_Performance.ps1 -OptimizeNetwork -OptimizeStorage
    Applies network and storage optimizations

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param (
    [switch]$OptimizeNetwork,
    [switch]$OptimizeStorage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [ProxmoxOpt] Transcript unavailable: $($_.Exception.Message)" }

$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [ProxmoxOpt] $Message"
    Write-Host $logMessage
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    Write-Log "===== Optimize_Proxmox_Performance starting ====="
    
    Write-Log "========================================================="
    Write-Log "Proxmox VE Performance Optimization"
    Write-Log "========================================================="
    
    # Verify QEMU Guest Agent
    $agentService = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
    if ($agentService) {
        Write-Log "[OK] QEMU Guest Agent: $($agentService.Status)"
        if ($agentService.Status -ne 'Running') {
            Start-Service -Name 'QEMU-GA'
            Write-Log "[OK] Started QEMU Guest Agent"
        }
        $script:OptimizationsApplied++
    }
    
    # Network optimization
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Optimizing VirtIO network adapters..."
        
        $virtioAdapters = Get-NetAdapter | Where-Object { 
            $_.InterfaceDescription -like '*VirtIO*' -or 
            $_.InterfaceDescription -like '*Red Hat*'
        }
        
        foreach ($adapter in $virtioAdapters) {
            try {
                # Disable power management
                $powerMgmt = Get-WmiObject MSPower_DeviceEnable -Namespace root\wmi | 
                    Where-Object { $_.InstanceName -like "*$($adapter.DeviceID)*" }
                
                if ($powerMgmt) {
                    $powerMgmt.Enable = $false
                    $powerMgmt.Put() | Out-Null
                    Write-Log "[OK] Disabled power management: $($adapter.Name)"
                }
                
                # Configure buffer sizes
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Receive Buffers" -DisplayValue "2048" -ErrorAction SilentlyContinue
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Transmit Buffers" -DisplayValue "2048" -ErrorAction SilentlyContinue
                Write-Log "[OK] Configured buffers: $($adapter.Name)"
                
                $script:OptimizationsApplied++
            }
            catch {
                Write-Log "Failed to optimize adapter: $($_.Exception.Message)" -Level WARN
                $script:OptimizationsFailed++
            }
        }
    }
    
    # Storage optimization
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Optimizing storage settings..."
        
        try {
            # Disable defragmentation
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "[OK] Disabled defragmentation"
            
            # Disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "[OK] Set disk timeout to 60s"
            
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Storage optimization failed" -Level WARN
            $script:OptimizationsFailed++
        }
    }
    
    # General VM optimizations
    Write-Log ""
    Write-Log "Applying general VM optimizations..."
    
    # TCP/IP settings
    $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
    Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
    Write-Log "[OK] Applied TCP/IP optimizations"
    $script:OptimizationsApplied++
    
    # Power plan
    $highPerf = powercfg /list | Select-String "High performance" | ForEach-Object { 
        if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } 
    }
    if ($highPerf) {
        powercfg /setactive $highPerf
        Write-Log "[OK] Set High Performance power plan"
        $script:OptimizationsApplied++
    }
    
    # Disable hibernation
    powercfg /hibernate off
    Write-Log "[OK] Disabled hibernation"
    $script:OptimizationsApplied++
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Optimization Summary"
    Write-Log "========================================================="
    Write-Log "Optimizations applied: $script:OptimizationsApplied"
    Write-Log "Optimizations failed: $script:OptimizationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    Write-Log "===== Optimize_Proxmox_Performance complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Optimization failed: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
