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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [PageFile] $Message"
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
        Write-Log "Error getting physical memory size: $($_.Exception.Message)" -Level WARN
        return 0
    }
}

function Get-RecommendedPageFileSize {
    Write-Log "Calculating recommended page file size..." -Level INFO
    
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
        
        Write-Log "System RAM: $ramGB GB" -Level INFO
        Write-Log "Recommended Initial Size: $initialMB MB ($([math]::Round($initialMB/1024, 2)) GB)" -Level INFO
        Write-Log "Recommended Maximum Size: $maximumMB MB ($([math]::Round($maximumMB/1024, 2)) GB)" -Level INFO
        
        return @{
            InitialSize = $initialMB
            MaximumSize = $maximumMB
        }
    }
    catch {
        Write-Log "Error calculating recommended size: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

#endregion

#region Page File Configuration

function Get-CurrentPageFileConfiguration {
    Write-Log "Retrieving current page file configuration..." -Level INFO
    
    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        $pageFileUsage = Get-CimInstance -ClassName Win32_PageFileUsage
        
        if ($pageFiles) {
            foreach ($pf in $pageFiles) {
                Write-Log "  Current: $($pf.Name)" -Level INFO
                Write-Log "    Initial Size: $($pf.InitialSize) MB" -Level INFO
                Write-Log "    Maximum Size: $($pf.MaximumSize) MB" -Level INFO
            }
        }
        else {
            Write-Log "  No page files configured (system-managed or none)" -Level INFO
        }
        
        if ($pageFileUsage) {
            foreach ($pfu in $pageFileUsage) {
                Write-Log "  Usage: $($pfu.Name)" -Level INFO
                Write-Log "    Allocated: $($pfu.AllocatedBaseSize) MB" -Level INFO
                Write-Log "    Current: $($pfu.CurrentUsage) MB" -Level INFO
                Write-Log "    Peak: $($pfu.PeakUsage) MB" -Level INFO
            }
        }
        
        return $pageFiles
    }
    catch {
        Write-Log "Error retrieving page file info: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Remove-ExistingPageFiles {
    Write-Log "Removing existing page files..." -Level INFO
    
    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        
        if ($pageFiles) {
            foreach ($pf in $pageFiles) {
                Write-Log "  Removing: $($pf.Name)" -Level INFO
                Remove-CimInstance -InputObject $pf
            }
            
            Write-Log "Existing page files removed" -Level INFO
            $script:ConfigurationsApplied++
            return $true
        }
        else {
            Write-Log "No existing page files to remove" -Level INFO
            return $true
        }
    }
    catch {
        Write-Log "Error removing page files: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Disable-AutomaticPageFile {
    Write-Log "Disabling automatic page file management..." -Level INFO
    
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        
        if ($computerSystem.AutomaticManagedPagefile) {
            $computerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile = $false}
            Write-Log "Automatic page file management disabled" -Level INFO
            $script:ConfigurationsApplied++
        }
        else {
            Write-Log "Automatic page file management already disabled" -Level INFO
        }
        
        return $true
    }
    catch {
        Write-Log "Error disabling automatic page file: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Enable-AutomaticPageFile {
    Write-Log "Enabling automatic page file management..." -Level INFO
    
    try {
        # Remove existing page files first
        Remove-ExistingPageFiles | Out-Null
        
        # Enable system-managed page file
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $computerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile = $true}
        
        Write-Log "Automatic page file management enabled" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error enabling automatic page file: $($_.Exception.Message)" -Level ERROR
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
    
    Write-Log "Creating custom page file..." -Level INFO
    
    try {
        # Validate drive
        if (-not (Test-Path $DriveLetter)) {
            Write-Log "Drive $DriveLetter does not exist" -Level ERROR
            $script:ConfigurationsFailed++
            return $false
        }
        
        # Get drive info
        $driveInfo = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -PSProvider FileSystem
        $freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
        $requiredGB = [math]::Round($Maximum / 1024, 2)
        
        Write-Log "Drive: $DriveLetter" -Level INFO
        Write-Log "  Free Space: $freeSpaceGB GB" -Level INFO
        Write-Log "  Required: $requiredGB GB" -Level INFO
        
        if ($freeSpaceGB -lt $requiredGB) {
            Write-Log "Insufficient free space on $DriveLetter" -Level WARN
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
        
        Write-Log "Page file created: $pageFileName" -Level INFO
        Write-Log "  Initial Size: $Initial MB ($([math]::Round($Initial/1024, 2)) GB)" -Level INFO
        Write-Log "  Maximum Size: $Maximum MB ($([math]::Round($Maximum/1024, 2)) GB)" -Level INFO
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error creating page file: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

#endregion

#region Verification

function Test-PageFileConfiguration {
    Write-Log "Verifying page file configuration..." -Level INFO
    
    try {
        # Wait a moment for changes to take effect
        Start-Sleep -Seconds 2
        
        # Check automatic management status
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        Write-Log "  Automatic Management: $($computerSystem.AutomaticManagedPagefile)" -Level INFO
        
        # Check configured page files
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting
        if ($pageFiles) {
            Write-Log "  Configured Page Files: $($pageFiles.Count)" -Level INFO
            foreach ($pf in $pageFiles) {
                Write-Log "    $($pf.Name): $($pf.InitialSize)-$($pf.MaximumSize) MB" -Level INFO
            }
        }
        else {
            if ($computerSystem.AutomaticManagedPagefile) {
                Write-Log "  System-managed page file (no manual configuration)" -Level INFO
            }
            else {
                Write-Log "  WARNING: No page files configured!" -Level WARN
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Error verifying configuration: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Get-PageFileReport {
    Write-Log "Generating page file configuration report..." -Level INFO
    
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
        
        Write-Log "Page file report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
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

    Write-Log "===== Configure_Page_File starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Display current configuration
    Get-CurrentPageFileConfiguration | Out-Null
    Write-Log "" -Level INFO
    
    # Process based on parameter set
    if ($RemoveAllPageFiles) {
        Write-Log "Removing all page files..." -Level WARN
        $success = Remove-ExistingPageFiles
    }
    elseif ($SystemManaged) {
        Write-Log "Configuring system-managed page file..." -Level INFO
        $success = Enable-AutomaticPageFile
    }
    elseif ($RecommendedSize) {
        Write-Log "Using recommended page file size..." -Level INFO
        $recommended = Get-RecommendedPageFileSize
        
        if ($recommended) {
            $success = New-CustomPageFile -DriveLetter $Drive `
                -Initial $recommended.InitialSize `
                -Maximum $recommended.MaximumSize
        }
        else {
            Write-Log "Could not calculate recommended size" -Level ERROR
            $success = $false
        }
    }
    else {
        # Custom configuration
        if ($InitialSize -gt 0 -and $MaximumSize -gt 0) {
            Write-Log "Configuring custom page file..." -Level INFO
            
            if ($InitialSize -gt $MaximumSize) {
                Write-Log "ERROR: Initial size cannot be greater than maximum size" -Level ERROR
                exit 1
            }
            
            $success = New-CustomPageFile -DriveLetter $Drive `
                -Initial $InitialSize `
                -Maximum $MaximumSize
        }
        else {
            Write-Log "No configuration specified, displaying current settings only" -Level INFO
            $success = $true
        }
    }
    
    # Verify configuration
    if ($success) {
        Write-Log "" -Level INFO
        Test-PageFileConfiguration | Out-Null
    }
    
    # Generate report
    Get-PageFileReport | Out-Null
    
    # Summary
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    if ($script:ConfigurationsFailed -eq 0) {
        Write-Log "NOTE: A system restart is required for changes to take effect" -Level WARN
        Write-Log "===== Configure_Page_File complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_Page_File complete in $([int]$duration)s; applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) =====" -Level WARN
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
