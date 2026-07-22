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

$script:Component = 'SCOM'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message
    Write-Host $line
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [SCOM] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SCOMAgentInstalled {
    try {
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "SCOM Agent service found: $($service.Status)" -Level INFO
            return $true
        }
        
        if (Test-Path $AgentRegistryPath) {
            Write-Log "SCOM Agent registry keys found" -Level INFO
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}

function Get-SCOMInstallerPath {
    Write-Log "Validating SCOM installer path..." -Level INFO
    
    # Check if installer path provided
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        Write-Log "No installer path provided" -Level WARN
        Write-Log "Please provide the path to MOMAgent.msi installer" -Level WARN
        Write-Log "Download from: System Center Operations Manager installation media" -Level INFO
        return $null
    }
    
    # Check if file exists
    if (-not (Test-Path $InstallerPath)) {
        Write-Log "Installer not found at: $InstallerPath" -Level ERROR
        return $null
    }
    
    # Verify it's an MSI file
    if ([IO.Path]::GetExtension($InstallerPath) -ne '.msi') {
        Write-Log "Installer must be an MSI file" -Level ERROR
        return $null
    }
    
    Write-Log "Installer found: $InstallerPath" -Level INFO
    return $InstallerPath
}

function Install-SCOMAgent {
    Write-Log "Installing SCOM Agent..." -Level INFO
    
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
        
        Write-Log "Installation command: msiexec.exe $installArgString" -Level INFO
        Write-Log "Installing SCOM Agent (this may take several minutes)..." -Level INFO
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgString -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "SCOM Agent installed successfully (Exit Code: $($process.ExitCode))" -Level INFO
            $script:ComponentsInstalled++
            
            # Wait for service to be created
            Start-Sleep -Seconds 10
            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level ERROR
            Write-Log "Check installation log: $LogDir\scom-install-$timestamp.log" -Level ERROR
            $script:InstallationsFailed++
            return $false
        }
    }
    catch {
        Write-Log "Error during installation: $($_.Exception.Message)" -Level ERROR
        $script:InstallationsFailed++
        return $false
    }
}

