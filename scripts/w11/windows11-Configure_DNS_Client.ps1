<#
.SYNOPSIS
    Configure DNS Client Settings for Windows 10/11

.DESCRIPTION
    Configures DNS client settings including DNS servers, suffix search list,
    registration settings, and DNS cache. Optimized for Windows 10/11.

.NOTES
    File Name      : windows11-Configure_DNS_Client.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Configure_DNS_Client.ps1
    Displays current DNS configuration
    
.EXAMPLE
    .\windows11-Configure_DNS_Client.ps1 -PrimaryDNS "10.0.0.10" -SecondaryDNS "10.0.0.11" -DNSSuffixList @('contoso.com', 'corp.contoso.com')
    Sets DNS servers and suffix search list
    
.PARAMETER PrimaryDNS
    Primary DNS server IP address
    
.PARAMETER SecondaryDNS
    Secondary DNS server IP address
    
.PARAMETER DNSSuffixList
    Array of DNS suffixes for search list
    
.PARAMETER RegisterConnection
    Register connection address in DNS
    
.PARAMETER UseSuffixWhenRegistering
    Use connection-specific DNS suffix when registering
    
.PARAMETER FlushDNSCache
    Flush DNS resolver cache
    
.PARAMETER DisableNetBIOS
    Disable NetBIOS over TCP/IP
#>

