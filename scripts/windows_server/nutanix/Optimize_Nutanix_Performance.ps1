<#
.SYNOPSIS
    Optimize Windows for Nutanix AHV Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on Nutanix AHV.
    Includes registry tweaks, service optimizations, and performance tuning specific
    to Nutanix virtualization platform.

.NOTES
    File Name      : Optimize_Nutanix_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply network adapter optimizations

.PARAMETER OptimizeStorage
    Apply storage performance optimization

.EXAMPLE
    .\Optimize_Nutanix_Performance.ps1
    Applies all Nutanix optimizations

.EXAMPLE
    .\Optimize_Nutanix_Performance.ps1 -OptimizeNetwork -OptimizeStorage
    Applies network and storage optimizations

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
$scriptName = 'nutanix-optimize'
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
    $logMessage = "[$timestamp] [$prefix] [NutanixOpt] $Message"
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
    Write-Log "Nutanix AHV Performance Optimization"
    Write-Log "========================================================="
    
    # Verify Nutanix Guest Agent
    $ngtService = Get-Service -Name 'NutanixGuestAgent' -ErrorAction SilentlyContinue
    if ($ngtService) {
        Write-Log "✓ Nutanix Guest Agent: $($ngtService.Status)"
        if ($ngtService.Status -ne 'Running') {
            Start-Service -Name 'NutanixGuestAgent'
            Write-Log "✓ Started Nutanix Guest Agent"
        }
        $script:OptimizationsApplied++
    }
    
    # Network optimization
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Optimizing network adapters..."
        
        $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
        Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
        Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
        Write-Log "✓ Applied TCP/IP optimizations"
        $script:OptimizationsApplied++
    }
    
    # Storage optimization  
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Applying storage optimizations..."
        
        try {
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled defragmentation"
            
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
    
    # Power settings
    Write-Log ""
    Write-Log "Optimizing power settings..."
    $highPerf = powercfg /list | Select-String "High performance" | ForEach-Object { 
        if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } 
    }
    if ($highPerf) {
        powercfg /setactive $highPerf
        Write-Log "✓ Set High Performance power plan"
        $script:OptimizationsApplied++
    }
    
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
