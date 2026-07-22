<#
.SYNOPSIS
    Prepares a Windows 11 image for Citrix Machine Creation Services (MCS) provisioning.

.DESCRIPTION
    Applies image-preparation tweaks so a Windows 11 golden image is ready to be cloned by
    Citrix MCS. Specifically it:
      - disables the legacy Citrix Personal vDisk service if present;
      - optionally applies MCSIO (Machine Creation Services storage optimization) registry
        settings when -EnableMCSIO is specified;
      - clears the ARP and DNS resolver caches so clones start clean;
      - disables the Citrix WEM agent cache build-time refresh service if present;
      - sets the system pagefile to system-managed via CIM (Win32_ComputerSystem /
        Win32_PageFileSetting) - it does NOT use wmic, which is removed on Windows 11 24H2+.

    Machine SID handling is intentionally NOT performed here: MCS provisions unique
    identities per clone, and OS generalization / KMS rearm is handled by Sysprep.

    The script is idempotent, non-interactive, and follows the repository provisioning
    script contract (docs/SCRIPT_CONTRACT.md). Developed for the XOAP Image Management
    module but usable independently.

.COMPONENT
    Citrix-MCS

.PARAMETER EnableMCSIO
    Apply MCSIO storage-optimization registry settings for the image.

.EXAMPLE
    .\windows11-Prepare_Citrix_MCS.ps1

.EXAMPLE
    .\windows11-Prepare_Citrix_MCS.ps1 -EnableMCSIO

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Apply MCSIO storage-optimization registry settings')]
    [switch]$EnableMCSIO = [System.Convert]::ToBoolean($(if ($env:CITRIX_ENABLE_MCSIO) { $env:CITRIX_ENABLE_MCSIO } else { 'false' }))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Component = 'Citrix-MCS'
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Citrix-MCS] Transcript unavailable: $($_.Exception.Message)" }

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

function Disable-CitrixService {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "$Description service ('$Name') not present - skipping."
        $script:Skipped++
        return
    }
    if ($svc.StartType -eq 'Disabled') {
        Write-Log "$Description service ('$Name') already disabled."
        $script:Skipped++
        return
    }
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
    Set-Service -Name $Name -StartupType Disabled
    Write-Log "[OK] Disabled $Description service ('$Name')."
    $script:Applied++
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

Write-Log "===== Prepare_Citrix_MCS starting (EnableMCSIO=$EnableMCSIO) ====="
Write-Log '========================================================='
Write-Log 'Prepare Windows 11 image for Citrix MCS'
Write-Log '========================================================='
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "EnableMCSIO: $EnableMCSIO"

# 1. Disable legacy Citrix Personal vDisk (deprecated; not used with modern MCS).
Disable-CitrixService -Name 'CitrixPvD' -Description 'Citrix Personal vDisk (legacy)'

# 2. Disable the Citrix WEM agent build-time cache refresh service if present.
#    Cache should be built on the provisioned clone, not baked into the master image.
Disable-CitrixService -Name 'Citrix WEM Agent Host Service' -Description 'Citrix WEM Agent Host'

# 3. Optional MCSIO storage-optimization registry settings.
if ($EnableMCSIO) {
    try {
        $mcsioKey = 'HKLM:\SOFTWARE\Citrix\MCSIO'
        if (-not (Test-Path $mcsioKey)) {
            New-Item -Path $mcsioKey -Force | Out-Null
        }
        $existing = (Get-ItemProperty -Path $mcsioKey -Name 'MCSIOEnabled' -ErrorAction SilentlyContinue).MCSIOEnabled
        if ($existing -eq 1) {
            Write-Log 'MCSIO already enabled in registry.'
            $script:Skipped++
        }
        else {
            New-ItemProperty -Path $mcsioKey -Name 'MCSIOEnabled' -Value 1 -PropertyType DWord -Force | Out-Null
            Write-Log '[OK] Applied MCSIO storage-optimization registry setting.'
            $script:Applied++
        }
    }
    catch {
        Write-Log "Failed to apply MCSIO settings: $($_.Exception.Message)" -Level WARN
        $script:Failed++
    }
}
else {
    Write-Log 'MCSIO not requested (-EnableMCSIO not set) - skipping MCSIO registry settings.'
    $script:Skipped++
}

# 4. Clear ARP and DNS caches so each provisioned clone starts with a clean network state.
try {
    $arpCleared = $false
    if (Get-Command -Name 'Remove-NetNeighbor' -ErrorAction SilentlyContinue) {
        Remove-NetNeighbor -Confirm:$false -ErrorAction SilentlyContinue
        $arpCleared = $true
    }
    if (-not $arpCleared) {
        & netsh interface ip delete arpcache | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "netsh arpcache delete returned exit code $LASTEXITCODE" -Level WARN
        }
    }
    Clear-DnsClientCache
    Write-Log '[OK] Cleared ARP and DNS client caches.'
    $script:Applied++
}
catch {
    Write-Log "Failed to clear network caches: $($_.Exception.Message)" -Level WARN
    $script:Failed++
}

# 5. Set the pagefile to system-managed via CIM (wmic is removed on 24H2+).
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs.AutomaticManagedPagefile) {
        Write-Log 'Pagefile already system-managed (AutomaticManagedPagefile = True).'
        $script:Skipped++
    }
    else {
        # Remove any explicit pagefile settings so the system-managed setting takes effect.
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

# 6. Guidance: MCS clones get unique identities; generalization/rearm is Sysprep's job.
Write-Log 'Note: MCS assigns unique machine identities per clone; no manual SID reset needed.'
Write-Log 'Note: OS generalization and KMS/license rearm are handled by Sysprep, not this script.'

$endTime = Get-Date
$duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)

Write-Log '========================================================='
Write-Log "Summary: applied=$script:Applied skipped=$script:Skipped failed=$script:Failed duration=${duration}s"
Write-Log '========================================================='
Write-Log "===== Prepare_Citrix_MCS complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

if ($script:Failed -gt 0) {
    Write-Log 'Completed with one or more non-fatal failures.' -Level WARN
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

Write-Log '[OK] MCS image preparation completed.'
try { Stop-Transcript | Out-Null } catch {}
exit 0
