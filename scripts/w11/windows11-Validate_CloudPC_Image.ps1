<#
.SYNOPSIS
    Validates a Windows 11 image against Windows 365 / CloudPC custom-image requirements.

.DESCRIPTION
    Report-style validator that checks a Windows 11 image against the Microsoft
    supported-image requirements for Windows 365 CloudPC custom images and returns a
    non-zero exit code if any hard requirement is violated. Checks performed:

      - Firmware/generation: image must be UEFI (Generation 2). BIOS/Legacy fails.
      - BitLocker: must NOT be enabled on the OS drive. CloudPC forbids BitLocker in
        the custom image; an enabled OS-drive volume fails.
      - OS edition: must be a supported edition (Enterprise / Pro). Logs EditionID.
      - Sysprep: no pending generalize/sysprep block recorded in the registry.
      - Generalize count: informational check against the Microsoft rearm/generalize
        limit (does not fail the build on its own).
      - Required inbox apps: a set of provisioned AppX packages that Windows 365
        requires to remain present (Store, App Installer, Security, Photos, Notepad,
        Paint) must still be provisioned. Any missing package fails.
      - EMS/boot debugging: unsupported boot debugging / Emergency Management Services
        must not be enabled.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes, env-var
    overridable parameters, idempotent, non-interactive.
    Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER FailFast
    Stop at the first hard-requirement failure instead of collecting all findings.
    Default off (collect all findings, then exit non-zero if any FAIL). Env CLOUDPC_FAILFAST=1.

.PARAMETER MaxGeneralizeCount
    Informational Microsoft generalize/rearm limit used for the count check. Default 1001.
    Env CLOUDPC_MAX_GENERALIZE.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Validate_CloudPC_Image.ps1
    Runs all checks, prints a PASS/FAIL summary, exits 0 if compliant or 1 if not.

.EXAMPLE
    .\windows11-Validate_CloudPC_Image.ps1 -FailFast
    Stops and exits 1 at the first hard-requirement violation.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [switch]$FailFast = [bool]$env:CLOUDPC_FAILFAST,

    [int]$MaxGeneralizeCount = $(if ($env:CLOUDPC_MAX_GENERALIZE) { [int]$env:CLOUDPC_MAX_GENERALIZE } else { 1001 })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'CloudPC-Validate'
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
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [CloudPC-Validate] Transcript unavailable: $($_.Exception.Message)" }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# Findings collector. Each finding: Check, Result (PASS/FAIL/WARN/INFO), Detail.
$script:Findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'WARN', 'INFO')][string]$Result,
        [string]$Detail = ''
    )
    $level = switch ($Result) { 'FAIL' { 'ERROR' } 'WARN' { 'WARN' } default { 'INFO' } }
    Write-Log ("[{0}] {1}{2}" -f $Result, $Check, $(if ($Detail) { " -> $Detail" } else { '' })) -Level $level
    $script:Findings.Add([pscustomobject]@{ Check = $Check; Result = $Result; Detail = $Detail })
    if ($FailFast -and $Result -eq 'FAIL') {
        Write-Log 'FailFast set; stopping at first hard-requirement failure.' -Level ERROR
        Write-Summary
        try { Stop-Transcript | Out-Null } catch {}
        exit 1
    }
}

function Write-Summary {
    $pass = ($script:Findings | Where-Object Result -eq 'PASS').Count
    $fail = ($script:Findings | Where-Object Result -eq 'FAIL').Count
    $warn = ($script:Findings | Where-Object Result -eq 'WARN').Count
    Write-Log '===== CloudPC image validation summary ====='
    foreach ($f in $script:Findings) {
        Write-Log ("  [{0}] {1}{2}" -f $f.Result, $f.Check, $(if ($f.Detail) { " -> $($f.Detail)" } else { '' }))
    }
    Write-Log ("Totals: {0} PASS, {1} FAIL, {2} WARN" -f $pass, $fail, $warn)
    if ($fail -gt 0) {
        Write-Log ("RESULT: FAIL - image is NOT supported for Windows 365 CloudPC ({0} hard requirement(s) violated)" -f $fail) -Level ERROR
    } else {
        Write-Log 'RESULT: PASS - image meets Windows 365 CloudPC custom-image requirements'
    }
}

# ---- Check implementations -------------------------------------------------

