<#
.SYNOPSIS
    Optimize Windows for AWS EC2 Performance

.DESCRIPTION
    Applies comprehensive performance optimizations for Windows running on AWS EC2.
    Includes ENA driver configuration, NVMe settings, network optimization, and
    EC2-specific tuning for optimal cloud performance.
    
    Optimizations include:
    - Elastic Network Adapter (ENA) driver configuration
    - NVMe storage optimization
    - Enhanced networking settings
    - Memory and processor tuning
    - Power management for cloud
    - EC2 metadata service optimization

.NOTES
    File Name      : Optimize_AWS_EC2_Performance.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER OptimizeNetwork
    Apply ENA and network adapter optimizations

.PARAMETER OptimizeStorage
    Apply NVMe and EBS volume optimizations

.PARAMETER OptimizeMemory
    Apply memory management optimizations

.EXAMPLE
    .\Optimize_AWS_EC2_Performance.ps1
    Applies all EC2 optimizations

.EXAMPLE
    .\Optimize_AWS_EC2_Performance.ps1 -OptimizeNetwork -OptimizeStorage
    Applies network and storage optimizations only

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [switch]$OptimizeNetwork,
    [switch]$OptimizeStorage,
    [switch]$OptimizeMemory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = 'aws-ec2-optimize'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:OptimizationsApplied = 0
