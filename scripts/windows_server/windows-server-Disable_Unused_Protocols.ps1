<#
.SYNOPSIS
    Disable Unused Network Protocols

.DESCRIPTION
    Disables unnecessary network protocols including NetBIOS over TCP/IP, LLMNR,
    WPAD, and other legacy protocols that can be security risks.

.NOTES
    File Name      : windows-server-Disable_Unused_Protocols.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Disable_Unused_Protocols.ps1
    Disables all unused protocols
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:ProtocolsDisabled = 0

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
    $logMessage = "[$timestamp] [$prefix] [NetProtocol] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "==================================================="
    Write-Log "Disable Unused Network Protocols Script"
    Write-Log "==================================================="
    
    # Disable NetBIOS over TCP/IP
    Write-Log "Disabling NetBIOS over TCP/IP..."
    try {
        $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE'
        
        foreach ($adapter in $adapters) {
            $result = $adapter.SetTcpipNetbios(2) # 0=Default, 1=Enable, 2=Disable
            if ($result.ReturnValue -eq 0) {
                Write-Log "  ✓ Disabled NetBIOS on: $($adapter.Description)"
                $script:ProtocolsDisabled++
            } else {
                Write-Log "  Failed to disable NetBIOS on: $($adapter.Description)" -Level Warning
            }
        }
        
        # Also disable via registry
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
        Set-ItemProperty -Path $regPath -Name 'NodeType' -Value 2 -Type DWord -ErrorAction SilentlyContinue
        
        Write-Log "✓ NetBIOS over TCP/IP disabled"
        
    } catch {
        Write-Log "Error disabling NetBIOS: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable LLMNR (Link-Local Multicast Name Resolution)
    Write-Log ""
    Write-Log "Disabling LLMNR..."
    try {
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name 'EnableMulticast' -Value 0 -Type DWord
        Write-Log "✓ LLMNR disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling LLMNR: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable WPAD (Web Proxy Auto-Discovery)
    Write-Log ""
    Write-Log "Disabling WPAD..."
    try {
        # Disable WPAD via registry
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad'
        )
        
        foreach ($regPath in $regPaths) {
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name 'DoNotAllowWpad' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
        
        # Disable automatic proxy detection
        $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
        Set-ItemProperty -Path $regPath -Name 'AutoDetect' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        
        Write-Log "✓ WPAD disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling WPAD: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable IPv6 (optional - only if not needed)
    Write-Log ""
    Write-Log "Configuring IPv6..."
    try {
        # Instead of completely disabling, prefer IPv4 over IPv6
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # 0xFF = Disable all IPv6, 0x20 = Prefer IPv4 over IPv6
        Set-ItemProperty -Path $regPath -Name 'DisabledComponents' -Value 0x20 -Type DWord
        Write-Log "✓ Configured to prefer IPv4 over IPv6"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error configuring IPv6: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable mDNS (Multicast DNS)
    Write-Log ""
    Write-Log "Disabling mDNS..."
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name 'EnableMDNS' -Value 0 -Type DWord
        Write-Log "✓ mDNS disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling mDNS: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable Windows Connect Now
    Write-Log ""
    Write-Log "Disabling Windows Connect Now..."
    try {
        $services = @('wcncsvc', 'WwanSvc')
        
        foreach ($svcName in $services) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svcName -StartupType Disabled
                Write-Log "  ✓ Disabled service: $svcName"
                $script:ProtocolsDisabled++
            }
        }
        
    } catch {
        Write-Log "Error disabling Windows Connect Now: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable SSDP Discovery (UPnP)
    Write-Log ""
    Write-Log "Disabling SSDP Discovery (UPnP)..."
    try {
        $svc = Get-Service -Name 'SSDPSRV' -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name 'SSDPSRV' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'SSDPSRV' -StartupType Disabled
            Write-Log "✓ SSDP Discovery disabled"
            $script:ProtocolsDisabled++
        }
        
    } catch {
        Write-Log "Error disabling SSDP: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable Remote Registry
    Write-Log ""
    Write-Log "Disabling Remote Registry..."
    try {
        $svc = Get-Service -Name 'RemoteRegistry' -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name 'RemoteRegistry' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'RemoteRegistry' -StartupType Disabled
            Write-Log "✓ Remote Registry disabled"
            $script:ProtocolsDisabled++
        }
        
    } catch {
        Write-Log "Error disabling Remote Registry: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable LMHOSTS lookup
    Write-Log ""
    Write-Log "Disabling LMHOSTS lookup..."
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
        Set-ItemProperty -Path $regPath -Name 'EnableLMHOSTS' -Value 0 -Type DWord
        Write-Log "✓ LMHOSTS lookup disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling LMHOSTS: $($_.Exception.Message)" -Level Warning
    }
    
    # Harden DNS configuration
    Write-Log ""
    Write-Log "Hardening DNS configuration..."
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
        
        # Disable DNS devolution
        Set-ItemProperty -Path $regPath -Name 'UseDomainNameDevolution' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        
        # Set DNS query timeout
        Set-ItemProperty -Path $regPath -Name 'QueryTimeout' -Value 2 -Type DWord -ErrorAction SilentlyContinue
        
        Write-Log "✓ DNS configuration hardened"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error hardening DNS: $($_.Exception.Message)" -Level Warning
    }
    
    # Flush DNS cache
    Write-Log ""
    Write-Log "Flushing DNS cache..."
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-Log "✓ DNS cache flushed"
        
    } catch {
        Write-Log "Error flushing DNS cache: $($_.Exception.Message)" -Level Warning
    }
    
    # Flush NetBIOS cache
    Write-Log "Flushing NetBIOS cache..."
    try {
        nbtstat -R | Out-Null
        nbtstat -RR | Out-Null
        Write-Log "✓ NetBIOS cache flushed"
        
    } catch {
        Write-Log "Error flushing NetBIOS cache: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "Protocol Disable Summary"
    Write-Log "==================================================="
    Write-Log "Protocols/Services disabled: $script:ProtocolsDisabled"
    Write-Log "NetBIOS over TCP/IP: Disabled"
    Write-Log "LLMNR: Disabled"
    Write-Log "WPAD: Disabled"
    Write-Log "mDNS: Disabled"
    Write-Log "IPv6: Prefer IPv4"
    Write-Log "SSDP/UPnP: Disabled"
    Write-Log "Remote Registry: Disabled"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "Protocol hardening completed!"
    Write-Log ""
    Write-Log "IMPORTANT:"
    Write-Log "  - A system restart is recommended for all changes to take effect"
    Write-Log "  - Test network connectivity after restart"
    Write-Log "  - These changes improve security by reducing attack surface"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}