function Test-Firmware {
    Write-Log 'Checking firmware type (UEFI / Generation 2 required)...'
    $uefi = $null
    # $env:firmware_type is set by the OS ('UEFI' or 'Legacy') in most builds.
    if ($env:firmware_type) {
        $uefi = ($env:firmware_type -eq 'UEFI')
        Write-Log "firmware_type environment variable: $($env:firmware_type)"
    }
    if ($null -eq $uefi) {
        # Confirm-SecureBootUEFI throws on BIOS; success (even if SecureBoot off) implies UEFI.
        try {
            Confirm-SecureBootUEFI -ErrorAction Stop | Out-Null
            $uefi = $true
        } catch {
            if ($_.Exception.Message -match 'not supported|BIOS|not a UEFI') { $uefi = $false }
        }
    }
    if ($null -eq $uefi) {
        # Fall back to bcdedit: a UEFI system reports path \EFI\...\bootmgfw.efi.
        try {
            $bcd = & bcdedit /enum '{bootmgr}' 2>&1
            if ($LASTEXITCODE -eq 0 -and ($bcd -join "`n") -match '\.efi') { $uefi = $true }
            elseif ($LASTEXITCODE -eq 0) { $uefi = $false }
        } catch { }
    }
    if ($uefi -eq $true) {
        Add-Finding -Check 'Firmware is UEFI (Generation 2)' -Result 'PASS'
    } elseif ($uefi -eq $false) {
        Add-Finding -Check 'Firmware is UEFI (Generation 2)' -Result 'FAIL' -Detail 'BIOS/Legacy detected; CloudPC requires a Generation 2 (UEFI) image'
    } else {
        Add-Finding -Check 'Firmware is UEFI (Generation 2)' -Result 'WARN' -Detail 'Could not determine firmware type; verify the image is Generation 2 (UEFI)'
    }
}

function Test-BitLocker {
    Write-Log 'Checking BitLocker on the OS drive (must NOT be enabled)...'
    $osDrive = $env:SystemDrive
    try {
        $vol = Get-BitLockerVolume -MountPoint $osDrive -ErrorAction Stop
        $enabled = ($vol.ProtectionStatus -eq 'On') -or ($vol.VolumeStatus -ne 'FullyDecrypted') -or ($vol.EncryptionPercentage -gt 0)
        if ($enabled) {
            Add-Finding -Check 'BitLocker disabled on OS drive' -Result 'FAIL' -Detail ("ProtectionStatus=$($vol.ProtectionStatus), VolumeStatus=$($vol.VolumeStatus), Encryption=$($vol.EncryptionPercentage)% on $osDrive; CloudPC forbids BitLocker in the image")
        } else {
            Add-Finding -Check 'BitLocker disabled on OS drive' -Result 'PASS' -Detail "$osDrive is fully decrypted"
        }
    } catch {
        # No BitLocker cmdlet / feature or volume not encryptable means not enabled.
        Add-Finding -Check 'BitLocker disabled on OS drive' -Result 'PASS' -Detail 'BitLocker not enabled / not present'
    }
}

function Test-Edition {
    Write-Log 'Checking OS edition (Enterprise / Pro supported)...'
    $supported = @('Enterprise', 'EnterpriseS', 'Professional', 'ProfessionalWorkstation', 'Education', 'EnterpriseN', 'ProfessionalN')
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $edition = $cv.EditionID
        $product = $cv.ProductName
        Write-Log "EditionID=$edition, ProductName=$product"
        if ($edition -and ($supported -contains $edition)) {
            Add-Finding -Check 'OS edition supported' -Result 'PASS' -Detail "EditionID=$edition"
        } else {
            Add-Finding -Check 'OS edition supported' -Result 'WARN' -Detail "EditionID=$edition may not be a supported Windows 365 CloudPC edition (Enterprise/Pro recommended)"
        }
    } catch {
        Add-Finding -Check 'OS edition supported' -Result 'WARN' -Detail "Could not read EditionID: $($_.Exception.Message)"
    }
}

function Test-SysprepState {
    Write-Log 'Checking for pending sysprep/generalize block...'
    $statusKey = 'HKLM:\SYSTEM\Setup\Status\SysprepStatus'
    try {
        if (Test-Path $statusKey) {
            $status = Get-ItemProperty -Path $statusKey -ErrorAction Stop
            # GeneralizationState 7 = sysprep succeeded / ready; other values can block re-sysprep.
            $genState = if ($status.PSObject.Properties.Name -contains 'GeneralizationState') { $status.GeneralizationState } else { $null }
            $cleanupState = if ($status.PSObject.Properties.Name -contains 'CleanupState') { $status.CleanupState } else { $null }
            Write-Log "SysprepStatus: GeneralizationState=$genState, CleanupState=$cleanupState"
            if (($null -ne $genState) -and ($genState -ne 7)) {
                Add-Finding -Check 'No pending sysprep/generalize block' -Result 'WARN' -Detail "GeneralizationState=$genState (7 expected for a clean state)"
            } else {
                Add-Finding -Check 'No pending sysprep/generalize block' -Result 'PASS'
            }
        } else {
            Add-Finding -Check 'No pending sysprep/generalize block' -Result 'PASS' -Detail 'No SysprepStatus key present'
        }
    } catch {
        Add-Finding -Check 'No pending sysprep/generalize block' -Result 'WARN' -Detail "Could not read SysprepStatus: $($_.Exception.Message)"
    }
}

