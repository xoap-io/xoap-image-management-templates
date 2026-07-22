<#
.SYNOPSIS
    Prepares a Windows 11 image for Windows 365 / CloudPC provisioning.

.DESCRIPTION
    Prepares a Windows 11 image so it is ready to be used as a Windows 365 CloudPC
    custom image. This script does NOT join the machine to anything (no Azure AD /
    Entra join, no domain join, no Intune enrollment) - Windows 365 handles enrollment
    at provisioning time. Instead it ensures the image is left in a clean, supportable
    state:

      - Enrollment hygiene: removes leftover MDM/Intune enrollment state and any staged
        provisioning packages (.ppkg) so the image does not carry a prior tenant identity.
      - BitLocker: verifies BitLocker is NOT enabled on the OS drive (CloudPC forbids it
        in the image). By default this only warns/reports; pass -Decrypt to actively
        disable protection and decrypt the OS drive.
      - Autopilot artifacts: clears cached Autopilot / provisioning reset artifacts that
        should not ship in a generic CloudPC image.
      - Recommended settings: applies CloudPC-friendly defaults and logs guidance.
      - Sysprep: by default it only PREPARES and logs that the caller should run
        windows-server-Invoke_Sysprep.ps1 -VMMode (generalize / oobe / mode:vm). Pass
        -RunSysprep to invoke the shared sysprep script directly.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes, env-var
    overridable parameters, idempotent, non-interactive.
    Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER Decrypt
    Actively disable BitLocker and decrypt the OS drive if it is encrypted. Default off
    (report only). Env CLOUDPC_DECRYPT=1.

.PARAMETER RunSysprep
    Invoke windows-server-Invoke_Sysprep.ps1 -VMMode after preparation. Default off
    (the script only logs the recommended sysprep command). Env CLOUDPC_RUN_SYSPREP=1.

.PARAMETER SysprepScriptPath
    Path to the shared sysprep script used when -RunSysprep is set. Defaults to the
    windows_server sibling script. Env CLOUDPC_SYSPREP_SCRIPT.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Prepare_CloudPC.ps1
    Prepares the image and logs the recommended sysprep command (no sysprep run).

