<#
.SYNOPSIS
    Configure Scheduled Tasks for Windows Server

.DESCRIPTION
    Creates, modifies, and manages Windows scheduled tasks for maintenance,
    backups, monitoring, and automation. Optimized for Windows Server 2025
    and Packer workflows.

.NOTES
    File Name      : windows-server-Configure_Scheduled_Tasks.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Scheduled_Tasks.ps1 -CreateMaintenanceTasks
    Creates standard maintenance tasks
    
.EXAMPLE
    .\windows-server-Configure_Scheduled_Tasks.ps1 -CreateTask -TaskName "Backup" -ScriptPath "C:\Scripts\Backup.ps1" -Schedule Daily -Time "02:00"
    Creates a custom backup task
    
.PARAMETER CreateTask
    Create a new scheduled task
    
.PARAMETER RemoveTask
    Remove a scheduled task
    
.PARAMETER TaskName
    Name of the task
    
.PARAMETER ScriptPath
    Path to script or executable
    
.PARAMETER Schedule
    Schedule type: Once, Daily, Weekly, Monthly, AtStartup, AtLogon
    
.PARAMETER Time
    Time to run (HH:mm format)
    
.PARAMETER DayOfWeek
    Day of week for weekly schedules
    
.PARAMETER RunAsSystem
    Run as SYSTEM account
    
.PARAMETER CreateMaintenanceTasks
    Create standard maintenance tasks
    
.PARAMETER ListTasks
    List all scheduled tasks
#>

