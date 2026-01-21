<#
.SYNOPSIS
    Removes OneDrive and Microsoft Teams from Windows 10/11

.DESCRIPTION
    This script completely removes OneDrive and Microsoft Teams from Windows 10/11 including:
    - Uninstalling applications
    - Clearing cache and temporary files
    - Removing registry entries and shortcuts
    - Disabling OneDrive via Group Policy
    - Cleaning up WinSxS leftovers
    
    Developed and optimized for use with the XOAP Image Management module.

.NOTES
    File Name      : windows11-Remove_OneDrive_And_Teams.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.COMPONENT
    PowerShell

.LINK
    https://github.com/xoap-io/xoap-packer-templates

.EXAMPLE
    .\windows11-Remove_OneDrive_And_Teams.ps1
    Removes OneDrive and Microsoft Teams completely
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
            'Remove_OneDrive_And_Teams'
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

function New-DirectoryIfNotExists {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Set-FolderOwnership {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return
    }
    
    Write-Log "Taking ownership of: $Path"
    
    try {
        & takeown.exe /A /F $Path /R /D Y 2>&1 | Out-Null
        
        $admins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $admins = $admins.Translate([System.Security.Principal.NTAccount])
        
        $acl = Get-Acl $Path
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $admins, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl
        
        Write-Log "Ownership set successfully"
    } catch {
        Write-Log "Failed to take ownership: $($_.Exception.Message)" -Level Warning
    }
}

function Stop-ProcessSafely {
    param(
        [string]$ProcessName,
        [string]$Description
    )
    
    try {
        $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($processes) {
            Write-Log "Stopping $Description process(es)..."
            $processes | Stop-Process -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Log "$Description stopped successfully"
            return $true
        }
    } catch {
        Write-Log "Failed to stop $Description : $($_.Exception.Message)" -Level Warning
    }
    return $false
}

function Remove-ItemSafely {
    param(
        [string]$Path,
        [string]$Description
    )
    
    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed: $($Description ? $Description : $Path)"
            return $true
        } catch {
            Write-Log "Failed to remove $($Description ? $Description : $Path): $($_.Exception.Message)" -Level Warning
            return $false
        }
    }
    return $false
}

function Remove-OneDrive {
    Write-Log "=== Starting OneDrive Removal ==="
    
    # Stop processes
    Stop-ProcessSafely -ProcessName 'OneDrive' -Description 'OneDrive'
    $explorerStopped = Stop-ProcessSafely -ProcessName 'explorer' -Description 'Explorer'
    
    # Uninstall OneDrive
    Write-Log "Uninstalling OneDrive..."
    $uninstallers = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    )
    
    foreach ($uninstaller in $uninstallers) {
        if (Test-Path $uninstaller) {
            Write-Log "Running uninstaller: $uninstaller"
            try {
                Start-Process -FilePath $uninstaller -ArgumentList '/uninstall' -Wait -NoNewWindow
            } catch {
                Write-Log "Uninstaller failed: $($_.Exception.Message)" -Level Warning
            }
        }
    }
    
    # Disable via Group Policy
    Write-Log "Disabling OneDrive via Group Policy..."
    $policyPath = 'HKLM:\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'
    New-DirectoryIfNotExists -Path $policyPath
    Set-ItemProperty -Path $policyPath -Name DisableFileSyncNGSC -Value 1 -Force
    
    # Remove leftover files
    Write-Log "Removing OneDrive leftover files..."
    $leftoverPaths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive",
        'C:\OneDriveTemp'
    )
    
    foreach ($path in $leftoverPaths) {
        Remove-ItemSafely -Path $path -Description "OneDrive folder: $path"
    }
    
    # Remove from Explorer sidebar
    Write-Log "Removing OneDrive from Explorer sidebar..."
    try {
        New-PSDrive -PSProvider Registry -Root HKEY_CLASSES_ROOT -Name HKCR -ErrorAction SilentlyContinue | Out-Null
        
        $clsids = @(
            'HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
            'HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        )
        
        foreach ($clsid in $clsids) {
            New-DirectoryIfNotExists -Path $clsid
            Set-ItemProperty -Path $clsid -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Force
        }
        
        Remove-PSDrive -Name HKCR -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Failed to modify Explorer sidebar: $($_.Exception.Message)" -Level Warning
    }
    
    # Remove from default user profile
    Write-Log "Removing OneDrive from default user profile..."
    try {
        & reg.exe load 'HKU\Default' 'C:\Users\Default\NTUSER.DAT' 2>&1 | Out-Null
        & reg.exe delete 'HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' /v 'OneDriveSetup' /f 2>&1 | Out-Null
        & reg.exe unload 'HKU\Default' 2>&1 | Out-Null
    } catch {
        Write-Log "Failed to clean default user profile: $($_.Exception.Message)" -Level Warning
    }
    
    # Remove Start Menu shortcut
    $shortcut = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
    Remove-ItemSafely -Path $shortcut -Description 'OneDrive Start Menu shortcut'
    
    # Restart Explorer if stopped
    if ($explorerStopped) {
        Write-Log "Restarting Explorer..."
        Start-Process -FilePath 'explorer.exe'
        Start-Sleep -Seconds 5
    }
    
    # Remove WinSxS leftovers
    Write-Log "Removing OneDrive WinSxS components..."
    $winsxsItems = Get-ChildItem -Path "$env:WinDir\WinSxS" -Filter '*onedrive*' -ErrorAction SilentlyContinue
    foreach ($item in $winsxsItems) {
        Set-FolderOwnership -Path $item.FullName
        Remove-ItemSafely -Path $item.FullName -Description "WinSxS: $($item.Name)"
    }
    
    Write-Log "=== OneDrive Removal Completed ==="
}

