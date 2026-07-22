<#
.SYNOPSIS
    Remove Windows 11 24H2 Appx Packages

.DESCRIPTION
    Removes provisioned and installed Windows 11 24H2 Appx packages for clean imaging.
    Disables Microsoft Consumer Experience features and removes bloatware.

    WARNING: Removing certain inbox apps makes an image UNSUPPORTED for Windows 365 /
    CloudPC. Use the -CloudPCSafe switch (or set CLOUDPC_SAFE=1) to exclude the
    Windows 365-required inbox apps from removal. Run
    windows11-Validate_CloudPC_Image.ps1 afterwards to confirm the image is still
    CloudPC-compliant.

.PARAMETER CloudPCSafe
    When set, EXCLUDES the Windows 365-required inbox apps from removal
    (Microsoft.WindowsStore, Microsoft.DesktopAppInstaller, Microsoft.SecHealthUI,
    Microsoft.Windows.Photos, Microsoft.WindowsNotepad, Microsoft.Paint and the Store
    dependency packages). Default off. Overridable via env CLOUDPC_SAFE=1.

.NOTES
    File Name      : windows11-W11_24H2_Remove_Apps.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io

.EXAMPLE
    .\windows11-W11_24H2_Remove_Apps.ps1
    Removes Windows 11 24H2 built-in apps

.EXAMPLE
    .\windows11-W11_24H2_Remove_Apps.ps1 -CloudPCSafe
    Removes built-in apps but keeps the Windows 365 CloudPC-required inbox apps.
#>

