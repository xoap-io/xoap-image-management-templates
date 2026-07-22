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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [NetProtocol] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

try {
    # Setup local file logging to C:\xoap-logs (transcript captures all host output)
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
    } catch {
        Write-Host "[WARN] Failed to start transcript logging to $LogDir : $($_.Exception.Message)"
    }

    $startTime = Get-Date

    Write-Log "===== Disable_Unused_Protocols starting ====="

    # Disable NetBIOS over TCP/IP
    Write-Log "Disabling NetBIOS over TCP/IP..."
    try {
        $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE'
        
        foreach ($adapter in $adapters) {
            $result = $adapter.SetTcpipNetbios(2) # 0=Default, 1=Enable, 2=Disable
            if ($result.ReturnValue -eq 0) {
                Write-Log "  [OK] Disabled NetBIOS on: $($adapter.Description)"
                $script:ProtocolsDisabled++
            } else {
                Write-Log "  Failed to disable NetBIOS on: $($adapter.Description)" -Level WARN
            }
        }
        
        # Also disable via registry
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
        Set-ItemProperty -Path $regPath -Name 'NodeType' -Value 2 -Type DWord -ErrorAction SilentlyContinue
        
        Write-Log "[OK] NetBIOS over TCP/IP disabled"
        
    } catch {
        Write-Log "Error disabling NetBIOS: $($_.Exception.Message)" -Level WARN
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
        Write-Log "[OK] LLMNR disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling LLMNR: $($_.Exception.Message)" -Level WARN
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
        
        Write-Log "[OK] WPAD disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling WPAD: $($_.Exception.Message)" -Level WARN
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
        Write-Log "[OK] Configured to prefer IPv4 over IPv6"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error configuring IPv6: $($_.Exception.Message)" -Level WARN
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
        Write-Log "[OK] mDNS disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling mDNS: $($_.Exception.Message)" -Level WARN
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
                Write-Log "  [OK] Disabled service: $svcName"
                $script:ProtocolsDisabled++
            }
        }
        
    } catch {
        Write-Log "Error disabling Windows Connect Now: $($_.Exception.Message)" -Level WARN
    }
    
    # Disable SSDP Discovery (UPnP)
    Write-Log ""
    Write-Log "Disabling SSDP Discovery (UPnP)..."
    try {
        $svc = Get-Service -Name 'SSDPSRV' -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name 'SSDPSRV' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'SSDPSRV' -StartupType Disabled
            Write-Log "[OK] SSDP Discovery disabled"
            $script:ProtocolsDisabled++
        }
        
    } catch {
        Write-Log "Error disabling SSDP: $($_.Exception.Message)" -Level WARN
    }
    
    # Disable Remote Registry
    Write-Log ""
    Write-Log "Disabling Remote Registry..."
    try {
        $svc = Get-Service -Name 'RemoteRegistry' -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name 'RemoteRegistry' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'RemoteRegistry' -StartupType Disabled
            Write-Log "[OK] Remote Registry disabled"
            $script:ProtocolsDisabled++
        }
        
    } catch {
        Write-Log "Error disabling Remote Registry: $($_.Exception.Message)" -Level WARN
    }
    
    # Disable LMHOSTS lookup
    Write-Log ""
    Write-Log "Disabling LMHOSTS lookup..."
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
        Set-ItemProperty -Path $regPath -Name 'EnableLMHOSTS' -Value 0 -Type DWord
        Write-Log "[OK] LMHOSTS lookup disabled"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error disabling LMHOSTS: $($_.Exception.Message)" -Level WARN
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
        
        Write-Log "[OK] DNS configuration hardened"
        $script:ProtocolsDisabled++
        
    } catch {
        Write-Log "Error hardening DNS: $($_.Exception.Message)" -Level WARN
    }
    
    # Flush DNS cache
    Write-Log ""
    Write-Log "Flushing DNS cache..."
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-Log "[OK] DNS cache flushed"
        
    } catch {
        Write-Log "Error flushing DNS cache: $($_.Exception.Message)" -Level WARN
    }
    
    # Flush NetBIOS cache
    Write-Log "Flushing NetBIOS cache..."
    try {
        nbtstat -R | Out-Null
        nbtstat -RR | Out-Null
        Write-Log "[OK] NetBIOS cache flushed"
        
    } catch {
        Write-Log "Error flushing NetBIOS cache: $($_.Exception.Message)" -Level WARN
    }
    
    # Summary
    $duration = ((Get-Date) - $startTime).TotalSeconds

    Write-Log "NetBIOS over TCP/IP: Disabled"
    Write-Log "LLMNR: Disabled"
    Write-Log "WPAD: Disabled"
    Write-Log "mDNS: Disabled"
    Write-Log "IPv6: Prefer IPv4"
    Write-Log "SSDP/UPnP: Disabled"
    Write-Log "Remote Registry: Disabled"
    Write-Log "IMPORTANT: A system restart is recommended for all changes to take effect" -Level WARN
    Write-Log "===== Disable_Unused_Protocols complete in $([int]$duration)s; disabled=$($script:ProtocolsDisabled) ====="

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit 0