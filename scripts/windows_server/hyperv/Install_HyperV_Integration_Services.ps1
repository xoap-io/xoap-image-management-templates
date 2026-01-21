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
    https://github.com/xoap-io/xoap-packer-templates
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
$scriptName = 'hyperv-integration-install'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

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
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        default   { 'INFO' }
    }
    $logMessage = "[$timestamp] [$prefix] [HyperV-IS] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

# Main execution
try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
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
        Write-Log "✓ Hyper-V detected"
        Write-Log "  Manufacturer: $manufacturer"
        Write-Log "  Model: $model"
        $isHyperV = $true
    }
    else {
        Write-Log "Warning: Hyper-V not detected" -Level Warning
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
        Write-Log "✓ Modern Windows version - Integration Services built-in"
    }
    elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -ge 2) {
        Write-Log "Windows 8/Server 2012 or newer - Integration Services built-in"
    }
    else {
        Write-Log "Warning: Older Windows version may require Integration Services installation" -Level Warning
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
            $statusSymbol = if ($service.Status -eq 'Running') { '✓' } else { '✗' }
            Write-Log "  $statusSymbol $($service.DisplayName) [$serviceName]: $($service.Status)"
            
            if ($service.Status -eq 'Running') {
                $servicesRunning++
            }
        }
        else {
            Write-Log "  ✗ $serviceName: Not found" -Level Warning
        }
    }
    
    Write-Log ""
    Write-Log "Services found: $servicesFound / $($HyperVServices.Count)"
    Write-Log "Services running: $servicesRunning / $servicesFound"
    
    if ($VerifyOnly) {
        Write-Log ""
        Write-Log "Verification complete."
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
                    Write-Log "✓ Started: $serviceName"
                    $script:ServicesConfigured++
                }
                catch {
                    Write-Log "Failed to start $serviceName : $($_.Exception.Message)" -Level Warning
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
                    Write-Log "✓ Set to Automatic: $serviceName"
                    $script:ServicesConfigured++
                }
                catch {
                    Write-Log "Failed to set startup type for $serviceName : $($_.Exception.Message)" -Level Warning
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
        Write-Log "✓ Found Hyper-V drivers:"
        foreach ($driver in $hypervDrivers) {
            Write-Log "  - $($driver.DeviceName) [$($driver.DriverVersion)]"
        }
    }
    else {
        Write-Log "Warning: No Hyper-V specific drivers detected" -Level Warning
    }
    
    # Verify network adapters
    Write-Log ""
    Write-Log "Checking network adapters..."
    
    $netAdapters = Get-NetAdapter | Where-Object { 
        $_.InterfaceDescription -like '*Hyper-V*' -or 
        $_.InterfaceDescription -like '*Microsoft*Virtual*'
    }
    
    if ($netAdapters) {
        Write-Log "✓ Found Hyper-V network adapters:"
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
            Write-Log "✓ Configured time synchronization"
            $script:ServicesConfigured++
        }
        
    }
    catch {
        Write-Log "Registry optimization failed: $($_.Exception.Message)" -Level Warning
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
        Write-Log "✓ All Integration Services are running"
    }
    else {
        Write-Log "Warning: Not all services are running" -Level Warning
    }
    
} catch {
    Write-Log "Installation failed: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
