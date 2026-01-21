
<#
.SYNOPSIS
    Prepares Windows 10/11 VM for Citrix Provisioning Services (PVS)

.DESCRIPTION
    This script optimizes and configures a Windows 10/11 VM for Citrix PVS usage. It disables unnecessary services, clears logs, sets update policies, and prepares the system for image streaming. Optionally, it can install Citrix PVS Target Device software if the installer path is provided.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.

.NOTES
    File Name      : windows11-Prepare_For_Citrix_PVS.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.COMPONENT
    PowerShell

.EXAMPLE
    .\windows11-Prepare_For_Citrix_PVS.ps1
    Prepares system for Citrix PVS imaging

.LINK
    https://github.com/xoap-io/xoap-packer-templates

#>

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Disable unnecessary services
$servicesToDisable = @(
    'Spooler',
    'Fax',
    'WSearch',
    'WMPNetworkSvc',
    'XblAuthManager',
    'XblGameSave',
    'XboxNetApiSvc',
    'PrintNotify',
    'RemoteRegistry',
    'bthserv',
    'SCardSvr',
    'WerSvc',
    'wisvc',
    'PhoneSvc',
    'RetailDemo',
    'seclogon',
    'CscService',
    'WcnSvc',
    'StiSvc',
    'FrameServer',
    'WbioSrvc'
)
foreach ($serviceName in $servicesToDisable) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $serviceName -StartupType Disabled
    }
}

# Set Windows Update to manual
Set-Service -Name wuauserv -StartupType Manual

# Optimize pagefile (optional, uncomment if needed)
wmic computersystem where name="%computername%" set AutomaticManagedPagefile=True

# Defragment disk (optional, uncomment if needed)
defrag C: /U /V

# Optionally install Citrix PVS Target Device software
# param(
#    [Parameter(Mandatory=$false)]
#    [string]$PvsInstallerPath
# )
# if ($PvsInstallerPath) {
#    Write-Host "Installing Citrix PVS Target Device software from $PvsInstallerPath..."
#    Start-Process -FilePath $PvsInstallerPath -ArgumentList '/quiet' -Wait
# }

Write-Host "VM preparation for Citrix PVS completed. You may now run the Citrix Imaging Wizard and sysprep if required."
