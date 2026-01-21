<#
.SYNOPSIS
    Configure Windows UI Performance Tweaks

.DESCRIPTION
    Optimizes Windows 10/11 UI settings for best performance by disabling visual effects,
    animations, and enabling helpful Explorer settings like showing file extensions.

.NOTES
    File Name      : windows11-UI_Tweaks.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-UI_Tweaks.ps1
    Applies performance-oriented UI tweaks
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

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
    Write-Host "[$timestamp] [$prefix] [UITweaks] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

$tweaks = @(
    @{ Desc = 'Show file extensions'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideFileExt -Type DWORD -Value 0 }},
    @{ Desc = 'Show hidden files'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Hidden -Type DWORD -Value 1 }},
    @{ Desc = 'Launch Explorer to This PC'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name LaunchTo -Type DWORD -Value 1 }},
    @{ Desc = 'Show full path in address bar'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name FullPathAddress -Type DWORD -Value 1 }},
    @{ Desc = 'Disable balloon tips'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name EnableBalloonTips -Type DWORD -Value 0 }},
    @{ Desc = 'Disable error reporting UI'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting' -Name DontShowUI -Type DWORD -Value 1 }},
    @{ Desc = 'Disable shutdown reason prompt'; Script = { Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name ShutdownReasonOn -Type DWORD -Value 0 }},
    @{ Desc = 'Set visual effects to best performance'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Type DWORD -Value 2 }},
    @{ Desc = 'Disable common tasks in folders'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name WebView -Type DWORD -Value 0 }},
    @{ Desc = 'Disable icon label shadows'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name ListviewShadow -Type DWORD -Value 0 }},
    @{ Desc = 'Disable folder background images'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name ListviewWatermark -Type DWORD -Value 0 }},
    @{ Desc = 'Disable taskbar button animations'; Script = { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarAnimations -Type DWORD -Value 0 }},
    @{ Desc = 'Disable minimize/maximize animations'; Script = { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -Type STRING -Value 0 }},
    @{ Desc = 'Disable show window contents while dragging'; Script = { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name DragFullWindows -Type STRING -Value 0 }},
    @{ Desc = 'Disable font smoothing'; Script = { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Type STRING -Value 0 }},
    @{ Desc = 'Disable UI animations and effects'; Script = { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name UserPreferencesMask -Type BINARY -Value ([byte[]](0x90,0x12,0x01,0x80)) }}
)

try {
    Write-Log "Applying Windows UI performance tweaks..."
    
    $successCount = 0
    $failCount = 0
    
    foreach ($tweak in $tweaks) {
        try {
            Write-Log "Applying: $($tweak.Desc)"
            & $tweak.Script
            $successCount++
        } catch {
            Write-Log "Failed to apply tweak '$($tweak.Desc)': $($_.Exception.Message)" -Level Warning
            $failCount++
        }
    }
    
    Write-Log "UI tweaks completed - $successCount succeeded, $failCount failed"
    
} catch {
    Write-Log "UI tweaks failed: $($_.Exception.Message)" -Level Error
    exit 1
}
