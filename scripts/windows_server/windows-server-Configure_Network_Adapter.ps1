<#
.SYNOPSIS
    Configure Network Adapter Settings for Windows Server

.DESCRIPTION
    Configures network adapter properties including TCP/IP offloading, RSS, VMQ,
    power management, and performance tuning. Optimized for Windows Server 2025
    and Packer image preparation workflows.

.NOTES
    File Name      : windows-server-Configure_Network_Adapter.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Network_Adapter.ps1
    Optimizes all network adapters with default settings
    
.EXAMPLE
    .\windows-server-Configure_Network_Adapter.ps1 -AdapterName "Ethernet" -DisableIPv6 -OptimizeForVirtualization
    Configures specific adapter, disables IPv6, optimizes for VM
    
.PARAMETER AdapterName
    Name of the network adapter to configure (default: all adapters)
    
.PARAMETER DisableIPv6
    Disable IPv6 on network adapters
    
.PARAMETER OptimizeForVirtualization
    Apply VM-specific optimizations (disable VMQ, adjust RSS)
    
.PARAMETER EnableJumboFrames
    Enable Jumbo Frames (MTU 9000)
    
.PARAMETER DisablePowerSaving
    Disable power management features
    
.PARAMETER ConfigureOffloading
    Configure TCP/IP offloading features
    
.PARAMETER DisableNetBIOS
    Disable NetBIOS over TCP/IP
#>

