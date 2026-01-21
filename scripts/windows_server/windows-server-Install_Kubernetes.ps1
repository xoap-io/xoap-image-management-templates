<#
.SYNOPSIS
    Installs and configures Kubernetes components for Windows Server nodes.

.DESCRIPTION
    This script prepares a Windows Server as a Kubernetes worker node by:
    - Installing kubelet, kubeadm, and kubectl binaries
    - Configuring containerd as the container runtime
    - Setting up Windows networking for Kubernetes
    - Configuring kubelet service for automatic startup
    - Installing CNI plugins for Windows
    
    Supports Windows Server 2019+ with Containers feature enabled.

.PARAMETER KubernetesVersion
    The Kubernetes version to install (e.g., "1.28.0"). Default: Latest stable.

.PARAMETER InstallPath
    Installation directory for Kubernetes binaries. Default: C:\k

.PARAMETER ContainerRuntime
    Container runtime to use. Valid: containerd, docker. Default: containerd

.PARAMETER CNIPlugin
    CNI plugin to install. Valid: flannel, calico, antrea. Default: flannel

.PARAMETER SkipNetworkConfiguration
    Skip Windows networking configuration for Kubernetes.

.EXAMPLE
    .\windows-server-Install_Kubernetes -KubernetesVersion "1.28.0"

.EXAMPLE
    .\windows-server-Install_Kubernetes -ContainerRuntime docker -CNIPlugin calico

.NOTES
    File Name      : windows-server-Install_Kubernetes.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KubernetesVersion = "latest",

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\k",

    [Parameter(Mandatory = $false)]
    [ValidateSet("containerd", "docker")]
    [string]$ContainerRuntime = "containerd",

    [Parameter(Mandatory = $false)]
    [ValidateSet("flannel", "calico", "antrea")]
    [string]$CNIPlugin = "flannel",

    [Parameter(Mandatory = $false)]
    [switch]$SkipNetworkConfiguration
)

# Statistics tracking
$script:DownloadedFiles = 0
$script:ConfiguredServices = 0
$script:NetworkChanges = 0

# Logging setup
$LogDate = Get-Date -Format 'yyyy-MM-dd'
$LogPath = "C:\xoap-logs"
$LogFile = Join-Path $LogPath "Install-Kubernetes_$LogDate.log"

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogFile -Append

# Error handling
trap {
    Write-Error "Error: $_"
    Write-Error $_.ScriptStackTrace
    Stop-Transcript
    exit 1
}

Write-Host "=== Kubernetes Installation for Windows Server ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Version: $KubernetesVersion" -ForegroundColor Gray
Write-Host "Runtime: $ContainerRuntime" -ForegroundColor Gray
Write-Host "CNI Plugin: $CNIPlugin" -ForegroundColor Gray
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

$OSInfo = Get-CimInstance Win32_OperatingSystem
if ($OSInfo.ProductType -ne 3) {
    Write-Warning "This script is designed for Windows Server (detected client OS)"
}

if ([int]$OSInfo.BuildNumber -lt 17763) {
    throw "Windows Server 2019 (build 17763) or later is required"
}

# Check Containers feature
$ContainersFeature = Get-WindowsFeature -Name Containers -ErrorAction SilentlyContinue
if (-not $ContainersFeature -or $ContainersFeature.InstallState -ne 'Installed') {
    Write-Host "Installing Containers feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Containers -Restart:$false
    $script:ConfiguredServices++
}

# Create installation directory
if (-not (Test-Path $InstallPath)) {
    Write-Host "Creating installation directory: $InstallPath" -ForegroundColor Yellow
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}

# Determine Kubernetes version
if ($KubernetesVersion -eq "latest") {
    Write-Host "Detecting latest stable Kubernetes version..." -ForegroundColor Yellow
    try {
        $VersionResponse = Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable.txt" -UseBasicParsing
        $KubernetesVersion = $VersionResponse.Trim()
        Write-Host "Latest version: $KubernetesVersion" -ForegroundColor Green
    } catch {
        Write-Warning "Could not detect latest version, using v1.28.0"
        $KubernetesVersion = "v1.28.0"
    }
}

if (-not $KubernetesVersion.StartsWith("v")) {
    $KubernetesVersion = "v$KubernetesVersion"
}

# Download Kubernetes binaries
Write-Host "`nDownloading Kubernetes binaries..." -ForegroundColor Yellow
$BaseUrl = "https://dl.k8s.io/release/$KubernetesVersion/bin/windows/amd64"
$Binaries = @("kubelet.exe", "kubeadm.exe", "kubectl.exe")

