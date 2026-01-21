<#
.SYNOPSIS
    Disable Windows User Account Control (UAC)

.DESCRIPTION
    Disables UAC prompts on Windows 10/11 to enable unattended operations during Packer builds.
    Configures registry settings to suppress elevation prompts.

.NOTES
    File Name      : windows11-Disable_Windows_UAC.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Disable_Windows_UAC.ps1
    Disables User Account Control
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
    Write-Host "[$timestamp] [$prefix] [UAC] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    Write-Log "Disabling Windows User Account Control (UAC)..."
    
    $regPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    
    Write-Log "Setting ConsentPromptBehaviorAdmin to 0"
    Set-ItemProperty -Path $regPath -Name ConsentPromptBehaviorAdmin -Type DWORD -Value 0
    
    Write-Log "Setting PromptOnSecureDesktop to 0"
    Set-ItemProperty -Path $regPath -Name PromptOnSecureDesktop -Type DWORD -Value 0
    
    Write-Log "Setting EnableLUA to 0"
    Set-ItemProperty -Path $regPath -Name EnableLUA -Type DWORD -Value 0
    
    Write-Log "Setting LocalAccountTokenFilterPolicy to 1"
    Set-ItemProperty -Path $regPath -Name LocalAccountTokenFilterPolicy -Type DWORD -Value 1
    
    Write-Log "UAC disabled successfully - restart required for full effect"
    
} catch {
    Write-Log "Failed to disable UAC: $($_.Exception.Message)" -Level Error
    exit 1
}
