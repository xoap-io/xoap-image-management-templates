<#
.SYNOPSIS
    Optimize Windows for VMware vSphere Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on VMware vSphere/ESXi.
    Includes VMware Tools configuration, PVSCSI optimization, and performance tuning
    specific to VMware virtualization platform.

.NOTES
    File Name      : Optimize_VMware_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, VMware Tools installed
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply VMware network adapter optimizations

.PARAMETER OptimizeStorage
    Apply PVSCSI and storage optimizations

.PARAMETER DisableTimeSync
    Disable VMware Tools time synchronization (use NTP instead)

.EXAMPLE
    .\Optimize_VMware_Performance.ps1
    Applies all VMware optimizations

.EXAMPLE
    .\Optimize_VMware_Performance.ps1 -OptimizeNetwork -OptimizeStorage
    Applies network and storage optimizations

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [switch]$OptimizeNetwork,
    [switch]$OptimizeStorage,
    [switch]$DisableTimeSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = 'vmware-optimize'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [VMOpt] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    Write-Log "========================================================="
    Write-Log "VMware vSphere Performance Optimization"
    Write-Log "========================================================="
    
    # Verify VMware Tools
    $vmTools = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue
    if ($vmTools) {
        Write-Log "✓ VMware Tools: $($vmTools.Status)"
        if ($vmTools.Status -ne 'Running') {
            Start-Service -Name 'VMTools'
            Write-Log "✓ Started VMware Tools"
        }
    }
    else {
        Write-Log "VMware Tools not found" -Level Warning
    }
    
    # Configure VMware Tools time synchronization
    if ($DisableTimeSync) {
        Write-Log ""
        Write-Log "Disabling VMware Tools time synchronization..."
        
        $vmtoolsdPath = "$env:ProgramFiles\VMware\VMware Tools\VMwareToolboxCmd.exe"
        if (Test-Path $vmtoolsdPath) {
            try {
                & $vmtoolsdPath timesync disable
                Write-Log "✓ Disabled VMware Tools time synchronization"
                $script:OptimizationsApplied++
            }
            catch {
                Write-Log "Failed to disable time sync" -Level Warning
                $script:OptimizationsFailed++
            }
        }
    }
    
    # Network optimization
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Optimizing VMware network adapters..."
        
        $vmwareAdapters = Get-NetAdapter | Where-Object { 
            $_.InterfaceDescription -like '*VMware*' -or 
            $_.InterfaceDescription -like '*vmxnet*'
        }
        
        foreach ($adapter in $vmwareAdapters) {
            try {
                # Enable RSS (Receive Side Scaling)
                Enable-NetAdapterRss -Name $adapter.Name -ErrorAction SilentlyContinue
                
                # Configure buffer sizes
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Receive Buffers" -DisplayValue "2048" -ErrorAction SilentlyContinue
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Transmit Buffers" -DisplayValue "2048" -ErrorAction SilentlyContinue
                
                # Enable Jumbo Frames
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Jumbo Packet" -DisplayValue "9014" -ErrorAction SilentlyContinue
                
                Write-Log "✓ Optimized: $($adapter.Name)"
                $script:OptimizationsApplied++
            }
            catch {
                Write-Log "Failed to optimize adapter" -Level Warning
                $script:OptimizationsFailed++
            }
        }
    }
    
    # Storage optimization
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Applying storage optimizations..."
        
        try {
            # Disable defragmentation
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled defragmentation"
            
            # Disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "✓ Set disk timeout to 60s"
            
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Storage optimization failed" -Level Warning
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
    Write-Log "✓ Applied TCP/IP optimizations"
    $script:OptimizationsApplied++
    
    # Power plan
    $highPerf = powercfg /list | Select-String "High performance" | ForEach-Object { 
        if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } 
    }
    if ($highPerf) {
        powercfg /setactive $highPerf
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        Write-Log "✓ Set High Performance power plan"
        $script:OptimizationsApplied++
    }
    
    # Disable hibernation
    powercfg /hibernate off
    Write-Log "✓ Disabled hibernation"
    $script:OptimizationsApplied++
    
    # Memory optimization
    $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-ItemProperty -Path $mmPath -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
    Write-Log "✓ Disabled paging executive"
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
    
} catch {
    Write-Log "Optimization failed: $_" -Level Error
    exit 1
}
