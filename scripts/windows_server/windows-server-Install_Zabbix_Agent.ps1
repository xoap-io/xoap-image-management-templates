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

$script:Component = 'Zabbix'
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
} catch { Write-Host ("[{0}] [WARN] [Zabbix] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ZabbixAgentInstalled {
    try {
        $agentPath = Join-Path $InstallPath "bin\$AgentExeName"
        if (Test-Path $agentPath) {
            Write-Log "Zabbix Agent found at: $agentPath" -Level INFO
            return $true
        }
        
        $service = Get-Service | Where-Object { $_.DisplayName -like "Zabbix Agent*" }
        if ($service) {
            Write-Log "Zabbix Agent service found: $($service.DisplayName)" -Level INFO
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
        
        Write-Log "Download URL: $downloadUrl" -Level INFO
        return $downloadUrl
    }
    catch {
        Write-Log "Error constructing download URL: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Install-ZabbixAgent {
    Write-Log "Installing Zabbix Agent..." -Level INFO
    
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
        
        Write-Log "Downloading Zabbix Agent from $downloadUrl" -Level INFO
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $installerPath)
            $webClient.Dispose()
        }
        catch {
            Write-Log "Download failed: $($_.Exception.Message)" -Level ERROR
            Write-Log "Please download manually from: https://www.zabbix.com/download_agents" -Level WARN
            throw "Download failed"
        }
        
        if (-not (Test-Path $installerPath)) {
            throw "Installer not found at $installerPath"
        }
        
        Write-Log "Installer downloaded successfully" -Level INFO
        
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
        
        Write-Log "Installation command: msiexec.exe $installArgString" -Level INFO
        Write-Log "Installing Zabbix Agent (this may take a few minutes)..." -Level INFO
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgString -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "Zabbix Agent installed successfully (Exit Code: $($process.ExitCode))" -Level INFO
            $script:ComponentsInstalled++
            
            # Wait for service to be created
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level ERROR
            Write-Log "Check installation log: $LogDir\zabbix-install-$timestamp.log" -Level ERROR
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

function New-PSKKey {
    Write-Log "Generating PSK key..." -Level INFO
    
    try {
        # Generate 32-byte (256-bit) random key
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $rng.GetBytes($bytes)
        
        # Convert to hex string
        $pskKey = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ''
        
        Write-Log "PSK key generated successfully" -Level INFO
        return $pskKey
    }
    catch {
        Write-Log "Error generating PSK key: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Configure-ZabbixAgent {
    Write-Log "Configuring Zabbix Agent..." -Level INFO
    
    try {
        $configPath = Join-Path $InstallPath "conf\$ConfigFileName"
        
        if (-not (Test-Path $configPath)) {
            Write-Log "Configuration file not found: $configPath" -Level ERROR
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
            Write-Log "Configuring PSK encryption..." -Level INFO
            
            # Generate PSK identity if not provided
            if ([string]::IsNullOrWhiteSpace($PSKIdentity)) {
                $script:PSKIdentity = "PSK-$HostName"
            }
            
            # Generate PSK key
            $pskKey = New-PSKKey
            if (-not $pskKey) {
                Write-Log "Failed to generate PSK key" -Level ERROR
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
            
            Write-Log "PSK encryption configured" -Level INFO
            Write-Log "PSK Identity: $PSKIdentity" -Level INFO
            
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
            Write-Log "PSK credentials saved to: $pskCredFile" -Level INFO
            
            $script:ConfigurationsApplied++
        }
        
        # Write updated configuration
        Set-Content -Path $configPath -Value $newConfig -Force
        
        Write-Log "Configuration file updated: $configPath" -Level INFO
        $script:ConfigurationsApplied++
        
        return $true
    }
    catch {
        Write-Log "Error configuring agent: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Set-ZabbixServiceStartup {
    Write-Log "Configuring Zabbix Agent service..." -Level INFO
    
    try {
        $service = Get-Service | Where-Object { $_.DisplayName -like "Zabbix Agent*" } | Select-Object -First 1
        
        if (-not $service) {
            Write-Log "Zabbix Agent service not found" -Level ERROR
            return $false
        }
        
        Write-Log "Found service: $($service.DisplayName)" -Level INFO
        
        if ($DisableService) {
            Write-Log "Disabling Zabbix Agent service (image preparation mode)" -Level INFO
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service.Name -StartupType Disabled
            Write-Log "Zabbix Agent service disabled" -Level INFO
        }
        else {
            Write-Log "Configuring Zabbix Agent to start automatically" -Level INFO
            Set-Service -Name $service.Name -StartupType Automatic
            
            if ($ZabbixServer) {
                Start-Service -Name $service.Name -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                
                $serviceStatus = (Get-Service -Name $service.Name).Status
                if ($serviceStatus -eq 'Running') {
                    Write-Log "Zabbix Agent service started successfully" -Level INFO
                }
                else {
                    Write-Log "Zabbix Agent service configured but not running: $serviceStatus" -Level WARN
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

function Set-ZabbixFirewallRules {
    Write-Log "Configuring Windows Firewall rules for Zabbix..." -Level INFO
    
    try {
        $ruleName = "Zabbix Agent - Passive Checks"
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        
        if ($existingRule) {
            Write-Log "Zabbix firewall rule already exists" -Level INFO
        }
        else {
            Write-Log "Creating Zabbix firewall rule..." -Level INFO
            
            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort $ListenPort `
                -Action Allow `
                -Profile Domain, Private `
                -Description "Allow Zabbix server to connect for passive checks" `
                -ErrorAction SilentlyContinue | Out-Null
            
            Write-Log "Firewall rule created for port $ListenPort" -Level INFO
            $script:ConfigurationsApplied++
        }
        
        return $true
    }
    catch {
        Write-Log "Error configuring firewall: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Test-ZabbixAgentConfiguration {
    Write-Log "Verifying Zabbix Agent installation..." -Level INFO
    
    try {
        # Check service
        $service = Get-Service | Where-Object { $_.DisplayName -like "Zabbix Agent*" } | Select-Object -First 1
        
        if ($service) {
            Write-Log "Service Name: $($service.Name)" -Level INFO
            Write-Log "Service Status: $($service.Status)" -Level INFO
            Write-Log "Service Startup Type: $($service.StartType)" -Level INFO
        }
        else {
            Write-Log "Zabbix Agent service not found" -Level ERROR
            return $false
        }
        
        # Check configuration file
        $configPath = Join-Path $InstallPath "conf\$ConfigFileName"
        if (Test-Path $configPath) {
            Write-Log "Configuration file: $configPath" -Level INFO
            
            $config = Get-Content $configPath
            $serverLine = $config | Where-Object { $_ -match "^Server=" } | Select-Object -First 1
            $hostnameLine = $config | Where-Object { $_ -match "^Hostname=" } | Select-Object -First 1
            
            if ($serverLine) { Write-Log "  $serverLine" -Level INFO }
            if ($hostnameLine) { Write-Log "  $hostnameLine" -Level INFO }
        }
        
        # Check agent executable
        $agentPath = Join-Path $InstallPath "bin\$AgentExeName"
        if (Test-Path $agentPath) {
            Write-Log "Agent executable: $agentPath" -Level INFO
            
            # Get version
            $versionOutput = & $agentPath --version 2>&1 | Select-Object -First 1
            Write-Log "  Version: $versionOutput" -Level INFO
        }
        
        Write-Log "Zabbix Agent verification completed" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error during verification: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Remove-ZabbixInstaller {
    Write-Log "Cleaning up installation files..." -Level INFO
    
    try {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Temporary files cleaned up" -Level INFO
        }
    }
    catch {
        Write-Log "Could not clean up temp directory: $($_.Exception.Message)" -Level WARN
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date

    Write-Log "===== Install_Zabbix_Agent starting (Version=$AgentVersion, Type=$(if ($UseAgent2) { 'Agent 2' } else { 'Agent 1' })) ====="
    Write-Log "Log File: $LogFile"

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Check if already installed
    if (Test-ZabbixAgentInstalled) {
        Write-Log "Zabbix Agent is already installed" -Level WARN
        Write-Log "Skipping installation. To reinstall, uninstall the existing agent first." -Level WARN
        exit 0
    }
    
    # Install Zabbix Agent
    $installSuccess = Install-ZabbixAgent
    
    if (-not $installSuccess) {
        Write-Log "Zabbix Agent installation failed" -Level ERROR
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
    
    if ($script:InstallationsFailed -eq 0) {
        if (-not $ZabbixServer) {
            Write-Log "NOTE: No Zabbix server configured" -Level WARN
            Write-Log "Edit configuration file: $(Join-Path $InstallPath "conf\$ConfigFileName")"
        }

        if ($EnablePSK) {
            Write-Log "PSK encryption enabled - remember to configure PSK on Zabbix server" -Level WARN
        }

        Write-Log "===== Install_Zabbix_Agent complete in $([int]((Get-Date) - $scriptStartTime).TotalSeconds)s; applied=$script:ConfigurationsApplied failed=$script:InstallationsFailed ====="
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
