<#
.SYNOPSIS
    Install and Configure Hyper-V Integration Services

.DESCRIPTION
    Verifies and configures Hyper-V Integration Services on Windows Server.
    Integration Services are typically built into modern Windows versions but
    may require configuration or updates on older systems.
    
    Ensures all Hyper-V services are running and optimally configured for
    virtual machine operation.

.NOTES
    File Name      : Install_HyperV_Integration_Services.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER VerifyOnly
    Only verify installation status without making changes

.PARAMETER EnableAllServices
    Enable all available integration services

.EXAMPLE
    .\Install_HyperV_Integration_Services.ps1
    Verifies and configures Hyper-V Integration Services

.EXAMPLE
    .\Install_HyperV_Integration_Services.ps1 -EnableAllServices
    Enables all available integration services

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Verify installation status only')]
    [switch]$VerifyOnly,

    [Parameter(HelpMessage = 'Enable all integration services')]
    [switch]$EnableAllServices
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [HyperV-IS] Transcript unavailable: $($_.Exception.Message)" }

# Hyper-V services to verify
$HyperVServices = @(
    'vmicheartbeat',      # Heartbeat
    'vmickvpexchange',    # Key-Value Pair Exchange
    'vmicshutdown',       # Guest Shutdown
    'vmictimesync',       # Time Synchronization
    'vmicvss',            # VSS (Volume Shadow Copy)
    'vmicguestinterface', # Guest Service Interface
    'vmicrdv'             # Remote Desktop Virtualization
)

