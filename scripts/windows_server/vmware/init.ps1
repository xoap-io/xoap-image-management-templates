<#
.SYNOPSIS
    Installs VMware Tools on Windows Server 2025

.DESCRIPTION
    This script installs or reinstalls VMware Tools, verifies service status, and logs all actions.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER SetupPath
    Path to the VMware Tools installation media. Default: E:

.PARAMETER MaxRetries
    Maximum number of retry attempts for service verification. Default: 5

.PARAMETER RetryInterval
    Interval in seconds between retry attempts. Default: 2

.EXAMPLE
    .\Install_VMware_Tools.ps1
    Installs VMware Tools using default parameters.

.EXAMPLE
    .\Install_VMware_Tools.ps1 -SetupPath "D:" -MaxRetries 10 -RetryInterval 5
    Installs VMware Tools from D: drive with custom retry settings.

.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Path to VMware Tools installation media')]
    [ValidateNotNullOrEmpty()]
    [string]$SetupPath = 'E:',

    [Parameter(HelpMessage = 'Maximum number of service verification retry attempts')]
    [ValidateRange(1, 20)]
    [int]$MaxRetries = 5,

    [Parameter(HelpMessage = 'Interval in seconds between retry attempts')]
    [ValidateRange(1, 30)]
    [int]$RetryInterval = 2
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Script-level variables
$script:VMToolsName = 'VMware Tools'
$script:VMToolsServiceName = 'VMTools'
$script:InstallAttempts = 0
$script:UninstallAttempts = 0
$script:ServiceCheckAttempts = 0
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
    } catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [VMware] Transcript unavailable: $($_.Exception.Message)" }
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
    Write-Host "[$timestamp] [$Level] [VMware] $Message"
}

function Stop-Logging {
    <#
    .SYNOPSIS
        Stops transcript logging and displays summary
    #>
    param([int]$ExitCode = 0)
    
    Write-Log "=============================================="
    Write-Log "VMware Tools Installation Summary"
    Write-Log "=============================================="
    Write-Log "Install attempts: $script:InstallAttempts"
    Write-Log "Uninstall attempts: $script:UninstallAttempts"
    Write-Log "Service check attempts: $script:ServiceCheckAttempts"
    Write-Log "Exit code: $ExitCode"
    Write-Log "=============================================="
    
    Write-Log "===== init complete in $([int]((Get-Date) - $script:startTime).TotalSeconds)s; exit=$ExitCode ====="
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

#region VMware Tools Detection Functions

function Test-VMToolsInstalled {
    <#
    .SYNOPSIS
        Checks if VMware Tools is currently installed on the system
    .OUTPUTS
        Boolean indicating installation status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Log "Checking for existing VMware Tools installation..." -Level INFO
    
    # Check via service
    try {
        $vmToolsService = Get-WmiObject -Class Win32_Service -Filter "Name='$script:VMToolsServiceName'" -ErrorAction SilentlyContinue
        if ($vmToolsService) {
            Write-Log "VMware Tools service detected" -Level INFO
            return $true
        }
    }
    catch {
        Write-Log "Service check failed: $($_.Exception.Message)" -Level WARN
    }
    
    # Check via registry
    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    foreach ($path in $registryPaths) {
        try {
            $vmToolsFound = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                           Where-Object { $_.DisplayName -like "*$script:VMToolsName*" } |
                           Select-Object -First 1
            
            if ($vmToolsFound) {
                Write-Log "VMware Tools found in registry: $($vmToolsFound.DisplayName)" -Level INFO
                Write-Log "  Version: $($vmToolsFound.DisplayVersion)" -Level INFO
                Write-Log "  Install Location: $($vmToolsFound.InstallLocation)" -Level INFO
                return $true
            }
        }
        catch {
            Write-Log "Registry check failed for ${path}: $($_.Exception.Message)" -Level WARN
        }
    }
    
    Write-Log "VMware Tools installation not detected" -Level INFO
    return $false
}

function Test-VMToolsService {
    <#
    .SYNOPSIS
        Verifies VMware Tools service is running
    .OUTPUTS
        Boolean indicating service status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Log "Verifying VMware Tools service status..." -Level INFO
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $script:ServiceCheckAttempts++
        
        try {
            $service = Get-Service -Name $script:VMToolsServiceName -ErrorAction Stop
            
            Write-Log "Service status: $($service.Status) (attempt $attempt/$MaxRetries)" -Level INFO
            
            if ($service.Status -eq 'Running') {
                Write-Log "VMware Tools service is running" -Level INFO
                return $true
            }
            
            if ($service.Status -eq 'Stopped') {
                Write-Log "Attempting to start VMware Tools service..." -Level WARN
                try {
                    Start-Service -Name $script:VMToolsServiceName -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    
                    $service = Get-Service -Name $script:VMToolsServiceName -ErrorAction Stop
                    if ($service.Status -eq 'Running') {
                        Write-Log "Successfully started VMware Tools service" -Level INFO
                        return $true
                    }
                }
                catch {
                    Write-Log "Failed to start service: $($_.Exception.Message)" -Level WARN
                }
            }
        }
        catch {
            Write-Log "Service check failed (attempt $attempt/$MaxRetries): $($_.Exception.Message)" -Level WARN
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-Log "Retrying in $RetryInterval seconds..." -Level INFO
            Start-Sleep -Seconds $RetryInterval
        }
    }
    
    Write-Log "VMware Tools service is not running after $MaxRetries attempts" -Level ERROR
    return $false
}