function Configure-SCOMAgent {
    Write-Log "Configuring SCOM Agent..." -Level INFO
    
    if (-not $ManagementServer -or -not $ManagementGroup) {
        Write-Log "No management server specified, skipping post-install configuration" -Level WARN
        Write-Log "Agent will need to be configured manually or via GPO" -Level INFO
        return $true
    }
    
    try {
        # Wait for agent to initialize
        Start-Sleep -Seconds 5
        
        # Load Operations Manager PowerShell module
        $agentPath = Join-Path $InstallPath "Agent\PowerShell\OperationsManager"
        $moduleManifest = Join-Path $agentPath "OperationsManager.psd1"
        
        if (Test-Path $moduleManifest) {
            Write-Log "Loading Operations Manager PowerShell module..." -Level INFO
            Import-Module $moduleManifest -ErrorAction SilentlyContinue
            
            # Configure management group
            try {
                Write-Log "Configuring management group: $ManagementGroup" -Level INFO
                New-SCOMManagementGroupConnection -ComputerName $ManagementServer -ErrorAction Stop
                
                Write-Log "Management group configured successfully" -Level INFO
                $script:ConfigurationsApplied++
            }
            catch {
                Write-Log "Could not configure via PowerShell: $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-Log "Operations Manager module not found, using registry configuration" -Level INFO
        }
        
        # Verify service is running
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Running') {
            Write-Log "Starting SCOM Agent service..." -Level INFO
            Start-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
        
        return $true
    }
    catch {
        Write-Log "Error during configuration: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Set-SCOMServiceStartup {
    Write-Log "Configuring SCOM Agent service..." -Level INFO
    
    try {
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-Log "SCOM Agent service not found" -Level ERROR
            return $false
        }
        
        if ($DisableService) {
            Write-Log "Disabling SCOM Agent service (image preparation mode)" -Level INFO
            Stop-Service -Name $AgentServiceName -Force -ErrorAction SilentlyContinue
            Set-Service -Name $AgentServiceName -StartupType Disabled
            Write-Log "SCOM Agent service disabled" -Level INFO
        }
        else {
            Write-Log "Configuring SCOM Agent to start automatically" -Level INFO
            Set-Service -Name $AgentServiceName -StartupType Automatic
            
            if ($ManagementServer) {
                Start-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
                
                $serviceStatus = (Get-Service -Name $AgentServiceName).Status
                if ($serviceStatus -eq 'Running') {
                    Write-Log "SCOM Agent service started successfully" -Level INFO
                }
                else {
                    Write-Log "SCOM Agent service configured but not running: $serviceStatus" -Level WARN
                }
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring service: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Set-SCOMFirewallRules {
    Write-Log "Configuring Windows Firewall rules for SCOM..." -Level INFO
    
    try {
        # Check if firewall is enabled
        $firewallProfile = Get-NetFirewallProfile -Profile Domain, Public, Private -ErrorAction SilentlyContinue
        if (-not $firewallProfile) {
            Write-Log "Windows Firewall not available" -Level WARN
            return $true
        }
        
        # Create firewall rule for SCOM Agent
        $ruleName = "SCOM Agent - Management Server Communication"
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        
        if ($existingRule) {
            Write-Log "SCOM firewall rule already exists" -Level INFO
        }
        else {
            Write-Log "Creating SCOM firewall rule..." -Level INFO
            
            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 5723 `
                -Action Allow `
                -Profile Domain, Private `
                -Description "Allow SCOM Management Server communication" `
                -ErrorAction SilentlyContinue | Out-Null
            
            Write-Log "Firewall rule created successfully" -Level INFO
            $script:ConfigurationsApplied++
        }
        
        return $true
    }
    catch {
        Write-Log "Error configuring firewall: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Test-SCOMAgentConfiguration {
    Write-Log "Verifying SCOM Agent installation..." -Level INFO
    
    try {
        # Check service
        $service = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "Service Status: $($service.Status)" -Level INFO
            Write-Log "Service Startup Type: $($service.StartType)" -Level INFO
        }
        else {
            Write-Log "SCOM Agent service not found" -Level ERROR
            return $false
        }
        
        # Check installation path
        if (Test-Path $InstallPath) {
            Write-Log "Installation Path: $InstallPath" -Level INFO
        }
        
        # Check registry
        if (Test-Path $AgentRegistryPath) {
            $regValues = Get-ItemProperty -Path $AgentRegistryPath
            Write-Log "Agent Version: $($regValues.AgentVersion)" -Level INFO
            Write-Log "Install Directory: $($regValues.InstallDirectory)" -Level INFO
        }
        
        # Check management group configuration
        $mgPath = "HKLM:\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups"
        if (Test-Path $mgPath) {
            $mgGroups = Get-ChildItem -Path $mgPath -ErrorAction SilentlyContinue
            if ($mgGroups) {
                Write-Log "Configured Management Groups: $($mgGroups.Count)" -Level INFO
                foreach ($mg in $mgGroups) {
                    $mgName = Split-Path $mg.Name -Leaf
                    Write-Log "  Management Group: $mgName" -Level INFO
                }
            }
        }
        
        Write-Log "SCOM Agent verification completed" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error during verification: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Get-SCOMAgentInfo {
    Write-Log "Generating SCOM Agent information report..." -Level INFO
    
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
        
        Write-Log "Agent information report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date

    Write-Log "===== Install_SCOM_Agent starting ====="
    Write-Log "Log File: $LogFile"

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Check if already installed
    if (Test-SCOMAgentInstalled) {
        Write-Log "SCOM Agent is already installed" -Level WARN
        Write-Log "Skipping installation. To reinstall, uninstall the existing agent first." -Level WARN
        exit 0
    }
    
    # Validate installer availability
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        Write-Log "No installer path provided" -Level ERROR
        Write-Log "Usage: .\Install-SCOMAgent.ps1 -InstallerPath 'C:\Path\To\MOMAgent.msi'" -Level INFO
        Write-Log "Download SCOM agent from System Center Operations Manager installation media" -Level INFO
        exit 1
    }
    
    # Install SCOM Agent
    $installSuccess = Install-SCOMAgent
    
    if (-not $installSuccess) {
        Write-Log "SCOM Agent installation failed" -Level ERROR
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
    
    if ($script:InstallationsFailed -eq 0) {
        if (-not $ManagementServer) {
            Write-Log "NOTE: Agent installed but not configured" -Level WARN
            Write-Log "Configure management group manually or via Group Policy"
        }
        Write-Log "===== Install_SCOM_Agent complete in $([int]((Get-Date) - $scriptStartTime).TotalSeconds)s; applied=$script:ConfigurationsApplied failed=$script:InstallationsFailed ====="
        exit 0
    }
    else {
        Write-Log "Installation completed with errors. Check logs." -Level WARN
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}

#endregion
