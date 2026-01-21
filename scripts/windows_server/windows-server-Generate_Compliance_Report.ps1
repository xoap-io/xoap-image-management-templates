<#
.SYNOPSIS
    Generates a compliance report for Windows Server 2025

.DESCRIPTION
    This script generates a compliance report based on system configuration and applied policies for Windows Server 2025.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Generate_Compliance_Report.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Generate_Compliance_Report.ps1
    Generates system compliance report

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
    Write-Log 'Starting compliance report generation'

    $reportPath = Join-Path $LogDir "compliance-report-$timestamp.json"
    Write-Log "Report will be saved to: $reportPath"

    # Collect system information
    $complianceData = @{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ComputerName = $env:COMPUTERNAME
        OSVersion = (Get-WmiObject Win32_OperatingSystem).Caption
        PowerPlan = $null
        Services = @{}
        RegistrySettings = @{}
        InstalledUpdates = @()
    }

    # Get power plan
    try {
        $activePlan = Get-WmiObject -Namespace root\cimv2\power -Class Win32_PowerPlan | Where-Object { $_.IsActive -eq $true }
        $complianceData.PowerPlan = $activePlan.ElementName
        Write-Log "Power plan: $($activePlan.ElementName)"
    } catch {
        Write-Log "Warning: Could not get power plan information"
    }

    # Check critical services
    $criticalServices = @('wuauserv', 'BITS', 'CryptSvc', 'TrustedInstaller')
    foreach ($service in $criticalServices) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                $complianceData.Services[$service] = @{
                    Status = $svc.Status
                    StartType = $svc.StartType
                }
                Write-Log "Service $service`: $($svc.Status) ($($svc.StartType))"
            }
        } catch {
            Write-Log "Warning: Could not check service $service"
        }
    }

    # Check key registry settings
    $registryChecks = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableLUA' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry' }
    )

    foreach ($check in $registryChecks) {
        try {
            $value = Get-ItemProperty -Path $check.Path -Name $check.Name -ErrorAction SilentlyContinue
            if ($value) {
                $complianceData.RegistrySettings["$($check.Path)\$($check.Name)"] = $value.($check.Name)
                Write-Log "Registry: $($check.Path)\$($check.Name) = $($value.($check.Name))"
            }
        } catch {
            Write-Log "Warning: Could not check registry setting $($check.Path)\$($check.Name)"
        }
    }

    # Get recent updates
    try {
        $updates = Get-HotFix | Select-Object -First 10 HotFixID, Description, InstalledOn
        $complianceData.InstalledUpdates = $updates
        Write-Log "Found $($updates.Count) recent updates"
    } catch {
        Write-Log "Warning: Could not retrieve update information"
    }

    # Save report
    try {
        $complianceData | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Log "Compliance report saved successfully"
    } catch {
        Write-Log "Warning: Could not save compliance report: $($_.Exception.Message)"
    }

    Write-Log "Compliance report generation completed successfully"
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
