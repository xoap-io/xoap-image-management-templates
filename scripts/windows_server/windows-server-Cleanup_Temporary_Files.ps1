<#
.SYNOPSIS
    Cleans up temporary files, event logs, WinSxS, and more on Windows Server 2025.

.DESCRIPTION
    This script removes temporary files, cleans event logs, runs CleanMgr (on workstations), cleans WinSxS, and removes disabled features.
    Developed and optimized for use with the XOAP Scripted Actions module, but can be used independently.
    No liability is assumed for the function, use, or consequences of this freely available script.

.NOTES
    File Name      : windows-server-Cleanup_Temporary_Files.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows-server-Cleanup_Temporary_Files.ps1
    Cleans temporary files and optimizes disk space

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
    $LogFile = $null
}

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

<# trap {
    Write-Log "ERROR: $_"
    Write-Log "ERROR: $($_.ScriptStackTrace)"
    Write-Log "ERROR EXCEPTION: $($_.Exception.ToString())"
    try { Stop-Transcript | Out-Null } catch {}
    Write-Log 'Sleeping for 60m to give you time to look around the virtual machine before self-destruction...'
    Start-Sleep -Seconds (60*60)
    Exit 1
} #>

try {
    Write-Log 'Starting cleanup process...'

    # CleanMgr (workstation only)
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($osInfo.ProductType -eq 1) {
        Write-Log 'Running CleanMgr automation (workstation only)...'
        try {
            Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\*' -Name StateFlags0001 -ErrorAction SilentlyContinue | Remove-ItemProperty -Name StateFlags0001 -ErrorAction SilentlyContinue
            New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Update Cleanup' -Name StateFlags0001 -Value 2 -PropertyType DWord
            New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Temporary Files' -Name StateFlags0001 -Value 2 -PropertyType DWord
            Start-Process -FilePath CleanMgr.exe -ArgumentList '/sagerun:1' -Wait
            Get-Process -Name cleanmgr,dismhost -ErrorAction SilentlyContinue | Wait-Process
            Write-Log 'CleanMgr completed.'
        } catch {
            Write-Log "Warning: CleanMgr failed: $($_.Exception.Message)"
        }
    }

    # Clean event logs
    Write-Log 'Cleaning event logs...'
    foreach ($log in @('Application','Security','Setup','System')) {
        try {
            wevtutil clear-log $log
            Write-Log "Cleared event log: $log"
        } catch {
            Write-Log "Warning: Could not clear event log $log : $($_.Exception.Message)"
        }
    }

    # Clean C:\Windows\Temp
    Write-Log 'Cleaning C:\Windows\Temp...'
    try {
        Takeown /d Y /R /f "C:\Windows\Temp\*"
        Icacls "C:\Windows\Temp\*" /GRANT:r administrators:F /T /c /q  2>&1
        $tempFiles = Get-ChildItem -Path "C:\Windows\Temp\*" -Recurse -ErrorAction SilentlyContinue
        Write-Log "Found $($tempFiles.Count) items in C:\Windows\Temp"
        $tempFiles | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log 'Successfully cleaned C:\Windows\Temp'
    } catch {
        Write-Log "Warning: Could not clean C:\Windows\Temp: $($_.Exception.Message)"
    }

    # Clean $env:TEMP
    Write-Log "Cleaning $env:TEMP..."
    try {
        $userTempFiles = Get-ChildItem -Path "$env:TEMP\*" -Recurse -ErrorAction SilentlyContinue
        Write-Log "Found $($userTempFiles.Count) items in $env:TEMP"
        $userTempFiles | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "Successfully cleaned $env:TEMP"
    } catch {
        Write-Log "Warning: Could not clean $env:TEMP: $($_.Exception.Message)"
    }

    # Clean other temp locations
    Write-Log 'Stopping services that might interfere with temporary file removal...'
    function Stop-ServiceForReal($name) {
        while ($true) {
            Stop-Service -ErrorAction SilentlyContinue $name
            if ((Get-Service $name).Status -eq 'Stopped') { break }
        }
    }
    Stop-ServiceForReal TrustedInstaller
    Stop-ServiceForReal wuauserv
    Stop-ServiceForReal BITS

    foreach ($path in @(
        "$env:windir\Logs\*",
        "$env:windir\Panther\*",
        "$env:windir\WinSxS\ManifestCache\*",
        "$env:windir\SoftwareDistribution\Download",
        "C:\Users\vagrant\Favorites\*"
    )) {
        if (Test-Path $path) {
            Write-Log "Removing temporary files $path..."
            try {
                takeown.exe /D Y /R /F $path | Out-Null
                icacls.exe $path /grant:r Administrators:F /T /C /Q 2>&1 | Out-Null
            } catch {
                Write-Log "Warning: Ownership error for $path : $($_.Exception.Message)"
            }
            try {
                Remove-Item $path -Exclude 'packer-*' -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            } catch {
                Write-Log "Warning: Remove error for $path : $($_.Exception.Message)"
            }
        }
    }

    # Clean WinSxS folder
    Write-Log 'Cleaning up the WinSxS folder...'
    try {
        dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
        Write-Log 'WinSxS cleanup completed.'
    } catch {
        Write-Log "WinSxS cleanup failed, attempting service restart and scheduled task..."
        try {
            net stop wuauserv
            net stop cryptSvc
            net stop bits
            net stop msiserver
            Remove-Item C:\Windows\SoftwareDistribution -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item C:\Windows\System32\catroot2 -Recurse -Force -ErrorAction SilentlyContinue
            net start wuauserv
            net start cryptSvc
            net start bits
            net start msiserver
            dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
            Write-Log 'WinSxS cleanup completed after service restart.'
        } catch {
            Write-Log "WinSxS cleanup failed, running scheduled task..."
            schtasks.exe /Run /TN "\Microsoft\Windows\Servicing\StartComponentCleanup"
        }
    }

    # Remove disabled features from WinSxS
    try {
        Get-WindowsOptionalFeature -Online | Where-Object {$_.State -eq 'Disabled'} | ForEach-Object {
            Write-Log "Removing disabled feature $($_.FeatureName)..."
            dism.exe /Online /Quiet /Disable-Feature "/FeatureName:$($_.FeatureName)" /Remove
        }
    } catch {
        Write-Log "Warning: Failed to remove disabled features: $($_.Exception.Message)"
    }

    # Analyze WinSxS
    Write-Log 'Analyzing the WinSxS folder...'
    try {
        dism.exe /Online /Cleanup-Image /AnalyzeComponentStore
    } catch {
        Write-Log "Warning: Failed to analyze WinSxS: $($_.Exception.Message)"
    }

    # Remove pagefile
    Write-Log 'Removing pagefile (will be recreated on next boot)...'
    try {
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles -Value '' -Force
    } catch {
        Write-Log "Warning: Failed to remove pagefile: $($_.Exception.Message)"
    }

    Write-Log "Cleanup script completed successfully."
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
