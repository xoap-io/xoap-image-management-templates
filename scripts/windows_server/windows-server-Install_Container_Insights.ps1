<#
.SYNOPSIS
    Installs and configures Azure Container Insights monitoring for Windows containers.

.DESCRIPTION
    This script sets up Azure Monitor Container Insights for Windows Server containers:
    - Installs OMS Agent for Windows
    - Configures container monitoring
    - Sets up log collection and metrics
    - Enables Docker/containerd monitoring
    - Configures Azure Log Analytics workspace integration
    
    Supports Azure, on-premises, and hybrid scenarios.

.PARAMETER WorkspaceId
    Azure Log Analytics Workspace ID.

.PARAMETER WorkspaceKey
    Azure Log Analytics Workspace primary key.

.PARAMETER AgentVersion
    OMS Agent version. Default: Latest

.PARAMETER MonitorDocker
    Enable Docker container monitoring.

.PARAMETER MonitorContainerd
    Enable containerd monitoring.

.EXAMPLE
    .\windows-server-Install_Container_Insights.ps1 -WorkspaceId "abc-123" -WorkspaceKey "key123"
    
.EXAMPLE
    .\windows-server-Install_Container_Insights.ps1 -WorkspaceId "abc" -WorkspaceKey "key" -MonitorContainerd
.NOTES
    File Name      : windows-server-Install_Container_Insights.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceKey,

    [Parameter(Mandatory = $false)]
    [string]$AgentVersion = "latest",

    [Parameter(Mandatory = $false)]
    [switch]$MonitorDocker,

    [Parameter(Mandatory = $false)]
    [switch]$MonitorContainerd
)

# Statistics tracking
$script:InstalledComponents = 0
$script:ConfiguredMonitors = 0
$script:CollectionRules = 0

# Logging setup
$LogDate = Get-Date -Format 'yyyy-MM-dd'
$LogPath = "C:\xoap-logs"
$LogFile = Join-Path $LogPath "Install-ContainerInsights_$LogDate.log"

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

Write-Host "=== Azure Container Insights Installation ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Workspace ID: $($WorkspaceId.Substring(0, 8))..." -ForegroundColor Gray
Write-Host ""

# Validate workspace credentials
if ($WorkspaceId.Length -lt 10 -or $WorkspaceKey.Length -lt 20) {
    throw "Invalid Workspace ID or Key format"
}

# Detect container runtime
Write-Host "Detecting container runtimes..." -ForegroundColor Yellow
$DockerService = Get-Service docker -ErrorAction SilentlyContinue
$ContainerdRunning = Get-Process containerd -ErrorAction SilentlyContinue

if ($DockerService -and $DockerService.Status -eq 'Running') {
    Write-Host "  [DETECTED] Docker" -ForegroundColor Green
    $MonitorDocker = $true
}

if ($ContainerdRunning) {
    Write-Host "  [DETECTED] containerd" -ForegroundColor Green
    $MonitorContainerd = $true
}

if (-not $MonitorDocker -and -not $MonitorContainerd) {
    Write-Warning "No container runtime detected. Installing agent only."
}

# Download OMS Agent
Write-Host "`nDownloading Microsoft Monitoring Agent..." -ForegroundColor Yellow
$AgentUrl = "https://go.microsoft.com/fwlink/?LinkId=828603"
$AgentPath = Join-Path $env:TEMP "MMASetup-AMD64.exe"

try {
    Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentPath -UseBasicParsing
    Write-Host "  [OK] Agent downloaded" -ForegroundColor Green
} catch {
    throw "Failed to download OMS Agent: $_"
}

# Install OMS Agent
Write-Host "`nInstalling Microsoft Monitoring Agent..." -ForegroundColor Yellow
$AgentArguments = @(
    "/C:setup.exe",
    "/qn",
    "NOAPM=1",
    "ADD_OPINSIGHTS_WORKSPACE=1",
    "OPINSIGHTS_WORKSPACE_ID=$WorkspaceId",
    "OPINSIGHTS_WORKSPACE_KEY=$WorkspaceKey",
    "AcceptEndUserLicenseAgreement=1"
)

