# Optimized removal of XPS Viewer feature for Windows Server 2022

$WindowsFeature = "XPS-Viewer"
$ErrorActionPreference = "Stop"

function Log {
    param([string]$msg)
    Write-Host "[XPSVIEWER] $msg"
}

try {
    Import-Module ServerManager
    $feature = Get-WindowsFeature $WindowsFeature
    if ($feature -and $feature.InstallState -eq "Installed") {
        Log "Removing $WindowsFeature..."
        Remove-WindowsFeature $WindowsFeature -IncludeAllSubFeature | Out-Null
        Log "$WindowsFeature removed."
    } elseif ($feature -and $feature.InstallState -eq "Available") {
        Log "$WindowsFeature already removed."
    } else {
        Log "$WindowsFeature does not exist."
    }
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
