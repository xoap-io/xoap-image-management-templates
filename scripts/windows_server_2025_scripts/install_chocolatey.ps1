# Optimized Chocolatey installation for Windows Server 2022

$ErrorActionPreference = 'Stop'
$env:chocolateyUseWindowsCompression = 'false'
$chocoScript = 'C:\Windows\Temp\choco.ps1'

try {
    Log "Downloading Chocolatey install script..."
    (New-Object System.Net.WebClient).DownloadFile('https://chocolatey.org/install.ps1', $chocoScript)
    Log "Running Chocolatey install script..."
    & $chocoScript
    Log "Chocolatey installation complete."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