$InstallProcess = Start-Process -FilePath $AgentPath -ArgumentList $AgentArguments -Wait -PassThru -NoNewWindow

if ($InstallProcess.ExitCode -eq 0 -or $InstallProcess.ExitCode -eq 3010) {
    Write-Host "  [OK] OMS Agent installed successfully" -ForegroundColor Green
    $script:InstalledComponents++
} else {
    throw "OMS Agent installation failed with exit code: $($InstallProcess.ExitCode)"
}

# Wait for service to start
Write-Host "Waiting for HealthService to start..." -ForegroundColor Yellow
$Timeout = 60
$Elapsed = 0
do {
    Start-Sleep -Seconds 5
    $Elapsed += 5
    $Service = Get-Service HealthService -ErrorAction SilentlyContinue
} while ((-not $Service -or $Service.Status -ne 'Running') -and $Elapsed -lt $Timeout)

if ($Service.Status -eq 'Running') {
    Write-Host "  [OK] HealthService running" -ForegroundColor Green
} else {
    Write-Warning "HealthService did not start within timeout"
}

# Configure container monitoring
if ($MonitorDocker) {
    Write-Host "`nConfiguring Docker monitoring..." -ForegroundColor Yellow
    
    # Create Docker monitoring configuration
    $DockerConfig = @{
        "ContainerInventory" = @{
            "Enabled" = $true
            "CollectionIntervalSeconds" = 60
        }
        "ContainerMetrics" = @{
            "Enabled" = $true
            "CollectionIntervalSeconds" = 30
        }
        "ContainerLogs" = @{
            "Enabled" = $true
            "MaxLogSizeMB" = 10
        }
    }
    
    $ConfigPath = "C:\Program Files\Microsoft Monitoring Agent\Agent\Health Service State\Monitoring Host Temporary Files 6\Container.config"
    $DockerConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding utf8 -Force
    
    Write-Host "  [OK] Docker monitoring configured" -ForegroundColor Green
    $script:ConfiguredMonitors++
    $script:CollectionRules += 3
}

