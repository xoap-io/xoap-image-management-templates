<#
.SYNOPSIS
    Run Azure VM Sysprep for Image Preparation

.DESCRIPTION
    Executes Windows Sysprep to prepare Azure VM for image capture.
    Configures VM for first boot, removes machine-specific information,
    and prepares Windows for Azure image creation.

.NOTES
    File Name      : azure-vm-sysprep.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER Generalize
    Run sysprep with generalize option

.PARAMETER Shutdown
    Shutdown after sysprep completion

.EXAMPLE
    .\azure-vm-sysprep.ps1
    Runs sysprep without shutdown

.EXAMPLE
    .\azure-vm-sysprep.ps1 -Generalize -Shutdown
    Runs generalized sysprep with shutdown

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param (
    [switch]$Generalize,
    [switch]$Shutdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [AzureSysprep] Transcript unavailable: $($_.Exception.Message)" }

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [AzureSysprep] $Message"
    Write-Host $logMessage
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    Write-Log "===== azure-vm-sysprep starting ====="
    
    Write-Log "========================================================="
    Write-Log "Azure VM Sysprep"
    Write-Log "========================================================="
    Write-Log "Generalize: $Generalize"
    Write-Log "Shutdown: $Shutdown"
    Write-Log ""
    
    # Verify Azure VM Agent
    Write-Log "Verifying Azure VM Agent..."
    $waService = Get-Service -Name 'WindowsAzureGuestAgent' -ErrorAction SilentlyContinue
    if ($waService) {
        Write-Log "[OK] Azure VM Agent: $($waService.Status)"
    }
    else {
        Write-Log "Warning: Azure VM Agent not found" -Level WARN
    }
    
    # Configure RDP
    Write-Log ""
    Write-Log "Configuring RDP..."
    $rdpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    Set-ItemProperty -Path $rdpPath -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
    Write-Log "[OK] Enabled RDP"
    
    # Sysprep execution
    Write-Log ""
    Write-Log "Executing sysprep..."
    
    $sysprepPath = "$env:SystemRoot\System32\Sysprep\sysprep.exe"
    $sysprepArgs = @('/oobe', '/quiet')
    
    if ($Generalize) {
        $sysprepArgs += '/generalize'
        Write-Log "Mode: Generalize"
    }
    
    if ($Shutdown) {
        $sysprepArgs += '/shutdown'
        Write-Log "Action: Shutdown"
    }
    else {
        $sysprepArgs += '/quit'
        Write-Log "Action: Quit"
    }
    
    Write-Log "Command: $sysprepPath $($sysprepArgs -join ' ')"
    
    $process = Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Log "[OK] Sysprep completed successfully"
    }
    else {
        throw "Sysprep failed with exit code: $($process.ExitCode)"
    }
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Sysprep Summary"
    Write-Log "========================================================="
    Write-Log "Mode: $(if($Generalize){'Generalize'}else{'Standard'})"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    Write-Log "===== azure-vm-sysprep complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Sysprep failed: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
