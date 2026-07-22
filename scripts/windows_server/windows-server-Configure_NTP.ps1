<#
.SYNOPSIS
    Configure Network Time Protocol (NTP) for Windows Server

.DESCRIPTION
    Configures Windows Time Service (W32Time) with NTP servers, synchronization settings,
    and monitoring. Optimized for Windows Server 2025 domain and standalone environments.

.NOTES
    File Name      : windows-server-Configure_NTP.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_NTP.ps1
    Configures default NTP servers (pool.ntp.org)
    
.EXAMPLE
    .\windows-server-Configure_NTP.ps1 -NTPServers @('time.windows.com', 'time.nist.gov') -TimeZone 'Eastern Standard Time'
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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [NTP] $Message"
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
    Write-Log "Stopping Windows Time service..." -Level INFO
    
    try {
        $service = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Stop-Service -Name W32Time -Force
            Write-Log "Windows Time service stopped" -Level INFO
            return $true
        }
        return $true
    }
    catch {
        Write-Log "Error stopping service: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Start-TimeService {
    Write-Log "Starting Windows Time service..." -Level INFO
    
    try {
        Set-Service -Name W32Time -StartupType Automatic
        Start-Service -Name W32Time
        
        Start-Sleep -Seconds 3
        
        $service = Get-Service -Name W32Time
        if ($service.Status -eq 'Running') {
            Write-Log "Windows Time service started successfully" -Level INFO
            return $true
        }
        else {
            Write-Log "Service status: $($service.Status)" -Level WARN
            return $false
        }
    }
    catch {
        Write-Log "Error starting service: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Set-TimeZoneConfiguration {
    if ([string]::IsNullOrWhiteSpace($TimeZone)) {
        Write-Log "No timezone specified, skipping timezone configuration" -Level INFO
        return $true
    }
    
    Write-Log "Setting timezone to: $TimeZone" -Level INFO
    
    try {
        # Get current timezone
        $currentTZ = Get-TimeZone
        Write-Log "Current timezone: $($currentTZ.Id)" -Level INFO
        
        if ($currentTZ.Id -eq $TimeZone) {
            Write-Log "Timezone already set correctly" -Level INFO
            return $true
        }
        
        # Validate timezone
        $validTZ = Get-TimeZone -Id $TimeZone -ErrorAction Stop
        
        # Set timezone
        Set-TimeZone -Id $TimeZone -ErrorAction Stop
        
        Write-Log "Timezone configured successfully: $TimeZone" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error setting timezone: $($_.Exception.Message)" -Level ERROR
        Write-Log "Use 'Get-TimeZone -ListAvailable' to see valid timezone IDs" -Level INFO
        $script:ConfigurationsFailed++
        return $false
    }
}

function Disable-HyperVTimeSync {
    if (-not $DisableVMICTimeProvider) {
        Write-Log "Hyper-V time sync not disabled (use -DisableVMICTimeProvider to disable)" -Level INFO
        return $true
    }
    
    Write-Log "Disabling Hyper-V time synchronization..." -Level INFO
    
    try {
        # Check if running on Hyper-V
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($computerSystem.Model -notlike '*Virtual Machine*' -and 
            $computerSystem.Model -notlike '*Hyper-V*') {
            Write-Log "Not running on Hyper-V, skipping VMIC time provider disable" -Level INFO
            return $true
        }
        
        # Disable VMIC Time Provider
        if (Test-Path $VMICTimeProviderPath) {
            Set-ItemProperty -Path $VMICTimeProviderPath -Name "Enabled" -Value 0 -Type DWord
            Write-Log "Hyper-V time synchronization disabled" -Level INFO
            $script:ConfigurationsApplied++
        }
        
        # Disable time sync in Hyper-V Integration Services
        $timeSync = Get-VMIntegrationService -VMName $env:COMPUTERNAME -Name "Time Synchronization" -ErrorAction SilentlyContinue
        if ($timeSync) {
            Disable-VMIntegrationService -VMName $env:COMPUTERNAME -Name "Time Synchronization" -ErrorAction SilentlyContinue
            Write-Log "Hyper-V Integration Services time sync disabled" -Level INFO
        }
        
        return $true
    }
    catch {
        Write-Log "Error disabling Hyper-V time sync: $($_.Exception.Message)" -Level WARN
        return $true  # Non-critical error
    }
}

function Set-NTPConfiguration {
    Write-Log "Configuring NTP settings..." -Level INFO
    
    try {
        Stop-TimeService | Out-Null
        
        # Configure NTP client
        Write-Log "Configuring NTP client..." -Level INFO
        
        # Set NTP servers
        $ntpServerString = ($NTPServers | ForEach-Object { "$_,0x9" }) -join ' '
        Set-ItemProperty -Path $W32TimeParameters -Name "NtpServer" -Value $ntpServerString
        Write-Log "NTP servers configured: $($NTPServers -join ', ')" -Level INFO
        
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
            
            Write-Log "Max positive correction: $MaxPosPhaseCorrection seconds" -Level INFO
            Write-Log "Max negative correction: $MaxNegPhaseCorrection seconds" -Level INFO
            Write-Log "Update interval: $SyncInterval seconds" -Level INFO
        }
        
        # Configure as domain time source if requested
        if ($SetAsDomainTimeSource) {
            Write-Log "Configuring as authoritative domain time source..." -Level INFO
            
            if (Test-IsDomainController) {
                Set-ItemProperty -Path $W32TimeConfig -Name "AnnounceFlags" -Value 5 -Type DWord
                Set-ItemProperty -Path $W32TimeParameters -Name "Type" -Value "NTP"
                
                # Enable NTP server
                $ntpServerPath = "$W32TimeTimeProviders\NtpServer"
                if (Test-Path $ntpServerPath) {
                    Set-ItemProperty -Path $ntpServerPath -Name "Enabled" -Value 1 -Type DWord
                }
                
                Write-Log "Configured as reliable time source for domain" -Level INFO
            }
            else {
                Write-Log "Not a domain controller - skipping domain time source configuration" -Level WARN
            }
        }
        
        Write-Log "NTP configuration completed" -Level INFO
        $script:ConfigurationsApplied++
        
        return $true
    }
    catch {
        Write-Log "Error configuring NTP: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Sync-TimeNow {
    Write-Log "Performing immediate time synchronization..." -Level INFO
    
    try {
        # Register time service
        w32tm.exe /register 2>&1 | Out-Null
        
        # Start service if not running
        Start-TimeService | Out-Null
        
        # Force resync
        Write-Log "Forcing time resynchronization..." -Level INFO
        $result = w32tm.exe /resync /force 2>&1
        
        Start-Sleep -Seconds 3
        
        Write-Log "Time synchronization initiated" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error during sync: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Test-NTPConfiguration {
    Write-Log "Verifying NTP configuration..." -Level INFO
    
    try {
        # Check service status
        $service = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "W32Time Service Status: $($service.Status)" -Level INFO
            Write-Log "W32Time Service Startup: $($service.StartType)" -Level INFO
        }
        
        # Check current time source
        $timeSource = w32tm.exe /query /source 2>&1
        Write-Log "Current time source: $timeSource" -Level INFO
        
        # Check NTP status
        Write-Log "Querying NTP status..." -Level INFO
        $status = w32tm.exe /query /status 2>&1
        
        if ($status -match "Source:") {
            Write-Log "NTP is functioning" -Level INFO
        }
        
        # Get time configuration
        $config = w32tm.exe /query /configuration 2>&1
        
        # Check peers
        Write-Log "Checking configured NTP peers..." -Level INFO
        $peers = w32tm.exe /query /peers 2>&1
        
        return $true
    }
    catch {
        Write-Log "Error during verification: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Get-NTPStatusReport {
    Write-Log "Generating NTP status report..." -Level INFO
    
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
        
        Write-Log "NTP status report saved to: $reportFile" -Level INFO
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

    Write-Log "===== Configure_NTP starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Check domain status
    if (Test-IsDomainMember -and -not $SetAsDomainTimeSource) {
        Write-Log "WARNING: This is a domain member" -Level WARN
        Write-Log "Domain members typically sync time from domain controllers" -Level WARN
        Write-Log "Manual NTP configuration may conflict with domain policy" -Level WARN
    }
    
    # Set timezone if specified
    Set-TimeZoneConfiguration | Out-Null
    
    # Disable Hyper-V time sync if requested
    Disable-HyperVTimeSync | Out-Null
    
    # Configure NTP
    $configSuccess = Set-NTPConfiguration
    
    if (-not $configSuccess) {
        Write-Log "NTP configuration failed" -Level ERROR
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
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    # Display current time info
    $currentTime = Get-Date
    Write-Log "Current System Time: $($currentTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "Current UTC Time: $($currentTime.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))"

    if ($script:ConfigurationsFailed -eq 0) {
        Write-Log "===== Configure_NTP complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_NTP complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) =====" -Level WARN
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
