<#
.SYNOPSIS
    Configure Network Time Protocol (NTP) for Windows 10/11

.DESCRIPTION
    Configures Windows Time Service (W32Time) with NTP servers, synchronization settings,
    and monitoring. Optimized for Windows 10/11 domain and standalone environments.

.NOTES
    File Name      : windows11-Configure_NTP.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Configure_NTP.ps1
    Configures default NTP servers (pool.ntp.org)
    
.EXAMPLE
    .\windows11-Configure_NTP.ps1 -NTPServers @('time.windows.com', 'time.nist.gov') -TimeZone 'Eastern Standard Time'
    Configures custom NTP servers and sets timezone
    
.PARAMETER NTPServers
    Array of NTP server addresses (default: pool.ntp.org servers)
    
.PARAMETER TimeZone
    Time zone ID (e.g., 'Eastern Standard Time', 'UTC')
    
.PARAMETER SyncInterval
    Synchronization interval in seconds (default: 900 = 15 minutes)
    
.PARAMETER MaxPosPhaseCorrection
    Maximum positive time correction in seconds (default: 3600)
    
.PARAMETER MaxNegPhaseCorrection
    Maximum negative time correction in seconds (default: 3600)
    
.PARAMETER SetAsDomainTimeSource
    Configure as authoritative time source (for domain controllers)
    
.PARAMETER DisableVMICTimeProvider
    Disable Hyper-V time synchronization (recommended for NTP config)
#>

[CmdletBinding()]
param(
    [string[]]$NTPServers = @(
        '0.pool.ntp.org',
        '1.pool.ntp.org',
        '2.pool.ntp.org',
        '3.pool.ntp.org'
    ),
    [string]$TimeZone = "",
    [int]$SyncInterval = 900,
    [int]$MaxPosPhaseCorrection = 3600,
    [int]$MaxNegPhaseCorrection = 3600,
    [switch]$SetAsDomainTimeSource,
    [switch]$DisableVMICTimeProvider
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# W32Time registry paths
$W32TimeConfig = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config'
$W32TimeParameters = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
$W32TimeTimeProviders = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders'
$NtpClientPath = "$W32TimeTimeProviders\NtpClient"
$VMICTimeProviderPath = "$W32TimeTimeProviders\VMICTimeProvider"

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
    
    # Ensure log directory exists
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

function Test-IsDomainController {
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        return ($osInfo.ProductType -eq 2)  # 2 = Domain Controller
    }
    catch {
        return $false
    }
}

function Test-IsDomainMember {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        return ($computerSystem.PartOfDomain -eq $true)
    }
    catch {
        return $false
    }
}

