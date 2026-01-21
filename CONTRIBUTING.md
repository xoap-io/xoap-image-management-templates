# Contributing to XOAP Packer Templates

First off, thank you for considering contributing to XOAP Packer Templates! It's people like you that make this project such a great tool for the community.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Pull Requests](#pull-requests)
- [Development Guidelines](#development-guidelines)
  - [Packer Configuration Standards](#packer-configuration-standards)
  - [Autounattend File Standards](#autounattend-file-standards)
  - [PowerShell Script Standards](#powershell-script-standards)
- [Git Workflow](#git-workflow)
- [Testing](#testing)
- [Documentation](#documentation)

---

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

---

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When creating a bug report, include as many details as possible:

**Bug Report Template:**

```markdown
**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Run Packer with '...'
2. Using autounattend file '...'
3. See error

**Expected behavior**
What you expected to happen.

**Environment:**
- OS: [e.g., macOS Ventura 13.3.1]
- Packer version: [e.g., 1.8.0]
- Hypervisor: [e.g., VMware Fusion Pro 12.3.3]
- Windows version: [e.g., Windows Server 2022 Datacenter]

**Additional context**
Add any other context about the problem here.
```

### Suggesting Enhancements

Enhancement suggestions are welcome! Please provide:

- **Use case:** Describe the problem you're trying to solve
- **Proposed solution:** How you envision the enhancement working
- **Alternatives:** Any alternative solutions you've considered
- **Additional context:** Screenshots, diagrams, or examples

### Pull Requests

We follow the "fork-and-pull" Git workflow:

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create a branch** for your changes
4. **Make your changes** following our standards
5. **Test** your changes thoroughly
6. **Commit** with conventional commit messages
7. **Push** to your fork
8. **Create a Pull Request** with a clear description

---

## Development Guidelines

### Packer Configuration Standards

#### File Organization

```PowerShell
{builder-type}/
└── windows/
    └── w{version}-{build}/
        └── w{version}-{edition}-{arch}-{locale}/
            ├── {builder}-{name}.pkr.hcl        # Configuration
            └── {builder}-{name}.pkrvars.hcl    # Variables
```

#### Naming Conventions

- **Windows versions:** `w2022-2108`, `w2k19-1809`, `w2k16-1607`
- **Editions:** `std` (Standard), `dc` (Datacenter), `core` (Server Core)
- **UI:** `dx` (Desktop Experience), `core` (Server Core)
- **Architecture:** Always `amd64`
- **Locale:** `en` for English

#### Required Variables

All Packer templates must include:

```hcl
variable "communicator" {
  type    = string
  default = "winrm"
}

variable "winrm_username" {
  type    = string
  default = "xoap-admin"
}

variable "winrm_timeout" {
  type    = string
  default = "2h"
}
```

#### Build Block Structure

```hcl
build {
  sources = ["source.{builder-type}.{builder-name}"]
  
  provisioner "powershell" { /* Initial setup */ }
  provisioner "windows-restart" { /* First reboot */ }
  provisioner "windows-update" { /* Updates */ }
  provisioner "windows-restart" { /* Post-update reboot */ }
  provisioner "powershell" { /* Cleanup */ }
  
  post-processor "vagrant" { /* Optional */ }
  post-processor "checksum" { /* SHA1 */ }
  post-processor "manifest" { /* Metadata */ }
}
```

### Autounattend File Standards

#### Directory Structure

Place files in hypervisor-specific folders:

```
autounattend/
├── {version}/              # e.g., 2022, 2025, W11
│   ├── vsphere/           # VMware vSphere
│   ├── nutanix/           # Nutanix AHV
│   ├── xenserver/         # Citrix XenServer
│   ├── hyperv/            # Hyper-V Gen1
│   └── hyperv-gen2/       # Hyper-V Gen2
```

#### File Naming
Format: `Autounattend-{Edition}.xml`

Examples:
- `Autounattend-StandardCore.xml`
- `Autounattend-Datacenter.xml`
- `Autounattend-AzureStackHCI.xml`
- `Autounattend-Enterprise.xml`

#### XOAP Standards

All autounattend files must include:

1. **User Configuration:**

   ```xml
   <LocalAccount wcm:action="add">
       <Name>xoap-admin</Name>
       <Password><Value>xoap-admin</Value></Password>
       <Group>administrators</Group>
   </LocalAccount>
   ```

2. **WinRM Configuration:**
   - Port 5985 (HTTP)
   - Basic authentication enabled
   - MaxTimeout: 1800000ms
   - AllowUnencrypted: true (for initial provisioning)

3. **System Settings:**
   - Locale: en-US
   - Timezone: UTC
   - UAC: Disabled
   - Server Manager: Disabled at logon
   - System Restore: Disabled

#### Partition Layouts

**BIOS/Legacy (Gen1):**

```xml
<CreatePartition wcm:action="add">
    <Type>Primary</Type>
    <Order>1</Order>
    <Size>100</Size>
</CreatePartition>
<CreatePartition wcm:action="add">
    <Order>2</Order>
    <Type>Primary</Type>
    <Extend>true</Extend>
</CreatePartition>
```

**UEFI (Gen2):**

```xml
<CreatePartition wcm:action="add">
    <Order>1</Order>
    <Size>350</Size>
    <Type>Primary</Type>
</CreatePartition>
<CreatePartition wcm:action="add">
    <Order>2</Order>
    <Size>100</Size>
    <Type>EFI</Type>
</CreatePartition>
<CreatePartition wcm:action="add">
    <Order>3</Order>
    <Size>128</Size>
    <Type>MSR</Type>
</CreatePartition>
<CreatePartition wcm:action="add">
    <Order>4</Order>
    <Extend>true</Extend>
    <Type>Primary</Type>
</CreatePartition>
```

### PowerShell Script Standards

#### File Organization

```PowerShell
scripts_wip/windows_server_2025_scripts/
├── aws/                   # AWS-specific scripts
├── azure/                 # Azure-specific scripts
├── google/                # Google Cloud scripts
├── vmware/                # VMware scripts
├── hyperv/                # Hyper-V scripts
├── proxmox/               # Proxmox scripts
├── nutanix/               # Nutanix scripts
└── xenserver/             # XenServer scripts
```

#### Script Template

```powershell
<#
.SYNOPSIS
    Brief description of what the script does

.DESCRIPTION
    Detailed description of functionality

.PARAMETER ParameterName
    Description of parameter

.EXAMPLE
    Example usage

.NOTES
    Author: XOAP
    Date: YYYY-MM-DD
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\xoap-logs"
)

# Initialize logging
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $LogPath "ScriptName_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

# Main script logic
try {
    Write-Log "Starting script execution"
    
    # Your code here
    
    Write-Log "Script completed successfully"
    exit 0
}
catch {
    Write-Log "Error: $_" -Level "ERROR"
    exit 1
}
```

#### XOAP Logging Framework

All scripts must use the XOAP logging framework:

```powershell
$logPath = "C:\xoap-logs"
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
```

---

## Git Workflow

### Branch Naming

- `feature/description` - New features
- `bugfix/description` - Bug fixes
- `hotfix/description` - Critical fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):

```PowerShell
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting)
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Maintenance tasks

**Examples:**

```markdown
feat(autounattend): add Azure Stack HCI support for Server 2025
fix(vmware): correct PVSCSI driver installation path
docs(readme): update hypervisor support matrix
```

### Pull Request Guidelines

**Title:** Follow conventional commit format

**Description Template:**

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] Tested on target platform
- [ ] Pre-commit hooks pass
- [ ] No merge conflicts

## Testing
Describe testing performed:
- Platform: [e.g., VMware Fusion Pro 12.3.3]
- OS: [e.g., Windows Server 2022 Datacenter]
- Results: [Pass/Fail with details]

## Screenshots (if applicable)

## Additional Notes
```

---

## Testing

### Pre-Commit Validation

Run pre-commit hooks before submitting:

```bash
pre-commit run --all-files
```

### Packer Validation
Validate all Packer configurations:

```bash
packer validate -var-file="config.pkrvars.hcl" template.pkr.hcl
```

### Autounattend Testing

Test autounattend files with:

1. Create a new VM with the autounattend file
2. Verify unattended installation completes
3. Check WinRM connectivity on port 5985
4. Verify xoap-admin user exists with correct permissions
5. Confirm all FirstLogonCommands executed successfully

### PowerShell Script Testing

Test scripts in clean Windows environment:

```powershell
# Run script
.\ScriptName.ps1

# Check exit code
$LASTEXITCODE  # Should be 0 for success

# Verify logs
Get-Content C:\xoap-logs\ScriptName_*.log
```

---

## Documentation

### File Documentation

Update documentation when adding/changing:

1. **Autounattend files:** Update `autounattend/README.md`
2. **Packer templates:** Update main `README.md`
3. **Scripts:** Add inline comments and update script headers
4. **New features:** Update `CHANGELOG.md`

### Documentation Standards

- Use Markdown formatting
- Include code examples
- Add links to related documentation
- Keep language clear and concise
- Include troubleshooting sections

---

## Questions?

- **Email:** Contact XOAP team
- **Issues:** Create a GitHub issue
- **Discussions:** Use GitHub Discussions for general questions

Thank you for contributing to XOAP Packer Templates! 🎉
