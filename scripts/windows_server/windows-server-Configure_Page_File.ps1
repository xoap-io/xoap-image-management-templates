<#
.SYNOPSIS
    Configure Page File Settings for Windows Server

.DESCRIPTION
    Configures Windows page file (virtual memory) size, location, and system-managed
    settings. Supports multiple page files across different drives. Optimized for
    Windows Server 2025 and enterprise deployments.

.NOTES
    File Name      : windows-server-Configure_Page_File.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Page_File.ps1 -SystemManaged
    Configures system-managed page file on C: drive
    
.EXAMPLE
    .\windows-server-Configure_Page_File.ps1 -Drive "D:" -InitialSize 4096 -MaximumSize 8192
    Sets custom page file size on D: drive
    
.EXAMPLE
    .\windows-server-Configure_Page_File.ps1 -Drive "C:" -InitialSize 16384 -MaximumSize 16384
    Sets fixed-size page file (16GB) on C: drive
    
.PARAMETER Drive
    Drive letter for page file (e.g., "C:", "D:")
    
.PARAMETER InitialSize
    Initial page file size in MB
    
.PARAMETER MaximumSize
    Maximum page file size in MB
    
.PARAMETER SystemManaged
    Use system-managed page file size
    
.PARAMETER RemoveAllPageFiles
    Remove all existing page files
    
.PARAMETER RecommendedSize
    Calculate and use recommended page file size based on RAM
#>

[CmdletBinding(DefaultParameterSetName='Custom')]
param(
    [Parameter(ParameterSetName='Custom')]
    [string]$Drive = "C:",
    
    [Parameter(ParameterSetName='Custom')]
    [int]$InitialSize = 0,
    
    [Parameter(ParameterSetName='Custom')]
    [int]$MaximumSize = 0,
    
    [Parameter(ParameterSetName='SystemManaged')]
    [switch]$SystemManaged,
    
    [Parameter(ParameterSetName='Remove')]
    [switch]$RemoveAllPageFiles,
    
    [Parameter(ParameterSetName='Recommended')]
    [switch]$RecommendedSize
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
$script:ConfigurationsApplied = 0
$script:ConfigurationsFailed = 0

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

function Get-PhysicalMemorySize {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $ramGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
        return $ramGB
    }
    catch {
        Write-LogMessage "Error getting physical memory size: $($_.Exception.Message)" -Level Warning
        return 0
    }
}

function Get-RecommendedPageFileSize {
    Write-LogMessage "Calculating recommended page file size..." -Level Info
    
    try {
        $ramGB = Get-PhysicalMemorySize
        
        # Microsoft recommendations:
        # Less than 8GB RAM: 1.5x to 3x RAM
        # 8-16GB RAM: 1x to 2x RAM
        # More than 16GB: 1x RAM or minimum 16GB
        
        if ($ramGB -le 8) {
            $initialMB = [math]::Round($ramGB * 1024 * 1.5)
            $maximumMB = [math]::Round($ramGB * 1024 * 3)
        }
        elseif ($ramGB -le 16) {
            $initialMB = [math]::Round($ramGB * 1024)
            $maximumMB = [math]::Round($ramGB * 1024 * 2)
        }
        else {
            $initialMB = [math]::Max(16384, [math]::Round($ramGB * 1024))
            $maximumMB = [math]::Max(16384, [math]::Round($ramGB * 1024))
        }
        
        Write-LogMessage "System RAM: $ramGB GB" -Level Info
        Write-LogMessage "Recommended Initial Size: $initialMB MB ($([math]::Round($initialMB/1024, 2)) GB)" -Level Info
        Write-LogMessage "Recommended Maximum Size: $maximumMB MB ($([math]::Round($maximumMB/1024, 2)) GB)" -Level Info
        
        return @{
            InitialSize = $initialMB
            MaximumSize = $maximumMB
        }
    }
    catch {
        Write-LogMessage "Error calculating recommended size: $($_.Exception.Message)" -Level Error
        return $null
    }
}

#endregion

#region Page File Configuration

