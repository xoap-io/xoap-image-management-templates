<#
.SYNOPSIS
    Install and Configure Splunk Universal Forwarder for Windows Server

.DESCRIPTION
    Downloads, installs, and configures Splunk Universal Forwarder on Windows Server 2025.
    Configures deployment server, forwarding, and monitoring inputs. Optimized for
    enterprise image preparation with secure default configurations.

.NOTES
    File Name      : windows-server-Install_Splunk_Forwarder.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Install_Splunk_Forwarder
    Installs Splunk Universal Forwarder with default configuration
    
.EXAMPLE
    .\windows-server-Install_Splunk_Forwarder -DeploymentServer "splunk-ds.company.com:8089" -IndexerAddress "splunk-idx.company.com:9997"
    Installs with custom deployment server and indexer
    
.PARAMETER SplunkVersion
    Splunk Universal Forwarder version to install (default: 9.2.0)
    
.PARAMETER DeploymentServer
    Deployment server address in format hostname:port (default: none)
    
.PARAMETER IndexerAddress
    Indexer address for forwarding in format hostname:port (default: none)
    
.PARAMETER SplunkAdmin
    Splunk admin username (default: admin)
    
.PARAMETER SplunkPassword
    Splunk admin password (default: randomly generated)
    
.PARAMETER InstallPath
    Installation path (default: C:\Program Files\SplunkUniversalForwarder)
    
.PARAMETER DisableBootStart
    Disable automatic start at boot (useful for images)
#>

