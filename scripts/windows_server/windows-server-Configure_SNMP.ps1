<#
.SYNOPSIS
    Configure SNMP Service for Windows Server

.DESCRIPTION
    Installs and configures SNMP Service on Windows Server 2025 with community strings,
    permitted managers, and traps. Optimized for enterprise monitoring and image preparation.

.NOTES
    File Name      : windows-server-Configure_SNMP.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Configure_SNMP
    Installs SNMP with default read-only community 'public'
    
.EXAMPLE
    .\windows-server-Configure_SNMP -Communities @{public='READ ONLY'; private='READ WRITE'} -PermittedManagers @('10.0.0.100', '10.0.0.101')
    Configures SNMP with custom communities and permitted managers
    
.PARAMETER Communities
    Hashtable of community names and permissions (READ ONLY, READ WRITE, READ CREATE)
    
.PARAMETER PermittedManagers
    Array of IP addresses or hostnames allowed to query SNMP
    
.PARAMETER TrapDestinations
    Array of trap receiver addresses
    
.PARAMETER ContactInfo
    SNMP contact information
    
.PARAMETER Location
    SNMP location string
    
.PARAMETER DisableService
    Disable SNMP service after configuration (for image preparation)
#>

[CmdletBinding()]
param(
    [hashtable]$Communities = @{ "public" = "READ ONLY" },
    [string[]]$PermittedManagers = @(),
    [string[]]$TrapDestinations = @(),
    [string]$ContactInfo = "IT Operations",
    [string]$Location = "Data Center",
    [switch]$DisableService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Registry paths
$SNMPParametersPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters'
$SNMPCommunitiesPath = "$SNMPParametersPath\ValidCommunities"
$SNMPPermittedPath = "$SNMPParametersPath\PermittedManagers"
$SNMPTrapsPath = "$SNMPParametersPath\TrapConfiguration"

# Statistics tracking
$script:ComponentsInstalled = 0
$script:ConfigurationsApplied = 0
$script:ConfigurationsFailed = 0

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

function Install-SNMPFeature {
    Write-LogMessage "Checking SNMP Service installation..." -Level Info
    
    try {
        $snmpService = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        
        if ($snmpService) {
            Write-LogMessage "SNMP Service is already installed" -Level Info
            return $true
        }
        
        Write-LogMessage "Installing SNMP Service feature..." -Level Info
        
        # Install using DISM
        $result = Start-Process -FilePath "dism.exe" -ArgumentList "/online /enable-feature /featurename:SNMP /all /quiet /norestart" -Wait -PassThru -NoNewWindow
        
        if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 3010) {
            Write-LogMessage "SNMP Service installed successfully" -Level Success
            $script:ComponentsInstalled++
            
            # Wait for service to be available
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-LogMessage "SNMP installation failed with exit code: $($result.ExitCode)" -Level Error
            
            # Try Windows capability method
            Write-LogMessage "Attempting alternative installation method..." -Level Info
            Add-WindowsCapability -Online -Name "SNMP.Client~~~~0.0.1.0" -ErrorAction Stop
            
            Write-LogMessage "SNMP installed via Windows Capability" -Level Success
            $script:ComponentsInstalled++
            return $true
        }
    }
    catch {
        Write-LogMessage "Error installing SNMP: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPCommunities {
    Write-LogMessage "Configuring SNMP communities..." -Level Info
    
    try {
        # Create ValidCommunities registry key if it doesn't exist
        if (-not (Test-Path $SNMPCommunitiesPath)) {
            New-Item -Path $SNMPCommunitiesPath -Force | Out-Null
        }
        
        foreach ($community in $Communities.GetEnumerator()) {
            $communityName = $community.Key
            $permission = $community.Value
            
            # Permission values: 4 = READ ONLY, 8 = READ WRITE, 16 = READ CREATE
            $permissionValue = switch ($permission) {
                'READ ONLY'   { 4 }
                'READ WRITE'  { 8 }
                'READ CREATE' { 16 }
                default       { 4 }
            }
            
            New-ItemProperty -Path $SNMPCommunitiesPath -Name $communityName -Value $permissionValue -PropertyType DWord -Force | Out-Null
            Write-LogMessage "Added community: $communityName ($permission)" -Level Info
        }
        
        Write-LogMessage "SNMP communities configured successfully" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring communities: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPPermittedManagers {
    Write-LogMessage "Configuring permitted SNMP managers..." -Level Info
    
    try {
        # Create PermittedManagers registry key if it doesn't exist
        if (-not (Test-Path $SNMPPermittedPath)) {
            New-Item -Path $SNMPPermittedPath -Force | Out-Null
        }
        
        # If no managers specified, accept from any host
        if ($PermittedManagers.Count -eq 0) {
            New-ItemProperty -Path $SNMPPermittedPath -Name "1" -Value "0.0.0.0" -PropertyType String -Force | Out-Null
            Write-LogMessage "Configured to accept SNMP requests from any host (0.0.0.0)" -Level Warning
        }
        else {
            # Add each permitted manager
            $index = 1
            foreach ($manager in $PermittedManagers) {
                New-ItemProperty -Path $SNMPPermittedPath -Name $index.ToString() -Value $manager -PropertyType String -Force | Out-Null
                Write-LogMessage "Added permitted manager: $manager" -Level Info
                $index++
            }
        }
        
        Write-LogMessage "Permitted managers configured successfully" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring permitted managers: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPTraps {
    Write-LogMessage "Configuring SNMP traps..." -Level Info
    
    try {
        if ($TrapDestinations.Count -eq 0) {
            Write-LogMessage "No trap destinations specified, skipping trap configuration" -Level Info
            return $true
        }
        
        # Configure trap community (typically 'public')
        $trapCommunity = if ($Communities.ContainsKey('public')) { 'public' } else { $Communities.Keys | Select-Object -First 1 }
        $trapPath = "$SNMPTrapsPath\$trapCommunity"
        
        if (-not (Test-Path $trapPath)) {
            New-Item -Path $trapPath -Force | Out-Null
        }
        
        $index = 1
        foreach ($destination in $TrapDestinations) {
            New-ItemProperty -Path $trapPath -Name $index.ToString() -Value $destination -PropertyType String -Force | Out-Null
            Write-LogMessage "Added trap destination: $destination" -Level Info
            $index++
        }
        
        Write-LogMessage "SNMP traps configured successfully" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring traps: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPServiceInfo {
    Write-LogMessage "Configuring SNMP service information..." -Level Info
    
    try {
        # Set contact and location
        Set-ItemProperty -Path $SNMPParametersPath -Name "sysContact" -Value $ContactInfo -Force
        Set-ItemProperty -Path $SNMPParametersPath -Name "sysLocation" -Value $Location -Force
        
        # Enable all SNMP services
        $servicesValue = 79  # All services: Physical, Applications, Datalink/Subnetwork, Internet, End-to-End
        Set-ItemProperty -Path $SNMPParametersPath -Name "EnableAuthenticationTraps" -Value 1 -Type DWord -Force
        
        Write-LogMessage "Contact: $ContactInfo" -Level Info
        Write-LogMessage "Location: $Location" -Level Info
        Write-LogMessage "SNMP service information configured successfully" -Level Success
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring service information: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPServiceStartup {
    Write-LogMessage "Configuring SNMP service startup..." -Level Info
    
    try {
        $service = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-LogMessage "SNMP service not found" -Level Error
            return $false
        }
        
        if ($DisableService) {
            Write-LogMessage "Disabling SNMP service (image preparation mode)" -Level Info
            Stop-Service -Name "SNMP" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "SNMP" -StartupType Disabled
            Write-LogMessage "SNMP service disabled" -Level Success
        }
        else {
            Write-LogMessage "Configuring SNMP service to start automatically" -Level Info
            Set-Service -Name "SNMP" -StartupType Automatic
            Start-Service -Name "SNMP" -ErrorAction SilentlyContinue
            
            Start-Sleep -Seconds 2
            
            $serviceStatus = (Get-Service -Name "SNMP").Status
            if ($serviceStatus -eq 'Running') {
                Write-LogMessage "SNMP service started successfully" -Level Success
            }
            else {
                Write-LogMessage "SNMP service configured but not running: $serviceStatus" -Level Warning
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-LogMessage "Error configuring service startup: $($_.Exception.Message)" -Level Error
        $script:ConfigurationsFailed++
        return $false
    }
}

function Test-SNMPConfiguration {
    Write-LogMessage "Verifying SNMP configuration..." -Level Info
    
    try {
        # Check service
        $service = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        if ($service) {
            Write-LogMessage "SNMP Service Status: $($service.Status)" -Level Info
            Write-LogMessage "SNMP Service Startup Type: $($service.StartType)" -Level Info
        }
        else {
            Write-LogMessage "SNMP service not found" -Level Error
            return $false
        }
        
        # Check registry configuration
        if (Test-Path $SNMPCommunitiesPath) {
            $communities = Get-ItemProperty -Path $SNMPCommunitiesPath
            $communityCount = ($communities.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
            Write-LogMessage "Configured communities: $communityCount" -Level Info
        }
        
        if (Test-Path $SNMPPermittedPath) {
            $managers = Get-ItemProperty -Path $SNMPPermittedPath
            $managerCount = ($managers.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
            Write-LogMessage "Permitted managers: $managerCount" -Level Info
        }
        
        # Check contact and location
        $params = Get-ItemProperty -Path $SNMPParametersPath
        Write-LogMessage "Contact: $($params.sysContact)" -Level Info
        Write-LogMessage "Location: $($params.sysLocation)" -Level Info
        
        Write-LogMessage "SNMP configuration verified successfully" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error during verification: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-SNMPConfigurationReport {
    Write-LogMessage "Generating SNMP configuration report..." -Level Info
    
    try {
        $reportFile = Join-Path $LogDir "snmp-config-$timestamp.txt"
        $report = @()
        
        $report += "SNMP Configuration Report"
        $report += "=" * 60
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += ""
        
        # Service status
        $service = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        if ($service) {
            $report += "Service Information:"
            $report += "  Status: $($service.Status)"
            $report += "  Startup Type: $($service.StartType)"
            $report += ""
        }
        
        # Communities
        $report += "Configured Communities:"
        if (Test-Path $SNMPCommunitiesPath) {
            $communities = Get-ItemProperty -Path $SNMPCommunitiesPath
            $communities.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                $permission = switch ($_.Value) {
                    4  { "READ ONLY" }
                    8  { "READ WRITE" }
                    16 { "READ CREATE" }
                    default { "UNKNOWN ($($_.Value))" }
                }
                $report += "  $($_.Name): $permission"
            }
        }
        $report += ""
        
        # Permitted managers
        $report += "Permitted Managers:"
        if (Test-Path $SNMPPermittedPath) {
            $managers = Get-ItemProperty -Path $SNMPPermittedPath
            $managers.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                $report += "  $($_.Value)"
            }
        }
        $report += ""
        
        # Service info
        $params = Get-ItemProperty -Path $SNMPParametersPath
        $report += "Service Information:"
        $report += "  Contact: $($params.sysContact)"
        $report += "  Location: $($params.sysLocation)"
        $report += ""
        
        # Trap destinations
        if ($TrapDestinations.Count -gt 0) {
            $report += "Trap Destinations:"
            foreach ($dest in $TrapDestinations) {
                $report += "  $dest"
            }
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-LogMessage "Configuration report saved to: $reportFile" -Level Success
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
    Write-LogMessage "SNMP Service Configuration" -Level Info
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
    
    # Install SNMP Service
    $installSuccess = Install-SNMPFeature
    
    if (-not $installSuccess) {
        Write-LogMessage "SNMP installation failed. Exiting." -Level Error
        exit 1
    }
    
    # Configure SNMP
    Set-SNMPCommunities | Out-Null
    Set-SNMPPermittedManagers | Out-Null
    Set-SNMPTraps | Out-Null
    Set-SNMPServiceInfo | Out-Null
    Set-SNMPServiceStartup | Out-Null
    
    # Verify configuration
    Test-SNMPConfiguration | Out-Null
    
    # Generate report
    Get-SNMPConfigurationReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Configuration Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Components Installed: $script:ComponentsInstalled" -Level Info
    Write-LogMessage "Configurations Applied: $script:ConfigurationsApplied" -Level Info
    Write-LogMessage "Configuration Failures: $script:ConfigurationsFailed" -Level Info
    Write-LogMessage "Duration: $($duration.TotalSeconds) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:ConfigurationsFailed -eq 0) {
        Write-LogMessage "SNMP configuration completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Configuration completed with errors. Check logs." -Level Warning
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
