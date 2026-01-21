# Testing Guide

This guide covers automated testing for PowerShell scripts, autounattend XML files, and Packer templates.

## Table of Contents

- [Quick Start](#quick-start)
- [Test Runner](#test-runner)
- [Pester Unit Tests](#pester-unit-tests)
- [CI/CD Integration](#cicd-integration)
- [Local Testing](#local-testing)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Run All Tests Locally

```powershell
# Syntax validation only (fast)
.\tests\Test-PowerShellScripts.ps1 -SkipExecution

# Full testing (slower, may require admin)
.\tests\Test-PowerShellScripts.ps1

# Run Pester unit tests
Invoke-Pester -Path .\tests
```

### Pre-Commit Testing

```bash
# Run pre-commit hooks (includes PowerShell validation)
pre-commit run --all-files
```

---

## Test Runner

The automated test runner (`tests/Test-PowerShellScripts.ps1`) validates all PowerShell scripts in the repository.

### Features

- **Syntax Validation** - Checks for PowerShell syntax errors
- **AST Parsing** - Deep validation using Abstract Syntax Tree
- **Execution Testing** - Safe dry-run execution where possible
- **Color-coded Output** - Visual feedback on test results
- **JSON Export** - Results exported for CI/CD integration

### Usage

```powershell
# Basic usage
.\tests\Test-PowerShellScripts.ps1

# Syntax check only
.\tests\Test-PowerShellScripts.ps1 -SkipExecution

# Test specific directory
.\tests\Test-PowerShellScripts.ps1 -Path scripts\windows_server

# Verbose output
.\tests\Test-PowerShellScripts.ps1 -VerboseOutput

# Exclude patterns
.\tests\Test-PowerShellScripts.ps1 -ExcludePatterns '*\build\*','*\temp\*'
```

### Test Categories

The test runner automatically categorizes scripts:

1. **Requires Mandatory Parameters** - Skipped (cannot auto-execute)
2. **Requires Administrator** - Skipped if not elevated
3. **Cloud-Specific** - Skipped (AWS/Azure/GCP metadata detection)
4. **Supports -WhatIf** - Executed with `-WhatIf` parameter
5. **Supports -Help** - Executed with `-Help` parameter
6. **Generic Scripts** - Dot-sourced for validation

### Output Example

```
========================================
PowerShell Script Test Runner
========================================

Found 45 PowerShell scripts

Testing: scripts/windows_server/Install_Azure_Tools.ps1
  ├─ Syntax check... ✓ PASS
  └─ Execution test... ⊘ SKIP (Cloud-specific script)

Testing: scripts/windows_server/Configure_WinRM.ps1
  ├─ Syntax check... ✓ PASS
  └─ Execution test... ✓ PASS

========================================
Test Summary
========================================

Total scripts: 45

Syntax Validation:
  ✓ Passed: 45
  ✗ Failed: 0

Execution Tests:
  ✓ Passed: 30
  ✗ Failed: 0
  ⊘ Skipped: 15

Duration: 12.34s
```

---

## Pester Unit Tests

Pester is PowerShell's testing framework. Tests are located in `tests/Scripts.Tests.ps1`.

### Installation

```powershell
# Install Pester (v5+)
Install-Module -Name Pester -Force -SkipPublisherCheck -MinimumVersion 5.0.0
```

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path .\tests

# Run with detailed output
Invoke-Pester -Path .\tests -Output Detailed

# Generate code coverage
$config = New-PesterConfiguration
$config.Run.Path = './tests'
$config.CodeCoverage.Enabled = $true
Invoke-Pester -Configuration $config
```

### Test Structure

```powershell
Describe "PowerShell Script Syntax Validation" {
    Context "All PowerShell scripts" {
        It "Should have valid PowerShell syntax" {
            # Test logic
        }
    }
}
```

### Test Categories

1. **Syntax Validation** - All `.ps1` files for syntax errors
2. **Script Standards** - SYNOPSIS, DESCRIPTION, EXAMPLE sections
3. **XOAP Logging** - C:\xoap-logs usage, error handling
4. **Cloud-Specific Tests** - AWS/Azure/GCP script validation
5. **Autounattend XML** - XML syntax, xoap-admin user, WinRM config

---

## CI/CD Integration

GitHub Actions automatically runs tests on every push and pull request.

### Workflow: `.github/workflows/test-powershell.yml`

**Jobs:**

1. **syntax-validation** - PowerShell syntax checks
2. **pester-tests** - Pester unit tests with XML output
3. **script-execution-tests** - Test runner execution
4. **cross-platform-validation** - Tests on Ubuntu, macOS, Windows
5. **autounattend-validation** - XML file validation
6. **security-scan** - Scan for hardcoded secrets
7. **test-summary** - Aggregate results

### Viewing Results

1. Go to **Actions** tab in GitHub
2. Select a workflow run
3. View job outputs and artifacts
4. Download `test-results.xml` or `test-results.json`

### Test Artifacts

- `pester-test-results/test-results.xml` - Pester test output
- `execution-test-results/test-results.json` - Test runner JSON

---

## Local Testing

### Prerequisites

```powershell
# Windows PowerShell 5.1+ or PowerShell 7+
$PSVersionTable.PSVersion

# Install Pester
Install-Module -Name Pester -Force -SkipPublisherCheck

# Install pre-commit (optional)
pip install pre-commit
pre-commit install
```

### Test Workflow

```powershell
# 1. Make changes to scripts
# Edit files...

# 2. Run quick syntax check
.\tests\Test-PowerShellScripts.ps1 -SkipExecution

# 3. Run Pester tests
Invoke-Pester -Path .\tests

# 4. (Optional) Full execution tests
.\tests\Test-PowerShellScripts.ps1

# 5. Commit changes
git add .
git commit -m "feat(scripts): add new installation script"
# Pre-commit hooks will run automatically
```

### IDE Integration

#### Visual Studio Code

1. Install **Pester Test Adapter** extension
2. Tests appear in **Test Explorer**
3. Run/debug individual tests from UI

#### PowerShell ISE

```powershell
# Open test file
ise .\tests\Scripts.Tests.ps1

# Run in ISE
Invoke-Pester -Path .\tests -Output Detailed
```

---

## Troubleshooting

### Common Issues

#### Syntax Errors

**Problem:** Script fails syntax validation

**Solution:**
```powershell
# Check specific script
$errors = $null
$content = Get-Content .\path\to\script.ps1 -Raw
$null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
$errors  # View specific errors
```

#### Execution Failures

**Problem:** Script fails execution test

**Reasons:**
- Requires mandatory parameters → Add default or optional parameters
- Requires administrator → Run test runner as admin
- Cloud-specific → Expected behavior, will skip automatically
- External dependencies → Mock or skip in tests

**Solution:**
```powershell
# Add parameter defaults
param(
    [string]$Path = "C:\default\path"  # Add default
)

# Or make optional
param(
    [Parameter(Mandatory=$false)]
    [string]$Path
)
```

#### Pester Test Failures

**Problem:** Pester tests fail unexpectedly

**Debug:**
```powershell
# Run specific test
Invoke-Pester -Path .\tests\Scripts.Tests.ps1 -FullNameFilter "*Should have valid syntax*"

# Enable debug output
Invoke-Pester -Path .\tests -Output Diagnostic
```

#### Cross-Platform Issues

**Problem:** Tests pass on Windows but fail on Linux/macOS

**Common Causes:**
- Path separators (`\` vs `/`)
- Case-sensitive file systems
- Windows-specific cmdlets

**Solution:**
```powershell
# Use cross-platform paths
$path = Join-Path $PSScriptRoot "subfolder" "file.txt"

# Check OS
if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    # Windows-specific code
} else {
    # Linux/macOS code
}
```

### Test Skipping

#### Skip Tests for Cloud Scripts

Cloud-specific scripts are automatically skipped in local testing:

```powershell
# Detected patterns:
- 169.254.169.254 (AWS/Azure IMDS)
- metadata.google.internal (GCP)
- EC2Launch|AzureMonitorAgent|GCEAgent (cloud agents)
```

#### Manually Skip Tests

```powershell
# In test runner
if ($scriptContent -match 'SpecialCondition') {
    return @{
        Success = $null
        Message = "Skipped: Requires special environment"
    }
}

# In Pester
It "Should test something" -Skip:($env:CI -eq 'true') {
    # Test logic
}
```

### Performance Optimization

#### Speed Up Tests

```powershell
# Syntax check only (fastest)
.\tests\Test-PowerShellScripts.ps1 -SkipExecution

# Test specific directory
.\tests\Test-PowerShellScripts.ps1 -Path scripts\windows_server

# Run Pester in parallel (Pester v5+)
$config = New-PesterConfiguration
$config.Run.Path = './tests'
$config.Run.Parallel = $true
Invoke-Pester -Configuration $config
```

---

## Writing Testable Scripts

### Best Practices

```powershell
<#
.SYNOPSIS
    Brief description
    
.DESCRIPTION
    Detailed description
    
.EXAMPLE
    .\Script.ps1
    Basic usage
    
.EXAMPLE
    .\Script.ps1 -Param Value
    Advanced usage
#>

[CmdletBinding()]  # Support common parameters
param(
    # Use optional parameters with defaults
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\xoap-logs",
    
    # Support -WhatIf for testing
    [switch]$WhatIf
)

# Error handling
try {
    # Script logic
    
    if ($WhatIf) {
        Write-Host "Would perform action"
        return
    }
    
    # Actual work
    
} catch {
    Write-Error "Failed: $_"
    exit 1
}
```

### Mock External Dependencies

```powershell
# In Pester tests
Mock Get-Service { 
    return @{ Status = 'Running'; Name = 'TestService' }
}

Mock Invoke-WebRequest {
    return @{ StatusCode = 200; Content = '{}' }
}
```

---

## Test Coverage Goals

| Category | Target | Current |
|----------|--------|---------|
| Syntax Validation | 100% | 100% |
| Documentation | 100% | ~95% |
| Execution Tests | 80%+ | ~67% |
| Unit Tests | 70%+ | ~50% |

---

## Additional Resources

- [Pester Documentation](https://pester.dev)
- [PowerShell Best Practices](https://github.com/PoshCode/PowerShellPracticeAndStyle)
- [GitHub Actions for PowerShell](https://docs.github.com/en/actions)
- [Pre-commit Hooks](https://pre-commit.com)

---

**Questions?** Open an issue or check [CONTRIBUTING.md](../CONTRIBUTING.md)