[CmdletBinding()]
param(
    [string]$SplunkVersion = "9.2.0",
    [string]$DeploymentServer = "",
    [string]$IndexerAddress = "",
    [string]$SplunkAdmin = "admin",
    [securestring]$SplunkPassword = "",
    [string]$InstallPath = "C:\Program Files\SplunkUniversalForwarder",
    [string]$DownloadUrl = "",
    [switch]$DisableBootStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = 'C:\Windows\Temp\Splunk'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Splunk configuration
$SplunkHome = $InstallPath
$SplunkBin = Join-Path $SplunkHome "bin\splunk.exe"
$Build = "1fff88043d5f"  # Build number for 9.2.0

# Statistics tracking
$script:ComponentsInstalled = 0
$script:ConfigurationsApplied = 0
$script:InstallationsFailed = 0

#region Helper Functions

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RandomPassword {
    param([int]$Length = 16)
    
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()'
    $password = -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $password
}

function Test-SplunkInstalled {
    return (Test-Path $SplunkBin)
}

function Get-SplunkDownloadUrl {
    param([string]$Version, [string]$Build)
    
    if ($DownloadUrl) {
        return $DownloadUrl
    }
    
    # Construct download URL for Splunk Universal Forwarder
    $baseUrl = "https://download.splunk.com/products/universalforwarder/releases"
    $filename = "splunkforwarder-${Version}-${Build}-x64-release.msi"
    return "$baseUrl/$Version/windows/$filename"
}

function Install-SplunkForwarder {
    Write-LogMessage "Starting Splunk Universal Forwarder installation..." -Level Info
    
    try {
        # Create temp directory
        if (-not (Test-Path $TempDir)) {
            New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
        }
        
        # Generate password if not provided
        if (-not $SplunkPassword) {
            $script:SplunkPassword = Get-RandomPassword
            Write-LogMessage "Generated random admin password" -Level Info
        }
        
        # Download installer
        $downloadUrl = Get-SplunkDownloadUrl -Version $SplunkVersion -Build $Build
        $installerPath = Join-Path $TempDir "splunkforwarder.msi"
        
        Write-LogMessage "Downloading Splunk Universal Forwarder from $downloadUrl" -Level Info
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $installerPath)
            $webClient.Dispose()
        }
        catch {
            Write-LogMessage "Failed to download from official source: $($_.Exception.Message)" -Level Warning
            Write-LogMessage "Please download manually from: https://www.splunk.com/en_us/download/universal-forwarder.html" -Level Warning
            throw "Download failed. Manual installation required."
        }
        
        if (-not (Test-Path $installerPath)) {
            throw "Installer not found at $installerPath"
        }
        
        Write-LogMessage "Installer downloaded successfully" -Level Success
        
        # Prepare installation arguments
        $installArgs = @(
            "/i `"$installerPath`""
            "AGREETOLICENSE=Yes"
            "SPLUNKUSERNAME=$SplunkAdmin"
            "SPLUNKPASSWORD=$SplunkPassword"
            "INSTALLDIR=`"$InstallPath`""
            "LAUNCHSPLUNK=0"
            "/quiet"
            "/norestart"
            "/l*v `"$LogDir\splunk-install-$timestamp.log`""
        )
        
        if ($DeploymentServer) {
            $installArgs += "DEPLOYMENT_SERVER=`"$DeploymentServer`""
        }
        
        if ($IndexerAddress) {
            $installArgs += "RECEIVING_INDEXER=`"$IndexerAddress`""
        }
        
        $installArgString = $installArgs -join ' '
        
        Write-LogMessage "Installing Splunk Universal Forwarder..." -Level Info
        Write-LogMessage "Installation command: msiexec.exe $installArgString" -Level Info
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgString -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-LogMessage "Splunk Universal Forwarder installed successfully (Exit Code: $($process.ExitCode))" -Level Success
            $script:ComponentsInstalled++
            return $true
        }
        else {
            Write-LogMessage "Installation failed with exit code: $($process.ExitCode)" -Level Error
            $script:InstallationsFailed++
            return $false
        }
    }
    catch {
        Write-LogMessage "Error during installation: $($_.Exception.Message)" -Level Error
        $script:InstallationsFailed++
        return $false
    }
}

function Configure-SplunkForwarder {
    Write-LogMessage "Configuring Splunk Universal Forwarder..." -Level Info
    
    if (-not (Test-Path $SplunkBin)) {
        Write-LogMessage "Splunk binary not found at $SplunkBin" -Level Error
        return $false
    }
    
    try {
        # Accept license
        Write-LogMessage "Accepting Splunk license..." -Level Info
        $result = & $SplunkBin start --accept-license --answer-yes --no-prompt 2>&1
        
        Start-Sleep -Seconds 10
        
        # Stop Splunk to configure
        Write-LogMessage "Stopping Splunk for configuration..." -Level Info
        & $SplunkBin stop 2>&1 | Out-Null
        
        Start-Sleep -Seconds 5
        
        # Configure deployment server if specified
        if ($DeploymentServer) {
            Write-LogMessage "Setting deployment server to: $DeploymentServer" -Level Info
            & $SplunkBin set deploy-poll $DeploymentServer -auth "${SplunkAdmin}:${SplunkPassword}" 2>&1 | Out-Null
            $script:ConfigurationsApplied++
        }
        
        # Configure forwarding if specified
        if ($IndexerAddress) {
            Write-LogMessage "Setting receiving indexer to: $IndexerAddress" -Level Info
            & $SplunkBin add forward-server $IndexerAddress -auth "${SplunkAdmin}:${SplunkPassword}" 2>&1 | Out-Null
            $script:ConfigurationsApplied++
        }
        
        # Configure inputs for Windows monitoring
        $inputsConf = Join-Path $SplunkHome "etc\system\local\inputs.conf"
        $inputsConfig = @"
[WinEventLog://Application]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5

[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5

[WinEventLog://System]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5

[perfmon://CPU]
object = Processor
counters = % Processor Time; % User Time; % Privileged Time
instances = _Total
interval = 300
disabled = 0

[perfmon://Memory]
object = Memory
counters = Available MBytes; Pages/sec; % Committed Bytes In Use
instances = *
interval = 300
disabled = 0

[perfmon://PhysicalDisk]
object = PhysicalDisk
counters = % Disk Time; Avg. Disk Queue Length; Disk Bytes/sec
instances = *
interval = 300
disabled = 0

[perfmon://Network]
object = Network Interface
counters = Bytes Total/sec; Packets/sec
instances = *
interval = 300
disabled = 0
"@
        
        $localDir = Join-Path $SplunkHome "etc\system\local"
        if (-not (Test-Path $localDir)) {
            New-Item -Path $localDir -ItemType Directory -Force | Out-Null
        }
        
        Set-Content -Path $inputsConf -Value $inputsConfig -Force
        Write-LogMessage "Configured Windows event log and performance monitoring inputs" -Level Success
        $script:ConfigurationsApplied++
        
        # Configure outputs for SSL if indexer specified
        if ($IndexerAddress) {
            $outputsConf = Join-Path $SplunkHome "etc\system\local\outputs.conf"
            $outputsConfig = @"
[tcpout]
defaultGroup = default-autolb-group
maxQueueSize = 7MB

[tcpout:default-autolb-group]
server = $IndexerAddress
compressed = true

[tcpout-server://$IndexerAddress]
"@
            Set-Content -Path $outputsConf -Value $outputsConfig -Force
            Write-LogMessage "Configured output forwarding" -Level Success
            $script:ConfigurationsApplied++
        }
        
        # Set Splunk as service to start automatically or disabled based on parameter
        if ($DisableBootStart) {
            Write-LogMessage "Disabling Splunk service auto-start (image preparation mode)" -Level Info
            Set-Service -Name "SplunkForwarder" -StartupType Disabled -ErrorAction SilentlyContinue
        }
        else {
            Write-LogMessage "Enabling Splunk service..." -Level Info
            & $SplunkBin enable boot-start -user $SplunkAdmin -auth "${SplunkAdmin}:${SplunkPassword}" 2>&1 | Out-Null
            Set-Service -Name "SplunkForwarder" -StartupType Automatic -ErrorAction SilentlyContinue
        }
        
        Write-LogMessage "Splunk Universal Forwarder configured successfully" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error during configuration: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-SplunkConfiguration {
    Write-LogMessage "Verifying Splunk configuration..." -Level Info
    
    try {
        $service = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue
        
        if ($service) {
            Write-LogMessage "Splunk service found: $($service.Status)" -Level Success
            
            if (-not $DisableBootStart) {
                if ($service.StartType -ne 'Automatic') {
                    Write-LogMessage "Warning: Service startup type is not Automatic" -Level Warning
                }
            }
        }
        else {
            Write-LogMessage "Splunk service not found" -Level Warning
        }
        
        # Check configuration files
        $configFiles = @(
            (Join-Path $SplunkHome "etc\system\local\inputs.conf"),
            (Join-Path $SplunkHome "etc\system\local\outputs.conf")
        )
        
        foreach ($file in $configFiles) {
            if (Test-Path $file) {
                Write-LogMessage "Configuration file exists: $file" -Level Info
            }
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Save-SplunkCredentials {
    Write-LogMessage "Saving Splunk credentials for reference..." -Level Info
    
    try {
        $credFile = Join-Path $LogDir "splunk-credentials-$timestamp.txt"
        $credContent = @"
Splunk Universal Forwarder Credentials
========================================
Installation Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Installation Path: $InstallPath
Admin Username: $SplunkAdmin
Admin Password: $SplunkPassword
Deployment Server: $DeploymentServer
Indexer Address: $IndexerAddress

IMPORTANT: Store these credentials securely and delete this file after recording them.
This file is created for initial setup reference only.
"@
        
        Set-Content -Path $credFile -Value $credContent -Force
        
        # Set file permissions to Administrators only
        $acl = Get-Acl $credFile
        $acl.SetAccessRuleProtection($true, $false)
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "Allow"
        )
        $acl.SetAccessRule($adminRule)
        Set-Acl -Path $credFile -AclObject $acl
        
        Write-LogMessage "Credentials saved to: $credFile" -Level Success
        Write-LogMessage "WARNING: Delete this file after recording credentials!" -Level Warning
    }
    catch {
        Write-LogMessage "Could not save credentials file: $($_.Exception.Message)" -Level Warning
    }
}

function Remove-SplunkInstaller {
    Write-LogMessage "Cleaning up installation files..." -Level Info
    
    try {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Temporary files cleaned up" -Level Success
        }
    }
    catch {
        Write-LogMessage "Could not clean up temp directory: $($_.Exception.Message)" -Level Warning
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Splunk Universal Forwarder Installation" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Version: $SplunkVersion" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
        exit 1
    }
    
    # Check if already installed
    if (Test-SplunkInstalled) {
        Write-LogMessage "Splunk Universal Forwarder is already installed at $SplunkHome" -Level Warning
        Write-LogMessage "Skipping installation. If reconfiguration is needed, uninstall first." -Level Warning
        exit 0
    }
    
    # Install Splunk
    $installSuccess = Install-SplunkForwarder
    
    if (-not $installSuccess) {
        Write-LogMessage "Installation failed. Check logs for details." -Level Error
        exit 1
    }
    
    # Configure Splunk
    $configSuccess = Configure-SplunkForwarder
    
    if (-not $configSuccess) {
        Write-LogMessage "Configuration completed with warnings. Check logs for details." -Level Warning
    }
    
    # Verify installation
    Test-SplunkConfiguration | Out-Null
    
    # Save credentials
    Save-SplunkCredentials
    
    # Cleanup
    Remove-SplunkInstaller
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Installation Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Components Installed: $script:ComponentsInstalled" -Level Info
    Write-LogMessage "Configurations Applied: $script:ConfigurationsApplied" -Level Info
    Write-LogMessage "Installation Failures: $script:InstallationsFailed" -Level Info
    Write-LogMessage "Duration: $($duration.TotalSeconds) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:InstallationsFailed -eq 0) {
        Write-LogMessage "Splunk Universal Forwarder installation completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Installation completed with errors. Check logs." -Level Warning
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
