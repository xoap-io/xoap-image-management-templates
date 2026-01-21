<#
.SYNOPSIS
    Optimize Windows for Azure VM Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on Azure VMs.
    Includes Accelerated Networking configuration, Azure storage optimization,
    and Azure-specific tuning for optimal cloud performance.

.NOTES
    File Name      : Optimize_Azure_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply Accelerated Networking optimizations

.PARAMETER OptimizeStorage
    Apply Azure Disk storage optimizations

.EXAMPLE
    .\Optimize_Azure_Performance.ps1
    Applies all Azure optimizations

.LINK
    https://github.com/xoap-io/xoap-packer-templates
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
$scriptName = 'azure-optimize'
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
    $logMessage = "[$timestamp] [$prefix] [AzureOpt] $Message"
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
    Write-Log "Azure VM Performance Optimization"
    Write-Log "========================================================="
    
    if (-not ($OptimizeNetwork -or $OptimizeStorage)) {
        $OptimizeNetwork = $true
        $OptimizeStorage = $true
    }
    
    # Detect Azure
    $isAzure = $false
    $vmSize = 'Unknown'
    try {
        $metadata = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
            -Headers @{Metadata='true'} -TimeoutSec 2
        $vmSize = $metadata.compute.vmSize
        Write-Log "✓ Azure VM detected: $vmSize"
        $isAzure = $true
    }
    catch {
        Write-Log "Warning: Not on Azure VM" -Level Warning
    }
    
    # Network optimization
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Optimizing network for Azure..."
        
        try {
            # Check for Mellanox/Azure Accelerated Networking
            $mlxAdapter = Get-NetAdapter | Where-Object { 
                $_.InterfaceDescription -like '*Mellanox*' -or
                $_.InterfaceDescription -like '*Azure Accelerated*'
            }
            
            if ($mlxAdapter) {
                Write-Log "✓ Accelerated Networking detected"
                Enable-NetAdapterRss -Name $mlxAdapter.Name -ErrorAction SilentlyContinue
                Enable-NetAdapterLso -Name $mlxAdapter.Name -ErrorAction SilentlyContinue
                Write-Log "✓ Optimized Accelerated Networking adapter"
                $script:OptimizationsApplied++
            }
            
            # TCP/IP optimizations
            $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
            Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
            Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
            Write-Log "✓ Applied TCP/IP optimizations"
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Network optimization failed" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Storage optimization
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Optimizing storage for Azure..."
        
        try {
            # Disable defragmentation
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled defragmentation"
            
            # Disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "✓ Set disk timeout"
            
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Storage optimization failed" -Level Warning
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
        Write-Log "✓ Set High Performance"
        $script:OptimizationsApplied++
    }
    
    powercfg /hibernate off
    Write-Log "✓ Disabled hibernation"
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Optimization Summary"
    Write-Log "========================================================="
    Write-Log "Azure VM: $isAzure ($vmSize)"
    Write-Log "Optimizations applied: $script:OptimizationsApplied"
    Write-Log "Optimizations failed: $script:OptimizationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
} catch {
    Write-Log "Optimization failed: $_" -Level Error
    exit 1
}
