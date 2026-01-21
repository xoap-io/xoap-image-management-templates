<#
.SYNOPSIS
    Remove Windows Optional Features

.DESCRIPTION
    Disables and removes optional Windows 10/11 features including Media Playback,
    PowerShell V2, Recall, and Snipping Tool to reduce image size.

.NOTES
    File Name      : windows11-Remove_Features.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Remove_Features.ps1
    Removes specified Windows optional features
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

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
    Write-Host "[$timestamp] [$prefix] [RemoveFeat] $Message"
}

$selectors = @(
    'MediaPlayback',
    'MicrosoftWindowsPowerShellV2Root',
    'Recall',
    'Microsoft-SnippingTool'
)

try {
    Write-Log "Starting Windows optional feature removal..."
    
    $installed = Get-WindowsOptionalFeature -Online | Where-Object {
        $_.State -notin @('Disabled', 'DisabledWithPayloadRemoved')
    }
    
    foreach ($selector in $selectors) {
        $found = $installed | Where-Object { $_.FeatureName -eq $selector }
        
        if ($found) {
            Write-Log "Disabling and removing feature: $selector"
            try {
                $found | Disable-WindowsOptionalFeature -Online -Remove -NoRestart -ErrorAction Stop | Out-Null
                Write-Log "Feature removed: $selector"
            } catch {
                Write-Log "Failed to remove feature $selector : $($_.Exception.Message)" -Level Warning
            }
        } else {
            Write-Log "Feature not installed: $selector" -Level Info
        }
    }
    
    Write-Log "Feature removal process completed"
    
} catch {
    Write-Log "Feature removal failed: $($_.Exception.Message)" -Level Error
    exit 1
}
