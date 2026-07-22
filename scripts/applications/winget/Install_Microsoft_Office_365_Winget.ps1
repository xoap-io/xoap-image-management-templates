<#
.SYNOPSIS
    Installs Microsoft Office (Microsoft 365 Apps) using winget on Windows Server 2025

.DESCRIPTION
    This script installs Microsoft Office (Microsoft 365 Apps for enterprise) using winget.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.
    PowerShell is a product of Microsoft Corporation. XOAP is a product of RIS AG. (c) RIS AG

.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-image-management-templates

#>
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [Winget] Transcript unavailable: $($_.Exception.Message)" }

function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [Winget] $Message"
}

trap {
    Write-Log "$_" -Level ERROR
    Write-Log "$($_.ScriptStackTrace)" -Level ERROR
    Write-Log "Exception: $($_.Exception.ToString())" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log "===== Install_Microsoft_Office_365_Winget starting ====="
    Write-Log "Installing Microsoft Office (Microsoft 365 Apps) via winget..."
    winget install --id Microsoft.Office --silent --accept-package-agreements --accept-source-agreements -e
    # winget: 0 = success, 3010 = reboot required, -1978335189 = no applicable update
    if ($LASTEXITCODE -notin @(0, 3010, -1978335189)) { throw "winget install failed (exit code $LASTEXITCODE)" }
    Write-Log "Microsoft Office (Microsoft 365 Apps) installed successfully."
    Write-Log "===== Install_Microsoft_Office_365_Winget complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit 0
