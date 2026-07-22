<#
.SYNOPSIS
    Installs Windows Exporter for Prometheus monitoring.

.DESCRIPTION
    This script installs and configures windows_exporter for Prometheus:
    - Downloads and installs windows_exporter
    - Configures system metrics collection
    - Enables collectors for CPU, memory, disk, network
    - Sets up Windows service
    - Configures firewall rules
    
    Provides metrics in Prometheus format for monitoring solutions.

.PARAMETER ExporterVersion
    Windows Exporter version. Default: Latest

.PARAMETER ListenPort
    HTTP port for metrics endpoint. Default: 9182

.PARAMETER EnabledCollectors
    Comma-separated list of collectors to enable.

.PARAMETER InstallPath
    Installation directory. Default: C:\Program Files\windows_exporter

.EXAMPLE
    .\windows-server-Install_Prometheus_Exporter.ps1

.EXAMPLE
    .\windows-server-Install_Prometheus_Exporter.ps1 -ListenPort 9100 -EnabledCollectors "cpu,memory,disk,network"

.NOTES
    File Name      : windows-server-Install_Prometheus_Exporter.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ExporterVersion = "latest",

    [Parameter(Mandatory = $false)]
    [int]$ListenPort = 9182,

    [Parameter(Mandatory = $false)]
    [string]$EnabledCollectors = "cpu,cs,logical_disk,memory,net,os,process,system,tcp",

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\Program Files\windows_exporter"
)

# Statistics tracking
$script:DownloadedFiles = 0
$script:ConfiguredCollectors = 0
$script:FirewallRules = 0

# Logging setup
$LogDate = Get-Date -Format 'yyyy-MM-dd'
$LogPath = "C:\xoap-logs"
$LogFile = Join-Path $LogPath "Install-PrometheusExporter_$LogDate.log"

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogFile -Append

$script:Component = 'PrometheusExporter'
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
Write-Log "===== Install_Prometheus_Exporter starting (ListenPort=$ListenPort, Collectors=$EnabledCollectors) ====="

# Determine latest version
if ($ExporterVersion -eq "latest") {
    Write-Log "Detecting latest windows_exporter version..."
    try {
        $ReleasesUrl = "https://api.github.com/repos/prometheus-community/windows_exporter/releases/latest"
        $Release = Invoke-RestMethod -Uri $ReleasesUrl -UseBasicParsing
        $ExporterVersion = $Release.tag_name.TrimStart('v')
        Write-Log "Latest version: $ExporterVersion"
    } catch {
        Write-Log "Could not detect latest version, using 0.25.1" -Level WARN
        $ExporterVersion = "0.25.1"
    }
}

# Download windows_exporter
Write-Log "Downloading windows_exporter..."
$DownloadUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v$ExporterVersion/windows_exporter-$ExporterVersion-amd64.msi"
$InstallerPath = Join-Path $env:TEMP "windows_exporter-$ExporterVersion.msi"

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Log "[OK] Downloaded windows_exporter"
    $script:DownloadedFiles++
} catch {
    throw "Failed to download windows_exporter: $_"
}

# Install windows_exporter
Write-Log "Installing windows_exporter..."
$ArgumentList = @(
    "/i",
    "`"$InstallerPath`"",
    "/quiet",
    "/norestart",
    "ENABLED_COLLECTORS=$EnabledCollectors",
    "LISTEN_PORT=$ListenPort"
)

$InstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow

if ($InstallProcess.ExitCode -eq 0 -or $InstallProcess.ExitCode -eq 3010) {
    Write-Log "[OK] windows_exporter installed successfully"
} else {
    throw "Installation failed with exit code: $($InstallProcess.ExitCode)"
}

# Configure firewall
Write-Log "Configuring firewall..."
$FirewallRule = Get-NetFirewallRule -Name "WindowsExporter" -ErrorAction SilentlyContinue
if (-not $FirewallRule) {
    New-NetFirewallRule -Name "WindowsExporter" -DisplayName "Prometheus Windows Exporter" `
        -Description "Allow Prometheus to scrape metrics" `
        -Protocol TCP -LocalPort $ListenPort -Action Allow -Enabled True | Out-Null
    Write-Log "[OK] Firewall rule created"
    $script:FirewallRules++
} else {
    Write-Log "[EXISTS] Firewall rule already exists"
}

# Verify service
Write-Log "Verifying service..."
$Service = Get-Service "windows_exporter" -ErrorAction SilentlyContinue
if ($Service) {
    if ($Service.Status -ne 'Running') {
        Start-Service "windows_exporter"
    }
    Set-Service "windows_exporter" -StartupType Automatic
    Write-Log "[OK] Service is running"
} else {
    Write-Log "Service not found" -Level WARN
}

# Test metrics endpoint
Write-Log "Testing metrics endpoint..."
Start-Sleep -Seconds 5
try {
    $MetricsUrl = "http://localhost:$ListenPort/metrics"
    $Response = Invoke-WebRequest -Uri $MetricsUrl -UseBasicParsing -TimeoutSec 10
    if ($Response.StatusCode -eq 200) {
        $MetricsCount = ($Response.Content -split "`n" | Where-Object { $_ -match "^#\s*HELP" }).Count
        Write-Log "[OK] Metrics endpoint responding ($MetricsCount metrics)"
    }
} catch {
    Write-Log "Could not reach metrics endpoint: $_" -Level WARN
}

# Count enabled collectors
$CollectorsList = $EnabledCollectors -split ','
$script:ConfiguredCollectors = $CollectorsList.Count

# Create Prometheus configuration example
$PrometheusConfig = @"
# Prometheus configuration for Windows Server monitoring

scrape_configs:
  - job_name: 'windows-servers'
    static_configs:
      - targets: ['$($env:COMPUTERNAME):$ListenPort']
        labels:
          instance: '$env:COMPUTERNAME'
          environment: 'production'
          
    # Optional: Add authentication
    # basic_auth:
    #   username: 'prometheus'
    #   password: 'your_password'
    
    scrape_interval: 30s
    scrape_timeout: 10s

# Common queries for Windows Server:
# - CPU Usage: 100 - (avg by (instance) (irate(windows_cpu_time_total{mode="idle"}[5m])) * 100)
# - Memory Usage: (windows_os_physical_memory_free_bytes / windows_cs_physical_memory_bytes) * 100
# - Disk Usage: 100 - (windows_logical_disk_free_bytes / windows_logical_disk_size_bytes) * 100
# - Network Traffic: rate(windows_net_bytes_received_total[5m])
"@

$ConfigPath = Join-Path $LogPath "prometheus-windows-config.yml"
$PrometheusConfig | Out-File -FilePath $ConfigPath -Encoding utf8
Write-Log "Prometheus config example: $ConfigPath"

# Summary report
Write-Log "Version: $ExporterVersion"
Write-Log "Listen Port: $ListenPort"
Write-Log "Metrics Endpoint: http://localhost:$ListenPort/metrics"
Write-Log "Statistics: DownloadedFiles=$script:DownloadedFiles ConfiguredCollectors=$script:ConfiguredCollectors FirewallRules=$script:FirewallRules"
Write-Log "Enabled Collectors:"
$CollectorsList | ForEach-Object { Write-Log "  - $_" }

Write-Log "===== Install_Prometheus_Exporter complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
Stop-Transcript
exit 0