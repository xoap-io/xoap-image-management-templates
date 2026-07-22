<#
.SYNOPSIS
    Downloads, installs and configures the Microsoft FSLogix agent for Azure Virtual Desktop.

.DESCRIPTION
    Installs the FSLogix Apps agent (profile containers) on a Windows 11 Enterprise
    multi-session / AVD session-host image and applies a recommended profile-container
    configuration under HKLM:\SOFTWARE\FSLogix\Profiles.

    By default the agent is downloaded from https://aka.ms/fslogix_download (a ZIP that
    contains x64\Release\FSLogixAppsSetup.exe), extracted, and installed silently with
    /install /quiet /norestart. An offline installer (ZIP or FSLogixAppsSetup.exe) may be
    supplied instead. All registry writes are idempotent (New-ItemProperty -Force).

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes (0 success,
    3010 reboot required, non-zero failure), env-var overridable parameters, idempotent,
    non-interactive. Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER DownloadUrl
    URL of the FSLogix ZIP download. Env FSLOGIX_DOWNLOAD_URL. Default https://aka.ms/fslogix_download.

.PARAMETER InstallerPath
    Optional path to an offline FSLogix installer (a ZIP or FSLogixAppsSetup.exe). When set,
    the download is skipped. Env FSLOGIX_INSTALLER_PATH.

.PARAMETER VHDLocations
    One or more UNC paths for the profile-container VHD(X) store, comma-separated when supplied
    via environment. Env FSLOGIX_VHD_LOCATIONS. Default empty (a WARN is logged; it MUST be set
    post-deploy for FSLogix to store profiles).

.PARAMETER SizeInMBs
    Maximum profile-container size in MB. Env FSLOGIX_SIZE_MB. Default 30000.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Install_FSLogix.ps1
    Downloads and installs FSLogix, applies defaults (VHDLocations left unset with a warning).

.EXAMPLE
    .\windows11-Install_FSLogix.ps1 -VHDLocations '\\storage\profiles'
    Installs FSLogix and points profile containers at the given share.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [string]$DownloadUrl = $(if ($env:FSLOGIX_DOWNLOAD_URL) { $env:FSLOGIX_DOWNLOAD_URL } else { 'https://aka.ms/fslogix_download' }),

    [string]$InstallerPath = $env:FSLOGIX_INSTALLER_PATH,

    [string[]]$VHDLocations = $(if ($env:FSLOGIX_VHD_LOCATIONS) { $env:FSLOGIX_VHD_LOCATIONS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @() }),

    [int]$SizeInMBs = $(if ($env:FSLOGIX_SIZE_MB) { [int]$env:FSLOGIX_SIZE_MB } else { 30000 })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'FSLogix'
$script:Applied = 0
$script:Failed = 0
$script:RebootRequired = $false

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = 'DWord'
    )
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Log "Set $Path\$Name = $Value ($Type)"
        $script:Applied++
    } catch {
        Write-Log "Failed to set $Path\$Name : $($_.Exception.Message)" -Level ERROR
        $script:Failed++
    }
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [FSLogix] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date
Write-Log '===== Install_FSLogix starting ====='

# --- Locate the installer -------------------------------------------------
$workDir = Join-Path $env:TEMP "fslogix-$ts"
if (-not (Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }

$setupExe = $null

if ($InstallerPath) {
    if (-not (Test-Path $InstallerPath)) { throw "InstallerPath not found: $InstallerPath" }
    Write-Log "Using offline installer: $InstallerPath"
    if ($InstallerPath -match '\.exe$') {
        $setupExe = $InstallerPath
    } else {
        Write-Log "Extracting offline ZIP to $workDir"
        Expand-Archive -Path $InstallerPath -DestinationPath $workDir -Force
    }
} else {
    $zipPath = Join-Path $workDir 'FSLogix.zip'
    Write-Log "Downloading FSLogix from: $DownloadUrl"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
    Write-Log "Extracting to $workDir"
    Expand-Archive -Path $zipPath -DestinationPath $workDir -Force
}

if (-not $setupExe) {
    $found = Get-ChildItem -Path $workDir -Recurse -Filter 'FSLogixAppsSetup.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1
    if (-not $found) {
        $found = Get-ChildItem -Path $workDir -Recurse -Filter 'FSLogixAppsSetup.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $found) { throw "FSLogixAppsSetup.exe not found after extraction under $workDir" }
    $setupExe = $found.FullName
}
Write-Log "Installer resolved to: $setupExe"

# --- Install --------------------------------------------------------------
Write-Log 'Running FSLogixAppsSetup.exe /install /quiet /norestart'
$proc = Start-Process -FilePath $setupExe -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru -NoNewWindow
$code = $proc.ExitCode
if ($code -eq 0) {
    Write-Log '[OK] FSLogix agent installed'
    $script:Applied++
} elseif ($code -eq 3010) {
    Write-Log '[OK] FSLogix agent installed; reboot required (exit 3010)'
    $script:Applied++
    $script:RebootRequired = $true
} else {
    throw "FSLogix installation failed with exit code $code"
}

# --- Configure profile-container registry ---------------------------------
$profilesKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'
Write-Log "Configuring profile-container settings under $profilesKey"

Set-RegistryValue -Path $profilesKey -Name 'Enabled' -Value 1 -Type DWord

if ($VHDLocations -and $VHDLocations.Count -gt 0) {
    Set-RegistryValue -Path $profilesKey -Name 'VHDLocations' -Value $VHDLocations -Type MultiString
} else {
    Write-Log 'VHDLocations is empty. FSLogix will NOT store profiles until this is set post-deploy (HKLM:\SOFTWARE\FSLogix\Profiles\VHDLocations).' -Level WARN
}

Set-RegistryValue -Path $profilesKey -Name 'VolumeType' -Value 'vhdx' -Type String
Set-RegistryValue -Path $profilesKey -Name 'SizeInMBs' -Value $SizeInMBs -Type DWord
Set-RegistryValue -Path $profilesKey -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord
Set-RegistryValue -Path $profilesKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -Type DWord

# --- Cleanup --------------------------------------------------------------
try { Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}

# --- Summary --------------------------------------------------------------
Write-Log "===== Install_FSLogix complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

try { Stop-Transcript | Out-Null } catch {}

if ($script:Failed -gt 0) {
    Write-Log 'One or more configuration steps failed.' -Level ERROR
    exit 1
}
if ($script:RebootRequired) {
    Write-Log 'Reboot required to complete FSLogix installation.'
    exit 3010
}
exit 0
