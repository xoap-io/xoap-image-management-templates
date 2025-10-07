# Optimized PowerShellGet installation for Windows Server 2022

$ErrorActionPreference = 'Stop'

try {
    Log "Setting execution policy to RemoteSigned..."
    Set-ExecutionPolicy RemoteSigned -Force
    Log "Installing PowerShellGet module..."
    Install-Module -Name PowerShellGet -Force -AllowClobber
    Log "Installing Nuget package provider..."
    Install-PackageProvider -Name Nuget -Force
    Log "Updating PowerShellGet module..."
    Update-Module -Name PowerShellGet
    Log "PowerShellGet installation and update complete."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
