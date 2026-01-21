# PowerShell Script Tests with Pester

BeforeAll {
    # Setup logging
    try {
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            $LogDir = 'C:\xoap-logs'
        } else {
            $LogDir = Join-Path $HOME 'xoap-logs'
        }
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        $scriptName = 'Scripts.Tests'
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"
        Start-Transcript -Path $script:LogFile -Append | Out-Null
        Write-Host "Logging to: $($script:LogFile)"
    } catch { 
        Write-Warning "Failed to start transcript logging: $($_.Exception.Message)" 
    }
    
    # Import module or script under test
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $ScriptsPath = Join-Path $ProjectRoot "scripts"
    $WindowsServerScripts = Join-Path $ProjectRoot "scripts" "windows_server"
    $WindowsServerScriptsWip = Join-Path $ProjectRoot "scripts_wip" "windows_server_2025_scripts"
    
    Write-Host "Project Root: $ProjectRoot"
    Write-Host "Scripts Path: $ScriptsPath"
    Write-Host "Windows Server Scripts WIP: $WindowsServerScriptsWip"
}

Describe "PowerShell Script Syntax Validation" {
    
    Context "All PowerShell scripts" {
        
        BeforeAll {
            Write-Host "Searching for PowerShell scripts in: $ProjectRoot"
            $allScripts = @(Get-ChildItem -Path $ProjectRoot -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { 
                    $_.FullName -notlike "*node_modules*" -and 
                    $_.FullName -notlike "*.git*" -and
                    $_.FullName -notlike "*build*" -and
                    $_.FullName -notlike "*tests*"
                })
            
            Write-Host "Found $($allScripts.Count) PowerShell scripts to test"
            if ($allScripts.Count -gt 0) {
                Write-Host "Sample scripts: $($allScripts[0..2].Name -join ', ')"
            }
        }
        
        It "Should find PowerShell scripts in repository" {
            $allScripts.Count | Should -BeGreaterThan 0 -Because "Repository should contain PowerShell scripts"
        }
        
        It "Should have valid PowerShell syntax: <Name>" -TestCases $allScripts {
            param($FullName, $Name)
            
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $FullName -Raw), 
                [ref]$errors
            )
            
            $errors.Count | Should -Be 0 -Because "Script should have no syntax errors"
        }
        
        It "Should parse correctly with AST: <Name>" -TestCases $allScripts {
            param($FullName, $Name)
            
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $FullName, 
                [ref]$null, 
                [ref]$errors
            )
            
            $errors.Count | Should -Be 0 -Because "Script AST should parse without errors"
            $ast | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "PowerShell Script Standards" {
    
    Context "Script documentation" {
        
        BeforeAll {
            $scriptFiles = @(Get-ChildItem -Path $WindowsServerScriptsWip -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue)
            Write-Host "Found $($scriptFiles.Count) scripts in windows_server_2025_scripts for documentation tests"
        }
        
        It "Should have a SYNOPSIS section: <Name>" -TestCases $scriptFiles -Skip:($scriptFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match '\.SYNOPSIS' -Because "All scripts should document their purpose"
        }
        
        It "Should have a DESCRIPTION section: <Name>" -TestCases $scriptFiles -Skip:($scriptFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match '\.DESCRIPTION' -Because "All scripts should have detailed description"
        }
        
        It "Should have EXAMPLE section: <Name>" -TestCases $scriptFiles -Skip:($scriptFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match '\.EXAMPLE' -Because "All scripts should provide usage examples"
        }
    }
    
    Context "XOAP logging framework" {
        
        BeforeAll {
            $scriptFiles = @(Get-ChildItem -Path $WindowsServerScriptsWip -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue)
        }
        
        It "Should use XOAP logging path: <Name>" -TestCases $scriptFiles -Skip:($scriptFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match 'C:\\xoap-logs' -Because "Scripts should use standard XOAP logging path"
        }
        
        It "Should have error handling: <Name>" -TestCases $scriptFiles -Skip:($scriptFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            ($content -match 'try\s*\{' -or $content -match 'trap\s*\{') | 
                Should -BeTrue -Because "Scripts should have error handling"
        }
    }
    
    Context "Script parameters" {
        
        BeforeAll {
            $cloudScripts = @(Get-ChildItem -Path $WindowsServerScriptsWip -Filter *Install*.ps1 -Recurse -ErrorAction SilentlyContinue)
        }
        
        It "Should use CmdletBinding: <Name>" -TestCases $cloudScripts -Skip:($cloudScripts.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match '\[CmdletBinding\(\)\]' -Because "Scripts should support common parameters"
        }
    }
}

