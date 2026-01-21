<#
.SYNOPSIS
    Install and Configure Zabbix Agent for Windows Server

.DESCRIPTION
    Downloads, installs, and configures Zabbix Agent on Windows Server 2025.
    Supports both Zabbix Agent 1 and Agent 2 with PSK encryption and active checks.
    Optimized for enterprise monitoring and image preparation.

.NOTES
    File Name      : windows-server-Install_Zabbix_Agent.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Install_Zabbix_Agent -ZabbixServer "zabbix.company.com"
    Installs Zabbix Agent with default settings
    
.EXAMPLE
    .\windows-server-Install_Zabbix_Agent -ZabbixServer "zabbix.company.com" -AgentVersion "6.4.10" -UseAgent2 -EnablePSK
    Installs Zabbix Agent 2 with PSK encryption
    
.PARAMETER ZabbixServer
    Zabbix server address (IP or FQDN)
    
.PARAMETER ServerActive
    Zabbix server address for active checks (default: same as ZabbixServer)
    
.PARAMETER AgentVersion
    Zabbix agent version to install (default: 6.4.10)
    
.PARAMETER HostName
    Hostname for Zabbix (default: computer name)
    
.PARAMETER HostMetadata
    Host metadata for auto-registration
    
.PARAMETER UseAgent2
    Install Zabbix Agent 2 instead of Agent 1
    
.PARAMETER EnablePSK
    Enable PSK encryption
    
.PARAMETER PSKIdentity
    PSK identity string
    
.PARAMETER ListenPort
    Agent listen port (default: 10050)
    
.PARAMETER InstallPath
    Installation directory (default: C:\Program Files\Zabbix Agent)
    
.PARAMETER DisableService
    Disable agent service after installation (for image preparation)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ZabbixServer = "",
    
    [string]$ServerActive = "",
    [string]$AgentVersion = "6.4.10",
    [string]$HostName = $env:COMPUTERNAME,
    [string]$HostMetadata = "Windows",
    [switch]$UseAgent2,
    [switch]$EnablePSK,
    [string]$PSKIdentity = "",
    [int]$ListenPort = 10050,
    [string]$InstallPath = "C:\Program Files\Zabbix Agent",
    [switch]$DisableService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$TempDir = 'C:\Windows\Temp\Zabbix'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Agent configuration
$AgentServiceName = if ($UseAgent2) { "Zabbix Agent 2" } else { "Zabbix Agent" }
$AgentExeName = if ($UseAgent2) { "zabbix_agent2.exe" } else { "zabbix_agentd.exe" }
$ConfigFileName = if ($UseAgent2) { "zabbix_agent2.conf" } else { "zabbix_agentd.conf" }

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

