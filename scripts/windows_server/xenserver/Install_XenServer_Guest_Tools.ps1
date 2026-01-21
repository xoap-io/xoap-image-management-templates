<#
.SYNOPSIS
    Install XenServer/Citrix Hypervisor PV Drivers and Management Agent

.DESCRIPTION
    Installs XenServer PV (Paravirtualization) drivers and management agent on Windows Server.
    Searches for installers on mounted CD/DVD drives or accepts explicit path.
    Verifies installation success and service status.
    
    Supports both legacy XenServer and modern Citrix Hypervisor installations.

.NOTES
    File Name      : Install_XenServer_Guest_Tools.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER InstallerPath
    Optional explicit path to XenServer Tools installer. If not specified, searches all CD/DVD drives.

.PARAMETER MaxRetries
    Maximum number of retry attempts for service verification. Default: 5

.PARAMETER RetryInterval
    Interval in seconds between retry attempts. Default: 3

.PARAMETER SkipReboot
    Skip automatic reboot after installation. Default: False

.EXAMPLE
    .\Install_XenServer_Guest_Tools.ps1
    Searches for and installs XenServer Tools from any available CD/DVD drive

.EXAMPLE
    .\Install_XenServer_Guest_Tools.ps1 -InstallerPath "D:\managementagentx64.msi"
    Installs XenServer Tools from a specific path

.EXAMPLE
    .\Install_XenServer_Guest_Tools.ps1 -SkipReboot
    Installs tools without automatic reboot

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Explicit path to XenServer Tools installer')]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "Installer path does not exist: $_"
        }
        $true
    })]
    [string]$InstallerPath,

    [Parameter(HelpMessage = 'Maximum number of service verification retry attempts')]
    [ValidateRange(1, 20)]
    [int]$MaxRetries = 5,

    [Parameter(HelpMessage = 'Interval in seconds between retry attempts')]
    [ValidateRange(1, 60)]
    [int]$RetryInterval = 3,

    [Parameter(HelpMessage = 'Skip automatic reboot after installation')]
    [switch]$SkipReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = 'xenserver-tools-install'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# XenServer service names to verify
