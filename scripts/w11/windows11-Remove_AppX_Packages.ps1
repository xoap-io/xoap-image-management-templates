<#
.SYNOPSIS
    Removes built-in and provisioned AppX packages from Windows 10/11

.DESCRIPTION
    This script disables the Microsoft Consumer Experience and removes unwanted AppX packages for all users.
    Developed and optimized for use with the XOAP Image Management module, but can be used independently.
    
    Features:
    - Removes provisioned packages (for new users)
    - Removes installed packages (all users)
    - Disables Windows Consumer Experience
    - Comprehensive logging to C:\xoap-logs
    
.NOTES
    File Name      : windows11-Remove_AppX_Packages.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-packer-templates

.EXAMPLE
    .\windows11-Remove_AppX_Packages.ps1
    Removes all specified AppX packages and provisions
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Initialize logging
$script:LogFile = $null
$script:TranscriptStarted = $false

function Initialize-Logging {
    try {
        $logDir = 'C:\xoap-logs'
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $scriptName = if ($PSCommandPath) {
            [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        } else {
            'Remove_AppX_Packages'
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:LogFile = Join-Path $logDir "$scriptName-$timestamp.log"
        
        Start-Transcript -Path $script:LogFile -Append | Out-Null
        $script:TranscriptStarted = $true
        
        Write-Log "Logging initialized: $script:LogFile"
    } catch {
        Write-Warning "Failed to initialize transcript logging: $($_.Exception.Message)"
        $script:TranscriptStarted = $false
    }
}

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
    
    $logEntry = "[$timestamp] [$prefix] $Message"
    Write-Host $logEntry
}

function Stop-Logging {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
            $script:TranscriptStarted = $false
        } catch {
            Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
        }
    }
}

