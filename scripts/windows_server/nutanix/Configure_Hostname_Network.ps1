<#
.SYNOPSIS
    Installs Nutanix Guest Tools (NGT) on Windows Server 2025

.DESCRIPTION
    This script searches for and installs Nutanix Guest Tools (NGT) from mounted CD/DVD drives.
    Verifies installation success and service status. Designed for use with Nutanix AHV hypervisor
    during Packer image builds.
    
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. © RIS AG

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
    https://github.com/xoap-io/xoap-packer-templates

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

#region Logging Functions

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes transcript logging to C:\xoap-logs
    #>
    try {
        $LogDir = 'C:\xoap-logs'
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        
        $scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
        
        Start-Transcript -Path $script:LogFile -Append | Out-Null
        Write-Log "Logging initialized: $script:LogFile" -Level Info
        return $true
    }
    catch {
        Write-Warning "Failed to start transcript logging: $($_.Exception.Message)"
        return $false
    }
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
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Error'   { Write-Host $formattedMessage -ForegroundColor Red }
        'Warning' { Write-Host $formattedMessage -ForegroundColor Yellow }
        'Success' { Write-Host $formattedMessage -ForegroundColor Green }
        default   { Write-Host $formattedMessage }
    }
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
    
    try { Stop-Transcript | Out-Null } catch {}
    exit $ExitCode
}

#endregion

#region Error Handling