.EXAMPLE
    .\windows11-Prepare_CloudPC.ps1 -Decrypt -RunSysprep
    Decrypts the OS drive if needed, prepares, then runs sysprep /generalize /oobe /mode:vm.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [switch]$Decrypt = [bool]$env:CLOUDPC_DECRYPT,

    [switch]$RunSysprep = [bool]$env:CLOUDPC_RUN_SYSPREP,

    [string]$SysprepScriptPath = $(if ($env:CLOUDPC_SYSPREP_SCRIPT) { $env:CLOUDPC_SYSPREP_SCRIPT } else { Join-Path $PSScriptRoot '..\windows_server\windows-server-Invoke_Sysprep.ps1' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'CloudPC-Prepare'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [CloudPC-Prepare] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$script:Applied = 0
$script:Skipped = 0
$script:Warnings = 0

function Clear-EnrollmentState {
    Write-Log 'Checking for leftover MDM/Intune enrollment state...'
    $enrollRoot = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    try {
        if (-not (Test-Path $enrollRoot)) {
            Write-Log 'No Enrollments registry root present; nothing to clear.'
            $script:Skipped++
            return
        }
        # Only remove enrollment subkeys that carry an actual MDM enrollment (EnrollmentState/UPN).
        $removed = 0
        Get-ChildItem -Path $enrollRoot -ErrorAction SilentlyContinue | ForEach-Object {
            $key = $_
            try {
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                $isMdm = $props -and (
                    ($props.PSObject.Properties.Name -contains 'EnrollmentState') -or
                    ($props.PSObject.Properties.Name -contains 'UPN') -or
                    ($props.PSObject.Properties.Name -contains 'ProviderID')
                )
                if ($isMdm) {
                    Write-Log "Removing stale enrollment key: $($key.PSChildName)"
                    Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction Stop
                    $removed++
                }
            } catch {
                Write-Log "Could not remove enrollment key $($key.PSChildName): $($_.Exception.Message)" -Level WARN
                $script:Warnings++
            }
        }
        if ($removed -gt 0) {
            Write-Log "Removed $removed stale enrollment key(s)."
            $script:Applied++
        } else {
            Write-Log 'No stale MDM enrollment keys found.'
            $script:Skipped++
        }
    } catch {
        Write-Log "Enrollment state check failed: $($_.Exception.Message)" -Level WARN
        $script:Warnings++
    }
}

function Remove-ProvisioningPackages {
    Write-Log 'Checking for staged provisioning packages (.ppkg)...'
    try {
        $pkgs = @()
        if (Get-Command Get-ProvisioningPackage -ErrorAction SilentlyContinue) {
            $pkgs = @(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction SilentlyContinue)
        }
        if ($pkgs.Count -eq 0) {
            Write-Log 'No installed provisioning packages found.'
            $script:Skipped++
            return
        }
        foreach ($pkg in $pkgs) {
            try {
                Write-Log "Removing provisioning package: $($pkg.PackageId)"
                Remove-ProvisioningPackage -PackageId $pkg.PackageId -ErrorAction Stop | Out-Null
                $script:Applied++
            } catch {
                Write-Log "Could not remove provisioning package $($pkg.PackageId): $($_.Exception.Message)" -Level WARN
                $script:Warnings++
            }
        }
    } catch {
        Write-Log "Provisioning package check failed: $($_.Exception.Message)" -Level WARN
        $script:Warnings++
    }
}

function Test-CloudPCBitLocker {
    Write-Log 'Verifying BitLocker is NOT enabled on the OS drive...'
    $osDrive = $env:SystemDrive
    try {
        $vol = Get-BitLockerVolume -MountPoint $osDrive -ErrorAction Stop
        $enabled = ($vol.ProtectionStatus -eq 'On') -or ($vol.VolumeStatus -ne 'FullyDecrypted') -or ($vol.EncryptionPercentage -gt 0)
        if (-not $enabled) {
            Write-Log "[OK] $osDrive is fully decrypted; CloudPC requirement satisfied."
            $script:Skipped++
            return
        }
        Write-Log "BitLocker is active on ${osDrive} (Status=$($vol.ProtectionStatus), Volume=$($vol.VolumeStatus))." -Level WARN
        Write-Log 'CloudPC custom images MUST NOT ship with BitLocker enabled.' -Level WARN
        if ($Decrypt) {
            Write-Log "Decrypt requested; disabling BitLocker on $osDrive ..."
            Disable-BitLocker -MountPoint $osDrive -ErrorAction Stop | Out-Null
            Write-Log 'Disable-BitLocker issued; decryption continues in the background. Re-run validation once VolumeStatus is FullyDecrypted.'
            $script:Applied++
        } else {
            Write-Log 'Decrypt switch not set; leaving decryption to the operator. Pass -Decrypt to disable BitLocker.' -Level WARN
            $script:Warnings++
        }
    } catch {
        Write-Log 'BitLocker not enabled / not present; CloudPC requirement satisfied.'
        $script:Skipped++
    }
}

function Clear-AutopilotArtifacts {
    Write-Log 'Clearing cached Autopilot / provisioning reset artifacts...'
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot',
        'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotPolicyCache'
    )
    $any = $false
    foreach ($p in $paths) {
        try {
            if (Test-Path $p) {
                Write-Log "Removing cache key: $p"
                Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
                $any = $true
            }
        } catch {
            Write-Log "Could not remove ${p}: $($_.Exception.Message)" -Level WARN
            $script:Warnings++
        }
    }
    $ppkgCache = 'C:\Recovery\AutoApply'
    try {
        if (Test-Path $ppkgCache) {
            $items = Get-ChildItem -Path $ppkgCache -Filter '*.ppkg' -ErrorAction SilentlyContinue
            if ($items) {
                Write-Log "Removing $($items.Count) staged .ppkg file(s) from $ppkgCache"
                $items | Remove-Item -Force -ErrorAction SilentlyContinue
                $any = $true
            }
        }
    } catch {
        Write-Log "Could not clean ${ppkgCache}: $($_.Exception.Message)" -Level WARN
        $script:Warnings++
    }
    if ($any) { $script:Applied++ } else { Write-Log 'No Autopilot reset artifacts found.'; $script:Skipped++ }
}

function Set-RecommendedSettings {
    Write-Log 'Applying recommended CloudPC image settings...'
    try {
        # Ensure Windows Consumer Experience stays disabled (no consumer app re-provisioning).
        $cloudContent = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        if (-not (Test-Path $cloudContent)) { New-Item -Path $cloudContent -Force | Out-Null }
        Set-ItemProperty -Path $cloudContent -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord -Force
        Write-Log '[OK] DisableWindowsConsumerFeatures = 1'
        $script:Applied++
    } catch {
        Write-Log "Could not apply recommended settings: $($_.Exception.Message)" -Level WARN
        $script:Warnings++
    }
    # Note: time zone redirection is an RDP/session-host policy, NOT an image requirement.
    Write-Log 'Note: time zone redirection is a session policy, not an image setting; no change needed here.'
}

function Invoke-CloudPCSysprep {
    Write-Log "RunSysprep set; invoking shared sysprep: $SysprepScriptPath"
    if (-not (Test-Path $SysprepScriptPath)) {
        throw "Sysprep script not found at $SysprepScriptPath"
    }
    # Stop our transcript first; sysprep tears the session down.
    try { Stop-Transcript | Out-Null } catch {}
    & $SysprepScriptPath -VMMode
    $code = $LASTEXITCODE
    if ($code -and $code -ne 0) {
        Write-Log "Sysprep script exited with code $code" -Level ERROR
        exit $code
    }
    Write-Log 'Sysprep script completed.'
}

# ---- Main ------------------------------------------------------------------

$started = Get-Date
Write-Log "===== Prepare_CloudPC starting (Decrypt=$([bool]$Decrypt), RunSysprep=$([bool]$RunSysprep)) ====="

Clear-EnrollmentState
Remove-ProvisioningPackages
Test-CloudPCBitLocker
Clear-AutopilotArtifacts
Set-RecommendedSettings

Write-Log '===== Prepare_CloudPC summary ====='
Write-Log ("Applied: {0}, Skipped: {1}, Warnings: {2}" -f $script:Applied, $script:Skipped, $script:Warnings)

if ($RunSysprep) {
    Invoke-CloudPCSysprep
} else {
    Write-Log 'Preparation complete. To generalize this image for Windows 365 CloudPC, run:'
    Write-Log '  windows-server-Invoke_Sysprep.ps1 -VMMode'
    Write-Log '(this produces sysprep /generalize /oobe /mode:vm /shutdown). Run windows11-Validate_CloudPC_Image.ps1 first to confirm compliance.'
}

$elapsed = [int]((Get-Date) - $started).TotalSeconds
Write-Log "===== Prepare_CloudPC complete in ${elapsed}s ====="

try { Stop-Transcript | Out-Null } catch {}
exit 0
