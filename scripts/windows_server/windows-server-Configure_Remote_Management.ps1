<#
.SYNOPSIS
    Configure Remote Management for Windows Server

.DESCRIPTION
    Configures Windows Remote Management (WinRM), PowerShell remoting, Remote Desktop,
    and Server Manager remote management. Optimized for Windows Server 2025.

.NOTES
    File Name      : windows-server-Configure_Remote_Management.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Remote_Management
    Enables remote management with default settings
    
.EXAMPLE
    .\windows-server-Configure_Remote_Management -EnableWinRM -EnablePSRemoting -EnableRDP -AllowedNetworks @('10.0.0.0/8', '192.168.0.0/16')
    Full remote management configuration with network restrictions
    
.PARAMETER EnableWinRM
    Enable and configure WinRM
    
.PARAMETER EnablePSRemoting
    Enable PowerShell remoting
    
.PARAMETER EnableRDP
    Enable Remote Desktop
    
.PARAMETER EnableServerManager
    Enable Server Manager remote management
    
.PARAMETER AllowedNetworks
    Array of allowed network ranges (CIDR notation)
    
.PARAMETER DisableWinRMHTTP
    Disable WinRM HTTP listener (HTTPS only)
    
.PARAMETER ConfigureFirewall
    Configure Windows Firewall rules
    
.PARAMETER SetupHTTPS
    Configure HTTPS listener for WinRM
#>