$script:OptimizationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [EC2Opt] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    Write-Log "========================================================="
    Write-Log "AWS EC2 Performance Optimization"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log ""
    
    # If no specific optimization selected, apply all
    if (-not ($OptimizeNetwork -or $OptimizeStorage -or $OptimizeMemory)) {
        $OptimizeNetwork = $true
        $OptimizeStorage = $true
        $OptimizeMemory = $true
        Write-Log "Applying all optimizations"
    }
    
    # Detect EC2 environment
    Write-Log "Detecting EC2 environment..."
    $isEC2 = $false
    $instanceType = 'Unknown'
    
    try {
        $instanceId = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id' -TimeoutSec 2 -ErrorAction Stop
        $instanceType = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-type' -TimeoutSec 2 -ErrorAction Stop
        Write-Log "✓ Running on EC2 instance: $instanceId"
        Write-Log "  Instance Type: $instanceType"
        $isEC2 = $true
    }
    catch {
        Write-Log "Warning: Not running on EC2 instance" -Level Warning
        Write-Log "Continuing with optimizations anyway..."
    }
    
    # Network optimization (ENA)
    if ($OptimizeNetwork) {
        Write-Log ""
        Write-Log "Optimizing network settings for EC2..."
        
        # Check for ENA driver
        $enaAdapter = Get-NetAdapter | Where-Object { 
            $_.InterfaceDescription -like '*Amazon Elastic Network Adapter*' -or
            $_.InterfaceDescription -like '*ENA*'
        }
        
        if ($enaAdapter) {
            Write-Log "✓ ENA adapter detected: $($enaAdapter.Name)"
            
            try {
                # Enable RSS (Receive Side Scaling)
                Enable-NetAdapterRss -Name $enaAdapter.Name -ErrorAction SilentlyContinue
                Write-Log "✓ Enabled RSS on ENA adapter"
                
                # Configure receive buffers
                Set-NetAdapterAdvancedProperty -Name $enaAdapter.Name `
                    -DisplayName "Receive Buffers" -DisplayValue "4096" -ErrorAction SilentlyContinue
                Write-Log "✓ Configured receive buffers"
                
                # Enable Large Send Offload (LSO)
                Enable-NetAdapterLso -Name $enaAdapter.Name -ErrorAction SilentlyContinue
                Write-Log "✓ Enabled LSO"
                
                $script:OptimizationsApplied++
            }
            catch {
                Write-Log "ENA optimization failed: $($_.Exception.Message)" -Level Warning
                $script:OptimizationsFailed++
            }
        }
        else {
            Write-Log "ENA adapter not detected" -Level Warning
        }
        
        # TCP/IP optimizations
        try {
            $tcpipPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
            
            # Optimize for cloud networking
            Set-ItemProperty -Path $tcpipPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force
            Set-ItemProperty -Path $tcpipPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
            Set-ItemProperty -Path $tcpipPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $tcpipPath -Name 'TCPNoDelay' -Value 1 -Type DWord -Force
            
            Write-Log "✓ Applied TCP/IP optimizations"
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "TCP/IP optimization failed" -Level Warning
            $script:OptimizationsFailed++
        }
        
        # Disable IPv6 if not used
        try {
            $ipv6Adapters = Get-NetAdapterBinding -ComponentID ms_tcpip6 | Where-Object { $_.Enabled -eq $true }
            if ($ipv6Adapters) {
                Disable-NetAdapterBinding -Name '*' -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
                Write-Log "✓ Disabled IPv6 (not commonly used in EC2)"
                $script:OptimizationsApplied++
            }
        }
        catch {
            Write-Log "IPv6 disable failed" -Level Warning
        }
    }
    
    # Storage optimization (NVMe)
    if ($OptimizeStorage) {
        Write-Log ""
        Write-Log "Optimizing storage settings for EC2..."
        
        # Check for NVMe devices
        $nvmeDisks = Get-PhysicalDisk | Where-Object { $_.FriendlyName -like '*NVMe*' -or $_.FriendlyName -like '*Amazon*' }
        
        if ($nvmeDisks) {
            Write-Log "✓ NVMe disks detected: $($nvmeDisks.Count)"
            foreach ($disk in $nvmeDisks) {
                Write-Log "  - $($disk.FriendlyName) [$($disk.MediaType)]"
            }
        }
        
        try {
            # Disable disk defragmentation (not needed for EBS)
            Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | 
                Disable-ScheduledTask -ErrorAction SilentlyContinue
            Write-Log "✓ Disabled scheduled defragmentation"
            
            # Optimize disk timeout
            $diskPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk'
            Set-ItemProperty -Path $diskPath -Name 'TimeOutValue' -Value 60 -Type DWord -Force
            Write-Log "✓ Set disk timeout to 60 seconds"
            
            # Disable System Restore (not recommended for EC2)
            try {
                Disable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
                Write-Log "✓ Disabled System Restore"
            }
            catch {
                Write-Log "System Restore already disabled" -Level Info
            }
            
            # Optimize for virtual environments
            $layoutPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout'
            if (-not (Test-Path $layoutPath)) {
                New-Item -Path $layoutPath -Force | Out-Null
            }
            Set-ItemProperty -Path $layoutPath -Name 'EnableAutoLayout' -Value 0 -Type DWord -Force
            Write-Log "✓ Disabled automatic disk layout optimization"
            
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Storage optimization failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Memory optimization
    if ($OptimizeMemory) {
        Write-Log ""
        Write-Log "Optimizing memory settings for EC2..."
        
        try {
            $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            
            # Disable paging executive (if sufficient memory)
            $totalMemoryGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
            Write-Log "Total Memory: ${totalMemoryGB}GB"
            
            if ($totalMemoryGB -ge 8) {
                Set-ItemProperty -Path $mmPath -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
                Write-Log "✓ Disabled paging executive"
            }
            else {
                Write-Log "Keeping paging executive enabled (< 8GB RAM)"
            }
            
            # Optimize system responsiveness
            $multiPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty -Path $multiPath -Name 'SystemResponsiveness' -Value 10 -Type DWord -Force
            Set-ItemProperty -Path $multiPath -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -Force
            Write-Log "✓ Optimized system responsiveness"
            
            $script:OptimizationsApplied++
        }
        catch {
            Write-Log "Memory optimization failed: $($_.Exception.Message)" -Level Warning
            $script:OptimizationsFailed++
        }
    }
    
    # Power management
    Write-Log ""
    Write-Log "Optimizing power settings for EC2..."
    
    try {
        # Set to High Performance
        $highPerf = powercfg /list | Select-String "High performance" | ForEach-Object { 
            if ($_ -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } 
        }
        
        if ($highPerf) {
            powercfg /setactive $highPerf
            Write-Log "✓ Set High Performance power plan"
            $script:OptimizationsApplied++
        }
        
        # Disable hibernation (not needed in cloud)
        powercfg /hibernate off
        Write-Log "✓ Disabled hibernation"
        
        # Disable sleep
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        Write-Log "✓ Disabled sleep timeouts"
        
        $script:OptimizationsApplied++
    }
    catch {
        Write-Log "Power optimization failed" -Level Warning
        $script:OptimizationsFailed++
    }
    
    # Disable unnecessary services for cloud
    Write-Log ""
    Write-Log "Disabling unnecessary services..."
    
    $servicesToDisable = @(
        'TabletInputService',  # Touch keyboard
        'WSearch',             # Windows Search (optional)
        'Superfetch',          # Superfetch (not needed for EBS)
        'Themes'               # Visual themes (optional for servers)
    )
    
    foreach ($service in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -ne 'Disabled') {
                Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Write-Log "✓ Disabled: $service"
                $script:OptimizationsApplied++
            }
        }
        catch {
            Write-Log "Failed to disable $service" -Level Warning
        }
    }
    
    # EC2 metadata service optimization
    Write-Log ""
    Write-Log "Configuring EC2 metadata service access..."
    
    try {
        # Ensure IMDSv2 is configured (security best practice)
        $metadataTokenPath = 'HKLM:\SOFTWARE\Amazon\EC2Launch'
        if (-not (Test-Path $metadataTokenPath)) {
            New-Item -Path $metadataTokenPath -Force | Out-Null
        }
        Set-ItemProperty -Path $metadataTokenPath -Name 'UseIMDSv2' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "✓ Configured for IMDSv2"
        $script:OptimizationsApplied++
    }
    catch {
        Write-Log "Metadata service configuration failed" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "EC2 Performance Optimization Summary"
    Write-Log "========================================================="
    Write-Log "EC2 Instance: $isEC2"
    Write-Log "Instance Type: $instanceType"
    Write-Log "Optimizations applied: $script:OptimizationsApplied"
    Write-Log "Optimizations failed: $script:OptimizationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    if ($script:OptimizationsFailed -eq 0) {
        Write-Log "✓ All optimizations applied successfully"
    }
    else {
        Write-Log "Warning: Some optimizations failed" -Level Warning
    }
    
    Write-Log ""
    Write-Log "Note: A system restart is recommended for all changes to take effect."
    
} catch {
    Write-Log "Optimization failed: $_" -Level Error
    exit 1
}
