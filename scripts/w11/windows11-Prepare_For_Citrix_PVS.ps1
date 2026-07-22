<#
.SYNOPSIS
    Prepares a Windows 11 VM to become a Citrix Provisioning Services (PVS) Target Device.

.DESCRIPTION
    Optimizes and configures a Windows 11 VM for Citrix PVS image streaming. It disables
    services that are unnecessary or harmful on a streamed target, sets Windows Update to
    manual, and configures the pagefile via CIM (Get-CimInstance / Set-CimInstance) - it
    does NOT use wmic, which is removed on Windows 11 24H2+.

    If a PVS Target Device installer is provided (via -PvsInstallerPath or the
    PVS_INSTALLER_PATH environment variable) it is run silently and its exit code checked;
    if none is provided the install step is skipped with an INFO message. A disk
    defragmentation pass is optional behind -Defrag (off by default).

    The script is idempotent, non-interactive, and follows the repository provisioning
    script contract (docs/SCRIPT_CONTRACT.md). Developed for the XOAP Image Management
    module but usable independently.

.COMPONENT
    Citrix-PVS

.PARAMETER PvsInstallerPath
    Optional full path to the PVS Target Device installer (PVS_Device_x64_*.exe).
    Defaults to the PVS_INSTALLER_PATH environment variable. When empty, install is skipped.

.PARAMETER Defrag
    Run a disk defragmentation pass on C: before streaming. Off by default.

.EXAMPLE
    .\windows11-Prepare_For_Citrix_PVS.ps1
    Prepares the system for Citrix PVS imaging (no installer, no defrag).

.EXAMPLE
    .\windows11-Prepare_For_Citrix_PVS.ps1 -PvsInstallerPath 'C:\media\PVS_Device_x64.exe' -Defrag

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Full path to the PVS Target Device installer')]
    [string]$PvsInstallerPath = $env:PVS_INSTALLER_PATH,

    [Parameter(HelpMessage = 'Run a disk defragmentation pass on C:')]
    [switch]$Defrag = [System.Convert]::ToBoolean($(if ($env:PVS_DEFRAG) { $env:PVS_DEFRAG } else { 'false' }))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Component = 'Citrix-PVS'
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Citrix-PVS] Transcript unavailable: $($_.Exception.Message)" }

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

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$startTime = Get-Date

Write-Log "===== Prepare_For_Citrix_PVS starting (Defrag=$Defrag) ====="
Write-Log '========================================================='
Write-Log 'Prepare Windows 11 VM for Citrix PVS Target Device'
Write-Log '========================================================='
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "Defrag: $Defrag"

# 1. Disable services unnecessary or harmful on a streamed PVS target.
#    Each service is checked for existence before being disabled (idempotent).
$servicesToDisable = @(
    'Spooler',
    'Fax',
    'WSearch',
    'WMPNetworkSvc',
    'XblAuthManager',
    'XblGameSave',
    'XboxNetApiSvc',
    'PrintNotify',
    'RemoteRegistry',
    'bthserv',
    'SCardSvr',
    'WerSvc',
    'wisvc',
    'PhoneSvc',
    'RetailDemo',
    'seclogon',
    'CscService',
    'WcnSvc',
    'StiSvc',
    'FrameServer',
    'WbioSrvc'
)
foreach ($serviceName in $servicesToDisable) {
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

# 2. Set Windows Update to manual start.
try {
    $wu = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
    if ($wu) {
        if ($wu.StartType -eq 'Manual') {
            Write-Log 'Windows Update (wuauserv) already set to Manual.'
            $script:Skipped++
        }
        else {
            Set-Service -Name 'wuauserv' -StartupType Manual
            Write-Log '[OK] Set Windows Update (wuauserv) start type to Manual.'
            $script:Applied++
        }
    }
    else {
        Write-Log 'Windows Update service (wuauserv) not present - skipping.'
        $script:Skipped++
    }
}
catch {
    Write-Log "Failed to configure Windows Update service: $($_.Exception.Message)" -Level WARN
    $script:Failed++
}

# 3. Set the pagefile to system-managed via CIM (wmic is removed on 24H2+).
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs.AutomaticManagedPagefile) {
        Write-Log 'Pagefile already system-managed (AutomaticManagedPagefile = True).'
        $script:Skipped++
    }
    else {
        Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-CimInstance -InputObject $_ -ErrorAction SilentlyContinue }
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true }
        Write-Log '[OK] Set pagefile to system-managed via CIM.'
        $script:Applied++
    }
}
catch {
    Write-Log "Failed to configure pagefile: $($_.Exception.Message)" -Level WARN
    $script:Failed++
}

# 4. Optional disk defragmentation (off by default; only useful before capturing to vDisk).
if ($Defrag) {
    Write-Log 'Running disk defragmentation on C: ...'
    & defrag.exe C: /U /V | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log '[OK] Defragmentation completed.'
        $script:Applied++
    }
    else {
        Write-Log "Defragmentation returned exit code $LASTEXITCODE." -Level WARN
        $script:Failed++
    }
}
else {
    Write-Log 'Defragmentation not requested (-Defrag not set) - skipping.'
    $script:Skipped++
}

# 5. Optional PVS Target Device software install.
if ([string]::IsNullOrWhiteSpace($PvsInstallerPath)) {
    Write-Log 'No PVS Target Device installer provided - install step skipped (set PVS_INSTALLER_PATH or -PvsInstallerPath).'
    $script:Skipped++
}
elseif (-not (Test-Path -LiteralPath $PvsInstallerPath -PathType Leaf)) {
    Write-Log "PVS Target Device installer not found at path: $PvsInstallerPath" -Level ERROR
    $script:Failed++
}
else {
    Write-Log "Installing Citrix PVS Target Device software from: $PvsInstallerPath"
    $proc = Start-Process -FilePath $PvsInstallerPath -ArgumentList '/S' -Wait -PassThru -NoNewWindow
    $pvsExit = $proc.ExitCode
    if ($pvsExit -in @(0, 3, 3010)) {
        Write-Log "[OK] PVS Target Device software installed (exit code $pvsExit; reboot required)."
        $script:Applied++
        $script:RebootRequired = $true
    }
    else {
        Write-Log "[FAIL] PVS Target Device install failed (exit code $pvsExit)." -Level ERROR
        $script:Failed++
    }
}

$endTime = Get-Date
$duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)

Write-Log '========================================================='
Write-Log "Summary: applied=$script:Applied skipped=$script:Skipped failed=$script:Failed duration=${duration}s"
Write-Log 'You may now run the Citrix Imaging Wizard and Sysprep if required.'
Write-Log '========================================================='
Write-Log "===== Prepare_For_Citrix_PVS complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

if ($script:Failed -gt 0) {
    Write-Log 'Completed with one or more failures.' -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$rebootRequired = $false
if (Get-Variable -Name RebootRequired -Scope Script -ErrorAction SilentlyContinue) {
    $rebootRequired = $script:RebootRequired
}
if ($rebootRequired) {
    Write-Log 'A reboot is required to complete the PVS Target Device installation (exit 3010).'
    try { Stop-Transcript | Out-Null } catch {}
    exit 3010
}

Write-Log '[OK] PVS Target Device preparation completed.'
try { Stop-Transcript | Out-Null } catch {}
exit 0