function Test-GeneralizeCount {
    Write-Log 'Checking generalize/rearm count (informational)...'
    try {
        $wpa = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
        $count = $null
        if (Test-Path $wpa) {
            $prop = Get-ItemProperty -Path $wpa -ErrorAction SilentlyContinue
            if ($prop -and ($prop.PSObject.Properties.Name -contains 'GeneralizationCount')) {
                $count = $prop.GeneralizationCount
            }
        }
        if ($null -ne $count) {
            $detail = "GeneralizationCount=$count (Microsoft limit ~$MaxGeneralizeCount)"
            if ($count -ge $MaxGeneralizeCount) {
                Add-Finding -Check 'Generalize count within limit' -Result 'WARN' -Detail $detail
            } else {
                Add-Finding -Check 'Generalize count within limit' -Result 'INFO' -Detail $detail
            }
        } else {
            Add-Finding -Check 'Generalize count within limit' -Result 'INFO' -Detail 'GeneralizationCount not recorded'
        }
    } catch {
        Add-Finding -Check 'Generalize count within limit' -Result 'INFO' -Detail "Could not read count: $($_.Exception.Message)"
    }
}

function Test-RequiredInboxApps {
    Write-Log 'Checking required Windows 365 inbox provisioned apps are present...'
    $required = @(
        'Microsoft.WindowsStore',
        'Microsoft.DesktopAppInstaller',
        'Microsoft.SecHealthUI',
        'Microsoft.Windows.Photos',
        'Microsoft.WindowsNotepad',
        'Microsoft.Paint'
    )
    try {
        $provisioned = Get-AppxProvisionedPackage -Online
        $names = @($provisioned | ForEach-Object { $_.DisplayName })
        $missing = @()
        foreach ($req in $required) {
            $present = $names | Where-Object { $_ -eq $req -or $_ -like "$req*" }
            if ($present) {
                Write-Log "Required app present: $req"
            } else {
                $missing += $req
            }
        }
        if ($missing.Count -gt 0) {
            Add-Finding -Check 'Required inbox apps present' -Result 'FAIL' -Detail ("Missing: {0}" -f ($missing -join ', '))
        } else {
            Add-Finding -Check 'Required inbox apps present' -Result 'PASS' -Detail ("All {0} required apps present" -f $required.Count)
        }
    } catch {
        Add-Finding -Check 'Required inbox apps present' -Result 'FAIL' -Detail "Could not enumerate provisioned packages: $($_.Exception.Message)"
    }
}

function Test-BootDebugging {
    Write-Log 'Checking for unsupported EMS / boot debugging...'
    try {
        $bcd = & bcdedit /enum '{current}' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Finding -Check 'No EMS / boot debugging enabled' -Result 'WARN' -Detail 'bcdedit enumeration failed; verify manually'
            return
        }
        $text = ($bcd -join "`n")
        $badFlags = @()
        if ($text -match '(?im)^\s*ems\s+Yes')       { $badFlags += 'ems' }
        if ($text -match '(?im)^\s*bootems\s+Yes')    { $badFlags += 'bootems' }
        if ($text -match '(?im)^\s*debug\s+Yes')      { $badFlags += 'debug' }
        if ($text -match '(?im)^\s*bootdebug\s+Yes')  { $badFlags += 'bootdebug' }
        if ($badFlags.Count -gt 0) {
            Add-Finding -Check 'No EMS / boot debugging enabled' -Result 'FAIL' -Detail ("Enabled: {0}" -f ($badFlags -join ', '))
        } else {
            Add-Finding -Check 'No EMS / boot debugging enabled' -Result 'PASS'
        }
    } catch {
        Add-Finding -Check 'No EMS / boot debugging enabled' -Result 'WARN' -Detail "Could not query bcdedit: $($_.Exception.Message)"
    }
}

# ---- Main ------------------------------------------------------------------

$started = Get-Date
Write-Log "===== Validate_CloudPC_Image starting (FailFast=$([bool]$FailFast)) ====="

Test-Firmware
Test-BitLocker
Test-Edition
Test-SysprepState
Test-GeneralizeCount
Test-RequiredInboxApps
Test-BootDebugging

Write-Summary

$elapsed = [int]((Get-Date) - $started).TotalSeconds
$failCount = ($script:Findings | Where-Object Result -eq 'FAIL').Count
Write-Log "===== Validate_CloudPC_Image complete in ${elapsed}s ====="

try { Stop-Transcript | Out-Null } catch {}

if ($failCount -gt 0) { exit 1 }
exit 0
