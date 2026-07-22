<#
.SYNOPSIS
    Regenerate .NET Native Image Cache

.DESCRIPTION
    Regenerates the .NET native image cache using ngen.exe for Windows Server 2025.
    Improves .NET application startup performance.

.NOTES
    File Name      : windows-server-dotnet_regenerate_native_image_cache.ps1
    Prerequisite   : PowerShell 5.1 or higher, .NET Framework 4.0+
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-dotnet_regenerate_native_image_cache
    Regenerates .NET native image cache
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Component = 'DotNet'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [DotNet] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

# Main script execution
try {
    $startTime = Get-Date
    Write-Log "===== dotnet_regenerate_native_image_cache starting ====="
    
    $ngenFramework = "$env:windir\microsoft.net\framework\v4.0.30319\ngen.exe"
    $ngenFramework64 = "$env:windir\microsoft.net\framework64\v4.0.30319\ngen.exe"
    
    if ([Environment]::Is64BitOperatingSystem) {
        Write-Log "Processing 64-bit .NET Framework..."
        
        # 32-bit Framework
        if (Test-Path $ngenFramework) {
            Write-Log "Updating 32-bit native images..."
            & $ngenFramework update /force /queue | Out-Null
            Write-Log "Executing queued items for 32-bit..."
            & $ngenFramework executequeueditems | Out-Null
        }
        
        # 64-bit Framework
        if (Test-Path $ngenFramework64) {
            Write-Log "Updating 64-bit native images..."
            & $ngenFramework64 update /force /queue | Out-Null
            Write-Log "Executing queued items for 64-bit..."
            & $ngenFramework64 executequeueditems | Out-Null
        }
    } else {
        Write-Log "Processing 32-bit .NET Framework..."
        
        if (Test-Path $ngenFramework) {
            Write-Log "Updating native images..."
            & $ngenFramework update /force /queue | Out-Null
            Write-Log "Executing queued items..."
            & $ngenFramework executequeueditems | Out-Null
        } else {
            throw "ngen.exe not found at: $ngenFramework"
        }
    }
    
    Write-Log "===== dotnet_regenerate_native_image_cache complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
