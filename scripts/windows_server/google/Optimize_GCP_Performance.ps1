<#
.SYNOPSIS
    Optimize Windows for Google Compute Engine Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on GCE.
    Includes VirtIO driver configuration, network optimization, and
    GCP-specific tuning for optimal cloud performance.

.NOTES
    File Name      : Optimize_GCP_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply network adapter optimizations

.PARAMETER OptimizeStorage
    Apply persistent disk optimizations

.EXAMPLE
    .\Optimize_GCP_Performance.ps1
    Applies all GCP optimizations

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
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [GCPOpt] Transcript unavailable: $($_.Exception.Message)" }

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
    $logMessage = "[$timestamp] [$Level] [GCPOpt] $Message"
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
    Write-Log "===== Optimize_GCP_Performance starting ====="
    
    Write-Log "========================================================="
    Write-Log "Google Compute Engine Performance Optimization"
    Write-Log "========================================================="
    
    if (-not ($OptimizeNetwork -or $OptimizeStorage)) {
        $OptimizeNetwork = $true
        $OptimizeStorage = $true
    }
    
    # Detect GCE
    $isGCE = $false
    $machineType = 'Unknown'
    try {
        $metadata = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/instance/machine-type' `
            -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 2
        $machineType = $metadata.Split('/')[-1]
        Write-Log "[OK] GCE instance detected: $machineType"
        $isGCE = $true
    }
    catch {
        Write-Log "Warning: Not on GCE instance" -Level WARN
    }
    
    # Network optimization
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Optimizing network for GCP..."
        
        try {
            # Check for Google VirtIO network adapters
            $virtioAdapter = Get-NetAdapter | Where-Object { 
                $_.InterfaceDescription -like '*VirtIO*' -or
                $_.InterfaceDescription -like '*Google*'
            }
            
            if ($virtioAdapter) {
                Write-Log "[OK] VirtIO network adapter detected"
                Enable-NetAdapterRss -Name $virtioAdapter.Name -ErrorAction SilentlyContinue
                Write-Log "[OK] Enabled RSS"
                $script:OptimizationsApplied++
            }
            
            # TCP/IP optimizations
            $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
            Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
            Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
            Write-Log "[OK] Applied TCP/IP optimizations"
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Network optimization failed" -Level WARN
            $script:OptimizationsFailed++
        }
    }
    
    # Storage optimization
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Optimizing storage for GCP..."
        
        try {
            # Disable defragmentation (Persistent Disks are SSD-backed)
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "[OK] Disabled defragmentation"
            
            # Disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "[OK] Set disk timeout"
            
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Storage optimization failed" -Level WARN
            $script:OptimizationsFailed++
        }
    }
    
    # Power settings
    Write-Log ""
    Write-Log "Optimizing power settings..."
    $highPerf = powercfg /list | Select-String "High performance" | ForEach-Object { 
        if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } 
    }
    if ($highPerf) {
        powercfg /setactive $highPerf
        Write-Log "[OK] Set High Performance"
        $script:OptimizationsApplied++
    }
    
    powercfg /hibernate off
    Write-Log "[OK] Disabled hibernation"
    
    # Memory optimization
    $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-ItemProperty -Path $mmPath -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
    Write-Log "[OK] Disabled paging executive"
    $script:OptimizationsApplied++
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Optimization Summary"
    Write-Log "========================================================="
    Write-Log "GCE Instance: $isGCE ($machineType)"
    Write-Log "Optimizations applied: $script:OptimizationsApplied"
    Write-Log "Optimizations failed: $script:OptimizationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    Write-Log "===== Optimize_GCP_Performance complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Optimization failed: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