function Get-CurrentPageFileConfiguration {
    Write-LogMessage "Retrieving current page file configuration..." -Level Info
    
    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        $pageFileUsage = Get-CimInstance -ClassName Win32_PageFileUsage
        
        if ($pageFiles) {
            foreach ($pf in $pageFiles) {
                Write-LogMessage "  Current: $($pf.Name)" -Level Info
                Write-LogMessage "    Initial Size: $($pf.InitialSize) MB" -Level Info
                Write-LogMessage "    Maximum Size: $($pf.MaximumSize) MB" -Level Info
            }
        }
        else {
            Write-LogMessage "  No page files configured (system-managed or none)" -Level Info
        }
        
        if ($pageFileUsage) {
            foreach ($pfu in $pageFileUsage) {
                Write-LogMessage "  Usage: $($pfu.Name)" -Level Info
                Write-LogMessage "    Allocated: $($pfu.AllocatedBaseSize) MB" -Level Info
                Write-LogMessage "    Current: $($pfu.CurrentUsage) MB" -Level Info
                Write-LogMessage "    Peak: $($pfu.PeakUsage) MB" -Level Info
            }
        }
        
        return $pageFiles
    }
    catch {
        Write-LogMessage "Error retrieving page file info: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Remove-ExistingPageFiles {
    Write-LogMessage "Removing existing page files..." -Level Info
    
    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        
        if ($pageFiles) {
            foreach ($pf in $pageFiles) {
                Write-LogMessage "  Removing: $($pf.Name)" -Level Info
                Remove-CimInstance -InputObject $pf
            }
            
            Write-LogMessage "Existing page files removed" -Level Success
            $script:ConfigurationsApplied++
            return $true
        }
        else {
            Write-LogMessage "No existing page files to remove" -Level Info
            return $true
        }
    }
    catch {
        Write-LogMessage "Error removing page files: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Disable-AutomaticPageFile {
    Write-LogMessage "Disabling automatic page file management..." -Level Info
    
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        
        if ($computerSystem.AutomaticManagedPagefile) {
            $computerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile = $false}
            Write-LogMessage "Automatic page file management disabled" -Level Success
            $script:ConfigurationsApplied++
        }
        else {
            Write-LogMessage "Automatic page file management already disabled" -Level Info
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error disabling automatic page file: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Enable-AutomaticPageFile {
    Write-LogMessage "Enabling automatic page file management..." -Level Info
    
    try {
        # Remove existing page files first
        Remove-ExistingPageFiles | Out-Null
        
        # Enable system-managed page file
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $computerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile = $true}
        
        Write-LogMessage "Automatic page file management enabled" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error enabling automatic page file: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function New-CustomPageFile {
    param(
        [string]$DriveLetter,
        [int]$Initial,
        [int]$Maximum
    )
    
    Write-LogMessage "Creating custom page file..." -Level Info
    
    try {
        # Validate drive
        if (-not (Test-Path $DriveLetter)) {
            Write-LogMessage "Drive $DriveLetter does not exist" -Level Error
            $script:ConfigurationsFailed++
            return $false
        }
        
        # Get drive info
        $driveInfo = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -PSProvider FileSystem
        $freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
        $requiredGB = [math]::Round($Maximum / 1024, 2)
        
        Write-LogMessage "Drive: $DriveLetter" -Level Info
        Write-LogMessage "  Free Space: $freeSpaceGB GB" -Level Info
        Write-LogMessage "  Required: $requiredGB GB" -Level Info
        
        if ($freeSpaceGB -lt $requiredGB) {
            Write-LogMessage "Insufficient free space on $DriveLetter" -Level Warning
        }
        
        # Disable automatic management
        Disable-AutomaticPageFile | Out-Null
        
        # Remove existing page files
        Remove-ExistingPageFiles | Out-Null
        
        # Create new page file
        $pageFileName = "$DriveLetter\pagefile.sys"
        
        $pageFile = New-CimInstance -ClassName Win32_PageFileSetting -Property @{
            Name = $pageFileName
            InitialSize = $Initial
            MaximumSize = $Maximum
        }
        
        Write-LogMessage "Page file created: $pageFileName" -Level Success
        Write-LogMessage "  Initial Size: $Initial MB ($([math]::Round($Initial/1024, 2)) GB)" -Level Info
        Write-LogMessage "  Maximum Size: $Maximum MB ($([math]::Round($Maximum/1024, 2)) GB)" -Level Info
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error creating page file: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Verification

function Test-PageFileConfiguration {
    Write-LogMessage "Verifying page file configuration..." -Level Info
    
    try {
        # Wait a moment for changes to take effect
        Start-Sleep -Seconds 2
        
        # Check automatic management status
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        Write-LogMessage "  Automatic Management: $($computerSystem.AutomaticManagedPagefile)" -Level Info
        
        # Check configured page files
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        if ($pageFiles) {
            Write-LogMessage "  Configured Page Files: $($pageFiles.Count)" -Level Info
            foreach ($pf in $pageFiles) {
                Write-LogMessage "    $($pf.Name): $($pf.InitialSize)-$($pf.MaximumSize) MB" -Level Info
            }
        }
        else {
            if ($computerSystem.AutomaticManagedPagefile) {
                Write-LogMessage "  System-managed page file (no manual configuration)" -Level Info
            }
            else {
                Write-LogMessage "  WARNING: No page files configured!" -Level Warning
            }
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error verifying configuration: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Get-PageFileReport {
    Write-LogMessage "Generating page file configuration report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "pagefile-config-$timestamp.txt"
        $report = @()
        
        $report += "Page File Configuration Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # System information
        $ramGB = Get-PhysicalMemorySize
        $report += "System Information:"
        $report += "  Physical RAM: $ramGB GB"
        $report += ""
        
        # Automatic management status
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $report += "Page File Management:"
        $report += "  Automatic Management: $($computerSystem.AutomaticManagedPagefile)"
        $report += ""
        
        # Configured page files
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        if ($pageFiles) {
            $report += "Configured Page Files:"
            foreach ($pf in $pageFiles) {
                $report += "  File: $($pf.Name)"
                $report += "    Initial Size: $($pf.InitialSize) MB ($([math]::Round($pf.InitialSize/1024, 2)) GB)"
                $report += "    Maximum Size: $($pf.MaximumSize) MB ($([math]::Round($pf.MaximumSize/1024, 2)) GB)"
                $report += ""
            }
        }
        else {
            $report += "Configured Page Files:"
            if ($computerSystem.AutomaticManagedPagefile) {
                $report += "  System-managed (automatic)"
            }
            else {
                $report += "  None configured"
            }
            $report += ""
        }
        
        # Current usage
        $pageFileUsage = Get-CimInstance -ClassName Win32_PageFileUsage
        if ($pageFileUsage) {
            $report += "Current Page File Usage:"
            foreach ($pfu in $pageFileUsage) {
                $report += "  File: $($pfu.Name)"
                $report += "    Allocated: $($pfu.AllocatedBaseSize) MB"
                $report += "    Current Usage: $($pfu.CurrentUsage) MB"
                $report += "    Peak Usage: $($pfu.PeakUsage) MB"
                $report += ""
            }
        }
        
        # Recommendations
        $recommended = Get-RecommendedPageFileSize
        if ($recommended) {
            $report += "Microsoft Recommendations:"
            $report += "  Initial Size: $($recommended.InitialSize) MB ($([math]::Round($recommended.InitialSize/1024, 2)) GB)"
            $report += "  Maximum Size: $($recommended.MaximumSize) MB ($([math]::Round($recommended.MaximumSize/1024, 2)) GB)"
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Page file report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Page File Configuration" -Level Info
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
    
    # Display current configuration
    Get-CurrentPageFileConfiguration | Out-Null
    Write-LogMessage "" -Level Info
    
    # Process based on parameter set
    if ($RemoveAllPageFiles) {
        Write-LogMessage "Removing all page files..." -Level Warning
        $success = Remove-ExistingPageFiles
    }
    elseif ($SystemManaged) {
        Write-LogMessage "Configuring system-managed page file..." -Level Info
        $success = Enable-AutomaticPageFile
    }
    elseif ($RecommendedSize) {
        Write-LogMessage "Using recommended page file size..." -Level Info
        $recommended = Get-RecommendedPageFileSize
        
        if ($recommended) {
            $success = New-CustomPageFile -DriveLetter $Drive `
                -Initial $recommended.InitialSize `
                -Maximum $recommended.MaximumSize
        }
        else {
            Write-LogMessage "Could not calculate recommended size" -Level Error
            $success = $false
        }
    }
    else {
        # Custom configuration
        if ($InitialSize -gt 0 -and $MaximumSize -gt 0) {
            Write-LogMessage "Configuring custom page file..." -Level Info
            
            if ($InitialSize -gt $MaximumSize) {
                Write-LogMessage "ERROR: Initial size cannot be greater than maximum size" -Level Error
                exit 1
            }
            
            $success = New-CustomPageFile -DriveLetter $Drive `
                -Initial $InitialSize `
                -Maximum $MaximumSize
        }
        else {
            Write-LogMessage "No configuration specified, displaying current settings only" -Level Info
            $success = $true
        }
    }
    
    # Verify configuration
    if ($success) {
        Write-LogMessage "" -Level Info
        Test-PageFileConfiguration | Out-Null
    }
    
    # Generate report
    Get-PageFileReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configuration Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configurations Applied: $script:ConfigurationsApplied" -Level Info
    Write-LogMessage "Configuration Failures: $script:ConfigurationsFailed" -Level Info
    Write-LogMessage "Duration: $($duration.TotalSeconds) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    Write-LogMessage "" -Level Info
    
    if ($script:ConfigurationsFailed -eq 0) {
        Write-LogMessage "Page file configuration completed successfully!" -Level Success
        Write-LogMessage "NOTE: A system restart is required for changes to take effect" -Level Warning
        exit 0
    }
    else {
        Write-LogMessage "Configuration completed with $script:ConfigurationsFailed errors" -Level Warning
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