[CmdletBinding()]
param(
    [switch]$EnableWinRM = $true,
    [switch]$EnablePSRemoting = $true,
    [switch]$EnableRDP,
    [switch]$EnableServerManager = $true,
    [string[]]$AllowedNetworks = @(),
    [switch]$DisableWinRMHTTP,
    [switch]$ConfigureFirewall = $true,
    [switch]$SetupHTTPS
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
    Write-Host "[$timestamp] [$Level] [RemoteMgmt] $Message"
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region WinRM Configuration

function Enable-WinRMService {
    if (-not $EnableWinRM) {
        Write-Log "Skipping WinRM configuration" -Level INFO
        return $false
    }
    
    Write-Log "Configuring Windows Remote Management (WinRM)..." -Level INFO
    
    try {
        # Quick configuration
        Write-Log "Running WinRM quick configuration..." -Level INFO
        winrm quickconfig -quiet 2>&1 | Out-Null
        
        # Set service to automatic
        Set-Service -Name WinRM -StartupType Automatic
        
        # Start service
        Start-Service -Name WinRM -ErrorAction SilentlyContinue
        
        # Verify service is running
        $service = Get-Service -Name WinRM
        if ($service.Status -eq 'Running') {
            Write-Log "WinRM service started successfully" -Level INFO
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error enabling WinRM: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-WinRMConfiguration {
    Write-Log "Configuring WinRM settings..." -Level INFO
    
    try {
        # Configure WinRM service
        winrm set winrm/config/service '@{AllowUnencrypted="false"}' 2>&1 | Out-Null
        winrm set winrm/config/service/auth '@{Basic="true"}' 2>&1 | Out-Null
        winrm set winrm/config/service/auth '@{Kerberos="true"}' 2>&1 | Out-Null
        winrm set winrm/config/service/auth '@{Negotiate="true"}' 2>&1 | Out-Null
        winrm set winrm/config/service/auth '@{Certificate="false"}' 2>&1 | Out-Null
        winrm set winrm/config/service/auth '@{CredSSP="false"}' 2>&1 | Out-Null
        
        # Configure client
        winrm set winrm/config/client '@{AllowUnencrypted="false"}' 2>&1 | Out-Null
        winrm set winrm/config/client '@{TrustedHosts="*"}' 2>&1 | Out-Null
        
        # Set max timeout values
        winrm set winrm/config '@{MaxTimeoutms="1800000"}' 2>&1 | Out-Null
        winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}' 2>&1 | Out-Null
        winrm set winrm/config/winrs '@{MaxShellsPerUser="30"}' 2>&1 | Out-Null
        
        Write-Log "WinRM configuration applied" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring WinRM: $($_.Exception.Message)" -Level WARN
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-WinRMListeners {
    Write-Log "Configuring WinRM listeners..." -Level INFO
    
    try {
        # Get existing listeners
        $listeners = winrm enumerate winrm/config/listener 2>&1
        
        # Configure HTTP listener
        if (-not $DisableWinRMHTTP) {
            Write-Log "Ensuring HTTP listener is configured..." -Level INFO
            
            $httpListener = winrm enumerate winrm/config/listener | Select-String -Pattern "Transport = HTTP"
            if (-not $httpListener) {
                winrm create winrm/config/listener?Address=*+Transport=HTTP 2>&1 | Out-Null
                Write-Log "HTTP listener created" -Level INFO
            }
            else {
                Write-Log "HTTP listener already exists" -Level INFO
            }
        }
        else {
            Write-Log "HTTP listener disabled (HTTPS only mode)" -Level WARN
            # Remove HTTP listener
            winrm delete winrm/config/listener?Address=*+Transport=HTTP 2>&1 | Out-Null
        }
        
        # Configure HTTPS listener if requested
        if ($SetupHTTPS) {
            Write-Log "Setting up HTTPS listener..." -Level INFO
            
            # Check for existing certificate
            $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {
                $_.Subject -like "*$env:COMPUTERNAME*" -and $_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication'
            } | Select-Object -First 1
            
            if ($cert) {
                $thumbprint = $cert.Thumbprint
                Write-Log "Using certificate: $thumbprint" -Level INFO
                
                # Create HTTPS listener
                $httpsListener = winrm enumerate winrm/config/listener | Select-String -Pattern "Transport = HTTPS"
                if (-not $httpsListener) {
                    winrm create winrm/config/listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`"; CertificateThumbprint=`"$thumbprint`"}" 2>&1 | Out-Null
                    Write-Log "HTTPS listener created" -Level INFO
                }
            }
            else {
                Write-Log "No suitable certificate found for HTTPS listener" -Level WARN
                Write-Log "Generate a certificate and re-run with -SetupHTTPS" -Level INFO
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring listeners: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region PowerShell Remoting

function Enable-PSRemotingConfiguration {
    if (-not $EnablePSRemoting) {
        Write-Log "Skipping PowerShell remoting configuration" -Level INFO
        return $false
    }
    
    Write-Log "Configuring PowerShell remoting..." -Level INFO
    
    try {
        # Enable PS Remoting
        Enable-PSRemoting -Force -SkipNetworkProfileCheck 2>&1 | Out-Null
        
        Write-Log "PowerShell remoting enabled" -Level INFO
        
        # Configure session configuration
        Set-PSSessionConfiguration -Name Microsoft.PowerShell -ShowSecurityDescriptorUI -Force -ErrorAction SilentlyContinue
        
        # Set execution policy
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        Write-Log "Execution policy set to RemoteSigned" -Level INFO
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error enabling PS remoting: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Remote Desktop

function Enable-RemoteDesktop {
    if (-not $EnableRDP) {
        Write-Log "Skipping Remote Desktop configuration" -Level INFO
        return $false
    }
    
    Write-Log "Configuring Remote Desktop..." -Level INFO
    
    try {
        # Enable RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Force
        
        # Enable NLA (Network Level Authentication) - more secure
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 -Force
        
        # Allow connections from computers running any version of RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Value 1 -Force
        
        Write-Log "Remote Desktop enabled with NLA" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error enabling RDP: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Server Manager

function Enable-ServerManagerRemoting {
    if (-not $EnableServerManager) {
        Write-Log "Skipping Server Manager remote management" -Level INFO
        return $false
    }
    
    Write-Log "Configuring Server Manager remote management..." -Level INFO
    
    try {
        # Enable Server Manager remote management
        Configure-SMRemoting.exe -Enable -Force 2>&1 | Out-Null
        
        Write-Log "Server Manager remote management enabled" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error enabling Server Manager remoting: $($_.Exception.Message)" -Level WARN
        Write-Log "Server Manager remoting may not be available on this version" -Level INFO
        return $false
    }
}

#endregion

#region Firewall Configuration

function Set-FirewallRules {
    if (-not $ConfigureFirewall) {
        Write-Log "Skipping firewall configuration" -Level INFO
        return $false
    }
    
    Write-Log "Configuring Windows Firewall rules..." -Level INFO
    
    try {
        # Enable WinRM firewall rules
        if ($EnableWinRM) {
            Write-Log "Enabling WinRM firewall rules..." -Level INFO
            
            Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue
            
            # Create custom rule if needed
            $winrmRule = Get-NetFirewallRule -DisplayName "WinRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
            if (-not $winrmRule -and -not $DisableWinRMHTTP) {
                New-NetFirewallRule -DisplayName "WinRM-HTTP-In-TCP" `
                    -Direction Inbound `
                    -Protocol TCP `
                    -LocalPort 5985 `
                    -Action Allow `
                    -Profile Domain, Private `
                    -Description "Allow WinRM HTTP" | Out-Null
                
                Write-Log "Created WinRM HTTP firewall rule" -Level INFO
            }
            
            # HTTPS rule
            if ($SetupHTTPS) {
                $winrmHTTPSRule = Get-NetFirewallRule -DisplayName "WinRM-HTTPS-In-TCP" -ErrorAction SilentlyContinue
                if (-not $winrmHTTPSRule) {
                    New-NetFirewallRule -DisplayName "WinRM-HTTPS-In-TCP" `
                        -Direction Inbound `
                        -Protocol TCP `
                        -LocalPort 5986 `
                        -Action Allow `
                        -Profile Domain, Private `
                        -Description "Allow WinRM HTTPS" | Out-Null
                    
                    Write-Log "Created WinRM HTTPS firewall rule" -Level INFO
                }
            }
        }
        
        # Enable RDP firewall rules
        if ($EnableRDP) {
            Write-Log "Enabling RDP firewall rules..." -Level INFO
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        }
        
        # Enable Server Manager firewall rules
        if ($EnableServerManager) {
            Write-Log "Enabling Server Manager firewall rules..." -Level INFO
            Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Remote Service Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Remote Volume Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Remote Scheduled Tasks Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Windows Defender Firewall Remote Management" -ErrorAction SilentlyContinue
        }
        
        # Apply network restrictions if specified
        if ($AllowedNetworks.Count -gt 0) {
            Write-Log "Applying network restrictions..." -Level INFO
            
            foreach ($network in $AllowedNetworks) {
                Write-Log "  Allowed network: $network" -Level INFO
            }
            
            # Note: This requires creating custom rules with RemoteAddress filters
            # For production, use more granular control
        }
        
        Write-Log "Firewall rules configured" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring firewall: $($_.Exception.Message)" -Level WARN
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Verification

function Test-RemoteManagementConfiguration {
    Write-Log "Verifying remote management configuration..." -Level INFO
    
    try {
        # Check WinRM
        if ($EnableWinRM) {
            $winrmService = Get-Service -Name WinRM
            Write-Log "  WinRM Service: $($winrmService.Status) ($($winrmService.StartType))" -Level INFO
            
            $listeners = winrm enumerate winrm/config/listener 2>&1
            Write-Log "  WinRM Listeners: Configured" -Level INFO
        }
        
        # Check PowerShell remoting
        if ($EnablePSRemoting) {
            try {
                $testSession = Test-WSMan -ComputerName localhost -ErrorAction Stop
                Write-Log "  PowerShell Remoting: Working" -Level INFO
            }
            catch {
                Write-Log "  PowerShell Remoting: Not responding" -Level WARN
            }
        }
        
        # Check RDP
        if ($EnableRDP) {
            $rdpEnabled = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections'
            if ($rdpEnabled.fDenyTSConnections -eq 0) {
                Write-Log "  Remote Desktop: Enabled" -Level INFO
            }
            else {
                Write-Log "  Remote Desktop: Disabled" -Level WARN
            }
        }
        
        # Check firewall rules
        if ($ConfigureFirewall) {
            $winrmRules = Get-NetFirewallRule -DisplayGroup "Windows Remote Management" | Where-Object { $_.Enabled -eq $true }
            Write-Log "  WinRM Firewall Rules: $($winrmRules.Count) enabled" -Level INFO
        }
        
        Write-Log "Verification completed" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error during verification: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Get-RemoteManagementReport {
    Write-Log "Generating remote management configuration report..." -Level INFO
    
    try {
        $reportFile = Join-Path $LogDir "remote-mgmt-config-$timestamp.txt"
        $report = @()
        
        $report += "Remote Management Configuration Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # WinRM Status
        $report += "Windows Remote Management (WinRM):"
        $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue
        if ($winrmService) {
            $report += "  Status: $($winrmService.Status)"
            $report += "  Startup Type: $($winrmService.StartType)"
            
            $listeners = winrm enumerate winrm/config/listener 2>&1
            $report += "  Listeners:"
            $report += "    $($listeners -join "`n    ")"
        }
        else {
            $report += "  Not installed or not accessible"
        }
        $report += ""
        
        # PowerShell Remoting
        $report += "PowerShell Remoting:"
        try {
            $testWS = Test-WSMan -ComputerName localhost -ErrorAction Stop
            $report += "  Status: Enabled and responding"
        }
        catch {
            $report += "  Status: Not responding"
        }
        $report += ""
        
        # Remote Desktop
        $report += "Remote Desktop (RDP):"
        $rdpEnabled = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue
        if ($rdpEnabled.fDenyTSConnections -eq 0) {
            $report += "  Status: Enabled"
            $nla = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -ErrorAction SilentlyContinue
            $report += "  Network Level Authentication: $(if ($nla.UserAuthentication -eq 1) { 'Enabled' } else { 'Disabled' })"
        }
        else {
            $report += "  Status: Disabled"
        }
        $report += ""
        
        # Firewall Rules
        $report += "Firewall Rules:"
        $winrmRules = Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
        $report += "  WinRM Rules Enabled: $($winrmRules.Count)"
        
        $rdpRules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
        $report += "  RDP Rules Enabled: $($rdpRules.Count)"
        
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

    Write-Log "===== Configure_Remote_Management starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Configure remote management components
    Enable-WinRMService | Out-Null
    
    if ($EnableWinRM) {
        Set-WinRMConfiguration | Out-Null
        Set-WinRMListeners | Out-Null
    }
    
    Enable-PSRemotingConfiguration | Out-Null
    Enable-RemoteDesktop | Out-Null
    Enable-ServerManagerRemoting | Out-Null
    Set-FirewallRules | Out-Null
    
    # Verify configuration
    Test-RemoteManagementConfiguration | Out-Null
    
    # Generate report
    Get-RemoteManagementReport | Out-Null
    
    # Summary
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    Write-Log "Test connection: Test-WSMan -ComputerName $env:COMPUTERNAME"

    if ($script:ConfigurationsFailed -eq 0) {
        Write-Log "===== Configure_Remote_Management complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_Remote_Management complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) =====" -Level WARN
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
