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
$script:Component = 'Docker'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [Docker] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

# Main script execution
try {
    $startTime = Get-Date
    Write-Log "===== Install_Docker starting ====="
    
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
    Write-Log "Uninstalling Windows Defender..." -Level WARN
    Uninstall-WindowsFeature Windows-Defender -ErrorAction SilentlyContinue

    # Check if restart is required
    if ($containerFeature.RestartNeeded -eq 'Yes') {
        Write-Log "System restart required. Restart manually after script completion." -Level WARN
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

    Write-Log "===== Install_Docker complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
