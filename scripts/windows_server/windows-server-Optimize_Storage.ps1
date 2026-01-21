<#
.SYNOPSIS
    Optimize Storage and Disks for Windows Server

.DESCRIPTION
    Performs disk optimization, defragmentation, TRIM operations, volume analysis,
    and storage cleanup. Optimized for Windows Server 2025 and Packer workflows.

.NOTES
    File Name      : windows-server-Optimize_Storage.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Optimize_Storage.ps1
    Optimizes all volumes with automatic detection
    
.EXAMPLE
    .\windows-server-Optimize_Storage.ps1 -DriveLetter "C", "D" -EnableTRIM -DefragmentHDD
    Optimizes specific drives with TRIM and defragmentation
    
.EXAMPLE
    .\windows-server-Optimize_Storage.ps1 -CleanupMode Aggressive
    Performs aggressive disk cleanup
    
.PARAMETER DriveLetter
    Drive letters to optimize (default: all)
    
.PARAMETER EnableTRIM
    Enable TRIM for SSDs
    
.PARAMETER DefragmentHDD
    Defragment HDDs
    
.PARAMETER AnalyzeOnly
    Only analyze volumes without optimization
    
.PARAMETER CleanupMode
    Cleanup mode: Basic, Standard, Aggressive
    
.PARAMETER CleanTempFiles
    Clean temporary files
    
.PARAMETER CleanWindowsUpdate
    Clean Windows Update files
    
.PARAMETER EmptyRecycleBin
    Empty Recycle Bin
#>

