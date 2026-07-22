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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [GCP] $Message"
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

# Main execution
try {
    # Setup local file logging to C:\xoap-logs (transcript captures all host output)
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
    } catch {
        Write-Host "[WARN] Failed to start transcript logging to $LogDir : $($_.Exception.Message)"
    }

    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }

    $startTime = Get-Date

    Write-Log "===== Configure_GCP_Services starting (SkipOpsAgent=$SkipOpsAgent, SkipSDK=$SkipSDK) ====="

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
        Write-Log "[OK] Running on Google Compute Engine"
        $script:ServicesConfigured++
    } catch {
        Write-Log "Not running on GCP (continuing anyway)" -Level WARN
    }
    
    # Enable TLS 1.2
    Write-Log "Enabling TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "[OK] TLS 1.2 enabled"
    
    # Check GCE Agent
    Write-Log "Checking Google Compute Engine Agent..."
    try {
        $gceService = Get-Service -Name 'GCEAgent' -ErrorAction SilentlyContinue
        
        if ($gceService) {
            Write-Log "GCE Agent is installed"
            Write-Log "  Service status: $($gceService.Status)"
            
            if ($gceService.Status -ne 'Running') {
                Start-Service -Name 'GCEAgent'
                Write-Log "[OK] GCE Agent service started"
            }
            $script:ServicesConfigured++
        } else {
            Write-Log "GCE Agent not found (typically pre-installed on GCE instances)" -Level WARN
        }
    } catch {
        Write-Log "Error checking GCE Agent: $($_.Exception.Message)" -Level WARN
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
                    Write-Log "[OK] Google Cloud SDK installed successfully"
                    $script:ServicesInstalled++
                } else {
                    throw "Google Cloud SDK installation failed - gcloud.cmd not found"
                }
            }
        } catch {
            Write-Log "Failed to install Google Cloud SDK: $($_.Exception.Message)" -Level ERROR
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
                    Write-Log "[OK] Google Cloud Ops Agent installed successfully"
                    $script:ServicesInstalled++
                } else {
                    Write-Log "Ops Agent installation completed (verify manually)" -Level WARN
                }
            }
        } catch {
            Write-Log "Failed to install Google Cloud Ops Agent: $($_.Exception.Message)" -Level ERROR
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
            Write-Log "OS Config Agent not found (typically pre-installed)" -Level WARN
        }
    } catch {
        Write-Log "Error checking OS Config Agent: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure metadata server access
    Write-Log "Configuring metadata server settings..."
    try {
        if ($isGCP) {
            # Test metadata server connectivity
            $projectId = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/project/project-id' `
                -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 5 -ErrorAction Stop
            
            Write-Log "[OK] Metadata server accessible (Project ID: $projectId)"
            $script:ServicesConfigured++
        }
    } catch {
        Write-Log "Could not access metadata server: $($_.Exception.Message)" -Level WARN
    }
    
    # Cleanup temp files
    Write-Log "Cleaning up temporary files..."
    try {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "[OK] Temporary files cleaned up"
        }
    } catch {
        Write-Log "Warning: Could not clean up temp files: $($_.Exception.Message)" -Level WARN
    }
    
    # Summary
    $duration = ((Get-Date) - $startTime).TotalSeconds

    Write-Log "Platform detected: $(if ($isGCP) { 'Google Compute Engine' } else { 'Non-GCP' })"
    Write-Log "Installed components:"
    Write-Log "  - GCE Agent: $(if (Get-Service -Name 'GCEAgent' -ErrorAction SilentlyContinue) { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "  - Google Cloud SDK: $(if (Test-Path "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd") { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "  - Cloud Ops Agent: $(if (Get-Service -Name 'google-cloud-ops-agent*' -ErrorAction SilentlyContinue) { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "  - OS Config Agent: $(if (Get-Service -Name 'google_osconfig_agent' -ErrorAction SilentlyContinue) { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "===== Configure_GCP_Services complete in $([int]$duration)s; installed=$($script:ServicesInstalled) configured=$($script:ServicesConfigured) failed=$($script:ConfigurationsFailed) ====="

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit 0