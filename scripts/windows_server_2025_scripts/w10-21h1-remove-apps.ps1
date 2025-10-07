Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Log {
    param([string]$msg)
    Write-Host "[W10-21H1-REMOVE] $msg"
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

# Remove appx packages for all users.
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
    'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo'
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
