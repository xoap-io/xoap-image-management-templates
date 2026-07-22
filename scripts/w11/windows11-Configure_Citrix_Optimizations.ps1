<#
.SYNOPSIS
    Applies a Citrix-Optimizer-aligned optimization pass to a Windows 11 VDA image.

.DESCRIPTION
    Applies optimizations analogous to Citrix Optimizer VDA templates to reduce resource
    usage and improve density on Citrix (MCS / PVS) images:
      - disables a curated set of services Citrix recommends disabling on VDAs;
      - disables a curated set of scheduled tasks (telemetry, maintenance, defrag);
      - applies recommended registry tweaks, including DisableTaskOffload=1 (recommended for
        PVS-streamed targets) and ClearPageFileAtShutdown=0.

    Each section can be skipped via -SkipServices / -SkipScheduledTasks / -SkipRegistry
    (all sections run by default). All changes are idempotent and non-interactive.

    This script deliberately does NOT remove inbox apps and does NOT disable Windows
    Defender. It follows the repository provisioning script contract
    (docs/SCRIPT_CONTRACT.md). Developed for the XOAP Image Management module but usable
    independently.

.COMPONENT
    Citrix-Optimize

.PARAMETER SkipServices
    Skip disabling the curated service set.

.PARAMETER SkipScheduledTasks
    Skip disabling the curated scheduled-task set.

.PARAMETER SkipRegistry
    Skip applying the recommended registry tweaks.

.EXAMPLE
    .\windows11-Configure_Citrix_Optimizations.ps1

.EXAMPLE
    .\windows11-Configure_Citrix_Optimizations.ps1 -SkipScheduledTasks

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Skip disabling services')]
    [switch]$SkipServices = [System.Convert]::ToBoolean($(if ($env:CITRIX_OPT_SKIP_SERVICES) { $env:CITRIX_OPT_SKIP_SERVICES } else { 'false' })),

    [Parameter(HelpMessage = 'Skip disabling scheduled tasks')]
    [switch]$SkipScheduledTasks = [System.Convert]::ToBoolean($(if ($env:CITRIX_OPT_SKIP_TASKS) { $env:CITRIX_OPT_SKIP_TASKS } else { 'false' })),

    [Parameter(HelpMessage = 'Skip applying registry tweaks')]
    [switch]$SkipRegistry = [System.Convert]::ToBoolean($(if ($env:CITRIX_OPT_SKIP_REGISTRY) { $env:CITRIX_OPT_SKIP_REGISTRY } else { 'false' }))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Component = 'Citrix-Optimize'
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Citrix-Optimize] Transcript unavailable: $($_.Exception.Message)" }

$script:Applied = 0
$script:Skipped = 0
$script:Failed = 0

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] [$Component] $Message"
    Write-Host $line
}

trap {
    Write-Log "Unhandled error: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date

Write-Log '===== Configure_Citrix_Optimizations starting ====='
Write-Log '========================================================='
Write-Log 'Citrix Optimizer-aligned VDA optimization pass'
Write-Log '========================================================='
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "SkipServices=$SkipServices SkipScheduledTasks=$SkipScheduledTasks SkipRegistry=$SkipRegistry"

# ------------------------------------------------------------------
# Section 1: Services recommended for disabling on Citrix VDAs.
# ------------------------------------------------------------------
if ($SkipServices) {
    Write-Log 'Service optimization skipped (-SkipServices).'
}
else {
    $servicesToDisable = @(
        'DiagTrack',            # Connected User Experiences and Telemetry
        'dmwappushservice',     # Device Management WAP Push message routing
        'MapsBroker',           # Downloaded Maps Manager
        'WSearch',              # Windows Search indexing
        'SysMain',              # Superfetch/prefetch (no benefit on streamed images)
        'WerSvc',               # Windows Error Reporting
        'RetailDemo',           # Retail Demo service
        'Fax',                  # Fax
        'lfsvc',                # Geolocation service
        'PhoneSvc',             # Phone service
        'wisvc',                # Windows Insider Service
        'RemoteRegistry',       # Remote Registry
        'WMPNetworkSvc'         # Windows Media Player Network Sharing
    )
    foreach ($serviceName in $servicesToDisable) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if (-not $service) {
                Write-Log "Service '$serviceName' not present - skipping."
                $script:Skipped++
                continue
            }
            if ($service.StartType -eq 'Disabled') {
                Write-Log "Service '$serviceName' already disabled."
                $script:Skipped++
                continue
            }
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $serviceName -StartupType Disabled
            Write-Log "[OK] Disabled service '$serviceName'."
            $script:Applied++
        }
        catch {
            Write-Log "Failed to disable service '$serviceName': $($_.Exception.Message)" -Level WARN
            $script:Failed++
        }
    }
}

