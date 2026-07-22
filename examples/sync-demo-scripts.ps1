<#
.SYNOPSIS
    Vendors the provisioning scripts each demo set references into its alpaka/scripts/ folder.

.DESCRIPTION
    Every demo set under examples/<set>/ has an alpaka/template.yaml whose `powershell`/`shell`
    actions reference scripts by an IN-TREE relative path (scripts/<name>). alpaka resolves
    script paths inside the template's own directory, so the referenced repo scripts must be
    copied next to the template before a build (or before uploading the set into a XOAP
    workspace). This script reads each template's `script:` references and copies the matching
    file from the repo's scripts/ tree into examples/<set>/alpaka/scripts/.

    alpaka/scripts/ is git-ignored (see examples/.gitignore) — it is build/upload scratch, not
    source. Re-run this whenever the underlying scripts change.

    Follows docs/SCRIPT_CONTRACT.md: stdout logging, explicit exit codes, non-interactive.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.PARAMETER Set
    Sync a single demo set (folder name under examples/, e.g. w11-avd). Default: all sets.

.PARAMETER RepoRoot
    Repo root. Defaults to the parent of this script's directory.

.EXAMPLE
    pwsh examples/sync-demo-scripts.ps1
    Vendor scripts for every demo set.

.EXAMPLE
    pwsh examples/sync-demo-scripts.ps1 -Set w11-avd
    Vendor scripts for just the AVD demo.

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>
[CmdletBinding()]
param(
    [string]$Set,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [Sync] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    exit 1
}

$examplesDir = Join-Path $RepoRoot 'examples'
$scriptsRoot = Join-Path $RepoRoot 'scripts'

$started = Get-Date
Write-Log "===== sync-demo-scripts starting (Set=$(if ($Set) { $Set } else { 'ALL' })) ====="

# Build an index of repo scripts by file name for fast lookup.
$index = @{}
Get-ChildItem -Path $scriptsRoot -Recurse -File -Include *.ps1, *.sh | ForEach-Object {
    if (-not $index.ContainsKey($_.Name)) { $index[$_.Name] = $_.FullName }
}

$setDirs = if ($Set) {
    @(Join-Path $examplesDir $Set)
} else {
    Get-ChildItem -Path $examplesDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'alpaka/template.yaml') } | ForEach-Object { $_.FullName }
}

$copied = 0; $missing = 0; $setsDone = 0
foreach ($dir in $setDirs) {
    $template = Join-Path $dir 'alpaka/template.yaml'
    if (-not (Test-Path $template)) { Write-Log "No alpaka/template.yaml in $dir; skipping." -Level WARN; continue }
    $vendor = Join-Path $dir 'alpaka/scripts'
    New-Item -Path $vendor -ItemType Directory -Force | Out-Null

    # Extract `script: "scripts/<name>"` references from the template.
    $refs = Select-String -Path $template -Pattern 'script:\s*"?scripts/([^"\s]+)"?' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

    foreach ($rel in $refs) {
        $name = Split-Path $rel -Leaf
        if (-not $index.ContainsKey($name)) {
            Write-Log "Referenced script not found in repo scripts/: $name (set $(Split-Path $dir -Leaf))" -Level WARN
            $missing++
            continue
        }
        Copy-Item -Path $index[$name] -Destination (Join-Path $vendor $name) -Force
        $copied++
    }
    $setsDone++
    Write-Log "$(Split-Path $dir -Leaf): vendored $($refs.Count) script(s) into alpaka/scripts/"
}

$elapsed = [int]((Get-Date) - $started).TotalSeconds
Write-Log "===== sync complete in ${elapsed}s; sets=$setsDone copied=$copied missing=$missing ====="
if ($missing -gt 0) { exit 1 }
exit 0
