<#
.SYNOPSIS
    Enable BitLocker Drive Encryption

.DESCRIPTION
    Enables BitLocker encryption on system drive with TPM or recovery key protection.
    Configures encryption algorithms and recovery key storage.

.NOTES
    File Name      : windows-server-Enable_Bitlocker.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, TPM chip (optional)
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Enable_Bitlocker.ps1
    Enables BitLocker with default settings
    
.EXAMPLE
    .\windows-server-Enable_Bitlocker.ps1 -RecoveryKeyPath "C:\Recovery"
    Enables BitLocker and saves recovery key to specified path
#>

[CmdletBinding()]
param(
    [string]$RecoveryKeyPath = "$env:SystemDrive\Recovery",
    [switch]$SkipHardwareTest,
    [ValidateSet('AES128', 'AES256', 'XTS-AES128', 'XTS-AES256')]
    [string]$EncryptionMethod = 'XTS-AES256'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [BitLocker] $Message"
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

    Write-Log "===== Enable_Bitlocker starting (EncryptionMethod=$EncryptionMethod, SkipHardwareTest=$SkipHardwareTest) ====="
    Write-Log "Recovery Key Path: $RecoveryKeyPath"

    # Check if BitLocker is available
    Write-Log "Checking BitLocker availability..."
    try {
        $bitlockerFeature = Get-WindowsOptionalFeature -Online -FeatureName 'BitLocker' -ErrorAction Stop
        
        if ($bitlockerFeature.State -ne 'Enabled') {
            Write-Log "Enabling BitLocker feature..."
            Enable-WindowsOptionalFeature -Online -FeatureName 'BitLocker' -All -NoRestart
            Write-Log "[OK] BitLocker feature enabled (restart may be required)"
        } else {
            Write-Log "[OK] BitLocker feature is already enabled"
        }
    } catch {
        Write-Log "Error checking BitLocker feature: $($_.Exception.Message)" -Level WARN
    }
    
    # Check TPM status
    Write-Log ""
    Write-Log "Checking TPM status..."
    $tpmAvailable = $false
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        Write-Log "TPM Present: $($tpm.TpmPresent)"
        Write-Log "TPM Ready: $($tpm.TpmReady)"
        Write-Log "TPM Enabled: $($tpm.TpmEnabled)"
        Write-Log "TPM Activated: $($tpm.TpmActivated)"
        
        if ($tpm.TpmPresent -and $tpm.TpmReady) {
            $tpmAvailable = $true
            Write-Log "[OK] TPM is available and ready"
        } else {
            Write-Log "TPM not ready - will use recovery password method" -Level WARN
        }
    } catch {
        Write-Log "TPM not available: $($_.Exception.Message)" -Level WARN
        Write-Log "Will use recovery password method"
    }
    
    # Check current BitLocker status
    Write-Log ""
    Write-Log "Checking current BitLocker status..."
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    
    if ($volume) {
        Write-Log "BitLocker status for $($env:SystemDrive):"
        Write-Log "  Protection Status: $($volume.ProtectionStatus)"
        Write-Log "  Encryption Percentage: $($volume.EncryptionPercentage)%"
        Write-Log "  Volume Status: $($volume.VolumeStatus)"
        Write-Log "  Encryption Method: $($volume.EncryptionMethod)"
        
        if ($volume.ProtectionStatus -eq 'On') {
            Write-Log "BitLocker is already enabled and protecting the drive"
            Write-Log "No action needed"

            # Summary and exit
            $duration = ((Get-Date) - $startTime).TotalSeconds
            Write-Log "===== Enable_Bitlocker complete in $([int]$duration)s; status=AlreadyProtected ====="
            try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
            exit 0
        }
    }
    
    # Create recovery key directory
    Write-Log ""
    Write-Log "Creating recovery key directory..."
    if (-not (Test-Path $RecoveryKeyPath)) {
        New-Item -Path $RecoveryKeyPath -ItemType Directory -Force | Out-Null
        Write-Log "[OK] Recovery key directory created: $RecoveryKeyPath"
    }
    
    # Configure BitLocker
    Write-Log ""
    Write-Log "Configuring BitLocker..."
    
    try {
        if ($tpmAvailable) {
            Write-Log "Enabling BitLocker with TPM protector..."
            
            # Add TPM protector
            Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -TpmProtector
            Write-Log "[OK] TPM protector added"
            
            # Add recovery password protector
            $recoveryPassword = Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector
            Write-Log "[OK] Recovery password protector added"
            
        } else {
            Write-Log "Enabling BitLocker with password protector..."
            
            # Generate recovery password
            $recoveryPassword = Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector
            Write-Log "[OK] Recovery password protector added"
        }
        
        # Save recovery key
        $recoveryKeyFile = Join-Path $RecoveryKeyPath "BitLocker-Recovery-$timestamp.txt"
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
        
        foreach ($keyProtector in $volume.KeyProtector) {
            if ($keyProtector.KeyProtectorType -eq 'RecoveryPassword') {
                $keyProtector.RecoveryPassword | Out-File -FilePath $recoveryKeyFile -Encoding UTF8
                Write-Log "[OK] Recovery password saved to: $recoveryKeyFile"
                break
            }
        }
        
        # Set encryption method
        Write-Log "Setting encryption method to: $EncryptionMethod"
        
        # Enable BitLocker
        Write-Log "Enabling BitLocker encryption..."
        if ($SkipHardwareTest) {
            Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod $EncryptionMethod -SkipHardwareTest -UsedSpaceOnly
            Write-Log "[OK] BitLocker enabled (hardware test skipped)"
        } else {
            Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod $EncryptionMethod -UsedSpaceOnly
            Write-Log "[OK] BitLocker enabled"
        }
        
        # Resume BitLocker (in case it's suspended)
        Resume-BitLocker -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        
        Write-Log "[OK] BitLocker encryption started"
        
    } catch {
        Write-Log "Error enabling BitLocker: $($_.Exception.Message)" -Level ERROR
        throw
    }
    
    # Verify BitLocker status
    Write-Log ""
    Write-Log "Verifying BitLocker status..."
    Start-Sleep -Seconds 3
    
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
    Write-Log "Current BitLocker status:"
    Write-Log "  Protection Status: $($volume.ProtectionStatus)"
    Write-Log "  Encryption Percentage: $($volume.EncryptionPercentage)%"
    Write-Log "  Volume Status: $($volume.VolumeStatus)"
    Write-Log "  Encryption Method: $($volume.EncryptionMethod)"
    Write-Log "  Key Protectors: $($volume.KeyProtector.Count)"
    
    foreach ($keyProtector in $volume.KeyProtector) {
        Write-Log "    - $($keyProtector.KeyProtectorType)"
    }
    
    # Summary
    $duration = ((Get-Date) - $startTime).TotalSeconds

    Write-Log "Protection Status: $($volume.ProtectionStatus)"
    Write-Log "Encryption Method: $($volume.EncryptionMethod)"
    Write-Log "TPM Used: $tpmAvailable"
    Write-Log "Recovery Key: $recoveryKeyFile"
    Write-Log "IMPORTANT: Save the recovery key in a secure location; encryption continues in the background" -Level WARN
    Write-Log "Monitor progress with: Get-BitLockerVolume -MountPoint $($env:SystemDrive)"
    Write-Log "===== Enable_Bitlocker complete in $([int]$duration)s; status=$($volume.ProtectionStatus) ====="

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit 0