[CmdletBinding()]
param(
    [string]$PrimaryDNS = "",
    [string]$SecondaryDNS = "",
    [string[]]$DNSSuffixList = @(),
    [switch]$RegisterConnection,
    [switch]$UseSuffixWhenRegistering,
    [switch]$FlushDNSCache,
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
$script:ConfigurationsApplied = 0
$script:ConfigurationsFailed = 0

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

function Test-IPAddress {
    param([string]$IP)
    
    try {
        [System.Net.IPAddress]::Parse($IP) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region DNS Server Configuration

function Set-DNSServerAddresses {
    if ([string]::IsNullOrWhiteSpace($PrimaryDNS) -and [string]::IsNullOrWhiteSpace($SecondaryDNS)) {
        Write-LogMessage "No DNS servers specified, skipping DNS server configuration" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring DNS server addresses..." -Level Info
    
    try {
        # Get active network adapters
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        
        if ($adapters.Count -eq 0) {
            Write-LogMessage "No active network adapters found" -Level Warning
            return $false
        }
        
        foreach ($adapter in $adapters) {
            Write-LogMessage "Configuring adapter: $($adapter.Name)" -Level Info
            
            # Build DNS server list
            $dnsServers = @()
            if ($PrimaryDNS -and (Test-IPAddress $PrimaryDNS)) {
                $dnsServers += $PrimaryDNS
            }
            if ($SecondaryDNS -and (Test-IPAddress $SecondaryDNS)) {
                $dnsServers += $SecondaryDNS
            }
            
            if ($dnsServers.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsServers
                Write-LogMessage "  DNS servers set: $($dnsServers -join ', ')" -Level Success
                $script:ConfigurationsApplied++
            }
            else {
                Write-LogMessage "  No valid DNS servers provided" -Level Warning
            }
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error setting DNS servers: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region DNS Suffix Configuration

function Set-DNSSuffixSearchList {
    if ($DNSSuffixList.Count -eq 0) {
        Write-LogMessage "No DNS suffix list specified" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring DNS suffix search list..." -Level Info
    
    try {
        # Set DNS suffix search list
        $suffixString = $DNSSuffixList -join ','
        
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
            -Name 'SearchList' -Value $suffixString -Force
        
        Write-LogMessage "DNS suffix search list configured:" -Level Info
        foreach ($suffix in $DNSSuffixList) {
            Write-LogMessage "  - $suffix" -Level Info
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error setting DNS suffix list: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-DNSRegistrationSettings {
    Write-LogMessage "Configuring DNS registration settings..." -Level Info
    
    try {
        # Get active network adapters
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        
        foreach ($adapter in $adapters) {
            $adapterGuid = $adapter.InterfaceGuid
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$adapterGuid"
            
            if (Test-Path $regPath) {
                # Register connection address in DNS
                if ($RegisterConnection) {
                    Set-ItemProperty -Path $regPath -Name 'RegisterAdapterName' -Value 1 -Type DWord -Force
                    Write-LogMessage "  Enabled DNS registration for: $($adapter.Name)" -Level Info
                }
                
                # Use connection-specific DNS suffix
                if ($UseSuffixWhenRegistering) {
                    Set-ItemProperty -Path $regPath -Name 'UseDomainNameDevolution' -Value 1 -Type DWord -Force
                    Write-LogMessage "  Enabled suffix devolution for: $($adapter.Name)" -Level Info
                }
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring DNS registration: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region DNS Cache Configuration

function Set-DNSCacheSettings {
    Write-LogMessage "Configuring DNS cache settings..." -Level Info
    
    try {
        # Configure DNS cache
        $dnsCachePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
        
        # Set negative cache time (0 = disabled, good for dynamic environments)
        Set-ItemProperty -Path $dnsCachePath -Name 'MaxCacheTtl' -Value 86400 -Type DWord -Force
        Set-ItemProperty -Path $dnsCachePath -Name 'MaxNegativeCacheTtl' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $dnsCachePath -Name 'NegativeCacheTime' -Value 0 -Type DWord -Force
        
        Write-LogMessage "DNS cache settings configured" -Level Success
        $script:ConfigurationsApplied++
        
        return $true
    }
    catch {
        Write-LogMessage "Error configuring DNS cache: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Clear-DNSCache {
    if (-not $FlushDNSCache) {
        return $false
    }
    
    Write-LogMessage "Flushing DNS resolver cache..." -Level Info
    
    try {
        Clear-DnsClientCache
        Write-LogMessage "DNS cache flushed successfully" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error flushing DNS cache: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region NetBIOS Configuration

function Disable-NetBIOSOverTCPIP {
    if (-not $DisableNetBIOS) {
        Write-LogMessage "Skipping NetBIOS configuration" -Level Info
        return $false
    }
    
    Write-LogMessage "Disabling NetBIOS over TCP/IP..." -Level Info
    
    try {
        # Get network adapters
        $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        
        foreach ($adapter in $adapters) {
            # Disable NetBIOS over TCP/IP
            # 0 = Use DHCP, 1 = Enable, 2 = Disable
            $adapter.SetTcpipNetbios(2) | Out-Null
            
            Write-LogMessage "  Disabled NetBIOS for: $($adapter.Description)" -Level Info
        }
        
        Write-LogMessage "NetBIOS over TCP/IP disabled" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error disabling NetBIOS: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region DNS Testing and Verification

function Test-DNSConfiguration {
    Write-LogMessage "Testing DNS configuration..." -Level Info
    
    try {
        # Get DNS configuration
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        
        foreach ($adapter in $adapters) {
            $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
            
            if ($dnsConfig.ServerAddresses.Count -gt 0) {
                Write-LogMessage "  Adapter: $($adapter.Name)" -Level Info
                Write-LogMessage "    DNS Servers: $($dnsConfig.ServerAddresses -join ', ')" -Level Info
                
                # Test DNS resolution
                foreach ($dnsServer in $dnsConfig.ServerAddresses) {
                    try {
                        $testResult = Test-NetConnection -ComputerName $dnsServer -Port 53 -WarningAction SilentlyContinue
                        if ($testResult.TcpTestSucceeded) {
                            Write-LogMessage "    DNS server $dnsServer is reachable" -Level Success
                        }
                        else {
                            Write-LogMessage "    DNS server $dnsServer is not reachable" -Level Warning
                        }
                    }
                    catch {
                        Write-LogMessage "    Could not test DNS server $dnsServer" -Level Warning
                    }
                }
            }
            else {
                Write-LogMessage "  Adapter: $($adapter.Name) - No DNS servers configured" -Level Warning
            }
        }
        
        # Test DNS resolution
        Write-LogMessage "Testing DNS resolution..." -Level Info
        try {
            $testDomain = "microsoft.com"
            $resolveResult = Resolve-DnsName -Name $testDomain -ErrorAction Stop
            Write-LogMessage "  DNS resolution test successful ($testDomain)" -Level Success
        }
        catch {
            Write-LogMessage "  DNS resolution test failed: $($_.Exception.Message)" -Level Warning
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error testing DNS configuration: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Get-DNSClientReport {
    Write-LogMessage "Generating DNS client configuration report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "dns-client-config-$timestamp.txt"
        $report = @()
        
        $report += "DNS Client Configuration Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # Network adapters and DNS servers
        $report += "Network Adapters and DNS Configuration:"
        $report += "-" * 60
        
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        
        foreach ($adapter in $adapters) {
            $report += ""
            $report += "Adapter: $($adapter.Name)"
            $report += "  Status: $($adapter.Status)"
            $report += "  Interface Index: $($adapter.ifIndex)"
            
            # DNS servers
            $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
                $report += "  DNS Servers:"
                foreach ($dns in $dnsConfig.ServerAddresses) {
                    $report += "    - $dns"
                }
            }
            else {
                $report += "  DNS Servers: DHCP or not configured"
            }
            
            # Connection-specific DNS suffix
            $suffix = Get-DnsClient -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
            if ($suffix) {
                $report += "  Connection Suffix: $($suffix.ConnectionSpecificSuffix)"
                $report += "  Register Connection: $($suffix.RegisterThisConnectionsAddress)"
                $report += "  Use Suffix: $($suffix.UseSuffixWhenRegistering)"
            }
        }
        
        # DNS suffix search list
        $report += ""
        $report += "DNS Suffix Search List:"
        $report += "-" * 60
        
        $searchList = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'SearchList' -ErrorAction SilentlyContinue
        if ($searchList -and $searchList.SearchList) {
            $suffixes = $searchList.SearchList -split ','
            foreach ($suffix in $suffixes) {
                $report += "  - $suffix"
            }
        }
        else {
            $report += "  Not configured"
        }
        
        # DNS cache statistics
        $report += ""
        $report += "DNS Cache Statistics:"
        $report += "-" * 60
        
        $cacheStats = Get-DnsClientCache -ErrorAction SilentlyContinue
        if ($cacheStats) {
            $report += "  Cached entries: $($cacheStats.Count)"
        }
        else {
            $report += "  DNS cache is empty"
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "DNS client report saved to: $reportFile" -Level Success
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
    Write-LogMessage "DNS Client Configuration" -Level Info
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
    
    # Configure DNS settings
    Set-DNSServerAddresses | Out-Null
    Set-DNSSuffixSearchList | Out-Null
    Set-DNSRegistrationSettings | Out-Null
    Set-DNSCacheSettings | Out-Null
    Clear-DNSCache | Out-Null
    Disable-NetBIOSOverTCPIP | Out-Null
    
    # Test and verify
    Test-DNSConfiguration | Out-Null
    
    # Generate report
    Get-DNSClientReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configuration Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configurations Applied: $script:ConfigurationsApplied" -Level Info
    Write-LogMessage "Configuration Failures: $script:ConfigurationsFailed" -Level Info
    Write-LogMessage "Duration: $($duration.TotalSeconds) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:ConfigurationsFailed -eq 0) {
        Write-LogMessage "DNS client configuration completed successfully!" -Level Success
        Write-LogMessage "Test resolution: Resolve-DnsName -Name example.com" -Level Info
        exit 0
    }
    else {
        Write-LogMessage "Configuration completed with $script:ConfigurationsFailed errors" -Level Warning
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
