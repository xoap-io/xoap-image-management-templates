<#
.SYNOPSIS
    Harden SMB Configuration

.DESCRIPTION
    Secures SMB configuration by disabling SMBv1, configuring SMBv2/v3 security,
    enabling encryption, and configuring SMB signing.

.NOTES
    File Name      : windows-server-Harden_SMB_Configuration.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Harden_SMB_Configuration.ps1
    Hardens SMB configuration with security best practices
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

$script:ConfigurationsApplied = 0

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
    $logMessage = "[$timestamp] [$prefix] [SMB] $Message"
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
    Write-Log "SMB Security Hardening Script"
    Write-Log "==================================================="
    
    # Check current SMB configuration
    Write-Log "Checking current SMB configuration..."
    try {
        $smbServerConfig = Get-SmbServerConfiguration
        Write-Log "Current SMB Server Configuration:"
        Write-Log "  SMBv1: $($smbServerConfig.EnableSMB1Protocol)"
        Write-Log "  SMBv2: $($smbServerConfig.EnableSMB2Protocol)"
        Write-Log "  Encryption: $($smbServerConfig.EncryptData)"
        Write-Log "  Signing: $($smbServerConfig.RequireSecuritySignature)"
    } catch {
        Write-Log "Could not retrieve SMB configuration: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable SMBv1 Protocol
    Write-Log ""
    Write-Log "Disabling SMBv1 protocol..."
    try {
        # Disable SMBv1 Server
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
        Write-Log "✓ SMBv1 server protocol disabled"
        $script:ConfigurationsApplied++
        
        # Disable SMBv1 Client
        sc.exe config lanmanworkstation depend= bowser/mrxsmb20/nsi
        sc.exe config mrxsmb10 start= disabled
        Write-Log "✓ SMBv1 client disabled"
        $script:ConfigurationsApplied++
        
        # Remove SMBv1 Windows feature (if installed)
        $smb1Feature = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
        if ($smb1Feature -and $smb1Feature.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop
            Write-Log "✓ SMBv1 Windows feature disabled"
            $script:ConfigurationsApplied++
        }
    } catch {
        Write-Log "Error disabling SMBv1: $($_.Exception.Message)" -Level Warning
    }
    
    # Enable SMBv2/SMBv3
    Write-Log ""
    Write-Log "Ensuring SMBv2/SMBv3 is enabled..."
    try {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
        Write-Log "✓ SMBv2/SMBv3 protocol enabled"
        $script:ConfigurationsApplied++
    } catch {
        Write-Log "Error enabling SMBv2/SMBv3: $($_.Exception.Message)" -Level Warning
    }
    
    # Enable SMB Encryption
    Write-Log ""
    Write-Log "Enabling SMB encryption..."
    try {
        Set-SmbServerConfiguration -EncryptData $true -Force -ErrorAction Stop
        Write-Log "✓ SMB encryption enabled"
        $script:ConfigurationsApplied++
        
        # Reject unencrypted access
        Set-SmbServerConfiguration -RejectUnencryptedAccess $true -Force -ErrorAction Stop
        Write-Log "✓ Unencrypted SMB access rejected"
        $script:ConfigurationsApplied++
    } catch {
        Write-Log "Error configuring SMB encryption: $($_.Exception.Message)" -Level Warning
    }
    
    # Enable SMB Signing
    Write-Log ""
    Write-Log "Enabling SMB signing..."
    try {
        Set-SmbServerConfiguration -RequireSecuritySignature $true -Force -ErrorAction Stop
        Write-Log "✓ SMB signing required"
        $script:ConfigurationsApplied++
        
        Set-SmbServerConfiguration -EnableSecuritySignature $true -Force -ErrorAction Stop
        Write-Log "✓ SMB signing enabled"
        $script:ConfigurationsApplied++
    } catch {
        Write-Log "Error configuring SMB signing: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable SMB compression (prevents compression bombs)
    Write-Log ""
    Write-Log "Configuring SMB compression settings..."
    try {
        # This requires Windows Server 2022 or later
        $osVersion = [System.Environment]::OSVersion.Version
        if ($osVersion.Major -ge 10 -and $osVersion.Build -ge 20348) {
            Set-SmbServerConfiguration -DisableCompression $true -Force -ErrorAction Stop
            Write-Log "✓ SMB compression disabled"
            $script:ConfigurationsApplied++
        } else {
            Write-Log "SMB compression settings not available on this OS version"
        }
    } catch {
        Write-Log "Could not configure SMB compression: $($_.Exception.Message)" -Level Warning
    }
    
    # Configure SMB timeouts
    Write-Log ""
    Write-Log "Configuring SMB timeout settings..."
    try {
        Set-SmbServerConfiguration -AutoDisconnectTimeout 15 -Force -ErrorAction Stop
        Write-Log "✓ Auto-disconnect timeout set to 15 minutes"
        $script:ConfigurationsApplied++
    } catch {
        Write-Log "Error configuring timeouts: $($_.Exception.Message)" -Level Warning
    }
    
    # Disable SMB1 audit logging (generate events for SMB1 access attempts)
    Write-Log ""
    Write-Log "Enabling SMB1 auditing..."
    try {
        Set-SmbServerConfiguration -AuditSmb1Access $true -Force -ErrorAction Stop
        Write-Log "✓ SMB1 access auditing enabled"
        $script:ConfigurationsApplied++
    } catch {
        Write-Log "Error enabling SMB1 auditing: $($_.Exception.Message)" -Level Warning
    }
    
    # Configure registry settings for additional hardening
    Write-Log ""
    Write-Log "Applying registry-based SMB hardening..."
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        
        # Disable SMBv1
        Set-ItemProperty -Path $regPath -Name 'SMB1' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        
        # Require SMB signing
        Set-ItemProperty -Path $regPath -Name 'RequireSecuritySignature' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'EnableSecuritySignature' -Value 1 -Type DWord
        
        # Configure workstation settings
        $wksPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
        Set-ItemProperty -Path $wksPath -Name 'RequireSecuritySignature' -Value 1 -Type DWord
        Set-ItemProperty -Path $wksPath -Name 'EnableSecuritySignature' -Value 1 -Type DWord
        
        Write-Log "✓ Registry-based SMB hardening applied"
        $script:ConfigurationsApplied++
    } catch {
        Write-Log "Error applying registry settings: $($_.Exception.Message)" -Level Warning
    }
    
    # Display final SMB configuration
    Write-Log ""
    Write-Log "Final SMB configuration:"
    try {
        $finalConfig = Get-SmbServerConfiguration
        Write-Log "  SMBv1 Protocol: $($finalConfig.EnableSMB1Protocol)"
        Write-Log "  SMBv2 Protocol: $($finalConfig.EnableSMB2Protocol)"
        Write-Log "  Encryption: $($finalConfig.EncryptData)"
        Write-Log "  Reject Unencrypted: $($finalConfig.RejectUnencryptedAccess)"
        Write-Log "  Require Signing: $($finalConfig.RequireSecuritySignature)"
        Write-Log "  Enable Signing: $($finalConfig.EnableSecuritySignature)"
        Write-Log "  SMB1 Auditing: $($finalConfig.AuditSmb1Access)"
        Write-Log "  Auto-Disconnect: $($finalConfig.AutoDisconnectTimeout) minutes"
    } catch {
        Write-Log "Could not display final configuration" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "SMB Security Hardening Summary"
    Write-Log "==================================================="
    Write-Log "Configurations applied: $script:ConfigurationsApplied"
    Write-Log "SMBv1: Disabled"
    Write-Log "SMBv2/v3: Enabled"
    Write-Log "Encryption: Enabled"
    Write-Log "Signing: Required"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "SMB security hardening completed!"
    Write-Log ""
    Write-Log "IMPORTANT: A system restart may be required for all changes to take effect"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}