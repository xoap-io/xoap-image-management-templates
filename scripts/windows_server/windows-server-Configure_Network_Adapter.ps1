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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [NetAdapter] $Message"
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
            Write-Log "  [OK] $Description" -Level INFO
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-Log "  [WARN] Property '$PropertyName' not found on adapter '$AdapterName'" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Failed to set $Description : $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Network Adapter Discovery

function Get-ConfigurableAdapters {
    Write-Log "Discovering network adapters..." -Level INFO
    
    try {
        $adapters = Get-NetAdapter -Name $AdapterName | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected' }
        
        if (-not $adapters) {
            Write-Log "No network adapters found matching '$AdapterName'" -Level WARN
            return $null
        }
        
        Write-Log "Found $($adapters.Count) network adapter(s):" -Level INFO
        
        foreach ($adapter in $adapters) {
            $speed = if ($adapter.LinkSpeed) { $adapter.LinkSpeed } else { "Unknown" }
            Write-Log "  - $($adapter.Name) ($($adapter.InterfaceDescription)) - $speed - Status: $($adapter.Status)" -Level INFO
        }
        
        return $adapters
    }
    catch {
        Write-Log "Error discovering adapters: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

#endregion

#region IPv6 Configuration

function Disable-IPv6OnAdapter {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Disabling IPv6 on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        # Disable IPv6 binding
        Disable-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop
        
        Write-Log "  [OK] IPv6 disabled" -Level INFO
        $script:OptimizationsApplied++
        
        # Also set registry key to disable IPv6 globally
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name 'DisabledComponents' -Value 0xFF -Type DWord
        Write-Log "  [OK] IPv6 disabled globally via registry" -Level INFO
        
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error disabling IPv6: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region TCP/IP Offloading

function Configure-TCPOffloading {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Configuring TCP/IP offloading on adapter: $($Adapter.Name)" -Level INFO
    
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
                Write-Log "  [OK] $($property.DisplayName): $($setting.Value)" -Level INFO
                $script:OptimizationsApplied++
            }
            catch {
                Write-Log "  [WARN] Could not set $($property.DisplayName): $($_.Exception.Message)" -Level WARN
            }
        }
    }
}

#endregion

#region RSS Configuration

