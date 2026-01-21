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

# Error handling
trap {
    Write-Error "Error: $_"
    Write-Error $_.ScriptStackTrace
    Stop-Transcript
    exit 1
}

Write-Host "=== Windows Exporter for Prometheus Installation ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Listen Port: $ListenPort" -ForegroundColor Gray
Write-Host "Collectors: $EnabledCollectors" -ForegroundColor Gray
Write-Host ""

# Determine latest version
if ($ExporterVersion -eq "latest") {
    Write-Host "Detecting latest windows_exporter version..." -ForegroundColor Yellow
    try {
        $ReleasesUrl = "https://api.github.com/repos/prometheus-community/windows_exporter/releases/latest"
        $Release = Invoke-RestMethod -Uri $ReleasesUrl -UseBasicParsing
        $ExporterVersion = $Release.tag_name.TrimStart('v')
        Write-Host "  Latest version: $ExporterVersion" -ForegroundColor Green
    } catch {
        Write-Warning "Could not detect latest version, using 0.25.1"
        $ExporterVersion = "0.25.1"
    }
}

# Download windows_exporter
Write-Host "`nDownloading windows_exporter..." -ForegroundColor Yellow
$DownloadUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v$ExporterVersion/windows_exporter-$ExporterVersion-amd64.msi"
$InstallerPath = Join-Path $env:TEMP "windows_exporter-$ExporterVersion.msi"

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Host "  [OK] Downloaded windows_exporter" -ForegroundColor Green
    $script:DownloadedFiles++
} catch {
    throw "Failed to download windows_exporter: $_"
}

# Install windows_exporter
Write-Host "`nInstalling windows_exporter..." -ForegroundColor Yellow
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
    Write-Host "  [OK] windows_exporter installed successfully" -ForegroundColor Green
} else {
    throw "Installation failed with exit code: $($InstallProcess.ExitCode)"
}

# Configure firewall
Write-Host "`nConfiguring firewall..." -ForegroundColor Yellow
$FirewallRule = Get-NetFirewallRule -Name "WindowsExporter" -ErrorAction SilentlyContinue
if (-not $FirewallRule) {
    New-NetFirewallRule -Name "WindowsExporter" -DisplayName "Prometheus Windows Exporter" `
        -Description "Allow Prometheus to scrape metrics" `
        -Protocol TCP -LocalPort $ListenPort -Action Allow -Enabled True | Out-Null
    Write-Host "  [OK] Firewall rule created" -ForegroundColor Green
    $script:FirewallRules++
} else {
    Write-Host "  [EXISTS] Firewall rule already exists" -ForegroundColor Gray
}

# Verify service
Write-Host "`nVerifying service..." -ForegroundColor Yellow
$Service = Get-Service "windows_exporter" -ErrorAction SilentlyContinue
if ($Service) {
    if ($Service.Status -ne 'Running') {
        Start-Service "windows_exporter"
    }
    Set-Service "windows_exporter" -StartupType Automatic
    Write-Host "  [OK] Service is running" -ForegroundColor Green
} else {
    Write-Warning "Service not found"
}

# Test metrics endpoint
Write-Host "`nTesting metrics endpoint..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
try {
    $MetricsUrl = "http://localhost:$ListenPort/metrics"
    $Response = Invoke-WebRequest -Uri $MetricsUrl -UseBasicParsing -TimeoutSec 10
    if ($Response.StatusCode -eq 200) {
        $MetricsCount = ($Response.Content -split "`n" | Where-Object { $_ -match "^#\s*HELP" }).Count
        Write-Host "  [OK] Metrics endpoint responding ($MetricsCount metrics)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not reach metrics endpoint: $_"
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
Write-Host "`nPrometheus config example: $ConfigPath" -ForegroundColor Cyan

# Summary report
Write-Host "`n=== Windows Exporter Installation Summary ===" -ForegroundColor Cyan
Write-Host "Version: $ExporterVersion" -ForegroundColor Gray
Write-Host "Listen Port: $ListenPort" -ForegroundColor Gray
Write-Host "Metrics Endpoint: http://localhost:$ListenPort/metrics" -ForegroundColor Gray
Write-Host ""
Write-Host "Statistics:" -ForegroundColor Yellow
Write-Host "  Downloaded Files: $script:DownloadedFiles" -ForegroundColor Gray
Write-Host "  Configured Collectors: $script:ConfiguredCollectors" -ForegroundColor Gray
Write-Host "  Firewall Rules: $script:FirewallRules" -ForegroundColor Gray
Write-Host ""
Write-Host "Enabled Collectors:" -ForegroundColor Yellow
$CollectorsList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Add this server to Prometheus: $ConfigPath" -ForegroundColor Gray
Write-Host "2. Test metrics: http://$($env:COMPUTERNAME):$ListenPort/metrics" -ForegroundColor Gray
Write-Host "3. Configure Grafana dashboards (ID: 14694)" -ForegroundColor Gray
Write-Host "4. Set up alerting rules in Prometheus" -ForegroundColor Gray
Write-Host ""
Write-Host "Documentation: https://github.com/prometheus-community/windows_exporter" -ForegroundColor Gray
Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green

Stop-Transcript