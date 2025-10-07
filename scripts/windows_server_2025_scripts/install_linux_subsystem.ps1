# Optimized WSL installation for Windows Server 2022

$ErrorActionPreference = 'Stop'

try {
    Log "Enabling Windows Subsystem for Linux feature..."
    Enable-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online | Out-Null
    Log "WSL feature enabled. Please install your preferred Linux distribution from the Microsoft Store."
    Log "After installing Linux, run the following commands inside your Linux shell to install PowerShell:"
    Log "sudo apt-get update"
    Log "sudo apt-get install curl apt-transport-https"
    Log "curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -"
    Log "sudo sh -c 'echo \"deb https://packages.microsoft.com/repos/microsoft-debian-stretch-prod stretch main\" > /etc/apt/sources.list.d/microsoft.list'"
    Log "sudo apt-get update"
    Log "sudo apt-get install -y powershell"
    Log "pwsh"
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
