<#
    .SYNOPSIS
        Optimise and seal a Windows image.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [System.String] $Path = "$env:SystemDrive\Apps\Microsoft\Optimise"
)

function Log {
    param([string]$msg)
    Write-Host "[W10OPT] $msg"
}

$ErrorActionPreference = 'Stop'
$VerbosePreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Set TLS to 1.2; Create target folder
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null

#region Individual optimisation functions
Function Invoke-WindowsDefender {
    Log "Running Windows Defender quick scan..."
    try {
        Start-Process -FilePath "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList "-SignatureUpdate -MMPC" -Wait
        Start-Process -FilePath "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList "-Scan -ScanType 1" -Wait
    } catch {
        Log "Warning: Windows Defender scan failed: $($_.Exception.Message)"
    }
}

Function Disable-ScheduledTask {
    Log "Disabling scheduled tasks..."
    $SchTasksList = @("BgTaskRegistrationMaintenanceTask", "Consolidator", "Diagnostics", "FamilySafetyMonitor",
        "FamilySafetyRefreshTask", "MapsToastTask", "MNO Metadata Parser", "NotificationTask",
        "ProcessMemoryDiagnosticEvents", "Proxy", "QueueReporting", "RecommendedTroubleshootingScanner",
        "RegIdleBackup", "RunFullMemoryDiagnostic", "ScheduledDefrag", "Scheduled", "SR", "StartupAppTask",
        "SyspartRepair", "WindowsActionDialog", "WinSAT", "XblGameSaveTask")
    if ($SchTasksList.count -gt 0) {
        $EnabledScheduledTasks = Get-ScheduledTask | Where-Object { $_.State -ne "Disabled" }
        foreach ($Item in $SchTasksList) {
            $Task = (($Item -split ":")[0]).Trim()
            try {
                $EnabledScheduledTasks | Where-Object { $_.TaskName -like "*$Task*" } | Disable-ScheduledTask -ErrorAction "SilentlyContinue"
            } catch {
                Log "Warning: Could not disable scheduled task $Task: $($_.Exception.Message)"
            }
        }
    }
}

Function Disable-WindowsTrace {
    Log "Disabling Windows traces..."
    $DisableAutologgers = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AppModel\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\CloudExperienceHostOOBE\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DiagLog\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\ReadyBoot\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WDIContextLog\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiDriverIHVSession\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WiFiSession\",
        "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WinPhoneCritical\")
    foreach ($Item in $DisableAutologgers) {
        try {
            New-ItemProperty -Path "$Item" -Name "Start" -PropertyType "DWORD" -Value "0" -Force -ErrorAction "SilentlyContinue"
        } catch {
            Log "Warning: Could not disable autologger $Item: $($_.Exception.Message)"
        }
    }
}

Function Disable-Service {
    Log "Disabling unnecessary services..."
    $ServicesToDisable = @("autotimesvc", "BcastDVRUserService", "CDPSvc", "CDPUserSvc", "CscService",
        "defragsvc", "DiagTrack", "DsmSvc", "DusmSvc", "icssvc", "lfsvc", "MapsBroker",
        "MessagingService", "OneSyncSvc", "PimIndexMaintenanceSvc", "Power", "SEMgrSvc", "SmsRouter",
        "SysMain", "TabletInputService", "UsoSvc", "WerSvc", "XblAuthManager",
        "XblGameSave", "XboxGipSvc", "XboxNetApiSvc", "AdobeARMservice")
    foreach ($Item in $ServicesToDisable) {
        try {
            $service = Get-Service -Name $Item -ErrorAction "SilentlyContinue"
            if ($service) {
                Log "Disabling service: $($service.DisplayName)"
                $service | Set-Service -StartupType "Disabled" -ErrorAction "SilentlyContinue"
            }
        } catch {
            Log "Warning: Could not disable service $Item: $($_.Exception.Message)"
        }
    }
}

Function Disable-SystemRestore {
    Log "Disabling System Restore..."
    try {
        Disable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction "SilentlyContinue"
    } catch {
        Log "Warning: Could not disable System Restore: $($_.Exception.Message)"
    }
}

Function Optimize-Network {
    Log "Applying network optimisations..."
    try {
        New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\" -Name "DisableBandwidthThrottling" -PropertyType "DWORD" -Value "1" -Force
        New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\" -Name "FileInfoCacheEntriesMax" -PropertyType "DWORD" -Value "1024" -Force
        New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\" -Name "DirectoryCacheEntriesMax" -PropertyType "DWORD" -Value "1024" -Force
        New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\" -Name "FileNotFoundCacheEntriesMax" -PropertyType "DWORD" -Value "1024" -Force
        New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\" -Name "DormantFileLimit" -PropertyType "DWORD" -Value "256" -Force
    } catch {
        Log "Warning: Could not apply network optimisations: $($_.Exception.Message)"
    }
}

Function Remove-TempFile {
    Log "Removing temp files..."
    try {
        $FilesToRemove = Get-ChildItem -Path "$env:SystemDrive\" -Include *.tmp, *.etl, *.evtx -Recurse -Force -ErrorAction SilentlyContinue
        $FilesToRemove | Remove-Item -ErrorAction "SilentlyContinue"
        Remove-Item -Path $env:windir\Temp\* -Recurse -Force -ErrorAction "SilentlyContinue"
        Remove-Item -Path $env:TEMP\* -Recurse -Force -ErrorAction "SilentlyContinue"
    } catch {
        Log "Warning: Could not remove temp files: $($_.Exception.Message)"
    }
}

Function Global:Clear-WinEvent {
    [CmdletBinding(SupportsShouldProcess = $True)]
    Param ([System.String] $LogName)
    Process {
        if ($PSCmdlet.ShouldProcess("$LogName", "Clear event log")) {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog("$LogName")
            } catch {
                Log "Warning: Failed to clear log: $LogName. $($_.Exception.Message)"
            }
        }
    }
}

#region Script logic
Log "Starting Windows 10 2004 image optimization..."
Invoke-WindowsDefender
Disable-ScheduledTask
Disable-WindowsTrace
Disable-SystemRestore
Disable-Service
Optimize-Network
Remove-TempFile
Get-WinEvent -ListLog * | ForEach-Object { Clear-WinEvent $_.LogName -Confirm:$False }
Log "Optimization complete: OptimiseImage."
#endregion
