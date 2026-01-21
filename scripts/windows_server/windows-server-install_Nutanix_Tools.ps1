<#
.SYNOPSIS
    Install Nutanix Guest Tools (NGT)

.DESCRIPTION
    Installs Nutanix Guest Tools including VirtIO drivers and enables
    application-consistent snapshots and self-service file restore.

.NOTES
    File Name      : windows-server-install_Nutanix_Tools.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_Nutanix_Tools.ps1
    Installs Nutanix Guest Tools
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
    $logMessage = "[$timestamp] [$prefix] [Nutanix] $Message"
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
    Write-Log "Nutanix Guest Tools (NGT) Installation"
    Write-Log "==================================================="
    
    # Detect Nutanix
    Write-Log "Detecting virtualization platform..."
    $isNutanix = $false
    
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $manufacturer = $computerSystem.Manufacturer
        $model = $computerSystem.Model
        
        Write-Log "System Manufacturer: $manufacturer"
        Write-Log "System Model: $model"
        
        if ($manufacturer -match 'Nutanix' -or $model -match 'AHV') {
            $isNutanix = $true
            Write-Log "✓ Running on Nutanix AHV"
        } else {
            Write-Log "Not running on Nutanix AHV" -Level Warning
            Write-Log "Continuing installation anyway..."
        }
    } catch {
        Write-Log "Could not detect platform: $($_.Exception.Message)" -Level Warning
    }
    
    # Check for existing NGT installation
    Write-Log "Checking for existing Nutanix Guest Tools..."
    $ngtService = Get-Service -Name 'NutanixGuestAgent' -ErrorAction SilentlyContinue
    
    if ($ngtService) {
        Write-Log "Nutanix Guest Tools already installed"
        Write-Log "Service status: $($ngtService.Status)"
    } else {
        Write-Log "Nutanix Guest Tools not installed, proceeding..."
        
        # Look for NGT installer
        $installerFound = $false
        $drives = Get-Volume | Where-Object { $_.DriveType -ne 'Fixed' -and $_.DriveLetter }
        
        foreach ($drive in $drives) {
            $letter = $drive.DriveLetter
            $installerMsi = "${letter}:\Nutanix-VirtIO-*.msi"
            $ngtInstaller = "${letter}:\setup.exe"
            
            # Look for VirtIO MSI
            $virtioFiles = Get-ChildItem -Path "${letter}:\" -Filter "Nutanix-VirtIO-*.msi" -ErrorAction SilentlyContinue
            
            if ($virtioFiles) {
                Write-Log "Found Nutanix VirtIO drivers: $($virtioFiles[0].FullName)"
                Write-Log "Installing VirtIO drivers..."
                
                Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$($virtioFiles[0].FullName)`" /qn /norestart" -Wait -NoNewWindow
                Write-Log "✓ VirtIO drivers installed"
            }
            
            # Look for NGT setup.exe
            if (Test-Path $ngtInstaller) {
                Write-Log "Found NGT installer: $ngtInstaller"
                Write-Log "Installing Nutanix Guest Tools..."
                
                Start-Process -FilePath $ngtInstaller -ArgumentList '/quiet', '/norestart' -Wait -NoNewWindow
                
                Start-Sleep -Seconds 5
                
                $ngtService = Get-Service -Name 'NutanixGuestAgent' -ErrorAction SilentlyContinue
                if ($ngtService) {
                    Write-Log "✓ Nutanix Guest Tools installed successfully"
                    $installerFound = $true
                    break
                }
            }
        }
        
        if (-not $installerFound) {
            Write-Log "NGT installer not found" -Level Warning
            Write-Log "Mount NGT ISO via Prism and run this script again"
        }
    }
    
    # Verify NGT services
    if ($ngtService) {
        Write-Log "Verifying Nutanix services..."
        
        $services = @('NutanixGuestAgent', 'NutanixVSSProvider')
        foreach ($svcName in $services) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Log "  ✓ $svcName : $($svc.Status)"
                
                if ($svc.Status -ne 'Running' -and $svc.StartType -ne 'Disabled') {
                    Start-Service -Name $svcName -ErrorAction SilentlyContinue
                    Write-Log "  Started $svcName"
                }
            }
        }
    }
    
    # Check VirtIO drivers
    Write-Log "Checking VirtIO drivers..."
    try {
        $drivers = @(
            @{Name='netkvm'; Description='Nutanix VirtIO Ethernet Adapter'},
            @{Name='viostor'; Description='Nutanix VirtIO SCSI Controller'},
            @{Name='vioscsi'; Description='Nutanix VirtIO SCSI pass-through'},
            @{Name='balloon'; Description='Nutanix VirtIO Balloon Driver'}
        )
        
        foreach ($driver in $drivers) {
            $driverInfo = Get-WindowsDriver -Online -Driver $driver.Name -ErrorAction SilentlyContinue
            if ($driverInfo) {
                Write-Log "  ✓ $($driver.Description) installed"
            } else {
                Write-Log "  - $($driver.Description) not found (may not be required)"
            }
        }
    } catch {
        Write-Log "Could not enumerate drivers: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "Nutanix Guest Tools Summary"
    Write-Log "==================================================="
    Write-Log "Platform: $(if ($isNutanix) { 'Nutanix AHV' } else { 'Non-Nutanix' })"
    Write-Log "Guest Tools: $(if ($ngtService) { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "Service Status: $(if ($ngtService) { $ngtService.Status } else { 'N/A' })"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}