<#
.SYNOPSIS
    Remove Built-in Windows Apps

.DESCRIPTION
    Removes provisioned and installed Windows 10/11 Store applications (AppX packages)
    to reduce image size and remove unnecessary applications. Includes disabling
    Microsoft Consumer Experience features.

.NOTES
    File Name      : windows11-Remove_Apps.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows11-Remove_Apps.ps1
    Removes all specified Windows Store applications
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

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
    Write-Host "[$timestamp] [$prefix] [RemoveApps] $Message"
}

trap {
    Write-Log "Critical error: $_" -Level Error
    ($_.ScriptStackTrace -split '\r?\n') | ForEach-Object { Write-Log "STACK: $_" -Level Error }
    Write-Log 'Sleeping for 60m to allow investigation...' -Level Error
    Start-Sleep -Seconds 3600
    exit 1
}

# Comprehensive list of apps to remove
$appsToRemove = @(
    'Clipchamp.Clipchamp',
    'Microsoft.549981C3F5F10',
    'Microsoft.BingNews',
    'Microsoft.BingSearch',
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
    'Microsoft.OutlookForWindows',
    'Microsoft.Paint',
    'Microsoft.People',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.ScreenSketch',
    'Microsoft.Services.Store.Engagement',
    'Microsoft.SkypeApp',
    'Microsoft.StorePurchaseApp',
    'Microsoft.Todos',
    'Microsoft.Wallet',
    'Microsoft.Windows.DevHome',
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
    'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftCorporationII.QuickAssist',
    'MicrosoftTeams',
    'MSTeams'
)

try {
    Write-Log "Starting Windows Store application removal..."
    
    # Disable Microsoft Consumer Experience
    Write-Log "Disabling Microsoft Consumer Experience features..."
    $cloudContentPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    if (-not (Test-Path $cloudContentPath)) {
        New-Item -Path $cloudContentPath -Force | Out-Null
    }
    Set-ItemProperty -Path $cloudContentPath -Name DisableWindowsConsumerFeatures -Value 1
    Write-Log "Consumer Experience features disabled"
    
    # Import Appx module if running on PowerShell Core and Windows 10
    $currentVersionKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$currentVersionKey.CurrentBuildNumber
    
    if (($PSVersionTable.PSEdition -ne 'Desktop') -and ($build -lt 22000)) {
        Write-Log "PowerShell Core detected on Windows 10 - importing Appx module..."
        Import-Module Appx -UseWindowsPowerShell
    }
    
    # Remove provisioned packages (for new users)
    Write-Log "Removing provisioned AppX packages..."
    $provisionedPackages = Get-AppXProvisionedPackage -Online
    $provisionedRemoved = 0
    $provisionedFailed = 0
    
    foreach ($package in $provisionedPackages) {
        $packageName = $package.DisplayName
        
        # Check if package matches any in our removal list
        $shouldRemove = $appsToRemove | Where-Object {
            $packageName -like "$_*" -or $packageName -eq $_
        }
        
        if ($shouldRemove) {
            Write-Log "Removing provisioned package: $packageName"
            try {
                $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
                $provisionedRemoved++
            } catch {
                Write-Log "Failed to remove provisioned package $packageName : $($_.Exception.Message)" -Level Warning
                $provisionedFailed++
            }
        }
    }
    
    Write-Log "Provisioned packages: $provisionedRemoved removed, $provisionedFailed failed"
    
    # Remove installed packages (current users)
    Write-Log "Removing installed AppX packages for all users..."
    $installedRemoved = 0
    $installedFailed = 0
    $installedNotFound = 0
    
    foreach ($appName in $appsToRemove) {
        try {
            $appx = Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue
            
            if ($appx) {
                Write-Log "Removing installed package: $($appx.Name)"
                try {
                    $appx | Remove-AppxPackage -AllUsers -ErrorAction Stop
                    $installedRemoved++
                } catch {
                    Write-Log "Failed to remove installed package $($appx.Name): $($_.Exception.Message)" -Level Warning
                    $installedFailed++
                }
            } else {
                $installedNotFound++
            }
        } catch {
            Write-Log "Error checking package $appName : $($_.Exception.Message)" -Level Warning
            $installedFailed++
        }
    }
    
    Write-Log "Installed packages: $installedRemoved removed, $installedFailed failed, $installedNotFound not found"
    
    # Summary
    $totalRemoved = $provisionedRemoved + $installedRemoved
    $totalFailed = $provisionedFailed + $installedFailed
    
    Write-Log "=== Removal Summary ==="
    Write-Log "Total packages removed: $totalRemoved"
    Write-Log "Total packages failed: $totalFailed"
    Write-Log "Packages not found: $installedNotFound"
    
    if ($totalRemoved -gt 0) {
        Write-Log "Windows Store application removal completed successfully"
    } else {
        Write-Log "No packages were removed - they may already be uninstalled" -Level Warning
    }
    
} catch {
    Write-Log "Application removal failed: $($_.Exception.Message)" -Level Error
    exit 1
}