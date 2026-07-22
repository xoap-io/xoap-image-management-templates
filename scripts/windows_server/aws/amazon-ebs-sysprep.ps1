<#
.SYNOPSIS
    Run AWS EC2Launch Sysprep for AMI Preparation

.DESCRIPTION
    Executes AWS EC2Launch sysprep to prepare Windows instance for AMI creation.
    Configures EC2 instance for first boot, handles user data, and prepares
    Windows for imaging without automatic shutdown.
    
    This script is specifically designed for AWS EC2 AMI creation workflows
    using Packer or other automated image building tools.

.NOTES
    File Name      : amazon-ebs-sysprep.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges, EC2Launch installed
    Copyright      : XOAP.io
    
.PARAMETER Shutdown
    Whether to shutdown after sysprep. Default: False

.PARAMETER VerifyOnly
    Only verify EC2Launch installation without running sysprep

.EXAMPLE
    .\amazon-ebs-sysprep.ps1
    Runs EC2Launch sysprep without automatic shutdown

.EXAMPLE
    .\amazon-ebs-sysprep.ps1 -Shutdown
    Runs EC2Launch sysprep with automatic shutdown

.EXAMPLE
    .\amazon-ebs-sysprep.ps1 -VerifyOnly
    Verifies EC2Launch installation without running sysprep

.LINK
    https://github.com/xoap-io/xoap-image-management-templates
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Shutdown after sysprep completion')]
    [switch]$Shutdown,

    [Parameter(HelpMessage = 'Verify EC2Launch installation only')]
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [EC2Sysprep] Transcript unavailable: $($_.Exception.Message)" }

# EC2Launch paths
$EC2LaunchExe = "$env:ProgramFiles\Amazon\EC2Launch\EC2Launch.exe"
$EC2LaunchV2Service = 'AmazonEC2Launch'

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [EC2Sysprep] $Message"
    Write-Host $logMessage
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# Main execution
try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    Write-Log "===== amazon-ebs-sysprep starting ====="
    
    Write-Log "========================================================="
    Write-Log "AWS EC2Launch Sysprep"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log "Shutdown: $Shutdown"
    Write-Log "VerifyOnly: $VerifyOnly"
    Write-Log ""
    
    # Detect EC2 environment
    Write-Log "Verifying EC2 environment..."
    
    $isEC2 = $false
    try {
        $metadata = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id' -TimeoutSec 2 -ErrorAction Stop
        if ($metadata) {
            Write-Log "[OK] Running on EC2 instance: $metadata"
            $isEC2 = $true
        }
    }
    catch {
        Write-Log "Warning: Not running on EC2 instance" -Level WARN
    }
    
    # Check for EC2Launch v2 (newer version)
    Write-Log "Checking for EC2Launch version..."
    
    $ec2LaunchV2 = Get-Service -Name $EC2LaunchV2Service -ErrorAction SilentlyContinue
    
    if ($ec2LaunchV2) {
        Write-Log "[OK] EC2Launch v2 detected"
        Write-Log "  Status: $($ec2LaunchV2.Status)"
        Write-Log "  DisplayName: $($ec2LaunchV2.DisplayName)"
        
        if ($VerifyOnly) {
            Write-Log "Verification complete. EC2Launch v2 is installed."
            try { Stop-Transcript | Out-Null } catch {}
            exit 0
        }
        
        Write-Log ""
        Write-Log "Note: EC2Launch v2 uses different sysprep mechanism"
        Write-Log "Configuring EC2Launch v2 for sysprep..."
        
        # EC2Launch v2 configuration
        $configPath = "$env:ProgramData\Amazon\EC2Launch\config\agent-config.yml"
        if (Test-Path $configPath) {
            Write-Log "[OK] Found EC2Launch v2 configuration: $configPath"
        }
        
        # For EC2Launch v2, sysprep is handled via instance metadata
        Write-Log "EC2Launch v2 sysprep will be triggered automatically on first boot"
        Write-Log "Ensure agent-config.yml is properly configured"
        
        try { Stop-Transcript | Out-Null } catch {}
        exit 0
    }
    
    # Check for EC2Launch v1
    if (-not (Test-Path $EC2LaunchExe)) {
        Write-Log "EC2Launch executable not found at: $EC2LaunchExe" -Level ERROR
        Write-Log "Checking alternate locations..." -Level WARN
        
        # Check for EC2Config (legacy)
        $ec2ConfigExe = "$env:ProgramFiles\Amazon\Ec2ConfigService\ec2config.exe"
        if (Test-Path $ec2ConfigExe) {
            Write-Log "Found legacy EC2Config service" -Level WARN
            Write-Log "Consider upgrading to EC2Launch or EC2Launch v2" -Level WARN
            
            if ($VerifyOnly) {
                Write-Log "Verification complete. EC2Config (legacy) is installed."
                try { Stop-Transcript | Out-Null } catch {}
                exit 0
            }
            
            throw "EC2Config is deprecated. Please use EC2Launch or EC2Launch v2"
        }
        
        throw "No EC2Launch installation found. Cannot proceed with sysprep."
    }
    
    Write-Log "[OK] EC2Launch v1 found: $EC2LaunchExe"
    
    if ($VerifyOnly) {
        Write-Log "Verification complete. EC2Launch v1 is installed."
        
        # Check version
        if (Test-Path $EC2LaunchExe) {
            $version = (Get-Item $EC2LaunchExe).VersionInfo.FileVersion
            Write-Log "Version: $version"
        }
        
        try { Stop-Transcript | Out-Null } catch {}
        exit 0
    }
    
    # Run sysprep
    Write-Log ""
    Write-Log "Executing EC2Launch sysprep..."
    
    $shutdownParam = if ($Shutdown) { '--shutdown=true' } else { '--shutdown=false' }
    
    Write-Log "Command: $EC2LaunchExe sysprep $shutdownParam"
    
    $process = Start-Process -FilePath $EC2LaunchExe `
        -ArgumentList "sysprep", $shutdownParam `
        -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Log "[OK] EC2Launch sysprep completed successfully"
    }
    else {
        throw "EC2Launch sysprep failed with exit code: $($process.ExitCode)"
    }
    
    # Verify sysprep artifacts
    Write-Log ""
    Write-Log "Verifying sysprep configuration..."
    
    $sysprepPath = "$env:SystemRoot\System32\Sysprep\Unattend.xml"
    if (Test-Path $sysprepPath) {
        Write-Log "[OK] Sysprep unattend file created: $sysprepPath"
    }
    else {
        Write-Log "Warning: Sysprep unattend file not found" -Level WARN
    }
    
    # Check EC2Launch configuration
    $ec2ConfigPath = "$env:ProgramData\Amazon\EC2-Windows\Launch\Config\LaunchConfig.json"
    if (Test-Path $ec2ConfigPath) {
        Write-Log "[OK] EC2Launch configuration exists: $ec2ConfigPath"
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "EC2Launch Sysprep Summary"
    Write-Log "========================================================="
    Write-Log "EC2 Instance: $isEC2"
    Write-Log "Sysprep completed: Yes"
    Write-Log "Shutdown scheduled: $Shutdown"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    if ($Shutdown) {
        Write-Log ""
        Write-Log "System shutdown initiated by EC2Launch..."
    }
    else {
        Write-Log ""
        Write-Log "Sysprep completed. Instance is ready for AMI creation."
        Write-Log "Remember to shutdown the instance before creating the AMI."
    }
    
    Write-Log "===== amazon-ebs-sysprep complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
} catch {
    Write-Log "Sysprep failed: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
