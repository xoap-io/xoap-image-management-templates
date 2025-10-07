Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Log {
    param([string]$msg)
    Write-Host "[SYSOPTIMIZE] $msg"
}

trap {
    Log "ERROR: $_"
    Log (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Log (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    Log 'Sleeping for 60m to give you time to look around the virtual machine before self-destruction...'
    Start-Sleep -Seconds (60*60)
    Exit 1
}

# run automatic maintenance.
Log 'Running Automatic Maintenance...'
MSchedExe.exe Start

function Wait-Condition {
    param(
      [scriptblock]$Condition,
      [int]$DebounceSeconds=15
    )
    process {
        $begin = [Windows]::GetUptime()
        do {
            Start-Sleep -Seconds 3
            try {
              $result = &$Condition
            } catch {
              $result = $false
            }
            if (-not $result) {
                $begin = [Windows]::GetUptime()
                continue
            }
        } while ((([Windows]::GetUptime()) - $begin).TotalSeconds -lt $DebounceSeconds)
    }
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Windows {
    [DllImport("kernel32", SetLastError=true)]
    public static extern UInt64 GetTickCount64();
    public static TimeSpan GetUptime() {
        return TimeSpan.FromMilliseconds(GetTickCount64());
    }
}
'@

function Get-ScheduledTasks() {
    $s = New-Object -ComObject 'Schedule.Service'
    try {
        $s.Connect()
        Get-ScheduledTasksInternal $s.GetFolder('\')
    } finally {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($s) | Out-Null
    }
}

function Get-ScheduledTasksInternal($Folder) {
    $Folder.GetTasks(0)
    $Folder.GetFolders(0) | ForEach-Object {
        Get-ScheduledTasksInternal $_
    }
}

function Test-IsMaintenanceTask([xml]$definition) {
    $ns = New-Object System.Xml.XmlNamespaceManager($definition.NameTable)
    $ns.AddNamespace('t', $definition.DocumentElement.NamespaceURI)
    $null -ne $definition.SelectSingleNode("/t:Task/t:Settings/t:MaintenanceSettings", $ns)
}

Wait-Condition {@(Get-ScheduledTasks | Where-Object {($_.State -ge 4) -and (Test-IsMaintenanceTask $_.XML)}).Count -eq 0} -DebounceSeconds 60

# generate the .net frameworks native images.
Get-ChildItem "$env:windir\Microsoft.NET\*\*\ngen.exe" | ForEach-Object {
    Log "Generating the .NET Framework native images with $_..."
    &$_ executeQueuedItems /nologo /silent
}

# remove temporary files.
Log 'Stopping services that might interfere with temporary file removal...'
function Stop-ServiceForReal($name) {
    while ($true) {
        Stop-Service -ErrorAction SilentlyContinue $name
        if ((Get-Service $name).Status -eq 'Stopped') {
            break
        }
    }
}
Stop-ServiceForReal TrustedInstaller   # Windows Modules Installer
Stop-ServiceForReal wuauserv           # Windows Update
Stop-ServiceForReal BITS               # Background Intelligent Transfer Service
@(
    "$env:LOCALAPPDATA\Temp\*"
    "$env:windir\Temp\*"
    "$env:windir\Logs\*"
    "$env:windir\Panther\*"
    "$env:windir\WinSxS\ManifestCache\*"
    "$env:windir\SoftwareDistribution\Download"
) | Where-Object {Test-Path $_} | ForEach-Object {
    Log "Removing temporary files $_..."
    takeown.exe /D Y /R /F $_ | Out-Null
    icacls.exe $_ /grant:r Administrators:F /T /C /Q 2>&1 | Out-Null
    Remove-Item $_ -Exclude 'packer-*' -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
}

# cleanup the WinSxS folder.
Log 'Cleaning up the WinSxS folder...'
dism.exe /Online /Quiet /Cleanup-Image /StartComponentCleanup /ResetBase
if ($LASTEXITCODE) {
    throw "Failed with Exit Code $LASTEXITCODE"
}

# Remove disabled features packages
Get-WindowsOptionalFeature -Online |
    Where-Object {$_.State -eq 'Disabled'} |
    ForEach-Object {
        Log "Removing feature $($_.FeatureName)..."
        dism.exe /Online /Quiet /Disable-Feature "/FeatureName:$($_.FeatureName)" /Remove
    }

Log 'Analyzing the WinSxS folder...'
dism.exe /Online /Cleanup-Image /AnalyzeComponentStore

# reclaim the free disk space.
Log 'Reclaiming the free disk space...'
$results = defrag.exe C: /H /L
if ($results -eq 'The operation completed successfully.') {
    Log $results
} else {
    Log 'Zero filling the free disk space...'
    (New-Object System.Net.WebClient).DownloadFile('https://download.sysinternals.com/files/SDelete.zip', "$env:TEMP\SDelete.zip")
    Expand-Archive "$env:TEMP\SDelete.zip" $env:TEMP
    Remove-Item "$env:TEMP\SDelete.zip"
    &"$env:TEMP\sdelete64.exe" -accepteula -z C:
}
