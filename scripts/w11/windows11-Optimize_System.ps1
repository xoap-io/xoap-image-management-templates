<#
.SYNOPSIS
    Optimize Windows 10/11 System

.DESCRIPTION
    Configures and optimizes Windows 10/11 VM for Packer builds including:
    - User account configuration (vagrant/Administrator)
    - Network settings (disable APIPA, IPv6)
    - Boot manager configuration
    - Guest tools installation (VirtualBox, VMware, Parallels, QEMU, Hyper-V)

.NOTES
    File Name      : windows11-Optimize_System.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Optimize_System.ps1
    Provisions VM based on PACKER_BUILDER_TYPE environment variable
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

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
    Write-Host "[$timestamp] [$prefix] [Provision] $Message"
}

function Install-GuestTools {
    param(
        [Parameter(Mandatory)]
        [string]$BuilderType
    )
    
    Write-Log "Searching for guest tools for builder: $BuilderType"
    $volList = Get-Volume | Where-Object { $_.DriveType -ne 'Fixed' -and $_.DriveLetter }
    
    switch ($BuilderType) {
        {$_ -in 'virtualbox-iso', 'virtualbox-ovf'} {
            Write-Log "Installing VirtualBox Guest Additions..."
            
            foreach ($vol in $volList) {
                $letter = $vol.DriveLetter
                $exe = "${letter}:\VBoxWindowsAdditions.exe"
                
                if (Test-Path -LiteralPath $exe) {
                    Write-Log "Found VirtualBox Guest Additions at $exe"
                    
                    try {
                        $certs = "${letter}:\cert"
                        Write-Log "Adding VirtualBox certificates..."
                        Start-Process -FilePath "${certs}\VBoxCertUtil.exe" `
                            -ArgumentList "add-trusted-publisher ${certs}\vbox*.cer --root ${certs}\vbox*.cer" `
                            -Wait -NoNewWindow
                        
                        Write-Log "Installing VirtualBox Guest Additions..."
                        Start-Process -FilePath $exe -ArgumentList '/with_wddm', '/S' -Wait -NoNewWindow
                        
                        Write-Log "VirtualBox Guest Additions installed successfully"
                        return $true
                    } catch {
                        throw "Failed to install VirtualBox Guest Additions: $($_.Exception.Message)"
                    }
                }
            }
            throw "VirtualBox Guest Additions installer not found"
        }
        
        {$_ -in 'vmware-iso', 'vmware-vmx'} {
            Write-Log "Installing VMware Tools..."
            
            $isoPath = 'C:\vmware-tools.iso'
            if (-not (Test-Path $isoPath)) {
                Write-Log "VMware Tools ISO not found at $isoPath" -Level Warning
                return $false
            }
            
            try {
                Write-Log "Mounting VMware Tools ISO..."
                Mount-DiskImage -ImagePath $isoPath -PassThru | Get-Volume | Out-Null
                Start-Sleep -Seconds 2
                
                $volList = Get-Volume | Where-Object { $_.DriveType -ne 'Fixed' -and $_.DriveLetter }
                
                foreach ($vol in $volList) {
                    $letter = $vol.DriveLetter
                    $exe = "${letter}:\setup.exe"
                    
                    if (Test-Path -LiteralPath $exe) {
                        Write-Log "Found VMware Tools at $exe"
                        
                        Write-Log "Installing VMware Tools..."
                        Start-Process -FilePath $exe -ArgumentList '/S /v "/qn REBOOT=R"' -Wait -NoNewWindow
                        
                        Write-Log "VMware Tools installed successfully"
                        
                        Dismount-DiskImage -ImagePath $isoPath
                        Remove-Item -Path $isoPath -Force
                        
                        return $true
                    }
                }
                
                Dismount-DiskImage -ImagePath $isoPath
                Remove-Item -Path $isoPath -Force
                throw "VMware Tools installer not found on ISO"
                
            } catch {
                Write-Log "Failed to install VMware Tools: $($_.Exception.Message)" -Level Error
                if (Test-Path $isoPath) {
                    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                    Remove-Item -Path $isoPath -Force -ErrorAction SilentlyContinue
                }
                throw
            }
        }
        
        {$_ -in 'parallels-iso', 'parallels-pvm'} {
            Write-Log "Installing Parallels Tools..."
            
            foreach ($vol in $volList) {
                $letter = $vol.DriveLetter
                $exe = "${letter}:\PTAgent.exe"
                
                if (Test-Path -LiteralPath $exe) {
                    Write-Log "Found Parallels Tools at $exe"
                    
                    try {
                        Write-Log "Installing Parallels Tools..."
                        Start-Process -FilePath $exe -ArgumentList '/install_silent' -Wait -NoNewWindow
                        
                        Write-Log "Parallels Tools installed successfully"
                        return $true
                    } catch {
                        throw "Failed to install Parallels Tools: $($_.Exception.Message)"
                    }
                }
            }
            throw "Parallels Tools installer not found"
        }
        
        'qemu' {
            Write-Log "Installing VirtIO Guest Tools (QEMU/KVM)..."
            
            foreach ($vol in $volList) {
                $letter = $vol.DriveLetter
                $exe = "${letter}:\virtio-win-guest-tools.exe"
                
                if (Test-Path -LiteralPath $exe) {
                    Write-Log "Found VirtIO Guest Tools at $exe"
                    
                    try {
                        Write-Log "Installing VirtIO Guest Tools..."
                        Start-Process -FilePath $exe -ArgumentList '/passive', '/norestart' -Wait -NoNewWindow
                        
                        Write-Log "VirtIO Guest Tools installed successfully"
                        return $true
                    } catch {
                        throw "Failed to install VirtIO Guest Tools: $($_.Exception.Message)"
                    }
                }
            }
            throw "VirtIO Guest Tools installer not found"
        }
        
        'hyperv-iso' {
            Write-Log "Hyper-V builder detected - using built-in integration services"
            return $true
        }
        
        default {
            throw "Unknown or unsupported PACKER_BUILDER_TYPE: $BuilderType"
        }
    }
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

try {
    Write-Log "Starting Windows VM provisioning..."
    
    # Validate prerequisites
    if (-not [Environment]::Is64BitProcess) {
        throw 'This script must run in a 64-bit PowerShell session'
    }
    
    $currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must run with Administrator privileges'
    }
    
    # Enable TLS 1.2
    Write-Log "Enabling TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12
    
    # Configure vagrant account
    Write-Log "Configuring vagrant user account..."
    try {
        # ADS_USER_FLAG_ENUM flags
        $AdsNormalAccount = 0x00200
        $AdsDontExpirePassword = 0x10000
        
        $account = [ADSI]'WinNT://./vagrant'
        $account.Userflags = $AdsNormalAccount -bor $AdsDontExpirePassword
        $account.SetInfo()
        Write-Log "Vagrant account configured successfully"
    } catch {
        Write-Log "Failed to configure vagrant account: $($_.Exception.Message)" -Level Warning
    }
    
    # Configure Administrator account
    Write-Log "Configuring Administrator account (disable and set password to never expire)..."
    try {
        $AdsAccountDisable = 0x00002
        
        $account = [ADSI]'WinNT://./Administrator'
        $account.Userflags = $AdsNormalAccount -bor $AdsDontExpirePassword -bor $AdsAccountDisable
        $account.SetInfo()
        Write-Log "Administrator account configured successfully"
    } catch {
        Write-Log "Failed to configure Administrator account: $($_.Exception.Message)" -Level Warning
    }
    
    # Network configuration
    Write-Log "Disabling Automatic Private IP Addressing (APIPA)..."
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
        -Name IPAutoconfigurationEnabled -Value 0
    
    Write-Log "Disabling IPv6..."
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' `
        -Name DisabledComponents -Value 0xff
    
    # Boot manager configuration
    Write-Log "Disabling Windows Boot Manager menu..."
    & bcdedit.exe /set '{bootmgr}' displaybootmenu no | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to disable boot menu (exit code: $LASTEXITCODE)" -Level Warning
    }
    
    # Install guest tools
    $builderType = $env:PACKER_BUILDER_TYPE
    if ([string]::IsNullOrEmpty($builderType)) {
        Write-Log "PACKER_BUILDER_TYPE not set - skipping guest tools installation" -Level Warning
    } else {
        try {
            $installed = Install-GuestTools -BuilderType $builderType
            if ($installed) {
                Write-Log "Guest tools installation completed successfully"
            }
        } catch {
            Write-Log "Guest tools installation failed: $($_.Exception.Message)" -Level Error
            throw
        }
    }
    
    Write-Log "Windows VM provisioning completed successfully"
    Write-Log "System may require a restart to complete guest tools installation"
    
} catch {
    Write-Log "Provisioning failed: $($_.Exception.Message)" -Level Error
    exit 1
}