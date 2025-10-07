###############################################################################################################
# Language     :  PowerShell 5.1+
# Filename     :  OptimizePowerShellStartup.ps1
# Author       :  BornToBeRoot (https://github.com/BornToBeRoot) + XOAP optimizations
# Description  :  Optimize PowerShell startup by reducing JIT compile time with ngen.exe
# Repository   :  https://github.com/BornToBeRoot/PowerShell
###############################################################################################################

<#
    .SYNOPSIS
    Optimize PowerShell startup by reducing JIT compile time with "ngen.exe"
    .DESCRIPTION
    Script requires administrative permissions.
    .EXAMPLE
    OptimizePowerShellStartup.ps1
    .LINK
    https://github.com/BornToBeRoot/PowerShell/blob/master/Documentation/Script/OptimizePowerShellStartup.README.md
#>

function Log {
    param([string]$msg)
    Write-Host "[PSOPTIMIZE] $msg"
}

$ErrorActionPreference = 'Stop'

Begin {
    Log "Starting PowerShell startup optimization..."
}

Process {
    # Restart script/console as admin with parameters
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        $Arguments = "& '" + $MyInvocation.MyCommand.Definition + "'"
        Log "Restarting as administrator..."
        Start-Process PowerShell.exe -Verb RunAs -ArgumentList $Arguments
        Break
    }

    Log "Locating ngen.exe..."
    $ngen_path = Join-Path -Path $env:windir -ChildPath "Microsoft.NET"
    if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
        $ngen_path = Join-Path -Path $ngen_path -ChildPath "Framework64"
    } else {
        $ngen_path = Join-Path -Path $ngen_path -ChildPath "Framework"
    }
    $ngen_application_path = (Get-ChildItem -Path $ngen_path -Filter "ngen.exe" -Recurse | Where-Object { $_.Length -gt 0 } | Select-Object -Last 1).FullName
    if (-not $ngen_application_path) {
        Log "ngen.exe not found. Exiting."
        exit 1
    }
    Set-Alias -Name ngen -Value $ngen_application_path

    Log "Optimizing loaded assemblies with ngen.exe..."
    try {
        [System.AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
            ngen install $_.Location /nologo /verbose
        }
        Log "Optimization finished!"
    } catch {
        Log "Error during ngen optimization: $($_.Exception.Message)"
        exit 1
    }
}

End {
    Log "PowerShell startup optimization script complete."
}
