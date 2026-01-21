<#
.SYNOPSIS
    Configure Windows Defender Credential Guard

.DESCRIPTION
    Enables Windows Defender Credential Guard and virtualization-based security
    to protect credentials from theft attacks.

.NOTES
    File Name      : windows-server-Configure_CredentialGuard.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, UEFI, TPM 2.0
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_CredentialGuard.ps1
    Enables Credential Guard with default settings
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
    $logMessage = "[$timestamp] [$prefix] [CredGuard] $Message"
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
    Write-Log "Credential Guard Configuration Script"
    Write-Log "==================================================="
    
    # Check system requirements
    Write-Log "Checking system requirements..."
    
    # Check for UEFI
    try {
        $firmwareType = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name 'UEFISecureBootEnabled' -ErrorAction Stop).UEFISecureBootEnabled
        if ($firmwareType -eq 1) {
            Write-Log "✓ UEFI Secure Boot is enabled"
        } else {
            Write-Log "UEFI Secure Boot is not enabled" -Level Warning
        }
    } catch {
        Write-Log "Could not verify UEFI status: $($_.Exception.Message)" -Level Warning
    }
    
    # Check for TPM
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        Write-Log "TPM Version: $($tpm.ManufacturerVersion)"
        Write-Log "TPM Present: $($tpm.TpmPresent)"
        Write-Log "TPM Ready: $($tpm.TpmReady)"
        
        if ($tpm.TpmPresent -and $tpm.TpmReady) {
            Write-Log "✓ TPM is available and ready"
        } else {
            Write-Log "TPM requirements not met" -Level Warning
        }
    } catch {
        Write-Log "TPM check failed: $($_.Exception.Message)" -Level Warning
    }
    
    # Check virtualization extensions
    Write-Log ""
    Write-Log "Checking virtualization support..."
    try {
        $hyperv = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-Hypervisor' -ErrorAction SilentlyContinue
        if ($hyperv) {
            Write-Log "Hyper-V hypervisor feature state: $($hyperv.State)"
        }
        
        # Check if VBS is supported
        $vbsStatus = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
        if ($vbsStatus) {
            Write-Log "Available Security Properties:"
            foreach ($prop in $vbsStatus.AvailableSecurityProperties) {
                Write-Log "  - $prop"
            }
        }
    } catch {
        Write-Log "Could not check virtualization support: $($_.Exception.Message)" -Level Warning
    }
    
    # Enable required Windows features
    Write-Log ""
    Write-Log "Enabling required Windows features..."
    
    $features = @(
        'Microsoft-Hyper-V-Hypervisor',
        'IsolatedUserMode'
    )
    
    foreach ($feature in $features) {
        try {
            $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            
            if ($featureState -and $featureState.State -ne 'Enabled') {
                Write-Log "Enabling feature: $feature"
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
                Write-Log "✓ $feature enabled"
            } elseif ($featureState) {
                Write-Log "✓ $feature already enabled"
            } else {
                Write-Log "$feature not found" -Level Warning
            }
        } catch {
            Write-Log "Could not enable $feature : $($_.Exception.Message)" -Level Warning
        }
    }
    
    # Configure Credential Guard via registry
    Write-Log ""
    Write-Log "Configuring Credential Guard registry settings..."
    
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Enable VBS
        Set-ItemProperty -Path $regPath -Name 'EnableVirtualizationBasedSecurity' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'RequirePlatformSecurityFeatures' -Value 1 -Type DWord # 1 = Secure Boot only, 3 = Secure Boot and DMA
        
        Write-Log "✓ Virtualization-based security enabled"
        
        # Enable Credential Guard
        $lsaRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        if (-not (Test-Path $lsaRegPath)) {
            New-Item -Path $lsaRegPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $lsaRegPath -Name 'LsaCfgFlags' -Value 1 -Type DWord # 1 = Enabled with UEFI lock, 2 = Enabled without lock
        Write-Log "✓ Credential Guard enabled"
        
        # Enable HVCI (Hypervisor-protected Code Integrity)
        $hvciRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
        if (-not (Test-Path $hvciRegPath)) {
            New-Item -Path $hvciRegPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $hvciRegPath -Name 'Enabled' -Value 1 -Type DWord
        Write-Log "✓ HVCI (Hypervisor-protected Code Integrity) enabled"
        
    } catch {
        Write-Log "Error configuring registry: $($_.Exception.Message)" -Level Error
        throw
    }
    
    # Configure additional security settings
    Write-Log ""
    Write-Log "Configuring additional VBS settings..."
    
    try {
        # Kernel DMA Protection (if supported)
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'RequireDMAProtection' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "✓ Kernel DMA Protection configured"
        
        # Secure Boot
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'Locked' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "✓ Secure Boot lock configured"
        
    } catch {
        Write-Log "Error configuring additional settings: $($_.Exception.Message)" -Level Warning
    }
    
    # Verify configuration
    Write-Log ""
    Write-Log "Verifying Credential Guard configuration..."
    
    try {
        $deviceGuard = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        
        Write-Log "Device Guard Configuration:"
        Write-Log "  VBS Running: $(if ($deviceGuard.VirtualizationBasedSecurityStatus -eq 2) { 'Yes' } else { 'No' })"
        Write-Log "  Credential Guard Status: $($deviceGuard.SecurityServicesRunning)"
        Write-Log "  Code Integrity Status: $($deviceGuard.CodeIntegrityPolicyEnforcementStatus)"
        
    } catch {
        Write-Log "Could not verify configuration: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "==================================================="
    Write-Log "Credential Guard Configuration Summary"
    Write-Log "==================================================="
    Write-Log "Virtualization-based Security: Enabled"
    Write-Log "Credential Guard: Enabled"
    Write-Log "HVCI: Enabled"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "==================================================="
    Write-Log "Credential Guard configuration completed!"
    Write-Log ""
    Write-Log "IMPORTANT:"
    Write-Log "  - A system restart is REQUIRED for changes to take effect"
    Write-Log "  - Verify after restart with: Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard"
    Write-Log "  - Credential Guard provides protection against:"
    Write-Log "    • Pass-the-Hash attacks"
    Write-Log "    • Pass-the-Ticket attacks"
    Write-Log "    • Credential theft from LSASS"
    
} catch {
    Write-Log "Script execution failed: $_" -Level Error
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}