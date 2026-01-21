<#
.SYNOPSIS
    Configure Event Log Sizes and Retention for Windows 10/11

.DESCRIPTION
    Configures Windows Event Log sizes, maximum file sizes, retention policies,
    and overflow behavior. Optimized for Windows 10/11 monitoring and compliance.

.NOTES
    File Name      : windows11-Configure_Event_Log_Sizes.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Configure_Event_Log_Sizes
    Configures event logs with default sizes
    
.EXAMPLE
    .\windows11-Configure_Event_Log_Sizes -ApplicationLogSize 512MB -SystemLogSize 512MB -SecurityLogSize 1GB
    Configures event logs with custom sizes
    
.PARAMETER ApplicationLogSize
    Application log maximum size (default: 256MB)
    
.PARAMETER SystemLogSize
    System log maximum size (default: 256MB)
    
.PARAMETER SecurityLogSize
    Security log maximum size (default: 512MB)
    
.PARAMETER SetupLogSize
    Setup log maximum size (default: 128MB)
    
.PARAMETER ForwardedEventsLogSize
    Forwarded Events log size (default: 256MB)
    
.PARAMETER RetentionDays
    Log retention in days (0 = overwrite as needed)
    
.PARAMETER OverwriteOlder
    Overwrite events older than X days (default: 0 = as needed)
    
.PARAMETER EnableAllLogs
    Enable all available event logs
#>

