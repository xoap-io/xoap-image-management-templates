<#
.SYNOPSIS
    Installs Nutanix Guest Tools (NGT) on Windows Server 2025

.DESCRIPTION
    This script searches for and installs Nutanix Guest Tools (NGT) from mounted CD/DVD drives.
    Verifies installation success and service status. Designed for use with Nutanix AHV hypervisor
    during Packer image builds.
    
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER InstallerPath
    Optional explicit path to the NGT installer. If not specified, searches all CD/DVD drives.

.PARAMETER MaxRetries
    Maximum number of retry attempts for service verification. Default: 5

.PARAMETER RetryInterval
    Interval in seconds between retry attempts. Default: 3

.EXAMPLE
    .\Install_Nutanix_Guest_Tools.ps1
    Searches for and installs NGT from any available CD/DVD drive.

.EXAMPLE
    .\Install_Nutanix_Guest_Tools.ps1 -InstallerPath "E:\Windows\NutanixGuestTools.msi"
    Installs NGT from a specific path.

.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Explicit path to Nutanix Guest Tools installer')]
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
    [ValidateRange(1, 30)]
    [int]$RetryInterval = 3
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Script-level variables
$script:NGTServiceNames = @('NutanixGuestAgent', 'ngt_guest_agent')
$script:TasksCompleted = 0
$script:TasksFailed = 0
$script:startTime = Get-Date

#region Logging Functions

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes transcript logging to C:\xoap-logs
    #>
    $LogDir = 'C:\xoap-logs'
    try {
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
            [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Start-Transcript -Path $script:LogFile -Append | Out-Null
    } catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Nutanix] Transcript unavailable: $($_.Exception.Message)" }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a formatted log message with timestamp
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [Nutanix] $Message"
}

function Stop-Logging {
    <#
    .SYNOPSIS
        Stops transcript logging and displays summary
    #>
    param([int]$ExitCode = 0)
    
    Write-Log "=============================================="
    Write-Log "Nutanix Guest Tools Installation Summary"
    Write-Log "=============================================="
    Write-Log "Tasks completed: $script:TasksCompleted"
    Write-Log "Tasks failed: $script:TasksFailed"
    Write-Log "Exit code: $ExitCode"
    Write-Log "=============================================="
    
    Write-Log "===== Install_Nutanix_Guest_Tools complete in $([int]((Get-Date) - $script:startTime).TotalSeconds)s; exit=$ExitCode ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit $ExitCode
}

#endregion

#region Error Handling

trap {
    Write-Log "FATAL ERROR: $_" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    Write-Log "Exception: $($_.Exception.ToString())" -Level ERROR
    Stop-Logging -ExitCode 1
}

#endregion

#region Detection Functions

function Test-NGTInstalled {
    <#
    .SYNOPSIS
        Checks if Nutanix Guest Tools is currently installed
    .OUTPUTS
        Boolean indicating installation status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Log "Checking for existing Nutanix Guest Tools installation..." -Level INFO
    
    # Check via registry
    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    foreach ($path in $registryPaths) {
        try {
            $ngtEntry = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -like "*Nutanix Guest Tools*" } |
                       Select-Object -First 1
            
            if ($ngtEntry) {
                Write-Log "Nutanix Guest Tools found: $($ngtEntry.DisplayName)" -Level INFO
                Write-Log "  Version: $($ngtEntry.DisplayVersion)" -Level INFO
                Write-Log "  Publisher: $($ngtEntry.Publisher)" -Level INFO
                Write-Log "  Install Location: $($ngtEntry.InstallLocation)" -Level INFO
                return $true
            }
        }
        catch {
            Write-Log "Registry check failed for ${path}: $($_.Exception.Message)" -Level WARN
        }
    }
    
    # Check via service
    foreach ($serviceName in $script:NGTServiceNames) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                Write-Log "Nutanix Guest Tools service detected: $serviceName" -Level INFO
                Write-Log "  Status: $($service.Status)" -Level INFO
                return $true
            }
        }
        catch {
            Write-Log "Service check failed for ${serviceName}: $($_.Exception.Message)" -Level WARN
        }
    }
    
    Write-Log "Nutanix Guest Tools not detected" -Level INFO
    return $false
}

