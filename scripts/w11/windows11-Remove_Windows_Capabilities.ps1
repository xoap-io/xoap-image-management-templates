<#
.SYNOPSIS
    Remove Windows Capabilities

.DESCRIPTION
    Removes optional Windows 10/11 capabilities to reduce image size and attack surface.
    Targets features like fax, handwriting, IE, Media Player, and other optional components.

.NOTES
    File Name      : windows11-Remove_Windows_Capabilities.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Remove_Windows_Capabilities.ps1
    Removes specified Windows capabilities
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
    Write-Host "[$timestamp] [$prefix] [RemoveCap] $Message"
}

$selectors = @(
    'Print.Fax.Scan',
    'Language.Handwriting',
    'Browser.InternetExplorer',
    'MathRecognizer',
    'OneCoreUAP.OneSync',
    'Microsoft.Windows.MSPaint',
    'App.Support.QuickAssist',
    'Microsoft.Windows.SnippingTool',
    'Language.Speech',
    'Language.TextToSpeech',
    'App.StepsRecorder',
    'Hello.Face.18967',
    'Hello.Face.Migration.18967',
    'Hello.Face.20134',
    'Media.WindowsMediaPlayer'
)

try {
    Write-Log "Starting Windows capability removal..."
    
    $installed = Get-WindowsCapability -Online | Where-Object {
        $_.State -notin @('NotPresent', 'Removed')
    }
    
    foreach ($selector in $selectors) {
        $found = $installed | Where-Object {
            ($_.Name -split '~')[0] -eq $selector
        }
        
        if ($found) {
            Write-Log "Removing capability: $selector"
            try {
                $found | Remove-WindowsCapability -Online -ErrorAction Stop | Out-Null
                Write-Log "Capability removed: $selector"
            } catch {
                Write-Log "Failed to remove capability $selector : $($_.Exception.Message)" -Level Warning
            }
        } else {
            Write-Log "Capability not installed: $selector" -Level Info
        }
    }
    
    Write-Log "Capability removal process completed"
    
} catch {
    Write-Log "Capability removal failed: $($_.Exception.Message)" -Level Error
    exit 1
}
