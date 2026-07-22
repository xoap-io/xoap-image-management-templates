<#
.SYNOPSIS
    Manage Windows Features and Capabilities for Windows Server

.DESCRIPTION
    Installs, removes, and manages Windows Server roles, features, and capabilities.
    Supports dependency handling, DISM operations, and comprehensive reporting.
    Optimized for Windows Server 2025 and Packer workflows.

.NOTES
    File Name      : windows-server-Manage_Windows_Features.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Manage_Windows_Features.ps1 -Install -FeatureName "Web-Server", "Web-Mgmt-Tools"
    Installs IIS and management tools
    
.EXAMPLE
    .\windows-server-Manage_Windows_Features.ps1 -Remove -FeatureName "Windows-Defender"
    Removes Windows Defender feature
    
.EXAMPLE
    .\windows-server-Manage_Windows_Features.ps1 -ListAvailable
    Lists all available features
    
.PARAMETER Install
    Install Windows features
    
.PARAMETER Remove
    Remove Windows features
    
.PARAMETER FeatureName
    Feature names to install or remove (comma-separated or array)
    
.PARAMETER IncludeManagementTools
    Include management tools when installing features
    
.PARAMETER IncludeAllSubFeatures
    Include all sub-features
    
.PARAMETER ListInstalled
    List installed features
    
.PARAMETER ListAvailable
    List all available features
    
.PARAMETER Source
    Source path for feature files (for offline installation)
    
.PARAMETER RestartIfNeeded
    Automatically restart if required
#>

