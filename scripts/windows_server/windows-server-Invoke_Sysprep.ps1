<#
.SYNOPSIS
    Performs final cleanup and generalizes a Windows image with Sysprep.

.DESCRIPTION
    Single, parameterized replacement for the previous near-identical sysprep scripts
    (Final_Cleanup_Sysprep, Final_Cleanup_Sysprep_oobe, Sysprep_Generalize and the
    Windows 11 equivalent). Optionally performs a final cleanup pass (temp files, logs,
    event logs, volume optimization) and then runs sysprep with the requested mode and
    shutdown behaviour, propagating the sysprep exit code so a failure fails the build.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes, env-var
    overridable parameters, idempotent, non-interactive.
    Developed for the XOAP Image Management module; usable independently.
    No liability is assumed for the function, use, or consequences of this script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER Mode
    Sysprep OOBE mode. 'OOBE' (default) or 'Audit'. Overridable via env SYSPREP_MODE.

.PARAMETER Shutdown
    Post-sysprep action: 'Shutdown' (default), 'Reboot', or 'Quit'. Env SYSPREP_SHUTDOWN.

.PARAMETER VMMode
    Adds /mode:vm (skips hardware-specific generalize steps; recommended for AVD/Citrix/CloudPC
    virtual images). Env SYSPREP_VMMODE=1.

.PARAMETER UnattendPath
    Optional path to a sysprep /unattend answer file. Env SYSPREP_UNATTEND.

.PARAMETER SkipCleanup
    Skip the pre-sysprep cleanup pass. Env SYSPREP_SKIPCLEANUP=1.

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Invoke_Sysprep.ps1
    Cleanup, then sysprep /generalize /oobe /shutdown /quiet.

.EXAMPLE
    .\windows-server-Invoke_Sysprep.ps1 -VMMode -Shutdown Shutdown
    Cleanup, then sysprep /generalize /oobe /mode:vm /shutdown /quiet (virtual images).

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [ValidateSet('OOBE', 'Audit')]
    [string]$Mode = $(if ($env:SYSPREP_MODE) { $env:SYSPREP_MODE } else { 'OOBE' }),

    [ValidateSet('Shutdown', 'Reboot', 'Quit')]
    [string]$Shutdown = $(if ($env:SYSPREP_SHUTDOWN) { $env:SYSPREP_SHUTDOWN } else { 'Shutdown' }),

    [switch]$VMMode = [bool]$env:SYSPREP_VMMODE,

    [string]$UnattendPath = $env:SYSPREP_UNATTEND,

    [switch]$SkipCleanup = [bool]$env:SYSPREP_SKIPCLEANUP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'Sysprep'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

# Optional transcript in addition to stdout.
try {
    $LogDir = 'C:\xoap-logs'
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $LogDir "windows-server-Invoke_Sysprep-$ts.log"
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Log "Transcript unavailable: $($_.Exception.Message)" -Level WARN }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level ERROR }
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$started = Get-Date
Write-Log "===== Invoke_Sysprep starting (Mode=$Mode, Shutdown=$Shutdown, VMMode=$([bool]$VMMode)) ====="

if (-not $SkipCleanup) {
    Write-Log 'Performing final system cleanup...'
    $cleanupPaths = @(
        'C:\Windows\Logs\*',
        'C:\Windows\Panther\*',
        'C:\Windows\SoftwareDistribution\Download\*',
        "$env:WINDIR\Temp\*",
        "$env:TEMP\*"
    )
    foreach ($path in $cleanupPaths) {
        try {
            if (Test-Path (Split-Path $path -Parent)) {
                $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                if ($items) {
                    Write-Log "Cleaning $path ($($items.Count) items)"
                    $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Log "Could not clean ${path}: $($_.Exception.Message)" -Level WARN
        }
    }

    Write-Log 'Clearing event logs...'
    try {
        Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
            try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch { }
        }
        Write-Log 'Event logs cleared'
    } catch { Write-Log 'Could not clear all event logs' -Level WARN }

    Write-Log 'Optimizing system drive...'
    try {
        Optimize-Volume -DriveLetter C -Defrag -Verbose:$false
        Write-Log 'System drive optimization completed'
    } catch { Write-Log "Could not optimize system drive: $($_.Exception.Message)" -Level WARN }
} else {
    Write-Log 'SkipCleanup set; proceeding directly to sysprep.'
}

# Build sysprep argument list.
$sysprepPath = Join-Path $env:WINDIR 'System32\Sysprep\sysprep.exe'
if (-not (Test-Path $sysprepPath)) { throw "sysprep.exe not found at $sysprepPath" }

$sysprepArgs = @('/generalize', '/quiet')
switch ($Mode) {
    'OOBE'  { $sysprepArgs += '/oobe' }
    'Audit' { $sysprepArgs += '/audit' }
}
if ($VMMode) { $sysprepArgs += '/mode:vm' }
switch ($Shutdown) {
    'Shutdown' { $sysprepArgs += '/shutdown' }
    'Reboot'   { $sysprepArgs += '/reboot' }
    'Quit'     { $sysprepArgs += '/quit' }
}
if ($UnattendPath) {
    if (Test-Path $UnattendPath) { $sysprepArgs += "/unattend:$UnattendPath"; Write-Log "Using unattend file: $UnattendPath" }
    else { Write-Log "Unattend file not found at ${UnattendPath}; ignoring." -Level WARN }
}

# Stop transcript before sysprep tears the session down.
try { Stop-Transcript | Out-Null } catch {}

Write-Log "Running: sysprep.exe $($sysprepArgs -join ' ')"
$proc = Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgs -Wait -PassThru -NoNewWindow
$elapsed = [int]((Get-Date) - $started).TotalSeconds
if ($proc.ExitCode -ne 0) {
    Write-Log "Sysprep failed with exit code $($proc.ExitCode) after ${elapsed}s" -Level ERROR
    exit $proc.ExitCode
}

Write-Log "===== Invoke_Sysprep complete in ${elapsed}s; action: $Shutdown ====="
exit 0