function Test-ZabbixAgentInstalled {
    try {
        $agentPath = Join-Path $InstallPath "bin\$AgentExeName"
        if (Test-Path $agentPath) {
            Write-LogMessage "Zabbix Agent found at: $agentPath" -Level Info
            return $true
        }
        
        $service = Get-Service | Where-Object { $_.DisplayName -like "Zabbix Agent*" }
        if ($service) {
            Write-LogMessage "Zabbix Agent service found: $($service.DisplayName)" -Level Info
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}

function Get-ZabbixDownloadUrl {
    param(
        [string]$Version,
        [bool]$IsAgent2
    )
    
    try {
        $agentType = if ($IsAgent2) { "zabbix_agent2" } else { "zabbix_agent" }
        
        # Construct download URL for Zabbix repository
        $majorMinor = $Version.Substring(0, $Version.LastIndexOf('.'))
        $baseUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/$majorMinor/$Version"
        $filename = "${agentType}-${Version}-windows-amd64-openssl.msi"
        
        $downloadUrl = "$baseUrl/$filename"
        
        Write-LogMessage "Download URL: $downloadUrl" -Level Info
        return $downloadUrl
    }
    catch {
        Write-LogMessage "Error constructing download URL: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Install-ZabbixAgent {
    Write-LogMessage "Installing Zabbix Agent..." -Level Info
    
    try {
        # Create temp directory
        if (-not (Test-Path $TempDir)) {
            New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
        }
        
        # Get download URL
        $downloadUrl = Get-ZabbixDownloadUrl -Version $AgentVersion -IsAgent2 $UseAgent2
        if (-not $downloadUrl) {
            throw "Could not determine download URL"
        }
        
        $installerPath = Join-Path $TempDir "zabbix_agent.msi"
        
        Write-LogMessage "Downloading Zabbix Agent from $downloadUrl" -Level Info
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $installerPath)
            $webClient.Dispose()
        }
        catch {
            Write-LogMessage "Download failed: $($_.Exception.Message)" -Level Error
            Write-LogMessage "Please download manually from: https://www.zabbix.com/download_agents" -Level Warning
            throw "Download failed"
        }
        
        if (-not (Test-Path $installerPath)) {
            throw "Installer not found at $installerPath"
        }
        
        Write-LogMessage "Installer downloaded successfully" -Level Success
        
        # Build installation arguments
        $installArgs = @(
            "/i `"$installerPath`""
            "/qn"
            "/norestart"
            "/l*v `"$LogDir\zabbix-install-$timestamp.log`""
            "INSTALLDIR=`"$InstallPath`""
            "ENABLEPATH=1"
        )
        
        # Add server configuration if provided
        if ($ZabbixServer) {
            $installArgs += "SERVER=`"$ZabbixServer`""
        }
        
        if ($ServerActive) {
            $installArgs += "SERVERACTIVE=`"$ServerActive`""
        }
        elseif ($ZabbixServer) {
            $installArgs += "SERVERACTIVE=`"$ZabbixServer`""
        }
        
        if ($HostName) {
            $installArgs += "HOSTNAME=`"$HostName`""
        }
        
        if ($ListenPort -ne 10050) {
            $installArgs += "LISTENPORT=$ListenPort"
        }
        
        $installArgString = $installArgs -join ' '
        
        Write-LogMessage "Installation command: msiexec.exe $installArgString" -Level Info
        Write-LogMessage "Installing Zabbix Agent (this may take a few minutes)..." -Level Info
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgString -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-LogMessage "Zabbix Agent installed successfully (Exit Code: $($process.ExitCode))" -Level Success
            $script:ComponentsInstalled++
            
            # Wait for service to be created
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-LogMessage "Installation failed with exit code: $($process.ExitCode)" -Level Error
            Write-LogMessage "Check installation log: $LogDir\zabbix-install-$timestamp.log" -Level Error
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

function New-PSKKey {
    Write-LogMessage "Generating PSK key..." -Level Info
    
    try {
        # Generate 32-byte (256-bit) random key
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $rng.GetBytes($bytes)
        
        # Convert to hex string
        $pskKey = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ''
        
        Write-LogMessage "PSK key generated successfully" -Level Success
        return $pskKey
    }
    catch {
        Write-LogMessage "Error generating PSK key: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Configure-ZabbixAgent {
    Write-LogMessage "Configuring Zabbix Agent..." -Level Info
    
    try {
        $configPath = Join-Path $InstallPath "conf\$ConfigFileName"
        
        if (-not (Test-Path $configPath)) {
            Write-LogMessage "Configuration file not found: $configPath" -Level Error
            return $false
        }
        
        # Read existing configuration
        $config = Get-Content $configPath
        
        # Update configuration
        $newConfig = @()
        $serverSet = $false
        $serverActiveSet = $false
        $hostnameSet = $false
        $metadataSet = $false
        
        foreach ($line in $config) {
            # Server configuration
            if ($line -match "^Server=" -or $line -match "^#\s*Server=") {
                if ($ZabbixServer -and -not $serverSet) {
                    $newConfig += "Server=$ZabbixServer"
                    $serverSet = $true
                }
                else {
                    $newConfig += $line
                }
            }
            # ServerActive configuration
            elseif ($line -match "^ServerActive=" -or $line -match "^#\s*ServerActive=") {
                $activeServer = if ($ServerActive) { $ServerActive } elseif ($ZabbixServer) { $ZabbixServer } else { "" }
                if ($activeServer -and -not $serverActiveSet) {
                    $newConfig += "ServerActive=$activeServer"
                    $serverActiveSet = $true
                }
                else {
                    $newConfig += $line
                }
            }
            # Hostname configuration
            elseif ($line -match "^Hostname=" -or $line -match "^#\s*Hostname=") {
                if ($HostName -and -not $hostnameSet) {
                    $newConfig += "Hostname=$HostName"
                    $hostnameSet = $true
                }
                else {
                    $newConfig += $line
                }
            }
            # Host metadata configuration
            elseif ($line -match "^HostMetadata=" -or $line -match "^#\s*HostMetadata=") {
                if ($HostMetadata -and -not $metadataSet) {
                    $newConfig += "HostMetadata=$HostMetadata"
                    $metadataSet = $true
                }
                else {
                    $newConfig += $line
                }
            }
            # ListenPort configuration
            elseif ($line -match "^ListenPort=" -or $line -match "^#\s*ListenPort=") {
                $newConfig += "ListenPort=$ListenPort"
            }
            else {
                $newConfig += $line
            }
        }
        
        # Configure PSK if enabled
        if ($EnablePSK) {
            Write-LogMessage "Configuring PSK encryption..." -Level Info
            
            # Generate PSK identity if not provided
            if ([string]::IsNullOrWhiteSpace($PSKIdentity)) {
                $script:PSKIdentity = "PSK-$HostName"
            }
            
            # Generate PSK key
            $pskKey = New-PSKKey
            if (-not $pskKey) {
                Write-LogMessage "Failed to generate PSK key" -Level Error
                return $false
            }
            
            # Save PSK key to file
            $pskFilePath = Join-Path $InstallPath "conf\zabbix_agentd.psk"
            Set-Content -Path $pskFilePath -Value $pskKey -Force
            
            # Update configuration for PSK
            $newConfig += ""
            $newConfig += "# PSK Configuration"
            $newConfig += "TLSConnect=psk"
            $newConfig += "TLSAccept=psk"
            $newConfig += "TLSPSKIdentity=$PSKIdentity"
            $newConfig += "TLSPSKFile=$pskFilePath"
            
            Write-LogMessage "PSK encryption configured" -Level Success
            Write-LogMessage "PSK Identity: $PSKIdentity" -Level Info
            
            # Save PSK credentials
            $pskCredFile = Join-Path $LogDir "zabbix-psk-$timestamp.txt"
            $pskCred = @"
Zabbix Agent PSK Credentials
=============================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Hostname: $HostName
PSK Identity: $PSKIdentity
PSK Key: $pskKey
PSK Key File: $pskFilePath

IMPORTANT: Store these credentials securely and configure them in Zabbix server.
Delete this file after recording credentials.
"@
            Set-Content -Path $pskCredFile -Value $pskCred -Force
            Write-LogMessage "PSK credentials saved to: $pskCredFile" -Level Info
            
            $script:ConfigurationsApplied++
        }
        
        # Write updated configuration
        Set-Content -Path $configPath -Value $newConfig -Force
        
        Write-LogMessage "Configuration file updated: $configPath" -Level Success
        $script:ConfigurationsApplied++
        
        return $true
    }
    catch {
        Write-LogMessage "Error configuring agent: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Set-ZabbixServiceStartup {
    Write-LogMessage "Configuring Zabbix Agent service..." -Level Info
    
    try {
        $service = Get-Service | Where-Object { $_.DisplayName -like "Zabbix Agent*" } | Select-Object -First 1
        
        if (-not $service) {
            Write-LogMessage "Zabbix Agent service not found" -Level Error
            return $false
        }
        
        Write-LogMessage "Found service: $($service.DisplayName)" -Level Info
        
        if ($DisableService) {
            Write-LogMessage "Disabling Zabbix Agent service (image preparation mode)" -Level Info
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service.Name -StartupType Disabled
            Write-LogMessage "Zabbix Agent service disabled" -Level Success
        }
        else {
            Write-LogMessage "Configuring Zabbix Agent to start automatically" -Level Info
            Set-Service -Name $service.Name -StartupType Automatic
            
            if ($ZabbixServer) {
                Start-Service -Name $service.Name -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                
                $serviceStatus = (Get-Service -Name $service.Name).Status
                if ($serviceStatus -eq 'Running') {
                    Write-LogMessage "Zabbix Agent service started successfully" -Level Success
                }
                else {
                    Write-LogMessage "Zabbix Agent service configured but not running: $serviceStatus" -Level Warning
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

function Set-ZabbixFirewallRules {
    Write-LogMessage "Configuring Windows Firewall rules for Zabbix..." -Level Info
    
    try {
        $ruleName = "Zabbix Agent - Passive Checks"
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        
        if ($existingRule) {
            Write-LogMessage "Zabbix firewall rule already exists" -Level Info
        }
        else {
            Write-LogMessage "Creating Zabbix firewall rule..." -Level Info
            
            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort $ListenPort `
                -Action Allow `
                -Profile Domain, Private `
                -Description "Allow Zabbix server to connect for passive checks" `
                -ErrorAction SilentlyContinue | Out-Null
            
            Write-LogMessage "Firewall rule created for port $ListenPort" -Level Success
            $script:ConfigurationsApplied++
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error configuring firewall: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Test-ZabbixAgentConfiguration {
    Write-LogMessage "Verifying Zabbix Agent installation..." -Level Info
    
    try {
        # Check service
        $service = Get-Service | Where-Object { $_.DisplayName -like "Zabbix Agent*" } | Select-Object -First 1
        
        if ($service) {
            Write-LogMessage "Service Name: $($service.Name)" -Level Info
            Write-LogMessage "Service Status: $($service.Status)" -Level Info
            Write-LogMessage "Service Startup Type: $($service.StartType)" -Level Info
        }
        else {
            Write-LogMessage "Zabbix Agent service not found" -Level Error
            return $false
        }
        
        # Check configuration file
        $configPath = Join-Path $InstallPath "conf\$ConfigFileName"
        if (Test-Path $configPath) {
            Write-LogMessage "Configuration file: $configPath" -Level Info
            
            $config = Get-Content $configPath
            $serverLine = $config | Where-Object { $_ -match "^Server=" } | Select-Object -First 1
            $hostnameLine = $config | Where-Object { $_ -match "^Hostname=" } | Select-Object -First 1
            
            if ($serverLine) { Write-LogMessage "  $serverLine" -Level Info }
            if ($hostnameLine) { Write-LogMessage "  $hostnameLine" -Level Info }
        }
        
        # Check agent executable
        $agentPath = Join-Path $InstallPath "bin\$AgentExeName"
        if (Test-Path $agentPath) {
            Write-LogMessage "Agent executable: $agentPath" -Level Info
            
            # Get version
            $versionOutput = & $agentPath --version 2>&1 | Select-Object -First 1
            Write-LogMessage "  Version: $versionOutput" -Level Info
        }
        
        Write-LogMessage "Zabbix Agent verification completed" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Remove-ZabbixInstaller {
    Write-LogMessage "Cleaning up installation files..." -Level Info
    
    try {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Temporary files cleaned up" -Level Success
        }
    }
    catch {
        Write-LogMessage "Could not clean up temp directory: $($_.Exception.Message)" -Level Warning
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Zabbix Agent Installation" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Agent Version: $AgentVersion" -Level Info
    Write-LogMessage "Agent Type: $(if ($UseAgent2) { 'Agent 2' } else { 'Agent 1' })" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
        exit 1
    }
    
    # Check if already installed
    if (Test-ZabbixAgentInstalled) {
        Write-LogMessage "Zabbix Agent is already installed" -Level Warning
        Write-LogMessage "Skipping installation. To reinstall, uninstall the existing agent first." -Level Warning
        exit 0
    }
    
    # Install Zabbix Agent
    $installSuccess = Install-ZabbixAgent
    
    if (-not $installSuccess) {
        Write-LogMessage "Zabbix Agent installation failed" -Level Error
        exit 1
    }
    
    # Configure agent
    Configure-ZabbixAgent | Out-Null
    
    # Configure service startup
    Set-ZabbixServiceStartup | Out-Null
    
    # Configure firewall
    Set-ZabbixFirewallRules | Out-Null
    
    # Verify installation
    Test-ZabbixAgentConfiguration | Out-Null
    
    # Cleanup
    Remove-ZabbixInstaller
    
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
        Write-LogMessage "Zabbix Agent installation completed successfully!" -Level Success
        
        if (-not $ZabbixServer) {
            Write-LogMessage "" -Level Info
            Write-LogMessage "NOTE: No Zabbix server configured" -Level Warning
            Write-LogMessage "Edit configuration file: $(Join-Path $InstallPath "conf\$ConfigFileName")" -Level Info
        }
        
        if ($EnablePSK) {
            Write-LogMessage "" -Level Info
            Write-LogMessage "PSK encryption enabled - remember to configure PSK on Zabbix server" -Level Warning
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
