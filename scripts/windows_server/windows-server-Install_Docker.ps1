<#
.SYNOPSIS
    Install Docker on Windows Server

.DESCRIPTION
    Installs Docker Engine on Windows Server 2025 with Containers feature.
    WARNING: This script will restart the computer and uninstall Windows Defender.

.NOTES
    File Name      : windows-server-install_docker.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_docker.ps1
    Installs Docker and required components
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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
    Write-Host "[$timestamp] [$prefix] [Docker] $Message"
}

# Main script execution
try {
    Write-Log "Starting Docker installation process..."
    
    # Set PowerShell as default shell
    Write-Log "Setting PowerShell as default shell..."
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -Value 'PowerShell.exe -noExit'

    # Install Containers feature
    Write-Log "Installing Containers Windows feature..."
    $containerFeature = Install-WindowsFeature -Name Containers -ErrorAction Stop
    if ($containerFeature.Success) {
        Write-Log "Containers feature installed successfully"
    }

    # Uninstall Windows Defender (optional - can be commented out)
    Write-Log "Uninstalling Windows Defender..." -Level Warning
    Uninstall-WindowsFeature Windows-Defender -ErrorAction SilentlyContinue

    # Check if restart is required
    if ($containerFeature.RestartNeeded -eq 'Yes') {
        Write-Log "System restart required. Restart manually after script completion." -Level Warning
    }

    # Install Docker provider
    Write-Log "Installing DockerMsftProvider module..."
    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force -ErrorAction Stop

    # Install Docker
    Write-Log "Installing Docker package..."
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force -RequiredVersion 18.03 -ErrorAction Stop

    # Start Docker service
    Write-Log "Starting Docker service..."
    Start-Service docker -ErrorAction Stop
    
    # Verify Docker is running
    $dockerService = Get-Service docker -ErrorAction Stop
    if ($dockerService.Status -eq 'Running') {
        Write-Log "Docker service is running successfully"
    }

    # Initialize Docker Swarm
    Write-Log "Initializing Docker Swarm..."
    $swarmResult = docker swarm init --advertise-addr 127.0.0.1 2>&1
    Write-Log "Docker Swarm initialized: $swarmResult"

    Write-Log "Docker installation and configuration complete"

} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
