<#
.SYNOPSIS
    Install Azure VM Agent and Tools

.DESCRIPTION
    Installs essential Azure tools and agents on Windows VMs including:
    - Azure VM Agent
    - Azure CLI
    - Azure PowerShell Modules
    - Azure Monitor Agent
    
    Verifies installation and configures services for optimal Azure operation.

.NOTES
    File Name      : Install_Azure_Tools.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.PARAMETER InstallVMAgent
    Install Azure VM Agent

.PARAMETER InstallCLI
    Install Azure CLI

.PARAMETER InstallPowerShell
    Install Azure PowerShell Modules

.PARAMETER InstallMonitor
    Install Azure Monitor Agent

.EXAMPLE
    .\Install_Azure_Tools.ps1
    Installs all Azure tools with default settings

.EXAMPLE
    .\Install_Azure_Tools.ps1 -InstallVMAgent -InstallCLI
    Installs only Azure VM Agent and CLI

.LINK
    https://github.com/xoap-io/xoap-packer-templates
#>

[CmdletBinding()]
param (
    [switch]$InstallVMAgent,
    [switch]$InstallCLI,
    [switch]$InstallPowerShell,
    [switch]$InstallMonitor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogDir = 'C:\xoap-logs'
$scriptName = 'azure-tools-install'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
$TempDir = Join-Path $env:TEMP "azure-install-$timestamp"

$script:InstallationsCompleted = 0
$script:InstallationsFailed = 0

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
    $logMessage = "[$timestamp] [$prefix] [AzureTools] $Message"
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
    Write-Log "Azure Tools and Agents Installation"
    Write-Log "========================================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log ""
    
    # If no specific tool selected, install all
    if (-not ($InstallVMAgent -or $InstallCLI -or $InstallPowerShell -or $InstallMonitor)) {
        $InstallVMAgent = $true
        $InstallCLI = $true
        $InstallPowerShell = $true
        $InstallMonitor = $true
        Write-Log "No specific tools selected - installing all Azure tools"
    }
    
    # Detect Azure environment
    Write-Log "Detecting Azure environment..."
    $isAzure = $false
    try {
        $metadata = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
            -Headers @{Metadata='true'} -TimeoutSec 2 -ErrorAction Stop
        Write-Log "✓ Running on Azure VM: $($metadata.compute.vmId)"
        Write-Log "  Location: $($metadata.compute.location)"
        Write-Log "  VM Size: $($metadata.compute.vmSize)"
        $isAzure = $true
    }
    catch {
        Write-Log "Warning: Not running on Azure VM" -Level Warning
    }
    
    # Install Azure VM Agent
    if ($InstallVMAgent) {
        Write-Log ""
        Write-Log "Installing Azure VM Agent..."
        
        $vmAgentPath = "${env:ProgramFiles}\WindowsAzure\GuestAgent"
        if (Test-Path $vmAgentPath) {
            Write-Log "Azure VM Agent already installed"
            
            $waService = Get-Service -Name 'WindowsAzureGuestAgent' -ErrorAction SilentlyContinue
            if ($waService) {
                Write-Log "  Status: $($waService.Status)"
                if ($waService.Status -ne 'Running') {
                    Start-Service -Name 'WindowsAzureGuestAgent'
                    Write-Log "✓ Started VM Agent service"
                }
            }
        }
        else {
            try {
                $vmAgentInstaller = Join-Path $TempDir 'VMAgent.msi'
                $vmAgentUrl = 'https://go.microsoft.com/fwlink/?LinkID=394789'
                
                Write-Log "Downloading Azure VM Agent..."
                Invoke-WebRequest -Uri $vmAgentUrl -OutFile $vmAgentInstaller -UseBasicParsing
                
                Write-Log "Installing Azure VM Agent..."
                $process = Start-Process -FilePath 'msiexec.exe' `
                    -ArgumentList "/i `"$vmAgentInstaller`" /qn /norestart" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ Azure VM Agent installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "VM Agent installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "VM Agent installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install Azure CLI
    if ($InstallCLI) {
        Write-Log ""
        Write-Log "Installing Azure CLI..."
        
        $azPath = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
        if (Test-Path $azPath) {
            $version = & $azPath version --output json 2>&1 | ConvertFrom-Json
            Write-Log "Azure CLI already installed: $($version.'azure-cli')"
        }
        else {
            try {
                $cliInstaller = Join-Path $TempDir 'AzureCLI.msi'
                $cliUrl = 'https://aka.ms/installazurecliwindows'
                
                Write-Log "Downloading Azure CLI..."
                Invoke-WebRequest -Uri $cliUrl -OutFile $cliInstaller -UseBasicParsing
                
                Write-Log "Installing Azure CLI..."
                $process = Start-Process -FilePath 'msiexec.exe' `
                    -ArgumentList "/i `"$cliInstaller`" /qn /norestart" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ Azure CLI installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "Azure CLI installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "Azure CLI installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Install Azure PowerShell
    if ($InstallPowerShell) {
        Write-Log ""
        Write-Log "Installing Azure PowerShell Modules..."
        
        try {
            $azModule = Get-Module -ListAvailable -Name 'Az.Accounts' -ErrorAction SilentlyContinue
            if ($azModule) {
                Write-Log "Azure PowerShell already installed: $($azModule.Version)"
            }
            else {
                Write-Log "Installing Az PowerShell module..."
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
                Install-Module -Name Az -Force -AllowClobber -Scope AllUsers
                Write-Log "✓ Azure PowerShell installed successfully"
                $script:InstallationsCompleted++
            }
        }
        catch {
            Write-Log "Azure PowerShell installation failed: $($_.Exception.Message)" -Level Error
            $script:InstallationsFailed++
        }
    }
    
    # Install Azure Monitor Agent
    if ($InstallMonitor) {
        Write-Log ""
        Write-Log "Installing Azure Monitor Agent..."
        
        $amaService = Get-Service -Name 'AzureMonitorAgent' -ErrorAction SilentlyContinue
        if ($amaService) {
            Write-Log "Azure Monitor Agent already installed: $($amaService.Status)"
        }
        else {
            try {
                $amaInstaller = Join-Path $TempDir 'AzureMonitorAgent.msi'
                $amaUrl = 'https://aka.ms/AzureMonitorAgentWindows'
                
                Write-Log "Downloading Azure Monitor Agent..."
                Invoke-WebRequest -Uri $amaUrl -OutFile $amaInstaller -UseBasicParsing
                
                Write-Log "Installing Azure Monitor Agent..."
                $process = Start-Process -FilePath 'msiexec.exe' `
                    -ArgumentList "/i `"$amaInstaller`" /qn /norestart" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "✓ Azure Monitor Agent installed successfully"
                    $script:InstallationsCompleted++
                }
                else {
                    throw "Monitor Agent installation failed with exit code: $($process.ExitCode)"
                }
            }
            catch {
                Write-Log "Monitor Agent installation failed: $($_.Exception.Message)" -Level Error
                $script:InstallationsFailed++
            }
        }
    }
    
    # Verification
    Write-Log ""
    Write-Log "Verifying installations..."
    
    if ($InstallVMAgent) {
        $waService = Get-Service -Name 'WindowsAzureGuestAgent' -ErrorAction SilentlyContinue
        if ($waService) {
            Write-Log "✓ Azure VM Agent: $($waService.Status)"
        }
    }
    
    if ($InstallCLI) {
        $azPath = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
        if (Test-Path $azPath) {
            Write-Log "✓ Azure CLI: Installed"
        }
    }
    
    if ($InstallPowerShell) {
        $azModule = Get-Module -ListAvailable -Name 'Az.Accounts' -ErrorAction SilentlyContinue
        if ($azModule) {
            Write-Log "✓ Azure PowerShell: $($azModule.Version)"
        }
    }
    
    if ($InstallMonitor) {
        $amaService = Get-Service -Name 'AzureMonitorAgent' -ErrorAction SilentlyContinue
        if ($amaService) {
            Write-Log "✓ Azure Monitor Agent: $($amaService.Status)"
        }
    }
    
    # Cleanup
    Write-Log ""
    Write-Log "Cleaning up..."
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Log ""
    Write-Log "========================================================="
    Write-Log "Azure Tools Installation Summary"
    Write-Log "========================================================="
    Write-Log "Azure VM: $isAzure"
    Write-Log "Installations completed: $script:InstallationsCompleted"
    Write-Log "Installation failures: $script:InstallationsFailed"
    Write-Log "Execution time: $([math]::Round($duration, 2))s"
    Write-Log "========================================================="
    
} catch {
    Write-Log "Installation failed: $_" -Level Error
    exit 1
}
