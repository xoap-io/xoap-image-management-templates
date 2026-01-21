<#
.SYNOPSIS
    Prepare Azure Virtual Desktop Image

.DESCRIPTION
    Prepares a Windows Server or Windows 10/11 image for Azure Virtual Desktop (AVD) customization.
    Disables Windows Defender real-time scanning and Windows Store updates.

.NOTES
    File Name      : windows11-Prepare_AVD_Imaging.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Prepare_AVD_Imaging.ps1
    Prepares image for AVD customization
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
