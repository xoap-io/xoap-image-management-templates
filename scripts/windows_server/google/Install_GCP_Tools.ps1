<#
.SYNOPSIS
    Install Google Cloud Tools and Agents

.DESCRIPTION
    Installs essential Google Cloud tools and agents on Windows VMs including:
    - Google Cloud SDK (gcloud CLI)
    - Google Cloud Operations Agent (formerly Stackdriver)
    - Google Cloud PowerShell Module
    
    Verifies installation and configures services for optimal GCE operation.

.NOTES
    File Name      : Install_GCP_Tools.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER InstallSDK
    Install Google Cloud SDK

.PARAMETER InstallOpsAgent
    Install Google Cloud Operations Agent

.PARAMETER InstallPowerShell
    Install Google Cloud PowerShell Module

.EXAMPLE
    .\Install_GCP_Tools.ps1
    Installs all GCP tools with default settings

.EXAMPLE
    .\Install_GCP_Tools.ps1 -InstallSDK -InstallOpsAgent
    Installs only Cloud SDK and Operations Agent

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [switch]$InstallSDK,
    [switch]$InstallOpsAgent,
    [switch]$InstallPowerShell
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = 'gcp-tools-install'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
$TempDir = Join-Path $env:TEMP "gcp-install-$timestamp"

$script:InstallationsCompleted = 0
$script:InstallationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [GCPTools] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    Write-Log "========================================================="
    Write-Log "Google Cloud Tools and Agents Installation"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log ""
    
    # If no specific tool selected, install all
    if (-not ($InstallSDK -or $InstallOpsAgent -or $InstallPowerShell)) {
        $InstallSDK = $true
        $InstallOpsAgent = $true
        $InstallPowerShell = $true
        Write-Log "No specific tools selected - installing all GCP tools"
    }
    
    # Detect GCE environment
    Write-Log "Detecting Google Compute Engine environment..."
    $isGCE = $false
    try {
        $metadata = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/instance/id' `
            -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 2 -ErrorAction Stop
        Write-Log "✓ Running on GCE instance: $metadata"
        
        $zone = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/instance/zone' `
            -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 2 -ErrorAction Stop
        $machineType = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/instance/machine-type' `
            -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 2 -ErrorAction Stop
        
        Write-Log "  Zone: $($zone.Split('/')[-1])"
        Write-Log "  Machine Type: $($machineType.Split('/')[-1])"
        $isGCE = $true
    }
    catch {
        Write-Log "Warning: Not running on GCE instance" -Level Warning
    }
    
    # Install Google Cloud SDK
    if ($InstallSDK) {
        Write-Log ""
        Write-Log "Installing Google Cloud SDK..."
        
        $gcloudPath = "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
        if (Test-Path $gcloudPath) {
            $version = & $gcloudPath version --format="value(version)" 2>&1
            Write-Log "Google Cloud SDK already installed: $version"
        }
        else {
            try {
                $sdkInstaller = Join-Path $TempDir 'GoogleCloudSDKInstaller.exe'
                $sdkUrl = 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe'
                
                Write-Log "Downloading Google Cloud SDK..."
                Invoke-WebRequest -Uri $sdkUrl -OutFile $sdkInstaller -UseBasicParsing
                
                Write-Log "Installing Google Cloud SDK..."
                $process = Start-Process -FilePath $sdkInstaller `
                    -ArgumentList '/S' `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ Google Cloud SDK installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "SDK installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "SDK installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install Google Cloud Operations Agent
    if ($InstallOpsAgent) {
        Write-Log ""
        Write-Log "Installing Google Cloud Operations Agent..."
        
        $opsService = Get-Service -Name 'google-cloud-ops-agent' -ErrorAction SilentlyContinue
        if ($opsService) {
            Write-Log "Operations Agent already installed: $($opsService.Status)"
        }
        else {
            try {
                # Download and run installation script
                Write-Log "Downloading Operations Agent installer..."
                
                $opsInstaller = Join-Path $TempDir 'google-cloud-ops-agent.exe'
                $opsUrl = 'https://dl.google.com/cloudagents/windows/google-cloud-ops-agent.exe'
                
                Invoke-WebRequest -Uri $opsUrl -OutFile $opsInstaller -UseBasicParsing
                
                Write-Log "Installing Operations Agent..."
                $process = Start-Process -FilePath $opsInstaller `
                    -ArgumentList '/S' `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ Operations Agent installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "Operations Agent installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "Operations Agent installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install Google Cloud PowerShell Module
    if ($InstallPowerShell) {
        Write-Log ""
        Write-Log "Installing Google Cloud PowerShell Module..."
        
        try {
            $gcpModule = Get-Module -ListAvailable -Name 'GoogleCloud' -ErrorAction SilentlyContinue
            if ($gcpModule) {
                Write-Log "Google Cloud PowerShell already installed: $($gcpModule.Version)"
            }
            else {
                Write-Log "Installing GoogleCloud PowerShell module..."
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
                Install-Module -Name GoogleCloud -Force -AllowClobber -Scope AllUsers
                Write-Log "✓ Google Cloud PowerShell installed successfully"
                $script:InstallationsCompleted++
            }
        }
        catch {
            Write-Log "PowerShell module installation failed: $($_.Exception.Message)" -Level Error
            $script:InstallationsFailed++
        }
    }
    
    # Verification
    Write-Log ""
    Write-Log "Verifying installations..."
    
    if ($InstallSDK) {
        $gcloudPath = "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
        if (Test-Path $gcloudPath) {
            Write-Log "✓ Google Cloud SDK: Installed"
        }
    }
    
    if ($InstallOpsAgent) {
        $opsService = Get-Service -Name 'google-cloud-ops-agent' -ErrorAction SilentlyContinue
        if ($opsService) {
            Write-Log "✓ Operations Agent: $($opsService.Status)"
        }
    }
    
    if ($InstallPowerShell) {
        $gcpModule = Get-Module -ListAvailable -Name 'GoogleCloud' -ErrorAction SilentlyContinue
        if ($gcpModule) {
            Write-Log "✓ Google Cloud PowerShell: $($gcpModule.Version)"
        }
    }
    
    # Cleanup
    Write-Log ""
    Write-Log "Cleaning up..."
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "GCP Tools Installation Summary"
    Write-Log "========================================================="
    Write-Log "GCE Instance: $isGCE"
    Write-Log "Installations completed: $script:InstallationsCompleted"
    Write-Log "Installation failures: $script:InstallationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
} catch {
    Write-Log "Installation failed: $_" -Level Error
    exit 1
}