# ------------------------------------------------------------------
# Section 2: Scheduled tasks recommended for disabling on Citrix VDAs.
# ------------------------------------------------------------------
if ($SkipScheduledTasks) {
    Write-Log 'Scheduled-task optimization skipped (-SkipScheduledTasks).'
}
else {
    # Each entry is a TaskPath + TaskName pair.
    $tasksToDisable = @(
        @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' },
        @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' },
        @{ Path = '\Microsoft\Windows\Defrag\'; Name = 'ScheduledDefrag' },
        @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{ Path = '\Microsoft\Windows\Maintenance\'; Name = 'WinSAT' },
        @{ Path = '\Microsoft\Windows\Windows Error Reporting\'; Name = 'QueueReporting' }
    )
    foreach ($task in $tasksToDisable) {
        try {
            $existing = Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                Write-Log "Scheduled task '$($task.Path)$($task.Name)' not present - skipping."
                $script:Skipped++
                continue
            }
            if ($existing.State -eq 'Disabled') {
                Write-Log "Scheduled task '$($task.Path)$($task.Name)' already disabled."
                $script:Skipped++
                continue
            }
            Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction Stop | Out-Null
            Write-Log "[OK] Disabled scheduled task '$($task.Path)$($task.Name)'."
            $script:Applied++
        }
        catch {
            Write-Log "Failed to disable scheduled task '$($task.Path)$($task.Name)': $($_.Exception.Message)" -Level WARN
            $script:Failed++
        }
    }
}

# ------------------------------------------------------------------
# Section 3: Recommended registry tweaks.
# ------------------------------------------------------------------
if ($SkipRegistry) {
    Write-Log 'Registry optimization skipped (-SkipRegistry).'
}
else {
    $registryTweaks = @(
        @{
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
            Name = 'DisableTaskOffload'
            Value = 1
            Type = 'DWord'
            Note = 'Disable TCP task offload (recommended for PVS-streamed targets)'
        },
        @{
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            Name = 'ClearPageFileAtShutdown'
            Value = 0
            Type = 'DWord'
            Note = 'Do not clear the pagefile at shutdown (faster shutdown)'
        },
        @{
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            Name = 'AllowTelemetry'
            Value = 0
            Type = 'DWord'
            Note = 'Set telemetry level to Security/off'
        }
    )
    foreach ($tweak in $registryTweaks) {
        try {
            if (-not (Test-Path $tweak.Path)) {
                New-Item -Path $tweak.Path -Force | Out-Null
            }
            $current = (Get-ItemProperty -Path $tweak.Path -Name $tweak.Name -ErrorAction SilentlyContinue).$($tweak.Name)
            if ($null -ne $current -and [int]$current -eq [int]$tweak.Value) {
                Write-Log "Registry '$($tweak.Path)\$($tweak.Name)' already set to $($tweak.Value)."
                $script:Skipped++
                continue
            }
            New-ItemProperty -Path $tweak.Path -Name $tweak.Name -Value $tweak.Value -PropertyType $tweak.Type -Force | Out-Null
            Write-Log "[OK] $($tweak.Note): set '$($tweak.Name)'=$($tweak.Value)."
            $script:Applied++
        }
        catch {
            Write-Log "Failed to apply registry tweak '$($tweak.Name)': $($_.Exception.Message)" -Level WARN
            $script:Failed++
        }
    }
}

$endTime = Get-Date
$duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)

Write-Log '========================================================='
Write-Log "Summary: applied=$script:Applied skipped=$script:Skipped failed=$script:Failed duration=${duration}s"
Write-Log '========================================================='

if ($script:Failed -gt 0) {
    Write-Log 'Completed with one or more non-fatal failures.' -Level WARN
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

Write-Log '[OK] Citrix optimization pass completed.'
Write-Log "===== Configure_Citrix_Optimizations complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
try { Stop-Transcript | Out-Null } catch {}
exit 0
