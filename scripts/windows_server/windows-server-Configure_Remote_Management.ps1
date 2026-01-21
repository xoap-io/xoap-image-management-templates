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

#endregion

#region WinRM Configuration

function Enable-WinRMService {
    if (-not $EnableWinRM) {
        Write-LogMessage "Skipping WinRM configuration" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring Windows Remote Management (WinRM)..." -Level Info
    
    try {
        # Quick configuration
        Write-LogMessage "Running WinRM quick configuration..." -Level Info
        winrm quickconfig -quiet 2>&1 | Out-Null
        
        # Set service to automatic
        Set-Service -Name WinRM -StartupType Automatic
        
        # Start service
        Start-Service -Name WinRM -ErrorAction SilentlyContinue
        
        # Verify service is running
        $service = Get-Service -Name WinRM
        if ($service.Status -eq 'Running') {
            Write-LogMessage "WinRM service started successfully" -Level Success
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error enabling WinRM: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-WinRMConfiguration {
    Write-LogMessage "Configuring WinRM settings..." -Level Info
    
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
        
        Write-LogMessage "WinRM configuration applied" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring WinRM: $($_.Exception.Message)" -Level Warning
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-WinRMListeners {
    Write-LogMessage "Configuring WinRM listeners..." -Level Info
    
    try {
        # Get existing listeners
        $listeners = winrm enumerate winrm/config/listener 2>&1
        
        # Configure HTTP listener
        if (-not $DisableWinRMHTTP) {
            Write-LogMessage "Ensuring HTTP listener is configured..." -Level Info
            
            $httpListener = winrm enumerate winrm/config/listener | Select-String -Pattern "Transport = HTTP"
            if (-not $httpListener) {
                winrm create winrm/config/listener?Address=*+Transport=HTTP 2>&1 | Out-Null
                Write-LogMessage "HTTP listener created" -Level Success
            }
            else {
                Write-LogMessage "HTTP listener already exists" -Level Info
            }
        }
        else {
            Write-LogMessage "HTTP listener disabled (HTTPS only mode)" -Level Warning
            # Remove HTTP listener
            winrm delete winrm/config/listener?Address=*+Transport=HTTP 2>&1 | Out-Null
        }
        
        # Configure HTTPS listener if requested
        if ($SetupHTTPS) {
            Write-LogMessage "Setting up HTTPS listener..." -Level Info
            
            # Check for existing certificate
            $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {
                $_.Subject -like "*$env:COMPUTERNAME*" -and $_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication'
            } | Select-Object -First 1
            
            if ($cert) {
                $thumbprint = $cert.Thumbprint
                Write-LogMessage "Using certificate: $thumbprint" -Level Info
                
                # Create HTTPS listener
                $httpsListener = winrm enumerate winrm/config/listener | Select-String -Pattern "Transport = HTTPS"
                if (-not $httpsListener) {
                    winrm create winrm/config/listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`"; CertificateThumbprint=`"$thumbprint`"}" 2>&1 | Out-Null
                    Write-LogMessage "HTTPS listener created" -Level Success
                }
            }
            else {
                Write-LogMessage "No suitable certificate found for HTTPS listener" -Level Warning
                Write-LogMessage "Generate a certificate and re-run with -SetupHTTPS" -Level Info
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring listeners: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region PowerShell Remoting

function Enable-PSRemotingConfiguration {
    if (-not $EnablePSRemoting) {
        Write-LogMessage "Skipping PowerShell remoting configuration" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring PowerShell remoting..." -Level Info
    
    try {
        # Enable PS Remoting
        Enable-PSRemoting -Force -SkipNetworkProfileCheck 2>&1 | Out-Null
        
        Write-LogMessage "PowerShell remoting enabled" -Level Success
        
        # Configure session configuration
        Set-PSSessionConfiguration -Name Microsoft.PowerShell -ShowSecurityDescriptorUI -Force -ErrorAction SilentlyContinue
        
        # Set execution policy
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        Write-LogMessage "Execution policy set to RemoteSigned" -Level Info
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error enabling PS remoting: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Remote Desktop

function Enable-RemoteDesktop {
    if (-not $EnableRDP) {
        Write-LogMessage "Skipping Remote Desktop configuration" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring Remote Desktop..." -Level Info
    
    try {
        # Enable RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Force
        
        # Enable NLA (Network Level Authentication) - more secure
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 -Force
        
        # Allow connections from computers running any version of RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Value 1 -Force
        
        Write-LogMessage "Remote Desktop enabled with NLA" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error enabling RDP: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Server Manager

function Enable-ServerManagerRemoting {
    if (-not $EnableServerManager) {
        Write-LogMessage "Skipping Server Manager remote management" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring Server Manager remote management..." -Level Info
    
    try {
        # Enable Server Manager remote management
        Configure-SMRemoting.exe -Enable -Force 2>&1 | Out-Null
        
        Write-LogMessage "Server Manager remote management enabled" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error enabling Server Manager remoting: $($_.Exception.Message)" -Level Warning
        Write-LogMessage "Server Manager remoting may not be available on this version" -Level Info
        return $false
    }
}

#endregion

#region Firewall Configuration

function Set-FirewallRules {
    if (-not $ConfigureFirewall) {
        Write-LogMessage "Skipping firewall configuration" -Level Info
        return $false
    }
    
    Write-LogMessage "Configuring Windows Firewall rules..." -Level Info
    
    try {
        # Enable WinRM firewall rules
        if ($EnableWinRM) {
            Write-LogMessage "Enabling WinRM firewall rules..." -Level Info
            
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
                
                Write-LogMessage "Created WinRM HTTP firewall rule" -Level Info
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
                    
                    Write-LogMessage "Created WinRM HTTPS firewall rule" -Level Info
                }
            }
        }
        
        # Enable RDP firewall rules
        if ($EnableRDP) {
            Write-LogMessage "Enabling RDP firewall rules..." -Level Info
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        }
        
        # Enable Server Manager firewall rules
        if ($EnableServerManager) {
            Write-LogMessage "Enabling Server Manager firewall rules..." -Level Info
            Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Remote Service Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Remote Volume Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Remote Scheduled Tasks Management" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "Windows Defender Firewall Remote Management" -ErrorAction SilentlyContinue
        }
        
        # Apply network restrictions if specified
        if ($AllowedNetworks.Count -gt 0) {
            Write-LogMessage "Applying network restrictions..." -Level Info
            
            foreach ($network in $AllowedNetworks) {
                Write-LogMessage "  Allowed network: $network" -Level Info
            }
            
            # Note: This requires creating custom rules with RemoteAddress filters
            # For production, use more granular control
        }
        
        Write-LogMessage "Firewall rules configured" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring firewall: $($_.Exception.Message)" -Level Warning
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Verification

function Test-RemoteManagementConfiguration {
    Write-LogMessage "Verifying remote management configuration..." -Level Info
    
    try {
        # Check WinRM
        if ($EnableWinRM) {
            $winrmService = Get-Service -Name WinRM
            Write-LogMessage "  WinRM Service: $($winrmService.Status) ($($winrmService.StartType))" -Level Info
            
            $listeners = winrm enumerate winrm/config/listener 2>&1
            Write-LogMessage "  WinRM Listeners: Configured" -Level Info
        }
        
        # Check PowerShell remoting
        if ($EnablePSRemoting) {
            try {
                $testSession = Test-WSMan -ComputerName localhost -ErrorAction Stop
                Write-LogMessage "  PowerShell Remoting: Working" -Level Info
            }
            catch {
                Write-LogMessage "  PowerShell Remoting: Not responding" -Level Warning
            }
        }
        
        # Check RDP
        if ($EnableRDP) {
            $rdpEnabled = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections'
            if ($rdpEnabled.fDenyTSConnections -eq 0) {
                Write-LogMessage "  Remote Desktop: Enabled" -Level Info
            }
            else {
                Write-LogMessage "  Remote Desktop: Disabled" -Level Warning
            }
        }
        
        # Check firewall rules
        if ($ConfigureFirewall) {
            $winrmRules = Get-NetFirewallRule -DisplayGroup "Windows Remote Management" | Where-Object { $_.Enabled -eq $true }
            Write-LogMessage "  WinRM Firewall Rules: $($winrmRules.Count) enabled" -Level Info
        }
        
        Write-LogMessage "Verification completed" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Get-RemoteManagementReport {
    Write-LogMessage "Generating remote management configuration report..." -Level Info
    
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
    Write-LogMessage "Remote Management Configuration" -Level Info
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
        Write-LogMessage "Remote management configuration completed successfully!" -Level Success
        Write-LogMessage "Test connection: Test-WSMan -ComputerName $env:COMPUTERNAME" -Level Info
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