function Configure-RSS {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Configuring RSS (Receive Side Scaling) on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        # Enable RSS
        $rss = Get-NetAdapterRss -Name $Adapter.Name -ErrorAction SilentlyContinue
        
        if ($rss) {
            if ($OptimizeForVirtualization) {
                # For VMs, use fewer RSS queues
                Set-NetAdapterRss -Name $Adapter.Name -Enabled $true -NumberOfReceiveQueues 2 -ErrorAction Stop
                Write-Log "  [OK] RSS enabled with 2 queues (VM optimized)" -Level INFO
            }
            else {
                # For physical, use more queues
                Set-NetAdapterRss -Name $Adapter.Name -Enabled $true -ErrorAction Stop
                Write-Log "  [OK] RSS enabled" -Level INFO
            }
            
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-Log "  [WARN] RSS not supported on this adapter" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error configuring RSS: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region VMQ Configuration

function Configure-VMQ {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Configuring VMQ (Virtual Machine Queue) on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        $vmq = Get-NetAdapterVmq -Name $Adapter.Name -ErrorAction SilentlyContinue
        
        if ($vmq) {
            if ($OptimizeForVirtualization) {
                # Disable VMQ for VMs (not needed, can cause issues)
                Set-NetAdapterVmq -Name $Adapter.Name -Enabled $false -ErrorAction Stop
                Write-Log "  [OK] VMQ disabled (VM optimization)" -Level INFO
            }
            else {
                # Enable VMQ for Hyper-V hosts
                Set-NetAdapterVmq -Name $Adapter.Name -Enabled $true -ErrorAction Stop
                Write-Log "  [OK] VMQ enabled" -Level INFO
            }
            
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-Log "  [WARN] VMQ not supported on this adapter" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error configuring VMQ: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Power Management

function Disable-AdapterPowerSaving {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Disabling power management on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        $powerSettings = Get-NetAdapterPowerManagement -Name $Adapter.Name -ErrorAction Stop
        
        # Disable all power saving features
        Set-NetAdapterPowerManagement -Name $Adapter.Name `
            -AllowComputerToTurnOffDevice Disabled `
            -DeviceSleepOnDisconnect Disabled `
            -ErrorAction Stop
        
        Write-Log "  [OK] Power management disabled" -Level INFO
        $script:OptimizationsApplied++
        
        # Also disable wake-on-LAN if not needed
        $wol = Get-NetAdapterPowerManagement -Name $Adapter.Name
        if ($wol.WakeOnMagicPacket -ne 'Disabled') {
            Set-NetAdapterPowerManagement -Name $Adapter.Name -WakeOnMagicPacket Disabled -ErrorAction SilentlyContinue
            Write-Log "  [OK] Wake-on-LAN disabled" -Level INFO
        }
        
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error disabling power management: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Jumbo Frames

function Enable-JumboFrames {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Enabling Jumbo Frames on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        # Check if adapter supports jumbo frames
        $property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | 
            Where-Object { $_.RegistryKeyword -like '*JumboPacket*' -or $_.DisplayName -like '*Jumbo*' }
        
        if ($property) {
            # Set to 9000 (9014 bytes including header)
            Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $property.RegistryKeyword -RegistryValue 9014 -ErrorAction Stop
            Write-Log "  [OK] Jumbo Frames enabled (MTU 9000)" -Level INFO
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-Log "  [WARN] Jumbo Frames not supported on this adapter" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error enabling Jumbo Frames: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region NetBIOS Configuration

function Disable-NetBIOSOverTCPIP {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Disabling NetBIOS over TCP/IP on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        $adapterConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | 
            Where-Object { $_.Description -eq $Adapter.InterfaceDescription -and $_.IPEnabled -eq $true }
        
        if ($adapterConfig) {
            # 2 = Disable NetBIOS over TCP/IP
            $result = $adapterConfig | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 }
            
            if ($result.ReturnValue -eq 0) {
                Write-Log "  [OK] NetBIOS over TCP/IP disabled" -Level INFO
                $script:OptimizationsApplied++
                return $true
            }
            else {
                Write-Log "  [FAIL] Failed to disable NetBIOS (Return code: $($result.ReturnValue))" -Level ERROR
                $script:OptimizationsFailed++
                return $false
            }
        }
        else {
            Write-Log "  [WARN] Adapter configuration not found" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error disabling NetBIOS: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Additional Optimizations

function Set-AdapterBuffers {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Configuring buffer settings on adapter: $($Adapter.Name)" -Level INFO
    
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
                Write-Log "  [OK] $($property.DisplayName): $($setting.Value)" -Level INFO
                $script:OptimizationsApplied++
            }
            catch {
                Write-Log "  [WARN] Could not set $($property.DisplayName): $($_.Exception.Message)" -Level WARN
            }
        }
    }
}

function Optimize-InterruptModeration {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "Optimizing Interrupt Moderation on adapter: $($Adapter.Name)" -Level INFO
    
    try {
        $property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | 
            Where-Object { $_.RegistryKeyword -eq '*InterruptModeration' }
        
        if ($property) {
            # Enable interrupt moderation for better performance
            Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword '*InterruptModeration' -RegistryValue 1 -ErrorAction Stop
            Write-Log "  [OK] Interrupt Moderation enabled" -Level INFO
            $script:OptimizationsApplied++
            return $true
        }
        else {
            Write-Log "  [WARN] Interrupt Moderation not available" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error configuring Interrupt Moderation: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Reporting

function Get-AdapterConfigurationReport {
    param([Parameter(Mandatory)]$Adapter)
    
    Write-Log "" -Level INFO
    Write-Log "Configuration report for adapter: $($Adapter.Name)" -Level INFO
    Write-Log "=" * 60 -Level INFO
    
    # Basic info
    Write-Log "Interface: $($Adapter.InterfaceDescription)" -Level INFO
    Write-Log "Status: $($Adapter.Status)" -Level INFO
    Write-Log "Speed: $($Adapter.LinkSpeed)" -Level INFO
    Write-Log "MAC Address: $($Adapter.MacAddress)" -Level INFO
    
    # IP configuration
    $ipConfig = Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -ErrorAction SilentlyContinue
    if ($ipConfig) {
        Write-Log "" -Level INFO
        Write-Log "IP Addresses:" -Level INFO
        foreach ($ip in $ipConfig) {
            Write-Log "  $($ip.IPAddress)/$($ip.PrefixLength) ($($ip.AddressFamily))" -Level INFO
        }
    }
    
    # Advanced properties
    Write-Log "" -Level INFO
    Write-Log "Advanced Properties:" -Level INFO
    
    $properties = Get-NetAdapterAdvancedProperty -Name $Adapter.Name | Sort-Object DisplayName
    foreach ($prop in $properties) {
        if ($prop.DisplayValue) {
            Write-Log "  $($prop.DisplayName): $($prop.DisplayValue)" -Level INFO
        }
    }
    
    # Bindings
    Write-Log "" -Level INFO
    Write-Log "Bindings:" -Level INFO
    
    $bindings = Get-NetAdapterBinding -Name $Adapter.Name
    foreach ($binding in $bindings) {
        $status = if ($binding.Enabled) { "Enabled" } else { "Disabled" }
        Write-Log "  $($binding.DisplayName): $status" -Level INFO
    }
    
    Write-Log "=" * 60 -Level INFO
}

function Save-ConfigurationReport {
    param([Parameter(Mandatory)]$Adapters)
    
    Write-Log "Generating configuration report..." -Level INFO
    
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
        
        Write-Log "Configuration report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    # Setup local file logging to C:\xoap-logs (transcript captures all host output)
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
    } catch {
        Write-Host "[WARN] Failed to start transcript logging to $LogDir : $($_.Exception.Message)"
    }

    $scriptStartTime = Get-Date

    Write-Log "===== Configure_Network_Adapter starting (AdapterName=$AdapterName) ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Discover adapters
    $adapters = Get-ConfigurableAdapters
    
    if (-not $adapters) {
        Write-Log "No network adapters to configure" -Level ERROR
        exit 1
    }
    
    # Configuration summary
    Write-Log "Configuration options:" -Level INFO
    Write-Log "  Disable IPv6: $DisableIPv6" -Level INFO
    Write-Log "  Optimize for Virtualization: $OptimizeForVirtualization" -Level INFO
    Write-Log "  Enable Jumbo Frames: $EnableJumboFrames" -Level INFO
    Write-Log "  Disable Power Saving: $DisablePowerSaving" -Level INFO
    Write-Log "  Configure Offloading: $ConfigureOffloading" -Level INFO
    Write-Log "  Disable NetBIOS: $DisableNetBIOS" -Level INFO
    Write-Log "" -Level INFO
    
    # Configure each adapter
    foreach ($adapter in $adapters) {
        Write-Log "" -Level INFO
        Write-Log "========== Configuring: $($adapter.Name) ==========" -Level INFO
        
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
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    Write-Log "Adapters Configured: $($adapters.Count)"

    if ($script:OptimizationsFailed -eq 0) {
        Write-Log "===== Configure_Network_Adapter complete in $([int]$duration)s; applied=$($script:OptimizationsApplied) failed=$($script:OptimizationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_Network_Adapter complete in $([int]$duration)s; applied=$($script:OptimizationsApplied) failed=$($script:OptimizationsFailed) =====" -Level WARN
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}

#endregion