[CmdletBinding()]
param(
    [long]$ApplicationLogSize = 256MB,
    [long]$SystemLogSize = 256MB,
    [long]$SecurityLogSize = 512MB,
    [long]$SetupLogSize = 128MB,
    [long]$ForwardedEventsLogSize = 256MB,
    [int]$RetentionDays = 0,
    [int]$OverwriteOlder = 0,
    [switch]$EnableAllLogs
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
$script:LogsConfigured = 0
$script:LogsFailed = 0

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

function Set-EventLogConfiguration {
    param(
        [string]$LogName,
        [long]$MaxSize,
        [string]$OverflowAction = 'OverwriteAsNeeded',
        [int]$RetentionDays = 0
    )
    
    try {
        # Get log configuration
        $log = Get-WinEvent -ListLog $LogName -ErrorAction Stop
        
        if (-not $log) {
            Write-LogMessage "  Log not found: $LogName" -Level Warning
            return $false
        }
        
        # Store original values
        $originalSize = $log.MaximumSizeInBytes
        $originalEnabled = $log.IsEnabled
        
        # Configure log
        $log.MaximumSizeInBytes = $MaxSize
        
        # Set retention policy
        if ($RetentionDays -gt 0) {
            $log.LogMode = 'Retain'
            # Note: AutoBackup requires additional configuration
        }
        else {
            $log.LogMode = 'Circular'  # Overwrite as needed
        }
        
        # Enable log if disabled
        if (-not $log.IsEnabled) {
            $log.IsEnabled = $true
        }
        
        # Save configuration
        $log.SaveChanges()
        
        $sizeMB = [math]::Round($MaxSize / 1MB, 2)
        $originalSizeMB = [math]::Round($originalSize / 1MB, 2)
        
        Write-LogMessage "  ✓ $LogName : $originalSizeMB MB → $sizeMB MB" -Level Info
        
        $script:LogsConfigured++
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Failed to configure $LogName : $($_.Exception.Message)" -Level Warning
        $script:LogsFailed++
        return $false
    }
}

function Get-EventLogInfo {
    param([string]$LogName)
    
    try {
        $log = Get-WinEvent -ListLog $LogName -ErrorAction Stop
        
        $info = [PSCustomObject]@{
            LogName           = $log.LogName
            Enabled           = $log.IsEnabled
            MaxSizeMB         = [math]::Round($log.MaximumSizeInBytes / 1MB, 2)
            CurrentSizeMB     = [math]::Round($log.FileSize / 1MB, 2)
            RecordCount       = $log.RecordCount
            LogMode           = $log.LogMode
            LogFilePath       = $log.LogFilePath
        }
        
        return $info
    }
    catch {
        return $null
    }
}

#endregion

#region Main Configuration

function Set-CoreEventLogs {
    Write-LogMessage "Configuring core event logs..." -Level Info
    
    # Application Log
    Set-EventLogConfiguration -LogName 'Application' -MaxSize $ApplicationLogSize -RetentionDays $RetentionDays
    
    # System Log
    Set-EventLogConfiguration -LogName 'System' -MaxSize $SystemLogSize -RetentionDays $RetentionDays
    
    # Security Log
    Set-EventLogConfiguration -LogName 'Security' -MaxSize $SecurityLogSize -RetentionDays $RetentionDays
    
    # Setup Log
    Set-EventLogConfiguration -LogName 'Setup' -MaxSize $SetupLogSize -RetentionDays $RetentionDays
    
    # Forwarded Events
    Set-EventLogConfiguration -LogName 'ForwardedEvents' -MaxSize $ForwardedEventsLogSize -RetentionDays $RetentionDays
    
    Write-LogMessage "Core event logs configured" -Level Success
}

function Set-AdditionalEventLogs {
    Write-LogMessage "Configuring additional event logs..." -Level Info
    
    $additionalLogs = @{
        'Microsoft-Windows-PowerShell/Operational' = 128MB
        'Windows PowerShell' = 64MB
        'Microsoft-Windows-TaskScheduler/Operational' = 64MB
        'Microsoft-Windows-GroupPolicy/Operational' = 64MB
        'Microsoft-Windows-WinRM/Operational' = 64MB
        'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' = 64MB
        'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' = 64MB
        'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational' = 64MB
        'Microsoft-Windows-SMBServer/Security' = 128MB
        'Microsoft-Windows-SMBServer/Operational' = 64MB
        'Microsoft-Windows-SMBClient/Security' = 64MB
        'Microsoft-Windows-NTLM/Operational' = 64MB
        'Microsoft-Windows-Kerberos/Operational' = 64MB
        'Microsoft-Windows-DNS-Client/Operational' = 64MB
    }
    
    foreach ($logName in $additionalLogs.Keys) {
        Set-EventLogConfiguration -LogName $logName -MaxSize $additionalLogs[$logName] -RetentionDays $RetentionDays
    }
    
    Write-LogMessage "Additional event logs configured" -Level Success
}

function Set-SecurityAuditLogs {
    Write-LogMessage "Configuring security and audit logs..." -Level Info
    
    $securityLogs = @{
        'Microsoft-Windows-Security-Auditing' = 256MB
        'Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController' = 64MB
        'Microsoft-Windows-Authentication/ProtectedUser-Client' = 64MB
        'Microsoft-Windows-Authentication/ProtectedUserFailures-DomainController' = 64MB
        'Microsoft-Windows-Eventlog-ForwardingPlugin/Operational' = 32MB
    }
    
    foreach ($logName in $securityLogs.Keys) {
        Set-EventLogConfiguration -LogName $logName -MaxSize $securityLogs[$logName] -RetentionDays $RetentionDays
    }
    
    Write-LogMessage "Security and audit logs configured" -Level Success
}

function Enable-ImportantLogs {
    Write-LogMessage "Enabling important event logs..." -Level Info
    
    $logsToEnable = @(
        'Microsoft-Windows-PowerShell/Operational',
        'Microsoft-Windows-TaskScheduler/Operational',
        'Microsoft-Windows-GroupPolicy/Operational',
        'Microsoft-Windows-WinRM/Operational',
        'Microsoft-Windows-SMBServer/Security',
        'Microsoft-Windows-NTLM/Operational',
        'Microsoft-Windows-Kerberos/Operational'
    )
    
    $enabled = 0
    foreach ($logName in $logsToEnable) {
        try {
            $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
            if (-not $log.IsEnabled) {
                $log.IsEnabled = $true
                $log.SaveChanges()
                Write-LogMessage "  ✓ Enabled: $logName" -Level Info
                $enabled++
            }
        }
        catch {
            Write-LogMessage "  ✗ Could not enable: $logName" -Level Warning
        }
    }
    
    Write-LogMessage "Enabled $enabled important event logs" -Level Success
}

function Get-EventLogReport {
    Write-LogMessage "Generating event log configuration report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "eventlog-config-$timestamp.txt"
        $report = @()
        
        $report += "Event Log Configuration Report"
        $report += "=" * 80
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += ""
        
        # Core logs
        $report += "Core Event Logs:"
        $report += "-" * 80
        
        $coreLogs = @('Application', 'System', 'Security', 'Setup', 'ForwardedEvents')
        
        foreach ($logName in $coreLogs) {
            $info = Get-EventLogInfo -LogName $logName
            if ($info) {
                $report += "  Log Name: $($info.LogName)"
                $report += "    Enabled: $($info.Enabled)"
                $report += "    Max Size: $($info.MaxSizeMB) MB"
                $report += "    Current Size: $($info.CurrentSizeMB) MB"
                $report += "    Record Count: $($info.RecordCount)"
                $report += "    Log Mode: $($info.LogMode)"
                $report += "    File Path: $($info.LogFilePath)"
                $report += ""
            }
        }
        
        # Additional logs summary
        $report += ""
        $report += "Additional Event Logs Summary:"
        $report += "-" * 80
        
        $additionalLogs = @(
            'Microsoft-Windows-PowerShell/Operational',
            'Microsoft-Windows-TaskScheduler/Operational',
            'Microsoft-Windows-SMBServer/Security',
            'Microsoft-Windows-WinRM/Operational'
        )
        
        foreach ($logName in $additionalLogs) {
            $info = Get-EventLogInfo -LogName $logName
            if ($info) {
                $report += "  $($info.LogName): $($info.MaxSizeMB) MB | Enabled: $($info.Enabled) | Records: $($info.RecordCount)"
            }
        }
        
        $report += ""
        $report += "Total Logs Configured: $script:LogsConfigured"
        $report += "Configuration Failures: $script:LogsFailed"
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Event log report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Clear-OldEventLogs {
    param([switch]$ClearAll)
    
    if (-not $ClearAll) {
        return
    }
    
    Write-LogMessage "Clearing old event logs (CAUTION: This will delete log data)..." -Level Warning
    
    $logsToClear = @('Application', 'System', 'Setup')
    
    foreach ($logName in $logsToClear) {
        try {
            # Export before clearing (backup)
            $backupPath = Join-Path $LogDir "backup-$logName-$timestamp.evtx"
            wevtutil.exe epl $logName $backupPath 2>&1 | Out-Null
            
            # Clear the log
            wevtutil.exe cl $logName 2>&1 | Out-Null
            
            Write-LogMessage "  ✓ Cleared and backed up: $logName" -Level Info
        }
        catch {
            Write-LogMessage "  ✗ Failed to clear: $logName" -Level Warning
        }
    }
}

function Test-EventLogConfiguration {
    Write-LogMessage "Verifying event log configuration..." -Level Info
    
    try {
        $coreLogs = @('Application', 'System', 'Security')
        $allConfigured = $true
        
        foreach ($logName in $coreLogs) {
            $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
            
            if ($log.IsEnabled) {
                Write-LogMessage "  ✓ $logName is enabled ($([math]::Round($log.MaximumSizeInBytes / 1MB, 2)) MB)" -Level Info
            }
            else {
                Write-LogMessage "  ✗ $logName is disabled" -Level Warning
                $allConfigured = $false
            }
        }
        
        return $allConfigured
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Event Log Configuration" -Level Info
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
    
    # Display configuration
    Write-LogMessage "Configuration:" -Level Info
    Write-LogMessage "  Application Log: $([math]::Round($ApplicationLogSize / 1MB, 2)) MB" -Level Info
    Write-LogMessage "  System Log: $([math]::Round($SystemLogSize / 1MB, 2)) MB" -Level Info
    Write-LogMessage "  Security Log: $([math]::Round($SecurityLogSize / 1MB, 2)) MB" -Level Info
    Write-LogMessage "  Retention Days: $RetentionDays" -Level Info
    Write-LogMessage "" -Level Info
    
    # Configure event logs
    Set-CoreEventLogs
    Set-AdditionalEventLogs
    Set-SecurityAuditLogs
    
    # Enable important logs if requested
    if ($EnableAllLogs) {
        Enable-ImportantLogs
    }
    
    # Verify configuration
    Test-EventLogConfiguration | Out-Null
    
    # Generate report
    Get-EventLogReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configuration Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Event Logs Configured: $script:LogsConfigured" -Level Info
    Write-LogMessage "Configuration Failures: $script:LogsFailed" -Level Info
    Write-LogMessage "Duration: $($duration.TotalSeconds) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:LogsFailed -eq 0) {
        Write-LogMessage "Event log configuration completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Configuration completed with $script:LogsFailed warnings" -Level Warning
        exit 0
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