[CmdletBinding()]
param(
    [string[]]$DriveLetter,
    [switch]$EnableTRIM,
    [switch]$DefragmentHDD,
    [switch]$AnalyzeOnly,
    [ValidateSet('Basic', 'Standard', 'Aggressive')]
    [string]$CleanupMode = 'Standard',
    [switch]$CleanTempFiles,
    [switch]$CleanWindowsUpdate,
    [switch]$EmptyRecycleBin
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
$script:VolumesOptimized = 0
$script:SpaceReclaimed = 0
$script:OptimizationsFailed = 0

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

function Format-ByteSize {
    param([long]$Bytes)
    
    if ($Bytes -ge 1TB) { return "$([math]::Round($Bytes / 1TB, 2)) TB" }
    if ($Bytes -ge 1GB) { return "$([math]::Round($Bytes / 1GB, 2)) GB" }
    if ($Bytes -ge 1MB) { return "$([math]::Round($Bytes / 1MB, 2)) MB" }
    if ($Bytes -ge 1KB) { return "$([math]::Round($Bytes / 1KB, 2)) KB" }
    return "$Bytes Bytes"
}

#endregion

#region Volume Discovery

function Get-VolumesToOptimize {
    Write-LogMessage "Discovering volumes..." -Level Info
    
    try {
        if ($DriveLetter) {
            $volumes = @()
            foreach ($letter in $DriveLetter) {
                $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
                if ($vol) {
                    $volumes += $vol
                }
                else {
                    Write-LogMessage "  ⚠ Drive $letter not found" -Level Warning
                }
            }
        }
        else {
            # Get all fixed volumes
            $volumes = Get-Volume | Where-Object { 
                $_.DriveType -eq 'Fixed' -and 
                $_.FileSystem -ne $null -and
                $_.DriveLetter -ne $null
            }
        }
        
        if (-not $volumes) {
            Write-LogMessage "No volumes found to optimize" -Level Warning
            return $null
        }
        
        Write-LogMessage "Found $($volumes.Count) volume(s) to optimize:" -Level Info
        
        foreach ($volume in $volumes) {
            $size = Format-ByteSize -Bytes $volume.Size
            $free = Format-ByteSize -Bytes $volume.SizeRemaining
            $percentFree = [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1)
            
            Write-LogMessage "  $($volume.DriveLetter): $($volume.FileSystemLabel) - $size total, $free free ($percentFree%)" -Level Info
        }
        
        return $volumes
    }
    catch {
        Write-LogMessage "Error discovering volumes: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Get-DriveType {
    param([Parameter(Mandatory)]$Volume)
    
    try {
        # Get physical disk for the volume
        $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $volume.DriveLetter }
        
        if ($partition) {
            $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq $partition.DiskNumber }
            
            if ($disk) {
                return $disk.MediaType
            }
        }
        
        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

#endregion

#region Volume Analysis

function Get-VolumeAnalysis {
    param([Parameter(Mandatory)]$Volume)
    
    Write-LogMessage "Analyzing volume $($Volume.DriveLetter)..." -Level Info
    
    try {
        $analysis = Optimize-Volume -DriveLetter $Volume.DriveLetter -Analyze -ErrorAction Stop
        
        Write-LogMessage "  Analysis results:" -Level Info
        Write-LogMessage "    Fragmented: $($analysis.FragmentedPercentage)%" -Level Info
        Write-LogMessage "    Slab Consolidated: $($analysis.SlabConsolidated)" -Level Info
        
        return $analysis
    }
    catch {
        Write-LogMessage "  ⚠ Analysis not available: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

#endregion

#region Volume Optimization

function Optimize-VolumeStorage {
    param(
        [Parameter(Mandatory)]$Volume,
        [string]$MediaType
    )
    
    Write-LogMessage "Optimizing volume $($Volume.DriveLetter)..." -Level Info
    
    try {
        if ($AnalyzeOnly) {
            Get-VolumeAnalysis -Volume $Volume | Out-Null
            return $true
        }
        
        # Determine optimization method based on media type
        $optimizationType = switch ($MediaType) {
            'SSD' { 'ReTrim' }
            'HDD' { if ($DefragmentHDD) { 'Defrag' } else { 'Analyze' } }
            default { 'Analyze' }
        }
        
        Write-LogMessage "  Media Type: $MediaType" -Level Info
        Write-LogMessage "  Optimization Type: $optimizationType" -Level Info
        
        # Perform optimization
        switch ($optimizationType) {
            'ReTrim' {
                if ($EnableTRIM) {
                    Write-LogMessage "  Executing TRIM operation..." -Level Info
                    Optimize-Volume -DriveLetter $Volume.DriveLetter -ReTrim -ErrorAction Stop
                    Write-LogMessage "  ✓ TRIM completed" -Level Success
                }
                else {
                    Write-LogMessage "  ⚠ TRIM optimization skipped (use -EnableTRIM to enable)" -Level Warning
                }
            }
            'Defrag' {
                Write-LogMessage "  Defragmenting volume..." -Level Info
                Optimize-Volume -DriveLetter $Volume.DriveLetter -Defrag -ErrorAction Stop
                Write-LogMessage "  ✓ Defragmentation completed" -Level Success
            }
            'Analyze' {
                Get-VolumeAnalysis -Volume $Volume | Out-Null
            }
        }
        
        $script:VolumesOptimized++
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error optimizing volume: $($_.Exception.Message)" -Level Error
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Disk Cleanup

function Invoke-DiskCleanup {
    Write-LogMessage "Performing disk cleanup ($CleanupMode mode)..." -Level Info
    
    $spaceBeforeCleanup = (Get-Volume -DriveLetter C).SizeRemaining
    
    try {
        # Clean temporary files
        if ($CleanTempFiles -or $CleanupMode -in @('Standard', 'Aggressive')) {
            Remove-TemporaryFiles
        }
        
        # Clean Windows Update files
        if ($CleanWindowsUpdate -or $CleanupMode -eq 'Aggressive') {
            Remove-WindowsUpdateFiles
        }
        
        # Empty Recycle Bin
        if ($EmptyRecycleBin -or $CleanupMode -in @('Standard', 'Aggressive')) {
            Clear-RecycleBinAll
        }
        
        # Additional aggressive cleanup
        if ($CleanupMode -eq 'Aggressive') {
            Remove-WindowsLogs
            Remove-DownloadedUpdates
        }
        
        # Calculate space reclaimed
        $spaceAfterCleanup = (Get-Volume -DriveLetter C).SizeRemaining
        $spaceReclaimed = $spaceAfterCleanup - $spaceBeforeCleanup
        $script:SpaceReclaimed = $spaceReclaimed
        
        if ($spaceReclaimed -gt 0) {
            Write-LogMessage "  ✓ Space reclaimed: $(Format-ByteSize -Bytes $spaceReclaimed)" -Level Success
        }
        
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error during cleanup: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Remove-TemporaryFiles {
    Write-LogMessage "  Cleaning temporary files..." -Level Info
    
    $tempPaths = @(
        "$env:TEMP\*"
        "$env:WINDIR\Temp\*"
        "$env:LOCALAPPDATA\Temp\*"
    )
    
    $filesRemoved = 0
    
    foreach ($path in $tempPaths) {
        try {
            $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $filesRemoved += $items.Count
            $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Silently continue on errors (files in use, etc.)
        }
    }
    
    Write-LogMessage "    ✓ Removed $filesRemoved temporary files" -Level Success
}

function Remove-WindowsUpdateFiles {
    Write-LogMessage "  Cleaning Windows Update files..." -Level Info
    
    try {
        # Use DISM to clean up
        $dismResult = & DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "    ✓ Windows Update cleanup completed" -Level Success
        }
        else {
            Write-LogMessage "    ⚠ DISM cleanup returned code: $LASTEXITCODE" -Level Warning
        }
    }
    catch {
        Write-LogMessage "    ✗ Error cleaning Windows Update files: $($_.Exception.Message)" -Level Error
    }
}

function Clear-RecycleBinAll {
    Write-LogMessage "  Emptying Recycle Bin..." -Level Info
    
    try {
        # Clear recycle bin for all drives
        $recycleBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
        $recycleBin.Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
        
        Write-LogMessage "    ✓ Recycle Bin emptied" -Level Success
    }
    catch {
        Write-LogMessage "    ⚠ Could not empty Recycle Bin: $($_.Exception.Message)" -Level Warning
    }
}

function Remove-WindowsLogs {
    Write-LogMessage "  Cleaning Windows logs..." -Level Info
    
    $logPaths = @(
        "$env:WINDIR\Logs\*"
        "$env:WINDIR\Panther\*"
    )
    
    foreach ($path in $logPaths) {
        try {
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Silently continue
        }
    }
    
    Write-LogMessage "    ✓ Old Windows logs removed" -Level Success
}

function Remove-DownloadedUpdates {
    Write-LogMessage "  Cleaning downloaded updates..." -Level Info
    
    try {
        $updatePath = "$env:WINDIR\SoftwareDistribution\Download\*"
        Get-ChildItem -Path $updatePath -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "    ✓ Downloaded updates removed" -Level Success
    }
    catch {
        Write-LogMessage "    ⚠ Could not remove downloaded updates: $($_.Exception.Message)" -Level Warning
    }
}

#endregion

#region Reporting

function Get-StorageReport {
    Write-LogMessage "Generating storage report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "storage-optimization-$timestamp.txt"
        $report = @()
        
        $report += "Storage Optimization Report"
        $report += "=" * 80
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # Session statistics
        $report += "Session Summary:"
        $report += "  Volumes Optimized: $script:VolumesOptimized"
        $report += "  Space Reclaimed: $(Format-ByteSize -Bytes $script:SpaceReclaimed)"
        $report += "  Optimizations Failed: $script:OptimizationsFailed"
        $report += ""
        
        # Volume status
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -ne $null } | Sort-Object DriveLetter
        
        $report += "Volume Status:"
        $report += "-" * 80
        
        foreach ($volume in $volumes) {
            $mediaType = Get-DriveType -Volume $volume
            $size = Format-ByteSize -Bytes $volume.Size
            $free = Format-ByteSize -Bytes $volume.SizeRemaining
            $percentFree = [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1)
            
            $report += ""
            $report += "Drive $($volume.DriveLetter): ($($volume.FileSystemLabel))"
            $report += "  File System: $($volume.FileSystem)"
            $report += "  Media Type: $mediaType"
            $report += "  Total Size: $size"
            $report += "  Free Space: $free ($percentFree%)"
            $report += "  Health: $($volume.HealthStatus)"
        }
        
        # Physical disks
        $report += ""
        $report += "Physical Disks:"
        $report += "-" * 80
        
        $disks = Get-PhysicalDisk
        foreach ($disk in $disks) {
            $size = Format-ByteSize -Bytes $disk.Size
            $report += ""
            $report += "Disk $($disk.DeviceId): $($disk.FriendlyName)"
            $report += "  Media Type: $($disk.MediaType)"
            $report += "  Size: $size"
            $report += "  Health: $($disk.HealthStatus)"
            $report += "  Bus Type: $($disk.BusType)"
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Storage report saved to: $reportFile" -Level Success
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
    Write-LogMessage "Storage Optimization" -Level Info
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
    
    # Configuration summary
    Write-LogMessage "Configuration:" -Level Info
    Write-LogMessage "  Cleanup Mode: $CleanupMode" -Level Info
    Write-LogMessage "  Enable TRIM: $EnableTRIM" -Level Info
    Write-LogMessage "  Defragment HDD: $DefragmentHDD" -Level Info
    Write-LogMessage "  Analyze Only: $AnalyzeOnly" -Level Info
    Write-LogMessage "" -Level Info
    
    # Discover volumes
    $volumes = Get-VolumesToOptimize
    
    if (-not $volumes) {
        Write-LogMessage "No volumes to optimize" -Level Error
        exit 1
    }
    
    Write-LogMessage "" -Level Info
    
    # Optimize each volume
    foreach ($volume in $volumes) {
        Write-LogMessage "========== Processing: $($volume.DriveLetter): ==========" -Level Info
        
        $mediaType = Get-DriveType -Volume $volume
        Optimize-VolumeStorage -Volume $volume -MediaType $mediaType
        
        Write-LogMessage "" -Level Info
    }
    
    # Perform disk cleanup
    if (-not $AnalyzeOnly) {
        Write-LogMessage "========== Disk Cleanup ==========" -Level Info
        Invoke-DiskCleanup
        Write-LogMessage "" -Level Info
    }
    
    # Generate report
    Get-StorageReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Storage Optimization Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Volumes Optimized: $script:VolumesOptimized" -Level Info
    Write-LogMessage "Space Reclaimed: $(Format-ByteSize -Bytes $script:SpaceReclaimed)" -Level Info
    Write-LogMessage "Optimizations Failed: $script:OptimizationsFailed" -Level Info
    Write-LogMessage "Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:OptimizationsFailed -eq 0) {
        Write-LogMessage "Storage optimization completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Optimization completed with $script:OptimizationsFailed failures" -Level Warning
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
