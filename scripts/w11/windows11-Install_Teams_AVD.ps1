<#
.SYNOPSIS
    Installs the new Microsoft Teams for Azure Virtual Desktop with AV redirection.

.DESCRIPTION
    Prepares a Windows 11 Enterprise multi-session / AVD session-host image for optimized
    Microsoft Teams, in the required order:

      1. Set HKLM:\SOFTWARE\Microsoft\Teams\IsWVDEnvironment = 1 (MUST be set before install so
         Teams and the WebRTC service detect the AVD environment and enable media optimization).
      2. Install the Remote Desktop WebRTC Redirector Service (MSI) for audio/video offload.
      3. Install the new Teams via teamsbootstrapper.exe -p (machine-wide provisioning).

    Downloads default to Microsoft aka.ms / fwlink endpoints and are overridable via parameters
    or environment variables. All steps are idempotent and check native exit codes.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes (0 success,
    3010 reboot required, non-zero failure), env-var overridable parameters, idempotent,
    non-interactive. Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER WebRtcUrl
    URL of the WebRTC Redirector Service MSI. Env TEAMS_WEBRTC_URL. Default https://aka.ms/msrdcwebrtcsvc/msi.

.PARAMETER BootstrapperUrl
    URL of the new-Teams bootstrapper (teamsbootstrapper.exe). Env TEAMS_BOOTSTRAPPER_URL.
    Default https://go.microsoft.com/fwlink/?linkid=2243204.

.PARAMETER WebRtcInstallerPath
    Optional offline path to the WebRTC MSI. Env TEAMS_WEBRTC_PATH.

.PARAMETER BootstrapperPath
    Optional offline path to teamsbootstrapper.exe. Env TEAMS_BOOTSTRAPPER_PATH.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Install_Teams_AVD.ps1
    Sets the AVD flag, installs the WebRTC service, then provisions new Teams machine-wide.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [string]$WebRtcUrl = $(if ($env:TEAMS_WEBRTC_URL) { $env:TEAMS_WEBRTC_URL } else { 'https://aka.ms/msrdcwebrtcsvc/msi' }),

    [string]$BootstrapperUrl = $(if ($env:TEAMS_BOOTSTRAPPER_URL) { $env:TEAMS_BOOTSTRAPPER_URL } else { 'https://go.microsoft.com/fwlink/?linkid=2243204' }),

    [string]$WebRtcInstallerPath = $env:TEAMS_WEBRTC_PATH,

    [string]$BootstrapperPath = $env:TEAMS_BOOTSTRAPPER_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'Teams-AVD'
$script:Applied = 0
$script:Failed = 0
$script:RebootRequired = $false

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Teams-AVD] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date
Write-Log '===== Install_Teams_AVD starting ====='

$workDir = Join-Path $env:TEMP "teams-avd-$ts"
if (-not (Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }

# --- Step 1: AVD environment flag (MUST be set before install) ------------
$teamsKey = 'HKLM:\SOFTWARE\Microsoft\Teams'
Write-Log "Setting $teamsKey\IsWVDEnvironment = 1 (required before Teams / WebRTC install)"
try {
    if (-not (Test-Path $teamsKey)) { New-Item -Path $teamsKey -Force | Out-Null }
    New-ItemProperty -Path $teamsKey -Name 'IsWVDEnvironment' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Log '[OK] IsWVDEnvironment set'
    $script:Applied++
} catch {
    Write-Log "Failed to set IsWVDEnvironment: $($_.Exception.Message)" -Level ERROR
    $script:Failed++
    throw
}

# --- Step 2: WebRTC Redirector Service ------------------------------------
Write-Log 'Installing Remote Desktop WebRTC Redirector Service...'
$webRtcInstalled = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%WebRTC%Redirector%'" -ErrorAction SilentlyContinue
if ($webRtcInstalled) {
    Write-Log "WebRTC Redirector already present: $($webRtcInstalled.Name) $($webRtcInstalled.Version); skipping"
} else {
    $msiPath = $WebRtcInstallerPath
    if ($msiPath) {
        if (-not (Test-Path $msiPath)) { throw "WebRtcInstallerPath not found: $msiPath" }
        Write-Log "Using offline WebRTC MSI: $msiPath"
    } else {
        $msiPath = Join-Path $workDir 'MsRdcWebRTCSvc.msi'
        Write-Log "Downloading WebRTC MSI from: $WebRtcUrl"
        Invoke-WebRequest -Uri $WebRtcUrl -OutFile $msiPath -UseBasicParsing
    }
    $logPath = Join-Path $workDir 'webrtc-install.log'
    Write-Log "Running msiexec /i for WebRTC service"
    $proc = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList "/i `"$msiPath`" /quiet /norestart /l*v `"$logPath`"" `
        -Wait -PassThru -NoNewWindow
    $code = $proc.ExitCode
    if ($code -eq 0) {
        Write-Log '[OK] WebRTC Redirector Service installed'
        $script:Applied++
    } elseif ($code -eq 3010) {
        Write-Log '[OK] WebRTC Redirector Service installed; reboot required (exit 3010)'
        $script:Applied++
        $script:RebootRequired = $true
    } else {
        throw "WebRTC MSI installation failed with exit code $code"
    }
}

# --- Step 3: new Teams via bootstrapper (machine-wide provisioning) -------
Write-Log 'Provisioning the new Microsoft Teams (machine-wide)...'
$existingTeams = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq 'MSTeams' }
if ($existingTeams) {
    Write-Log "New Teams already provisioned: $($existingTeams.PackageName); skipping"
} else {
    $bootstrapper = $BootstrapperPath
    if ($bootstrapper) {
        if (-not (Test-Path $bootstrapper)) { throw "BootstrapperPath not found: $bootstrapper" }
        Write-Log "Using offline bootstrapper: $bootstrapper"
    } else {
        $bootstrapper = Join-Path $workDir 'teamsbootstrapper.exe'
        Write-Log "Downloading Teams bootstrapper from: $BootstrapperUrl"
        Invoke-WebRequest -Uri $BootstrapperUrl -OutFile $bootstrapper -UseBasicParsing
    }
    Write-Log 'Running teamsbootstrapper.exe -p'
    $proc = Start-Process -FilePath $bootstrapper -ArgumentList '-p' -Wait -PassThru -NoNewWindow
    $code = $proc.ExitCode
    if ($code -eq 0) {
        Write-Log '[OK] New Teams provisioned machine-wide'
        $script:Applied++
    } elseif ($code -eq 3010) {
        Write-Log '[OK] New Teams provisioned; reboot required (exit 3010)'
        $script:Applied++
        $script:RebootRequired = $true
    } else {
        throw "teamsbootstrapper.exe failed with exit code $code"
    }
}

# --- Cleanup --------------------------------------------------------------
try { Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}

# --- Summary --------------------------------------------------------------
Write-Log "===== Install_Teams_AVD complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

try { Stop-Transcript | Out-Null } catch {}

if ($script:Failed -gt 0) {
    Write-Log 'One or more steps failed.' -Level ERROR
    exit 1
}
if ($script:RebootRequired) {
    Write-Log 'Reboot required to complete Teams / WebRTC installation.'
    exit 3010
}
exit 0
