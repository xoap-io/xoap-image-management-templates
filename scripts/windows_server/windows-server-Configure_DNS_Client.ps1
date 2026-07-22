<#
.SYNOPSIS
    Configure DNS Client Settings for Windows Server

.DESCRIPTION
    Configures DNS client settings including DNS servers, suffix search list,
    registration settings, and DNS cache. Optimized for Windows Server 2025.

.NOTES
    File Name      : windows-server-Configure_DNS_Client.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_DNS_Client.ps1
    Displays current DNS configuration
    
.EXAMPLE
    .\windows-server-Configure_DNS_Client.ps1 -PrimaryDNS "10.0.0.10" -SecondaryDNS "10.0.0.11" -DNSSuffixList @('contoso.com', 'corp.contoso.com')
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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [DNS] $Message"
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
        Write-Log "No DNS servers specified, skipping DNS server configuration" -Level INFO
        return $false
    }
    
    Write-Log "Configuring DNS server addresses..." -Level INFO
    
    try {
        # Get active network adapters
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        
        if ($adapters.Count -eq 0) {
            Write-Log "No active network adapters found" -Level WARN
            return $false
        }
        
        foreach ($adapter in $adapters) {
            Write-Log "Configuring adapter: $($adapter.Name)" -Level INFO
            
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
                Write-Log "  DNS servers set: $($dnsServers -join ', ')" -Level INFO
                $script:ConfigurationsApplied++
            }
            else {
                Write-Log "  No valid DNS servers provided" -Level WARN
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Error setting DNS servers: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region DNS Suffix Configuration

function Set-DNSSuffixSearchList {
    if ($DNSSuffixList.Count -eq 0) {
        Write-Log "No DNS suffix list specified" -Level INFO
        return $false
    }
    
    Write-Log "Configuring DNS suffix search list..." -Level INFO
    
    try {
        # Set DNS suffix search list
        $suffixString = $DNSSuffixList -join ','
        
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
            -Name 'SearchList' -Value $suffixString -Force
        
        Write-Log "DNS suffix search list configured:" -Level INFO
        foreach ($suffix in $DNSSuffixList) {
            Write-Log "  - $suffix" -Level INFO
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error setting DNS suffix list: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-DNSRegistrationSettings {
    Write-Log "Configuring DNS registration settings..." -Level INFO
    
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
                    Write-Log "  Enabled DNS registration for: $($adapter.Name)" -Level INFO
                }
                
                # Use connection-specific DNS suffix
                if ($UseSuffixWhenRegistering) {
                    Set-ItemProperty -Path $regPath -Name 'UseDomainNameDevolution' -Value 1 -Type DWord -Force
                    Write-Log "  Enabled suffix devolution for: $($adapter.Name)" -Level INFO
                }
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring DNS registration: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region DNS Cache Configuration

function Set-DNSCacheSettings {
    Write-Log "Configuring DNS cache settings..." -Level INFO
    
    try {
        # Configure DNS cache
        $dnsCachePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
        
        # Set negative cache time (0 = disabled, good for dynamic environments)
        Set-ItemProperty -Path $dnsCachePath -Name 'MaxCacheTtl' -Value 86400 -Type DWord -Force
        Set-ItemProperty -Path $dnsCachePath -Name 'MaxNegativeCacheTtl' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $dnsCachePath -Name 'NegativeCacheTime' -Value 0 -Type DWord -Force
        
        Write-Log "DNS cache settings configured" -Level INFO
        $script:ConfigurationsApplied++
        
        return $true
    }
    catch {
        Write-Log "Error configuring DNS cache: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Clear-DNSCache {
    if (-not $FlushDNSCache) {
        return $false
    }
    
    Write-Log "Flushing DNS resolver cache..." -Level INFO
    
    try {
        Clear-DnsClientCache
        Write-Log "DNS cache flushed successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error flushing DNS cache: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region NetBIOS Configuration

function Disable-NetBIOSOverTCPIP {
    if (-not $DisableNetBIOS) {
        Write-Log "Skipping NetBIOS configuration" -Level INFO
        return $false
    }
    
    Write-Log "Disabling NetBIOS over TCP/IP..." -Level INFO
    
    try {
        # Get network adapters
        $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        
        foreach ($adapter in $adapters) {
            # Disable NetBIOS over TCP/IP
            # 0 = Use DHCP, 1 = Enable, 2 = Disable
            $adapter.SetTcpipNetbios(2) | Out-Null
            
            Write-Log "  Disabled NetBIOS for: $($adapter.Description)" -Level INFO
        }
        
        Write-Log "NetBIOS over TCP/IP disabled" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error disabling NetBIOS: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region DNS Testing and Verification

function Test-DNSConfiguration {
    Write-Log "Testing DNS configuration..." -Level INFO
    
    try {
        # Get DNS configuration
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        
        foreach ($adapter in $adapters) {
            $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
            
            if ($dnsConfig.ServerAddresses.Count -gt 0) {
                Write-Log "  Adapter: $($adapter.Name)" -Level INFO
                Write-Log "    DNS Servers: $($dnsConfig.ServerAddresses -join ', ')" -Level INFO
                
                # Test DNS resolution
                foreach ($dnsServer in $dnsConfig.ServerAddresses) {
                    try {
                        $testResult = Test-NetConnection -ComputerName $dnsServer -Port 53 -WarningAction SilentlyContinue
                        if ($testResult.TcpTestSucceeded) {
                            Write-Log "    DNS server $dnsServer is reachable" -Level INFO
                        }
                        else {
                            Write-Log "    DNS server $dnsServer is not reachable" -Level WARN
                        }
                    }
                    catch {
                        Write-Log "    Could not test DNS server $dnsServer" -Level WARN
                    }
                }
            }
            else {
                Write-Log "  Adapter: $($adapter.Name) - No DNS servers configured" -Level WARN
            }
        }
        
        # Test DNS resolution
        Write-Log "Testing DNS resolution..." -Level INFO
        try {
            $testDomain = "microsoft.com"
            $resolveResult = Resolve-DnsName -Name $testDomain -ErrorAction Stop
            Write-Log "  DNS resolution test successful ($testDomain)" -Level INFO
        }
        catch {
            Write-Log "  DNS resolution test failed: $($_.Exception.Message)" -Level WARN
        }
        
        return $true
    }
    catch {
        Write-Log "Error testing DNS configuration: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Get-DNSClientReport {
    Write-Log "Generating DNS client configuration report..." -Level INFO
    
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
        
        Write-Log "DNS client report saved to: $reportFile" -Level INFO
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

    Write-Log "===== Configure_DNS_Client starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
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
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    if ($script:ConfigurationsFailed -eq 0) {
        Write-Log "===== Configure_DNS_Client complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_DNS_Client complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) =====" -Level WARN
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