Describe "Cloud-Specific Script Tests" {
    
    Context "AWS Scripts" {
        
        BeforeAll {
            $awsScriptsPath = Join-Path $WindowsServerScriptsWip "aws"
            $script:hasAwsScripts = Test-Path $awsScriptsPath
            if ($script:hasAwsScripts) {
                $awsScripts = Get-ChildItem -Path $awsScriptsPath -Filter *.ps1
            }
        }
        
        It "AWS scripts should reference EC2 metadata service" -Skip:(-not $script:hasAwsScripts) {
            $awsScripts | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                if ($_.Name -like "*Install*" -or $_.Name -like "*Optimize*") {
                    $content | Should -Match '169\.254\.169\.254' -Because "AWS scripts should use IMDS"
                }
            }
        }
    }
    
    Context "Azure Scripts" {
        
        BeforeAll {
            $azureScriptsPath = Join-Path $WindowsServerScriptsWip "azure"
            $script:hasAzureScripts = Test-Path $azureScriptsPath
            if ($script:hasAzureScripts) {
                $azureScripts = Get-ChildItem -Path $azureScriptsPath -Filter *.ps1
            }
        }
        
        It "Azure scripts should reference metadata service" -Skip:(-not $script:hasAzureScripts) {
            $azureScripts | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                if ($_.Name -like "*Install*" -or $_.Name -like "*Optimize*") {
                    $content | Should -Match '169\.254\.169\.254|WindowsAzure' -Because "Azure scripts should use Azure-specific APIs"
                }
            }
        }
    }
    
    Context "Google Cloud Scripts" {
        
        BeforeAll {
            $gcpScriptsPath = Join-Path $WindowsServerScriptsWip "google"
            $script:hasGcpScripts = Test-Path $gcpScriptsPath
            if ($script:hasGcpScripts) {
                $gcpScripts = Get-ChildItem -Path $gcpScriptsPath -Filter *.ps1
            }
        }
        
        It "GCP scripts should reference metadata server" -Skip:(-not $script:hasGcpScripts) {
            $gcpScripts | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                if ($_.Name -like "*Install*" -or $_.Name -like "*Optimize*") {
                    $content | Should -Match 'metadata\.google\.internal' -Because "GCP scripts should use metadata server"
                }
            }
        }
    }
}

AfterAll {
    # Stop transcript
    try { 
        Stop-Transcript | Out-Null 
        if ($script:LogFile) {
            Write-Host "Test log saved to: $($script:LogFile)"
        }
    } catch {}
}

Describe "Autounattend XML Files" {
    
    Context "XML syntax validation" {
        
        BeforeAll {
            $autounattendPath = Join-Path $ProjectRoot "autounattend"
            $xmlFiles = @(Get-ChildItem -Path $autounattendPath -Filter *.xml -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -like "Autounattend-*.xml" })
            
            Write-Host "Found $($xmlFiles.Count) autounattend XML files to test"
        }
        
        It "Should be valid XML: <Name>" -TestCases $xmlFiles -Skip:($xmlFiles.Count -eq 0) {
            param($FullName, $Name)
            
            { [xml](Get-Content $FullName -Raw) } | Should -Not -Throw -Because "File should be valid XML"
        }
        
        It "Should have xoap-admin user: <Name>" -TestCases $xmlFiles -Skip:($xmlFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match 'xoap-admin' -Because "Autounattend files should use XOAP standard user"
        }
        
        It "Should configure WinRM: <Name>" -TestCases $xmlFiles -Skip:($xmlFiles.Count -eq 0) {
            param($FullName, $Name)
            
            $content = Get-Content $FullName -Raw
            $content | Should -Match 'winrm' -Because "Autounattend files should configure WinRM"
        }
    }
}

AfterAll {
    # Stop transcript
    try { 
        Stop-Transcript | Out-Null 
        if ($script:LogFile) {
            Write-Host "Test log saved to: $($script:LogFile)"
        }
    } catch {}
}
