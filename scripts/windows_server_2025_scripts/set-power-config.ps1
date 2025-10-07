<#
.SYNOPSIS
  Set Power Config for Windows Server 2022.

.DESCRIPTION
  Sets the power configuration during the Packer build run.

.OUTPUTS
  C:\Windows\Temp\set-power-config.log

.NOTES
  Version:        1.1
  Author:         XOAP
  Creation Date:  2022-05-11
  Purpose/Change: Optimized for Windows Server 2022

.EXAMPLE
  script = "../../scripts/set-power-config.ps1"
#>

#---[Variables and Declarations]---------------------------------------------------------------

#Script Version
[int]$ScriptVersion = "1.1"

#Log File Info
[string]$LogPath = "C:\Windows\Temp"
[string]$LogName = "set-power-config.log"
[string]$LogFile = Join-Path -Path $LogPath -ChildPath $LogName

function Log {
    param([string]$msg)
    Write-Host "[POWER] $msg"
}

#---[Execution]--------------------------------------------------------------------------------

Start-Transcript -Append $LogFile

try {
    Log "Setting power configuration to High Performance..."
    powercfg -setactive SCHEME_MIN
    Log "Disabling monitor timeout..."
    powercfg -Change -monitor-timeout-ac 0
    powercfg -Change -monitor-timeout-dc 0
    Log "Disabling hibernate..."
    powercfg -hibernate OFF
    Log "Power configuration applied."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}

#---[Finish and Cleanup]-----------------------------------------------------------------------

Stop-Transcript
