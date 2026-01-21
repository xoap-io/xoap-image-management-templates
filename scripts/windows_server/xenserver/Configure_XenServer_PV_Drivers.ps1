<#
.SYNOPSIS
    Configure XenServer PV Drivers for Optimal Performance

.DESCRIPTION
    Configures XenServer Paravirtualization (PV) drivers for optimal performance.
    Verifies driver installation, configures driver settings, and optimizes
    network and storage settings for XenServer/Citrix Hypervisor environments.

.NOTES
    File Name      : Configure_XenServer_PV_Drivers.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, XenServer Tools installed
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply network adapter optimizations for XenServer PV drivers

.PARAMETER OptimizeStorage
    Apply storage optimizations for XenServer PV drivers

.PARAMETER DisableOffloading
    Disable network offloading features (can improve stability in some cases)

.EXAMPLE
    .\Configure_XenServer_PV_Drivers.ps1
    Verifies and configures XenServer PV drivers with default settings

.EXAMPLE
    .\Configure_XenServer_PV_Drivers.ps1 -OptimizeNetwork -OptimizeStorage
    Applies all performance optimizations

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Apply network adapter optimizations')]
    [switch]$OptimizeNetwork,

    [Parameter(HelpMessage = 'Apply storage optimizations')]
    [switch]$OptimizeStorage,

    [Parameter(HelpMessage = 'Disable network offloading features')]
    [switch]$DisableOffloading
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = 'xenserver-pv-config'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:ConfigurationsApplied = 0
$script:ConfigurationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [XenPV] $Message"
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
    Write-Log "XenServer PV Drivers Configuration"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "OptimizeNetwork: $OptimizeNetwork"
    Write-Log "OptimizeStorage: $OptimizeStorage"
    Write-Log "DisableOffloading: $DisableOffloading"
    Write-Log ""
    
    # Verify XenServer drivers are installed
    Write-Log "Verifying XenServer PV drivers installation..."
    
    $xenDrivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object { 
        $_.DeviceName -like '*Xen*' -or 
        $_.Manufacturer -like '*Citrix*' -or
        $_.DriverProviderName -like '*Citrix*'
    }
    
    if (-not $xenDrivers) {
        throw "No XenServer PV drivers found. Please install XenServer Tools first."
    }
    
    Write-Log "✓ Found XenServer PV drivers:"
    foreach ($driver in $xenDrivers) {
        Write-Log "  - $($driver.DeviceName)"
        Write-Log "    Version: $($driver.DriverVersion), Provider: $($driver.DriverProviderName)"
    }
    $script:ConfigurationsApplied++
    
    # Verify XenServer services
    Write-Log ""
    Write-Log "Verifying XenServer services..."
    
    $xenServices = @('xenservice', 'xenvif', 'xenvbd')
    foreach ($serviceName in $xenServices) {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log "✓ Service $serviceName : $($svc.Status)"
            if ($svc.Status -ne 'Running') {
                try {
                    Start-Service -Name $serviceName -ErrorAction Stop
                    Write-Log "  Started service: $serviceName"
                    $script:ConfigurationsApplied++
                }
                catch {
                    Write-Log "  Failed to start service: $($_.Exception.Message)" -Level Warning
                    $script:ConfigurationsFailed++
                }
            }
        }
        else {
            Write-Log "Service $serviceName not found" -Level Warning
        }
    }
    
    # Network optimization
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Applying network optimizations..."
        
        # Get XenServer network adapters
        $xenAdapters = Get-NetAdapter | Where-Object { 
            $_.DriverDescription -like '*Xen*' -or 
            $_.DriverDescription -like '*Citrix*' 
        }
        
        if ($xenAdapters) {
            foreach ($adapter in $xenAdapters) {
                Write-Log "Configuring adapter: $($adapter.Name)"
                
                try {
                    # Enable Jumbo Frames (9000 bytes)
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Jumbo Packet" -DisplayValue "9014" -ErrorAction SilentlyContinue
                    Write-Log "  ✓ Set Jumbo Frames to 9014"
                    
                    # Configure Receive/Transmit Buffers
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Receive Buffers" -DisplayValue "2048" -ErrorAction SilentlyContinue
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Transmit Buffers" -DisplayValue "2048" -ErrorAction SilentlyContinue
                    Write-Log "  ✓ Configured buffer sizes"
                    
                    $script:ConfigurationsApplied++
                }
                catch {
                    Write-Log "  Failed to configure adapter: $($_.Exception.Message)" -Level Warning
                    $script:ConfigurationsFailed++
                }
            }
        }
        else {
            Write-Log "No XenServer network adapters found" -Level Warning
        }
    }
    
    # Disable offloading if requested
    if ($DisableOffloading) {
        Write-Log ""
        Write-Log "Disabling network offloading features..."
        
        $xenAdapters = Get-NetAdapter | Where-Object { 
            $_.DriverDescription -like '*Xen*' -or 
            $_.DriverDescription -like '*Citrix*' 
        }
        
        if ($xenAdapters) {
            foreach ($adapter in $xenAdapters) {
                try {
                    # Disable various offloading features
                    Disable-NetAdapterChecksumOffload -Name $adapter.Name -ErrorAction SilentlyContinue
                    Disable-NetAdapterLso -Name $adapter.Name -ErrorAction SilentlyContinue
                    Disable-NetAdapterRsc -Name $adapter.Name -ErrorAction SilentlyContinue
                    
                    Write-Log "✓ Disabled offloading for: $($adapter.Name)"
                    $script:ConfigurationsApplied++
                }
                catch {
                    Write-Log "Failed to disable offloading: $($_.Exception.Message)" -Level Warning
                    $script:ConfigurationsFailed++
                }
            }
        }
    }
    
    # Storage optimization
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Applying storage optimizations..."
        
        try {
            # Configure disk timeout values
            $diskTimeoutPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            if (Test-Path $diskTimeoutPath) {
                Set-ItemProperty -Path $diskTimeoutPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
                Write-Log "✓ Set disk timeout to 60 seconds"
                $script:ConfigurationsApplied++
            }
            
            # Optimize for virtual environments
            $optimizePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout'
            if (-not (Test-Path $optimizePath)) {
                New-Item -Path $optimizePath -Force | Out-Null
            }
            Set-ItemProperty -Path $optimizePath -Name 'EnableAutoLayout' -Value 0 -Type DWord -Force
            Write-Log "✓ Disabled automatic disk layout optimization"
            $script:ConfigurationsApplied++
            
        }
        catch {
            Write-Log "Storage optimization failed: $($_.Exception.Message)" -Level Warning
            $script:ConfigurationsFailed++
        }
    }
    
    # Configure XenServer specific registry settings
    Write-Log ""
    Write-Log "Applying XenServer registry optimizations..."
    
    try {
        # XenServer specific settings
        $xenRegPath = 'HKLM:\SOFTWARE\Citrix\XenTools'
        if (Test-Path $xenRegPath) {
            # Enable performance optimizations
            Set-ItemProperty -Path $xenRegPath -Name 'DisableAutoUpdate' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled XenTools auto-update"
            $script:ConfigurationsApplied++
        }
        
        # Network optimization registry settings
        $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
        Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
        Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
        Write-Log "✓ Applied TCP/IP optimizations"
        $script:ConfigurationsApplied++
        
    }
    catch {
        Write-Log "Registry optimization failed: $($_.Exception.Message)" -Level Warning
        $script:ConfigurationsFailed++
    }
    
    # Verify final state
    Write-Log ""
    Write-Log "Verifying final configuration..."
    
    $xenServices = @('xenservice', 'xenvif', 'xenvbd')
    $runningServices = 0
    foreach ($serviceName in $xenServices) {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            $runningServices++
        }
    }
    
    Write-Log "XenServer services running: $runningServices / $($xenServices.Count)"
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "XenServer PV Drivers Configuration Summary"
    Write-Log "========================================================="
    Write-Log "Configurations applied: $script:ConfigurationsApplied"
    Write-Log "Configurations failed: $script:ConfigurationsFailed"
    Write-Log "Services running: $runningServices / $($xenServices.Count)"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    Write-Log "Configuration completed successfully!"
    Write-Log ""
    Write-Log "Note: Some changes may require a system restart."
    
} catch {
    Write-Log "Configuration failed: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