trap {
    Write-Log "FATAL ERROR: $_" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log "Exception: $($_.Exception.ToString())" -Level Error
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
    
    Write-Log "Checking for existing Nutanix Guest Tools installation..." -Level Info
    
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
                Write-Log "Nutanix Guest Tools found: $($ngtEntry.DisplayName)" -Level Info
                Write-Log "  Version: $($ngtEntry.DisplayVersion)" -Level Info
                Write-Log "  Publisher: $($ngtEntry.Publisher)" -Level Info
                Write-Log "  Install Location: $($ngtEntry.InstallLocation)" -Level Info
                return $true
            }
        }
        catch {
            Write-Log "Registry check failed for ${path}: $($_.Exception.Message)" -Level Warning
        }
    }
    
    # Check via service
    foreach ($serviceName in $script:NGTServiceNames) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                Write-Log "Nutanix Guest Tools service detected: $serviceName" -Level Info
                Write-Log "  Status: $($service.Status)" -Level Info
                return $true
            }
        }
        catch {
            Write-Log "Service check failed for ${serviceName}: $($_.Exception.Message)" -Level Warning
        }
    }
    
    Write-Log "Nutanix Guest Tools not detected" -Level Info
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
    
    Write-Log "Verifying Nutanix Guest Tools service status..." -Level Info
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        foreach ($serviceName in $script:NGTServiceNames) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                
                if ($service) {
                    Write-Log "Service found: $serviceName (Status: $($service.Status))" -Level Info
                    
                    if ($service.Status -eq 'Running') {
                        Write-Log "Nutanix Guest Tools service is running" -Level Success
                        return $true
                    }
                    
                    if ($service.Status -eq 'Stopped') {
                        Write-Log "Attempting to start service: $serviceName..." -Level Warning
                        try {
                            Start-Service -Name $serviceName -ErrorAction Stop
                            Start-Sleep -Seconds 2
                            
                            $service = Get-Service -Name $serviceName -ErrorAction Stop
                            if ($service.Status -eq 'Running') {
                                Write-Log "Successfully started service: $serviceName" -Level Success
                                return $true
                            }
                        }
                        catch {
                            Write-Log "Failed to start service: $($_.Exception.Message)" -Level Warning
                        }
                    }
                }
            }
            catch {
                Write-Log "Service check failed for ${serviceName}: $($_.Exception.Message)" -Level Warning
            }
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-Log "Retrying service verification in $RetryInterval seconds... (attempt $attempt/$MaxRetries)" -Level Info
            Start-Sleep -Seconds $RetryInterval
        }
    }
    
    Write-Log "No Nutanix Guest Tools service is running after $MaxRetries attempts" -Level Warning
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
    
    Write-Log "Searching for Nutanix Guest Tools installer..." -Level Info
    
    # Get all CD/DVD drives
    try {
        $cdDrives = Get-WmiObject -Class Win32_CDROMDrive -ErrorAction Stop |
                   Where-Object { $_.Drive } |
                   Select-Object -ExpandProperty Drive
        
        if (-not $cdDrives) {
            Write-Log "No CD/DVD drives detected" -Level Warning
            return $null
        }
        
        Write-Log "Found $(@($cdDrives).Count) CD/DVD drive(s): $($cdDrives -join ', ')" -Level Info
    }
    catch {
        Write-Log "Failed to enumerate CD/DVD drives: $($_.Exception.Message)" -Level Error
        return $null
    }
    
    # Search for installer on each drive
    foreach ($drive in $cdDrives) {
        $installerPath = Join-Path $drive 'Windows\NutanixGuestTools.msi'
        
        Write-Log "Checking: $installerPath" -Level Info
        
        if (Test-Path $installerPath) {
            Write-Log "Nutanix Guest Tools installer found: $installerPath" -Level Success
            
            # Get file details
            try {
                $fileInfo = Get-Item $installerPath -ErrorAction Stop
                Write-Log "  Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -Level Info
                Write-Log "  Last Modified: $($fileInfo.LastWriteTime)" -Level Info
            }
            catch {
                Write-Log "Could not retrieve file details: $($_.Exception.Message)" -Level Warning
            }
            
            return $installerPath
        }
    }
    
    # Alternative search - check root of CD drives
    Write-Log "Standard path not found, checking alternative locations..." -Level Info
    foreach ($drive in $cdDrives) {
        try {
            $msiFiles = Get-ChildItem -Path $drive -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -like "*Nutanix*" }
            
            if ($msiFiles) {
                $installerPath = $msiFiles[0].FullName
                Write-Log "Found alternative installer path: $installerPath" -Level Success
                return $installerPath
            }
        }
        catch {
            Write-Log "Search failed for drive ${drive}: $($_.Exception.Message)" -Level Warning
        }
    }
    
    Write-Log "Nutanix Guest Tools installer not found on any CD/DVD drive" -Level Warning
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
    
    Write-Log "Installing Nutanix Guest Tools..." -Level Info
    Write-Log "  Installer: $InstallerPath" -Level Info
    Write-Log "  Arguments: /i /qn /norestart" -Level Info
    
    try {
        $process = Start-Process -FilePath 'msiexec.exe' `
                                -ArgumentList "/i `"$InstallerPath`" /qn /norestart /L*v `"C:\xoap-logs\NGT-Install.log`"" `
                                -Wait `
                                -PassThru `
                                -NoNewWindow `
                                -ErrorAction Stop
        
        Write-Log "Installation process completed with exit code: $($process.ExitCode)" -Level Info
        
        # MSI exit codes: 0 = success, 3010 = success with reboot required
        if ($process.ExitCode -eq 0) {
            Write-Log "Nutanix Guest Tools installation succeeded" -Level Success
            Start-Sleep -Seconds 5  # Allow services to initialize
            return $true
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "Installation succeeded but requires reboot (exit code 3010)" -Level Warning
            Start-Sleep -Seconds 5
            return $true
        }
        elseif ($process.ExitCode -eq 1638) {
            Write-Log "Another version is already installed (exit code 1638)" -Level Warning
            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level Error
            Write-Log "Check detailed log: C:\xoap-logs\NGT-Install.log" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Installation exception: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Main Execution

try {
    # Initialize logging
    Initialize-Logging | Out-Null
    
    $startTime = Get-Date
    
    Write-Log "=============================================="
    Write-Log "Nutanix Guest Tools Installation Script"
    Write-Log "=============================================="
    Write-Log "Script: $PSCommandPath"
    Write-Log "Max Retries: $MaxRetries"
    Write-Log "Retry Interval: $RetryInterval seconds"
    Write-Log "Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "=============================================="
    
    # Check if already installed and running
    if (Test-NGTInstalled) {
        Write-Log "Nutanix Guest Tools is already installed" -Level Info
        
        if (Test-NGTService) {
            Write-Log "Nutanix Guest Tools is properly installed and running" -Level Success
            $script:TasksCompleted++
            Stop-Logging -ExitCode 0
        }
        else {
            Write-Log "Nutanix Guest Tools is installed but service is not running" -Level Warning
            Write-Log "This may be normal if services start on next boot" -Level Info
            $script:TasksCompleted++
            Stop-Logging -ExitCode 0
        }
    }
    
    # Locate installer
    Write-Log ""
    if ($InstallerPath) {
        Write-Log "Using specified installer path: $InstallerPath" -Level Info
        $ngtInstaller = $InstallerPath
    }
    else {
        $ngtInstaller = Find-NGTInstaller
    }
    
    if (-not $ngtInstaller) {
        Write-Log "Nutanix Guest Tools installer not found" -Level Warning
        Write-Log "This is expected if not running on Nutanix AHV hypervisor" -Level Info
        Stop-Logging -ExitCode 0
    }
    
    # Install NGT
    Write-Log ""
    if (-not (Install-NGT -InstallerPath $ngtInstaller)) {
        Write-Log "Installation failed" -Level Error
        $script:TasksFailed++
        Stop-Logging -ExitCode 1
    }
    
    $script:TasksCompleted++
    
    # Verify installation
    Write-Log ""
    Write-Log "Performing post-installation verification..." -Level Info
    
    if (Test-NGTInstalled) {
        Write-Log "Installation verified successfully" -Level Success
        $script:TasksCompleted++
        
        if (Test-NGTService) {
            Write-Log "Service verification successful" -Level Success
            $script:TasksCompleted++
        }
        else {
            Write-Log "Service not running yet (may start after reboot)" -Level Warning
        }
    }
    else {
        Write-Log "Installation verification failed" -Level Error
        $script:TasksFailed++
        Stop-Logging -ExitCode 1
    }
    
    # Calculate execution time
    $endTime = Get-Date
    $duration = $endTime - $startTime
    Write-Log ""
    Write-Log "Total execution time: $($duration.TotalSeconds) seconds" -Level Info
    
    Write-Log "Nutanix Guest Tools installation completed successfully" -Level Success
    Stop-Logging -ExitCode 0
}
catch {
    Write-Log "Unhandled exception in main execution: $_" -Level Error
    $script:TasksFailed++
    Stop-Logging -ExitCode 1
}

#endregion
