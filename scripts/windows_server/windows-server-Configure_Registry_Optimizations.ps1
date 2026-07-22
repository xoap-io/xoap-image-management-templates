<#
.SYNOPSIS
    Apply Registry Optimizations for Windows Server

.DESCRIPTION
    Applies comprehensive registry optimizations for Windows Server 2025 including
    performance tuning, security hardening, UI improvements, and system tweaks.
    Optimized for Packer image preparation and enterprise deployments.

.NOTES
    File Name      : windows-server-Configure_Registry_Optimizations.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Registry_Optimizations.ps1
    Applies all registry optimizations
    
.EXAMPLE
    .\windows-server-Configure_Registry_Optimizations.ps1 -SkipUI -SkipNetworking
    Applies optimizations excluding UI and networking tweaks
    
.PARAMETER SkipPerformance
    Skip performance-related optimizations
    
.PARAMETER SkipSecurity
    Skip security-related optimizations
    
.PARAMETER SkipUI
    Skip UI-related optimizations
    
.PARAMETER SkipNetworking
    Skip networking-related optimizations
    
.PARAMETER CreateBackup
    Create registry backup before making changes
#>

[CmdletBinding()]
param(
    [switch]$SkipPerformance,
    [switch]$SkipSecurity,
    [switch]$SkipUI,
    [switch]$SkipNetworking,
    [switch]$CreateBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$BackupDir = Join-Path $LogDir 'registry-backups'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

#region Helper Functions

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [Registry] $Message"
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string]$Type = 'DWord',
        [string]$Description
    )
    
    try {
        # Create registry path if it doesn't exist
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        
        # Set registry value
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        
        if ($Description) {
            Write-Log "  [OK] $Description" -Level INFO
        }
        
        $script:OptimizationsApplied++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Failed to set $Path\$Name : $($_.Exception.Message)" -Level WARN
        $script:OptimizationsFailed++
        return $false
    }
}

