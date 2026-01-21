<#
.SYNOPSIS
    Optimize Windows Server 2016 for Citrix SBC

.DESCRIPTION
    Optimizes Windows Server 2016 Operating Systems running in a Citrix SBC environment.
    This script disables services, disables scheduled tasks and modifies the registry to optimize system performance.

.NOTES
    File Name      : windows-server-optimize_w2k16.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    WARNING        : Review all optimizations before use in production
    
.EXAMPLE
    .\windows-server-optimize_w2k16.ps1
    Applies Citrix optimization settings for Windows Server 2016
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        default   { 'INFO' }
    }
    Write-Host "[$timestamp] [$prefix] [W2K16Opt] $Message"
}

# Get OneSync service name
$SyncService = Get-Service -Name OneSync* -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name

# Array of registry objects that will be created
$CreateRegistry = @(
    @("HideSCAHealth DWORD - Hide Action Center Icon.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v HideSCAHealth /t REG_DWORD /d 0x1 /f"),
    @("NoRemoteRecursiveEvents DWORD - Turn off change notify events for file and folder changes.", "'HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v NoRemoteRecursiveEvents /t REG_DWORD /d 0x1 /f"),
    @("SendAlert DWORD - Do not send Administrative alert during system crash.", "'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v SendAlert /t REG_DWORD /d 0x0 /f"),
    @("ServicesPipeTimeout DWORD - Increase services startup timeout from 30 to 45 seconds.", "'HKLM\SYSTEM\CurrentControlSet\Control' /v ServicesPipeTimeout /t REG_DWORD /d 0xafc8 /f"),
    @("DisableFirstRunCustomize DWORD - Disable Internet Explorer first-run customise wizard.", "'HKLM\SOFTWARE\Policies\Microsoft\Internet Explorer\Main' /v DisableFirstRunCustomize /t REG_DWORD /d 0x1 /f"),
    @("AllowTelemetry DWORD - Disable telemetry.", "'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v AllowTelemetry /t REG_DWORD /d 0x0 /f"),
    @("Enabled DWORD - Disable offline files.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\NetCache' /v Enabled /t REG_DWORD /d 0x0 /f"),
    @("Enable REG_SZ - Disable Defrag.", "'HKLM\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction' /v Enable /t REG_SZ /d N /f"),
    @("NoAutoUpdate DWORD - Disable Windows Autoupdate.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' /v NoAutoUpdate /t REG_DWORD /d 0x1 /f"),
    @("AUOptions DWORD - Disable Windows Autoupdate.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' /v AUOptions /t REG_DWORD /d 0x1 /f"),
    @("ScheduleInstallDay DWORD - Disable Windows Autoupdate.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' /v ScheduleInstallDay /t REG_DWORD /d 0x0 /f"),
    @("ScheduleInstallTime DWORD - Disable Windows Autoupdate.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' /v ScheduleInstallTime /t REG_DWORD /d 0x3 /f"),
    @("EnableAutoLayout DWORD - Disable Background Layout Service.", "'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout' /v EnableAutoLayout /t REG_DWORD /d 0x0 /f"),
    @("DumpFileSize DWORD - Reduce DedicatedDumpFile DumpFileSize to 2 MB.", "'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v DumpFileSize /t REG_DWORD /d 0x2 /f"),
    @("IgnorePagefileSize DWORD - Reduce DedicatedDumpFile DumpFileSize to 2 MB.", "'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v IgnorePagefileSize /t REG_DWORD /d 0x1 /f"),
    @("DisableLogonBackgroundImage DWORD - Disable Logon Background Image.", "'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' /v DisableLogonBackgroundImage /t REG_DWORD /d 0x1 /f")
)

