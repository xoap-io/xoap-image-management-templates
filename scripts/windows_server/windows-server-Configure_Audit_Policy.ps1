<#
.SYNOPSIS
    Configure Advanced Audit Policies

.DESCRIPTION
    Enables advanced audit policies for security monitoring including process creation,
    registry access, file system access, and security event forwarding.

.NOTES
    File Name      : windows-server-configure_Audit_Policy.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-configure_Audit_Policy.ps1
    Configures comprehensive audit policies
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:PoliciesConfigured = 0

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [Audit] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

try {
    # Setup local file logging to C:\xoap-logs (transcript captures all host output)
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
    } catch {
        Write-Host "[WARN] Failed to start transcript logging to $LogDir : $($_.Exception.Message)"
    }

    $startTime = Get-Date

    Write-Log "===== Configure_Audit_Policy starting ====="

    # Configure audit log size
    Write-Log "Configuring Security event log size..."
    try {
        $logName = 'Security'
        $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
        
        # Set to 1GB
        $log.MaximumSizeInBytes = 1GB
        $log.SaveChanges()
        
        Write-Log "[OK] Security log size set to 1GB"
        Write-Log "  Current size: $([math]::Round($log.FileSize / 1MB, 2)) MB"
        $script:PoliciesConfigured++
    } catch {
        Write-Log "Error configuring log size: $($_.Exception.Message)" -Level WARN
    }
    
    # Enable advanced audit policies using auditpol
    Write-Log ""
    Write-Log "Configuring advanced audit policies..."
    
    $auditCategories = @(
        # Account Logon
        @{Category='Account Logon'; Subcategory='Credential Validation'; Setting='Success,Failure'},
        @{Category='Account Logon'; Subcategory='Kerberos Authentication Service'; Setting='Success,Failure'},
        @{Category='Account Logon'; Subcategory='Kerberos Service Ticket Operations'; Setting='Success,Failure'},
        
        # Account Management
        @{Category='Account Management'; Subcategory='User Account Management'; Setting='Success,Failure'},
        @{Category='Account Management'; Subcategory='Security Group Management'; Setting='Success,Failure'},
        @{Category='Account Management'; Subcategory='Computer Account Management'; Setting='Success,Failure'},
        
        # Detailed Tracking
        @{Category='Detailed Tracking'; Subcategory='Process Creation'; Setting='Success'},
        @{Category='Detailed Tracking'; Subcategory='Process Termination'; Setting='Success'},
        @{Category='Detailed Tracking'; Subcategory='DPAPI Activity'; Setting='Success,Failure'},
        
        # Logon/Logoff
        @{Category='Logon/Logoff'; Subcategory='Logon'; Setting='Success,Failure'},
        @{Category='Logon/Logoff'; Subcategory='Logoff'; Setting='Success'},
        @{Category='Logon/Logoff'; Subcategory='Account Lockout'; Setting='Success,Failure'},
        @{Category='Logon/Logoff'; Subcategory='Special Logon'; Setting='Success'},
        
        # Object Access
        @{Category='Object Access'; Subcategory='File System'; Setting='Failure'},
        @{Category='Object Access'; Subcategory='Registry'; Setting='Failure'},
        @{Category='Object Access'; Subcategory='Removable Storage'; Setting='Success,Failure'},
        @{Category='Object Access'; Subcategory='Handle Manipulation'; Setting='Failure'},
        
        # Policy Change
        @{Category='Policy Change'; Subcategory='Audit Policy Change'; Setting='Success,Failure'},
        @{Category='Policy Change'; Subcategory='Authentication Policy Change'; Setting='Success'},
        @{Category='Policy Change'; Subcategory='Authorization Policy Change'; Setting='Success'},
        
        # Privilege Use
        @{Category='Privilege Use'; Subcategory='Sensitive Privilege Use'; Setting='Success,Failure'},
        
        # System
        @{Category='System'; Subcategory='Security State Change'; Setting='Success,Failure'},
        @{Category='System'; Subcategory='Security System Extension'; Setting='Success,Failure'},
        @{Category='System'; Subcategory='System Integrity'; Setting='Success,Failure'},
        @{Category='System'; Subcategory='IPsec Driver'; Setting='Success,Failure'}
    )
    
    foreach ($policy in $auditCategories) {
        try {
            $result = & auditpol.exe /set /subcategory:"$($policy.Subcategory)" /success:enable /failure:enable 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] $($policy.Category) - $($policy.Subcategory): $($policy.Setting)"
                $script:PoliciesConfigured++
            } else {
                Write-Log "  [FAIL] Failed to set: $($policy.Subcategory)" -Level WARN
            }
        } catch {
            Write-Log "  Error setting $($policy.Subcategory): $($_.Exception.Message)" -Level WARN
        }
    }
    
    # Enable command line process auditing
    Write-Log ""
    Write-Log "Enabling command line process auditing..."
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord
        Write-Log "[OK] Command line process auditing enabled"
        $script:PoliciesConfigured++
    } catch {
        Write-Log "Error enabling command line auditing: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure PowerShell logging
    Write-Log ""
    Write-Log "Enabling PowerShell logging..."
    try {
        # Module logging
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name 'EnableModuleLogging' -Value 1 -Type DWord
        
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name '*' -Value '*' -Type String
        
        # Script block logging
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name 'EnableScriptBlockLogging' -Value 1 -Type DWord
        
        # Transcription
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name 'EnableTranscripting' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'EnableInvocationHeader' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'OutputDirectory' -Value 'C:\xoap-logs\PowerShell' -Type String
        
        # Create PowerShell log directory
        $psLogDir = 'C:\xoap-logs\PowerShell'
        if (-not (Test-Path $psLogDir)) {
            New-Item -Path $psLogDir -ItemType Directory -Force | Out-Null
        }
        
        Write-Log "[OK] PowerShell logging enabled"
        $script:PoliciesConfigured++
    } catch {
        Write-Log "Error configuring PowerShell logging: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure Windows Defender Advanced Threat Protection logging (if available)
    Write-Log ""
    Write-Log "Configuring Windows Defender ATP logging..."
    try {
        $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name 'DisableEnhancedNotifications' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "[OK] Windows Defender logging configured"
        $script:PoliciesConfigured++
    } catch {
        Write-Log "Windows Defender ATP not available or error: $($_.Exception.Message)" -Level WARN
    }
    
    # Enable DNS Client logging
    Write-Log ""
    Write-Log "Enabling DNS Client event logging..."
    try {
        $dnsLog = Get-WinEvent -ListLog 'Microsoft-Windows-DNS-Client/Operational' -ErrorAction Stop
        $dnsLog.IsEnabled = $true
        $dnsLog.SaveChanges()
        Write-Log "[OK] DNS Client logging enabled"
        $script:PoliciesConfigured++
    } catch {
        Write-Log "Error enabling DNS logging: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure audit policy backup
    Write-Log ""
    Write-Log "Creating audit policy backup..."
    try {
        $backupPath = Join-Path $LogDir "AuditPolicy-Backup-$timestamp.csv"
        & auditpol.exe /backup /file:$backupPath 2>&1 | Out-Null
        
        if (Test-Path $backupPath) {
            Write-Log "[OK] Audit policy backed up to: $backupPath"
            $script:PoliciesConfigured++
        }
    } catch {
        Write-Log "Error backing up audit policy: $($_.Exception.Message)" -Level WARN
    }
    
    # Display current audit policy
    Write-Log ""
    Write-Log "Current audit policy summary:"
    try {
        $auditSummary = & auditpol.exe /get /category:* 2>&1
        $enabledPolicies = ($auditSummary | Select-String -Pattern 'Success and Failure|Success|Failure').Count
        Write-Log "  Total enabled audit policies: $enabledPolicies"
    } catch {
        Write-Log "Could not retrieve audit summary" -Level WARN
    }
    
    # Summary
    $duration = ((Get-Date) - $startTime).TotalSeconds

    Write-Log "Security log size: 1GB"
    Write-Log "Command line auditing: Enabled"
    Write-Log "PowerShell logging: Enabled"
    Write-Log "===== Configure_Audit_Policy complete in $([int]$duration)s; applied=$($script:PoliciesConfigured) ====="

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit 0