function Stop-TimeService {
    Write-LogMessage "Stopping Windows Time service..." -Level Info
    
    try {
        $service = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Stop-Service -Name W32Time -Force
            Write-LogMessage "Windows Time service stopped" -Level Success
            return $true
        }
        return $true
    }
    catch {
        Write-LogMessage "Error stopping service: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Start-TimeService {
    Write-LogMessage "Starting Windows Time service..." -Level Info
    
    try {
        Set-Service -Name W32Time -StartupType Automatic
        Start-Service -Name W32Time
        
        Start-Sleep -Seconds 3
        
        $service = Get-Service -Name W32Time
        if ($service.Status -eq 'Running') {
            Write-LogMessage "Windows Time service started successfully" -Level Success
            return $true
        }
        else {
            Write-LogMessage "Service status: $($service.Status)" -Level Warning
            return $false
        }
    }
    catch {
        Write-LogMessage "Error starting service: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Set-TimeZoneConfiguration {
    if ([string]::IsNullOrWhiteSpace($TimeZone)) {
        Write-LogMessage "No timezone specified, skipping timezone configuration" -Level Info
        return $true
    }
    
    Write-LogMessage "Setting timezone to: $TimeZone" -Level Info
    
    try {
        # Get current timezone
        $currentTZ = Get-TimeZone
        Write-LogMessage "Current timezone: $($currentTZ.Id)" -Level Info
        
        if ($currentTZ.Id -eq $TimeZone) {
            Write-LogMessage "Timezone already set correctly" -Level Info
            return $true
        }
        
        # Validate timezone
        $validTZ = Get-TimeZone -Id $TimeZone -ErrorAction Stop
        
        # Set timezone
        Set-TimeZone -Id $TimeZone -ErrorAction Stop
        
        Write-LogMessage "Timezone configured successfully: $TimeZone" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error setting timezone: $($_.Exception.Message)" -Level Error
        Write-LogMessage "Use 'Get-TimeZone -ListAvailable' to see valid timezone IDs" -Level Info
        $script:ConfigurationsFailed++
        return $false
    }
}

function Disable-HyperVTimeSync {
    if (-not $DisableVMICTimeProvider) {
        Write-LogMessage "Hyper-V time sync not disabled (use -DisableVMICTimeProvider to disable)" -Level Info
        return $true
    }
    
    Write-LogMessage "Disabling Hyper-V time synchronization..." -Level Info
    
    try {
        # Check if running on Hyper-V
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($computerSystem.Model -notlike '*Virtual Machine*' -and 
            $computerSystem.Model -notlike '*Hyper-V*') {
            Write-LogMessage "Not running on Hyper-V, skipping VMIC time provider disable" -Level Info
            return $true
        }
        
        # Disable VMIC Time Provider
        if (Test-Path $VMICTimeProviderPath) {
            Set-ItemProperty -Path $VMICTimeProviderPath -Name "Enabled" -Value 0 -Type DWord
            Write-LogMessage "Hyper-V time synchronization disabled" -Level Success
            $script:ConfigurationsApplied++
        }
        
        # Disable time sync in Hyper-V Integration Services
        $timeSync = Get-VMIntegrationService -VMName $env:COMPUTERNAME -Name "Time Synchronization" -ErrorAction SilentlyContinue
        if ($timeSync) {
            Disable-VMIntegrationService -VMName $env:COMPUTERNAME -Name "Time Synchronization" -ErrorAction SilentlyContinue
            Write-LogMessage "Hyper-V Integration Services time sync disabled" -Level Success
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error disabling Hyper-V time sync: $($_.Exception.Message)" -Level Warning
        return $true  # Non-critical error
    }
}

function Set-NTPConfiguration {
    Write-LogMessage "Configuring NTP settings..." -Level Info
    
    try {
        Stop-TimeService | Out-Null
        
        # Configure NTP client
        Write-LogMessage "Configuring NTP client..." -Level Info
        
        # Set NTP servers
        $ntpServerString = ($NTPServers | ForEach-Object { "$_,0x9" }) -join ' '
        Set-ItemProperty -Path $W32TimeParameters -Name "NtpServer" -Value $ntpServerString
        Write-LogMessage "NTP servers configured: $($NTPServers -join ', ')" -Level Info
        
        # Set time source type (NTP)
        Set-ItemProperty -Path $W32TimeParameters -Name "Type" -Value "NTP"
        
        # Enable NTP client
        if (Test-Path $NtpClientPath) {
            Set-ItemProperty -Path $NtpClientPath -Name "Enabled" -Value 1 -Type DWord
            Set-ItemProperty -Path $NtpClientPath -Name "CrossSiteSyncFlags" -Value 2 -Type DWord
            Set-ItemProperty -Path $NtpClientPath -Name "ResolvePeerBackoffMinutes" -Value 15 -Type DWord
            Set-ItemProperty -Path $NtpClientPath -Name "ResolvePeerBackoffMaxTimes" -Value 7 -Type DWord
            Set-ItemProperty -Path $NtpClientPath -Name "SpecialPollInterval" -Value $SyncInterval -Type DWord
        }
        
        # Configure time correction limits
        if (Test-Path $W32TimeConfig) {
            Set-ItemProperty -Path $W32TimeConfig -Name "MaxPosPhaseCorrection" -Value $MaxPosPhaseCorrection -Type DWord
            Set-ItemProperty -Path $W32TimeConfig -Name "MaxNegPhaseCorrection" -Value $MaxNegPhaseCorrection -Type DWord
            Set-ItemProperty -Path $W32TimeConfig -Name "UpdateInterval" -Value $SyncInterval -Type DWord
            
            Write-LogMessage "Max positive correction: $MaxPosPhaseCorrection seconds" -Level Info
            Write-LogMessage "Max negative correction: $MaxNegPhaseCorrection seconds" -Level Info
            Write-LogMessage "Update interval: $SyncInterval seconds" -Level Info
        }
        
        # Configure as domain time source if requested
        if ($SetAsDomainTimeSource) {
            Write-LogMessage "Configuring as authoritative domain time source..." -Level Info
            
            if (Test-IsDomainController) {
                Set-ItemProperty -Path $W32TimeConfig -Name "AnnounceFlags" -Value 5 -Type DWord
                Set-ItemProperty -Path $W32TimeParameters -Name "Type" -Value "NTP"
                
                # Enable NTP server
                $ntpServerPath = "$W32TimeTimeProviders\NtpServer"
                if (Test-Path $ntpServerPath) {
                    Set-ItemProperty -Path $ntpServerPath -Name "Enabled" -Value 1 -Type DWord
                }
                
                Write-LogMessage "Configured as reliable time source for domain" -Level Success
            }
            else {
                Write-LogMessage "Not a domain controller - skipping domain time source configuration" -Level Warning
            }
        }
        
        Write-LogMessage "NTP configuration completed" -Level Success
        $script:ConfigurationsApplied++
        
        return $true
    }
    catch {
        Write-LogMessage "Error configuring NTP: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Sync-TimeNow {
    Write-LogMessage "Performing immediate time synchronization..." -Level Info
    
    try {
        # Register time service
        w32tm.exe /register 2>&1 | Out-Null
        
        # Start service if not running
        Start-TimeService | Out-Null
        
        # Force resync
        Write-LogMessage "Forcing time resynchronization..." -Level Info
        $result = w32tm.exe /resync /force 2>&1
        
        Start-Sleep -Seconds 3
        
        Write-LogMessage "Time synchronization initiated" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error during sync: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Test-NTPConfiguration {
    Write-LogMessage "Verifying NTP configuration..." -Level Info
    
    try {
        # Check service status
        $service = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($service) {
            Write-LogMessage "W32Time Service Status: $($service.Status)" -Level Info
            Write-LogMessage "W32Time Service Startup: $($service.StartType)" -Level Info
        }
        
        # Check current time source
        $timeSource = w32tm.exe /query /source 2>&1
        Write-LogMessage "Current time source: $timeSource" -Level Info
        
        # Check NTP status
        Write-LogMessage "Querying NTP status..." -Level Info
        $status = w32tm.exe /query /status 2>&1
        
        if ($status -match "Source:") {
            Write-LogMessage "NTP is functioning" -Level Success
        }
        
        # Get time configuration
        $config = w32tm.exe /query /configuration 2>&1
        
        # Check peers
        Write-LogMessage "Checking configured NTP peers..." -Level Info
        $peers = w32tm.exe /query /peers 2>&1
        
        return $true
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Get-NTPStatusReport {
    Write-LogMessage "Generating NTP status report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "ntp-config-$timestamp.txt"
        $report = @()
        
        $report += "NTP Configuration Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += ""
        
        # System information
        $report += "System Information:"
        $report += "  Computer Name: $env:COMPUTERNAME"
        $report += "  Domain Member: $(Test-IsDomainMember)"
        $report += "  Domain Controller: $(Test-IsDomainController)"
        $report += ""
        
        # Time zone
        $tz = Get-TimeZone
        $report += "Time Zone:"
        $report += "  ID: $($tz.Id)"
        $report += "  Display Name: $($tz.DisplayName)"
        $report += "  UTC Offset: $($tz.BaseUtcOffset)"
        $report += ""
        
        # NTP configuration
        $report += "NTP Configuration:"
        $report += "  Configured Servers:"
        foreach ($server in $NTPServers) {
            $report += "    - $server"
        }
        $report += "  Sync Interval: $SyncInterval seconds"
        $report += "  Max Positive Correction: $MaxPosPhaseCorrection seconds"
        $report += "  Max Negative Correction: $MaxNegPhaseCorrection seconds"
        $report += ""
        
        # Service status
        $service = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($service) {
            $report += "Service Status:"
            $report += "  Status: $($service.Status)"
            $report += "  Startup Type: $($service.StartType)"
            $report += ""
        }
        
        # Current time source
        $timeSource = w32tm.exe /query /source 2>&1
        $report += "Current Time Source:"
        $report += "  $timeSource"
        $report += ""
        
        # W32Time status
        $report += "W32Time Status:"
        $status = w32tm.exe /query /status 2>&1
        $report += $status
        $report += ""
        
        # Peer information
        $report += "NTP Peers:"
        $peers = w32tm.exe /query /peers 2>&1
        $report += $peers
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "NTP status report saved to: $reportFile" -Level Success
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
    Write-LogMessage "NTP Configuration for Windows 10/11" -Level Info
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
    
    # Check domain status
    if (Test-IsDomainMember -and -not $SetAsDomainTimeSource) {
        Write-LogMessage "WARNING: This is a domain member" -Level Warning
        Write-LogMessage "Domain members typically sync time from domain controllers" -Level Warning
        Write-LogMessage "Manual NTP configuration may conflict with domain policy" -Level Warning
    }
    
    # Set timezone if specified
    Set-TimeZoneConfiguration | Out-Null
    
    # Disable Hyper-V time sync if requested
    Disable-HyperVTimeSync | Out-Null
    
    # Configure NTP
    $configSuccess = Set-NTPConfiguration
    
    if (-not $configSuccess) {
        Write-LogMessage "NTP configuration failed" -Level Error
        exit 1
    }
    
    # Start service and sync
    Start-TimeService | Out-Null
    Sync-TimeNow | Out-Null
    
    # Verify configuration
    Test-NTPConfiguration | Out-Null
    
    # Generate status report
    Get-NTPStatusReport | Out-Null
    
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
    Write-LogMessage "" -Level Info
    
    # Display current time info
    $currentTime = Get-Date
    Write-LogMessage "Current System Time: $($currentTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    Write-LogMessage "Current UTC Time: $($currentTime.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    
    if ($script:ConfigurationsFailed -eq 0) {
        Write-LogMessage "NTP configuration completed successfully!" -Level Success
        Write-LogMessage "Monitor time sync with: w32tm /query /status" -Level Info
        exit 0
    }
    else {
        Write-LogMessage "Configuration completed with errors. Check logs." -Level Warning
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
