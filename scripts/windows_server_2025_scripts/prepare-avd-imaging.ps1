<#
    .SYNOPSIS
        Preps a RDS/WVD image for customisation.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[CmdletBinding()]
Param ()

function Log {
    param([string]$msg)
    Write-Host "[AVD-PREP] $msg"
}

$ErrorActionPreference = 'Stop'

try {
    Log "Disabling Windows Defender real-time scan..."
    Set-MpPreference -DisableRealtimeMonitoring $true
    Log "Disabling Windows Store updates..."
    REG add HKLM\Software\Policies\Microsoft\Windows\CloudContent /v "DisableWindowsConsumerFeatures" /d 1 /t "REG_DWORD" /f
    REG add HKLM\Software\Policies\Microsoft\WindowsStore /v "AutoDownload" /d 2 /t "REG_DWORD" /f
    Log "Image preparation complete."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
