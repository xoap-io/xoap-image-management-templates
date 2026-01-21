<#
.SYNOPSIS
    Configure Google Cloud Platform Services for Windows Server

.DESCRIPTION
    Installs and configures GCP services including Cloud Ops Agent, Google Cloud SDK,
    GCE metadata service configuration, and OS Config agent.

.NOTES
    File Name      : windows-server-configure_GCP_Services.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-configure_GCP_Services.ps1
    Configures all GCP services with default settings
    
.EXAMPLE
    .\windows-server-configure_GCP_Services.ps1 -SkipOpsAgent
    Configures GCP services without Ops Agent
    
.PARAMETER SkipOpsAgent
    Skip Google Cloud Ops Agent installation
    
.PARAMETER SkipSDK
    Skip Google Cloud SDK installation
#>

[CmdletBinding()]
param(
    [switch]$SkipOpsAgent,
    [switch]$SkipSDK
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = 'C:\Windows\Temp\GCP'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:ServicesConfigured = 0
$script:ServicesInstalled = 0
$script:ConfigurationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [GCP] $Message"
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
    # Ensure directories exist
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "==================================================="
    Write-Log "Google Cloud Platform Services Configuration"
    Write-Log "==================================================="
    Write-Log "Skip Ops Agent: $SkipOpsAgent"
    Write-Log "Skip SDK: $SkipSDK"
    Write-Log ""
    
    # Detect if running on GCP
    Write-Log "Detecting cloud platform..."
    try {
        $isGCP = $false
        $metadataUrl = 'http://metadata.google.internal/computeMetadata/v1/instance/id'
        $request = [System.Net.WebRequest]::Create($metadataUrl)
        $request.Headers.Add('Metadata-Flavor', 'Google')
        $request.Timeout = 2000
        $response = $request.GetResponse()
        $isGCP = $true
        $response.Close()
        Write-Log "✓ Running on Google Compute Engine"
        $script:ServicesConfigured++
    } catch {
        Write-Log "Not running on GCP (continuing anyway)" -Level Warning
    }
    
    # Enable TLS 1.2
    Write-Log "Enabling TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "✓ TLS 1.2 enabled"
    
    # Check GCE Agent
    Write-Log "Checking Google Compute Engine Agent..."
    try {
        $gceService = Get-Service -Name 'GCEAgent' -ErrorAction SilentlyContinue
        
        if ($gceService) {
            Write-Log "GCE Agent is installed"
            Write-Log "  Service status: $($gceService.Status)"
            
            if ($gceService.Status -ne 'Running') {
                Start-Service -Name 'GCEAgent'
                Write-Log "✓ GCE Agent service started"
            }
            $script:ServicesConfigured++
        } else {
            Write-Log "GCE Agent not found (typically pre-installed on GCE instances)" -Level Warning
        }
    } catch {
        Write-Log "Error checking GCE Agent: $($_.Exception.Message)" -Level Warning
    }
    
    # Install Google Cloud SDK
    if (-not $SkipSDK) {
        Write-Log "Installing Google Cloud SDK..."
        try {
            $gcloudPath = "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
            
            if (Test-Path $gcloudPath) {
                Write-Log "Google Cloud SDK already installed"
            } else {
                $sdkInstaller = Join-Path $TempDir 'GoogleCloudSDKInstaller.exe'
                $sdkUrl = 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe'
                
                Write-Log "Downloading Google Cloud SDK from: $sdkUrl"
                (New-Object System.Net.WebClient).DownloadFile($sdkUrl, $sdkInstaller)
                
                Write-Log "Installing Google Cloud SDK..."
                Start-Process -FilePath $sdkInstaller -ArgumentList '/S' -Wait -NoNewWindow
                
                if (Test-Path $gcloudPath) {
                    Write-Log "✓ Google Cloud SDK installed successfully"
                    $script:ServicesInstalled++
                } else {
                    throw "Google Cloud SDK installation failed - gcloud.cmd not found"
                }
            }
        } catch {
            Write-Log "Failed to install Google Cloud SDK: $($_.Exception.Message)" -Level Error
            $script:ConfigurationsFailed++
        }
    } else {
        Write-Log "Skipping Google Cloud SDK installation (SkipSDK specified)"
    }
    
    # Install Google Cloud Ops Agent
    if (-not $SkipOpsAgent) {
        Write-Log "Installing Google Cloud Ops Agent..."
        try {
            $opsAgentService = Get-Service -Name 'google-cloud-ops-agent*' -ErrorAction SilentlyContinue
            
            if ($opsAgentService) {
                Write-Log "Google Cloud Ops Agent already installed"
                Write-Log "  Service status: $($opsAgentService.Status)"
                $script:ServicesConfigured++
            } else {
                Write-Log "Downloading and installing Ops Agent..."
                
                # Download Ops Agent installer script
                $opsAgentScript = Join-Path $TempDir 'add-google-cloud-ops-agent-repo.ps1'
                $opsAgentUrl = 'https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.ps1'
                
                (New-Object System.Net.WebClient).DownloadFile($opsAgentUrl, $opsAgentScript)
                
                # Execute installer
                & $opsAgentScript -AlsoInstall
                
                Start-Sleep -Seconds 5
                
                $opsAgentService = Get-Service -Name 'google-cloud-ops-agent*' -ErrorAction SilentlyContinue
                if ($opsAgentService) {
                    Write-Log "✓ Google Cloud Ops Agent installed successfully"
                    $script:ServicesInstalled++
                } else {
                    Write-Log "Ops Agent installation completed (verify manually)" -Level Warning
                }
            }
        } catch {
            Write-Log "Failed to install Google Cloud Ops Agent: $($_.Exception.Message)" -Level Error
            $script:ConfigurationsFailed++
        }
    } else {
        Write-Log "Skipping Google Cloud Ops Agent installation (SkipOpsAgent specified)"
    }
    
    # Check OS Config Agent
    Write-Log "Checking OS Config Agent..."
    try {
        $osConfigService = Get-Service -Name 'google_osconfig_agent' -ErrorAction SilentlyContinue
        
        if ($osConfigService) {
            Write-Log "OS Config Agent is installed"
            Write-Log "  Service status: $($osConfigService.Status)"
            $script:ServicesConfigured++
        } else {
            Write-Log "OS Config Agent not found (typically pre-installed)" -Level Warning
        }
    } catch {
        Write-Log "Error checking OS Config Agent: $($_.Exception.Message)" -Level Warning
    }
    
    # Configure metadata server access
    Write-Log "Configuring metadata server settings..."
    try {
        if ($isGCP) {
            # Test metadata server connectivity
            $projectId = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/project/project-id' `
                -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 5 -ErrorAction Stop
            
            Write-Log "✓ Metadata server accessible (Project ID: $projectId)"
            $script:ServicesConfigured++
        }
    } catch {
        Write-Log "Could not access metadata server: $($_.Exception.Message)" -Level Warning
    }
    
    # Cleanup temp files
    Write-Log "Cleaning up temporary files..."
    try {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "✓ Temporary files cleaned up"
        }
    } catch {
        Write-Log "Warning: Could not clean up temp files: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "GCP Services Configuration Summary"
    Write-Log "==================================================="
    Write-Log "Platform detected: $(if ($isGCP) { 'Google Compute Engine' } else { 'Non-GCP' })"
    Write-Log "Services installed: $script:ServicesInstalled"
    Write-Log "Services configured: $script:ServicesConfigured"
    Write-Log "Configurations failed: $script:ConfigurationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "GCP services configuration completed!"
    Write-Log ""
    Write-Log "Installed components:"
    Write-Log "  - GCE Agent: $(if (Get-Service -Name 'GCEAgent' -ErrorAction SilentlyContinue) { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "  - Google Cloud SDK: $(if (Test-Path "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd") { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "  - Cloud Ops Agent: $(if (Get-Service -Name 'google-cloud-ops-agent*' -ErrorAction SilentlyContinue) { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "  - OS Config Agent: $(if (Get-Service -Name 'google_osconfig_agent' -ErrorAction SilentlyContinue) { '✓ Installed' } else { '✗ Not installed' })"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}