#endregion

#region Installation Functions

function Get-VMToolsInstaller {
    <#
    .SYNOPSIS
        Locates the VMware Tools installer executable
    .OUTPUTS
        String path to installer or $null if not found
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    Write-Log "Searching for VMware Tools installer in: $SetupPath" -Level INFO
    
    if (-not (Test-Path $SetupPath)) {
        Write-Log "Setup path does not exist: $SetupPath" -Level ERROR
        return $null
    }
    
    # Check for 64-bit installer first
    $setup64Path = Join-Path $SetupPath 'setup64.exe'
    if (Test-Path $setup64Path) {
        Write-Log "Found 64-bit installer: $setup64Path" -Level INFO
        return $setup64Path
    }
    
    # Check for generic installer
    $setupPath = Join-Path $SetupPath 'setup.exe'
    if (Test-Path $setupPath) {
        Write-Log "Found installer: $setupPath" -Level INFO
        return $setupPath
    }
    
    # List available executables
    try {
        $availableFiles = Get-ChildItem -Path $SetupPath -Filter '*.exe' -ErrorAction SilentlyContinue |
                         Select-Object -ExpandProperty Name
        
        if ($availableFiles) {
            Write-Log "Available executables in ${SetupPath}:" -Level WARN
            $availableFiles | ForEach-Object { Write-Log "  - $_" -Level WARN }
        }
        else {
            Write-Log "No executable files found in $SetupPath" -Level ERROR
        }
    }
    catch {
        Write-Log "Failed to list files in ${SetupPath}: $($_.Exception.Message)" -Level ERROR
    }
    
    Write-Log "VMware Tools installer not found" -Level ERROR
    return $null
}

