# PowerShell Script Tests with Pester (Pester 5.x)
#
# NOTE: Collections consumed by -TestCases and -Skip must be built during the
# DISCOVERY phase, so they live in BeforeDiscovery / top-level scope rather than
# BeforeAll (which only runs in the Run phase). Populating them in BeforeAll was
# the historical bug that caused every data-driven test to silently collapse to a
# single case or skip entirely.

BeforeDiscovery {
    # Pester 5 binds <Name> / $FullName only from hashtable test cases, so every
    # collection consumed by -TestCases is projected to @{ FullName; Name } here.
    function ConvertTo-TestCases {
        param([System.IO.FileInfo[]]$Items)
        @($Items | ForEach-Object { @{ FullName = $_.FullName; Name = $_.Name } })
    }

    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $WindowsServerScripts = Join-Path $ProjectRoot 'scripts' 'windows_server'

    $allScriptFiles = @(Get-ChildItem -Path $ProjectRoot -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notlike '*node_modules*' -and
            $_.FullName -notlike '*.git*' -and
            $_.FullName -notlike '*build*' -and
            $_.FullName -notlike '*tests*'
        })

    $serverFiles   = @(Get-ChildItem -Path $WindowsServerScripts -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue)
    $serverInstallFiles = @(Get-ChildItem -Path $WindowsServerScripts -Filter *Install*.ps1 -Recurse -ErrorAction SilentlyContinue)
    $awsFiles      = @(Get-ChildItem -Path (Join-Path $WindowsServerScripts 'aws')    -Filter *.ps1 -ErrorAction SilentlyContinue)
    $azureFiles    = @(Get-ChildItem -Path (Join-Path $WindowsServerScripts 'azure')  -Filter *.ps1 -ErrorAction SilentlyContinue)
    $gcpFiles      = @(Get-ChildItem -Path (Join-Path $WindowsServerScripts 'google') -Filter *.ps1 -ErrorAction SilentlyContinue)
    $xmlFileList   = @(Get-ChildItem -Path (Join-Path $ProjectRoot 'autounattend') -Filter *.xml -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Autounattend-*.xml' })

    $cloudFilter = { $_.Name -like '*Install*' -or $_.Name -like '*Optimize*' }

    $allScripts   = ConvertTo-TestCases $allScriptFiles
    $serverScripts = ConvertTo-TestCases $serverFiles
    $serverInstall = ConvertTo-TestCases $serverInstallFiles
    $awsScripts   = ConvertTo-TestCases $awsFiles
    $azureScripts = ConvertTo-TestCases $azureFiles
    $gcpScripts   = ConvertTo-TestCases $gcpFiles
    $awsCloud     = ConvertTo-TestCases (@($awsFiles)   | Where-Object $cloudFilter)
    $azureCloud   = ConvertTo-TestCases (@($azureFiles) | Where-Object $cloudFilter)
    $gcpCloud     = ConvertTo-TestCases (@($gcpFiles)   | Where-Object $cloudFilter)
    $xmlFiles     = ConvertTo-TestCases $xmlFileList
}

BeforeAll {
    # Setup logging
    try {
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            $LogDir = 'C:\xoap-logs'
        } else {
            $LogDir = Join-Path $HOME 'xoap-logs'
        }
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:LogFile = Join-Path $LogDir "Scripts.Tests-$timestamp.log"
        Start-Transcript -Path $script:LogFile -Append | Out-Null
        Write-Host "Logging to: $($script:LogFile)"
    } catch {
        Write-Warning "Failed to start transcript logging: $($_.Exception.Message)"
    }
}

Describe "PowerShell Script Syntax Validation" {

    It "Should find PowerShell scripts in repository" {
        @($allScripts).Count | Should -BeGreaterThan 0 -Because "Repository should contain PowerShell scripts"
    }

    It "Should have valid PowerShell syntax: <Name>" -TestCases $allScripts {
        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $FullName -Raw), [ref]$errors)
        $errors.Count | Should -Be 0 -Because "Script should have no syntax errors"
    }

    It "Should parse correctly with AST: <Name>" -TestCases $allScripts {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0 -Because "Script AST should parse without errors"
        $ast | Should -Not -BeNullOrEmpty
    }
}

