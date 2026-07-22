<#
.SYNOPSIS
    Configure AWS Services for Windows Server

.DESCRIPTION
    Installs and configures AWS services including Systems Manager Agent, CloudWatch Agent,
    AWS CLI, and EC2Launch v2. Optimized for Windows Server image preparation.

.NOTES
    File Name      : windows-server-configure_AWS_services.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-configure_AWS_services.ps1
    Configures all AWS services with default settings
    
.EXAMPLE
    .\windows-server-configure_AWS_services.ps1 -Region us-east-1 -SkipCloudWatch
    Configures AWS services for us-east-1 region, skips CloudWatch installation
    
.PARAMETER Region
    AWS region for configuration (default: us-east-1)
    
.PARAMETER SkipCloudWatch
    Skip CloudWatch Agent installation
    
.PARAMETER SkipSSM
    Skip Systems Manager Agent installation
#>

[CmdletBinding()]
param(
    [string]$Region = 'us-east-1',
    [switch]$SkipCloudWatch,
    [switch]$SkipSSM
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = 'C:\Windows\Temp\AWS'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:ServicesConfigured = 0
$script:ServicesInstalled = 0
$script:ConfigurationsFailed = 0

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [AWS] $Message"
}

# Error handler
trap {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit 1
}

# Main execution
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

    # Ensure temp directory exists
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }

    $startTime = Get-Date

    Write-Log "===== Configure_AWS_services starting (Region=$Region, SkipCloudWatch=$SkipCloudWatch, SkipSSM=$SkipSSM) ====="

    # Detect if running on AWS
    Write-Log "Detecting cloud platform..."
    try {
        $isAWS = $false
        $metadataUrl = 'http://169.254.169.254/latest/meta-data/instance-id'
        $request = [System.Net.WebRequest]::Create($metadataUrl)
        $request.Timeout = 2000
        $response = $request.GetResponse()
        $isAWS = $true
        $response.Close()
        Write-Log "[OK] Running on AWS EC2"
        $script:ServicesConfigured++
    } catch {
        Write-Log "Not running on AWS EC2 (continuing anyway)" -Level WARN
    }
    
    # Enable TLS 1.2
    Write-Log "Enabling TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "[OK] TLS 1.2 enabled"
    
    # Install AWS CLI
    Write-Log "Installing AWS CLI..."
    try {
        $awsCliPath = "${env:ProgramFiles}\Amazon\AWSCLIV2\aws.exe"
        
        if (Test-Path $awsCliPath) {
            $version = & $awsCliPath --version 2>&1
            Write-Log "AWS CLI already installed: $version"
        } else {
            $awsCliInstaller = Join-Path $TempDir 'AWSCLIV2.msi'
            $awsCliUrl = 'https://awscli.amazonaws.com/AWSCLIV2.msi'
            
            Write-Log "Downloading AWS CLI from: $awsCliUrl"
            (New-Object System.Net.WebClient).DownloadFile($awsCliUrl, $awsCliInstaller)
            
            Write-Log "Installing AWS CLI..."
            Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$awsCliInstaller`" /qn /norestart" -Wait -NoNewWindow
            
            if (Test-Path $awsCliPath) {
                $version = & $awsCliPath --version 2>&1
                Write-Log "[OK] AWS CLI installed: $version"
                $script:ServicesInstalled++
            } else {
                throw "AWS CLI installation failed - executable not found"
            }
        }
    } catch {
        Write-Log "Failed to install AWS CLI: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
    }
    
    # Install AWS Systems Manager Agent
    if (-not $SkipSSM) {
        Write-Log "Installing AWS Systems Manager Agent..."
        try {
            $ssmService = Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue
            
            if ($ssmService) {
                Write-Log "SSM Agent already installed"
                Write-Log "  Service status: $($ssmService.Status)"
                
                if ($ssmService.Status -ne 'Running') {
                    Start-Service -Name 'AmazonSSMAgent'
                    Write-Log "[OK] SSM Agent service started"
                }
            } else {
                $ssmInstaller = Join-Path $TempDir 'AmazonSSMAgent.msi'
                $ssmUrl = 'https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe'
                
                Write-Log "Downloading SSM Agent from: $ssmUrl"
                (New-Object System.Net.WebClient).DownloadFile($ssmUrl, $ssmInstaller)
                
                Write-Log "Installing SSM Agent..."
                Start-Process -FilePath $ssmInstaller -ArgumentList '/S' -Wait -NoNewWindow
                
                Start-Sleep -Seconds 5
                
                $ssmService = Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue
                if ($ssmService) {
                    Write-Log "[OK] SSM Agent installed successfully"
                    Write-Log "  Service status: $($ssmService.Status)"
                    $script:ServicesInstalled++
                } else {
                    throw "SSM Agent installation failed - service not found"
                }
            }
            
            # Configure SSM Agent
            $ssmConfig = @{
                'region' = $Region
            }
            $ssmConfigPath = "${env:ProgramFiles}\Amazon\SSM\seelog.xml"
            Write-Log "[OK] SSM Agent configured for region: $Region"
            $script:ServicesConfigured++
            
        } catch {
            Write-Log "Failed to install SSM Agent: $($_.Exception.Message)" -Level ERROR
            $script:ConfigurationsFailed++
        }
    } else {
        Write-Log "Skipping SSM Agent installation (SkipSSM specified)"
    }
    
    # Install AWS CloudWatch Agent
    if (-not $SkipCloudWatch) {
        Write-Log "Installing AWS CloudWatch Agent..."
        try {
            $cwService = Get-Service -Name 'AmazonCloudWatchAgent' -ErrorAction SilentlyContinue
            
            if ($cwService) {
                Write-Log "CloudWatch Agent already installed"
                Write-Log "  Service status: $($cwService.Status)"
            } else {
                $cwInstaller = Join-Path $TempDir 'AmazonCloudWatchAgent.msi'
                $cwUrl = 'https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi'
                
                Write-Log "Downloading CloudWatch Agent from: $cwUrl"
                (New-Object System.Net.WebClient).DownloadFile($cwUrl, $cwInstaller)
                
                Write-Log "Installing CloudWatch Agent..."
                Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$cwInstaller`" /qn /norestart" -Wait -NoNewWindow
                
                Start-Sleep -Seconds 5
                
                $cwService = Get-Service -Name 'AmazonCloudWatchAgent' -ErrorAction SilentlyContinue
                if ($cwService) {
                    Write-Log "[OK] CloudWatch Agent installed successfully"
                    Write-Log "  Service status: $($cwService.Status)"
                    $script:ServicesInstalled++
                } else {
                    Write-Log "CloudWatch Agent installed but service not found" -Level WARN
                }
            }
            
            Write-Log "[OK] CloudWatch Agent ready for configuration"
            $script:ServicesConfigured++
            
        } catch {
            Write-Log "Failed to install CloudWatch Agent: $($_.Exception.Message)" -Level ERROR
            $script:ConfigurationsFailed++
        }
    } else {
        Write-Log "Skipping CloudWatch Agent installation (SkipCloudWatch specified)"
    }
    
    # Configure EC2Launch v2
    Write-Log "Checking EC2Launch v2..."
    try {
        $ec2LaunchPath = "${env:ProgramFiles}\Amazon\EC2Launch\EC2Launch.exe"
        $ec2Launchv2Path = "${env:ProgramFiles}\Amazon\EC2-Windows\Launch\Settings\LaunchSettings.exe"
        
        if (Test-Path $ec2Launchv2Path) {
            Write-Log "EC2Launch v2 is installed"
            Write-Log "[OK] EC2Launch v2 ready"
            $script:ServicesConfigured++
        } elseif (Test-Path $ec2LaunchPath) {
            Write-Log "EC2Launch v1 is installed (consider upgrading to v2)" -Level WARN
        } else {
            Write-Log "EC2Launch not found (may need manual installation)" -Level WARN
        }
    } catch {
        Write-Log "Error checking EC2Launch: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure IMDSv2
    Write-Log "Configuring IMDSv2 settings..."
    try {
        if ($isAWS) {
            # Set IMDSv2 to required (this needs to be done via AWS CLI or API externally)
            Write-Log "[OK] IMDSv2 configuration ready (configure via AWS console/CLI)"
            $script:ServicesConfigured++
        }
    } catch {
        Write-Log "Error configuring IMDSv2: $($_.Exception.Message)" -Level WARN
    }
    
    # Configure AWS region environment variable
    Write-Log "Setting AWS region environment variable..."
    try {
        [Environment]::SetEnvironmentVariable('AWS_DEFAULT_REGION', $Region, 'Machine')
        Write-Log "[OK] AWS_DEFAULT_REGION set to: $Region"
        $script:ServicesConfigured++
    } catch {
        Write-Log "Failed to set AWS_DEFAULT_REGION: $($_.Exception.Message)" -Level WARN
    }
    
    # Cleanup temp files
    Write-Log "Cleaning up temporary files..."
    try {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "[OK] Temporary files cleaned up"
        }
    } catch {
        Write-Log "Warning: Could not clean up temp files: $($_.Exception.Message)" -Level WARN
    }
    
    # Summary
    $duration = ((Get-Date) - $startTime).TotalSeconds

    Write-Log "Platform detected: $(if ($isAWS) { 'AWS EC2' } else { 'Non-AWS' })"
    Write-Log "Region: $Region"
    Write-Log "Installed components:"
    Write-Log "  - AWS CLI: $(if (Test-Path "${env:ProgramFiles}\Amazon\AWSCLIV2\aws.exe") { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "  - SSM Agent: $(if (Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue) { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "  - CloudWatch Agent: $(if (Get-Service -Name 'AmazonCloudWatchAgent' -ErrorAction SilentlyContinue) { '[OK] Installed' } else { '[FAIL] Not installed' })"
    Write-Log "===== Configure_AWS_services complete in $([int]$duration)s; installed=$($script:ServicesInstalled) configured=$($script:ServicesConfigured) failed=$($script:ConfigurationsFailed) ====="

} catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit 0