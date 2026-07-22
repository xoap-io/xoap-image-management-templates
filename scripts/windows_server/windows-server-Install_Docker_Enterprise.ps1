<#
.SYNOPSIS
    Install Docker Enterprise Edition for Windows Server

.DESCRIPTION
    Installs Docker EE for Windows Server with proper configuration including
    daemon settings, networking, and storage drivers.

.NOTES
    File Name      : windows-server-Install_Docker_Enterprise.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, Windows Server 2016+
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Install_Docker_Enterprise.ps1
    Installs Docker EE with default configuration
#>

[CmdletBinding()]
param(
    [string]$DockerVersion = 'latest'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:Component = 'Docker'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message
    Write-Host $line
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "===== Install_Docker_Enterprise starting (DockerVersion=$DockerVersion) ====="

    # Check OS version
    Write-Log "Checking OS compatibility..."
    $osVersion = [System.Environment]::OSVersion.Version
    Write-Log "OS Version: $($osVersion.Major).$($osVersion.Minor).$($osVersion.Build)"
    
    if ($osVersion.Major -lt 10) {
        throw "Docker requires Windows Server 2016 or later"
    }
    Write-Log "[OK] OS version compatible"
    
    # Install Containers feature
    Write-Log "Installing Containers Windows feature..."
    try {
        $containerFeature = Get-WindowsFeature -Name Containers -ErrorAction Stop
        
        if ($containerFeature.Installed) {
            Write-Log "Containers feature already installed"
        } else {
            Install-WindowsFeature -Name Containers -ErrorAction Stop
            Write-Log "[OK] Containers feature installed"
            Write-Log "Note: A restart may be required"
        }
    } catch {
        Write-Log "Error installing Containers feature: $($_.Exception.Message)" -Level WARN
    }
    
    # Check if Docker is already installed
    Write-Log "Checking for existing Docker installation..."
    $dockerService = Get-Service -Name 'docker' -ErrorAction SilentlyContinue
    
    if ($dockerService) {
        Write-Log "Docker service found"
        
        try {
            $dockerVersion = & docker --version 2>&1
            Write-Log "Installed version: $dockerVersion"
            
            if ($dockerService.Status -ne 'Running') {
                Start-Service -Name 'docker'
                Write-Log "[OK] Docker service started"
            }
        } catch {
            Write-Log "Docker command not available in PATH" -Level WARN
        }
    } else {
        Write-Log "Docker not installed, proceeding with installation..."
        
        # Install Docker using Package Management
        Write-Log "Installing Docker via PackageManagement..."
        
        try {
            # Install DockerMsftProvider
            Write-Log "Installing DockerMsftProvider..."
            Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
            Write-Log "[OK] DockerMsftProvider installed"
            
            # Install Docker package
            Write-Log "Installing Docker package..."
            if ($DockerVersion -eq 'latest') {
                Install-Package -Name docker -ProviderName DockerMsftProvider -Force
            } else {
                Install-Package -Name docker -ProviderName DockerMsftProvider -Force -RequiredVersion $DockerVersion
            }
            Write-Log "[OK] Docker package installed"
            
            # Start Docker service
            Start-Service -Name docker
            Write-Log "[OK] Docker service started"
            
        } catch {
            Write-Log "Error installing Docker: $($_.Exception.Message)" -Level ERROR
            throw
        }
    }
    
    # Verify Docker installation
    Write-Log "Verifying Docker installation..."
    try {
        $dockerInfo = & docker info 2>&1 | Out-String
        Write-Log "Docker Info:"
        $dockerInfo -split "`n" | Select-Object -First 10 | ForEach-Object { Write-Log "  $_" }
        
        $dockerVersion = & docker version --format '{{.Server.Version}}' 2>&1
        Write-Log "Docker Engine Version: $dockerVersion"
        
    } catch {
        Write-Log "Error verifying Docker: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure Docker daemon
    Write-Log "Configuring Docker daemon..."
    
    $daemonConfigPath = 'C:\ProgramData\docker\config\daemon.json'
    $daemonConfigDir = Split-Path -Parent $daemonConfigPath
    
    if (-not (Test-Path $daemonConfigDir)) {
        New-Item -Path $daemonConfigDir -ItemType Directory -Force | Out-Null
    }
    
    $daemonConfig = @{
        'log-driver' = 'json-file'
        'log-opts' = @{
            'max-size' = '10m'
            'max-file' = '3'
        }
        'dns' = @('8.8.8.8', '8.8.4.4')
        'storage-driver' = 'windowsfilter'
        'experimental' = $false
    }
    
    $daemonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $daemonConfigPath -Encoding UTF8
    Write-Log "[OK] Docker daemon configuration created: $daemonConfigPath"
    
    # Restart Docker to apply configuration
    Write-Log "Restarting Docker service to apply configuration..."
    Restart-Service -Name docker -Force
    Start-Sleep -Seconds 5
    Write-Log "[OK] Docker service restarted"
    
    # Configure Docker service
    Write-Log "Configuring Docker service..."
    Set-Service -Name docker -StartupType Automatic
    Write-Log "[OK] Docker service set to automatic startup"
    
    # Configure firewall rules for Docker
    Write-Log "Configuring firewall rules for Docker..."
    try {
        # Docker daemon API
        $ruleName = "Docker-Daemon-API"
        $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        
        if (-not $existingRule) {
            New-NetFirewallRule -Name $ruleName `
                -DisplayName "Docker Daemon API" `
                -Direction Inbound `
                -Action Allow `
                -Protocol TCP `
                -LocalPort 2375 `
                -Profile Any `
                -Enabled False | Out-Null
            Write-Log "[OK] Docker API firewall rule created (disabled by default for security)"
        }
        
    } catch {
        Write-Log "Error configuring firewall: $($_.Exception.Message)" -Level WARN
    }
    
    # Pull base Windows images
    Write-Log "Pulling base Windows container images..."
    try {
        $images = @(
            'mcr.microsoft.com/windows/servercore:ltsc2022',
            'mcr.microsoft.com/windows/nanoserver:ltsc2022'
        )
        
        foreach ($image in $images) {
            Write-Log "Pulling image: $image"
            & docker pull $image 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] $image"
            } else {
                Write-Log "  [FAIL] Failed to pull $image" -Level WARN
            }
        }
        
    } catch {
        Write-Log "Error pulling images: $($_.Exception.Message)" -Level WARN
    }
    
    # Test Docker installation
    Write-Log "Testing Docker installation..."
    try {
        Write-Log "Running test container..."
        $testOutput = & docker run --rm mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c echo "Docker is working" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "[OK] Docker test successful: $testOutput"
        } else {
            Write-Log "Docker test failed" -Level WARN
        }
        
    } catch {
        Write-Log "Error testing Docker: $($_.Exception.Message)" -Level WARN
    }
    
    # Display Docker information
    Write-Log "Docker installation summary:"
    try {
        $dockerService = Get-Service -Name docker
        Write-Log "  Service Status: $($dockerService.Status)"
        Write-Log "  Startup Type: $($dockerService.StartType)"
        
        $images = & docker images --format "{{.Repository}}:{{.Tag}}" 2>&1
        Write-Log "  Images installed: $($images.Count)"
        
    } catch {
        Write-Log "Could not retrieve Docker information" -Level WARN
    }
    
    # Summary
    Write-Log "===== Install_Docker_Enterprise complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}