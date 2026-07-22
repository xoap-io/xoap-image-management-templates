<#
.SYNOPSIS
    Installs the Citrix Virtual Delivery Agent (VDA) from a locally provided installer.

.DESCRIPTION
    Runs the Citrix VDA installer (VDAWorkstationSetup_*.exe or VDAServerSetup_*.exe) in
    unattended mode to prepare a Windows 11 image for Citrix Machine Creation Services (MCS),
    Provisioning Services (PVS), or a standard (manual) deployment.

    There is NO public download URL for the VDA installer; it must be provided via
    -InstallerPath or the CITRIX_VDA_INSTALLER environment variable. If no installer is
    supplied the script logs an ERROR and exits 1.

    The script is idempotent: if the VDA is already present (registry or BrokerAgent service)
    it logs and exits 0. The VDA installer commonly returns exit code 3 to signal a required
    reboot; this script treats 0, 3, and 3010 as success-needing-reboot and exits 3010.

    Developed and optimized for use with the XOAP Image Management module, but can be used
    independently. Follows the repository provisioning script contract (docs/SCRIPT_CONTRACT.md).

.COMPONENT
    Citrix-VDA

.PARAMETER InstallerPath
    Full path to the VDA installer executable. Defaults to the CITRIX_VDA_INSTALLER
    environment variable. REQUIRED (parameter or environment variable).

.PARAMETER Mode
    Provisioning mode: MCS, PVS, or Standard. Default MCS. MCS/PVS add /masterimage.

.PARAMETER Edition
    VDA edition: Workstation (single-session, default) or Server (multi-session).

.PARAMETER Controllers
    Optional space-separated list of Delivery Controller FQDNs. Defaults to the
    CITRIX_CONTROLLERS environment variable. When empty, /no_controller_check is used.

.EXAMPLE
    .\windows11-Install_Citrix_VDA.ps1 -InstallerPath 'C:\media\VDAWorkstationSetup_2402.exe' -Mode MCS

.EXAMPLE
    $env:CITRIX_VDA_INSTALLER = 'C:\media\VDAWorkstationSetup_2402.exe'; .\windows11-Install_Citrix_VDA.ps1

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Full path to the VDA installer executable')]
    [string]$InstallerPath = $env:CITRIX_VDA_INSTALLER,

    [Parameter(HelpMessage = 'Provisioning mode: MCS, PVS or Standard')]
    [ValidateSet('MCS', 'PVS', 'Standard')]
    [string]$Mode = $(if ($env:CITRIX_VDA_MODE) { $env:CITRIX_VDA_MODE } else { 'MCS' }),

    [Parameter(HelpMessage = 'VDA edition: Workstation or Server')]
    [ValidateSet('Workstation', 'Server')]
    [string]$Edition = $(if ($env:CITRIX_VDA_EDITION) { $env:CITRIX_VDA_EDITION } else { 'Workstation' }),

    [Parameter(HelpMessage = 'Space-separated list of Delivery Controller FQDNs')]
    [string]$Controllers = $env:CITRIX_CONTROLLERS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Component = 'Citrix-VDA'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Level] [$Component] $Message"
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Citrix-VDA] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Unhandled error: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date

Write-Log '===== Install_Citrix_VDA starting ====='
Write-Log 'Citrix Virtual Delivery Agent (VDA) Installation'
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "Mode: $Mode   Edition: $Edition"

# Idempotency check: is the VDA already installed?
$vdaRegKey = 'HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent'
$brokerAgent = Get-Service -Name 'BrokerAgent' -ErrorAction SilentlyContinue
if ((Test-Path $vdaRegKey) -or $brokerAgent) {
    Write-Log 'Citrix VDA already installed (registry key or BrokerAgent service present). Nothing to do.'
    Write-Log "===== Install_Citrix_VDA complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

# The VDA installer must be provided locally; there is no public download URL.
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    Write-Log 'No VDA installer provided. Supply -InstallerPath or set CITRIX_VDA_INSTALLER.' -Level ERROR
    Write-Log 'The VDA installer (VDAWorkstationSetup_*.exe / VDAServerSetup_*.exe) is not publicly downloadable.' -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    Write-Log "VDA installer not found at path: $InstallerPath" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

Write-Log "Using VDA installer: $InstallerPath"

# Build the silent installation arguments.
$installArgs = [System.Collections.Generic.List[string]]::new()
$installArgs.Add('/quiet')
$installArgs.Add('/noreboot')
$installArgs.Add('/noresume')
$installArgs.Add('/components')
$installArgs.Add('vda')
$installArgs.Add('/enable_remote_assistance')
$installArgs.Add('/enable_hdx_ports')
$installArgs.Add('/enable_hdx_udp_ports')
$installArgs.Add('/virtualmachine')

# Master image flag applies to both MCS and PVS provisioning (image is a golden template).
if ($Mode -eq 'MCS' -or $Mode -eq 'PVS') {
    $installArgs.Add('/masterimage')
}

# PVS-specific guidance: the VDA is installed the same way; the PVS Target Device software
# is a separate package (see windows11-Prepare_For_Citrix_PVS.ps1). Optimizations for a
# streamed image are applied by windows11-Configure_Citrix_Optimizations.ps1.
if ($Mode -eq 'PVS') {
    Write-Log 'PVS mode: install the PVS Target Device software separately and run the PVS optimizations.'
}

# Delivery Controllers: register them if provided, otherwise skip the controller check.
if ([string]::IsNullOrWhiteSpace($Controllers)) {
    $installArgs.Add('/no_controller_check')
    Write-Log 'No controllers provided; using /no_controller_check.'
}
else {
    $installArgs.Add('/controllers')
    $installArgs.Add("`"$Controllers`"")
    Write-Log "Registering Delivery Controllers: $Controllers"
}

Write-Log "Install arguments: $($installArgs -join ' ')"
Write-Log 'Starting VDA installation (this can take several minutes)...'

$process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs.ToArray() -Wait -PassThru -NoNewWindow
$exitCode = $process.ExitCode
Write-Log "VDA installer returned exit code: $exitCode"

# The VDA installer commonly returns 3 (mapped to 3010) to signal a required reboot.
if ($exitCode -in @(0, 3, 3010)) {
    Write-Log '[OK] Citrix VDA installed successfully.'
    Write-Log 'A reboot is required to complete VDA installation (exit 3010).'
    Write-Log "===== Install_Citrix_VDA complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 3010
}

Write-Log "[FAIL] Citrix VDA installation failed (exit code $exitCode)." -Level ERROR
Write-Log "===== Install_Citrix_VDA complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
try { Stop-Transcript | Out-Null } catch {}
exit 1
