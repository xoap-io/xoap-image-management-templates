

#Requires -RunAsAdministrator

Write-Host "___________________________________________________________________________"
Write-Host "Get-ExecutionPolicy" -ForegroundColor green
Get-ExecutionPolicy

Write-Host "___________________________________________________________________________"
Write-Host "DSC Information" -ForegroundColor green
(Get-DscLocalConfigurationManager).ConfigurationDownloadManagers

Write-Host "___________________________________________________________________________"
Write-Host "IP-Address Information" -ForegroundColor green
$IPAddressNEW = Get-NetIPAddress
foreach ($ip in $IPAddressNEW) {
    Write-Host "Interface: "$IPAddressNEW.IndexOf($ip) "IPAddress: " $ip.IPAddress
    Write-Host "Interface: " $IPAddressNEW.IndexOf($ip) "AddressFamily: " $ip.AddressFamily `n
}

Write-Host "___________________________________________________________________________"
Write-Host "OS Information" -ForegroundColor green
$OperatingSystemInfo = Get-ComputerInfo | Select-Object OsName, OsVersion, OsBuildNumber, OsServicePackMajorVersion, OsServicePackMinorVersion, CsDNSHostName, BiosFirmwareType, WindowsCurrentVersion, OsLocalDateTime, OsLanguage, TimeZone, KeyboardLayout
Write-Host "`nOS Information: " $OperatingSystemInfo

Write-Host "___________________________________________________________________________"
Write-Host "Microsoft.NET TLS1.2" -ForegroundColor green
$TLS1 = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' | Select-Object -Property "SchUseStrongCrypto"
$TLS2 = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' | Select-Object -Property "SchUseStrongCrypto"
$TLS3 = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v2.0.50727' | Select-Object -Property "SchUseStrongCrypto"

Write-Host "`n.NetFrameworkv4.0: $TLS1"
Write-Host ".NetFrameworkv4.0x64" $TLS2 
Write-Host ".NetFrameworkv2.0" $TLS3

Write-Host "___________________________________________________________________________"
Write-Host "Check Access to Sites" -ForegroundColor green
$URLs = @{
    XOAPAPI = "https://api.xoap.io/ping"
    XOAP = "https://app.xoap.io"
}

foreach ($url in $URLs.Keys){
    
    $value = $URLs[$url]
    Write-Host "$url - $($URLs[$url])"-ForegroundColor green
    #$ErrorActionPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $value -UseBasicParsing -ErrorAction SilentlyContinue
}

Write-Host "___________________________________________________________________________"
Write-Host "Microsoft.NET Framework Proxy" -ForegroundColor green

$MicrosoftNETProxy64 = Get-Content -Path "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config" | Select-String "proxyaddress"
$MicrosoftNETProxy = Get-Content -Path "C:\Windows\Microsoft.NET\Framework\v4.0.30319\Config\machine.config" | Select-String "proxyaddress"

Write-Host "`nMicrosoft.NET Proxy settings x64: "$MicrosoftNETProxy64
Write-Host "Microsoft.NET Proxy settings: "$MicrosoftNETProxy

Write-Host "___________________________________________________________________________"
Write-Host "User Proxy" -ForegroundColor green
$Proxy = Get-ItemProperty -Path "Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" | Select-Object ProxyEnable,ProxyServer,ProxyOverride
Write-Host "
Enabled: $($Proxy.ProxyEnable)
Server: $($Proxy.ProxyServer)
Override: $($Proxy.ProxyOverride)
"

Write-Host "___________________________________________________________________________"
Write-Host "User Proxy (System)" -ForegroundColor green
$Proxy = Get-ItemProperty -Path "Registry::HKU\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Internet Settings" | Select-Object ProxyEnable,ProxyServer,ProxyOverride
Write-Host "
Enabled: $($Proxy.ProxyEnable)
Server: $($Proxy.ProxyServer)
Override: $($Proxy.ProxyOverride)
"

Write-Host "___________________________________________________________________________"
Write-Host "Registering Node" -ForegroundColor green

[DscLocalConfigurationManager()]
Configuration LCMDefault
{

        $regKey 		= '3e0cbed0-0b21-4e8e-874e-7577f9cda75f'
        Settings
        {
            RefreshFrequencyMins            = 30;
            RefreshMode                     = 'PULL';
            ConfigurationMode               = 'ApplyAndAutoCorrect';
            AllowModuleOverwrite            = $false;
            RebootNodeIfNeeded              = $true;
            ConfigurationModeFrequencyMins  = 15;
            
        }
        ConfigurationRepositoryWeb 'xoap.io'
        {
            ServerURL         			    = 'https://api.dev.xoap.io/dsc/113e9620-23d7-4533-aa05-b52184b242c6'
            RegistrationKey                 = $regKey
            ConfigurationNames              = 'GRP#18c26d9e-903b-4f15-984b-90470ad5df07'
            AllowUnsecureConnection			= $true

        }
        ReportServerWeb 'xoap.io'
        {
            ServerURL = 'https://api.dev.xoap.io/dsc/113e9620-23d7-4533-aa05-b52184b242c6'
            RegistrationKey   = $regKey
            AllowUnsecureConnection = $true
        }   
}
if ($PSISE -ne $null -or (![Environment]::Is64BitProcess)){
    Write-Error 'This Script must not be run in the ISE and a PowerShell x86! Please use a normal PowerShell x64'
    exit 1
}

Write-Host "___________________________________________________________________________"
Write-Host "Setting Execution Policy to Bypass" -ForegroundColor green

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

Write-Host "___________________________________________________________________________"
Write-Host "Setting Machine Execution Policy to RemoteSigned" -ForegroundColor green

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Get-ExecutionPolicy

Write-Host "___________________________________________________________________________"
Write-Host "Setting TLS to 1.2" -ForegroundColor green
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v2.0.50727' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$tls12 = try {
    $resp = (New-Object System.Net.WebClient).DownloadString("https://tls-v1-2.badssl.com:1012/")
    [bool] $resp.Contains("green")
  } catch {
    $false
  }
$tls12

Write-Host "___________________________________________________________________________"
Write-Host "Setting Connection Profile to private" -ForegroundColor green
Set-NetConnectionProfile -InterfaceAlias Ethernet* -NetworkCategory Private

Write-Host "___________________________________________________________________________"
Write-Host "Configuring WinRM" -ForegroundColor green

winrm quickconfig -quiet
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item -Path WSMan:\localhost\MaxEnvelopeSizeKb -Value 16384
Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB 4096

Write-Warning 'Restarting WinRM'
Restart-Service WinRM -Force

Write-Host "___________________________________________________________________________"
Write-Host "Applying configuration" -ForegroundColor green

LCMDefault
Set-DSCLocalConfigurationManager  -Path .\LCMDefault\ -Verbose 
Update-DscConfiguration -Verbose -Wait