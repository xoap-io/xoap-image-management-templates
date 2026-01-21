<#
.SYNOPSIS
    Optimize Windows for Hyper-V Virtual Machine Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on Hyper-V.
    Includes registry tweaks, service optimizations, and performance tuning specific
    to Microsoft Hyper-V virtualization platform.

.NOTES
    File Name      : Optimize_HyperV_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER DisableDynamicMemory
    Optimize settings for Dynamic Memory disabled configurations

.PARAMETER EnableEnhancedSession
    Enable Enhanced Session Mode support

.EXAMPLE
    .\Optimize_HyperV_Performance.ps1
    Applies all Hyper-V optimizations

.EXAMPLE
    .\Optimize_HyperV_Performance.ps1 -EnableEnhancedSession
    Applies optimizations with Enhanced Session Mode enabled

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [switch]$DisableDynamicMemory,
    [switch]$EnableEnhancedSession
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = 'hyperv-optimize'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

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
    $logMessage = "[$timestamp] [$prefix] [HyperV-Opt] $Message"
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
    Write-Log "Hyper-V Performance Optimization"
    Write-Log "========================================================="
    
    # Disable unnecessary services
    $servicesToDisable = @('TabletInputService', 'WSearch', 'Superfetch')
    foreach ($svc in $servicesToDisable) {
        try {
            if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
                Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Write-Log "✓ Disabled: $svc"
                $script:OptimizationsApplied++
            }
        }
        catch {
            Write-Log "Failed to disable $svc" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Registry optimizations
    Write-Log "Applying registry optimizations..."
    
    # Network optimization
    $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
    Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
    Write-Log "✓ Applied TCP/IP optimizations"
    $script:OptimizationsApplied++
    
    # Memory optimization
    if ($DisableDynamicMemory) {
        $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        Set-ItemProperty -Path $mmPath -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
        Write-Log "✓ Disabled paging executive"
        $script:OptimizationsApplied++
    }
    
    # Enhanced Session Mode
    if ($EnableEnhancedSession) {
        Write-Log "Configuring Enhanced Session Mode..."
        try {
            Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
            Write-Log "✓ Enabled Enhanced Session Mode support"
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Failed to enable Enhanced Session Mode" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Power settings
    $highPerf = powercfg /list | Select-String "High performance" | ForEach-Object { 
        if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } 
    }
    if ($highPerf) {
        powercfg /setactive $highPerf
        Write-Log "✓ Set High Performance power plan"
        $script:OptimizationsApplied++
    }
    
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
