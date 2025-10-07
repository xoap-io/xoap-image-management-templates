# Optimized Docker installation for Windows Server 2022

$ErrorActionPreference = 'Stop'

try {
    Log "Setting PowerShell as default shell..."
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -Value 'PowerShell.exe -noExit'

    Log "Installing Containers feature..."
    Install-WindowsFeature -Name Containers | Out-Null

    Log "Uninstalling Windows Defender..."
    Uninstall-WindowsFeature Windows-Defender | Out-Null

    Log "Restarting computer..."
    Restart-Computer -Force

    Log "Installing DockerMsftProvider module..."
    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force

    Log "Installing Docker package..."
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force -RequiredVersion 18.03

    Log "Starting Docker service..."
    Start-Service docker

    Log "Initializing Docker Swarm..."
    docker swarm init --advertise-addr 127.0.0.1

    Log "Docker installation and configuration complete."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
