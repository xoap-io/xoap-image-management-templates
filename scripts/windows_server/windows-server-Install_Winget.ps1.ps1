<#
.SYNOPSIS
    Install Windows Package Manager (winget)

.DESCRIPTION
    Installs the Windows Package Manager (winget) on Windows Server and client operating systems.
    Downloads and installs required dependencies including VCLibs and UI.Xaml frameworks.
    Compatible with Windows Server 2019+, Windows 10, and Windows 11.

.NOTES
    File Name      : windows-server-install_winget.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-install_winget.ps1
    Installs winget with all required dependencies

.LINK
    https://github.com/microsoft/winget-cli
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$TempPath = "$env:TEMP\WingetInstall"
$VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
$UIXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
$WingetUrl = "https://aka.ms/getwinget"

# Logging function
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
    Write-Host "[$timestamp] [$prefix] [Winget] $Message"
}

# Function to download file
function Get-FileDownload {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        Write-Log "Downloading from: $Url"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutputPath)
        
        if (Test-Path $OutputPath) {
            Write-Log "Downloaded successfully to: $OutputPath"
            return $true
        } else {
            throw "File not found after download"
        }
    } catch {
        Write-Log "Failed to download from $Url : $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Function to install Appx package
function Install-AppxPackageWithRetry {
    param(
        [string]$PackagePath,
        [string]$PackageName
    )
    
    try {
        Write-Log "Installing $PackageName..."
        Add-AppxPackage -Path $PackagePath -ErrorAction Stop
        Write-Log "$PackageName installed successfully"
        return $true
    } catch {
        Write-Log "Failed to install $PackageName : $($_.Exception.Message)" -Level Warning
        return $false
    }
}

# Main script execution
try {
    Write-Log "Starting Windows Package Manager (winget) installation..."
    
    # Check if running on supported OS
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $osVersion = [System.Version]$osInfo.Version
    $osBuildNumber = $osInfo.BuildNumber
    
    Write-Log "Operating System: $($osInfo.Caption)"
    Write-Log "Version: $($osInfo.Version)"
    Write-Log "Build: $osBuildNumber"
    
    # Check if winget is already installed
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) {
        Write-Log "Winget is already installed at: $($wingetPath.Source)"
        $wingetVersion = & winget --version 2>&1
        Write-Log "Current version: $wingetVersion"
        exit 0
    }
    
    # Create temporary directory
    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        Write-Log "Created temporary directory: $TempPath"
    }
    
    # Define file paths
    $VCLibsPath = Join-Path $TempPath "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $UIXamlPath = Join-Path $TempPath "Microsoft.UI.Xaml.2.8.x64.appx"
    $WingetPath = Join-Path $TempPath "Microsoft.DesktopAppInstaller.msixbundle"
    
    # Download VCLibs dependency
    Write-Log "Downloading VCLibs dependency..."
    if (-not (Get-FileDownload -Url $VCLibsUrl -OutputPath $VCLibsPath)) {
        throw "Failed to download VCLibs dependency"
    }
    
    # Download UI.Xaml dependency
    Write-Log "Downloading UI.Xaml dependency..."
    if (-not (Get-FileDownload -Url $UIXamlUrl -OutputPath $UIXamlPath)) {
        throw "Failed to download UI.Xaml dependency"
    }
    
    # Download winget
    Write-Log "Downloading Windows Package Manager..."
    if (-not (Get-FileDownload -Url $WingetUrl -OutputPath $WingetPath)) {
        throw "Failed to download Windows Package Manager"
    }
    
    # Install dependencies
    Write-Log "Installing dependencies..."
    
    # Install VCLibs
    $vcLibsInstalled = Install-AppxPackageWithRetry -PackagePath $VCLibsPath -PackageName "VCLibs"
    
    # Install UI.Xaml
    $uiXamlInstalled = Install-AppxPackageWithRetry -PackagePath $UIXamlPath -PackageName "UI.Xaml"
    
    # Install winget
    Write-Log "Installing Windows Package Manager..."
    try {
        Add-AppxPackage -Path $WingetPath -ErrorAction Stop
        Write-Log "Windows Package Manager installed successfully"
    } catch {
        Write-Log "Attempting to install with dependencies explicitly..." -Level Warning
        Add-AppxPackage -Path $WingetPath -DependencyPath $VCLibsPath,$UIXamlPath -ErrorAction Stop
        Write-Log "Windows Package Manager installed with explicit dependencies"
    }
    
    # Verify installation
    Start-Sleep -Seconds 3
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    
    if ($wingetCmd) {
        $wingetVersion = & winget --version 2>&1
        Write-Log "Winget installed successfully!"
        Write-Log "Version: $wingetVersion"
        Write-Log "Location: $($wingetCmd.Source)"
    } else {
        throw "Winget command not found after installation"
    }
    
    # Cleanup
    Write-Log "Cleaning up temporary files..."
    Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Log "Windows Package Manager installation completed successfully"
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    
    # Cleanup on error
    if (Test-Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}
