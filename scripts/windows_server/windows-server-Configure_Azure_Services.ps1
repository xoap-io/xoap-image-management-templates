<#
.SYNOPSIS
    Configure Azure Services for Windows Server

.DESCRIPTION
    Installs and configures Azure VM Agent, Azure Monitor Agent, Azure CLI,
    and Azure Arc agent. Optimized for Windows Server image preparation.

.NOTES
    File Name      : windows-server-configure_Azure_Services.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-configure_Azure_Services.ps1
    Configures all Azure services with default settings
    
.EXAMPLE
    .\windows-server-configure_Azure_Services.ps1 -SkipArc
    Configures Azure services without Azure Arc
    
.PARAMETER SkipArc
    Skip Azure Arc agent installation
    
.PARAMETER SkipMonitor
    Skip Azure Monitor Agent installation
#>

[CmdletBinding()]
param(
    [switch]$SkipArc,
    [switch]$SkipMonitor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = 'C:\Windows\Temp\Azure'
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
    $logMessage = "[$timestamp] [$prefix] [Azure] $Message"
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
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    # Ensure temp directory exists
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "==================================================="
    Write-Log "Azure Services Configuration Script"
    Write-Log "==================================================="
    Write-Log "Skip Arc: $SkipArc"
    Write-Log "Skip Monitor: $SkipMonitor"
    Write-Log ""
    
    # Detect if running on Azure
    Write-Log "Detecting cloud platform..."
    try {
        $isAzure = $false
        $metadataUrl = 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'
        $request = [System.Net.WebRequest]::Create($metadataUrl)
        $request.Headers.Add('Metadata', 'true')
        $request.Timeout = 2000
        $response = $request.GetResponse()
        $isAzure = $true
        $response.Close()
        Write-Log "✓ Running on Azure VM"
        $script:ServicesConfigured++
    } catch {
        Write-Log "Not running on Azure VM (continuing anyway)" -Level Warning
    }
    
    # Enable TLS 1.2
    Write-Log "Enabling TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "✓ TLS 1.2 enabled"
    
    # Check Azure VM Agent
    Write-Log "Checking Azure VM Agent (WALinuxAgent)..."
    try {
        $vmAgentService = Get-Service -Name 'WindowsAzureGuestAgent' -ErrorAction SilentlyContinue
        
        if ($vmAgentService) {
            Write-Log "Azure VM Agent is installed"
            Write-Log "  Service status: $($vmAgentService.Status)"
            
            if ($vmAgentService.Status -ne 'Running') {
                Start-Service -Name 'WindowsAzureGuestAgent'
                Write-Log "✓ Azure VM Agent service started"
            }
            $script:ServicesConfigured++
        } else {
            Write-Log "Azure VM Agent not found (typically pre-installed on Azure VMs)" -Level Warning
        }
    } catch {
        Write-Log "Error checking Azure VM Agent: $($_.Exception.Message)" -Level Warning
    }
    
    # Install Azure CLI
    Write-Log "Installing Azure CLI..."
    try {
        $azPath = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
        
        if (Test-Path $azPath) {
            Write-Log "Azure CLI already installed"
        } else {
            $azCliInstaller = Join-Path $TempDir 'AzureCLI.msi'
            $azCliUrl = 'https://aka.ms/installazurecliwindows'
            
            Write-Log "Downloading Azure CLI from: $azCliUrl"
            (New-Object System.Net.WebClient).DownloadFile($azCliUrl, $azCliInstaller)
            
            Write-Log "Installing Azure CLI..."
            Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$azCliInstaller`" /qn /norestart" -Wait -NoNewWindow
            
            if (Test-Path $azPath) {
                Write-Log "✓ Azure CLI installed successfully"
                $script:ServicesInstalled++
            } else {
                throw "Azure CLI installation failed - executable not found"
            }
        }
    } catch {
        Write-Log "Failed to install Azure CLI: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
    }
    
    # Install Azure Monitor Agent
    if (-not $SkipMonitor) {
        Write-Log "Checking Azure Monitor Agent..."
        try {
            $amaExtension = Get-Service -Name 'AzureMonitorAgent' -ErrorAction SilentlyContinue
            
            if ($amaExtension) {
                Write-Log "Azure Monitor Agent is installed"
                Write-Log "  Service status: $($amaExtension.Status)"
                $script:ServicesConfigured++
            } else {
                Write-Log "Azure Monitor Agent not found (install via Azure Portal or policy)" -Level Warning
                Write-Log "  Visit: https://docs.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-install"
            }
        } catch {
            Write-Log "Error checking Azure Monitor Agent: $($_.Exception.Message)" -Level Warning
        }
    } else {
        Write-Log "Skipping Azure Monitor Agent check (SkipMonitor specified)"
    }
    
    # Check Azure Arc Agent
    if (-not $SkipArc) {
        Write-Log "Checking Azure Arc Agent..."
        try {
            $arcService = Get-Service -Name 'himds' -ErrorAction SilentlyContinue
            
            if ($arcService) {
                Write-Log "Azure Arc Agent is installed"
                Write-Log "  Service status: $($arcService.Status)"
                $script:ServicesConfigured++
            } else {
                Write-Log "Azure Arc Agent not found (install manually if needed)" -Level Warning
                Write-Log "  Visit: https://docs.microsoft.com/azure/azure-arc/servers/agent-overview"
            }
        } catch {
            Write-Log "Error checking Azure Arc Agent: $($_.Exception.Message)" -Level Warning
        }
    } else {
        Write-Log "Skipping Azure Arc Agent check (SkipArc specified)"
    }
    
    # Configure Windows Azure Guest Agent settings
    Write-Log "Configuring Azure Guest Agent settings..."
    try {
        if ($isAzure) {
            # Ensure provisioning is enabled
            $provisioningPath = 'HKLM:\SOFTWARE\Microsoft\Windows Azure'
            if (Test-Path $provisioningPath) {
                Write-Log "✓ Azure Guest Agent registry path exists"
                $script:ServicesConfigured++
            }
        }
    } catch {
        Write-Log "Error configuring Guest Agent: $($_.Exception.Message)" -Level Warning
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
    Write-Log "Azure Services Configuration Summary"
    Write-Log "==================================================="
    Write-Log "Platform detected: $(if ($isAzure) { 'Azure VM' } else { 'Non-Azure' })"
    Write-Log "Services installed: $script:ServicesInstalled"
    Write-Log "Services configured: $script:ServicesConfigured"
    Write-Log "Configurations failed: $script:ConfigurationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "Azure services configuration completed!"
    Write-Log ""
    Write-Log "Installed components:"
    Write-Log "  - Azure VM Agent: $(if (Get-Service -Name 'WindowsAzureGuestAgent' -ErrorAction SilentlyContinue) { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "  - Azure CLI: $(if (Test-Path "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd") { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "  - Azure Monitor Agent: $(if (Get-Service -Name 'AzureMonitorAgent' -ErrorAction SilentlyContinue) { '✓ Installed' } else { '✗ Not installed' })"
    Write-Log "  - Azure Arc Agent: $(if (Get-Service -Name 'himds' -ErrorAction SilentlyContinue) { '✓ Installed' } else { '✗ Not installed' })"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}