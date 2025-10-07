# Optimized addition of XPS Viewer feature for Windows Server 2022

$WindowsFeature = "XPS-Viewer"
$ErrorActionPreference = "Stop"

function Log {
    param([string]$msg)
    Write-Host "[XPSVIEWER] $msg"
}

try {
    Import-Module ServerManager
    $feature = Get-WindowsFeature $WindowsFeature
    if ($feature -and $feature.InstallState -eq "Available") {
        Log "Adding $WindowsFeature..."
        Add-WindowsFeature $WindowsFeature -IncludeAllSubFeature | Out-Null
        Log "$WindowsFeature added."
    } elseif ($feature -and $feature.InstallState -eq "Installed") {
        Log "$WindowsFeature already installed."
    } else {
        Log "$WindowsFeature does not exist."
    }
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