function Remove-MicrosoftTeams {
    Write-Log "=== Starting Microsoft Teams Removal ==="
    
    # Stop Teams
    Stop-ProcessSafely -ProcessName 'Teams' -Description 'Microsoft Teams'
    
    # Clear Teams cache
    Write-Log "Clearing Teams cache..."
    $cachePaths = @(
        "$env:APPDATA\Microsoft\teams\application cache\cache",
        "$env:APPDATA\Microsoft\teams\blob_storage",
        "$env:APPDATA\Microsoft\teams\databases",
        "$env:APPDATA\Microsoft\teams\cache",
        "$env:APPDATA\Microsoft\teams\gpucache",
        "$env:APPDATA\Microsoft\teams\Indexeddb",
        "$env:APPDATA\Microsoft\teams\Local Storage",
        "$env:APPDATA\Microsoft\teams\tmp"
    )
    
    foreach ($path in $cachePaths) {
        if (Test-Path $path) {
            try {
                Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                Write-Log "Cleared cache: $path"
            } catch {
                Write-Log "Failed to clear cache $path" -Level Warning
            }
        }
    }
    
    # Stop browser processes
    Stop-ProcessSafely -ProcessName 'MicrosoftEdge' -Description 'Microsoft Edge'
    Stop-ProcessSafely -ProcessName 'IExplore' -Description 'Internet Explorer'
    
    # Clear browser cache
    Write-Log "Clearing browser cache..."
    try {
        & RunDll32.exe InetCpl.cpl, ClearMyTracksByProcess 8 2>&1 | Out-Null
        & RunDll32.exe InetCpl.cpl, ClearMyTracksByProcess 2 2>&1 | Out-Null
        Write-Log "Browser cache cleared"
    } catch {
        Write-Log "Failed to clear browser cache: $($_.Exception.Message)" -Level Warning
    }
    
    # Remove Machine-Wide Installer
    Write-Log "Removing Teams Machine-Wide Installer..."
    try {
        $machineWide = Get-CimInstance -ClassName Win32_Product -Filter "Name = 'Teams Machine-Wide Installer'"
        if ($machineWide) {
            $machineWide | Invoke-CimMethod -MethodName Uninstall | Out-Null
            Write-Log "Teams Machine-Wide Installer removed"
        }
    } catch {
        Write-Log "Failed to remove Machine-Wide Installer: $($_.Exception.Message)" -Level Warning
    }
    
    # Uninstall Teams client
    Write-Log "Uninstalling Teams client..."
    $installPaths = @(
        "$env:LOCALAPPDATA\Microsoft\Teams",
        "$env:ProgramData\$env:USERNAME\Microsoft\Teams"
    )
    
    $uninstalled = $false
    foreach ($path in $installPaths) {
        $installer = Join-Path $path 'Update.exe'
        if (Test-Path "$path\Current\Teams.exe") {
            Write-Log "Found Teams installation at: $path"
            try {
                if (Test-Path $installer) {
                    $process = Start-Process -FilePath $installer -ArgumentList '--uninstall', '/s' `
                        -PassThru -Wait -NoNewWindow -ErrorAction Stop
                    
                    if ($process.ExitCode -eq 0) {
                        Write-Log "Teams uninstalled from $path"
                        $uninstalled = $true
                        break
                    } else {
                        Write-Log "Teams uninstall returned exit code $($process.ExitCode)" -Level Warning
                    }
                }
            } catch {
                Write-Log "Failed to uninstall Teams: $($_.Exception.Message)" -Level Warning
            }
        }
    }
    
    if (-not $uninstalled) {
        Write-Log "Teams installation not found or already removed"
    }
    
    Write-Log "=== Microsoft Teams Removal Completed ==="
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

# Main execution
try {
    Initialize-Logging
    
    Write-Log "=== Starting OneDrive and Teams Removal ==="
    Write-Log "Script: Remove_OneDrive_And_Teams.ps1"
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"
    
    Remove-OneDrive
    Remove-MicrosoftTeams
    
    Write-Log "=== Removal Process Completed ==="
    Write-Log "A system restart is recommended to complete the removal"
    
} catch {
    Write-Log "Removal process failed: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    Stop-Logging
}