trap {
    Write-Log "Critical error: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log "Exception: $($_.Exception.ToString())" -Level Error
    Stop-Logging
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

# App packages to remove
$script:AppPackagesToRemove = @(
    'Clipchamp.Clipchamp',
    'Microsoft.549981C3F5F10',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.GamingApp',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.Microsoft3DViewer',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.MixedReality.Portal',
    'Microsoft.MSPaint',
    'Microsoft.Office.OneNote',
    'Microsoft.OneDriveSync',
    'Microsoft.Paint',
    'Microsoft.People',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.ScreenSketch',
    'Microsoft.Services.Store.Engagement',
    'Microsoft.SkypeApp',
    'Microsoft.StorePurchaseApp',
    'Microsoft.Todos',
    'Microsoft.Wallet',
    'Microsoft.Windows.Photos',
    'Microsoft.WindowsAlarms',
    'Microsoft.WindowsCalculator',
    'Microsoft.WindowsCamera',
    'microsoft.windowscommunicationsapps',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.WindowsStore',
    'Microsoft.Xbox.TCUI',
    'Microsoft.XboxApp',
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.YourPhone',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    'MicrosoftCorporationII.QuickAssist',
    'MicrosoftWindows.Client.WebExperience',
    'MicrosoftTeams'
)

function Disable-ConsumerExperience {
    Write-Log "Disabling Microsoft Consumer Experience features..."
    
    try {
        $cloudContentPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        if (-not (Test-Path $cloudContentPath)) {
            New-Item -Path $cloudContentPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $cloudContentPath -Name DisableWindowsConsumerFeatures -Value 1 -Force
        Write-Log "Consumer Experience features disabled successfully"
        return $true
    } catch {
        Write-Log "Failed to disable Consumer Experience: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Initialize-AppxModule {
    Write-Log "Checking if Appx module needs special handling..."
    
    try {
        $currentVersionKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $build = [int]$currentVersionKey.CurrentBuildNumber
        
        if (($PSVersionTable.PSEdition -ne 'Desktop') -and ($build -lt 22000)) {
            Write-Log "PowerShell Core detected on Windows 10 - importing Appx module..."
            Import-Module Appx -UseWindowsPowerShell
            Write-Log "Appx module imported successfully"
        } else {
            Write-Log "Appx module available natively"
        }
        return $true
    } catch {
        Write-Log "Failed to initialize Appx module: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Remove-ProvisionedPackages {
    Write-Log "Removing provisioned AppX packages (for new users)..."
    
    $stats = @{
        Total = 0
        Removed = 0
        Failed = 0
    }
    
    try {
        $provisionedPackages = Get-AppXProvisionedPackage -Online
        $stats.Total = $provisionedPackages.Count
        
        Write-Log "Found $($stats.Total) provisioned packages"
        
        foreach ($package in $provisionedPackages) {
            $packageName = $package.DisplayName
            
            # Check if package matches removal list
            $shouldRemove = $script:AppPackagesToRemove | Where-Object {
                $packageName -like "$_*" -or $packageName -eq $_
            }
            
            if ($shouldRemove) {
                Write-Log "Removing provisioned: $packageName"
                try {
                    $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
                    $stats.Removed++
                } catch {
                    Write-Log "Failed to remove provisioned package $packageName : $($_.Exception.Message)" -Level Warning
                    $stats.Failed++
                }
            }
        }
        
        Write-Log "Provisioned packages: $($stats.Removed) removed, $($stats.Failed) failed, $($stats.Total - $stats.Removed - $stats.Failed) skipped"
        return $stats
        
    } catch {
        Write-Log "Error processing provisioned packages: $($_.Exception.Message)" -Level Error
        return $stats
    }
}

function Remove-InstalledPackages {
    Write-Log "Removing installed AppX packages (all users)..."
    
    $stats = @{
        Total = $script:AppPackagesToRemove.Count
        Removed = 0
        Failed = 0
        NotFound = 0
    }
    
    foreach ($packageName in $script:AppPackagesToRemove) {
        try {
            $appx = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
            
            if ($appx) {
                Write-Log "Removing installed: $($appx.Name)"
                try {
                    $appx | Remove-AppxPackage -AllUsers -ErrorAction Stop
                    $stats.Removed++
                } catch {
                    Write-Log "Failed to remove $($appx.Name): $($_.Exception.Message)" -Level Warning
                    $stats.Failed++
                }
            } else {
                $stats.NotFound++
            }
        } catch {
            Write-Log "Error processing $packageName : $($_.Exception.Message)" -Level Warning
            $stats.Failed++
        }
    }
    
    Write-Log "Installed packages: $($stats.Removed) removed, $($stats.Failed) failed, $($stats.NotFound) not found"
    return $stats
}

# Main execution
try {
    Initialize-Logging
    
    Write-Log "=== Starting AppX Package Removal ==="
    Write-Log "Script: Remove_AppX_Packages.ps1"
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Log "OS Build: $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber)"
    
    # Disable Consumer Experience
    $consumerDisabled = Disable-ConsumerExperience
    
    # Initialize Appx module
    $appxReady = Initialize-AppxModule
    
    if (-not $appxReady) {
        Write-Log "Appx module initialization failed - attempting to continue anyway" -Level Warning
    }
    
    # Remove provisioned packages
    $provisionedStats = Remove-ProvisionedPackages
    
    # Remove installed packages
    $installedStats = Remove-InstalledPackages
    
    # Summary
    Write-Log "=== Removal Summary ==="
    Write-Log "Consumer Experience: $(if ($consumerDisabled) { 'Disabled' } else { 'Failed' })"
    Write-Log "Provisioned packages removed: $($provisionedStats.Removed)"
    Write-Log "Installed packages removed: $($installedStats.Removed)"
    Write-Log "Total packages removed: $($provisionedStats.Removed + $installedStats.Removed)"
    Write-Log "Total failures: $($provisionedStats.Failed + $installedStats.Failed)"
    
    Write-Log "AppX package removal completed successfully"
    
} catch {
    Write-Log "AppX removal script failed: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    Stop-Logging
}