function Backup-RegistryKeys {
    Write-Log "Creating registry backup..." -Level INFO
    
    try {
        if (-not (Test-Path $BackupDir)) {
            New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
        }
        
        $backupFile = Join-Path $BackupDir "registry-backup-$timestamp.reg"
        
        # Export key registry hives
        $keysToBackup = @(
            'HKLM\SYSTEM\CurrentControlSet\Services',
            'HKLM\SYSTEM\CurrentControlSet\Control',
            'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
            'HKLM\SOFTWARE\Policies\Microsoft\Windows'
        )
        
        foreach ($key in $keysToBackup) {
            $result = Start-Process -FilePath "reg.exe" -ArgumentList "export `"$key`" `"$backupFile`" /y" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        }
        
        Write-Log "Registry backup created: $backupFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Registry backup failed: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region Performance Optimizations

function Set-PerformanceOptimizations {
    if ($SkipPerformance) {
        Write-Log "Skipping performance optimizations" -Level INFO
        return
    }
    
    Write-Log "Applying performance optimizations..." -Level INFO
    
    # Disable Windows Search indexing for better disk performance
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows Search' -Name 'SetupCompletedSuccessfully' -Value 0 -Description 'Disable Windows Search indexing'
    
    # Disable Superfetch/SysMain (not needed on servers)
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\SysMain' -Name 'Start' -Value 4 -Description 'Disable Superfetch/SysMain'
    
    # Optimize memory management
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'ClearPageFileAtShutdown' -Value 0 -Description 'Disable page file clearing at shutdown'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 1 -Description 'Keep kernel in memory'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'LargeSystemCache' -Value 1 -Description 'Optimize for file sharing'
    
    # Disable hibernation (saves disk space)
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -Value 0 -Description 'Disable hibernation'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabledDefault' -Value 0 -Description 'Disable hibernation by default'
    
    # Optimize boot settings
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'WaitToKillServiceTimeout' -Value '2000' -Type String -Description 'Reduce service kill timeout'
    
    # Disable unnecessary visual effects for better performance
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Description 'Set visual effects for best performance'
    
    # Optimize disk timeout values
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk' -Name 'TimeOutValue' -Value 60 -Description 'Set disk timeout to 60 seconds'
    
    # Disable Windows Error Reporting
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'Disabled' -Value 1 -Description 'Disable Windows Error Reporting'
    
    # Disable automatic maintenance
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' -Name 'MaintenanceDisabled' -Value 1 -Description 'Disable automatic maintenance'
    
    Write-Log "Performance optimizations completed" -Level INFO
}

#endregion

#region Security Optimizations

function Set-SecurityOptimizations {
    if ($SkipSecurity) {
        Write-Log "Skipping security optimizations" -Level INFO
        return
    }
    
    Write-Log "Applying security optimizations..." -Level INFO
    
    # Disable LLMNR (security best practice)
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Value 0 -Description 'Disable LLMNR'
    
    # Disable NetBIOS over TCP/IP
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' -Name 'NodeType' -Value 2 -Description 'Disable NetBIOS broadcasts'
    
    # Enable DEP (Data Execution Prevention) for all programs
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoDataExecutionPrevention' -Value 0 -Description 'Enable DEP for all programs'
    
    # Disable autorun for all drives
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Value 255 -Description 'Disable autorun for all drives'
    
    # Enable UAC (User Account Control)
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value 1 -Description 'Enable UAC'
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Value 5 -Description 'Set UAC prompt for administrators'
    
    # Disable anonymous enumeration of SAM accounts
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymousSAM' -Value 1 -Description 'Disable anonymous SAM enumeration'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymous' -Value 1 -Description 'Restrict anonymous access'
    
    # Disable LM hash storage
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'NoLMHash' -Value 1 -Description 'Disable LM hash storage'
    
    # Enable Windows Firewall logging
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Logging' -Name 'LogDroppedPackets' -Value 1 -Description 'Enable firewall dropped packet logging'
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Logging' -Name 'LogSuccessfulConnections' -Value 1 -Description 'Enable firewall successful connection logging'
    
    # Disable guest account
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList' -Name 'Guest' -Value 0 -Description 'Hide guest account'
    
    # Require Ctrl+Alt+Del for login (security best practice)
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableCAD' -Value 0 -Description 'Require Ctrl+Alt+Del for login'
    
    # Set minimum password length in message
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LegalNoticeCaption' -Value 'Notice' -Type String -Description 'Set legal notice caption'
    
    Write-Log "Security optimizations completed" -Level INFO
}

#endregion

#region UI Optimizations

function Set-UIOptimizations {
    if ($SkipUI) {
        Write-Log "Skipping UI optimizations" -Level INFO
        return
    }
    
    Write-Log "Applying UI optimizations..." -Level INFO
    
    # Disable Action Center
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableNotificationCenter' -Value 1 -Description 'Disable Action Center'
    
    # Disable Windows Consumer Features
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 -Description 'Disable Windows Consumer Features'
    
    # Disable tips and suggestions
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSoftLanding' -Value 1 -Description 'Disable tips and suggestions'
    
    # Disable lock screen
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1 -Description 'Disable lock screen'
    
    # Show file extensions
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Description 'Show file extensions'
    
    # Show hidden files
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value 1 -Description 'Show hidden files'
    
    # Disable shake to minimize
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoWindowMinimizingShortcuts' -Value 1 -Description 'Disable shake to minimize'
    
    # Set taskbar to never combine
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarGlomLevel' -Value 2 -Description 'Never combine taskbar buttons'
    
    # Disable new app installed notification
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoNewAppAlert' -Value 1 -Description 'Disable new app notification'
    
    # Disable first sign-in animation
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableFirstLogonAnimation' -Value 0 -Description 'Disable first sign-in animation'
    
    # Set Windows Explorer to open to This PC
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Value 1 -Description 'Open Explorer to This PC'
    
    Write-Log "UI optimizations completed" -Level INFO
}

#endregion

#region Networking Optimizations

function Set-NetworkingOptimizations {
    if ($SkipNetworking) {
        Write-Log "Skipping networking optimizations" -Level INFO
        return
    }
    
    Write-Log "Applying networking optimizations..." -Level INFO
    
    # Disable IPv6 components (keep enabled but disable components if needed)
    # Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -Value 0xFF -Description 'Disable IPv6 components'
    
    # Optimize TCP/IP settings
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'TcpMaxDataRetransmissions' -Value 3 -Description 'Set TCP max retransmissions'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'TcpTimedWaitDelay' -Value 30 -Description 'Reduce TCP TIME_WAIT delay'
    
    # Optimize network throttling
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Description 'Disable network throttling'
    
    # Enable RSS (Receive Side Scaling)
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'EnableRSS' -Value 1 -Description 'Enable RSS'
    
    # Optimize for network applications
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'Size' -Value 3 -Description 'Optimize for network applications'
    
    # Disable Large Send Offload (can cause issues with some adapters)
    # Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'DisableTaskOffload' -Value 0 -Description 'Enable TCP offloading'
    
    # Set DNS cache settings
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'NegativeCacheTime' -Value 0 -Description 'Disable negative DNS caching'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'MaxNegativeCacheTtl' -Value 0 -Description 'Disable negative DNS cache TTL'
    
    # Disable Windows Network Connectivity Status Indicator tests
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' -Name 'NoActiveProbe' -Value 1 -Description 'Disable NCSI active probes'
    
    # Optimize SMB settings
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'DisableBandwidthThrottling' -Value 1 -Description 'Disable SMB bandwidth throttling'
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'DisableLargeMtu' -Value 0 -Description 'Enable large MTU for SMB'
    
    Write-Log "Networking optimizations completed" -Level INFO
}

#endregion

#region Additional System Optimizations

function Set-SystemOptimizations {
    Write-Log "Applying additional system optimizations..." -Level INFO
    
    # Disable Customer Experience Improvement Program
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' -Name 'CEIPEnable' -Value 0 -Description 'Disable CEIP'
    
    # Disable Application Compatibility Engine
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisableInventory' -Value 1 -Description 'Disable App Compat inventory'
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisableUAR' -Value 1 -Description 'Disable App Compat UAR'
    
    # Disable Program Compatibility Assistant
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisablePCA' -Value 1 -Description 'Disable Program Compatibility Assistant'
    
    # Disable Windows Media Player network sharing
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer' -Name 'PreventLibrarySharing' -Value 1 -Description 'Prevent WMP library sharing'
    
    # Disable delivery optimization
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DODownloadMode' -Value 0 -Description 'Disable delivery optimization'
    
    # Set time service to start automatically
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time' -Name 'Start' -Value 2 -Description 'Set W32Time to automatic'
    
    # Disable Remote Assistance
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name 'fAllowToGetHelp' -Value 0 -Description 'Disable Remote Assistance'
    
    # Optimize event log service
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog' -Name 'Start' -Value 2 -Description 'Set Event Log to automatic'
    
    # Disable Storage Sense
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' -Name 'AllowStorageSenseGlobal' -Value 0 -Description 'Disable Storage Sense'
    
    Write-Log "Additional system optimizations completed" -Level INFO
}

#endregion

#region Main Execution

function Main {
    # Setup local file logging to C:\xoap-logs (transcript captures all host output)
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
    } catch {
        Write-Host "[WARN] Failed to start transcript logging to $LogDir : $($_.Exception.Message)"
    }

    $scriptStartTime = Get-Date

    Write-Log "===== Configure_Registry_Optimizations starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Create backup if requested
    if ($CreateBackup) {
        Backup-RegistryKeys | Out-Null
    }
    
    # Apply optimizations
    Set-PerformanceOptimizations
    Set-SecurityOptimizations
    Set-UIOptimizations
    Set-NetworkingOptimizations
    Set-SystemOptimizations
    
    # Summary
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    if ($script:OptimizationsFailed -eq 0) {
        Write-Log "NOTE: Some changes may require a system restart to take effect" -Level WARN
    }
    else {
        Write-Log "Optimizations completed with $script:OptimizationsFailed warnings" -Level WARN
    }
    Write-Log "===== Configure_Registry_Optimizations complete in $([int]$duration)s; applied=$($script:OptimizationsApplied) failed=$($script:OptimizationsFailed) ====="
    exit 0
}

# Execute main function
try {
    Main
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}

#endregion
