<#
.SYNOPSIS
    Install and Configure VMware Tools

.DESCRIPTION
    Installs VMware Tools (open-vm-tools or VMware Tools) with proper version detection
    and configuration. Supports VMware Workstation, ESXi, and vSphere environments.

.NOTES
    File Name      : windows-server-install_VMware_Tools.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_VMware_Tools.ps1
    Installs VMware Tools automatically
    
.EXAMPLE
    .\windows-server-install_VMware_Tools.ps1 -DisableCopyPaste
    Installs VMware Tools and disables copy/paste feature
    
.PARAMETER DisableCopyPaste
    Disable copy/paste between host and guest
    
.PARAMETER DisableDragDrop
    Disable drag and drop between host and guest
#>

[CmdletBinding()]
param(
    [switch]$DisableCopyPaste,
    [switch]$DisableDragDrop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

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
    $logMessage = "[$timestamp] [$prefix] [VMware] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

# Main execution
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "==================================================="
    Write-Log "VMware Tools Installation Script"
    Write-Log "==================================================="
    Write-Log "Disable Copy/Paste: $DisableCopyPaste"
    Write-Log "Disable Drag/Drop: $DisableDragDrop"
    Write-Log ""
    
    # Detect virtualization platform
    Write-Log "Detecting virtualization platform..."
    $isVMware = $false
    
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $manufacturer = $computerSystem.Manufacturer
        $model = $computerSystem.Model
        
        Write-Log "System Manufacturer: $manufacturer"
        Write-Log "System Model: $model"
        
        if ($manufacturer -match 'VMware' -or $model -match 'VMware') {
            $isVMware = $true
            Write-Log "✓ Running on VMware platform"
        } else {
            Write-Log "Not running on VMware platform" -Level Warning
            Write-Log "Continuing installation anyway..."
        }
    } catch {
        Write-Log "Could not detect platform: $($_.Exception.Message)" -Level Warning
    }
    
    # Check if VMware Tools already installed
    Write-Log "Checking for existing VMware Tools installation..."
    $toolsInstalled = $false
    $toolsVersion = $null
    
    # Check for VMware Tools service
    $vmToolsService = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue
    if ($vmToolsService) {
        $toolsInstalled = $true
        Write-Log "VMware Tools service found: $($vmToolsService.Status)"
        
        # Get version
        try {
            $toolsPath = "${env:ProgramFiles}\VMware\VMware Tools\VMwareToolboxCmd.exe"
            if (Test-Path $toolsPath) {
                $toolsVersion = & $toolsPath -v 2>&1
                Write-Log "Installed version: $toolsVersion"
            }
        } catch {
            Write-Log "Could not determine VMware Tools version" -Level Warning
        }
    }
    
    # Install VMware Tools if not present
    if (-not $toolsInstalled) {
        Write-Log "VMware Tools not installed, proceeding with installation..."
        
        # Look for VMware Tools installer on mounted drives
        $installerFound = $false
        $drives = Get-Volume | Where-Object { $_.DriveType -ne 'Fixed' -and $_.DriveLetter }
        
        foreach ($drive in $drives) {
            $letter = $drive.DriveLetter
            $setupExe = "${letter}:\setup.exe"
            $setup64Exe = "${letter}:\setup64.exe"
            
            if (Test-Path $setup64Exe) {
                Write-Log "Found VMware Tools installer: $setup64Exe"
                Write-Log "Installing VMware Tools..."
                
                Start-Process -FilePath $setup64Exe -ArgumentList '/S', '/v', '/qn', 'REBOOT=R' -Wait -NoNewWindow
                
                Start-Sleep -Seconds 5
                
                $vmToolsService = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue
                if ($vmToolsService) {
                    Write-Log "✓ VMware Tools installed successfully"
                    $installerFound = $true
                    break
                }
            } elseif (Test-Path $setupExe) {
                Write-Log "Found VMware Tools installer: $setupExe"
                Write-Log "Installing VMware Tools..."
                
                Start-Process -FilePath $setupExe -ArgumentList '/S', '/v', '/qn', 'REBOOT=R' -Wait -NoNewWindow
                
                Start-Sleep -Seconds 5
                
                $vmToolsService = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue
                if ($vmToolsService) {
                    Write-Log "✓ VMware Tools installed successfully"
                    $installerFound = $true
                    break
                }
            }
        }
        
        if (-not $installerFound) {
            Write-Log "VMware Tools installer not found on any drive" -Level Warning
            Write-Log "Please mount VMware Tools ISO and run this script again"
        }
    } else {
        Write-Log "VMware Tools already installed"
    }
    
    # Configure VMware Tools settings
    Write-Log "Configuring VMware Tools settings..."
    
    $vmToolsConfigPath = "${env:ProgramData}\VMware\VMware Tools\tools.conf"
    $vmToolsConfigDir = Split-Path -Parent $vmToolsConfigPath
    
    if (-not (Test-Path $vmToolsConfigDir)) {
        New-Item -Path $vmToolsConfigDir -ItemType Directory -Force | Out-Null
    }
    
    $configContent = @"
