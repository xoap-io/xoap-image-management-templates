<#
.SYNOPSIS
    Configure Event Log Sizes and Retention for Windows Server

.DESCRIPTION
    Configures Windows Event Log sizes, maximum file sizes, retention policies,
    and overflow behavior. Optimized for Windows Server 2025 monitoring and compliance.

.NOTES
    File Name      : windows-server-Configure_Event_Log_Sizes.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Event_Log_Sizes
    Configures event logs with default sizes
    
.EXAMPLE
    .\windows-server-Configure_Event_Log_Sizes -ApplicationLogSize 512MB -SystemLogSize 512MB -SecurityLogSize 1GB
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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [EventLog] $Message"
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
            Write-Log "  Log not found: $LogName" -Level WARN
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
        
        Write-Log "  [OK] $LogName : $originalSizeMB MB -> $sizeMB MB" -Level INFO
        
        $script:LogsConfigured++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Failed to configure $LogName : $($_.Exception.Message)" -Level WARN
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
    Write-Log "Configuring core event logs..." -Level INFO
    
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
    
    Write-Log "Core event logs configured" -Level INFO
}

function Set-AdditionalEventLogs {
    Write-Log "Configuring additional event logs..." -Level INFO
    
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
    
    Write-Log "Additional event logs configured" -Level INFO
}

function Set-SecurityAuditLogs {
    Write-Log "Configuring security and audit logs..." -Level INFO
    
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
    
    Write-Log "Security and audit logs configured" -Level INFO
}

function Enable-ImportantLogs {
    Write-Log "Enabling important event logs..." -Level INFO
    
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
                Write-Log "  [OK] Enabled: $logName" -Level INFO
                $enabled++
            }
        }
        catch {
            Write-Log "  [FAIL] Could not enable: $logName" -Level WARN
        }
    }
    
    Write-Log "Enabled $enabled important event logs" -Level INFO
}

function Get-EventLogReport {
    Write-Log "Generating event log configuration report..." -Level INFO
    
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
        
        Write-Log "Event log report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Clear-OldEventLogs {
    param([switch]$ClearAll)
    
    if (-not $ClearAll) {
        return
    }
    
    Write-Log "Clearing old event logs (CAUTION: This will delete log data)..." -Level WARN
    
    $logsToClear = @('Application', 'System', 'Setup')
    
    foreach ($logName in $logsToClear) {
        try {
            # Export before clearing (backup)
            $backupPath = Join-Path $LogDir "backup-$logName-$timestamp.evtx"
            wevtutil.exe epl $logName $backupPath 2>&1 | Out-Null
            
            # Clear the log
            wevtutil.exe cl $logName 2>&1 | Out-Null
            
            Write-Log "  [OK] Cleared and backed up: $logName" -Level INFO
        }
        catch {
            Write-Log "  [FAIL] Failed to clear: $logName" -Level WARN
        }
    }
}

function Test-EventLogConfiguration {
    Write-Log "Verifying event log configuration..." -Level INFO
    
    try {
        $coreLogs = @('Application', 'System', 'Security')
        $allConfigured = $true
        
        foreach ($logName in $coreLogs) {
            $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
            
            if ($log.IsEnabled) {
                Write-Log "  [OK] $logName is enabled ($([math]::Round($log.MaximumSizeInBytes / 1MB, 2)) MB)" -Level INFO
            }
            else {
                Write-Log "  [FAIL] $logName is disabled" -Level WARN
                $allConfigured = $false
            }
        }
        
        return $allConfigured
    }
    catch {
        Write-Log "Error during verification: $($_.Exception.Message)" -Level ERROR
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

    Write-Log "===== Configure_Event_Log_Sizes starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Display configuration
    Write-Log "Configuration:" -Level INFO
    Write-Log "  Application Log: $([math]::Round($ApplicationLogSize / 1MB, 2)) MB" -Level INFO
    Write-Log "  System Log: $([math]::Round($SystemLogSize / 1MB, 2)) MB" -Level INFO
    Write-Log "  Security Log: $([math]::Round($SecurityLogSize / 1MB, 2)) MB" -Level INFO
    Write-Log "  Retention Days: $RetentionDays" -Level INFO
    Write-Log "" -Level INFO
    
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
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    if ($script:LogsFailed -ne 0) {
        Write-Log "Configuration completed with $script:LogsFailed warnings" -Level WARN
    }
    Write-Log "===== Configure_Event_Log_Sizes complete in $([int]$duration)s; applied=$($script:LogsConfigured) failed=$($script:LogsFailed) ====="
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
