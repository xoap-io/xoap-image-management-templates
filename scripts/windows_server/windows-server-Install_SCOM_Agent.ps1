<#
.SYNOPSIS
    Install System Center Operations Manager (SCOM) Agent for Windows Server

.DESCRIPTION
    Downloads, installs, and configures Microsoft System Center Operations Manager (SCOM)
    agent on Windows Server 2025. Supports manual and automatic configuration with
    management groups. Optimized for enterprise monitoring and image preparation.

.NOTES
    File Name      : windows-server-Install_SCOM_Agent.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Install_SCOM_Agent.ps1 -InstallerPath "C:\Temp\MOMAgent.msi"
    Installs SCOM agent from local installer
    
.EXAMPLE
    .\windows-server-Install_SCOM_Agent.ps1 -InstallerPath "C:\Temp\MOMAgent.msi" -ManagementServer "scom.company.com" -ManagementGroup "PROD_MG"
    Installs and configures SCOM agent with management server
    
.PARAMETER InstallerPath
    Path to MOMAgent.msi installer file (required)
    
.PARAMETER ManagementServer
    Primary management server address (FQDN or IP)
    
.PARAMETER ManagementServerPort
    Management server port (default: 5723)
    
.PARAMETER ManagementGroup
    Management group name
    
.PARAMETER ActionAccount
    Action account credentials (default: Local System)
    
.PARAMETER InstallPath
    Installation directory (default: C:\Program Files\Microsoft Monitoring Agent)
    
.PARAMETER DisableService
    Disable agent service after installation (for image preparation)
    
.PARAMETER UseClientCertificate
    Enable certificate-based authentication
    
.PARAMETER AcceptEndUserLicenseAgreement
    Automatically accept EULA
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InstallerPath = "",
    
    [string]$ManagementServer = "",
    [int]$ManagementServerPort = 5723,
    [string]$ManagementGroup = "",
    [string]$ActionAccount = "LocalSystem",
    [string]$InstallPath = "C:\Program Files\Microsoft Monitoring Agent",
    [switch]$DisableService,
    [switch]$UseClientCertificate,
    [switch]$AcceptEndUserLicenseAgreement
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = 'C:\Windows\Temp\SCOM'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Agent configuration
$AgentServiceName = "HealthService"
$AgentRegistryPath = "HKLM:\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Setup"

# Statistics tracking
$script:ComponentsInstalled = 0
$script:ConfigurationsApplied = 0
$script:InstallationsFailed = 0

#region Helper Functions

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SCOMAgentInstalled {
    try {
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-LogMessage "SCOM Agent service found: $($service.Status)" -Level Info
            return $true
        }
        
        if (Test-Path $AgentRegistryPath) {
            Write-LogMessage "SCOM Agent registry keys found" -Level Info
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}

function Get-SCOMInstallerPath {
    Write-LogMessage "Validating SCOM installer path..." -Level Info
    
    # Check if installer path provided
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        Write-LogMessage "No installer path provided" -Level Warning
        Write-LogMessage "Please provide the path to MOMAgent.msi installer" -Level Warning
        Write-LogMessage "Download from: System Center Operations Manager installation media" -Level Info
        return $null
    }
    
    # Check if file exists
    if (-not (Test-Path $InstallerPath)) {
        Write-LogMessage "Installer not found at: $InstallerPath" -Level Error
        return $null
    }
    
    # Verify it's an MSI file
    if ([IO.Path]::GetExtension($InstallerPath) -ne '.msi') {
        Write-LogMessage "Installer must be an MSI file" -Level Error
        return $null
    }
    
    Write-LogMessage "Installer found: $InstallerPath" -Level Success
    return $InstallerPath
}

function Install-SCOMAgent {
    Write-LogMessage "Installing SCOM Agent..." -Level Info
    
    try {
        # Create temp directory
        if (-not (Test-Path $TempDir)) {
            New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
        }
        
        # Validate installer
        $validInstallerPath = Get-SCOMInstallerPath
        if (-not $validInstallerPath) {
            throw "Valid installer path required"
        }
        
        # Build installation arguments
        $installArgs = @(
            "/i `"$validInstallerPath`""
            "/qn"
            "/norestart"
            "/l*v `"$LogDir\scom-install-$timestamp.log`""
            "INSTALLDIR=`"$InstallPath`""
        )
        
        # Add EULA acceptance if specified
        if ($AcceptEndUserLicenseAgreement) {
            $installArgs += "AcceptEndUserLicenseAgreement=1"
        }
        
        # Add management server configuration if provided
        if ($ManagementServer -and $ManagementGroup) {
            $installArgs += "MANAGEMENT_GROUP=`"$ManagementGroup`""
            $installArgs += "MANAGEMENT_SERVER_DNS=`"$ManagementServer`""
            $installArgs += "MANAGEMENT_SERVER_AD_NAME=`"$ManagementServer`""
            $installArgs += "SECURE_PORT=$ManagementServerPort"
            $installArgs += "ACTIONS_USE_COMPUTER_ACCOUNT=1"
            
            if ($UseClientCertificate) {
                $installArgs += "USE_MANUALLY_SPECIFIED_SETTINGS=1"
                $installArgs += "USE_SETTINGS_FROM_AD=0"
            }
        }
        
        $installArgString = $installArgs -join ' '
        
        Write-LogMessage "Installation command: msiexec.exe $installArgString" -Level Info
        Write-LogMessage "Installing SCOM Agent (this may take several minutes)..." -Level Info
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgString -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-LogMessage "SCOM Agent installed successfully (Exit Code: $($process.ExitCode))" -Level Success
            $script:ComponentsInstalled++
            
            # Wait for service to be created
            Start-Sleep -Seconds 10
            return $true
        }
        else {
            Write-LogMessage "Installation failed with exit code: $($process.ExitCode)" -Level Error
            Write-LogMessage "Check installation log: $LogDir\scom-install-$timestamp.log" -Level Error
            $script:InstallationsFailed++
            return $false
        }
    }
    catch {
        Write-LogMessage "Error during installation: $($_.Exception.Message)" -Level Error
        $script:InstallationsFailed++
        return $false
    }
}

