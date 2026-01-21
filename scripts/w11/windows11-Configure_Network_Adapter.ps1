<#
.SYNOPSIS
    Configure Network Adapter Settings for Windows 10/11

.DESCRIPTION
    Configures network adapter properties including TCP/IP offloading, power management,
    and performance tuning. Optimized for Windows 10/11 and Packer image preparation workflows.

.NOTES
    File Name      : windows11-Configure_Network_Adapter.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Configure_Network_Adapter.ps1
    Optimizes all network adapters with default settings
    
.EXAMPLE
    .\windows11-Configure_Network_Adapter.ps1 -DisableIPv6 -DisablePowerSaving
    Configures adapters, disables IPv6 and power management
    
.PARAMETER DisableIPv6
    Disable IPv6 on network adapters
    
.PARAMETER DisablePowerSaving
    Disable power management features
    
.PARAMETER DisableNetBIOS
    Disable NetBIOS over TCP/IP
#>

[CmdletBinding()]
param(
    [switch]$DisableIPv6,
    [switch]$DisablePowerSaving,
    [switch]$DisableNetBIOS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

try {
    Write-LogMessage "=============================================="
    Write-LogMessage "Network Adapter Configuration Script"
    Write-LogMessage "=============================================="
    Write-LogMessage "Disable IPv6: $DisableIPv6"
    Write-LogMessage "Disable Power Saving: $DisablePowerSaving"
    Write-LogMessage "Disable NetBIOS: $DisableNetBIOS"
    Write-LogMessage ""
    
    # Get all physical network adapters
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    Write-LogMessage "Found $($adapters.Count) active physical network adapter(s)"
    
    foreach ($adapter in $adapters) {
        Write-LogMessage "Configuring adapter: $($adapter.Name)"
        
        # Disable IPv6 if requested
        if ($DisableIPv6) {
            try {
                Write-LogMessage "  Disabling IPv6..."
                Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
                $script:OptimizationsApplied++
                Write-LogMessage "  ✓ IPv6 disabled" -Level Success
            } catch {
                $script:OptimizationsFailed++
                Write-LogMessage "  ✗ Failed to disable IPv6: $($_.Exception.Message)" -Level Warning
            }
        }
        
        # Disable power management if requested
        if ($DisablePowerSaving) {
            try {
                Write-LogMessage "  Disabling power management..."
                $powerMgmt = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi | 
                    Where-Object { $_.InstanceName -like "*$($adapter.DeviceID)*" }
                
                if ($powerMgmt) {
                    $powerMgmt | Set-CimInstance -Property @{Enable = $false}
                }
                
                # Also disable via registry
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
                $adapterGuid = (Get-NetAdapter -Name $adapter.Name).InterfaceGuid
                
                Get-ChildItem $regPath | ForEach-Object {
                    $props = Get-ItemProperty -Path $_.PSPath
                    if ($props.NetCfgInstanceId -eq $adapterGuid) {
                        Set-ItemProperty -Path $_.PSPath -Name "PnPCapabilities" -Value 24 -ErrorAction SilentlyContinue
                    }
                }
                
                $script:OptimizationsApplied++
                Write-LogMessage "  ✓ Power management disabled" -Level Success
            } catch {
                $script:OptimizationsFailed++
                Write-LogMessage "  ✗ Failed to disable power management: $($_.Exception.Message)" -Level Warning
            }
        }
        
        # Disable NetBIOS if requested
        if ($DisableNetBIOS) {
            try {
                Write-LogMessage "  Disabling NetBIOS over TCP/IP..."
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
                $adapterGuid = (Get-NetAdapter -Name $adapter.Name).InterfaceGuid
                $netbtPath = Join-Path $regPath "Tcpip_$adapterGuid"
                
                if (Test-Path $netbtPath) {
                    Set-ItemProperty -Path $netbtPath -Name "NetbiosOptions" -Value 2 -Type DWord
                    $script:OptimizationsApplied++
                    Write-LogMessage "  ✓ NetBIOS disabled" -Level Success
                } else {
                    Write-LogMessage "  ⊗ NetBIOS registry path not found" -Level Warning
                }
            } catch {
                $script:OptimizationsFailed++
                Write-LogMessage "  ✗ Failed to disable NetBIOS: $($_.Exception.Message)" -Level Warning
            }
        }
    }
    
    Write-LogMessage ""
    Write-LogMessage "=============================================="
    Write-LogMessage "Configuration Summary"
    Write-LogMessage "=============================================="
    Write-LogMessage "Optimizations Applied: $script:OptimizationsApplied"
    Write-LogMessage "Optimizations Failed: $script:OptimizationsFailed"
    Write-LogMessage "Network adapter configuration completed successfully" -Level Success
    
} catch {
    Write-LogMessage "Critical error during network adapter configuration: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