Describe "PowerShell Script Standards" {

    It "Should find Windows Server scripts to validate" {
        @($serverScripts).Count | Should -BeGreaterThan 0 -Because "windows_server should contain provisioning scripts"
    }

    It "Should have a SYNOPSIS section: <Name>" -TestCases $serverScripts {
        (Get-Content $FullName -Raw) | Should -Match '\.SYNOPSIS' -Because "All scripts should document their purpose"
    }

    It "Should have a DESCRIPTION section: <Name>" -TestCases $serverScripts {
        (Get-Content $FullName -Raw) | Should -Match '\.DESCRIPTION' -Because "All scripts should have detailed description"
    }

    It "Should have error handling: <Name>" -TestCases $serverScripts {
        $content = Get-Content $FullName -Raw
        ($content -match 'try\s*\{' -or $content -match 'trap\s*\{') |
            Should -BeTrue -Because "Scripts should have error handling"
    }

    It "Should use CmdletBinding: <Name>" -TestCases $serverInstall {
        (Get-Content $FullName -Raw) | Should -Match '\[CmdletBinding\(\)\]' -Because "Install scripts should support common parameters"
    }
}

Describe "Cloud-Specific Script Tests" {

    It "Should find AWS platform scripts" {
        @($awsScripts).Count | Should -BeGreaterThan 0 -Because "scripts/windows_server/aws should contain AWS scripts"
    }

    It "AWS Install/Optimize script references EC2 IMDS: <Name>" -TestCases $awsCloud {
        (Get-Content $FullName -Raw) | Should -Match '169\.254\.169\.254' -Because "AWS scripts should use the EC2 instance metadata service"
    }

    It "Should find Azure platform scripts" {
        @($azureScripts).Count | Should -BeGreaterThan 0 -Because "scripts/windows_server/azure should contain Azure scripts"
    }

    It "Azure Install/Optimize script references Azure metadata: <Name>" -TestCases $azureCloud {
        (Get-Content $FullName -Raw) | Should -Match '169\.254\.169\.254|WindowsAzure' -Because "Azure scripts should use Azure-specific APIs"
    }

    It "Should find Google Cloud platform scripts" {
        @($gcpScripts).Count | Should -BeGreaterThan 0 -Because "scripts/windows_server/google should contain GCP scripts"
    }

    It "GCP Install/Optimize script references metadata server: <Name>" -TestCases $gcpCloud {
        (Get-Content $FullName -Raw) | Should -Match 'metadata\.google\.internal' -Because "GCP scripts should use the metadata server"
    }
}

Describe "Autounattend XML Files" {

    It "Should find autounattend XML files" {
        @($xmlFiles).Count | Should -BeGreaterThan 0 -Because "autounattend should contain Autounattend-*.xml files"
    }

    It "Should be valid XML: <Name>" -TestCases $xmlFiles {
        { [xml](Get-Content $FullName -Raw) } | Should -Not -Throw -Because "File should be valid XML"
    }

    It "Should have xoap-admin user: <Name>" -TestCases $xmlFiles {
        (Get-Content $FullName -Raw) | Should -Match 'xoap-admin' -Because "Autounattend files should use the XOAP standard user"
    }

    It "Should configure WinRM: <Name>" -TestCases $xmlFiles {
        (Get-Content $FullName -Raw) | Should -Match 'winrm' -Because "Autounattend files should configure WinRM"
    }
}

AfterAll {
    try {
        Stop-Transcript | Out-Null
        if ($script:LogFile) {
            Write-Host "Test log saved to: $($script:LogFile)"
        }
    } catch {}
}
