<#
.SYNOPSIS
    Enable BitLocker Drive Encryption

.DESCRIPTION
    Enables BitLocker encryption on system drive with TPM or recovery key protection.
    Configures encryption algorithms and recovery key storage.

.NOTES
    File Name      : windows11-Enable_Bitlocker.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, TPM chip (optional)
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Enable_Bitlocker.ps1
    Enables BitLocker with default settings
    
.EXAMPLE
    .\windows11-Enable_Bitlocker.ps1 -RecoveryKeyPath "C:\Recovery"
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
    $logMessage = "[$timestamp] [$prefix] [BitLocker] $Message"
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
    Write-Log "BitLocker Drive Encryption Configuration"
    Write-Log "==================================================="
    Write-Log "Recovery Key Path: $RecoveryKeyPath"
    Write-Log "Encryption Method: $EncryptionMethod"
    Write-Log "Skip Hardware Test: $SkipHardwareTest"
    Write-Log ""
    
    # Check if BitLocker is available
    Write-Log "Checking BitLocker availability..."
    try {
        $bitlockerFeature = Get-WindowsOptionalFeature -Online -FeatureName 'BitLocker' -ErrorAction Stop
        
        if ($bitlockerFeature.State -ne 'Enabled') {
            Write-Log "Enabling BitLocker feature..."
            Enable-WindowsOptionalFeature -Online -FeatureName 'BitLocker' -All -NoRestart
            Write-Log "✓ BitLocker feature enabled (restart may be required)"
        } else {
            Write-Log "✓ BitLocker feature is already enabled"
        }
    } catch {
        Write-Log "Error checking BitLocker feature: $($_.Exception.Message)" -Level Warning
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
            Write-Log "✓ TPM is available and ready"
        } else {
            Write-Log "TPM not ready - will use recovery password method" -Level Warning
        }
    } catch {
        Write-Log "TPM not available: $($_.Exception.Message)" -Level Warning
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
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            Write-Log ""
            Write-Log "==================================================="
            Write-Log "BitLocker Status: Already Protected"
            Write-Log "Execution time: $([math]::Round($duration, 2))s"
            Write-Log "==================================================="
            return
        }
    }
    
    # Create recovery key directory
    Write-Log ""
    Write-Log "Creating recovery key directory..."
    if (-not (Test-Path $RecoveryKeyPath)) {
        New-Item -Path $RecoveryKeyPath -ItemType Directory -Force | Out-Null
        Write-Log "✓ Recovery key directory created: $RecoveryKeyPath"
    }
    
    # Configure BitLocker
    Write-Log ""
    Write-Log "Configuring BitLocker..."
    
    try {
        if ($tpmAvailable) {
            Write-Log "Enabling BitLocker with TPM protector..."
            
            # Add TPM protector
            Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -TpmProtector
            Write-Log "✓ TPM protector added"
            
            # Add recovery password protector
            $recoveryPassword = Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector
            Write-Log "✓ Recovery password protector added"
            
        } else {
            Write-Log "Enabling BitLocker with password protector..."
            
            # Generate recovery password
            $recoveryPassword = Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector
            Write-Log "✓ Recovery password protector added"
        }
        
        # Save recovery key
        $recoveryKeyFile = Join-Path $RecoveryKeyPath "BitLocker-Recovery-$timestamp.txt"
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
        
        foreach ($keyProtector in $volume.KeyProtector) {
            if ($keyProtector.KeyProtectorType -eq 'RecoveryPassword') {
                $keyProtector.RecoveryPassword | Out-File -FilePath $recoveryKeyFile -Encoding UTF8
                Write-Log "✓ Recovery password saved to: $recoveryKeyFile"
                break
            }
        }
        
        # Set encryption method
        Write-Log "Setting encryption method to: $EncryptionMethod"
        
        # Enable BitLocker
        Write-Log "Enabling BitLocker encryption..."
        if ($SkipHardwareTest) {
            Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod $EncryptionMethod -SkipHardwareTest -UsedSpaceOnly
            Write-Log "✓ BitLocker enabled (hardware test skipped)"
        } else {
            Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod $EncryptionMethod -UsedSpaceOnly
            Write-Log "✓ BitLocker enabled"
        }
        
        # Resume BitLocker (in case it's suspended)
        Resume-BitLocker -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        
        Write-Log "✓ BitLocker encryption started"
        
    } catch {
        Write-Log "Error enabling BitLocker: $($_.Exception.Message)" -Level Error
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
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "BitLocker Encryption Summary"
    Write-Log "==================================================="
    Write-Log "Protection Status: $($volume.ProtectionStatus)"
    Write-Log "Encryption Method: $($volume.EncryptionMethod)"
    Write-Log "TPM Used: $tpmAvailable"
    Write-Log "Recovery Key: $recoveryKeyFile"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "BitLocker encryption initiated successfully!"
    Write-Log ""
    Write-Log "IMPORTANT:"
    Write-Log "  - Save the recovery key in a secure location"
    Write-Log "  - Encryption will continue in the background"
    Write-Log "  - Monitor progress with: Get-BitLockerVolume -MountPoint $($env:SystemDrive)"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}