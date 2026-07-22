<#
.SYNOPSIS
    Install Evergreen Core Applications

.DESCRIPTION
    Installs baseline applications using the Evergreen module including Visual C++ Redistributables,
    Microsoft Edge, and other core applications for Windows Server 2025.

.PARAMETER Path
    Directory path where application installers will be saved. Default: C:\Apps

.NOTES
    File Name      : windows-server-install_server_baseline_apps.ps1
    Prerequisite   : PowerShell 5.1 or higher, Internet connection
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_server_baseline_apps.ps1
    Installs baseline applications to default path

.EXAMPLE
    .\windows-server-install_server_baseline_apps.ps1 -Path "D:\Applications"
    Installs baseline applications to custom path
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [System.String] $Path = "$env:SystemDrive\Apps"
)

$script:Component = 'Baseline'
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    Write-Host ("[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message)
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [Baseline] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

trap {
    Write-Log "Critical error: $_" -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

#region Functions
Function Install-RequiredModule {
    Write-Log "Installing required modules..."
    Install-Module -Name Evergreen -AllowClobber -Force
    Install-Module -Name VcRedist -AllowClobber -Force
}

Function Install-VcRedistributable ($Path) {
    Write-Log "Installing Microsoft Visual C++ Redistributables..."
    If (!(Test-Path $Path)) { New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null }
    $VcList = Get-VcList -Release 2010, 2012, 2013, 2019
    Save-VcRedist -Path $Path -VcList $VcList -Verbose
    Install-VcRedist -VcList $VcList -Path $Path -Verbose
    Write-Log "VcRedist installation complete."
}

Function Install-MicrosoftEdge ($Path) {
    Write-Log "Installing Microsoft Edge..."
    $App = Get-EvergreenApp -Name "MicrosoftEdge" | Where-Object { $_.Architecture -eq "x64" -and $_.Channel -eq "Stable" -and $_.Release -eq "Enterprise" } `
    | Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | Select-Object -First 1
    If ($App) {
        Write-Log "Downloading Microsoft Edge..."
        If (!(Test-Path $Path)) { New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null }
        $OutFile = Save-EvergreenApp -InputObject $App -Path $Path -WarningAction "SilentlyContinue"
        Write-Log "Installing Microsoft Edge..."
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
            Write-Log "Failed to install Microsoft Edge. $_" -Level ERROR
        }
        Write-Log "Configuring post-install preferences..."
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
                Write-Log "Could not disable service $service. $_" -Level WARN
            }
        }
        ForEach ($task in (Get-ScheduledTask -TaskName *Edge*)) {
            try {
                Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$False -ErrorAction SilentlyContinue
            } catch {
                Write-Log "Could not unregister scheduled task $($task.TaskName). $_" -Level WARN
            }
        }
        Write-Log "Microsoft Edge installation and configuration complete."
    } Else {
        Write-Log "Failed to retrieve Microsoft Edge." -Level WARN
    }
}
#endregion Functions

#region Script logic
$VerbosePreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$startTime = Get-Date
Write-Log "===== install_server_baseline_apps starting ====="

If (!(Test-Path $Path)) { New-Item -Path $Path -Type Directory -Force -ErrorAction SilentlyContinue }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path $Path -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null

# Trust the PSGallery for modules
If (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
    Write-Log "Trusting the repository: PSGallery"
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
    Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
}

Install-RequiredModule
Install-VcRedistributable -Path "$Path\VcRedist"
Install-MicrosoftEdge -Path "$Path\Edge"
Write-Log "===== install_server_baseline_apps complete in $([int]((Get-Date) - $startTime).TotalSeconds)s ====="
try { Stop-Transcript | Out-Null } catch {}
exit 0
#endregion