$XenServices = @(
    'xenservice',
    'xenvif',
    'xenvbd'
)

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
    $logMessage = "[$timestamp] [$prefix] [XenTools] $Message"
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
    Write-Log "XenServer Guest Tools Installation"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log ""
    
    # Check if already installed
    Write-Log "Checking for existing XenServer installation..."
    $xenInstalled = $false
    foreach ($service in $XenServices) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Write-Log "✓ XenServer service found: $service"
            $xenInstalled = $true
        }
    }
    
    if ($xenInstalled) {
        Write-Log "XenServer Tools appear to be already installed"
        Write-Log "Verifying all services..."
        
        $allRunning = $true
        foreach ($service in $XenServices) {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Log "  $service : $($svc.Status)"
                if ($svc.Status -ne 'Running') {
                    $allRunning = $false
                }
            }
        }
        
        if ($allRunning) {
            Write-Log "All XenServer services are running. Installation not required."
            exit 0
        }
    }
    
    # Find installer
    Write-Log "Searching for XenServer Tools installer..."
    
    if ($InstallerPath -and (Test-Path $InstallerPath)) {
        Write-Log "Using provided installer path: $InstallerPath"
        $installerFile = $InstallerPath
    }
    else {
        Write-Log "Searching CD/DVD drives for XenServer Tools..."
        
        $cdDrives = Get-WmiObject -Class Win32_CDROMDrive | Where-Object { $_.MediaLoaded -eq $true }
        
        if (-not $cdDrives) {
            throw "No CD/DVD drives found with media loaded"
        }
        
        $installerFile = $null
        $installerPatterns = @(
            'managementagentx64.msi',
            'managementagent.msi',
            'xensetup.exe',
            'citrixhypervisor*.msi'
        )
        
        foreach ($drive in $cdDrives) {
            $driveLetter = $drive.Drive
            Write-Log "Checking drive: $driveLetter"
            
            foreach ($pattern in $installerPatterns) {
                $searchPath = Join-Path $driveLetter $pattern
                $found = Get-ChildItem -Path $driveLetter -Filter $pattern -Recurse -ErrorAction SilentlyContinue | 
                    Select-Object -First 1
                
                if ($found) {
                    $installerFile = $found.FullName
                    Write-Log "✓ Found installer: $installerFile"
                    break
                }
            }
            
            if ($installerFile) { break }
        }
        
        if (-not $installerFile) {
            throw "XenServer Tools installer not found on any CD/DVD drive"
        }
    }
    
    # Install XenServer Tools
    Write-Log "Installing XenServer Tools from: $installerFile"
    
    $installerExt = [System.IO.Path]::GetExtension($installerFile).ToLower()
    
    if ($installerExt -eq '.msi') {
        Write-Log "Installing MSI package..."
        
        $msiArgs = @(
            '/i'
            "`"$installerFile`""
            '/qn'
            '/norestart'
            "/l*v `"$LogDir\xentools-msi-$timestamp.log`""
        )
        
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Log "✓ XenServer Tools MSI installation completed successfully"
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "✓ XenServer Tools installation completed (reboot required)"
        }
        else {
            throw "MSI installation failed with exit code: $($process.ExitCode)"
        }
    }
    elseif ($installerExt -eq '.exe') {
        Write-Log "Installing EXE package..."
        
        $exeArgs = @('/S', '/norestart')
        $process = Start-Process -FilePath $installerFile -ArgumentList $exeArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Log "✓ XenServer Tools EXE installation completed successfully"
        }
        else {
            throw "EXE installation failed with exit code: $($process.ExitCode)"
        }
    }
    else {
        throw "Unsupported installer type: $installerExt"
    }
    
    # Verify installation
    Write-Log "Verifying XenServer Tools installation..."
    
    Start-Sleep -Seconds 5
    
    $attempt = 0
    $allServicesRunning = $false
    
    while ($attempt -lt $MaxRetries -and -not $allServicesRunning) {
        $attempt++
        Write-Log "Verification attempt $attempt of $MaxRetries..."
        
        $servicesFound = 0
        $servicesRunning = 0
        
        foreach ($service in $XenServices) {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                $servicesFound++
                Write-Log "  $service : $($svc.Status)"
                
                if ($svc.Status -eq 'Running') {
                    $servicesRunning++
                }
                elseif ($svc.Status -eq 'Stopped') {
                    try {
                        Start-Service -Name $service -ErrorAction Stop
                        Write-Log "  Started service: $service"
                        $servicesRunning++
                    }
                    catch {
                        Write-Log "  Failed to start service $service : $($_.Exception.Message)" -Level Warning
                    }
                }
            }
        }
        
        if ($servicesFound -gt 0 -and $servicesFound -eq $servicesRunning) {
            $allServicesRunning = $true
            Write-Log "✓ All XenServer services are running"
        }
        else {
            Write-Log "Services found: $servicesFound, Running: $servicesRunning"
            if ($attempt -lt $MaxRetries) {
                Write-Log "Waiting $RetryInterval seconds before next attempt..."
                Start-Sleep -Seconds $RetryInterval
            }
        }
    }
    
    if (-not $allServicesRunning) {
        Write-Log "Warning: Not all XenServer services are running after $MaxRetries attempts" -Level Warning
        Write-Log "A reboot may be required for services to start properly" -Level Warning
    }
    
    # Check for installed drivers
    Write-Log "Checking for XenServer PV drivers..."
    $drivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object { 
        $_.DeviceName -like '*Xen*' -or $_.Manufacturer -like '*Citrix*' 
    }
    
    if ($drivers) {
        Write-Log "✓ Found XenServer PV drivers:"
        foreach ($driver in $drivers) {
            Write-Log "  - $($driver.DeviceName) [$($driver.DriverVersion)]"
        }
    }
    else {
        Write-Log "Warning: No XenServer PV drivers detected (may require reboot)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "XenServer Tools Installation Summary"
    Write-Log "========================================================="
    Write-Log "Installation file: $installerFile"
    Write-Log "Services verified: $servicesFound"
    Write-Log "Services running: $servicesRunning"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    # Reboot handling
    if (-not $SkipReboot) {
        Write-Log ""
        Write-Log "System will reboot in 30 seconds to complete installation..."
        Write-Log "Use -SkipReboot parameter to prevent automatic reboot"
        Start-Sleep -Seconds 30
        Restart-Computer -Force
    }
    else {
        Write-Log ""
        Write-Log "Installation completed. Manual reboot recommended."
    }
    
} catch {
    Write-Log "Installation failed: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
