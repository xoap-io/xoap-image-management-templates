<#
.SYNOPSIS
    Disables unnecessary services on Windows Server 2025

.DESCRIPTION
    This script disables unnecessary Windows services to optimize performance and security on Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Disable_Unnecessary_Services.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Disable_Unnecessary_Services
    Disables unnecessary Windows services

.LINK
    https://github.com/xoap-io/xoap-packer-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Setup local file logging to C:\xoap-logs
try {
    $LogDir = 'C:\xoap-logs'
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Host "Logging to: $LogFile"
} catch {
    Write-Warning "Failed to start transcript logging to C:\xoap-logs: $($_.Exception.Message)"
}

# Simple logging function
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

try {
    Write-Log 'Starting service optimization'

    # Services to disable for server optimization
        $servicesToDisable = @(
            'Fax',              # Fax service (rarely used on servers)
            'Spooler',          # Print Spooler (disable if no printing required)
            'Themes',           # Desktop Themes (not needed for server/core)
            'TabletInputService', # Tablet PC Input (not needed on servers)
            'WebClient',        # WebDAV client (not needed for most servers)
            'WMPNetworkSvc',    # Windows Media Player Network Sharing Service
            'WSearch',          # Windows Search (indexing, not needed for most servers)
            'XblAuthManager',   # Xbox Live Authentication Manager
            'XblGameSave',      # Xbox Live Game Save
            'XboxNetApiSvc',    # Xbox Live Networking Service
            'PrintNotify',      # Print Notifications
            'RemoteRegistry',   # Remote Registry (security risk if not used)
            'bthserv',          # Bluetooth Support Service
            'SCardSvr',         # Smart Card
            'WerSvc',           # Windows Error Reporting Service
            'wuauserv',         # Windows Update (if managed externally)
            'DPS',              # Diagnostic Policy Service
            'wisvc',            # Windows Insider Service
            'PhoneSvc',         # Phone Service
            'RetailDemo',       # Retail Demo Service
            'seclogon',         # Secondary Logon
            'CscService',       # Offline Files
            'WcnSvc',           # Windows Connect Now
            'StiSvc',           # Windows Image Acquisition
            'FrameServer',      # Windows Camera Frame Server
            'WbioSrvc'          # Windows Biometric Service
            # 'TermService'     # Remote Desktop Services (excluded per user request)
        )

    Write-Log "Will attempt to disable $($servicesToDisable.Count) services"

    foreach ($serviceName in $servicesToDisable) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                Write-Log "Disabling service: $serviceName (Current: $($service.Status))"
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Set-Service -Name $serviceName -StartupType Disabled
                Write-Log "Successfully disabled: $serviceName"
            } else {
                Write-Log "Service not found: $serviceName"
            }
        } catch {
            Write-Log "Warning: Could not disable service $serviceName`: $($_.Exception.Message)"
        }
    }

    Write-Log "Service optimization completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