function Install-VMwareTools {
    <#
    .SYNOPSIS
        Installs VMware Tools from the specified setup path
    .OUTPUTS
        Boolean indicating installation success
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $script:InstallAttempts++
    
    $installerPath = Get-VMToolsInstaller
    if (-not $installerPath) {
        Write-Log "Cannot proceed with installation - installer not found" -Level ERROR
        return $false
    }
    
    Write-Log "Installing VMware Tools..." -Level INFO
    Write-Log "  Installer: $installerPath" -Level INFO
    Write-Log "  Arguments: /s /v `"/qb REBOOT=R`"" -Level INFO
    
    try {
        $process = Start-Process -FilePath $installerPath `
                                -ArgumentList '/s /v "/qb REBOOT=R"' `
                                -Wait `
                                -PassThru `
                                -NoNewWindow `
                                -ErrorAction Stop
        
        Write-Log "Installation process completed with exit code: $($process.ExitCode)" -Level INFO
        
        if ($process.ExitCode -eq 0) {
            Write-Log "VMware Tools installation succeeded" -Level INFO
            Start-Sleep -Seconds 5  # Allow services to initialize
            return $true
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "Installation succeeded but requires reboot (exit code 3010)" -Level WARN
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Installation exception: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Uninstall-VMwareTools {
    <#
    .SYNOPSIS
        Uninstalls existing VMware Tools installation
    .OUTPUTS
        Boolean indicating uninstallation success
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $script:UninstallAttempts++
    
    Write-Log "Initiating VMware Tools uninstallation..." -Level INFO
    
    # Find uninstall entry
    $uninstallKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    $vmToolsEntry = $null
    foreach ($path in $uninstallKeys) {
        try {
            $vmToolsEntry = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                           Where-Object { $_.DisplayName -like "*$script:VMToolsName*" } |
                           Select-Object -First 1
            
            if ($vmToolsEntry) {
                Write-Log "Found uninstall entry: $($vmToolsEntry.DisplayName)" -Level INFO
                break
            }
        }
        catch {
            Write-Log "Registry access failed: $($_.Exception.Message)" -Level WARN
        }
    }
    
    # Execute MSI uninstall
    if ($vmToolsEntry -and $vmToolsEntry.PSChildName) {
        Write-Log "Executing MSI uninstall: $($vmToolsEntry.PSChildName)" -Level INFO
        
        try {
            $process = Start-Process -FilePath 'msiexec.exe' `
                                    -ArgumentList "/X $($vmToolsEntry.PSChildName) /quiet /norestart" `
                                    -Wait `
                                    -PassThru `
                                    -NoNewWindow `
                                    -ErrorAction Stop
            
            Write-Log "Uninstall completed with exit code: $($process.ExitCode)" -Level INFO
            
            if ($process.ExitCode -notin @(0, 3010, 1605)) {
                Write-Log "Uninstall returned unexpected exit code: $($process.ExitCode)" -Level WARN
            }
        }
        catch {
            Write-Log "MSI uninstall failed: $($_.Exception.Message)" -Level WARN
        }
    }
    else {
        Write-Log "No uninstall entry found in registry" -Level WARN
    }
    
    # Stop service
    try {
        $service = Get-Service -Name $script:VMToolsServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "Stopping VMware Tools service..." -Level INFO
            Stop-Service -Name $script:VMToolsServiceName -Force -ErrorAction Stop
            Write-Log "Service stopped successfully" -Level INFO
        }
    }
    catch {
        Write-Log "Service stop failed: $($_.Exception.Message)" -Level WARN
    }
    
    Start-Sleep -Seconds 3
    Write-Log "Uninstallation process completed" -Level INFO
    return $true
}

#endregion

#region Main Execution

try {
    # Initialize logging
    Initialize-Logging | Out-Null
    $script:startTime = Get-Date
    Write-Log "===== init starting ====="
    
    Write-Log "=============================================="
    Write-Log "VMware Tools Installation Script"
    Write-Log "=============================================="
    Write-Log "Setup Path: $SetupPath"
    Write-Log "Max Retries: $MaxRetries"
    Write-Log "Retry Interval: $RetryInterval seconds"
    Write-Log "=============================================="
    
    # Check if already installed and running
    if (Test-VMToolsInstalled) {
        Write-Log "VMware Tools installation detected" -Level INFO
        
        if (Test-VMToolsService) {
            Write-Log "VMware Tools is properly installed and running" -Level INFO
            Stop-Logging -ExitCode 0
        }
        else {
            Write-Log "VMware Tools service is not running properly" -Level WARN
            Write-Log "Initiating reinstallation process..." -Level INFO
            
            if (Uninstall-VMwareTools) {
                Write-Log "Uninstallation completed" -Level INFO
            }
            else {
                Write-Log "Uninstallation completed with warnings" -Level WARN
            }
        }
    }
    else {
        Write-Log "VMware Tools not detected - proceeding with fresh installation" -Level INFO
    }
    
    # Install VMware Tools
    Write-Log "Starting VMware Tools installation..." -Level INFO
    if (-not (Install-VMwareTools)) {
        Write-Log "Installation failed" -Level ERROR
        Stop-Logging -ExitCode 1
    }
    
    # Verify installation
    Write-Log "Performing post-installation verification..." -Level INFO
    if (Test-VMToolsService) {
        Write-Log "VMware Tools successfully installed and verified" -Level INFO
        Stop-Logging -ExitCode 0
    }
    else {
        Write-Log "Installation completed but service verification failed" -Level ERROR
        Stop-Logging -ExitCode 1
    }
}
catch {
    Write-Log "Unhandled exception in main execution: $_" -Level ERROR
    Stop-Logging -ExitCode 1
}

#endregion
