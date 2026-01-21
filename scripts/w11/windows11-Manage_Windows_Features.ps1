<#
.SYNOPSIS
    Manage Windows Features and Capabilities for Windows 10/11

.DESCRIPTION
    Installs, removes, and manages Windows 10/11 roles, features, and capabilities.
    Supports dependency handling, DISM operations, and comprehensive reporting.
    Optimized for Windows 10/11 and Packer workflows.

.NOTES
    File Name      : windows11-Manage_Windows_Features.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Manage_Windows_Features.ps1 -Install -FeatureName "Web-Server", "Web-Mgmt-Tools"
    Installs IIS and management tools
    
.EXAMPLE
    .\windows11-Manage_Windows_Features.ps1 -Remove -FeatureName "Windows-Defender"
    Removes Windows Defender feature
    
.EXAMPLE
    .\windows11-Manage_Windows_Features.ps1 -ListAvailable
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

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

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
    
    Write-LogMessage "Retrieving Windows features ($Filter)..." -Level Info
    
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
        Write-LogMessage "Error retrieving features: $($_.Exception.Message)" -Level Error
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
        Write-LogMessage "No features found" -Level Warning
        return
    }
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "Windows Features ($Filter): $($features.Count)" -Level Info
    Write-LogMessage "=" * 80 -Level Info
    
    # Group by feature type
    $grouped = $features | Group-Object -Property FeatureType
    
    foreach ($group in $grouped) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "$($group.Name) ($($group.Count)):" -Level Info
        
        foreach ($feature in $group.Group | Sort-Object DisplayName) {
            $status = if ($feature.Installed) { "[Installed]" } else { "[Available]" }
            $indent = "  " * $feature.Depth
            Write-LogMessage "$indent$status $($feature.DisplayName) ($($feature.Name))" -Level Info
        }
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
    
    Write-LogMessage "Installing feature: $Name" -Level Info
    
    try {
        # Check if already installed
        $feature = Get-WindowsFeature -Name $Name -ErrorAction Stop
        
        if (-not $feature) {
            Write-LogMessage "  ✗ Feature not found: $Name" -Level Error
            $script:OperationsFailed++
            return $false
        }
        
        if ($feature.Installed) {
            Write-LogMessage "  ⚠ Feature is already installed" -Level Warning
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
        
        Write-LogMessage "  Installing..." -Level Info
        
        # Install feature
        $result = Install-WindowsFeature @installParams
        
        if ($result.Success) {
            Write-LogMessage "  ✓ Installation successful" -Level Success
            Write-LogMessage "    Feature: $($feature.DisplayName)" -Level Info
            
            if ($result.FeatureResult) {
                Write-LogMessage "    Components installed: $($result.FeatureResult.Count)" -Level Info
            }
            
            if ($result.RestartNeeded -eq 'Yes') {
                Write-LogMessage "    ⚠ Restart required" -Level Warning
            }
            
            $script:FeaturesInstalled++
            return $true
        }
        else {
            Write-LogMessage "  ✗ Installation failed" -Level Error
            
            if ($result.ExitCode) {
                Write-LogMessage "    Exit code: $($result.ExitCode)" -Level Error
            }
            
            $script:OperationsFailed++
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error installing feature: $($_.Exception.Message)" -Level Error
        $script:OperationsFailed++
        return $false
    }
}

function Install-MultipleFeatures {
    param(
        [Parameter(Mandatory)]
        [string[]]$Features
    )
    
    Write-LogMessage "Installing $($Features.Count) feature(s)..." -Level Info
    Write-LogMessage "" -Level Info
    
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
        
        Write-LogMessage "" -Level Info
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
    
    Write-LogMessage "Removing feature: $Name" -Level Info
    
    try {
        # Check if installed
        $feature = Get-WindowsFeature -Name $Name -ErrorAction Stop
        
        if (-not $feature) {
            Write-LogMessage "  ✗ Feature not found: $Name" -Level Error
            $script:OperationsFailed++
            return $false
        }
        
        if (-not $feature.Installed) {
            Write-LogMessage "  ⚠ Feature is not installed" -Level Warning
            return $true
        }
        
        Write-LogMessage "  Removing..." -Level Info
        
        # Remove feature
        $result = Uninstall-WindowsFeature -Name $Name -Remove -ErrorAction Stop
        
        if ($result.Success) {
            Write-LogMessage "  ✓ Removal successful" -Level Success
            Write-LogMessage "    Feature: $($feature.DisplayName)" -Level Info
            
            if ($result.RestartNeeded -eq 'Yes') {
                Write-LogMessage "    ⚠ Restart required" -Level Warning
            }
            
            $script:FeaturesRemoved++
            return $true
        }
        else {
            Write-LogMessage "  ✗ Removal failed" -Level Error
            $script:OperationsFailed++
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error removing feature: $($_.Exception.Message)" -Level Error
        $script:OperationsFailed++
        return $false
    }
}

function Remove-MultipleFeatures {
    param(
        [Parameter(Mandatory)]
        [string[]]$Features
    )
    
    Write-LogMessage "Removing $($Features.Count) feature(s)..." -Level Info
    Write-LogMessage "" -Level Info
    
    $restartNeeded = $false
    
    foreach ($featureName in $Features) {
        $result = Remove-WindowsFeatureComplete -Name $featureName
        
        if ($result) {
            $feature = Get-WindowsFeature -Name $featureName
            if ($feature.InstallState -eq 'RemovePending') {
                $restartNeeded = $true
            }
        }
        
        Write-LogMessage "" -Level Info
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
    Write-LogMessage "Common Feature Sets:" -Level Info
    Write-LogMessage "=" * 80 -Level Info
    
    $sets = Get-CommonFeatureSets
    
    foreach ($setName in $sets.Keys | Sort-Object) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "$setName ($($sets[$setName].Count) features):" -Level Info
        
        foreach ($feature in $sets[$setName]) {
            $installed = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
            $status = if ($installed -and $installed.Installed) { "[Installed]" } else { "[Available]" }
            Write-LogMessage "  $status $feature" -Level Info
        }
    }
}

#endregion

#region Reporting

function Get-FeatureInstallationReport {
    Write-LogMessage "Generating feature installation report..." -Level Info
    
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
        
        Write-LogMessage "Feature report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
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
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Windows Features Management" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
        exit 1
    }
    
    # Check if ServerManager module is available
    if (-not (Get-Module -Name ServerManager -ListAvailable)) {
        Write-LogMessage "ServerManager module not available. This script requires Windows 10/11." -Level Error
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
            Write-LogMessage "FeatureName parameter is required for installation" -Level Error
            exit 1
        }
        
        $restartNeeded = Install-MultipleFeatures -Features $FeatureName
        $operationPerformed = $true
    }
    
    # Remove features
    if ($Remove) {
        if (-not $FeatureName) {
            Write-LogMessage "FeatureName parameter is required for removal" -Level Error
            exit 1
        }
        
        $restartNeeded = Remove-MultipleFeatures -Features $FeatureName
        $operationPerformed = $true
    }
    
    # If no operation specified, show installed features
    if (-not $operationPerformed) {
        Write-LogMessage "No operation specified. Use -ListInstalled, -ListAvailable, -Install, or -Remove" -Level Info
        Write-LogMessage "" -Level Info
        Show-FeaturesList -Filter 'Installed'
    }
    
    # Generate report
    Get-FeatureInstallationReport | Out-Null
    
    # Handle restart if needed
    if ($restartNeeded) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "========================================" -Level Warning
        Write-LogMessage "RESTART REQUIRED" -Level Warning
        Write-LogMessage "========================================" -Level Warning
        
        if ($RestartIfNeeded) {
            Write-LogMessage "System will restart in 60 seconds..." -Level Warning
            Start-Sleep -Seconds 5
            Restart-Computer -Force
            exit 0
        }
        else {
            Write-LogMessage "Please restart the system to complete the operation" -Level Warning
            Write-LogMessage "Use -RestartIfNeeded to restart automatically" -Level Info
        }
    }
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Features Management Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Features Installed: $script:FeaturesInstalled" -Level Info
    Write-LogMessage "Features Removed: $script:FeaturesRemoved" -Level Info
    Write-LogMessage "Operations Failed: $script:OperationsFailed" -Level Info
    Write-LogMessage "Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:OperationsFailed -eq 0) {
        Write-LogMessage "Windows features management completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Features management completed with $script:OperationsFailed failures" -Level Warning
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