[CmdletBinding()]
param(
    [switch]$CreateTask,
    [switch]$RemoveTask,
    [string]$TaskName,
    [string]$ScriptPath,
    [string]$Arguments,
    [ValidateSet('Once', 'Daily', 'Weekly', 'Monthly', 'AtStartup', 'AtLogon')]
    [string]$Schedule = 'Daily',
    [string]$Time = '02:00',
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$DayOfWeek = 'Sunday',
    [switch]$RunAsSystem,
    [string]$WorkingDirectory,
    [switch]$CreateMaintenanceTasks,
    [switch]$ListTasks,
    [switch]$Enabled = $true
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
$script:TasksCreated = 0
$script:TasksRemoved = 0
$script:OperationsFailed = 0

#region Helper Functions

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [SchedTasks] $Message"
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region Task Creation

function New-ScheduledTaskEx {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$Execute,
        
        [string]$Args,
        [string]$WorkDir,
        [string]$Description,
        
        [Parameter(Mandatory)]
        [ValidateSet('Once', 'Daily', 'Weekly', 'Monthly', 'AtStartup', 'AtLogon')]
        [string]$ScheduleType,
        
        [string]$ScheduleTime = '02:00',
        [string]$Day = 'Sunday',
        [bool]$SystemAccount = $true,
        [bool]$TaskEnabled = $true
    )
    
    Write-Log "Creating scheduled task: $Name" -Level INFO
    
    try {
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        
        if ($existingTask) {
            Write-Log "  [WARN] Task already exists: $Name" -Level WARN
            Write-Log "  Removing existing task..." -Level INFO
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        }
        
        # Create action
        $actionParams = @{
            Execute = $Execute
        }
        
        if ($Args) {
            $actionParams['Argument'] = $Args
        }
        
        if ($WorkDir) {
            $actionParams['WorkingDirectory'] = $WorkDir
        }
        
        $action = New-ScheduledTaskAction @actionParams
        
        # Create trigger based on schedule type
        $trigger = switch ($ScheduleType) {
            'Once' {
                $triggerTime = [DateTime]::Today.Add([TimeSpan]::Parse($ScheduleTime))
                New-ScheduledTaskTrigger -Once -At $triggerTime
            }
            'Daily' {
                New-ScheduledTaskTrigger -Daily -At $ScheduleTime
            }
            'Weekly' {
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $ScheduleTime
            }
            'Monthly' {
                # Monthly on first day
                $triggerTime = [DateTime]::Today.Add([TimeSpan]::Parse($ScheduleTime))
                New-ScheduledTaskTrigger -Once -At $triggerTime -RepetitionInterval (New-TimeSpan -Days 30)
            }
            'AtStartup' {
                New-ScheduledTaskTrigger -AtStartup
            }
            'AtLogon' {
                New-ScheduledTaskTrigger -AtLogon
            }
        }
        
        # Create principal (user context)
        if ($SystemAccount) {
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        }
        else {
            $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        }
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable:$false `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        
        if (-not $TaskEnabled) {
            $settings.Enabled = $false
        }
        
        # Register task
        $task = Register-ScheduledTask `
            -TaskName $Name `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description $Description `
            -ErrorAction Stop
        
        Write-Log "  [OK] Task created successfully" -Level INFO
        Write-Log "    Name: $Name" -Level INFO
        Write-Log "    Schedule: $ScheduleType" -Level INFO
        Write-Log "    Execute: $Execute" -Level INFO
        
        $script:TasksCreated++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error creating task: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

#endregion

#region Task Removal

function Remove-ScheduledTaskEx {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    Write-Log "Removing scheduled task: $Name" -Level INFO
    
    try {
        $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        
        if (-not $task) {
            Write-Log "  [WARN] Task not found: $Name" -Level WARN
            return $true
        }
        
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        
        Write-Log "  [OK] Task removed successfully" -Level INFO
        $script:TasksRemoved++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error removing task: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

#endregion

#region Maintenance Tasks

function New-MaintenanceTasks {
    Write-Log "Creating maintenance scheduled tasks..." -Level INFO
    Write-Log "" -Level INFO
    
    # 1. Windows Update Check (Daily at 3 AM)
    New-ScheduledTaskEx `
        -Name "XOAP-WindowsUpdateCheck" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot`"" `
        -Description "Check and install Windows Updates" `
        -ScheduleType Daily `
        -ScheduleTime "03:00" `
        -SystemAccount $true
    
    # 2. Disk Cleanup (Weekly on Sunday at 2 AM)
    New-ScheduledTaskEx `
        -Name "XOAP-DiskCleanup" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"C:\xoap-scripts\windows-server-Optimize_Storage.ps1 -CleanupMode Standard`"" `
        -Description "Weekly disk cleanup and optimization" `
        -ScheduleType Weekly `
        -Day "Sunday" `
        -ScheduleTime "02:00" `
        -SystemAccount $true
    
    # 3. Event Log Backup (Daily at 1 AM)
    New-ScheduledTaskEx `
        -Name "XOAP-EventLogBackup" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"wevtutil epl System C:\xoap-logs\EventLog-System-`$(Get-Date -Format 'yyyyMMdd').evtx`"" `
        -Description "Backup System event log daily" `
        -ScheduleType Daily `
        -ScheduleTime "01:00" `
        -SystemAccount $true
    
    # 4. Certificate Validation (Weekly on Monday at 6 AM)
    New-ScheduledTaskEx `
        -Name "XOAP-CertificateValidation" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"C:\xoap-scripts\windows-server-Manage_Certificates.ps1 -ValidateCertificates`"" `
        -Description "Weekly certificate validation and expiration check" `
        -ScheduleType Weekly `
        -Day "Monday" `
        -ScheduleTime "06:00" `
        -SystemAccount $true
    
    # 5. Security Baseline Audit (Weekly on Friday at 7 PM)
    New-ScheduledTaskEx `
        -Name "XOAP-SecurityAudit" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"Get-ComputerInfo | Out-File C:\xoap-logs\SecurityAudit-`$(Get-Date -Format 'yyyyMMdd').txt`"" `
        -Description "Weekly security baseline audit" `
        -ScheduleType Weekly `
        -Day "Friday" `
        -ScheduleTime "19:00" `
        -SystemAccount $true
    
    # 6. Log Cleanup (Daily at 4 AM)
    New-ScheduledTaskEx `
        -Name "XOAP-LogCleanup" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"Get-ChildItem C:\xoap-logs\*.log -Recurse | Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force`"" `
        -Description "Clean up old log files (>30 days)" `
        -ScheduleType Daily `
        -ScheduleTime "04:00" `
        -SystemAccount $true
    
    # 7. Service Health Check (Every 4 hours)
    $trigger = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration ([TimeSpan]::MaxValue)
    New-ScheduledTaskEx `
        -Name "XOAP-ServiceHealthCheck" `
        -Execute "powershell.exe" `
        -Args "-NoProfile -ExecutionPolicy Bypass -Command `"Get-Service | Where-Object { `$_.StartType -eq 'Automatic' -and `$_.Status -ne 'Running' } | Out-File C:\xoap-logs\ServiceHealth-`$(Get-Date -Format 'yyyyMMdd-HHmm').txt`"" `
        -Description "Monitor service health every 4 hours" `
        -ScheduleType Daily `
        -ScheduleTime "00:00" `
        -SystemAccount $true
    
    Write-Log "" -Level INFO
    Write-Log "Maintenance tasks created successfully" -Level INFO
}

#endregion

#region Task Listing

function Show-ScheduledTasks {
    Write-Log "Scheduled Tasks:" -Level INFO
    Write-Log "=" * 80 -Level INFO
    
    try {
        $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike "*Microsoft*" } | Sort-Object TaskName
        
        if ($tasks.Count -eq 0) {
            Write-Log "No custom scheduled tasks found" -Level WARN
            return
        }
        
        Write-Log "Found $($tasks.Count) custom task(s):" -Level INFO
        Write-Log "" -Level INFO
        
        foreach ($task in $tasks) {
            $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
            
            $status = if ($task.State -eq 'Ready') { '[OK]' } elseif ($task.State -eq 'Running') { '>' } else { '[FAIL]' }
            $enabled = if ($task.Settings.Enabled) { 'Enabled' } else { 'Disabled' }
            
            Write-Log "$status $($task.TaskName) - $enabled" -Level INFO
            Write-Log "  Path: $($task.TaskPath)" -Level INFO
            Write-Log "  State: $($task.State)" -Level INFO
            
            if ($info) {
                if ($info.LastRunTime) {
                    Write-Log "  Last Run: $($info.LastRunTime)" -Level INFO
                }
                if ($info.NextRunTime) {
                    Write-Log "  Next Run: $($info.NextRunTime)" -Level INFO
                }
                Write-Log "  Last Result: $($info.LastTaskResult)" -Level INFO
            }
            
            # Trigger info
            if ($task.Triggers) {
                Write-Log "  Triggers:" -Level INFO
                foreach ($trigger in $task.Triggers) {
                    $triggerType = $trigger.CimClass.CimClassName -replace 'MSFT_TaskTrigger', ''
                    Write-Log "    - $triggerType" -Level INFO
                }
            }
            
            Write-Log "" -Level INFO
        }
    }
    catch {
        Write-Log "Error listing tasks: $($_.Exception.Message)" -Level ERROR
    }
}

#endregion

#region Reporting

function Get-ScheduledTaskReport {
    Write-Log "Generating scheduled tasks report..." -Level INFO
    
    try {
        $reportFile = Join-Path $LogDir "scheduled-tasks-$timestamp.txt"
        $report = @()
        
        $report += "Scheduled Tasks Report"
        $report += "=" * 80
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # Session statistics
        $report += "Session Summary:"
        $report += "  Tasks Created: $script:TasksCreated"
        $report += "  Tasks Removed: $script:TasksRemoved"
        $report += "  Operations Failed: $script:OperationsFailed"
        $report += ""
        
        # All tasks
        $tasks = Get-ScheduledTask | Sort-Object TaskPath, TaskName
        
        $report += "All Scheduled Tasks ($($tasks.Count)):"
        $report += "-" * 80
        
        $groupedTasks = $tasks | Group-Object -Property TaskPath
        
        foreach ($group in $groupedTasks) {
            $report += ""
            $report += "Path: $($group.Name)"
            
            foreach ($task in $group.Group) {
                $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
                $enabled = if ($task.Settings.Enabled) { "Enabled" } else { "Disabled" }
                
                $report += "  $($task.TaskName) - $enabled - State: $($task.State)"
                
                if ($info) {
                    if ($info.LastRunTime) {
                        $report += "    Last Run: $($info.LastRunTime)"
                    }
                    if ($info.NextRunTime) {
                        $report += "    Next Run: $($info.NextRunTime)"
                    }
                }
            }
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-Log "Task report saved to: $reportFile" -Level INFO
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

    Write-Log "===== Configure_Scheduled_Tasks starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Process operations
    $operationPerformed = $false
    
    # Create custom task
    if ($CreateTask) {
        if (-not $TaskName -or -not $ScriptPath) {
            Write-Log "TaskName and ScriptPath parameters are required" -Level ERROR
            exit 1
        }
        
        New-ScheduledTaskEx `
            -Name $TaskName `
            -Execute $ScriptPath `
            -Args $Arguments `
            -WorkDir $WorkingDirectory `
            -Description "Custom task: $TaskName" `
            -ScheduleType $Schedule `
            -ScheduleTime $Time `
            -Day $DayOfWeek `
            -SystemAccount $RunAsSystem `
            -TaskEnabled $Enabled
        
        $operationPerformed = $true
    }
    
    # Remove task
    if ($RemoveTask) {
        if (-not $TaskName) {
            Write-Log "TaskName parameter is required for removal" -Level ERROR
            exit 1
        }
        
        Remove-ScheduledTaskEx -Name $TaskName
        $operationPerformed = $true
    }
    
    # Create maintenance tasks
    if ($CreateMaintenanceTasks) {
        New-MaintenanceTasks
        $operationPerformed = $true
    }
    
    # List tasks
    if ($ListTasks) {
        Show-ScheduledTasks
        $operationPerformed = $true
    }
    
    # If no operation specified, list tasks
    if (-not $operationPerformed) {
        Write-Log "No operation specified. Listing scheduled tasks..." -Level INFO
        Write-Log "" -Level INFO
        Show-ScheduledTasks
    }
    
    # Generate report
    Get-ScheduledTaskReport | Out-Null
    
    # Summary
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    if ($script:OperationsFailed -eq 0) {
        Write-Log "===== Configure_Scheduled_Tasks complete in $([int]$duration)s; created=$($script:TasksCreated) removed=$($script:TasksRemoved) failed=$($script:OperationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_Scheduled_Tasks complete in $([int]$duration)s; created=$($script:TasksCreated) removed=$($script:TasksRemoved) failed=$($script:OperationsFailed) =====" -Level WARN
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