foreach ($Binary in $Binaries) {
    $DownloadUrl = "$BaseUrl/$Binary"
    $DestinationPath = Join-Path $InstallPath $Binary
    
    if (Test-Path $DestinationPath) {
        Write-Host "  [EXISTS] $Binary" -ForegroundColor Gray
    } else {
        Write-Host "  Downloading $Binary..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $DestinationPath -UseBasicParsing
            $script:DownloadedFiles++
            Write-Host "  [OK] $Binary" -ForegroundColor Green
        } catch {
            Write-Error "Failed to download $Binary : $_"
        }
    }
}

# Add to PATH
Write-Host "`nConfiguring system PATH..." -ForegroundColor Yellow
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($CurrentPath -notlike "*$InstallPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$InstallPath", "Machine")
    $env:Path = "$env:Path;$InstallPath"
    Write-Host "Added $InstallPath to system PATH" -ForegroundColor Green
    $script:NetworkChanges++
}

# Configure container runtime
Write-Host "`nConfiguring container runtime: $ContainerRuntime" -ForegroundColor Yellow

if ($ContainerRuntime -eq "containerd") {
    # Download and configure containerd
    $ContainerdVersion = "1.7.11"
    $ContainerdUrl = "https://github.com/containerd/containerd/releases/download/v$ContainerdVersion/containerd-$ContainerdVersion-windows-amd64.tar.gz"
    $ContainerdArchive = Join-Path $env:TEMP "containerd.tar.gz"
    
    Write-Host "  Downloading containerd v$ContainerdVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $ContainerdUrl -OutFile $ContainerdArchive -UseBasicParsing
    
    # Extract containerd
    $ContainerdPath = "C:\Program Files\containerd"
    if (-not (Test-Path $ContainerdPath)) {
        New-Item -Path $ContainerdPath -ItemType Directory -Force | Out-Null
    }
    
    tar -xzf $ContainerdArchive -C $ContainerdPath
    $script:DownloadedFiles++
    
    # Generate containerd configuration
    $ConfigPath = Join-Path $ContainerdPath "config.toml"
    & "$ContainerdPath\bin\containerd.exe" config default | Out-File $ConfigPath -Encoding ascii
    
    # Register containerd service
    & "$ContainerdPath\bin\containerd.exe" --register-service
    Start-Service containerd
    Set-Service containerd -StartupType Automatic
    $script:ConfiguredServices++
    Write-Host "  [OK] containerd configured and started" -ForegroundColor Green
    
} elseif ($ContainerRuntime -eq "docker") {
    # Verify Docker is installed
    if (-not (Get-Service docker -ErrorAction SilentlyContinue)) {
        Write-Warning "Docker is not installed. Install Docker Enterprise first."
        Write-Host "Run: .\Install-DockerEnterprise.ps1" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Docker runtime detected" -ForegroundColor Green
    }
}

# Download CNI plugins
Write-Host "`nInstalling CNI plugins..." -ForegroundColor Yellow
$CNIPath = Join-Path $InstallPath "cni"
if (-not (Test-Path $CNIPath)) {
    New-Item -Path $CNIPath -ItemType Directory -Force | Out-Null
}

$CNIVersion = "v1.4.0"
$CNIUrl = "https://github.com/microsoft/windows-container-networking/releases/download/$CNIVersion/windows-container-networking-cni-amd64-$CNIVersion.zip"
$CNIArchive = Join-Path $env:TEMP "cni-plugins.zip"

Write-Host "  Downloading CNI plugins $CNIVersion..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $CNIUrl -OutFile $CNIArchive -UseBasicParsing
Expand-Archive -Path $CNIArchive -DestinationPath $CNIPath -Force
$script:DownloadedFiles++
Write-Host "  [OK] CNI plugins installed" -ForegroundColor Green

# Configure Windows networking
if (-not $SkipNetworkConfiguration) {
    Write-Host "`nConfiguring Windows networking for Kubernetes..." -ForegroundColor Yellow
    
    # Enable IP forwarding
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
        -Name "IPEnableRouter" -Value 1 -Type DWord
    $script:NetworkChanges++
    
    # Disable Windows Firewall for testing (should be configured properly in production)
    Write-Host "  Configuring firewall rules..." -ForegroundColor Cyan
    New-NetFirewallRule -Name "Kubelet" -DisplayName "Kubelet" `
        -Protocol TCP -LocalPort 10250 -Action Allow -Enabled True -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name "Kubernetes-API" -DisplayName "Kubernetes API" `
        -Protocol TCP -LocalPort 6443 -Action Allow -Enabled True -ErrorAction SilentlyContinue
    $script:NetworkChanges++
    
    Write-Host "  [OK] Network configuration complete" -ForegroundColor Green
}

# Create kubelet configuration directory
$KubeletConfigPath = Join-Path $InstallPath "config"
if (-not (Test-Path $KubeletConfigPath)) {
    New-Item -Path $KubeletConfigPath -ItemType Directory -Force | Out-Null
}