[CmdletBinding()]
param(
    [switch]$CloudPCSafe = [bool]$env:CLOUDPC_SAFE
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
        [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [W11-24H2-Remove] Transcript unavailable: $($_.Exception.Message)" }

function Write-Log {
    param(
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] [W11-24H2-Remove] $Message"
}

# Windows 365 / CloudPC-required inbox apps and Store dependencies that must remain
# provisioned for a supported custom image. Excluded from removal when -CloudPCSafe.
$script:CloudPCRequiredApps = @(
    'Microsoft.WindowsStore',
    'Microsoft.DesktopAppInstaller',
    'Microsoft.SecHealthUI',
    'Microsoft.Windows.Photos',
    'Microsoft.WindowsNotepad',
    'Microsoft.Paint',
    'Microsoft.StorePurchaseApp',
    'Microsoft.Services.Store.Engagement',
    'Microsoft.VCLibs.140.00',
    'Microsoft.NET.Native.Framework',
    'Microsoft.NET.Native.Runtime',
    'Microsoft.UI.Xaml'
)

function Test-CloudPCRequired {
    param([string]$Name)
    if (-not $CloudPCSafe) { return $false }
    foreach ($req in $script:CloudPCRequiredApps) {
        if ($Name -eq $req -or $Name -like "$req*") { return $true }
    }
    return $false
}

$startTime = Get-Date
Write-Log "===== W11_24H2_Remove_Apps starting (CloudPCSafe=$CloudPCSafe) ====="

if ($CloudPCSafe) {
    Write-Log 'CloudPCSafe enabled: Windows 365-required inbox apps will be skipped.'
}

trap {
    Write-Log "ERROR: $_"
    Write-Log (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Write-Log (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    try { Stop-Transcript | Out-Null } catch {}
    Exit 1
}

Write-Log 'Disabling the Microsoft Consumer Experience...'
try {
    mkdir -Force 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' | Set-ItemProperty -Name DisableWindowsConsumerFeatures -Value 1
} catch {
    Write-Log "Warning: Could not set Consumer Experience policy: $($_.Exception.Message)"
}

# Remove all the provisioned appx packages.
Get-AppXProvisionedPackage -Online | ForEach-Object {
    if (Test-CloudPCRequired -Name $_.DisplayName) {
        Write-Log "Skipping CloudPC-required provisioned appx package: $($_.DisplayName)"
        return
    }
    Write-Log "Removing the $($_.PackageName) provisioned appx package..."
    try {
        $_ | Remove-AppxProvisionedPackage -Online | Out-Null
    } catch {
        Write-Log "WARN Failed to remove appx: $_"
    }
}

# Remove appx packages for all users (Windows 11 24H2 list, update as needed).
@(
    'Microsoft.3DBuilder', 'Microsoft.BingWeather', 'Microsoft.DesktopAppInstaller', 'Microsoft.GetHelp',
    'Microsoft.Getstarted', 'Microsoft.HEIFImageExtension', 'Microsoft.Messaging', 'Microsoft.Microsoft3DViewer',
    'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes',
    'Microsoft.MixedReality.Portal', 'Microsoft.MSPaint', 'Microsoft.Office.OneNote', 'Microsoft.OneConnect',
    'Microsoft.Outlook.DesktopIntegrationServices', 'Microsoft.People', 'Microsoft.Print3D', 'Microsoft.ScreenSketch',
    'Microsoft.Services.Store.Engagement', 'Microsoft.SkypeApp', 'Microsoft.StorePurchaseApp', 'Microsoft.VP9VideoExtensions',
    'Microsoft.Wallet', 'Microsoft.WebMediaExtensions', 'Microsoft.WebpImageExtension', 'Microsoft.WindowsAlarms',
    'Microsoft.WindowsCalculator', 'Microsoft.WindowsCamera', 'microsoft.windowscommunicationsapps', 'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder', 'Microsoft.WindowsStore', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp',
    'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
    # Windows 11 specific apps (add/remove as needed)
    'Microsoft.Windows.DevHome', 'Microsoft.Windows.DevHome.DevHomeApp', 'Microsoft.Windows.DevHome.DevHomeInstaller',
    'Microsoft.Windows.DevHome.DevHomeSettings', 'Microsoft.Windows.DevHome.DevHomeWelcome', 'Microsoft.Windows.DevHome.DevHomeWidgets',
    'Microsoft.Windows.DevHome.DevHomeExtensions', 'Microsoft.Windows.DevHome.DevHomeFeedback', 'Microsoft.Windows.DevHome.DevHomeTips',
    'Microsoft.Windows.DevHome.DevHomeUpdate', 'Microsoft.Windows.DevHome.DevHomeWebExperience',
    'Microsoft.Windows.DevHome.DevHomeWebView', 'Microsoft.Windows.DevHome.DevHomeWebView2',
    'Microsoft.Windows.DevHome.DevHomeWebViewHost', 'Microsoft.Windows.DevHome.DevHomeWebViewShell',
    'Microsoft.Windows.DevHome.DevHomeWebViewUI', 'Microsoft.Windows.DevHome.DevHomeWebViewUX',
    'Microsoft.Windows.DevHome.DevHomeWebViewX', 'Microsoft.Windows.DevHome.DevHomeWebViewY',
    'Microsoft.Windows.DevHome.DevHomeWebViewZ', 'Microsoft.Windows.DevHome.DevHomeWebViewAA',
    'Microsoft.Windows.DevHome.DevHomeWebViewAB', 'Microsoft.Windows.DevHome.DevHomeWebViewAC',
    'Microsoft.Windows.DevHome.DevHomeWebViewAD', 'Microsoft.Windows.DevHome.DevHomeWebViewAE',
    'Microsoft.Windows.DevHome.DevHomeWebViewAF', 'Microsoft.Windows.DevHome.DevHomeWebViewAG',
    'Microsoft.Windows.DevHome.DevHomeWebViewAH', 'Microsoft.Windows.DevHome.DevHomeWebViewAI',
    'Microsoft.Windows.DevHome.DevHomeWebViewAJ', 'Microsoft.Windows.DevHome.DevHomeWebViewAK',
    'Microsoft.Windows.DevHome.DevHomeWebViewAL', 'Microsoft.Windows.DevHome.DevHomeWebViewAM',
    'Microsoft.Windows.DevHome.DevHomeWebViewAN', 'Microsoft.Windows.DevHome.DevHomeWebViewAO',
    'Microsoft.Windows.DevHome.DevHomeWebViewAP', 'Microsoft.Windows.DevHome.DevHomeWebViewAQ',
    'Microsoft.Windows.DevHome.DevHomeWebViewAR', 'Microsoft.Windows.DevHome.DevHomeWebViewAS',
    'Microsoft.Windows.DevHome.DevHomeWebViewAT', 'Microsoft.Windows.DevHome.DevHomeWebViewAU',
    'Microsoft.Windows.DevHome.DevHomeWebViewAV', 'Microsoft.Windows.DevHome.DevHomeWebViewAW',
    'Microsoft.Windows.DevHome.DevHomeWebViewAX', 'Microsoft.Windows.DevHome.DevHomeWebViewAY',
    'Microsoft.Windows.DevHome.DevHomeWebViewAZ', 'Microsoft.Windows.DevHome.DevHomeWebViewBA',
    'Microsoft.Windows.DevHome.DevHomeWebViewBB', 'Microsoft.Windows.DevHome.DevHomeWebViewBC',
    'Microsoft.Windows.DevHome.DevHomeWebViewBD', 'Microsoft.Windows.DevHome.DevHomeWebViewBE',
    'Microsoft.Windows.DevHome.DevHomeWebViewBF', 'Microsoft.Windows.DevHome.DevHomeWebViewBG',
    'Microsoft.Windows.DevHome.DevHomeWebViewBH', 'Microsoft.Windows.DevHome.DevHomeWebViewBI',
    'Microsoft.Windows.DevHome.DevHomeWebViewBJ', 'Microsoft.Windows.DevHome.DevHomeWebViewBK',
    'Microsoft.Windows.DevHome.DevHomeWebViewBL', 'Microsoft.Windows.DevHome.DevHomeWebViewBM',
    'Microsoft.Windows.DevHome.DevHomeWebViewBN', 'Microsoft.Windows.DevHome.DevHomeWebViewBO',
    'Microsoft.Windows.DevHome.DevHomeWebViewBP', 'Microsoft.Windows.DevHome.DevHomeWebViewBQ',
    'Microsoft.Windows.DevHome.DevHomeWebViewBR', 'Microsoft.Windows.DevHome.DevHomeWebViewBS',
    'Microsoft.Windows.DevHome.DevHomeWebViewBT', 'Microsoft.Windows.DevHome.DevHomeWebViewBU',
    'Microsoft.Windows.DevHome.DevHomeWebViewBV', 'Microsoft.Windows.DevHome.DevHomeWebViewBW',
    'Microsoft.Windows.DevHome.DevHomeWebViewBX', 'Microsoft.Windows.DevHome.DevHomeWebViewBY',
    'Microsoft.Windows.DevHome.DevHomeWebViewBZ', 'Microsoft.Windows.DevHome.DevHomeWebViewCA',
    'Microsoft.Windows.DevHome.DevHomeWebViewCB', 'Microsoft.Windows.DevHome.DevHomeWebViewCC',
    'Microsoft.Windows.DevHome.DevHomeWebViewCD', 'Microsoft.Windows.DevHome.DevHomeWebViewCE',
    'Microsoft.Windows.DevHome.DevHomeWebViewCF', 'Microsoft.Windows.DevHome.DevHomeWebViewCG',
    'Microsoft.Windows.DevHome.DevHomeWebViewCH', 'Microsoft.Windows.DevHome.DevHomeWebViewCI',
    'Microsoft.Windows.DevHome.DevHomeWebViewCJ', 'Microsoft.Windows.DevHome.DevHomeWebViewCK',
    'Microsoft.Windows.DevHome.DevHomeWebViewCL', 'Microsoft.Windows.DevHome.DevHomeWebViewCM',
    'Microsoft.Windows.DevHome.DevHomeWebViewCN', 'Microsoft.Windows.DevHome.DevHomeWebViewCO',
    'Microsoft.Windows.DevHome.DevHomeWebViewCP', 'Microsoft.Windows.DevHome.DevHomeWebViewCQ',
    'Microsoft.Windows.DevHome.DevHomeWebViewCR', 'Microsoft.Windows.DevHome.DevHomeWebViewCS',
    'Microsoft.Windows.DevHome.DevHomeWebViewCT', 'Microsoft.Windows.DevHome.DevHomeWebViewCU',
    'Microsoft.Windows.DevHome.DevHomeWebViewCV', 'Microsoft.Windows.DevHome.DevHomeWebViewCW',
    'Microsoft.Windows.DevHome.DevHomeWebViewCX', 'Microsoft.Windows.DevHome.DevHomeWebViewCY',
    'Microsoft.Windows.DevHome.DevHomeWebViewCZ'
) | ForEach-Object {
    if (Test-CloudPCRequired -Name $_) {
        Write-Log "Skipping CloudPC-required appx package: $_"
        return
    }
    $appx = Get-AppxPackage -AllUsers $_
    if ($appx) {
        Write-Log "Removing the $($appx.Name) appx package..."
        try {
            $appx | Remove-AppxPackage -AllUsers
        } catch {
            Write-Log "WARN Failed to remove appx: $_"
        }
    }
}

Write-Log "===== W11_24H2_Remove_Apps complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
try { Stop-Transcript | Out-Null } catch {}
exit 0
