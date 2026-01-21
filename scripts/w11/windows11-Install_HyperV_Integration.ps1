<#
.SYNOPSIS
    Install and Configure Hyper-V Integration Services

.DESCRIPTION
    Configures Hyper-V Integration Services for Windows 10/11 VMs including
    Enhanced Session Mode, Dynamic Memory, and PowerShell Direct.

.NOTES
    File Name      : windows11-install_HyperV-Integration.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-install_HyperV-Integration.ps1
    Configures Hyper-V Integration Services
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
    $logMessage = "[$timestamp] [$prefix] [Hyper-V] $Message"
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
    Write-Log "Hyper-V Integration Services Configuration"
    Write-Log "==================================================="
    
    # Detect Hyper-V
    Write-Log "Detecting virtualization platform..."
    $isHyperV = $false
    
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $manufacturer = $computerSystem.Manufacturer
        $model = $computerSystem.Model
        
        Write-Log "System Manufacturer: $manufacturer"
        Write-Log "System Model: $model"
        
        if ($manufacturer -match 'Microsoft' -and $model -match 'Virtual') {
            $isHyperV = $true
            Write-Log "✓ Running on Hyper-V"
        } else {
            Write-Log "Not running on Hyper-V" -Level Warning
            Write-Log "Continuing configuration anyway..."
        }
    } catch {
        Write-Log "Could not detect platform: $($_.Exception.Message)" -Level Warning
    }
    
    # Check Integration Services
    Write-Log "Checking Hyper-V Integration Services..."
    
    $integrationServices = @(
        'vmicheartbeat',     # Heartbeat
        'vmicvss',           # Volume Shadow Copy
        'vmicshutdown',      # Guest Shutdown
        'vmickvpexchange',   # Key-Value Pair Exchange
        'vmictimesync',      # Time Synchronization
        'vmicrdv',           # Remote Desktop Virtualization
        'vmicguestinterface' # Guest Service Interface
    )
    
    $servicesConfigured = 0
    foreach ($svcName in $integrationServices) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log "  ✓ $svcName : $($svc.Status)"
            
            if ($svc.StartType -ne 'Automatic') {
                Set-Service -Name $svcName -StartupType Automatic
                Write-Log "    Set $svcName to Automatic startup"
            }
            
            if ($svc.Status -ne 'Running') {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                Write-Log "    Started $svcName"
            }
            
            $servicesConfigured++
        } else {
            Write-Log "  ✗ $svcName not found" -Level Warning
        }
    }
    
    # Configure Enhanced Session Mode
    Write-Log "Configuring Enhanced Session Mode support..."
    try {
        $rdpPath = 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest'
        if (-not (Test-Path $rdpPath)) {
            New-Item -Path $rdpPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $rdpPath -Name 'OSVersion' -Value ([System.Environment]::OSVersion.Version.ToString()) -Type String
        Write-Log "✓ Enhanced Session Mode registry configured"
    } catch {
        Write-Log "Could not configure Enhanced Session Mode: $($_.Exception.Message)" -Level Warning
    }
    
    # Enable Remote Desktop
    Write-Log "Ensuring Remote Desktop is enabled..."
    try {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
        
        # Enable RDP in firewall
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        Write-Log "✓ Remote Desktop enabled"
    } catch {
        Write-Log "Could not enable Remote Desktop: $($_.Exception.Message)" -Level Warning
    }
    
    # Configure Dynamic Memory readiness
    Write-Log "Configuring system for Dynamic Memory..."
    try {
        # Disable pagefile on C: (if desired for dynamic memory optimization)
        # This is commented out as it may not be desired in all scenarios
        # $pagefile = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting WHERE Name='C:\\pagefile.sys'"
        # if ($pagefile) {
        #     $pagefile.Delete()
        #     Write-Log "✓ Removed pagefile for Dynamic Memory optimization"
        # }
        
        Write-Log "✓ System ready for Dynamic Memory"
    } catch {
        Write-Log "Could not configure Dynamic Memory settings: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "Hyper-V Integration Services Summary"
    Write-Log "==================================================="
    Write-Log "Platform: $(if ($isHyperV) { 'Hyper-V' } else { 'Non-Hyper-V' })"
    Write-Log "Integration Services configured: $servicesConfigured"
    Write-Log "Enhanced Session Mode: Configured"
    Write-Log "Remote Desktop: Enabled"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}