[guestinfo]
# Guest information settings
poll-interval = 5

[logging]
# Logging configuration
log = true
vmtoolsd.level = info

"@
    
    # Add copy/paste settings if disabled
    if ($DisableCopyPaste) {
        Write-Log "Disabling copy/paste functionality..."
        $configContent += @"

[vmbackup]
enableHostToGuestCopyPaste = false
enableGuestToHostCopyPaste = false

"@
    }
    
    # Add drag/drop settings if disabled
    if ($DisableDragDrop) {
        Write-Log "Disabling drag/drop functionality..."
        $configContent += @"

[vmbackup]
enableHostToGuestDragDrop = false
enableGuestToHostDragDrop = false

"@
    }
    
    # Write configuration
    Set-Content -Path $vmToolsConfigPath -Value $configContent -Force
    Write-Log "✓ VMware Tools configuration updated"
    
    # Enable and start service
    if ($vmToolsService) {
        if ($vmToolsService.StartType -ne 'Automatic') {
            Set-Service -Name 'VMTools' -StartupType Automatic
            Write-Log "✓ VMware Tools service set to automatic startup"
        }
        
        if ($vmToolsService.Status -ne 'Running') {
            Start-Service -Name 'VMTools'
            Write-Log "✓ VMware Tools service started"
        }
    }
    
    # Configure VMware Tools memory balloon driver
    Write-Log "Checking memory balloon driver..."
    try {
        $balloonService = Get-Service -Name 'vmmemctl' -ErrorAction SilentlyContinue
        if ($balloonService) {
            Write-Log "Memory balloon driver present: $($balloonService.Status)"
            if ($balloonService.Status -ne 'Running') {
                Start-Service -Name 'vmmemctl'
                Write-Log "✓ Memory balloon driver started"
            }
        } else {
            Write-Log "Memory balloon driver not found (this is normal for some VMware Tools versions)"
        }
    } catch {
        Write-Log "Could not configure memory balloon driver: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "VMware Tools Installation Summary"
    Write-Log "==================================================="
    Write-Log "Platform: $(if ($isVMware) { 'VMware' } else { 'Non-VMware' })"
    Write-Log "VMware Tools: $(if ($vmToolsService) { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "Service Status: $(if ($vmToolsService) { $vmToolsService.Status } else { 'N/A' })"
    Write-Log "Copy/Paste: $(if ($DisableCopyPaste) { 'Disabled' } else { 'Enabled' })"
    Write-Log "Drag/Drop: $(if ($DisableDragDrop) { 'Disabled' } else { 'Enabled' })"
    Write-Log "Configuration: $vmToolsConfigPath"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "VMware Tools installation completed!"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}