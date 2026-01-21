<#
.SYNOPSIS
    Install AWS Tools and Agents for EC2 Instances

.DESCRIPTION
    Installs essential AWS tools and agents on Windows EC2 instances including:
    - AWS CLI v2
    - AWS Systems Manager (SSM) Agent
    - Amazon CloudWatch Agent
    - AWS Tools for PowerShell
    
    Verifies installation and configures services for optimal EC2 operation.

.NOTES
    File Name      : Install_AWS_Tools.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER InstallCLI
    Install AWS CLI v2

.PARAMETER InstallSSM
    Install AWS Systems Manager Agent

.PARAMETER InstallCloudWatch
    Install Amazon CloudWatch Agent

.PARAMETER InstallPowerShell
    Install AWS Tools for PowerShell

.PARAMETER SkipVerification
    Skip post-installation verification

.EXAMPLE
    .\Install_AWS_Tools.ps1
    Installs all AWS tools with default settings

.EXAMPLE
    .\Install_AWS_Tools.ps1 -InstallCLI -InstallSSM
    Installs only AWS CLI and SSM Agent

.EXAMPLE
    .\Install_AWS_Tools.ps1 -InstallCloudWatch -SkipVerification
    Installs CloudWatch Agent without verification

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = 'Install AWS CLI v2')]
    [switch]$InstallCLI,

    [Parameter(HelpMessage = 'Install AWS Systems Manager Agent')]
    [switch]$InstallSSM,

    [Parameter(HelpMessage = 'Install Amazon CloudWatch Agent')]
    [switch]$InstallCloudWatch,

    [Parameter(HelpMessage = 'Install AWS Tools for PowerShell')]
    [switch]$InstallPowerShell,

    [Parameter(HelpMessage = 'Skip post-installation verification')]
    [switch]$SkipVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = 'aws-tools-install'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
$TempDir = Join-Path $env:TEMP "aws-install-$timestamp"

# Statistics
$script:InstallationsCompleted = 0
$script:InstallationsFailed = 0

# Logging function
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
    $logMessage = "[$timestamp] [$prefix] [AWSTools] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

