<#
.SYNOPSIS
    Installs Microsoft OneDrive in per-machine (all-users) mode for AVD.

.DESCRIPTION
    Installs the OneDrive sync client machine-wide using OneDriveSetup.exe /allusers, which
    is the configuration Azure Virtual Desktop / multi-session hosts require so that a single
    installation serves every user profile (rather than the default per-user install).

    Sets HKLM:\SOFTWARE\Microsoft\OneDrive\AllUsersInstall = 1 before running setup, downloads
    the installer from the Microsoft fwlink (overridable), or uses a supplied offline installer.
    The native exit code is checked and the operation is idempotent (an existing per-machine
    install is detected and skipped).

    NOTE: This is the AVD-appropriate counterpart to windows11-Remove_OneDrive_And_Teams.ps1,
    which does the opposite (removing OneDrive/Teams) and is intended for non-AVD images.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes (0 success,
    3010 reboot required, non-zero failure), env-var overridable parameters, idempotent,
    non-interactive. Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER DownloadUrl
    URL of OneDriveSetup.exe. Env ONEDRIVE_DOWNLOAD_URL. Default https://go.microsoft.com/fwlink/?linkid=844652.

.PARAMETER InstallerPath
    Optional path to an offline OneDriveSetup.exe. When set the download is skipped.
    Env ONEDRIVE_INSTALLER_PATH.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Install_OneDrive_PerMachine.ps1
    Downloads OneDriveSetup.exe and installs it machine-wide.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [string]$DownloadUrl = $(if ($env:ONEDRIVE_DOWNLOAD_URL) { $env:ONEDRIVE_DOWNLOAD_URL } else { 'https://go.microsoft.com/fwlink/?linkid=844652' }),

    [string]$InstallerPath = $env:ONEDRIVE_INSTALLER_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'OneDrive'
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
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [OneDrive] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$startTime = Get-Date
Write-Log '===== Install_OneDrive_PerMachine starting ====='

$oneDriveKey = 'HKLM:\SOFTWARE\Microsoft\OneDrive'

# --- Idempotency check ----------------------------------------------------
$alreadyPerMachine = $false
try {
    if (Test-Path $oneDriveKey) {
        $existing = Get-ItemProperty -Path $oneDriveKey -ErrorAction SilentlyContinue
        if ($existing -and $existing.PSObject.Properties.Name -contains 'AllUsersInstall' -and $existing.AllUsersInstall -eq 1) {
            $alreadyPerMachine = $true
        }
    }
} catch {}

if ($alreadyPerMachine -and (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")) {
    Write-Log 'OneDrive is already installed per-machine (AllUsersInstall=1); skipping.'
} else {
    # Set AllUsersInstall BEFORE running setup.
    Write-Log "Setting $oneDriveKey\AllUsersInstall = 1"
    if (-not (Test-Path $oneDriveKey)) { New-Item -Path $oneDriveKey -Force | Out-Null }
    New-ItemProperty -Path $oneDriveKey -Name 'AllUsersInstall' -Value 1 -PropertyType DWord -Force | Out-Null

    # Resolve installer.
    $workDir = Join-Path $env:TEMP "onedrive-$ts"
    if (-not (Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }

    $setupExe = $InstallerPath
    if ($setupExe) {
        if (-not (Test-Path $setupExe)) { throw "InstallerPath not found: $setupExe" }
        Write-Log "Using offline installer: $setupExe"
    } else {
        $setupExe = Join-Path $workDir 'OneDriveSetup.exe'
        Write-Log "Downloading OneDriveSetup.exe from: $DownloadUrl"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $setupExe -UseBasicParsing
    }

    Write-Log 'Running OneDriveSetup.exe /allusers'
    $proc = Start-Process -FilePath $setupExe -ArgumentList '/allusers' -Wait -PassThru -NoNewWindow
    $code = $proc.ExitCode
    if ($code -eq 0) {
        Write-Log '[OK] OneDrive installed per-machine'
        $script:Applied++
    } elseif ($code -eq 3010) {
        Write-Log '[OK] OneDrive installed per-machine; reboot required (exit 3010)'
        $script:Applied++
        $script:RebootRequired = $true
    } else {
        throw "OneDriveSetup.exe failed with exit code $code"
    }

    try { Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

# --- Summary --------------------------------------------------------------
Write-Log "===== Install_OneDrive_PerMachine complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="

try { Stop-Transcript | Out-Null } catch {}

if ($script:Failed -gt 0) {
    Write-Log 'OneDrive installation failed.' -Level ERROR
    exit 1
}
if ($script:RebootRequired) {
    Write-Log 'Reboot required to complete OneDrive installation.'
    exit 3010
}
exit 0