# Array of registry objects that will be deleted
$DeleteRegistry = @(
    @("StubPath - Themes Setup.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{2C7339CF-2B09-4501-B3F3-F3508C9228ED}' /v StubPath /f"),
    @("StubPath - WinMail.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{44BBA840-CC51-11CF-AAFA-00AA00B6015C}' /v StubPath /f"),
    @("StubPath x64 - WinMail.", "'HKLM\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components\{44BBA840-CC51-11CF-AAFA-00AA00B6015C}' /v StubPath /f"),
    @("StubPath - Windows Media Player.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{6BF52A52-394A-11d3-B153-00C04F79FAA6}' /v StubPath /f"),
    @("StubPath x64 - Windows Media Player.", "'HKLM\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components\{6BF52A52-394A-11d3-B153-00C04F79FAA6}' /v StubPath /f"),
    @("StubPath - Windows Desktop Update.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{89820200-ECBD-11cf-8B85-00AA005B4340}' /v StubPath /f"),

  ("StubPath - Web Platform Customizations.","'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{89820200-ECBD-11cf-8B85-00AA005B4383}' /v StubPath /f"),

  ("StubPath - DotNetFrameworks.","'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{89B4C1CD-B018-4511-B0A1-5476DBF70820}' /v StubPath /f"),

  ("StubPath x64 - DotNetFrameworks.","'HKLM\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components\{89B4C1CD-B018-4511-B0A1-5476DBF70820}' /v StubPath /f"),

  ("StubPath - Windows Media Player.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\>{22d6f312-b0f6-11d0-94ab-0080c74c7e95}' /v StubPath /f"),

  ("StubPath x64 - Windows Media Player.", "'HKLM\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components\>{22d6f312-b0f6-11d0-94ab-0080c74c7e95}' /v StubPath /f"),

  ("StubPath - IE ESC for Admins.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}' /v StubPath /f"),

  ("StubPath - IE ESC for Users.", "'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}' /v StubPath /f")



 #Array of registry objects that will be modified

 $ModifyRegistry =

 @("DisablePagingExecutive DWORD from 0x0 to 0x1 - Keep drivers and kernel on physical memory.","'HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management' /v DisablePagingExecutive /t REG_DWORD /d 0x1 /f"),

  ("EventLog DWORD from 0x3 to 0x1 - Log print job error notifications in Event Viewer.","'HKLM\SYSTEM\CurrentControlSet\Control\Print\Providers' /v EventLog /t REG_DWORD /d 0x1 /f"),

  ("CrashDumpEnabled DWORD from 0x7 to 0x0 - Disable crash dump creation.","'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v CrashDumpEnabled /t REG_DWORD /d 0x0 /f"),

  ("LogEvent DWORD from 0x1 to 0x0 - Disable system crash logging to Event Log.","'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v LogEvent /t REG_DWORD /d 0x0 /f"),

  ("ErrorMode DWORD from 0x0 to 0x2 - Hide hard error messages.","'HKLM\SYSTEM\CurrentControlSet\Control\Windows' /v ErrorMode /t REG_DWORD /d 0x2 /f"),

  ("MaxSize DWORD from 0x01400000 to 0x00010000 - Reduce Application Event Log size to 64KB","'HKLM\SYSTEM\CurrentControlSet\Services\Eventlog\Application' /v MaxSize /t REG_DWORD /d 0x10000 /f"),

  ("MaxSize DWORD from 0x0140000 to 0x00010000 - Reduce Security Event Log size to 64KB.","'HKLM\SYSTEM\CurrentControlSet\Services\Eventlog\Security' /v MaxSize /t REG_DWORD /d 0x10000 /f"),

  ("MaxSize DWORD from 0x0140000 to 0x00010000 - Reduce System Event Log size to 64KB.","'HKLM\SYSTEM\CurrentControlSet\Services\Eventlog\System' /v MaxSize /t REG_DWORD /d 0x10000 /f"),

  ("ClearPageFileAtShutdown DWORD to 0x0 - Disable clear Page File at shutdown.","'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v ClearPageFileAtShutdown /t REG_DWORD /d 0x0 /f"),

  ("Creating Paths DWORD - Reduce IE Temp File.","'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Cache\Paths' /v Paths /t REG_DWORD /d 0x4 /f"),

  ("Creating CacheLimit DWORD - Reduce IE Temp File.","'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Cache\Paths\path1' /v CacheLimit /t REG_DWORD /d 0x100 /f"),

  ("Creating CacheLimit DWORD - Reduce IE Temp File.","'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Cache\Paths\path2' /v CacheLimit /t REG_DWORD /d 0x100 /f"),

  ("Creating CacheLimit DWORD - Reduce IE Temp File.","'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Cache\Paths\path3' /v CacheLimit /t REG_DWORD /d 0x100 /f"),

  ("Creating CacheLimit DWORD - Reduce IE Temp File.","'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Cache\Paths\path4' /v CacheLimit /t REG_DWORD /d 0x100 /f"),

  ("DisablePasswordChange DWORD from 0x0 to 0x1 - Disable Machine Account Password Changes.","'HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' /v DisablePasswordChange /t REG_DWORD /d 0x1 /f"),

  ("PreferredPlan REG_SZ from 381b4222-f694-41f0-9685-ff5bb260df2e to 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c - Changing Power Plan to High Performance.","'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{025A5937-A6BE-4686-A844-36FE4BEC8B6D}' /v PreferredPlan /t REG_SZ /d 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c /f"),

  ("TimeoutValue DWORD from 0x41 to 0xC8 - Increase Disk I/O Timeout to 200 seconds.","'HKLM\SYSTEM\CurrentControlSet\Services\Disk' /v TimeoutValue /t REG_DWORD /d 0xC8 /f"),

  ("Start DWORD from 0x2 to 0x4 - Disable the Sync Host Service.","'HKLM\SYSTEM\CurrentControlSet\Services\$SyncService' /v Start /t REG_DWORD /d 0x4 /f")



 #Array of service objects that will be set to disabled

 $Services =

 @("AJRouter - AllJoyn Router Service.","AJRouter"),

  ("ALG - Application Layer Gateway Service.","ALG"),

  ("AppMgmt - Application Management.","AppMgmt"),

  ("BITS - Background Intelligent Transfer Service.","BITS"),

  ("bthserv - Bluetooth Support Service.","bthserv"),

  ("DcpSvc - DataCollectionPublishingService.","DcpSvc"),

  ("DPS - Diagnostic Policy Service.","DPS"),

  ("WdiServiceHost - Diagnostic Service Host.","WdiServiceHost"),

  ("WdiSystemHost - Diagnostic System Host.","WdiSystemHost"),

  ("DiagTrack - Connected User Experiences and Telemetry [Diagnostics Tracking Service].","DiagTrack"),

  ("dmwappushservice - dmwappushsvc.","dmwappushservice"),

  ("MapsBroker - Downloaded Maps Manager.","MapsBroker"),

  ("EFS - Encrypting File System [EFS].","EFS"),

  ("Eaphost - Extensible Authentication Protocol.","Eaphost"),

  ("FDResPub - Function Discovery Resource Publication.","FDResPub"),

  ("lfsvc - Geolocation Service.","lfsvc"),

  ("UI0Detect - Interactive Services Detection.","UI0Detect"),

  ("SharedAccess - Internet Connection Sharing [ICS].","SharedAccess"),

  ("iphlpsvc - IP Helper.","iphlpsvc"),

  ("lltdsvc - Link-Layer Topology Discovery Mapper.","lltdsvc"),

  ("diagnosticshub.standardcollector.service - Microsoft [R] Diagnostics Hub Standard Collector Service.","diagnosticshub.standardcollector.service"),

  ("wlidsvc - Microsoft Account Sign-in Assistant.","wlidsvc"),

  ("MSiSCSI - Microsoft iSCSI Initiator Service.","MSiSCSI"),

  ("smphost - Microsoft Storage Spaces SMP.","smphost"),

  ("NcbService - Network Connection Broker.","NcbService"),

  ("NcaSvc - Network Connectivity Assistant.","NcaSvc"),

  ("defragsvc - Optimize drives.","defragsvc"),

  ("wercplsupport - Problem Reports and Solutions Control Panel.","wercplsupport"),

  ("PcaSvc - Program Compatibility Assistant Service.","PcaSvc"),

  ("QWAVE - Quality Windows Audio Video Experience.","QWAVE"),

  ("RmSvc - Radio Management Service.","RmSvc"),

  ("RasMan - Remote Access Connection Manager.","RasMan"),

  ("SstpSvc - Secure Socket Tunneling Protocol Service.","SstpSvc"),

  ("SensorDataService - Sensor Data Service.","SensorDataService"),

  ("SensrSvc - Sensor Monitoring Service.","SensrSvc"),

  ("SensorService - Sensor Service.","SensorService"),

  ("SNMPTRAP - SNMP Trap.","SNMPTRAP"),

  ("sacsvr - Special Administration Console Helper.","sacsvr"),

  ("svsvc - Spot Verifier.","svsvc"),

  ("SSDPSRV - SSDP Discovery.","SSDPSRV"),

  ("TieringEngineService - Storage Tiers Management.","TieringEngineService"),

  ("SysMain - Superfetch.","SysMain"),

  ("TapiSrv - Telephony.","TapiSrv"),

  ("UALSVC - User Access Logging Service.","UALSVC"),

  ("Wcmsvc - Windows Connection Manager.","Wcmsvc"),

  ("WerSvc - Windows Error Reporting Service.","WerSvc"),

  ("wisvc - Windows Insider Service.","wisvc"),

  ("icssvc - Windows Mobile Hotspot Service.","icssvc"),

  ("wuauserv - Windows Update.","wuauserv"),

  ("dot3svc - Wired AutoConfig.","dot3svc"),

  ("XblAuthManager - Xbox Live Auth Manager.","XblAuthManager"),

  ("XblGameSave - Xbox Live Game Save.","XblGameSave")



  #Array of scheduled task objects that will be set to disabled

  $ScheduledTasks = 

  @("'AD RMS Rights Policy Template Management (Manual)'","'\Microsoft\Windows\Active Directory Rights Management Services Client'"),

   ("'EDP Policy Manager'","'\Microsoft\Windows\AppID'"),

   ("SmartScreenSpecific","'\Microsoft\Windows\AppID'"),

   ("'Microsoft Compatibility Appraiser'","'\Microsoft\Windows\Application Experience'"),

   ("ProgramDataUpdater","'\Microsoft\Windows\Application Experience'"),

   ("StartupAppTask","'\Microsoft\Windows\Application Experience'"),

   ("CleanupTemporaryState","\Microsoft\Windows\ApplicationData"),

   ("DsSvcCleanup","\Microsoft\Windows\ApplicationData"),

   ("Proxy","'\Microsoft\Windows\Autochk'"),

   ("UninstallDeviceTask","\Microsoft\Windows\Bluetooth"),

   ("AikCertEnrollTask","\Microsoft\Windows\CertificateServicesClient"),

   ("CryptoPolicyTask","\Microsoft\Windows\CertificateServicesClient"),

   ("KeyPreGenTask","\Microsoft\Windows\CertificateServicesClient"),

   ("ProactiveScan","\Microsoft\Windows\Chkdsk"),

   ("CreateObjectTask","\Microsoft\Windows\CloudExperienceHost"),

   ("Consolidator","'\Microsoft\Windows\Customer Experience Improvement Program'"),

   ("KernelCeipTask","'\Microsoft\Windows\Customer Experience Improvement Program'"),

   ("UsbCeip","'\Microsoft\Windows\Customer Experience Improvement Program'"),

   ("'Data Integrity Scan'","'\Microsoft\Windows\Data Integrity Scan'"),

   ("'Data Integrity Scan for Crash Recovery'","'\Microsoft\Windows\Data Integrity Scan'"),

   ("ScheduledDefrag","\Microsoft\Windows\Defrag"),

   ("Device","'\Microsoft\Windows\Device Information'"),

   ("Scheduled","\Microsoft\Windows\Diagnosis"),

   ("SilentCleanup","\Microsoft\Windows\DiskCleanup"),

   ("Microsoft-Windows-DiskDiagnosticDataCollector","\Microsoft\Windows\DiskDiagnostic"),

   ("Notifications","\Microsoft\Windows\Location"),

   ("WindowsActionDialog","\Microsoft\Windows\Location"),

   ("WinSAT","\Microsoft\Windows\Maintenance"),

   ("MapsToastTask","\Microsoft\Windows\Maps"),

   ("'MNO Metadata Parser'","'\Microsoft\Windows\Mobile Broadband Accounts'"),

   ("LPRemove","\Microsoft\Windows\MUI"),

   ("GatherNetworkInfo","\Microsoft\Windows\NetTrace"),

   ("Secure-Boot-Update","\Microsoft\Windows\PI"),

   ("Sqm-Tasks","\Microsoft\Windows\PI"),

   ("AnalyzeSystem","'\Microsoft\Windows\Power Efficiency Diagnostics'"),

   ("MobilityManager","\Microsoft\Windows\Ras"),

   ("VerifyWinRE","\Microsoft\Windows\RecoveryEnvironment"),

   ("RegIdleBackup","\Microsoft\Windows\Registry"),

   ("CleanupOldPerfLogs","'\Microsoft\Windows\Server Manager'"),

   ("StartComponentCleanup","\Microsoft\Windows\Servicing"),

   ("IndexerAutomaticMaintenance","\Microsoft\Windows\Shell"),

   ("Configuration","'\Microsoft\Windows\Software Inventory Logging'"),

   ("SpaceAgentTask","\Microsoft\Windows\SpacePort"),

   ("SpaceManagerTask","\Microsoft\Windows\SpacePort"),

   ("SpeechModelDownloadTask","\Microsoft\Windows\Speech"),

   ("'Storage Tiers Management Initialization'","'\Microsoft\Windows\Storage Tiers Management'"),

   ("Tpm-HASCertRetr","\Microsoft\Windows\TPM"),

   ("Tpm-Maintenance","'\Microsoft\Windows\TPM'"),

   ("'Schedule Scan'","\Microsoft\Windows\UpdateOrchestrator"),

   ("ResolutionHost","\Microsoft\Windows\WDI"),

   ("QueueReporting","'\Microsoft\Windows\Windows Error Reporting'"),

   ("BfeOnServiceStartTypeChange","'\Microsoft\Windows\Windows Filtering Platform'"),

   ("'Automatic App Update'","\Microsoft\Windows\WindowsUpdate"),

   ("'Scheduled Start'","\Microsoft\Windows\WindowsUpdate"),

   ("sih","\Microsoft\Windows\WindowsUpdate"),

   ("sihboot","\Microsoft\Windows\WindowsUpdate"),

   ("XblGameSaveTask","\Microsoft\XblGameSave"),

   ("XblGameSaveTaskLogon","\Microsoft\XblGameSave")

Write-Log "Starting Windows Server 2016 Citrix optimization..." -Level Info
Write-Log "This script will modify registry, disable services, and remove features"

# Create registry entries
Write-Log "Creating registry objects for performance optimization..."
foreach ($RegistryObject in $CreateRegistry) {
    Write-Log "Creating registry object: $($RegistryObject[0])"
    try {
        $command = "reg add " + $RegistryObject[1]
        Start-Process -FilePath "reg.exe" -ArgumentList ("add " + $RegistryObject[1]) -NoNewWindow -Wait
    } catch {
        Write-Log "Could not create registry object $($RegistryObject[0]): $($_.Exception.Message)" -Level Warning
    }
}

# Delete registry entries
Write-Log "Deleting unnecessary Active Setup registry entries..."
foreach ($RegistryObject in $DeleteRegistry) {
    Write-Log "Deleting registry object: $($RegistryObject[0])"
    try {
        Start-Process -FilePath "reg.exe" -ArgumentList ("delete " + $RegistryObject[1]) -NoNewWindow -Wait
    } catch {
        Write-Log "Could not delete registry object $($RegistryObject[0]): $($_.Exception.Message)" -Level Warning
    }
}

# Modify registry entries
Write-Log "Modifying registry objects for performance optimization..."
foreach ($RegistryObject in $ModifyRegistry) {
    Write-Log "Modifying: $($RegistryObject[0])"
    try {
        Start-Process -FilePath "reg.exe" -ArgumentList ("add " + $RegistryObject[1]) -NoNewWindow -Wait
    } catch {
        Write-Log "Could not modify registry object $($RegistryObject[0]): $($_.Exception.Message)" -Level Warning
    }
}

# Disable services
Write-Log "Disabling unnecessary services..."
foreach ($ServiceObject in $Services) {
    Write-Log "Disabling service: $($ServiceObject[0])"
    try {
        Set-Service -Name $ServiceObject[1] -StartupType Disabled -ErrorAction Stop
    } catch {
        Write-Log "Could not disable service $($ServiceObject[0]): $($_.Exception.Message)" -Level Warning
    }
}

# Disable scheduled tasks
Write-Log "Disabling unnecessary scheduled tasks..."
foreach ($TaskObject in $ScheduledTasks) {
    Write-Log "Disabling scheduled task: $($TaskObject[0])"
    try {
        Disable-ScheduledTask -TaskName $TaskObject[0].Trim("'") -TaskPath $TaskObject[1].Trim("'") -ErrorAction Stop | Out-Null
    } catch {
        Write-Log "Could not disable scheduled task $($TaskObject[0]): $($_.Exception.Message)" -Level Warning
    }
}

# Remove Windows Defender
Write-Log "Removing Windows Defender feature..."
try {
    Uninstall-WindowsFeature -Name "Windows-Defender-Features" -ErrorAction Stop | Out-Null
    Write-Log "Windows Defender removed successfully"
} catch {
    Write-Log "Could not remove Windows Defender: $($_.Exception.Message)" -Level Warning
}

Write-Log "All optimizations are complete. Please restart your system." -Level Info
