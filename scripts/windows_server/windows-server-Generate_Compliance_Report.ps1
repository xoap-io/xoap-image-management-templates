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
    https://github.com/xoap-io/xoap-image-management-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Logging function
$script:Component = 'Compliance'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

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
    Write-Log "Logging to: $LogFile"
} catch {
    Write-Log "Failed to start transcript logging to C:\xoap-logs: $($_.Exception.Message)" -Level WARN
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    Write-Log "Exception: $($_.Exception.ToString())" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    $startTime = Get-Date
    Write-Log '===== Generate_Compliance_Report starting ====='

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
        Write-Log "Could not get power plan information" -Level WARN
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
            Write-Log "Could not check service $service" -Level WARN
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
            Write-Log "Could not check registry setting $($check.Path)\$($check.Name)" -Level WARN
        }
    }

    # Get recent updates
    try {
        $updates = Get-HotFix | Select-Object -First 10 HotFixID, Description, InstalledOn
        $complianceData.InstalledUpdates = $updates
        Write-Log "Found $($updates.Count) recent updates"
    } catch {
        Write-Log "Could not retrieve update information" -Level WARN
    }

    # Save report
    try {
        $complianceData | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Log "Compliance report saved successfully"
    } catch {
        Write-Log "Could not save compliance report: $($_.Exception.Message)" -Level WARN
    }

    Write-Log "Compliance report generation completed successfully"
    Write-Log "===== Generate_Compliance_Report complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    exit 0
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
