<#
.SYNOPSIS
    Configure Windows Firewall with Advanced Security

.DESCRIPTION
    Configures Windows Firewall with security best practices including predefined rules,
    port blocking, logging, and custom rules for common services.

.NOTES
    File Name      : windows-server-configure_Windows_Firewall.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-configure_Windows_Firewall.ps1
    Configures Windows Firewall with defaults
    
.EXAMPLE
    .\windows-server-configure_Windows_Firewall.ps1 -EnableRDP -EnableWinRM
    Configures firewall and enables RDP and WinRM rules
#>

[CmdletBinding()]
param(
    [switch]$EnableRDP,
    [switch]$EnableWinRM,
    [switch]$EnableSMB,
    [switch]$EnableICMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:RulesConfigured = 0
$script:RulesEnabled = 0
$script:RulesDisabled = 0

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
    $logMessage = "[$timestamp] [$prefix] [Firewall] $Message"
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
    Write-Log "Windows Firewall Configuration Script"
    Write-Log "==================================================="
    Write-Log "Enable RDP: $EnableRDP"
    Write-Log "Enable WinRM: $EnableWinRM"
    Write-Log "Enable SMB: $EnableSMB"
    Write-Log "Enable ICMP: $EnableICMP"
    Write-Log ""
    
    # Enable Windows Firewall on all profiles
    Write-Log "Enabling Windows Firewall on all profiles..."
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    Write-Log "✓ Windows Firewall enabled on all profiles"
    $script:RulesConfigured++
    
    # Configure default actions
    Write-Log "Configuring default firewall actions..."
    Set-NetFirewallProfile -Profile Domain -DefaultInboundAction Block -DefaultOutboundAction Allow
    Set-NetFirewallProfile -Profile Public -DefaultInboundAction Block -DefaultOutboundAction Allow
    Set-NetFirewallProfile -Profile Private -DefaultInboundAction Block -DefaultOutboundAction Allow
    Write-Log "✓ Default actions configured (Block Inbound, Allow Outbound)"
    $script:RulesConfigured++
    
    # Enable firewall logging
    Write-Log "Enabling firewall logging..."
    $logPath = "$env:SystemRoot\System32\LogFiles\Firewall"
    if (-not (Test-Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -Force | Out-Null
    }
    
    Set-NetFirewallProfile -Profile Domain,Public,Private `
        -LogFileName "$logPath\pfirewall.log" `
        -LogMaxSizeKilobytes 4096 `
        -LogBlocked True `
        -LogAllowed False
    
    Write-Log "✓ Firewall logging enabled: $logPath\pfirewall.log"
    $script:RulesConfigured++
    
    # Disable all unnecessary predefined rules
    Write-Log "Disabling unnecessary predefined rules..."
    $unnecessaryRules = @(
        'RemoteDesktop*',
        'RemoteEventLogSvc*',
        'RemoteService*',
        'RemoteTask*',
        'RemoteVolume*',
        'WMI-*'
    )
    
    foreach ($ruleName in $unnecessaryRules) {
        $rules = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        foreach ($rule in $rules) {
            if ($rule.Enabled -eq 'True') {
                Disable-NetFirewallRule -Name $rule.Name
                Write-Log "  Disabled: $($rule.DisplayName)"
                $script:RulesDisabled++
            }
        }
    }
    
    # Enable RDP if requested
    if ($EnableRDP) {
        Write-Log "Enabling Remote Desktop rules..."
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        Write-Log "✓ Remote Desktop firewall rules enabled"
        $script:RulesEnabled++
    }
    
    # Enable WinRM if requested
    if ($EnableWinRM) {
        Write-Log "Enabling Windows Remote Management rules..."
        Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"
        Write-Log "✓ WinRM firewall rules enabled"
        $script:RulesEnabled++
    }
    
    # Enable SMB if requested
    if ($EnableSMB) {
        Write-Log "Enabling File and Printer Sharing rules..."
        Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
        Write-Log "✓ SMB firewall rules enabled"
        $script:RulesEnabled++
    }
    
    # Enable ICMP if requested
    if ($EnableICMP) {
        Write-Log "Enabling ICMP (ping) rules..."
        Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
        Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv6-In)"
        Write-Log "✓ ICMP firewall rules enabled"
        $script:RulesEnabled++
    }
    
    # Create custom security rules
    Write-Log "Creating custom security rules..."
    
    # Block common attack ports
    $blockPorts = @(
        @{Port=135; Protocol='TCP'; Description='Block RPC'},
        @{Port=137; Protocol='UDP'; Description='Block NetBIOS Name Service'},
        @{Port=138; Protocol='UDP'; Description='Block NetBIOS Datagram'},
        @{Port=139; Protocol='TCP'; Description='Block NetBIOS Session'},
        @{Port=445; Protocol='TCP'; Description='Block SMB (if not explicitly enabled)'},
        @{Port=1433; Protocol='TCP'; Description='Block SQL Server'},
        @{Port=1434; Protocol='UDP'; Description='Block SQL Browser'},
        @{Port=3389; Protocol='TCP'; Description='Block RDP (if not explicitly enabled)'}
    )
    
    foreach ($portRule in $blockPorts) {
        $ruleName = "XOAP-Block-$($portRule.Protocol)-$($portRule.Port)"
        
        # Skip if we explicitly enabled the service
        if (($portRule.Port -eq 3389 -and $EnableRDP) -or 
            ($portRule.Port -eq 445 -and $EnableSMB)) {
            Write-Log "  Skipping block rule for port $($portRule.Port) (service enabled)"
            continue
        }
        
        $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if (-not $existingRule) {
            New-NetFirewallRule -Name $ruleName `
                -DisplayName $portRule.Description `
                -Direction Inbound `
                -Action Block `
                -Protocol $portRule.Protocol `
                -LocalPort $portRule.Port `
                -Profile Any `
                -ErrorAction SilentlyContinue | Out-Null
            
            Write-Log "  Created: $($portRule.Description)"
            $script:RulesConfigured++
        }
    }
    
    # Allow essential outbound traffic
    Write-Log "Configuring essential outbound rules..."
    $outboundRules = @(
        @{Port=53; Protocol='UDP'; Description='Allow DNS'},
        @{Port=80; Protocol='TCP'; Description='Allow HTTP'},
        @{Port=443; Protocol='TCP'; Description='Allow HTTPS'},
        @{Port=123; Protocol='UDP'; Description='Allow NTP'}
    )
    
    foreach ($portRule in $outboundRules) {
        $ruleName = "XOAP-Allow-Out-$($portRule.Protocol)-$($portRule.Port)"
        
        $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if (-not $existingRule) {
            New-NetFirewallRule -Name $ruleName `
                -DisplayName $portRule.Description `
                -Direction Outbound `
                -Action Allow `
                -Protocol $portRule.Protocol `
                -RemotePort $portRule.Port `
                -Profile Any `
                -ErrorAction SilentlyContinue | Out-Null
            
            Write-Log "  Created: $($portRule.Description)"
            $script:RulesConfigured++
        }
    }
    
    # Enable Windows Firewall with Advanced Security service
    Write-Log "Ensuring Windows Firewall service is running..."
    $firewallService = Get-Service -Name 'mpssvc'
    if ($firewallService.Status -ne 'Running') {
        Start-Service -Name 'mpssvc'
        Write-Log "✓ Windows Firewall service started"
    }
    Set-Service -Name 'mpssvc' -StartupType Automatic
    Write-Log "✓ Windows Firewall service set to automatic"
    
    # Display current profile status
    Write-Log ""
    Write-Log "Current firewall profile status:"
    $profiles = Get-NetFirewallProfile
    foreach ($profile in $profiles) {
        Write-Log "  $($profile.Name):"
        Write-Log "    Enabled: $($profile.Enabled)"
        Write-Log "    Default Inbound: $($profile.DefaultInboundAction)"
        Write-Log "    Default Outbound: $($profile.DefaultOutboundAction)"
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "Windows Firewall Configuration Summary"
    Write-Log "==================================================="
    Write-Log "Rules configured: $script:RulesConfigured"
    Write-Log "Rules enabled: $script:RulesEnabled"
    Write-Log "Rules disabled: $script:RulesDisabled"
    Write-Log "Firewall profiles: All enabled"
    Write-Log "Logging: Enabled ($logPath\pfirewall.log)"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "Windows Firewall configuration completed!"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}