[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Remove,
    [string[]]$FeatureName,
    [switch]$IncludeManagementTools,
    [switch]$IncludeAllSubFeatures,
    [switch]$ListInstalled,
    [switch]$ListAvailable,
    [string]$Source,
    [switch]$RestartIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:FeaturesInstalled = 0
$script:FeaturesRemoved = 0
$script:OperationsFailed = 0

#region Helper Functions

$script:Component = 'WindowsFeatures'

function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message
    Write-Host $line
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [WindowsFeatures] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region Feature Discovery

function Get-WindowsFeaturesList {
    param(
        [ValidateSet('All', 'Installed', 'Available')]
        [string]$Filter = 'All'
    )
    
    Write-Log "Retrieving Windows features ($Filter)..."    
    try {
        $features = Get-WindowsFeature
        
        switch ($Filter) {
            'Installed' {
                $features = $features | Where-Object { $_.Installed -eq $true }
            }
            'Available' {
                $features = $features | Where-Object { $_.Installed -eq $false }
            }
        }
        
        return $features
    }
    catch {
        Write-Log "Error retrieving features: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Show-FeaturesList {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('All', 'Installed', 'Available')]
        [string]$Filter
    )
    
    $features = Get-WindowsFeaturesList -Filter $Filter
    
    if (-not $features) {
        Write-Log "No features found" -Level WARN
        return
    }
        Write-Log "Windows Features ($Filter): $($features.Count)"    Write-Log "=" * 80    
    # Group by feature type
    $grouped = $features | Group-Object -Property FeatureType
    
    foreach ($group in $grouped) {        Write-Log "$($group.Name) ($($group.Count)):"        
        foreach ($feature in $group.Group | Sort-Object DisplayName) {
            $status = if ($feature.Installed) { "[Installed]" } else { "[Available]" }
            $indent = "  " * $feature.Depth
            Write-Log "$indent$status $($feature.DisplayName) ($($feature.Name))"        }
    }
}

#endregion

#region Feature Installation

function Install-WindowsFeatureWithDependencies {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$ManagementTools,
        [switch]$AllSubFeatures,
        [string]$SourcePath
    )
    
    Write-Log "Installing feature: $Name"    
    try {
        # Check if already installed
        $feature = Get-WindowsFeature -Name $Name -ErrorAction Stop
        
        if (-not $feature) {
            Write-Log "  [FAIL] Feature not found: $Name" -Level ERROR
            $script:OperationsFailed++
            return $false
        }
        
        if ($feature.Installed) {
            Write-Log "  [WARN] Feature is already installed" -Level WARN
            return $true
        }
        
        # Build installation parameters
        $installParams = @{
            Name = $Name
            ErrorAction = 'Stop'
        }
        
        if ($ManagementTools) {
            $installParams['IncludeManagementTools'] = $true
        }
        
        if ($AllSubFeatures) {
            $installParams['IncludeAllSubFeature'] = $true
        }
        
        if ($SourcePath) {
            $installParams['Source'] = $SourcePath
        }
        
        Write-Log "  Installing..."        
        # Install feature
        $result = Install-WindowsFeature @installParams
        
        if ($result.Success) {
            Write-Log "  [OK] Installation successful" -Level INFO
            Write-Log "    Feature: $($feature.DisplayName)"            
            if ($result.FeatureResult) {
                Write-Log "    Components installed: $($result.FeatureResult.Count)"            }
            
            if ($result.RestartNeeded -eq 'Yes') {
                Write-Log "    [WARN] Restart required" -Level WARN
            }
            
            $script:FeaturesInstalled++
            return $true
        }
        else {
            Write-Log "  [FAIL] Installation failed" -Level ERROR
            
            if ($result.ExitCode) {
                Write-Log "    Exit code: $($result.ExitCode)" -Level ERROR
            }
            
            $script:OperationsFailed++
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error installing feature: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

function Install-MultipleFeatures {
    param(
        [Parameter(Mandatory)]
        [string[]]$Features
    )
    
    Write-Log "Installing $($Features.Count) feature(s)..."    Write-Log ""    
    $restartNeeded = $false
    
    foreach ($featureName in $Features) {
        $result = Install-WindowsFeatureWithDependencies `
            -Name $featureName `
            -ManagementTools:$IncludeManagementTools `
            -AllSubFeatures:$IncludeAllSubFeatures `
            -SourcePath $Source
        
        if ($result) {
            # Check if restart is needed
            $feature = Get-WindowsFeature -Name $featureName
            if ($feature.InstallState -eq 'InstallPending') {
                $restartNeeded = $true
            }
        }
            }
    
    return $restartNeeded
}

#endregion

#region Feature Removal

function Remove-WindowsFeatureComplete {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    Write-Log "Removing feature: $Name"    
    try {
        # Check if installed
        $feature = Get-WindowsFeature -Name $Name -ErrorAction Stop
        
        if (-not $feature) {
            Write-Log "  [FAIL] Feature not found: $Name" -Level ERROR
            $script:OperationsFailed++
            return $false
        }
        
        if (-not $feature.Installed) {
            Write-Log "  [WARN] Feature is not installed" -Level WARN
            return $true
        }
        
        Write-Log "  Removing..."        
        # Remove feature
        $result = Uninstall-WindowsFeature -Name $Name -Remove -ErrorAction Stop
        
        if ($result.Success) {
            Write-Log "  [OK] Removal successful" -Level INFO
            Write-Log "    Feature: $($feature.DisplayName)"            
            if ($result.RestartNeeded -eq 'Yes') {
                Write-Log "    [WARN] Restart required" -Level WARN
            }
            
            $script:FeaturesRemoved++
            return $true
        }
        else {
            Write-Log "  [FAIL] Removal failed" -Level ERROR
            $script:OperationsFailed++
            return $false
        }
    }
    catch {
        Write-Log "  [FAIL] Error removing feature: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

function Remove-MultipleFeatures {
    param(
        [Parameter(Mandatory)]
        [string[]]$Features
    )
    
    Write-Log "Removing $($Features.Count) feature(s)..."    Write-Log ""    
    $restartNeeded = $false
    
    foreach ($featureName in $Features) {
        $result = Remove-WindowsFeatureComplete -Name $featureName
        
        if ($result) {
            $feature = Get-WindowsFeature -Name $featureName
            if ($feature.InstallState -eq 'RemovePending') {
                $restartNeeded = $true
            }
        }
            }
    
    return $restartNeeded
}

#endregion

#region Common Feature Sets

function Get-CommonFeatureSets {
    return @{
        'WebServer' = @(
            'Web-Server'
            'Web-Common-Http'
            'Web-Default-Doc'
            'Web-Dir-Browsing'
            'Web-Http-Errors'
            'Web-Static-Content'
            'Web-Mgmt-Tools'
            'Web-Mgmt-Console'
        )
        'FileServer' = @(
            'FS-FileServer'
            'FS-Resource-Manager'
            'FS-VSS-Agent'
            'FS-Data-Deduplication'
        )
        'DNSServer' = @(
            'DNS'
            'RSAT-DNS-Server'
        )
        'DHCPServer' = @(
            'DHCP'
            'RSAT-DHCP'
        )
        'ActiveDirectory' = @(
            'AD-Domain-Services'
            'RSAT-ADDS'
            'RSAT-AD-PowerShell'
        )
        'HyperV' = @(
            'Hyper-V'
            'Hyper-V-PowerShell'
            'Hyper-V-Tools'
            'RSAT-Hyper-V-Tools'
        )
        'RemoteDesktop' = @(
            'RDS-RD-Server'
            'RDS-Licensing'
            'RDS-Gateway'
            'RSAT-RDS-Tools'
        )
        'Containers' = @(
            'Containers'
            'Hyper-V-PowerShell'
        )
    }
}

function Show-CommonFeatureSets {
    Write-Log "Common Feature Sets:"    Write-Log "=" * 80    
    $sets = Get-CommonFeatureSets
    
    foreach ($setName in $sets.Keys | Sort-Object) {        Write-Log "$setName ($($sets[$setName].Count) features):"        
        foreach ($feature in $sets[$setName]) {
            $installed = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
            $status = if ($installed -and $installed.Installed) { "[Installed]" } else { "[Available]" }
            Write-Log "  $status $feature"        }
    }
}

#endregion

#region Reporting

function Get-FeatureInstallationReport {
    Write-Log "Generating feature installation report..."    
    try {
        $reportFile = Join-Path $LogDir "windows-features-$timestamp.txt"
        $report = @()
        
        $report += "Windows Features Report"
        $report += "=" * 80
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # Session statistics
        $report += "Session Summary:"
        $report += "  Features Installed: $script:FeaturesInstalled"
        $report += "  Features Removed: $script:FeaturesRemoved"
        $report += "  Operations Failed: $script:OperationsFailed"
        $report += ""
        
        # Installed features
        $installedFeatures = Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Sort-Object DisplayName
        
        $report += "Installed Features ($($installedFeatures.Count)):"
        $report += "-" * 80
        
        foreach ($feature in $installedFeatures) {
            $indent = "  " * $feature.Depth
            $report += "$indent$($feature.DisplayName) ($($feature.Name))"
        }
        $report += ""
        
        # Pending restart
        $pendingReboot = Test-PendingReboot
        $report += "Pending Restart: $pendingReboot"
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-Log "Feature report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Test-PendingReboot {
    try {
        # Check multiple sources for pending reboot
        $pendingReboot = $false
        
        # Check Windows Update
        $wuReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
        if ($wuReboot) { $pendingReboot = $true }
        
        # Check Component Based Servicing
        $cbsReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
        if ($cbsReboot) { $pendingReboot = $true }
        
        # Check PendingFileRenameOperations
        $fileRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($fileRename) { $pendingReboot = $true }
        
        return $pendingReboot
    }
    catch {
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-Log '===== Manage_Windows_Features starting ====='
    Write-Log "Log file: $LogFile"

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Check if ServerManager module is available
    if (-not (Get-Module -Name ServerManager -ListAvailable)) {
        Write-Log "ServerManager module not available. This script requires Windows Server." -Level ERROR
        exit 1
    }
    
    Import-Module ServerManager -ErrorAction Stop
    
    # Process operations
    $operationPerformed = $false
    $restartNeeded = $false
    
    # List available features
    if ($ListAvailable) {
        Show-FeaturesList -Filter 'Available'
        $operationPerformed = $true
    }
    
    # List installed features
    if ($ListInstalled) {
        Show-FeaturesList -Filter 'Installed'
        $operationPerformed = $true
    }
    
    # Install features
    if ($Install) {
        if (-not $FeatureName) {
            Write-Log "FeatureName parameter is required for installation" -Level ERROR
            exit 1
        }
        
        $restartNeeded = Install-MultipleFeatures -Features $FeatureName
        $operationPerformed = $true
    }
    
    # Remove features
    if ($Remove) {
        if (-not $FeatureName) {
            Write-Log "FeatureName parameter is required for removal" -Level ERROR
            exit 1
        }
        
        $restartNeeded = Remove-MultipleFeatures -Features $FeatureName
        $operationPerformed = $true
    }
    
    # If no operation specified, show installed features
    if (-not $operationPerformed) {
        Write-Log "No operation specified. Use -ListInstalled, -ListAvailable, -Install, or -Remove"        Write-Log ""        Show-FeaturesList -Filter 'Installed'
    }
    
    # Generate report
    Get-FeatureInstallationReport | Out-Null
    
    # Handle restart if needed
    if ($restartNeeded) {
        Write-Log 'Restart required to complete the operation.' -Level WARN

        if ($RestartIfNeeded) {
            Write-Log 'System will restart in 60 seconds...' -Level WARN
            Start-Sleep -Seconds 5
            try { Stop-Transcript | Out-Null } catch {}
            Restart-Computer -Force
            exit 0
        }
        else {
            Write-Log 'Use -RestartIfNeeded to restart automatically.' -Level WARN
        }
    }

    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime

    if ($script:OperationsFailed -eq 0) {
        Write-Log "===== Manage_Windows_Features complete in $([int]$duration.TotalSeconds)s applied=$($script:FeaturesInstalled + $script:FeaturesRemoved) failed=$script:OperationsFailed ====="
        exit 0
    }
    else {
        Write-Log "Features management completed with $script:OperationsFailed failure(s)." -Level ERROR
        exit 1
    }
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
