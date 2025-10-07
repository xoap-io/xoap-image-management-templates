# Run-Sysprep.ps1
# This script runs sysprep with the unattend.xml file located in C:\ root
# and shuts down the VM after the sysprep process is finished with the generalize option

<#
.SYNOPSIS
    Runs sysprep with unattend.xml from C:\ root and shuts down the VM

.DESCRIPTION
    This script performs sysprep generalization using an unattend.xml file located at C:\unattend.xml
    and shuts down the system after the process completes successfully.

.PARAMETER UnattendPath
    Path to the unattend.xml file (default: C:\unattend.xml)

.EXAMPLE
    .\Run-Sysprep.ps1
    Runs sysprep with default unattend.xml path

.EXAMPLE
    .\Run-Sysprep.ps1 -UnattendPath "C:\custom-unattend.xml"
    Runs sysprep with custom unattend.xml path
#>

param(
    [string]$UnattendPath = "C:\unattend.xml"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Setup logging
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
    Write-Warning "Failed to start transcript logging: $($_.Exception.Message)"
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
    Write-Log "Starting sysprep process with generalize and shutdown options"
    
    # Validate unattend.xml file exists
    if (-not (Test-Path $UnattendPath)) {
        throw "Unattend.xml file not found at: $UnattendPath"
    }
    
    Write-Log "Found unattend.xml file at: $UnattendPath"
    
    # Validate sysprep executable exists
    $sysprepPath = Join-Path $env:WINDIR "System32\Sysprep\sysprep.exe"
    if (-not (Test-Path $sysprepPath)) {
        throw "Sysprep executable not found at: $sysprepPath"
    }
    
    Write-Log "Found sysprep executable at: $sysprepPath"
    
    # Prepare sysprep arguments
    $sysprepArgs = @(
        '/generalize',
        '/shutdown',
        '/quiet',
        "/unattend:$UnattendPath"
    )
    
    Write-Log "Sysprep command: $sysprepPath $($sysprepArgs -join ' ')"
    Write-Log "This will generalize the system and shut it down when complete"
    
    # Stop transcript before sysprep
    try { Stop-Transcript | Out-Null } catch {}
    
    # Run sysprep
    Write-Log "Starting sysprep process..."
    $process = Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgs -Wait -PassThru -NoNewWindow
    
    # Check exit code
    $exitCode = $process.ExitCode
    if ($null -eq $exitCode) {
        $exitCode = $LASTEXITCODE
    }
    
    if ($exitCode -eq 0) {
        Write-Log "Sysprep completed successfully."
        Write-Log "Forcing system shutdown in 30 seconds to ensure VM shuts down..."
        Start-Sleep -Seconds 5
        # Force shutdown as backup in case sysprep /shutdown doesn't work
        shutdown.exe /s /f /t 30 /c "Sysprep completed - shutting down system"
        Write-Log "System shutdown initiated."
    } else {
        Write-Log "Sysprep failed with exit code: $exitCode"
        Write-Log "Check Windows Event Logs for more details"
        exit $exitCode
    }
    
} catch {
    Write-Log "Critical error during sysprep: $($_.Exception.Message)"
    try { Stop-Transcript | Out-Null } catch {}
    throw
}