<#
.SYNOPSIS
    Applies Virtual-Desktop-Optimization-Tool (VDOT) aligned optimizations to an AVD session host.

.DESCRIPTION
    Performs a curated, non-destructive optimization pass for Windows 11 Enterprise
    multi-session / Azure Virtual Desktop session hosts, aligned with the Microsoft
    Virtual Desktop Optimization Tool guidance:

      - Disables Storage Sense (policy).
      - Disables a curated list of scheduled tasks that are unnecessary on AVD.
      - Disables a curated list of services that are safe to disable on AVD.
      - Applies recommended policy registry tweaks (disable Cortana, disable Windows
        Consumer Features / soft landing, disable Advertising ID, disable Teredo).

    This script supersedes the older windows11-Prepare_AVD_Imaging.ps1. It deliberately does
    NOT touch Windows Defender (ordering is handled by a dedicated script), does NOT remove
    inbox / AppX apps, and does NOT configure time-zone redirection (see
    windows11-Configure_Timezone_Redirection.ps1). The multi-session SKU is detected and
    logged; when the SKU is not multi-session nothing destructive is performed and the
    (still non-destructive) optimizations are applied with an informational note.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes (0 success,
    non-zero failure), env-var overridable parameters, idempotent, non-interactive.
    Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER SkipServices
    Skip the service-disable group. Env AVD_SKIP_SERVICES=1.

.PARAMETER SkipScheduledTasks
    Skip the scheduled-task-disable group. Env AVD_SKIP_SCHEDTASKS=1.

.PARAMETER SkipRegistry
    Skip the registry-tweak group (including Storage Sense). Env AVD_SKIP_REGISTRY=1.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Configure_AVD_Optimizations.ps1
    Runs all optimization groups.

.EXAMPLE
    .\windows11-Configure_AVD_Optimizations.ps1 -SkipServices
    Runs scheduled-task and registry groups only.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [switch]$SkipServices = [bool]$env:AVD_SKIP_SERVICES,
    [switch]$SkipScheduledTasks = [bool]$env:AVD_SKIP_SCHEDTASKS,
    [switch]$SkipRegistry = [bool]$env:AVD_SKIP_REGISTRY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'AVD-Optimize'
$script:Applied = 0
$script:Skipped = 0
$script:Failed = 0

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

function Set-RegistryValue {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Log "Set $Path\$Name = $Value ($Type)"
        $script:Applied++
    } catch {
        Write-Log "Failed to set $Path\$Name : $($_.Exception.Message)" -Level WARN
        $script:Failed++
    }
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [AVD-Optimize] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date
Write-Log '===== Configure_AVD_Optimizations starting ====='

# --- Detect multi-session SKU (log only) ----------------------------------
$editionId = ''
try {
    $editionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction Stop).EditionID
} catch { Write-Log "Could not read EditionID: $($_.Exception.Message)" -Level WARN }

$isMultiSession = $editionId -match 'ServerRdsh|EnterpriseMultiSession'
Write-Log "EditionID: $editionId  MultiSession: $isMultiSession"
if (-not $isMultiSession) {
    Write-Log 'Not a Windows 11 Enterprise multi-session SKU; applying non-destructive optimizations only.' -Level WARN
}

# --- Group 1: Services -----------------------------------------------------
if ($SkipServices) {
    Write-Log 'SkipServices set; skipping service group.'
} else {
    Write-Log 'Disabling AVD-unnecessary services...'
    $services = @(
        'DiagTrack',       # Connected User Experiences and Telemetry
        'MapsBroker',      # Downloaded Maps Manager
        'RetailDemo',      # Retail Demo Service
        'WerSvc',          # Windows Error Reporting
        'fhsvc',           # File History Service
        'wisvc',           # Windows Insider Service
        'XblAuthManager',  # Xbox Live Auth Manager
        'XblGameSave',     # Xbox Live Game Save
        'XboxGipSvc',      # Xbox Accessory Management
        'XboxNetApiSvc'    # Xbox Live Networking
    )
    foreach ($name in $services) {
        try {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $svc) { Write-Log "  Service $name not present; skipping"; $script:Skipped++; continue }
            if ($svc.StartType -eq 'Disabled') { Write-Log "  Service $name already disabled"; $script:Skipped++; continue }
            if ($svc.Status -eq 'Running') { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue }
            Set-Service -Name $name -StartupType Disabled
            Write-Log "  [OK] Disabled service $name"
            $script:Applied++
        } catch {
            Write-Log "  Could not disable service ${name}: $($_.Exception.Message)" -Level WARN
            $script:Failed++
        }
    }
}

# --- Group 2: Scheduled tasks ----------------------------------------------
if ($SkipScheduledTasks) {
    Write-Log 'SkipScheduledTasks set; skipping scheduled-task group.'
} else {
    Write-Log 'Disabling AVD-unnecessary scheduled tasks...'
    $tasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Maps\MapsToastTask',
        '\Microsoft\Windows\Maps\MapsUpdateTask',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
    foreach ($full in $tasks) {
        try {
            $taskName = Split-Path $full -Leaf
            $taskPath = (Split-Path $full -Parent).TrimEnd('\') + '\'
            $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
            if (-not $task) { Write-Log "  Task $full not present; skipping"; $script:Skipped++; continue }
            if ($task.State -eq 'Disabled') { Write-Log "  Task $full already disabled"; $script:Skipped++; continue }
            Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
            Write-Log "  [OK] Disabled task $full"
            $script:Applied++
        } catch {
            Write-Log "  Could not disable task ${full}: $($_.Exception.Message)" -Level WARN
            $script:Failed++
        }
    }
}

# --- Group 3: Registry tweaks (includes Storage Sense) --------------------
if ($SkipRegistry) {
    Write-Log 'SkipRegistry set; skipping registry group.'
} else {
    Write-Log 'Applying recommended policy registry tweaks...'

    # Storage Sense off
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' -Name 'AllowStorageSenseGlobal' -Value 0 -Type DWord

    # Cortana off
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0 -Type DWord

    # Windows Consumer Features / soft landing off
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSoftLanding' -Value 1 -Type DWord

    # Advertising ID off
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Name 'DisabledByGroupPolicy' -Value 1 -Type DWord

    # Teredo disabled (policy)
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition' -Name 'Teredo_State' -Value 'Disabled' -Type String
}

# --- Summary --------------------------------------------------------------
if ($script:Failed -gt 0) {
    Write-Log 'One or more optimizations failed (see WARN lines above).' -Level WARN
}
Write-Log "===== Configure_AVD_Optimizations complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

try { Stop-Transcript | Out-Null } catch {}
exit 0