[CmdletBinding()]
param(
    [string]$AdapterName = "*",
    [switch]$DisableIPv6,
    [switch]$OptimizeForVirtualization,
    [switch]$EnableJumboFrames,
    [switch]$DisablePowerSaving,
    [switch]$ConfigureOffloading = $true,
    [switch]$DisableNetBIOS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

#region Helper Functions

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

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-NetworkAdapterProperty {
    param(
        [Parameter(Mandatory)]
        [string]$AdapterName,
        
        [Parameter(Mandatory)]
        [string]$PropertyName,
        
        [Parameter(Mandatory)]
        $PropertyValue,
        
        [string]$Description
    )
    
    try {
        $adapter = Get-NetAdapter -Name $AdapterName
        
        # Check if property exists
        $property = Get-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $PropertyName -ErrorAction SilentlyContinue
        
        if (-not $property) {
            # Try by RegistryKeyword
            $property = Get-NetAdapterAdvancedProperty -Name $AdapterName | Where-Object { $_.RegistryKeyword -eq $PropertyName }
        }
        
        if ($property) {
            Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $PropertyName -DisplayValue $PropertyValue -ErrorAction Stop
            Write-LogMessage "  ✓ $Description" -Level Success
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-LogMessage "  ⚠ Property '$PropertyName' not found on adapter '$AdapterName'" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Failed to set $Description : $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Network Adapter Discovery

function Get-ConfigurableAdapters {
    Write-LogMessage "Discovering network adapters..." -Level Info
    
    try {
        $adapters = Get-NetAdapter -Name $AdapterName | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected' }
        
        if (-not $adapters) {
            Write-LogMessage "No network adapters found matching '$AdapterName'" -Level Warning
            return $null
        }
        
        Write-LogMessage "Found $($adapters.Count) network adapter(s):" -Level Info
        
        foreach ($adapter in $adapters) {
            $speed = if ($adapter.LinkSpeed) { $adapter.LinkSpeed } else { "Unknown" }
            Write-LogMessage "  - $($adapter.Name) ($($adapter.InterfaceDescription)) - $speed - Status: $($adapter.Status)" -Level Info
        }
        
        return $adapters
    }
    catch {
        Write-LogMessage "Error discovering adapters: $($_.Exception.Message)" -Level Error
        return $null
    }
}

#endregion

#region IPv6 Configuration

function Disable-IPv6OnAdapter {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Disabling IPv6 on adapter: $($Adapter.Name)" -Level Info
    
    try {
        # Disable IPv6 binding
        Disable-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop
        
        Write-LogMessage "  ✓ IPv6 disabled" -Level Success
        $script:OptimizationsApplied++
        
        # Also set registry key to disable IPv6 globally
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name 'DisabledComponents' -Value 0xFF -Type DWord
        Write-LogMessage "  ✓ IPv6 disabled globally via registry" -Level Success
        
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error disabling IPv6: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region TCP/IP Offloading

function Configure-TCPOffloading {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Configuring TCP/IP offloading on adapter: $($Adapter.Name)" -Level Info
    
    $offloadSettings = @{
        '*IPChecksumOffloadIPv4' = 'Enabled'
        '*TCPChecksumOffloadIPv4' = 'Enabled'
        '*UDPChecksumOffloadIPv4' = 'Enabled'
        '*LsoV2IPv4' = 'Enabled'
        '*LsoV2IPv6' = 'Enabled'
        '*TCPChecksumOffloadIPv6' = 'Enabled'
        '*UDPChecksumOffloadIPv6' = 'Enabled'
    }
    
    foreach ($setting in $offloadSettings.GetEnumerator()) {
        $property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | Where-Object { $_.RegistryKeyword -eq $setting.Key }
        
        if ($property) {
            try {
                Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $setting.Key -RegistryValue 3 -ErrorAction Stop
                Write-LogMessage "  ✓ $($property.DisplayName): $($setting.Value)" -Level Success
                $script:OptimizationsApplied++
            }
            catch {
                Write-LogMessage "  ⚠ Could not set $($property.DisplayName): $($_.Exception.Message)" -Level Warning
            }
        }
    }
}

#endregion

#region RSS Configuration

function Configure-RSS {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Configuring RSS (Receive Side Scaling) on adapter: $($Adapter.Name)" -Level Info
    
    try {
        # Enable RSS
        $rss = Get-NetAdapterRss -Name $Adapter.Name -ErrorAction SilentlyContinue
        
        if ($rss) {
            if ($OptimizeForVirtualization) {
                # For VMs, use fewer RSS queues
                Set-NetAdapterRss -Name $Adapter.Name -Enabled $true -NumberOfReceiveQueues 2 -ErrorAction Stop
                Write-LogMessage "  ✓ RSS enabled with 2 queues (VM optimized)" -Level Success
            }
            else {
                # For physical, use more queues
                Set-NetAdapterRss -Name $Adapter.Name -Enabled $true -ErrorAction Stop
                Write-LogMessage "  ✓ RSS enabled" -Level Success
            }
            
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-LogMessage "  ⚠ RSS not supported on this adapter" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error configuring RSS: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region VMQ Configuration

function Configure-VMQ {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Configuring VMQ (Virtual Machine Queue) on adapter: $($Adapter.Name)" -Level Info
    
    try {
        $vmq = Get-NetAdapterVmq -Name $Adapter.Name -ErrorAction SilentlyContinue
        
        if ($vmq) {
            if ($OptimizeForVirtualization) {
                # Disable VMQ for VMs (not needed, can cause issues)
                Set-NetAdapterVmq -Name $Adapter.Name -Enabled $false -ErrorAction Stop
                Write-LogMessage "  ✓ VMQ disabled (VM optimization)" -Level Success
            }
            else {
                # Enable VMQ for Hyper-V hosts
                Set-NetAdapterVmq -Name $Adapter.Name -Enabled $true -ErrorAction Stop
                Write-LogMessage "  ✓ VMQ enabled" -Level Success
            }
            
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-LogMessage "  ⚠ VMQ not supported on this adapter" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error configuring VMQ: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Power Management

function Disable-AdapterPowerSaving {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Disabling power management on adapter: $($Adapter.Name)" -Level Info
    
    try {
        $powerSettings = Get-NetAdapterPowerManagement -Name $Adapter.Name -ErrorAction Stop
        
        # Disable all power saving features
        Set-NetAdapterPowerManagement -Name $Adapter.Name `
            -AllowComputerToTurnOffDevice Disabled `
            -DeviceSleepOnDisconnect Disabled `
            -ErrorAction Stop
        
        Write-LogMessage "  ✓ Power management disabled" -Level Success
        $script:OptimizationsApplied++
        
        # Also disable wake-on-LAN if not needed
        $wol = Get-NetAdapterPowerManagement -Name $Adapter.Name
        if ($wol.WakeOnMagicPacket -ne 'Disabled') {
            Set-NetAdapterPowerManagement -Name $Adapter.Name -WakeOnMagicPacket Disabled -ErrorAction SilentlyContinue
            Write-LogMessage "  ✓ Wake-on-LAN disabled" -Level Success
        }
        
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error disabling power management: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Jumbo Frames

function Enable-JumboFrames {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Enabling Jumbo Frames on adapter: $($Adapter.Name)" -Level Info
    
    try {
        # Check if adapter supports jumbo frames
        $property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | 
            Where-Object { $_.RegistryKeyword -like '*JumboPacket*' -or $_.DisplayName -like '*Jumbo*' }
        
        if ($property) {
            # Set to 9000 (9014 bytes including header)
            Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $property.RegistryKeyword -RegistryValue 9014 -ErrorAction Stop
            Write-LogMessage "  ✓ Jumbo Frames enabled (MTU 9000)" -Level Success
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-LogMessage "  ⚠ Jumbo Frames not supported on this adapter" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error enabling Jumbo Frames: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region NetBIOS Configuration

function Disable-NetBIOSOverTCPIP {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Disabling NetBIOS over TCP/IP on adapter: $($Adapter.Name)" -Level Info
    
    try {
        $adapterConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | 
            Where-Object { $_.Description -eq $Adapter.InterfaceDescription -and $_.IPEnabled -eq $true }
        
        if ($adapterConfig) {
            # 2 = Disable NetBIOS over TCP/IP
            $result = $adapterConfig | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 }
            
            if ($result.ReturnValue -eq 0) {
                Write-LogMessage "  ✓ NetBIOS over TCP/IP disabled" -Level Success
                $script:OptimizationsApplied++
                return $true
            }
            else {
                Write-LogMessage "  ✗ Failed to disable NetBIOS (Return code: $($result.ReturnValue))" -Level Error
                $script:OptimizationsFailed++
                return $false
            }
        }
        else {
            Write-LogMessage "  ⚠ Adapter configuration not found" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error disabling NetBIOS: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Additional Optimizations

function Set-AdapterBuffers {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Configuring buffer settings on adapter: $($Adapter.Name)" -Level Info
    
    # Increase receive buffers for better performance
    $bufferSettings = @{
        '*ReceiveBuffers' = 512
        '*TransmitBuffers' = 512
        'NumRxBuffers' = 512
        'NumTxBuffers' = 512
    }
    
    foreach ($setting in $bufferSettings.GetEnumerator()) {
        $property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | 
            Where-Object { $_.RegistryKeyword -eq $setting.Key }
        
        if ($property) {
            try {
                Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $setting.Key -RegistryValue $setting.Value -ErrorAction Stop
                Write-LogMessage "  ✓ $($property.DisplayName): $($setting.Value)" -Level Success
                $script:OptimizationsApplied++
            }
            catch {
                Write-LogMessage "  ⚠ Could not set $($property.DisplayName): $($_.Exception.Message)" -Level Warning
            }
        }
    }
}

function Optimize-InterruptModeration {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "Optimizing Interrupt Moderation on adapter: $($Adapter.Name)" -Level Info
    
    try {
        $property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | 
            Where-Object { $_.RegistryKeyword -eq '*InterruptModeration' }
        
        if ($property) {
            # Enable interrupt moderation for better performance
            Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword '*InterruptModeration' -RegistryValue 1 -ErrorAction Stop
            Write-LogMessage "  ✓ Interrupt Moderation enabled" -Level Success
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-LogMessage "  ⚠ Interrupt Moderation not available" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error configuring Interrupt Moderation: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Reporting

function Get-AdapterConfigurationReport {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "Configuration report for adapter: $($Adapter.Name)" -Level Info
    Write-LogMessage "=" * 60 -Level Info
    
    # Basic info
    Write-LogMessage "Interface: $($Adapter.InterfaceDescription)" -Level Info
    Write-LogMessage "Status: $($Adapter.Status)" -Level Info
    Write-LogMessage "Speed: $($Adapter.LinkSpeed)" -Level Info
    Write-LogMessage "MAC Address: $($Adapter.MacAddress)" -Level Info
    
    # IP configuration
    $ipConfig = Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -ErrorAction SilentlyContinue
    if ($ipConfig) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "IP Addresses:" -Level Info
        foreach ($ip in $ipConfig) {
            Write-LogMessage "  $($ip.IPAddress)/$($ip.PrefixLength) ($($ip.AddressFamily))" -Level Info
        }
    }
    
    # Advanced properties
    Write-LogMessage "" -Level Info
    Write-LogMessage "Advanced Properties:" -Level Info
    
    $properties = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | Sort-Object DisplayName
    foreach ($prop in $properties) {
        if ($prop.DisplayValue) {
            Write-LogMessage "  $($prop.DisplayName): $($prop.DisplayValue)" -Level Info
        }
    }
    
    # Bindings
    Write-LogMessage "" -Level Info
    Write-LogMessage "Bindings:" -Level Info
    
    $bindings = Get-NetAdapterBinding -Name $Adapter.Name
    foreach ($binding in $bindings) {
        $status = if ($binding.Enabled) { "Enabled" } else { "Disabled" }
        Write-LogMessage "  $($binding.DisplayName): $status" -Level Info
    }
    
    Write-LogMessage "=" * 60 -Level Info
}

function Save-ConfigurationReport {
    param([Parameter(Mandatory)]$Adapters)
    
    Write-LogMessage "Generating configuration report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "network-adapters-$timestamp.txt"
        $report = @()
        
        $report += "Network Adapter Configuration Report"
        $report += "=" * 80
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        foreach ($adapter in $Adapters) {
            $report += "Adapter: $($adapter.Name)"
            $report += "-" * 80
            $report += "  Interface: $($adapter.InterfaceDescription)"
            $report += "  Status: $($adapter.Status)"
            $report += "  Speed: $($adapter.LinkSpeed)"
            $report += "  MAC: $($adapter.MacAddress)"
            $report += ""
            
            # IP addresses
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
            if ($ipConfig) {
                $report += "  IP Addresses:"
                foreach ($ip in $ipConfig) {
                    $report += "    $($ip.IPAddress)/$($ip.PrefixLength) ($($ip.AddressFamily))"
                }
                $report += ""
            }
            
            # Key settings
            $report += "  Key Settings:"
            
            $rss = Get-NetAdapterRss -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($rss) {
                $report += "    RSS: $($rss.Enabled)"
            }
            
            $vmq = Get-NetAdapterVmq -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($vmq) {
                $report += "    VMQ: $($vmq.Enabled)"
            }
            
            $power = Get-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($power) {
                $report += "    Power Management: $($power.AllowComputerToTurnOffDevice)"
            }
            
            $report += ""
        }
        
        $report += "Summary:"
        $report += "  Optimizations Applied: $script:OptimizationsApplied"
        $report += "  Optimizations Failed: $script:OptimizationsFailed"
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Configuration report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Network Adapter Configuration" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
        exit 1
    }
    
    # Discover adapters
    $adapters = Get-ConfigurableAdapters
    
    if (-not $adapters) {
        Write-LogMessage "No network adapters to configure" -Level Error
        exit 1
    }
    
    # Configuration summary
    Write-LogMessage "Configuration options:" -Level Info
    Write-LogMessage "  Disable IPv6: $DisableIPv6" -Level Info
    Write-LogMessage "  Optimize for Virtualization: $OptimizeForVirtualization" -Level Info
    Write-LogMessage "  Enable Jumbo Frames: $EnableJumboFrames" -Level Info
    Write-LogMessage "  Disable Power Saving: $DisablePowerSaving" -Level Info
    Write-LogMessage "  Configure Offloading: $ConfigureOffloading" -Level Info
    Write-LogMessage "  Disable NetBIOS: $DisableNetBIOS" -Level Info
    Write-LogMessage "" -Level Info
    
    # Configure each adapter
    foreach ($adapter in $adapters) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "========== Configuring: $($adapter.Name) ==========" -Level Info
        
        # IPv6
        if ($DisableIPv6) {
            Disable-IPv6OnAdapter -Adapter $adapter
        }
        
        # TCP/IP Offloading
        if ($ConfigureOffloading) {
            Configure-TCPOffloading -Adapter $adapter
        }
        
        # RSS
        Configure-RSS -Adapter $adapter
        
        # VMQ
        Configure-VMQ -Adapter $adapter
        
        # Power Management
        if ($DisablePowerSaving) {
            Disable-AdapterPowerSaving -Adapter $adapter
        }
        
        # Jumbo Frames
        if ($EnableJumboFrames) {
            Enable-JumboFrames -Adapter $adapter
        }
        
        # NetBIOS
        if ($DisableNetBIOS) {
            Disable-NetBIOSOverTCPIP -Adapter $adapter
        }
        
        # Buffer settings
        Set-AdapterBuffers -Adapter $adapter
        
        # Interrupt moderation
        Optimize-InterruptModeration -Adapter $adapter
        
        # Report
        Get-AdapterConfigurationReport -Adapter $adapter
    }
    
    # Save report
    Save-ConfigurationReport -Adapters $adapters
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configuration Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Adapters Configured: $($adapters.Count)" -Level Info
    Write-LogMessage "Optimizations Applied: $script:OptimizationsApplied" -Level Info
    Write-LogMessage "Optimizations Failed: $script:OptimizationsFailed" -Level Info
    Write-LogMessage "Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:OptimizationsFailed -eq 0) {
        Write-LogMessage "Network adapter configuration completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Configuration completed with $script:OptimizationsFailed failures" -Level Warning
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
