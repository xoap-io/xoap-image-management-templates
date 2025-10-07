<#
    .SYNOPSIS
        Install evergreen core applications.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [System.String] $Path = "$env:SystemDrive\Apps"
)

function Log {
    param([string]$msg)
    Write-Host "[BASELINE] $msg"
}

#region Functions
Function Install-RequiredModule {
    Log "Installing required modules..."
    Install-Module -Name Evergreen -AllowClobber -Force
    Install-Module -Name VcRedist -AllowClobber -Force
}

Function Install-VcRedistributable ($Path) {
    Log "Installing Microsoft Visual C++ Redistributables..."
    If (!(Test-Path $Path)) { New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null }
    $VcList = Get-VcList -Release 2010, 2012, 2013, 2019
    Save-VcRedist -Path $Path -VcList $VcList -Verbose
    Install-VcRedist -VcList $VcList -Path $Path -Verbose
    Log "VcRedist installation complete."
}

Function Install-MicrosoftEdge ($Path) {
    Log "Installing Microsoft Edge..."
    $App = Get-EvergreenApp -Name "MicrosoftEdge" | Where-Object { $_.Architecture -eq "x64" -and $_.Channel -eq "Stable" -and $_.Release -eq "Enterprise" } `
    | Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | Select-Object -First 1
    If ($App) {
        Log "Downloading Microsoft Edge..."
        If (!(Test-Path $Path)) { New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null }
        $OutFile = Save-EvergreenApp -InputObject $App -Path $Path -WarningAction "SilentlyContinue"
        Log "Installing Microsoft Edge..."
        try {
            $params = @{
                FilePath     = "$env:SystemRoot\System32\msiexec.exe"
                ArgumentList = "/package $($OutFile.FullName) /quiet /norestart DONOTCREATEDESKTOPSHORTCUT=true"
                WindowStyle  = "Hidden"
                Wait         = $True
                Verbose      = $True
            }
            Start-Process @params
        } catch {
            Log "ERR: Failed to install Microsoft Edge. $_"
        }
        Log "Configuring post-install preferences..."
        $prefs = @{
            "homepage"               = "edge://newtab"
            "homepage_is_newtabpage" = $false
            "browser"                = @{ "show_home_button" = $true }
            "distribution"           = @{
                "skip_first_run_ui"              = $True
                "show_welcome_page"              = $False
                "import_search_engine"           = $False
                "import_history"                 = $False
                "do_not_create_any_shortcuts"    = $False
                "do_not_create_taskbar_shortcut" = $False
                "do_not_create_desktop_shortcut" = $True
                "do_not_launch_chrome"           = $True
                "make_chrome_default"            = $True
                "make_chrome_default_for_user"   = $True
                "system_level"                   = $True
            }
        }
        $prefs | ConvertTo-Json | Set-Content -Path "${Env:ProgramFiles(x86)}\Microsoft\Edge\Application\master_preferences" -Force
        $services = "edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService"
        ForEach ($service in $services) {
            try {
                Get-Service -Name $service | Set-Service -StartupType "Disabled"
            } catch {
                Log "Warning: Could not disable service $service. $_"
            }
        }
        ForEach ($task in (Get-ScheduledTask -TaskName *Edge*)) {
            try {
                Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$False -ErrorAction SilentlyContinue
            } catch {
                Log "Warning: Could not unregister scheduled task $($task.TaskName). $_"
            }
        }
        Log "Microsoft Edge installation and configuration complete."
    } Else {
        Log "Failed to retrieve Microsoft Edge."
    }
}
#endregion Functions

#region Script logic
$VerbosePreference = "Continue"
$ProgressPreference = "SilentlyContinue"

If (!(Test-Path $Path)) { New-Item -Path $Path -Type Directory -Force -ErrorAction SilentlyContinue }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null

# Trust the PSGallery for modules
If (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
    Log "Trusting the repository: PSGallery"
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
    Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
}

Install-RequiredModule
Install-VcRedistributable -Path "$Path\VcRedist"
Install-MicrosoftEdge -Path "$Path\Edge"
Log "Complete: $($MyInvocation.MyCommand)."
#endregion
