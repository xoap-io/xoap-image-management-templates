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

# Leveled logging function (stdout is the state channel)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [SNMP] $Message"
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-SNMPFeature {
    Write-Log "Checking SNMP Service installation..." -Level INFO
    
    try {
        $snmpService = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        
        if ($snmpService) {
            Write-Log "SNMP Service is already installed" -Level INFO
            return $true
        }
        
        Write-Log "Installing SNMP Service feature..." -Level INFO
        
        # Install using DISM
        $result = Start-Process -FilePath "dism.exe" -ArgumentList "/online /enable-feature /featurename:SNMP /all /quiet /norestart" -Wait -PassThru -NoNewWindow
        
        if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 3010) {
            Write-Log "SNMP Service installed successfully" -Level INFO
            $script:ComponentsInstalled++
            
            # Wait for service to be available
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-Log "SNMP installation failed with exit code: $($result.ExitCode)" -Level ERROR
            
            # Try Windows capability method
            Write-Log "Attempting alternative installation method..." -Level INFO
            Add-WindowsCapability -Online -Name "SNMP.Client~~~~0.0.1.0" -ErrorAction Stop
            
            Write-Log "SNMP installed via Windows Capability" -Level INFO
            $script:ComponentsInstalled++
            return $true
        }
    }
    catch {
        Write-Log "Error installing SNMP: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPCommunities {
    Write-Log "Configuring SNMP communities..." -Level INFO
    
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
            Write-Log "Added community: $communityName ($permission)" -Level INFO
        }
        
        Write-Log "SNMP communities configured successfully" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring communities: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPPermittedManagers {
    Write-Log "Configuring permitted SNMP managers..." -Level INFO
    
    try {
        # Create PermittedManagers registry key if it doesn't exist
        if (-not (Test-Path $SNMPPermittedPath)) {
            New-Item -Path $SNMPPermittedPath -Force | Out-Null
        }
        
        # If no managers specified, accept from any host
        if ($PermittedManagers.Count -eq 0) {
            New-ItemProperty -Path $SNMPPermittedPath -Name "1" -Value "0.0.0.0" -PropertyType String -Force | Out-Null
            Write-Log "Configured to accept SNMP requests from any host (0.0.0.0)" -Level WARN
        }
        else {
            # Add each permitted manager
            $index = 1
            foreach ($manager in $PermittedManagers) {
                New-ItemProperty -Path $SNMPPermittedPath -Name $index.ToString() -Value $manager -PropertyType String -Force | Out-Null
                Write-Log "Added permitted manager: $manager" -Level INFO
                $index++
            }
        }
        
        Write-Log "Permitted managers configured successfully" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring permitted managers: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPTraps {
    Write-Log "Configuring SNMP traps..." -Level INFO
    
    try {
        if ($TrapDestinations.Count -eq 0) {
            Write-Log "No trap destinations specified, skipping trap configuration" -Level INFO
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
            Write-Log "Added trap destination: $destination" -Level INFO
            $index++
        }
        
        Write-Log "SNMP traps configured successfully" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring traps: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPServiceInfo {
    Write-Log "Configuring SNMP service information..." -Level INFO
    
    try {
        # Set contact and location
        Set-ItemProperty -Path $SNMPParametersPath -Name "sysContact" -Value $ContactInfo -Force
        Set-ItemProperty -Path $SNMPParametersPath -Name "sysLocation" -Value $Location -Force
        
        # Enable all SNMP services
        $servicesValue = 79  # All services: Physical, Applications, Datalink/Subnetwork, Internet, End-to-End
        Set-ItemProperty -Path $SNMPParametersPath -Name "EnableAuthenticationTraps" -Value 1 -Type DWord -Force
        
        Write-Log "Contact: $ContactInfo" -Level INFO
        Write-Log "Location: $Location" -Level INFO
        Write-Log "SNMP service information configured successfully" -Level INFO
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring service information: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Set-SNMPServiceStartup {
    Write-Log "Configuring SNMP service startup..." -Level INFO
    
    try {
        $service = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-Log "SNMP service not found" -Level ERROR
            return $false
        }
        
        if ($DisableService) {
            Write-Log "Disabling SNMP service (image preparation mode)" -Level INFO
            Stop-Service -Name "SNMP" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "SNMP" -StartupType Disabled
            Write-Log "SNMP service disabled" -Level INFO
        }
        else {
            Write-Log "Configuring SNMP service to start automatically" -Level INFO
            Set-Service -Name "SNMP" -StartupType Automatic
            Start-Service -Name "SNMP" -ErrorAction SilentlyContinue
            
            Start-Sleep -Seconds 2
            
            $serviceStatus = (Get-Service -Name "SNMP").Status
            if ($serviceStatus -eq 'Running') {
                Write-Log "SNMP service started successfully" -Level INFO
            }
            else {
                Write-Log "SNMP service configured but not running: $serviceStatus" -Level WARN
            }
        }
        
        $script:ConfigurationsApplied++
        return $true
    }
    catch {
        Write-Log "Error configuring service startup: $($_.Exception.Message)" -Level ERROR
        $script:ConfigurationsFailed++
        return $false
    }
}

function Test-SNMPConfiguration {
    Write-Log "Verifying SNMP configuration..." -Level INFO
    
    try {
        # Check service
        $service = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "SNMP Service Status: $($service.Status)" -Level INFO
            Write-Log "SNMP Service Startup Type: $($service.StartType)" -Level INFO
        }
        else {
            Write-Log "SNMP service not found" -Level ERROR
            return $false
        }
        
        # Check registry configuration
        if (Test-Path $SNMPCommunitiesPath) {
            $communities = Get-ItemProperty -Path $SNMPCommunitiesPath
            $communityCount = ($communities.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
            Write-Log "Configured communities: $communityCount" -Level INFO
        }
        
        if (Test-Path $SNMPPermittedPath) {
            $managers = Get-ItemProperty -Path $SNMPPermittedPath
            $managerCount = ($managers.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
            Write-Log "Permitted managers: $managerCount" -Level INFO
        }
        
        # Check contact and location
        $params = Get-ItemProperty -Path $SNMPParametersPath
        Write-Log "Contact: $($params.sysContact)" -Level INFO
        Write-Log "Location: $($params.sysLocation)" -Level INFO
        
        Write-Log "SNMP configuration verified successfully" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error during verification: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Get-SNMPConfigurationReport {
    Write-Log "Generating SNMP configuration report..." -Level INFO
    
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
        
        Write-Log "Configuration report saved to: $reportFile" -Level INFO
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
    # Setup local file logging to C:\xoap-logs (transcript captures all host output)
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
    } catch {
        Write-Host "[WARN] Failed to start transcript logging to $LogDir : $($_.Exception.Message)"
    }

    $scriptStartTime = Get-Date

    Write-Log "===== Configure_SNMP starting ====="

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Install SNMP Service
    $installSuccess = Install-SNMPFeature
    
    if (-not $installSuccess) {
        Write-Log "SNMP installation failed. Exiting." -Level ERROR
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
    $duration = ((Get-Date) - $scriptStartTime).TotalSeconds

    if ($script:ConfigurationsFailed -eq 0) {
        Write-Log "===== Configure_SNMP complete in $([int]$duration)s; installed=$($script:ComponentsInstalled) applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) ====="
        exit 0
    }
    else {
        Write-Log "===== Configure_SNMP complete in $([int]$duration)s; installed=$($script:ComponentsInstalled) applied=$($script:ConfigurationsApplied) failed=$($script:ConfigurationsFailed) =====" -Level WARN
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
