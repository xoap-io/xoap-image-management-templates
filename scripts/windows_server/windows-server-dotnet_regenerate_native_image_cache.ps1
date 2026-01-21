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

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        default   { 'INFO' }
    }
    Write-Host "[$timestamp] [$prefix] [DotNet] $Message"
}

# Main script execution
try {
    Write-Log "Starting .NET native image cache regeneration..."
    
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
    
    Write-Log ".NET native image cache regeneration completed successfully"
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