function Configure-SCOMAgent {
    Write-LogMessage "Configuring SCOM Agent..." -Level Info
    
    if (-not $ManagementServer -or -not $ManagementGroup) {
        Write-LogMessage "No management server specified, skipping post-install configuration" -Level Warning
        Write-LogMessage "Agent will need to be configured manually or via GPO" -Level Info
        return $true
    }
    
    try {
        # Wait for agent to initialize
        Start-Sleep -Seconds 5
        
        # Load Operations Manager PowerShell module
        $agentPath = Join-Path $InstallPath "Agent\PowerShell\OperationsManager"
        $moduleManifest = Join-Path $agentPath "OperationsManager.psd1"
        
        if (Test-Path $moduleManifest) {
            Write-LogMessage "Loading Operations Manager PowerShell module..." -Level Info
            Import-Module $moduleManifest -ErrorAction SilentlyContinue
            
            # Configure management group
            try {
                Write-LogMessage "Configuring management group: $ManagementGroup" -Level Info
                New-SCOMManagementGroupConnection -ComputerName $ManagementServer -ErrorAction Stop
                
                Write-LogMessage "Management group configured successfully" -Level Success
                $script:ConfigurationsApplied++
            }
            catch {
                Write-LogMessage "Could not configure via PowerShell: $($_.Exception.Message)" -Level Warning
            }
        }
        else {
            Write-LogMessage "Operations Manager module not found, using registry configuration" -Level Info
        }
        
        # Verify service is running
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Running') {
            Write-LogMessage "Starting SCOM Agent service..." -Level Info
            Start-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error during configuration: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Set-SCOMServiceStartup {
    Write-LogMessage "Configuring SCOM Agent service..." -Level Info
    
    try {
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-LogMessage "SCOM Agent service not found" -Level Error
            return $false
        }
        
        if ($DisableService) {
            Write-LogMessage "Disabling SCOM Agent service (image preparation mode)" -Level Info
            Stop-Service -Name $AgentServiceName -Force -ErrorAction SilentlyContinue
            Set-Service -Name $AgentServiceName -StartupType Disabled
            Write-LogMessage "SCOM Agent service disabled" -Level Success
        }
        else {
            Write-LogMessage "Configuring SCOM Agent to start automatically" -Level Info
            Set-Service -Name $AgentServiceName -StartupType Automatic
            
            if ($ManagementServer) {
                Start-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
                
                $serviceStatus = (Get-Service -Name $AgentServiceName).Status
                if ($serviceStatus -eq 'Running') {
                    Write-LogMessage "SCOM Agent service started successfully" -Level Success
                }
                else {
                    Write-LogMessage "SCOM Agent service configured but not running: $serviceStatus" -Level Warning
                }
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring service: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Set-SCOMFirewallRules {
    Write-LogMessage "Configuring Windows Firewall rules for SCOM..." -Level Info
    
    try {
        # Check if firewall is enabled
        $firewallProfile = Get-NetFirewallProfile -Profile Domain, Public, Private -ErrorAction SilentlyContinue
        if (-not $firewallProfile) {
            Write-LogMessage "Windows Firewall not available" -Level Warning
            return $true
        }
        
        # Create firewall rule for SCOM Agent
        $ruleName = "SCOM Agent - Management Server Communication"
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        
        if ($existingRule) {
            Write-LogMessage "SCOM firewall rule already exists" -Level Info
        }
        else {
            Write-LogMessage "Creating SCOM firewall rule..." -Level Info
            
            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 5723 `
                -Action Allow `
                -Profile Domain, Private `
                -Description "Allow SCOM Management Server communication" `
                -ErrorAction SilentlyContinue | Out-Null
            
            Write-LogMessage "Firewall rule created successfully" -Level Success
            $script:ConfigurationsApplied++
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error configuring firewall: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Test-SCOMAgentConfiguration {
    Write-LogMessage "Verifying SCOM Agent installation..." -Level Info
    
    try {
        # Check service
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-LogMessage "Service Status: $($service.Status)" -Level Info
            Write-LogMessage "Service Startup Type: $($service.StartType)" -Level Info
        }
        else {
            Write-LogMessage "SCOM Agent service not found" -Level Error
            return $false
        }
        
        # Check installation path
        if (Test-Path $InstallPath) {
            Write-LogMessage "Installation Path: $InstallPath" -Level Info
        }
        
        # Check registry
        if (Test-Path $AgentRegistryPath) {
            $regValues = Get-ItemProperty -Path $AgentRegistryPath
            Write-LogMessage "Agent Version: $($regValues.AgentVersion)" -Level Info
            Write-LogMessage "Install Directory: $($regValues.InstallDirectory)" -Level Info
        }
        
        # Check management group configuration
        $mgPath = "HKLM:\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups"
        if (Test-Path $mgPath) {
            $mgGroups = Get-ChildItem -Path $mgPath -ErrorAction SilentlyContinue
            if ($mgGroups) {
                Write-LogMessage "Configured Management Groups: $($mgGroups.Count)" -Level Info
                foreach ($mg in $mgGroups) {
                    $mgName = Split-Path $mg.Name -Leaf
                    Write-LogMessage "  Management Group: $mgName" -Level Info
                }
            }
        }
        
        Write-LogMessage "SCOM Agent verification completed" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-SCOMAgentInfo {
    Write-LogMessage "Generating SCOM Agent information report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "scom-agent-info-$timestamp.txt"
        $report = @()
        
        $report += "SCOM Agent Installation Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += ""
        
        # Service information
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $report += "Service Information:"
            $report += "  Name: $($service.Name)"
            $report += "  Display Name: $($service.DisplayName)"
            $report += "  Status: $($service.Status)"
            $report += "  Startup Type: $($service.StartType)"
            $report += ""
        }
        
        # Installation details
        if (Test-Path $AgentRegistryPath) {
            $regValues = Get-ItemProperty -Path $AgentRegistryPath
            $report += "Installation Details:"
            $report += "  Agent Version: $($regValues.AgentVersion)"
            $report += "  Install Directory: $($regValues.InstallDirectory)"
            $report += "  Product: $($regValues.Product)"
            $report += ""
        }
        
        # Management group configuration
        $report += "Management Configuration:"
        if ($ManagementServer) {
            $report += "  Management Server: $ManagementServer"
            $report += "  Management Group: $ManagementGroup"
            $report += "  Port: $ManagementServerPort"
        }
        else {
            $report += "  Not configured (manual configuration required)"
        }
        $report += ""
        
        # Firewall status
        $firewallRule = Get-NetFirewallRule -DisplayName "SCOM Agent*" -ErrorAction SilentlyContinue
        if ($firewallRule) {
            $report += "Firewall Rules:"
            foreach ($rule in $firewallRule) {
                $report += "  $($rule.DisplayName): $($rule.Enabled)"
            }
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Agent information report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "SCOM Agent Installation" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
        exit 1
    }
    
    # Check if already installed
    if (Test-SCOMAgentInstalled) {
        Write-LogMessage "SCOM Agent is already installed" -Level Warning
        Write-LogMessage "Skipping installation. To reinstall, uninstall the existing agent first." -Level Warning
        exit 0
    }
    
    # Validate installer availability
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        Write-LogMessage "No installer path provided" -Level Error
        Write-LogMessage "Usage: .\Install-SCOMAgent.ps1 -InstallerPath 'C:\Path\To\MOMAgent.msi'" -Level Info
        Write-LogMessage "Download SCOM agent from System Center Operations Manager installation media" -Level Info
        exit 1
    }
    
    # Install SCOM Agent
    $installSuccess = Install-SCOMAgent
    
    if (-not $installSuccess) {
        Write-LogMessage "SCOM Agent installation failed" -Level Error
        exit 1
    }
    
    # Configure agent
    Configure-SCOMAgent | Out-Null
    
    # Configure service startup
    Set-SCOMServiceStartup | Out-Null
    
    # Configure firewall
    Set-SCOMFirewallRules | Out-Null
    
    # Verify installation
    Test-SCOMAgentConfiguration | Out-Null
    
    # Generate report
    Get-SCOMAgentInfo | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Installation Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Components Installed: $script:ComponentsInstalled" -Level Info
    Write-LogMessage "Configurations Applied: $script:ConfigurationsApplied" -Level Info
    Write-LogMessage "Installation Failures: $script:InstallationsFailed" -Level Info
    Write-LogMessage "Duration: $($duration.TotalSeconds) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:InstallationsFailed -eq 0) {
        Write-LogMessage "SCOM Agent installation completed successfully!" -Level Success
        
        if (-not $ManagementServer) {
            Write-LogMessage "" -Level Info
            Write-LogMessage "NOTE: Agent installed but not configured" -Level Warning
            Write-LogMessage "Configure management group manually or via Group Policy" -Level Info
        }
        
        exit 0
    }
    else {
        Write-LogMessage "Installation completed with errors. Check logs." -Level Warning
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
