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

$script:Component = 'Storage'

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
} catch { Write-Host ("[{0}] [WARN] [Storage] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

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
    Write-Log "Discovering volumes..."    
    try {
        if ($DriveLetter) {
            $volumes = @()
            foreach ($letter in $DriveLetter) {
                $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
                if ($vol) {
                    $volumes += $vol
                }
                else {
                    Write-Log "  [WARN] Drive $letter not found" -Level WARN
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
            Write-Log "No volumes found to optimize" -Level WARN
            return $null
        }
        
        Write-Log "Found $($volumes.Count) volume(s) to optimize:"        
        foreach ($volume in $volumes) {
            $size = Format-ByteSize -Bytes $volume.Size
            $free = Format-ByteSize -Bytes $volume.SizeRemaining
            $percentFree = [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1)
            
            Write-Log "  $($volume.DriveLetter): $($volume.FileSystemLabel) - $size total, $free free ($percentFree%)"        }
        
        return $volumes
    }
    catch {
        Write-Log "Error discovering volumes: $($_.Exception.Message)" -Level ERROR
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
    
    Write-Log "Analyzing volume $($Volume.DriveLetter)..."    
    try {
        $analysis = Optimize-Volume -DriveLetter $Volume.DriveLetter -Analyze -ErrorAction Stop
        
        Write-Log "  Analysis results:"        Write-Log "    Fragmented: $($analysis.FragmentedPercentage)%"        Write-Log "    Slab Consolidated: $($analysis.SlabConsolidated)"        
        return $analysis
    }
    catch {
        Write-Log "  [WARN] Analysis not available: $($_.Exception.Message)" -Level WARN
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
    
    Write-Log "Optimizing volume $($Volume.DriveLetter)..."    
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
        
        Write-Log "  Media Type: $MediaType"        Write-Log "  Optimization Type: $optimizationType"        
        # Perform optimization
        switch ($optimizationType) {
            'ReTrim' {
                if ($EnableTRIM) {
                    Write-Log "  Executing TRIM operation..."                    Optimize-Volume -DriveLetter $Volume.DriveLetter -ReTrim -ErrorAction Stop
                    Write-Log "  [OK] TRIM completed" -Level INFO
                }
                else {
                    Write-Log "  [WARN] TRIM optimization skipped (use -EnableTRIM to enable)" -Level WARN
                }
            }
            'Defrag' {
                Write-Log "  Defragmenting volume..."                Optimize-Volume -DriveLetter $Volume.DriveLetter -Defrag -ErrorAction Stop
                Write-Log "  [OK] Defragmentation completed" -Level INFO
            }
            'Analyze' {
                Get-VolumeAnalysis -Volume $Volume | Out-Null
            }
        }
        
        $script:VolumesOptimized++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error optimizing volume: $($_.Exception.Message)" -Level ERROR
        $script:OptimizationsFailed++
        return $false
    }
}

#endregion

#region Disk Cleanup

function Invoke-DiskCleanup {
    Write-Log "Performing disk cleanup ($CleanupMode mode)..."    
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
            Write-Log "  [OK] Space reclaimed: $(Format-ByteSize -Bytes $spaceReclaimed)" -Level INFO
        }
        
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error during cleanup: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Remove-TemporaryFiles {
    Write-Log "  Cleaning temporary files..."    
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
    
    Write-Log "    [OK] Removed $filesRemoved temporary files" -Level INFO
}

function Remove-WindowsUpdateFiles {
    Write-Log "  Cleaning Windows Update files..."    
    try {
        # Use DISM to clean up
        $dismResult = & DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "    [OK] Windows Update cleanup completed" -Level INFO
        }
        else {
            Write-Log "    [WARN] DISM cleanup returned code: $LASTEXITCODE" -Level WARN
        }
    }
    catch {
        Write-Log "    [FAIL] Error cleaning Windows Update files: $($_.Exception.Message)" -Level ERROR
    }
}

function Clear-RecycleBinAll {
    Write-Log "  Emptying Recycle Bin..."    
    try {
        # Clear recycle bin for all drives
        $recycleBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
        $recycleBin.Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
        
        Write-Log "    [OK] Recycle Bin emptied" -Level INFO
    }
    catch {
        Write-Log "    [WARN] Could not empty Recycle Bin: $($_.Exception.Message)" -Level WARN
    }
}

function Remove-WindowsLogs {
    Write-Log "  Cleaning Windows logs..."    
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
    
    Write-Log "    [OK] Old Windows logs removed" -Level INFO
}

function Remove-DownloadedUpdates {
    Write-Log "  Cleaning downloaded updates..."    
    try {
        $updatePath = "$env:WINDIR\SoftwareDistribution\Download\*"
        Get-ChildItem -Path $updatePath -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Log "    [OK] Downloaded updates removed" -Level INFO
    }
    catch {
        Write-Log "    [WARN] Could not remove downloaded updates: $($_.Exception.Message)" -Level WARN
    }
}

#endregion

#region Reporting

function Get-StorageReport {
    Write-Log "Generating storage report..."    
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
        
        Write-Log "Storage report saved to: $reportFile" -Level INFO
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
    $scriptStartTime = Get-Date
    
    Write-Log '===== Optimize_Storage starting ====='
    Write-Log "Log file: $LogFile"

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Configuration summary
    Write-Log "Configuration:"    Write-Log "  Cleanup Mode: $CleanupMode"    Write-Log "  Enable TRIM: $EnableTRIM"    Write-Log "  Defragment HDD: $DefragmentHDD"    Write-Log "  Analyze Only: $AnalyzeOnly"    Write-Log ""    
    # Discover volumes
    $volumes = Get-VolumesToOptimize
    
    if (-not $volumes) {
        Write-Log "No volumes to optimize" -Level ERROR
        exit 1
    }
        
    # Optimize each volume
    foreach ($volume in $volumes) {
        Write-Log "========== Processing: $($volume.DriveLetter): =========="        
        $mediaType = Get-DriveType -Volume $volume
        Optimize-VolumeStorage -Volume $volume -MediaType $mediaType
            }
    
    # Perform disk cleanup
    if (-not $AnalyzeOnly) {
        Write-Log "========== Disk Cleanup =========="        Invoke-DiskCleanup    }
    
    # Generate report
    Get-StorageReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-Log "Space reclaimed: $(Format-ByteSize -Bytes $script:SpaceReclaimed)"

    if ($script:OptimizationsFailed -eq 0) {
        Write-Log "===== Optimize_Storage complete in $([int]$duration.TotalSeconds)s applied=$script:VolumesOptimized failed=$script:OptimizationsFailed ====="
        exit 0
    }
    else {
        Write-Log "Storage optimization completed with $script:OptimizationsFailed failure(s)." -Level ERROR
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
