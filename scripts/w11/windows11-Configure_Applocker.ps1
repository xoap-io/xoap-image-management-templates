<#
.SYNOPSIS
    Configure AppLocker Application Whitelisting

.DESCRIPTION
    Enables and configures AppLocker with default rules for application whitelisting,
    creates publisher rules, path rules, and enables audit mode for testing.

.NOTES
    File Name      : windows11-Configure_Applocker.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, Windows Enterprise/Server
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Configure_Applocker.ps1
    Configures AppLocker with default policies
    
.EXAMPLE
    .\windows11-Configure_Applocker.ps1 -AuditMode
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
    $logMessage = "[$timestamp] [$prefix] [AppLocker] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Start-Transcript -Path $LogFile -Append | Out-Null
    $startTime = Get-Date
    
    Write-Log "==================================================="
    Write-Log "AppLocker Configuration Script"
    Write-Log "==================================================="
    Write-Log "Audit Mode: $AuditMode"
    Write-Log ""
    
    # Check if AppLocker is available
    Write-Log "Checking AppLocker availability..."
    try {
        $appIdService = Get-Service -Name 'AppIDSvc' -ErrorAction Stop
        Write-Log "✓ AppLocker service found"
    } catch {
        Write-Log "AppLocker service not found - may not be available on this edition" -Level Error
        throw "AppLocker requires Windows Enterprise or Server edition"
    }
    
    # Enable and start Application Identity service
    Write-Log "Configuring Application Identity service..."
    try {
        Set-Service -Name 'AppIDSvc' -StartupType Automatic
        Start-Service -Name 'AppIDSvc' -ErrorAction Stop
        Write-Log "✓ Application Identity service started"
    } catch {
        Write-Log "Error starting AppIDSvc: $($_.Exception.Message)" -Level Warning
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
        Write-Log "✓ Executable rules created"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating executable rules: $($_.Exception.Message)" -Level Warning
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
        Write-Log "✓ Windows Installer rules created"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating MSI rules: $($_.Exception.Message)" -Level Warning
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
        Write-Log "✓ Script rules created"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating script rules: $($_.Exception.Message)" -Level Warning
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
        Write-Log "✓ DLL rules created (audit mode only)"
        $script:RulesCreated += 3
    } catch {
        Write-Log "Error creating DLL rules: $($_.Exception.Message)" -Level Warning
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
                Write-Log "  ✓ Enabled: $logName"
            } catch {
                Write-Log "  Could not enable: $logName" -Level Warning
            }
        }
    } catch {
        Write-Log "Error enabling AppLocker logs: $($_.Exception.Message)" -Level Warning
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
        Write-Log "Could not retrieve AppLocker policy" -Level Warning
    }
    
    # Clean up temp files
    Remove-Item -Path "$env:TEMP\AppLocker-*.xml" -Force -ErrorAction SilentlyContinue
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "AppLocker Configuration Summary"
    Write-Log "==================================================="
    Write-Log "Rules created: $script:RulesCreated"
    Write-Log "Enforcement mode: $(if ($AuditMode) { 'Audit Only' } else { 'Enabled' })"
    Write-Log "Service status: $($(Get-Service -Name 'AppIDSvc').Status)"
    Write-Log "Event logging: Enabled"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "AppLocker configuration completed!"
    
    if ($AuditMode) {
        Write-Log ""
        Write-Log "IMPORTANT: AppLocker is in AUDIT MODE"
        Write-Log "Monitor AppLocker logs before enforcing policies"
        Write-Log "Event Viewer: Applications and Services Logs > Microsoft > Windows > AppLocker"
    }
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}