trap {
    Write-Log "Critical error: $_" -Level Error
    exit 1
}

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    Write-Log "========================================================="
    Write-Log "AWS Tools and Agents Installation"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log ""
    
    # If no specific tool selected, install all
    if (-not ($InstallCLI -or $InstallSSM -or $InstallCloudWatch -or $InstallPowerShell)) {
        $InstallCLI = $true
        $InstallSSM = $true
        $InstallCloudWatch = $true
        $InstallPowerShell = $true
        Write-Log "No specific tools selected - installing all AWS tools"
    }
    
    # Detect EC2 environment
    Write-Log "Detecting EC2 environment..."
    $isEC2 = $false
    try {
        $instanceId = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id' -TimeoutSec 2 -ErrorAction Stop
        Write-Log "✓ Running on EC2 instance: $instanceId"
        $isEC2 = $true
    }
    catch {
        Write-Log "Warning: Not running on EC2 instance" -Level Warning
    }
    
    # Install AWS CLI v2
    if ($InstallCLI) {
        Write-Log ""
        Write-Log "Installing AWS CLI v2..."
        
        $cliPath = "${env:ProgramFiles}\Amazon\AWSCLIV2\aws.exe"
        if (Test-Path $cliPath) {
            $version = & $cliPath --version 2>&1
            Write-Log "AWS CLI already installed: $version"
        }
        else {
            try {
                $cliInstaller = Join-Path $TempDir 'AWSCLIV2.msi'
                $cliUrl = 'https://awscli.amazonaws.com/AWSCLIV2.msi'
                
                Write-Log "Downloading AWS CLI from: $cliUrl"
                Invoke-WebRequest -Uri $cliUrl -OutFile $cliInstaller -UseBasicParsing
                
                Write-Log "Installing AWS CLI..."
                $process = Start-Process -FilePath 'msiexec.exe' `
                    -ArgumentList "/i `"$cliInstaller`" /qn /norestart" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ AWS CLI installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "AWS CLI installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "AWS CLI installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install SSM Agent
    if ($InstallSSM) {
        Write-Log ""
        Write-Log "Installing AWS Systems Manager Agent..."
        
        $ssmService = Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue
        if ($ssmService) {
            Write-Log "SSM Agent already installed: $($ssmService.Status)"
            if ($ssmService.Status -ne 'Running') {
                Start-Service -Name 'AmazonSSMAgent'
                Write-Log "✓ Started SSM Agent service"
            }
        }
        else {
            try {
                $ssmInstaller = Join-Path $TempDir 'SSMAgent.exe'
                $ssmUrl = 'https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe'
                
                Write-Log "Downloading SSM Agent from: $ssmUrl"
                Invoke-WebRequest -Uri $ssmUrl -OutFile $ssmInstaller -UseBasicParsing
                
                Write-Log "Installing SSM Agent..."
                $process = Start-Process -FilePath $ssmInstaller `
                    -ArgumentList '/S' `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ SSM Agent installed successfully"
                    
                    Start-Sleep -Seconds 5
                    $ssmService = Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue
                    if ($ssmService -and $ssmService.Status -eq 'Running') {
                        Write-Log "✓ SSM Agent service is running"
                    }
                    
                    $script:InstallationsCompleted++
                }
                else {
                    throw "SSM Agent installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "SSM Agent installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install CloudWatch Agent
    if ($InstallCloudWatch) {
        Write-Log ""
        Write-Log "Installing Amazon CloudWatch Agent..."
        
        $cwService = Get-Service -Name 'AmazonCloudWatchAgent' -ErrorAction SilentlyContinue
        if ($cwService) {
            Write-Log "CloudWatch Agent already installed: $($cwService.Status)"
        }
        else {
            try {
                $cwInstaller = Join-Path $TempDir 'CloudWatchAgent.msi'
                $cwUrl = 'https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi'
                
                Write-Log "Downloading CloudWatch Agent from: $cwUrl"
                Invoke-WebRequest -Uri $cwUrl -OutFile $cwInstaller -UseBasicParsing
                
                Write-Log "Installing CloudWatch Agent..."
                $process = Start-Process -FilePath 'msiexec.exe' `
                    -ArgumentList "/i `"$cwInstaller`" /qn /norestart" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ CloudWatch Agent installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "CloudWatch Agent installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "CloudWatch Agent installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install AWS Tools for PowerShell
    if ($InstallPowerShell) {
        Write-Log ""
        Write-Log "Installing AWS Tools for PowerShell..."
        
        try {
            $awsModule = Get-Module -ListAvailable -Name 'AWS.Tools.Common' -ErrorAction SilentlyContinue
            if ($awsModule) {
                Write-Log "AWS Tools for PowerShell already installed: $($awsModule.Version)"
            }
            else {
                Write-Log "Installing AWSPowerShell.NetCore module..."
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
                Install-Module -Name AWSPowerShell.NetCore -Force -AllowClobber -Scope AllUsers
                Write-Log "✓ AWS Tools for PowerShell installed successfully"
                $script:InstallationsCompleted++
            }
        }
        catch {
            Write-Log "AWS Tools for PowerShell installation failed: $($_.Exception.Message)" -Level Error
            $script:InstallationsFailed++
        }
    }
    
    # Verification
    if (-not $SkipVerification) {
        Write-Log ""
        Write-Log "Verifying installations..."
        
        # Verify AWS CLI
        if ($InstallCLI) {
            $cliPath = "${env:ProgramFiles}\Amazon\AWSCLIV2\aws.exe"
            if (Test-Path $cliPath) {
                $version = & $cliPath --version 2>&1
                Write-Log "✓ AWS CLI: $version"
            }
            else {
                Write-Log "✗ AWS CLI not found" -Level Warning
            }
        }
        
        # Verify SSM Agent
        if ($InstallSSM) {
            $ssmService = Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue
            if ($ssmService) {
                Write-Log "✓ SSM Agent: $($ssmService.Status)"
            }
            else {
                Write-Log "✗ SSM Agent not found" -Level Warning
            }
        }
        
        # Verify CloudWatch Agent
        if ($InstallCloudWatch) {
            $cwService = Get-Service -Name 'AmazonCloudWatchAgent' -ErrorAction SilentlyContinue
            if ($cwService) {
                Write-Log "✓ CloudWatch Agent: $($cwService.Status)"
            }
            else {
                Write-Log "✗ CloudWatch Agent not found" -Level Warning
            }
        }
        
        # Verify PowerShell Module
        if ($InstallPowerShell) {
            $awsModule = Get-Module -ListAvailable -Name 'AWSPowerShell.NetCore' -ErrorAction SilentlyContinue
            if ($awsModule) {
                Write-Log "✓ AWS PowerShell: $($awsModule.Version)"
            }
            else {
                Write-Log "✗ AWS PowerShell module not found" -Level Warning
            }
        }
    }
    
    # Cleanup
    Write-Log ""
    Write-Log "Cleaning up temporary files..."
    try {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "✓ Cleanup completed"
    }
    catch {
        Write-Log "Cleanup failed: $($_.Exception.Message)" -Level Warning
    }
    
    # Summary
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "AWS Tools Installation Summary"
    Write-Log "========================================================="
    Write-Log "EC2 Instance: $isEC2"
    Write-Log "Installations completed: $script:InstallationsCompleted"
    Write-Log "Installation failures: $script:InstallationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
    if ($script:InstallationsFailed -eq 0) {
        Write-Log "✓ All AWS tools installed successfully"
    }
    else {
        Write-Log "Warning: Some installations failed" -Level Warning
    }
    
} catch {
    Write-Log "Installation failed: $_" -Level Error
    exit 1
}
