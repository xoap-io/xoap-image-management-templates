<#
.SYNOPSIS
    Install Proxmox QEMU Guest Agent and VirtIO Drivers

.DESCRIPTION
    Installs QEMU Guest Agent and VirtIO drivers for optimal Proxmox VE performance.
    Searches for installers on mounted CD/DVD drives or accepts explicit paths.
    Configures guest agent service and verifies VirtIO driver installation.
    
    Supports both legacy and modern Proxmox VE environments.

.NOTES
    File Name      : Install_Proxmox_Guest_Agent.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER GuestAgentPath
    Optional explicit path to QEMU Guest Agent installer

.PARAMETER VirtIOPath
    Optional explicit path to VirtIO drivers ISO

.PARAMETER SkipVirtIO
    Skip VirtIO driver installation

.EXAMPLE
    .\Install_Proxmox_Guest_Agent.ps1
    Searches for and installs guest agent and VirtIO drivers

.EXAMPLE
    .\Install_Proxmox_Guest_Agent.ps1 -SkipVirtIO
    Installs only the guest agent

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Path to QEMU Guest Agent installer')]
    [string]$GuestAgentPath,

    [Parameter(HelpMessage = 'Path to VirtIO drivers ISO or directory')]
    [string]$VirtIOPath,

    [Parameter(HelpMessage = 'Skip VirtIO driver installation')]
    [switch]$SkipVirtIO
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
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [ProxmoxGA] Transcript unavailable: $($_.Exception.Message)" }

$script:InstallationsCompleted = 0
$script:InstallationsFailed = 0

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [ProxmoxGA] $Message"
    Write-Host $logMessage
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    Write-Log "===== Install_Proxmox_Guest_Agent starting ====="
    
    Write-Log "========================================================="
    Write-Log "Proxmox Guest Agent Installation"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log ""
    
    # Detect Proxmox
    Write-Log "Detecting virtualization platform..."
    $manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
    $model = (Get-WmiObject -Class Win32_ComputerSystem).Model
    
    if ($manufacturer -like '*QEMU*' -or $model -like '*QEMU*') {
        Write-Log "[OK] QEMU/Proxmox detected"
        Write-Log "  Manufacturer: $manufacturer"
        Write-Log "  Model: $model"
    }
    else {
        Write-Log "Warning: QEMU/Proxmox not detected" -Level WARN
        Write-Log "Continuing anyway..."
    }
    
    # Check if guest agent already installed
    Write-Log ""
    Write-Log "Checking for existing QEMU Guest Agent..."
    
    $agentService = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
    if ($agentService) {
        Write-Log "[OK] QEMU Guest Agent already installed"
        Write-Log "  Status: $($agentService.Status)"
        
        if ($agentService.Status -ne 'Running') {
            try {
                Start-Service -Name 'QEMU-GA' -ErrorAction Stop
                Write-Log "[OK] Started QEMU Guest Agent service"
            }
            catch {
                Write-Log "Failed to start service: $($_.Exception.Message)" -Level WARN
            }
        }
    }
    else {
        Write-Log "QEMU Guest Agent not installed, searching for installer..."
        
        # Find installer
        if ($GuestAgentPath -and (Test-Path $GuestAgentPath)) {
            $installerFile = $GuestAgentPath
        }
        else {
            $cdDrives = Get-WmiObject -Class Win32_CDROMDrive | Where-Object { $_.MediaLoaded -eq $true }
            
            $installerPatterns = @(
                'qemu-ga-*.msi',
                'qemu-ga.msi',
                'guest-agent*.msi'
            )
            
            $installerFile = $null
            foreach ($drive in $cdDrives) {
                $driveLetter = $drive.Drive
                Write-Log "Searching drive: $driveLetter"
                
                foreach ($pattern in $installerPatterns) {
                    $found = Get-ChildItem -Path $driveLetter -Filter $pattern -Recurse -ErrorAction SilentlyContinue | 
                        Select-Object -First 1
                    
                    if ($found) {
                        $installerFile = $found.FullName
                        Write-Log "[OK] Found installer: $installerFile"
                        break
                    }
                }
                
                if ($installerFile) { break }
            }
        }
        
        if ($installerFile) {
            Write-Log ""
            Write-Log "Installing QEMU Guest Agent..."
            
            $msiArgs = @(
                '/i'
                "`"$installerFile`""
                '/qn'
                '/norestart'
                "/l*v `"$LogDir\qemu-ga-$timestamp.log`""
            )
            
            $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Log "[OK] QEMU Guest Agent installed successfully"
                $script:InstallationsCompleted++
                
                # Start service
                Start-Sleep -Seconds 3
                $svc = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
                if ($svc) {
                    if ($svc.Status -ne 'Running') {
                        Start-Service -Name 'QEMU-GA'
                        Write-Log "[OK] Started QEMU Guest Agent service"
                    }
                }
            }
            else {
                Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level ERROR
                $script:InstallationsFailed++
            }
        }
        else {
            Write-Log "QEMU Guest Agent installer not found" -Level WARN
            $script:InstallationsFailed++
        }
    }
    
    # Install VirtIO drivers
    if (-not $SkipVirtIO) {
        Write-Log ""
        Write-Log "Checking VirtIO drivers..."
        
        $virtioDrivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object { 
            $_.DeviceName -like '*VirtIO*' -or $_.DriverProviderName -like '*Red Hat*'
        }
        
        if ($virtioDrivers) {
            Write-Log "[OK] VirtIO drivers already installed:"
            foreach ($driver in $virtioDrivers) {
                Write-Log "  - $($driver.DeviceName) [$($driver.DriverVersion)]"
            }
        }
        else {
            Write-Log "VirtIO drivers not detected, checking for installer..."
            
            if ($VirtIOPath -and (Test-Path $VirtIOPath)) {
                Write-Log "Using provided VirtIO path: $VirtIOPath"
                
                # Install drivers using pnputil
                $osVersion = [System.Environment]::OSVersion.Version
                $osDir = if ($osVersion.Major -eq 10) { 
                    if ($osVersion.Build -ge 22000) { 'w11' } else { 'w10' } 
                } else { "2k$($osVersion.Minor)" }
                
                $driverPath = Join-Path $VirtIOPath $osDir
                if (Test-Path $driverPath) {
                    Write-Log "Installing VirtIO drivers from: $driverPath"
                    
                    $infFiles = Get-ChildItem -Path $driverPath -Filter '*.inf' -Recurse
                    foreach ($inf in $infFiles) {
                        try {
                            $result = pnputil /add-driver $inf.FullName /install
                            Write-Log "[OK] Installed: $($inf.Name)"
                            $script:InstallationsCompleted++
                        }
                        catch {
                            Write-Log "Failed to install $($inf.Name)" -Level WARN
                        }
                    }
                }
            }
            else {
                Write-Log "VirtIO drivers path not provided, skipping" -Level WARN
            }
        }
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Installation Summary"
    Write-Log "========================================================="
    Write-Log "Components installed: $script:InstallationsCompleted"
    Write-Log "Installation failures: $script:InstallationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    $agentFinal = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
    if ($agentFinal -and $agentFinal.Status -eq 'Running') {
        Write-Log "[OK] QEMU Guest Agent is running"
    }
    
    Write-Log "===== Install_Proxmox_Guest_Agent complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Installation failed: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
