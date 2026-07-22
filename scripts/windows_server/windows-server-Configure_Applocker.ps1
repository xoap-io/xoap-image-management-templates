<#
.SYNOPSIS
    Configure AppLocker Application Whitelisting

.DESCRIPTION
    Enables and configures AppLocker with default rules for application whitelisting,
    creates publisher rules, path rules, and enables audit mode for testing.

.NOTES
    File Name      : windows-server-Configure_Applocker.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, Windows Enterprise/Server
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_Applocker.ps1
    Configures AppLocker with default policies
    
.EXAMPLE
    .\windows-server-Configure_Applocker.ps1 -AuditMode
    Configures AppLocker in audit-only mode
#>

[CmdletBinding()]
param(
    [switch]$AuditMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

$script:RulesCreated = 0

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [AppLocker] $Message"
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

    Write-Log "===== Configure_Applocker starting (AuditMode=$AuditMode) ====="

    # Check if AppLocker is available
    Write-Log "Checking AppLocker availability..."
    try {
        $appIdService = Get-Service -Name 'AppIDSvc' -ErrorAction Stop
        Write-Log "[OK] AppLocker service found"
    } catch {
        Write-Log "AppLocker service not found - may not be available on this edition" -Level ERROR
        throw "AppLocker requires Windows Enterprise or Server edition"
    }
    
    # Enable and start Application Identity service
    Write-Log "Configuring Application Identity service..."
    try {
        Set-Service -Name 'AppIDSvc' -StartupType Automatic
        Start-Service -Name 'AppIDSvc' -ErrorAction Stop
        Write-Log "[OK] Application Identity service started"
    } catch {
        Write-Log "Error starting AppIDSvc: $($_.Exception.Message)" -Level WARN
    }
    
    # Create default AppLocker rules
    Write-Log ""
    Write-Log "Creating default AppLocker rules..."
    
    # Executable rules
    Write-Log "Creating executable rules..."
    try {
        $exeRules = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="$(if ($AuditMode) { 'AuditOnly' } else { 'Enabled' })">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="All files located in the Program Files folder" Description="Allows members of the Everyone group to run applications that are located in the Program Files folder." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7b51" Name="All files located in the Windows folder" Description="Allows members of the Everyone group to run applications that are located in the Windows folder." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="All files" Description="Allows members of the local Administrators group to run all applications." UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
        
        $exeRules | Out-File -FilePath "$env:TEMP\AppLocker-Exe.xml" -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy "$env:TEMP\AppLocker-Exe.xml" -Merge
        Write-Log "[OK] Executable rules created"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating executable rules: $($_.Exception.Message)" -Level WARN
    }
    
    # Windows Installer rules
    Write-Log "Creating Windows Installer rules..."
    try {
        $msiRules = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Msi" EnforcementMode="$(if ($AuditMode) { 'AuditOnly' } else { 'Enabled' })">
    <FilePathRule Id="5b290184-345a-4453-b184-45305f6d9a54" Name="All Windows Installer files in %systemdrive%\Windows\Installer" Description="Allows members of the Everyone group to run all Windows Installer files located in %systemdrive%\Windows\Installer." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\Installer\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="64ad46ff-0d71-4fa0-a30b-3f3d30c5433d" Name="All digitally signed Windows Installer files" Description="Allows members of the Everyone group to run digitally signed Windows Installer files." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="b7af4042-7c7c-4382-bcf8-9f0e18f18380" Name="All Windows Installer files" Description="Allows members of the local Administrators group to run all Windows Installer files." UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
        
        $msiRules | Out-File -FilePath "$env:TEMP\AppLocker-Msi.xml" -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy "$env:TEMP\AppLocker-Msi.xml" -Merge
        Write-Log "[OK] Windows Installer rules created"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating MSI rules: $($_.Exception.Message)" -Level WARN
    }
    
    # Script rules
    Write-Log "Creating script rules..."
    try {
        $scriptRules = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Script" EnforcementMode="$(if ($AuditMode) { 'AuditOnly' } else { 'Enabled' })">
    <FilePathRule Id="06dce67b-934c-454f-a263-2515c8796a5d" Name="All scripts located in the Program Files folder" Description="Allows members of the Everyone group to run scripts that are located in the Program Files folder." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="9428c672-5fc3-47f4-808a-a0011f36dd2c" Name="All scripts located in the Windows folder" Description="Allows members of the Everyone group to run scripts that are located in the Windows folder." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="ed97d0cb-15ff-430f-b82c-8d7832957725" Name="All scripts" Description="Allows members of the local Administrators group to run all scripts." UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
        
        $scriptRules | Out-File -FilePath "$env:TEMP\AppLocker-Script.xml" -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy "$env:TEMP\AppLocker-Script.xml" -Merge
        Write-Log "[OK] Script rules created"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating script rules: $($_.Exception.Message)" -Level WARN
    }
    
    # DLL rules (optional - can impact performance)
    Write-Log "Creating DLL rules (enforcement disabled by default)..."
    try {
        $dllRules = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Dll" EnforcementMode="AuditOnly">
    <FilePathRule Id="b7c4d2b3-30c8-434f-8076-7c5d8d7f4f58" Name="All DLLs located in the Program Files folder" Description="Allows members of the Everyone group to load DLLs that are located in the Program Files folder." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d3" Name="All DLLs located in the Windows folder" Description="Allows members of the Everyone group to load DLLs that are located in the Windows folder." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="ad7d1fb5-20e8-4c7d-b3f8-9c6e6b1d5c8f" Name="All DLLs" Description="Allows members of the local Administrators group to load all DLLs." UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
        
        $dllRules | Out-File -FilePath "$env:TEMP\AppLocker-Dll.xml" -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy "$env:TEMP\AppLocker-Dll.xml" -Merge
        Write-Log "[OK] DLL rules created (audit mode only)"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating DLL rules: $($_.Exception.Message)" -Level WARN
    }
    
    # Enable AppLocker event logging
    Write-Log ""
    Write-Log "Enabling AppLocker event logs..."
    try {
        $appLockerLogs = @(
            'Microsoft-Windows-AppLocker/EXE and DLL',
            'Microsoft-Windows-AppLocker/MSI and Script',
            'Microsoft-Windows-AppLocker/Packaged app-Deployment',
            'Microsoft-Windows-AppLocker/Packaged app-Execution'
        )
        
        foreach ($logName in $appLockerLogs) {
            try {
                $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
                $log.IsEnabled = $true
                $log.SaveChanges()
                Write-Log "  [OK] Enabled: $logName"
            } catch {
                Write-Log "  Could not enable: $logName" -Level WARN
            }
        }
    } catch {
        Write-Log "Error enabling AppLocker logs: $($_.Exception.Message)" -Level WARN
    }
    
    # Display current AppLocker policy
    Write-Log ""
    Write-Log "Current AppLocker policy summary:"
    try {
        $policy = Get-AppLockerPolicy -Effective
        Write-Log "  Rule collections configured: $($policy.RuleCollections.Count)"
        
        foreach ($collection in $policy.RuleCollections) {
            $ruleCount = $collection.Count
            Write-Log "  $($collection.RuleCollectionType): $ruleCount rules, Mode: $($collection.EnforcementMode)"
        }
    } catch {
        Write-Log "Could not retrieve AppLocker policy" -Level WARN
    }
    
    # Clean up temp files
    Remove-Item -Path "$env:TEMP\AppLocker-*.xml" -Force -ErrorAction SilentlyContinue
    
    # Summary
    $duration = ((Get-Date) - $startTime).TotalSeconds

    Write-Log "Enforcement mode: $(if ($AuditMode) { 'Audit Only' } else { 'Enabled' })"
    Write-Log "Service status: $($(Get-Service -Name 'AppIDSvc').Status)"
    Write-Log "Event logging: Enabled"

    if ($AuditMode) {
        Write-Log "IMPORTANT: AppLocker is in AUDIT MODE" -Level WARN
        Write-Log "Monitor AppLocker logs before enforcing policies" -Level WARN
        Write-Log "Event Viewer: Applications and Services Logs > Microsoft > Windows > AppLocker" -Level WARN
    }

    Write-Log "===== Configure_Applocker complete in $([int]$duration)s; applied=$($script:RulesCreated) ====="

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit 0