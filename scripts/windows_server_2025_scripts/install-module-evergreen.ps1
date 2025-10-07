# Optimized Evergreen module installation for Windows Server 2022

function Log {
    param([string]$msg)
    Write-Host "[EVERGREEN] $msg"
}

$ErrorActionPreference = 'Stop'

try {
    Log "Installing Evergreen module..."
    Install-Module -Name Evergreen -Force -AllowClobber
    Log "Importing Evergreen module..."
    Import-Module -Name Evergreen
    Log "Updating Evergreen module..."
    Update-Module -Name Evergreen -Force
    Log "Evergreen module installation and update complete."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