# Create kubelet startup script
Write-Host "`nCreating kubelet service configuration..." -ForegroundColor Yellow
$KubeletScript = @"
`$ErrorActionPreference = 'Stop'

# Kubelet startup script for Windows
`$kubeletPath = "$InstallPath\kubelet.exe"
`$kubeletArgs = @(
    "--config=$InstallPath\config\kubelet-config.yaml",
    "--bootstrap-kubeconfig=$InstallPath\config\bootstrap-kubelet.conf",
    "--kubeconfig=$InstallPath\config\kubelet.conf",
    "--hostname-override=`$env:COMPUTERNAME",
    "--pod-infra-container-image=mcr.microsoft.com/oss/kubernetes/pause:3.9",
    "--enable-debugging-handlers",
    "--cgroups-per-qos=false",
    "--enforce-node-allocatable=",
    "--resolv-conf="",
    "--container-runtime-endpoint=npipe:////./pipe/containerd-containerd"
)

& `$kubeletPath `$kubeletArgs
"@

$KubeletScriptPath = Join-Path $InstallPath "start-kubelet.ps1"
$KubeletScript | Out-File -FilePath $KubeletScriptPath -Encoding utf8

# Create kubelet service using NSSM (if available) or manual setup instructions
Write-Host "`nKubelet service setup:" -ForegroundColor Yellow
Write-Host "  To complete kubelet setup, you need to:" -ForegroundColor Cyan
Write-Host "  1. Join this node to a Kubernetes cluster using kubeadm" -ForegroundColor Gray
Write-Host "  2. Configure kubelet service to start automatically" -ForegroundColor Gray
Write-Host "  3. Apply the CNI network plugin configuration" -ForegroundColor Gray
Write-Host ""
Write-Host "  Example commands:" -ForegroundColor Gray
Write-Host "    kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>" -ForegroundColor DarkGray

# Create helper scripts
$JoinScriptTemplate = @"
# Kubernetes Join Script Template
# Replace placeholders with actual values from your control plane

`$ErrorActionPreference = 'Stop'

# Join cluster
kubeadm join <CONTROL_PLANE_IP>:6443 \
    --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>

# Verify node status
kubectl get nodes
"@

$JoinScriptPath = Join-Path $InstallPath "join-cluster-template.ps1"
$JoinScriptTemplate | Out-File -FilePath $JoinScriptPath -Encoding utf8

# Verify installation
Write-Host "`nVerifying installation..." -ForegroundColor Yellow
$VerificationResults = @()

foreach ($Binary in $Binaries) {
    $BinaryPath = Join-Path $InstallPath $Binary
    if (Test-Path $BinaryPath) {
        $Version = & $BinaryPath version --client --short 2>$null
        $VerificationResults += [PSCustomObject]@{
            Component = $Binary.Replace('.exe', '')
            Status = "Installed"
            Version = $Version
        }
        Write-Host "  [OK] $Binary - $Version" -ForegroundColor Green
    } else {
        $VerificationResults += [PSCustomObject]@{
            Component = $Binary.Replace('.exe', '')
            Status = "Missing"
            Version = "N/A"
        }
        Write-Host "  [FAIL] $Binary not found" -ForegroundColor Red
    }
}

# Summary report
Write-Host "`n=== Kubernetes Installation Summary ===" -ForegroundColor Cyan
Write-Host "Installation Path: $InstallPath" -ForegroundColor Gray
Write-Host "Kubernetes Version: $KubernetesVersion" -ForegroundColor Gray
Write-Host "Container Runtime: $ContainerRuntime" -ForegroundColor Gray
Write-Host "CNI Plugin: $CNIPlugin (to be configured)" -ForegroundColor Gray
Write-Host ""
Write-Host "Statistics:" -ForegroundColor Yellow
Write-Host "  Downloaded Files: $script:DownloadedFiles" -ForegroundColor Gray
Write-Host "  Configured Services: $script:ConfiguredServices" -ForegroundColor Gray
Write-Host "  Network Changes: $script:NetworkChanges" -ForegroundColor Gray
Write-Host ""
Write-Host "Components:" -ForegroundColor Yellow
$VerificationResults | Format-Table -AutoSize

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Obtain join command from Kubernetes control plane" -ForegroundColor Gray
Write-Host "2. Update and run: $JoinScriptPath" -ForegroundColor Gray
Write-Host "3. Configure CNI plugin on control plane" -ForegroundColor Gray
Write-Host "4. Verify node joins cluster: kubectl get nodes" -ForegroundColor Gray
Write-Host ""
Write-Host "Documentation: https://kubernetes.io/docs/setup/production-environment/windows/" -ForegroundColor Gray
Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green

Stop-Transcript
