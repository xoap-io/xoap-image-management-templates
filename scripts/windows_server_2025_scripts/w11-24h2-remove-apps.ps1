Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Log {
    param([string]$msg)
    Write-Host "[W11-24H2-REMOVE] $msg"
}

trap {
    Log "ERROR: $_"
    Log (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Log (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    Log 'Sleeping for 60m to give you time to look around the virtual machine before self-destruction...'
    Start-Sleep -Seconds (60*60)
    Exit 1
}

Log 'Disabling the Microsoft Consumer Experience...'
try {
    mkdir -Force 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' | Set-ItemProperty -Name DisableWindowsConsumerFeatures -Value 1
} catch {
    Log "Warning: Could not set Consumer Experience policy: $($_.Exception.Message)"
}

# Remove all the provisioned appx packages.
Get-AppXProvisionedPackage -Online | ForEach-Object {
    Log "Removing the $($_.PackageName) provisioned appx package..."
    try {
        $_ | Remove-AppxProvisionedPackage -Online | Out-Null
    } catch {
        Log "WARN Failed to remove appx: $_"
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
    $appx = Get-AppxPackage -AllUsers $_
    if ($appx) {
        Log "Removing the $($appx.Name) appx package..."
        try {
            $appx | Remove-AppxPackage -AllUsers
        } catch {
            Log "WARN Failed to remove appx: $_"
        }
    }
}
