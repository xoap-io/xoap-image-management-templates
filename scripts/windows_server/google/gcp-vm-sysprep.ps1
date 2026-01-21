<#
.SYNOPSIS
    Run Google Compute Engine Sysprep for Image Preparation

.DESCRIPTION
    Executes Windows Sysprep with GCE-specific configuration to prepare
    VM for image creation. Removes machine-specific information and
    configures VM for first boot with GCE startup scripts.

.NOTES
    File Name      : gcp-vm-sysprep.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER Generalize
    Run sysprep with generalize option

.PARAMETER Shutdown
    Shutdown after sysprep completion

.EXAMPLE
    .\gcp-vm-sysprep.ps1
    Runs sysprep without shutdown

.EXAMPLE
    .\gcp-vm-sysprep.ps1 -Generalize -Shutdown
    Runs generalized sysprep with shutdown

.LINK
    https://github.com/xoap-io/xoap-packer-templates
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
$scriptName = 'gcp-vm-sysprep'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

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
    $logMessage = "[$timestamp] [$prefix] [GCPSysprep] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    Write-Log "========================================================="
    Write-Log "Google Compute Engine VM Sysprep"
    Write-Log "========================================================="
    Write-Log "Generalize: $Generalize"
    Write-Log "Shutdown: $Shutdown"
    Write-Log ""
    
    # Verify GCE environment
    Write-Log "Verifying GCE environment..."
    try {
        $instanceId = Invoke-RestMethod -Uri 'http://metadata.google.internal/computeMetadata/v1/instance/id' `
            -Headers @{'Metadata-Flavor'='Google'} -TimeoutSec 2
        Write-Log "✓ Running on GCE instance: $instanceId"
    }
    catch {
        Write-Log "Warning: Not running on GCE instance" -Level Warning
    }
    
    # Configure RDP
    Write-Log ""
    Write-Log "Configuring RDP..."
    $rdpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    Set-ItemProperty -Path $rdpPath -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
    Write-Log "✓ Enabled RDP"
    
    # Configure GCE agent (if present)
    Write-Log ""
    Write-Log "Checking GCE agent..."
    $gceService = Get-Service -Name 'GCEAgent' -ErrorAction SilentlyContinue
    if ($gceService) {
        Write-Log "✓ GCE Agent: $($gceService.Status)"
    }
    else {
        Write-Log "GCE Agent not found" -Level Warning
    }
    
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
        Write-Log "✓ Sysprep completed successfully"
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
    Write-Log ""
    Write-Log "VM is ready for GCE image creation"
    
} catch {
    Write-Log "Sysprep failed: $_" -Level Error
    exit 1
}
