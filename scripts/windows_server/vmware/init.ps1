<#
.SYNOPSIS
    Installs VMware Tools on Windows Server 2025

.DESCRIPTION
    This script installs or reinstalls VMware Tools, verifies service status, and logs all actions.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. © RIS AG

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
    https://github.com/xoap-io/xoap-packer-templates

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
    Write-Log "VMware Tools Installation Summary"
    Write-Log "=============================================="
    Write-Log "Install attempts: $script:InstallAttempts"
    Write-Log "Uninstall attempts: $script:UninstallAttempts"
    Write-Log "Service check attempts: $script:ServiceCheckAttempts"
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
    
    Write-Log "Checking for existing VMware Tools installation..." -Level Info
    
    # Check via service
    try {
        $vmToolsService = Get-WmiObject -Class Win32_Service -Filter "Name='$script:VMToolsServiceName'" -ErrorAction SilentlyContinue
        if ($vmToolsService) {
            Write-Log "VMware Tools service detected" -Level Info
            return $true
        }
    }
    catch {
        Write-Log "Service check failed: $($_.Exception.Message)" -Level Warning
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
                Write-Log "VMware Tools found in registry: $($vmToolsFound.DisplayName)" -Level Info
                Write-Log "  Version: $($vmToolsFound.DisplayVersion)" -Level Info
                Write-Log "  Install Location: $($vmToolsFound.InstallLocation)" -Level Info
                return $true
            }
        }
        catch {
            Write-Log "Registry check failed for ${path}: $($_.Exception.Message)" -Level Warning
        }
    }
    
    Write-Log "VMware Tools installation not detected" -Level Info
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
    
    Write-Log "Verifying VMware Tools service status..." -Level Info
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $script:ServiceCheckAttempts++
        
        try {
            $service = Get-Service -Name $script:VMToolsServiceName -ErrorAction Stop
            
            Write-Log "Service status: $($service.Status) (attempt $attempt/$MaxRetries)" -Level Info
            
            if ($service.Status -eq 'Running') {
                Write-Log "VMware Tools service is running" -Level Success
                return $true
            }
            
            if ($service.Status -eq 'Stopped') {
                Write-Log "Attempting to start VMware Tools service..." -Level Warning
                try {
                    Start-Service -Name $script:VMToolsServiceName -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    
                    $service = Get-Service -Name $script:VMToolsServiceName -ErrorAction Stop
                    if ($service.Status -eq 'Running') {
                        Write-Log "Successfully started VMware Tools service" -Level Success
                        return $true
                    }
                }
                catch {
                    Write-Log "Failed to start service: $($_.Exception.Message)" -Level Warning
                }
            }
        }
        catch {
            Write-Log "Service check failed (attempt $attempt/$MaxRetries): $($_.Exception.Message)" -Level Warning
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-Log "Retrying in $RetryInterval seconds..." -Level Info
            Start-Sleep -Seconds $RetryInterval
        }
    }
    
    Write-Log "VMware Tools service is not running after $MaxRetries attempts" -Level Error
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
    
    Write-Log "Searching for VMware Tools installer in: $SetupPath" -Level Info
    
    if (-not (Test-Path $SetupPath)) {
        Write-Log "Setup path does not exist: $SetupPath" -Level Error
        return $null
    }
    
    # Check for 64-bit installer first
    $setup64Path = Join-Path $SetupPath 'setup64.exe'
    if (Test-Path $setup64Path) {
        Write-Log "Found 64-bit installer: $setup64Path" -Level Success
        return $setup64Path
    }
    
    # Check for generic installer
    $setupPath = Join-Path $SetupPath 'setup.exe'
    if (Test-Path $setupPath) {
        Write-Log "Found installer: $setupPath" -Level Success
        return $setupPath
    }
    
    # List available executables
    try {
        $availableFiles = Get-ChildItem -Path $SetupPath -Filter '*.exe' -ErrorAction SilentlyContinue |
                         Select-Object -ExpandProperty Name
        
        if ($availableFiles) {
            Write-Log "Available executables in ${SetupPath}:" -Level Warning
            $availableFiles | ForEach-Object { Write-Log "  - $_" -Level Warning }
        }
        else {
            Write-Log "No executable files found in $SetupPath" -Level Error
        }
    }
    catch {
        Write-Log "Failed to list files in ${SetupPath}: $($_.Exception.Message)" -Level Error
    }
    
    Write-Log "VMware Tools installer not found" -Level Error
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
        Write-Log "Cannot proceed with installation - installer not found" -Level Error
        return $false
    }
    
    Write-Log "Installing VMware Tools..." -Level Info
    Write-Log "  Installer: $installerPath" -Level Info
    Write-Log "  Arguments: /s /v `"/qb REBOOT=R`"" -Level Info
    
    try {
        $process = Start-Process -FilePath $installerPath `
                                -ArgumentList '/s /v "/qb REBOOT=R"' `
                                -Wait `
                                -PassThru `
                                -NoNewWindow `
                                -ErrorAction Stop
        
        Write-Log "Installation process completed with exit code: $($process.ExitCode)" -Level Info
        
        if ($process.ExitCode -eq 0) {
            Write-Log "VMware Tools installation succeeded" -Level Success
            Start-Sleep -Seconds 5  # Allow services to initialize
            return $true
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "Installation succeeded but requires reboot (exit code 3010)" -Level Warning
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Installation exception: $($_.Exception.Message)" -Level Error
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
    
    Write-Log "Initiating VMware Tools uninstallation..." -Level Info
    
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
                Write-Log "Found uninstall entry: $($vmToolsEntry.DisplayName)" -Level Info
                break
            }
        }
        catch {
            Write-Log "Registry access failed: $($_.Exception.Message)" -Level Warning
        }
    }
    
    # Execute MSI uninstall
    if ($vmToolsEntry -and $vmToolsEntry.PSChildName) {
        Write-Log "Executing MSI uninstall: $($vmToolsEntry.PSChildName)" -Level Info
        
        try {
            $process = Start-Process -FilePath 'msiexec.exe' `
                                    -ArgumentList "/X $($vmToolsEntry.PSChildName) /quiet /norestart" `
                                    -Wait `
                                    -PassThru `
                                    -NoNewWindow `
                                    -ErrorAction Stop
            
            Write-Log "Uninstall completed with exit code: $($process.ExitCode)" -Level Info
            
            if ($process.ExitCode -notin @(0, 3010, 1605)) {
                Write-Log "Uninstall returned unexpected exit code: $($process.ExitCode)" -Level Warning
            }
        }
        catch {
            Write-Log "MSI uninstall failed: $($_.Exception.Message)" -Level Warning
        }
    }
    else {
        Write-Log "No uninstall entry found in registry" -Level Warning
    }
    
    # Stop service
    try {
        $service = Get-Service -Name $script:VMToolsServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "Stopping VMware Tools service..." -Level Info
            Stop-Service -Name $script:VMToolsServiceName -Force -ErrorAction Stop
            Write-Log "Service stopped successfully" -Level Success
        }
    }
    catch {
        Write-Log "Service stop failed: $($_.Exception.Message)" -Level Warning
    }
    
    Start-Sleep -Seconds 3
    Write-Log "Uninstallation process completed" -Level Info
    return $true
}

#endregion

#region Main Execution

try {
    # Initialize logging
    Initialize-Logging | Out-Null
    
    Write-Log "=============================================="
    Write-Log "VMware Tools Installation Script"
    Write-Log "=============================================="
    Write-Log "Setup Path: $SetupPath"
    Write-Log "Max Retries: $MaxRetries"
    Write-Log "Retry Interval: $RetryInterval seconds"
    Write-Log "=============================================="
    
    # Check if already installed and running
    if (Test-VMToolsInstalled) {
        Write-Log "VMware Tools installation detected" -Level Info
        
        if (Test-VMToolsService) {
            Write-Log "VMware Tools is properly installed and running" -Level Success
            Stop-Logging -ExitCode 0
        }
        else {
            Write-Log "VMware Tools service is not running properly" -Level Warning
            Write-Log "Initiating reinstallation process..." -Level Info
            
            if (Uninstall-VMwareTools) {
                Write-Log "Uninstallation completed" -Level Success
            }
            else {
                Write-Log "Uninstallation completed with warnings" -Level Warning
            }
        }
    }
    else {
        Write-Log "VMware Tools not detected - proceeding with fresh installation" -Level Info
    }
    
    # Install VMware Tools
    Write-Log "Starting VMware Tools installation..." -Level Info
    if (-not (Install-VMwareTools)) {
        Write-Log "Installation failed" -Level Error
        Stop-Logging -ExitCode 1
    }
    
    # Verify installation
    Write-Log "Performing post-installation verification..." -Level Info
    if (Test-VMToolsService) {
        Write-Log "VMware Tools successfully installed and verified" -Level Success
        Stop-Logging -ExitCode 0
    }
    else {
        Write-Log "Installation completed but service verification failed" -Level Error
        Stop-Logging -ExitCode 1
    }
}
catch {
    Write-Log "Unhandled exception in main execution: $_" -Level Error
    Stop-Logging -ExitCode 1
}

#endregion
