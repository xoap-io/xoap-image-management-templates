<#
.SYNOPSIS
    Installs the Remote Desktop Session Host (RDSH) role for AVD-on-Server / multi-session.

.DESCRIPTION
    Installs the Remote Desktop Session Host role (Windows feature RDS-RD-Server) with its
    management tools on Windows Server (e.g. Server 2025) so the host can serve Azure Virtual
    Desktop / RDS multi-session workloads.

    The install is idempotent: if the feature is already installed it is reported and skipped.
    Install-WindowsFeature returns a result object; when a restart is required the script logs
    it and exits 3010 so the build pipeline can treat it as "success, reboot needed".

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes (0 success,
    3010 reboot required, non-zero failure), idempotent, non-interactive.
    Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Install_RDSH_Role.ps1
    Installs the RD Session Host role, exiting 3010 if a reboot is required.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'RDSH'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

# Optional transcript in addition to stdout.
try {
    $LogDir = 'C:\xoap-logs'
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $LogDir "windows-server-Install_RDSH_Role-$ts.log"
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Log "Transcript unavailable: $($_.Exception.Message)" -Level WARN }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$started = Get-Date
Write-Log '===== Install_RDSH_Role starting ====='

# ServerManager is required for Install-WindowsFeature / Get-WindowsFeature.
Import-Module ServerManager -ErrorAction Stop

$featureName = 'RDS-RD-Server'

$feature = Get-WindowsFeature -Name $featureName -ErrorAction Stop
if (-not $feature) { throw "Windows feature $featureName is not available on this OS (Windows Server required)." }

if ($feature.Installed) {
    Write-Log "[OK] $featureName is already installed; nothing to do."
    Write-Log "===== Install_RDSH_Role complete in $([int]((Get-Date) - $started).TotalSeconds)s; applied=0 skipped=1 failed=0 ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

Write-Log "Installing $featureName with management tools..."
$result = Install-WindowsFeature -Name $featureName -IncludeManagementTools

Write-Log "===== Install_RDSH_Role complete in $([int]((Get-Date) - $started).TotalSeconds)s; applied=1 skipped=0 failed=0 ====="

try { Stop-Transcript | Out-Null } catch {}

if (-not $result.Success) {
    Write-Log "RDSH role installation failed (ExitCode: $($result.ExitCode))." -Level ERROR
    exit 1
}

# RestartNeeded is an enum: Yes / No / Maybe. Any non-No value warrants a reboot.
if ("$($result.RestartNeeded)" -ne 'No') {
    Write-Log 'RDSH role installed; reboot required to complete (exit 3010).'
    exit 3010
}

Write-Log '[OK] RDSH role installation complete.'
exit 0