# Statistics tracking
$script:ServicesConfigured = 0
$script:ServicesFailed = 0

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [HyperV-IS] $Message"
    Write-Host $logMessage
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# Main execution
try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    Write-Log "===== Install_HyperV_Integration_Services starting ====="
    
    Write-Log "========================================================="
    Write-Log "Hyper-V Integration Services Installation"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log ""
    
    # Detect Hyper-V
    Write-Log "Detecting virtualization platform..."
    
    $isHyperV = $false
    $manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
    $model = (Get-WmiObject -Class Win32_ComputerSystem).Model
    
    if ($manufacturer -like '*Microsoft*' -and $model -like '*Virtual*') {
        Write-Log "[OK] Hyper-V detected"
        Write-Log "  Manufacturer: $manufacturer"
        Write-Log "  Model: $model"
        $isHyperV = $true
    }
    else {
        Write-Log "Warning: Hyper-V not detected" -Level WARN
        Write-Log "  Manufacturer: $manufacturer"
        Write-Log "  Model: $model"
        Write-Log "Continuing anyway..."
    }
    
    # Check Windows version
    Write-Log ""
    Write-Log "Checking Windows version..."
    
    $osVersion = [System.Environment]::OSVersion.Version
    Write-Log "Windows Version: $($osVersion.Major).$($osVersion.Minor) Build $($osVersion.Build)"
    
    if ($osVersion.Major -ge 10) {
        Write-Log "[OK] Modern Windows version - Integration Services built-in"
    }
    elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -ge 2) {
        Write-Log "Windows 8/Server 2012 or newer - Integration Services built-in"
    }
    else {
        Write-Log "Warning: Older Windows version may require Integration Services installation" -Level WARN
    }
    
    # Check for Integration Services
    Write-Log ""
    Write-Log "Checking Integration Services status..."
    
    $servicesFound = 0
    $servicesRunning = 0
    
    foreach ($serviceName in $HyperVServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        
        if ($service) {
            $servicesFound++
            $statusSymbol = if ($service.Status -eq 'Running') { '[OK]' } else { '[FAIL]' }
            Write-Log "  $statusSymbol $($service.DisplayName) [$serviceName]: $($service.Status)"
            
            if ($service.Status -eq 'Running') {
                $servicesRunning++
            }
        }
        else {
            Write-Log "  [MISSING] ${serviceName}: Not found" -Level WARN
        }
    }
    
    Write-Log ""
    Write-Log "Services found: $servicesFound / $($HyperVServices.Count)"
    Write-Log "Services running: $servicesRunning / $servicesFound"
    
    if ($VerifyOnly) {
        Write-Log ""
        Write-Log "Verification complete."
        try { Stop-Transcript | Out-Null } catch {}
        exit 0
    }
    
    # Start stopped services
    if ($servicesRunning -lt $servicesFound) {
        Write-Log ""
        Write-Log "Starting stopped Integration Services..."
        
        foreach ($serviceName in $HyperVServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            
            if ($service -and $service.Status -ne 'Running') {
                try {
                    Start-Service -Name $serviceName -ErrorAction Stop
                    Write-Log "[OK] Started: $serviceName"
                    $script:ServicesConfigured++
                }
                catch {
                    Write-Log "Failed to start $serviceName : $($_.Exception.Message)" -Level WARN
                    $script:ServicesFailed++
                }
            }
        }
    }
    
    # Enable services if requested
    if ($EnableAllServices) {
        Write-Log ""
        Write-Log "Enabling all Integration Services..."
        
        foreach ($serviceName in $HyperVServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            
            if ($service) {
                try {
                    Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
                    Write-Log "[OK] Set to Automatic: $serviceName"
                    $script:ServicesConfigured++
                }
                catch {
                    Write-Log "Failed to set startup type for $serviceName : $($_.Exception.Message)" -Level WARN
                    $script:ServicesFailed++
                }
            }
        }
    }
    
    # Check for Hyper-V drivers
    Write-Log ""
    Write-Log "Checking for Hyper-V drivers..."
    
    $hypervDrivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object { 
        $_.DeviceName -like '*Hyper-V*' -or 
        $_.Manufacturer -like '*Microsoft*' -and $_.DeviceName -like '*Virtual*'
    }
    
    if ($hypervDrivers) {
        Write-Log "[OK] Found Hyper-V drivers:"
        foreach ($driver in $hypervDrivers) {
            Write-Log "  - $($driver.DeviceName) [$($driver.DriverVersion)]"
        }
    }
    else {
        Write-Log "Warning: No Hyper-V specific drivers detected" -Level WARN
    }
    
    # Verify network adapters
    Write-Log ""
    Write-Log "Checking network adapters..."
    
    $netAdapters = Get-NetAdapter | Where-Object { 
        $_.InterfaceDescription -like '*Hyper-V*' -or 
        $_.InterfaceDescription -like '*Microsoft*Virtual*'
    }
    
    if ($netAdapters) {
        Write-Log "[OK] Found Hyper-V network adapters:"
        foreach ($adapter in $netAdapters) {
            Write-Log "  - $($adapter.Name): $($adapter.Status) [$($adapter.LinkSpeed)]"
        }
    }
    
    # Configure registry settings
    Write-Log ""
    Write-Log "Applying Hyper-V optimizations..."
    
    try {
        # Time synchronization settings
        $timePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
        if (Test-Path $timePath) {
            Set-ItemProperty -Path $timePath -Name 'Type' -Value 'NoSync' -ErrorAction SilentlyContinue
            Write-Log "[OK] Configured time synchronization"
            $script:ServicesConfigured++
        }
        
    }
    catch {
        Write-Log "Registry optimization failed: $($_.Exception.Message)" -Level WARN
        $script:ServicesFailed++
    }
    
    # Final verification
    Write-Log ""
    Write-Log "Final verification..."
    
    $finalRunning = 0
    foreach ($serviceName in $HyperVServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            $finalRunning++
        }
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Hyper-V Integration Services Summary"
    Write-Log "========================================================="
    Write-Log "Platform detected: Hyper-V = $isHyperV"
    Write-Log "Services found: $servicesFound"
    Write-Log "Services running: $finalRunning / $servicesFound"
    Write-Log "Services configured: $script:ServicesConfigured"
    Write-Log "Configuration failures: $script:ServicesFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    if ($finalRunning -eq $servicesFound) {
        Write-Log "[OK] All Integration Services are running"
    }
    else {
        Write-Log "Warning: Not all services are running" -Level WARN
    }
    
    Write-Log "===== Install_HyperV_Integration_Services complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Installation failed: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