function Test-NGTService {
    <#
    .SYNOPSIS
        Verifies Nutanix Guest Tools service is running
    .OUTPUTS
        Boolean indicating service status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Log "Verifying Nutanix Guest Tools service status..." -Level INFO
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        foreach ($serviceName in $script:NGTServiceNames) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                
                if ($service) {
                    Write-Log "Service found: $serviceName (Status: $($service.Status))" -Level INFO
                    
                    if ($service.Status -eq 'Running') {
                        Write-Log "Nutanix Guest Tools service is running" -Level INFO
                        return $true
                    }
                    
                    if ($service.Status -eq 'Stopped') {
                        Write-Log "Attempting to start service: $serviceName..." -Level WARN
                        try {
                            Start-Service -Name $serviceName -ErrorAction Stop
                            Start-Sleep -Seconds 2
                            
                            $service = Get-Service -Name $serviceName -ErrorAction Stop
                            if ($service.Status -eq 'Running') {
                                Write-Log "Successfully started service: $serviceName" -Level INFO
                                return $true
                            }
                        }
                        catch {
                            Write-Log "Failed to start service: $($_.Exception.Message)" -Level WARN
                        }
                    }
                }
            }
            catch {
                Write-Log "Service check failed for ${serviceName}: $($_.Exception.Message)" -Level WARN
            }
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-Log "Retrying service verification in $RetryInterval seconds... (attempt $attempt/$MaxRetries)" -Level INFO
            Start-Sleep -Seconds $RetryInterval
        }
    }
    
    Write-Log "No Nutanix Guest Tools service is running after $MaxRetries attempts" -Level WARN
    return $false
}

#endregion

#region Installer Functions

function Find-NGTInstaller {
    <#
    .SYNOPSIS
        Searches for Nutanix Guest Tools installer on CD/DVD drives
    .OUTPUTS
        String path to installer or $null if not found
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    Write-Log "Searching for Nutanix Guest Tools installer..." -Level INFO
    
    # Get all CD/DVD drives
    try {
        $cdDrives = Get-WmiObject -Class Win32_CDROMDrive -ErrorAction Stop |
                   Where-Object { $_.Drive } |
                   Select-Object -ExpandProperty Drive
        
        if (-not $cdDrives) {
            Write-Log "No CD/DVD drives detected" -Level WARN
            return $null
        }
        
        Write-Log "Found $(@($cdDrives).Count) CD/DVD drive(s): $($cdDrives -join ', ')" -Level INFO
    }
    catch {
        Write-Log "Failed to enumerate CD/DVD drives: $($_.Exception.Message)" -Level ERROR
        return $null
    }
    
    # Search for installer on each drive
    foreach ($drive in $cdDrives) {
        $installerPath = Join-Path $drive 'Windows\NutanixGuestTools.msi'
        
        Write-Log "Checking: $installerPath" -Level INFO
        
        if (Test-Path $installerPath) {
            Write-Log "Nutanix Guest Tools installer found: $installerPath" -Level INFO
            
            # Get file details
            try {
                $fileInfo = Get-Item $installerPath -ErrorAction Stop
                Write-Log "  Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -Level INFO
                Write-Log "  Last Modified: $($fileInfo.LastWriteTime)" -Level INFO
            }
            catch {
                Write-Log "Could not retrieve file details: $($_.Exception.Message)" -Level WARN
            }
            
            return $installerPath
        }
    }
    
    # Alternative search - check root of CD drives
    Write-Log "Standard path not found, checking alternative locations..." -Level INFO
    foreach ($drive in $cdDrives) {
        try {
            $msiFiles = Get-ChildItem -Path $drive -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -like "*Nutanix*" }
            
            if ($msiFiles) {
                $installerPath = $msiFiles[0].FullName
                Write-Log "Found alternative installer path: $installerPath" -Level INFO
                return $installerPath
            }
        }
        catch {
            Write-Log "Search failed for drive ${drive}: $($_.Exception.Message)" -Level WARN
        }
    }
    
    Write-Log "Nutanix Guest Tools installer not found on any CD/DVD drive" -Level WARN
    return $null
}

