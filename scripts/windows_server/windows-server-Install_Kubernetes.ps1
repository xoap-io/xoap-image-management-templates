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

$script:Component = 'Kubernetes'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

# Error handling
trap {
    Write-Log "Error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    Stop-Transcript
    exit 1
}

$startTime = Get-Date
Write-Log "===== Install_Kubernetes starting (Version=$KubernetesVersion, Runtime=$ContainerRuntime, CNIPlugin=$CNIPlugin) ====="

# Check prerequisites
Write-Log "Checking prerequisites..."

$OSInfo = Get-CimInstance Win32_OperatingSystem
if ($OSInfo.ProductType -ne 3) {
    Write-Log "This script is designed for Windows Server (detected client OS)" -Level WARN
}

if ([int]$OSInfo.BuildNumber -lt 17763) {
    throw "Windows Server 2019 (build 17763) or later is required"
}

# Check Containers feature
$ContainersFeature = Get-WindowsFeature -Name Containers -ErrorAction SilentlyContinue
if (-not $ContainersFeature -or $ContainersFeature.InstallState -ne 'Installed') {
    Write-Log "Installing Containers feature..."
    Install-WindowsFeature -Name Containers -Restart:$false
    $script:ConfiguredServices++
}

# Create installation directory
if (-not (Test-Path $InstallPath)) {
    Write-Log "Creating installation directory: $InstallPath"
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}

# Determine Kubernetes version
if ($KubernetesVersion -eq "latest") {
    Write-Log "Detecting latest stable Kubernetes version..."
    try {
        $VersionResponse = Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable.txt" -UseBasicParsing
        $KubernetesVersion = $VersionResponse.Trim()
        Write-Log "Latest version: $KubernetesVersion"
    } catch {
        Write-Log "Could not detect latest version, using v1.28.0" -Level WARN
        $KubernetesVersion = "v1.28.0"
    }
}

if (-not $KubernetesVersion.StartsWith("v")) {
    $KubernetesVersion = "v$KubernetesVersion"
}

# Download Kubernetes binaries
Write-Log "Downloading Kubernetes binaries..."
$BaseUrl = "https://dl.k8s.io/release/$KubernetesVersion/bin/windows/amd64"
$Binaries = @("kubelet.exe", "kubeadm.exe", "kubectl.exe")

foreach ($Binary in $Binaries) {
    $DownloadUrl = "$BaseUrl/$Binary"
    $DestinationPath = Join-Path $InstallPath $Binary

    if (Test-Path $DestinationPath) {
        Write-Log "[EXISTS] $Binary"
    } else {
        Write-Log "Downloading $Binary..."
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $DestinationPath -UseBasicParsing
            $script:DownloadedFiles++
            Write-Log "[OK] $Binary"
        } catch {
            Write-Log "Failed to download $Binary : $_" -Level ERROR
        }
    }
}

# Add to PATH
Write-Log "Configuring system PATH..."
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($CurrentPath -notlike "*$InstallPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$InstallPath", "Machine")
    $env:Path = "$env:Path;$InstallPath"
    Write-Log "Added $InstallPath to system PATH"
    $script:NetworkChanges++
}

# Configure container runtime
Write-Log "Configuring container runtime: $ContainerRuntime"

if ($ContainerRuntime -eq "containerd") {
    # Download and configure containerd
    $ContainerdVersion = "1.7.11"
    $ContainerdUrl = "https://github.com/containerd/containerd/releases/download/v$ContainerdVersion/containerd-$ContainerdVersion-windows-amd64.tar.gz"
    $ContainerdArchive = Join-Path $env:TEMP "containerd.tar.gz"
    
    Write-Log "Downloading containerd v$ContainerdVersion..."
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
    Write-Log "[OK] containerd configured and started"

} elseif ($ContainerRuntime -eq "docker") {
    # Verify Docker is installed
    if (-not (Get-Service docker -ErrorAction SilentlyContinue)) {
        Write-Log "Docker is not installed. Install Docker Enterprise first." -Level WARN
        Write-Log "Run: .\Install-DockerEnterprise.ps1"
    } else {
        Write-Log "[OK] Docker runtime detected"
    }
}

# Download CNI plugins
Write-Log "Installing CNI plugins..."
$CNIPath = Join-Path $InstallPath "cni"
if (-not (Test-Path $CNIPath)) {
    New-Item -Path $CNIPath -ItemType Directory -Force | Out-Null
}

$CNIVersion = "v1.4.0"
$CNIUrl = "https://github.com/microsoft/windows-container-networking/releases/download/$CNIVersion/windows-container-networking-cni-amd64-$CNIVersion.zip"
$CNIArchive = Join-Path $env:TEMP "cni-plugins.zip"

Write-Log "Downloading CNI plugins $CNIVersion..."
Invoke-WebRequest -Uri $CNIUrl -OutFile $CNIArchive -UseBasicParsing
Expand-Archive -Path $CNIArchive -DestinationPath $CNIPath -Force
$script:DownloadedFiles++
Write-Log "[OK] CNI plugins installed"

# Configure Windows networking
if (-not $SkipNetworkConfiguration) {
    Write-Log "Configuring Windows networking for Kubernetes..."
    
    # Enable IP forwarding
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
        -Name "IPEnableRouter" -Value 1 -Type DWord
    $script:NetworkChanges++
    
    # Disable Windows Firewall for testing (should be configured properly in production)
    Write-Log "Configuring firewall rules..."
    New-NetFirewallRule -Name "Kubelet" -DisplayName "Kubelet" `
        -Protocol TCP -LocalPort 10250 -Action Allow -Enabled True -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name "Kubernetes-API" -DisplayName "Kubernetes API" `
        -Protocol TCP -LocalPort 6443 -Action Allow -Enabled True -ErrorAction SilentlyContinue
    $script:NetworkChanges++

    Write-Log "[OK] Network configuration complete"
}

# Create kubelet configuration directory
$KubeletConfigPath = Join-Path $InstallPath "config"
if (-not (Test-Path $KubeletConfigPath)) {
    New-Item -Path $KubeletConfigPath -ItemType Directory -Force | Out-Null
}

# Create kubelet startup script
Write-Log "Creating kubelet service configuration..."
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
Write-Log "Kubelet service setup:"
Write-Log "To complete kubelet setup, you need to:"
Write-Log "1. Join this node to a Kubernetes cluster using kubeadm"
Write-Log "2. Configure kubelet service to start automatically"
Write-Log "3. Apply the CNI network plugin configuration"
Write-Log "Example commands:"
Write-Log "  kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"

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
Write-Log "Verifying installation..."
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
        Write-Log "[OK] $Binary - $Version"
    } else {
        $VerificationResults += [PSCustomObject]@{
            Component = $Binary.Replace('.exe', '')
            Status = "Missing"
            Version = "N/A"
        }
        Write-Log "[FAIL] $Binary not found" -Level ERROR
    }
}

# Summary report
Write-Log "Installation Path: $InstallPath"
Write-Log "Kubernetes Version: $KubernetesVersion"
Write-Log "Container Runtime: $ContainerRuntime"
Write-Log "CNI Plugin: $CNIPlugin (to be configured)"
Write-Log "Statistics: DownloadedFiles=$script:DownloadedFiles ConfiguredServices=$script:ConfiguredServices NetworkChanges=$script:NetworkChanges"
Write-Log "Components:"
$VerificationResults | Format-Table -AutoSize

Write-Log "===== Install_Kubernetes complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
Stop-Transcript
exit 0