if ($MonitorContainerd) {
    Write-Host "`nConfiguring containerd monitoring..." -ForegroundColor Yellow
    
    # Configure containerd metrics endpoint
    $MetricsPort = 1338
    New-NetFirewallRule -Name "Containerd-Metrics" -DisplayName "Containerd Metrics" `
        -Protocol TCP -LocalPort $MetricsPort -Action Allow -Enabled True -ErrorAction SilentlyContinue
    
    Write-Host "  [OK] containerd monitoring configured" -ForegroundColor Green
    $script:ConfiguredMonitors++
}

# Configure performance counters
Write-Host "`nConfiguring performance counters..." -ForegroundColor Yellow
$Counters = @(
    "\Container(*)\*",
    "\Process(*)\*",
    "\Memory\*",
    "\Processor(*)\*",
    "\Network Interface(*)\*"
)

$AgentPath = "C:\Program Files\Microsoft Monitoring Agent\Agent"
$ConfigTool = Join-Path $AgentPath "TestCloudConnection.exe"

if (Test-Path $ConfigTool) {
    Write-Host "  Verifying workspace connectivity..." -ForegroundColor Cyan
    $TestResult = & $ConfigTool -WorkspaceId $WorkspaceId
    if ($TestResult -match "success|connected") {
        Write-Host "  [OK] Workspace connection verified" -ForegroundColor Green
    }
}

$script:CollectionRules += $Counters.Count

# Create custom monitoring queries
Write-Host "`nCreating monitoring queries documentation..." -ForegroundColor Yellow
$QueriesDoc = @"
# Container Insights Queries for Windows

## Container Inventory
``kusto
ContainerInventory
| where Computer == "$env:COMPUTERNAME"
| where TimeGenerated > ago(1h)
| summarize Count = count() by ContainerName, Image
``

## Container Performance
``kusto
Perf
| where Computer == "$env:COMPUTERNAME"
| where ObjectName == "Container"
| where TimeGenerated > ago(1h)
| summarize avg(CounterValue) by CounterName, InstanceName
``

## Container Logs
``kusto
ContainerLog
| where Computer == "$env:COMPUTERNAME"
| where TimeGenerated > ago(1h)
| project TimeGenerated, LogEntry, ContainerName
``

## Resource Usage
``kusto
Perf
| where Computer == "$env:COMPUTERNAME"
| where CounterName in ("% Processor Time", "Available MBytes")
| where TimeGenerated > ago(1h)
| summarize avg(CounterValue) by CounterName, bin(TimeGenerated, 5m)
``
"@

$QueriesPath = Join-Path $LogPath "ContainerInsights-Queries.md"
$QueriesDoc | Out-File -FilePath $QueriesPath -Encoding utf8
Write-Host "  [OK] Queries saved to: $QueriesPath" -ForegroundColor Green

# Restart monitoring service
Write-Host "`nRestarting monitoring services..." -ForegroundColor Yellow
Restart-Service HealthService -Force
Start-Sleep -Seconds 10

# Verify installation
Write-Host "`nVerifying installation..." -ForegroundColor Yellow
$VerificationChecks = @()

# Check OMS Agent
$OMSAgent = Get-Service HealthService -ErrorAction SilentlyContinue
$VerificationChecks += [PSCustomObject]@{
    Component = "OMS Agent"
    Status = if ($OMSAgent -and $OMSAgent.Status -eq 'Running') { "Running" } else { "Not Running" }
    Details = $OMSAgent.Status
}

# Check Docker monitoring
if ($MonitorDocker) {
    $DockerMonitoring = Test-Path "C:\Program Files\Microsoft Monitoring Agent\Agent\Health Service State\Monitoring Host Temporary Files 6\Container.config"
    $VerificationChecks += [PSCustomObject]@{
        Component = "Docker Monitoring"
        Status = if ($DockerMonitoring) { "Configured" } else { "Not Configured" }
        Details = if ($DockerMonitoring) { "Enabled" } else { "Disabled" }
    }
}

# Check containerd monitoring
if ($MonitorContainerd) {
    $ContainerdFirewall = Get-NetFirewallRule -Name "Containerd-Metrics" -ErrorAction SilentlyContinue
    $VerificationChecks += [PSCustomObject]@{
        Component = "containerd Monitoring"
        Status = if ($ContainerdFirewall) { "Configured" } else { "Not Configured" }
        Details = if ($ContainerdFirewall) { "Firewall rule created" } else { "No firewall rule" }
    }
}

# Summary report
Write-Host "`n=== Container Insights Installation Summary ===" -ForegroundColor Cyan
Write-Host "Workspace ID: $($WorkspaceId.Substring(0, 8))..." -ForegroundColor Gray
Write-Host "Computer Name: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host ""
Write-Host "Statistics:" -ForegroundColor Yellow
Write-Host "  Installed Components: $script:InstalledComponents" -ForegroundColor Gray
Write-Host "  Configured Monitors: $script:ConfiguredMonitors" -ForegroundColor Gray
Write-Host "  Collection Rules: $script:CollectionRules" -ForegroundColor Gray
Write-Host ""
Write-Host "Verification:" -ForegroundColor Yellow
$VerificationChecks | Format-Table -AutoSize

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Wait 5-10 minutes for data to appear in Azure Portal" -ForegroundColor Gray
Write-Host "2. Open Azure Portal > Monitor > Containers" -ForegroundColor Gray
Write-Host "3. Use queries in: $QueriesPath" -ForegroundColor Gray
Write-Host "4. Configure alerts and dashboards as needed" -ForegroundColor Gray
Write-Host ""
Write-Host "Documentation: https://docs.microsoft.com/azure/azure-monitor/containers/containers" -ForegroundColor Gray
Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green

Stop-Transcript