function Install-NGT {
    <#
    .SYNOPSIS
        Installs Nutanix Guest Tools from the specified installer
    .OUTPUTS
        Boolean indicating installation success
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath
    )
    
    Write-Log "Installing Nutanix Guest Tools..." -Level INFO
    Write-Log "  Installer: $InstallerPath" -Level INFO
    Write-Log "  Arguments: /i /qn /norestart" -Level INFO
    
    try {
        $process = Start-Process -FilePath 'msiexec.exe' `
                                -ArgumentList "/i `"$InstallerPath`" /qn /norestart /L*v `"C:\xoap-logs\NGT-Install.log`"" `
                                -Wait `
                                -PassThru `
                                -NoNewWindow `
                                -ErrorAction Stop
        
        Write-Log "Installation process completed with exit code: $($process.ExitCode)" -Level INFO
        
        # MSI exit codes: 0 = success, 3010 = success with reboot required
        if ($process.ExitCode -eq 0) {
            Write-Log "Nutanix Guest Tools installation succeeded" -Level INFO
            Start-Sleep -Seconds 5  # Allow services to initialize
            return $true
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "Installation succeeded but requires reboot (exit code 3010)" -Level WARN
            Start-Sleep -Seconds 5
            return $true
        }
        elseif ($process.ExitCode -eq 1638) {
            Write-Log "Another version is already installed (exit code 1638)" -Level WARN
            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level ERROR
            Write-Log "Check detailed log: C:\xoap-logs\NGT-Install.log" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Installation exception: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

#endregion

#region Main Execution

try {
    # Initialize logging
    Initialize-Logging | Out-Null
    Write-Log "===== Install_Nutanix_Guest_Tools starting ====="
    
    $script:startTime = Get-Date
    
    Write-Log "=============================================="
    Write-Log "Nutanix Guest Tools Installation Script"
    Write-Log "=============================================="
    Write-Log "Script: $PSCommandPath"
    Write-Log "Max Retries: $MaxRetries"
    Write-Log "Retry Interval: $RetryInterval seconds"
    Write-Log "Started: $($script:startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "=============================================="
    
    # Check if already installed and running
    if (Test-NGTInstalled) {
        Write-Log "Nutanix Guest Tools is already installed" -Level INFO
        
        if (Test-NGTService) {
            Write-Log "Nutanix Guest Tools is properly installed and running" -Level INFO
            $script:TasksCompleted++
            Stop-Logging -ExitCode 0
        }
        else {
            Write-Log "Nutanix Guest Tools is installed but service is not running" -Level WARN
            Write-Log "This may be normal if services start on next boot" -Level INFO
            $script:TasksCompleted++
            Stop-Logging -ExitCode 0
        }
    }
    
    # Locate installer
    Write-Log ""
    if ($InstallerPath) {
        Write-Log "Using specified installer path: $InstallerPath" -Level INFO
        $ngtInstaller = $InstallerPath
    }
    else {
        $ngtInstaller = Find-NGTInstaller
    }
    
    if (-not $ngtInstaller) {
        Write-Log "Nutanix Guest Tools installer not found" -Level WARN
        Write-Log "This is expected if not running on Nutanix AHV hypervisor" -Level INFO
        Stop-Logging -ExitCode 0
    }
    
    # Install NGT
    Write-Log ""
    if (-not (Install-NGT -InstallerPath $ngtInstaller)) {
        Write-Log "Installation failed" -Level ERROR
        $script:TasksFailed++
        Stop-Logging -ExitCode 1
    }
    
    $script:TasksCompleted++
    
    # Verify installation
    Write-Log ""
    Write-Log "Performing post-installation verification..." -Level INFO
    
    if (Test-NGTInstalled) {
        Write-Log "Installation verified successfully" -Level INFO
        $script:TasksCompleted++
        
        if (Test-NGTService) {
            Write-Log "Service verification successful" -Level INFO
            $script:TasksCompleted++
        }
        else {
            Write-Log "Service not running yet (may start after reboot)" -Level WARN
        }
    }
    else {
        Write-Log "Installation verification failed" -Level ERROR
        $script:TasksFailed++
        Stop-Logging -ExitCode 1
    }
    
    # Calculate execution time
    $endTime = Get-Date
    $duration = $endTime - $script:startTime
    Write-Log ""
    Write-Log "Total execution time: $($duration.TotalSeconds) seconds" -Level INFO
    
    Write-Log "Nutanix Guest Tools installation completed successfully" -Level INFO
    Stop-Logging -ExitCode 0
}
catch {
    Write-Log "Unhandled exception in main execution: $_" -Level ERROR
    $script:TasksFailed++
    Stop-Logging -ExitCode 1
}

#endregion
