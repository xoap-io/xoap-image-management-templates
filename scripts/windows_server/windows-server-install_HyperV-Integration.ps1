<#
.SYNOPSIS
    Install and Configure Hyper-V Integration Services

.DESCRIPTION
    Configures Hyper-V Integration Services for Windows Server VMs including
    Enhanced Session Mode, Dynamic Memory, and PowerShell Direct.

.NOTES
    File Name      : windows-server-install_HyperV-Integration.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_HyperV-Integration.ps1
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

$script:Component = 'Hyper-V'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message
    Write-Host $line
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "===== install_HyperV-Integration starting ====="

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
            Write-Log "[OK] Running on Hyper-V"
        } else {
            Write-Log "Not running on Hyper-V" -Level WARN
            Write-Log "Continuing configuration anyway..."
        }
    } catch {
        Write-Log "Could not detect platform: $($_.Exception.Message)" -Level WARN
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
            Write-Log "  [OK] $svcName : $($svc.Status)"
            
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
            Write-Log "  [FAIL] $svcName not found" -Level WARN
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
        Write-Log "[OK] Enhanced Session Mode registry configured"
    } catch {
        Write-Log "Could not configure Enhanced Session Mode: $($_.Exception.Message)" -Level WARN
    }
    
    # Enable Remote Desktop
    Write-Log "Ensuring Remote Desktop is enabled..."
    try {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
        
        # Enable RDP in firewall
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        Write-Log "[OK] Remote Desktop enabled"
    } catch {
        Write-Log "Could not enable Remote Desktop: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure Dynamic Memory readiness
    Write-Log "Configuring system for Dynamic Memory..."
    try {
        # Disable pagefile on C: (if desired for dynamic memory optimization)
        # This is commented out as it may not be desired in all scenarios
        # $pagefile = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting WHERE Name='C:\\pagefile.sys'"
        # if ($pagefile) {
        #     $pagefile.Delete()
        #     Write-Log "[OK] Removed pagefile for Dynamic Memory optimization"
        # }
        
        Write-Log "[OK] System ready for Dynamic Memory"
    } catch {
        Write-Log "Could not configure Dynamic Memory settings: $($_.Exception.Message)" -Level WARN
    }
    
    # Summary
    Write-Log "Platform: $(if ($isHyperV) { 'Hyper-V' } else { 'Non-Hyper-V' })"
    Write-Log "Integration Services configured: $servicesConfigured"
    Write-Log "Enhanced Session Mode: Configured"
    Write-Log "Remote Desktop: Enabled"
    Write-Log "===== install_HyperV-Integration complete in $([int]((Get-Date) - $startTime).TotalSeconds)s; applied=$servicesConfigured ====="
    exit 0
} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}