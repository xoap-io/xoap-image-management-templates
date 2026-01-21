# XOAP Packer Templates - AI Coding Assistant Instructions

## Project Overview
This repository contains Packer templates for automated Windows VM image creation across multiple platforms (VMware, AWS, Azure, Hyper-V, QEMU). Part of the XOAP Infrastructure as Code ecosystem, it focuses on Windows Server (2016-2025), Windows 10/11, and provides unattended installation configurations.

## Architecture & File Organization

### Directory Structure Pattern
```
{builder-type}/
├── windows/
│   ├── w{version}-{build}/          # e.g., w2022-2108, w2019-1809
│   │   ├── w{version}-{edition}-{arch}-{locale}/  # e.g., w2022-2108-dc-dx-en
│   │   │   ├── {builder}-{name}.pkr.hcl          # Packer configuration
│   │   │   └── {builder}-{name}.pkrvars.hcl      # Variable definitions
```

### Key Components
- **`vmware-iso/`** - VMware Workstation/Fusion templates (primary platform)
- **`amazon-ebs/`** - AWS EC2 AMI builders  
- **`autounattend/`** - Unattended installation XML configs per Windows version
- **`scripts/`** - PowerShell provisioning scripts organized by OS type
- **`drivers/`** - VirtIO drivers for QEMU/KVM by Windows version
- **`templates/`** - Base template for creating new configurations
- **`opentofu/`** - Infrastructure deployment configs for multiple clouds

### Naming Conventions
- **Windows versions**: `w2022-2108` (Windows Server 2022 build 2108), `w2k19-1809`, `w2k16-1607`
- **Editions**: `std` (Standard), `dc` (Datacenter), `core` (Server Core)  
- **UI**: `dx` (Desktop Experience), `core` (Server Core without GUI)
- **Architecture**: Always `amd64`/x64
- **Locale**: `en` (English)

## Essential Patterns

### Packer Configuration Structure
Each `.pkr.hcl` follows this pattern:
1. **Required plugins** - Always includes `windows-update` plugin
2. **Extensive variable definitions** - ~50+ variables with detailed descriptions
3. **Single source block** - Builder-specific (vmware-iso, amazon-ebs, etc.)
4. **Standardized build block**:
   ```hcl
   build {
     sources = ["source.{builder-type}.{builder-name}"]
     
     provisioner "powershell" { /* Initial setup scripts */ }
     provisioner "windows-restart" { /* First reboot */ }
     provisioner "windows-update" { /* Windows updates */ }
     provisioner "windows-restart" { /* Post-update reboot */ }
     provisioner "powershell" { /* Cleanup */ }
     
     post-processor "vagrant" { /* Vagrant box creation */ }
     post-processor "checksum" { /* SHA1 checksums */ }
     post-processor "manifest" { /* Build metadata */ }
   }
   ```

### Variable Management
- **`.pkrvars.hcl` files** - Define actual values, never commit sensitive data
- **Common variables across all templates**:
  - `communicator = "winrm"`
  - `winrm_username = "xoap-admin"` (not Administrator for AWS)
  - `iso_checksum` and `iso_url` for source media
  - `vm_name` follows naming convention
  - `tools_upload_flavor = ""` (empty for VMware Tools auto-detection)

### Windows Updates Configuration
Critical filter pattern in all templates:
```hcl
filters = [
  "exclude:$_.Title -like '*Preview*'",
  "exclude:$_.Title -like '*Feature update*'",  # Remove to get latest features
  "include:$true"
]
```

### WinRM Communication
- **Port**: 5985 (HTTP), 5986 (HTTPS)
- **Authentication**: Basic auth for most builders, NTLM for advanced scenarios
- **Timeout**: `2h` minimum for Windows setup
- **Username**: `xoap-admin` (NOT Administrator for AWS compatibility)

## Platform-Specific Knowledge

### VMware (Primary Platform)
- **Builder**: `vmware-iso`
- **Tools**: Automatically detected via `tools_upload_flavor = ""`
- **Network**: `e1000` adapter type default
- **Disk**: SCSI adapter, expandable disks (~40GB default)
- **Output**: Creates `.vmx` files and disk images

### AWS EC2 
- **Builder**: `amazon-ebs`  
- **Critical**: AMI IDs are region-specific
- **Authentication**: Use IAM roles/profiles, not access keys
- **WinRM**: Must use "Administrator" username, password auto-generated
- **Sysprep**: Uses EC2Launch v2 for password retrieval

### Unattended Installation
- **Location**: `autounattend/{version}/Autounattend.xml`
- **VirtIO drivers**: Pre-configured paths for QEMU/KVM
- **Product keys**: Uses KMS keys from `helper/key-management-services.md`
- **Partitioning**: UEFI vs BIOS configurations in separate variants

## Essential Scripts & Workflows

### PowerShell Scripts (`scripts/windows/`)
- **`provision.ps1`** - Guest tools installation (VMware, VirtualBox, Parallels, QEMU)
- **`configure-winrm.ps1`, `enable-rdp.ps1`** - Remote access setup
- **`disable-windows-updates.ps1`** - Disable auto-updates post-build
- **`cleanup.ps1`** - Final image optimization

### Development Workflow
1. **Pre-commit hooks** - Validates Packer configs via `pre-commit-packer`
2. **Build command**: `packer build -var-file="config.pkrvars.hcl" template.pkr.hcl`
3. **Template creation**: Copy from `templates/vmware-iso-template/`
4. **Variable files**: Must have both `.pkr.hcl` and `.pkrvars.hcl` for validation

### Helper Resources
- **`helper/w{version}-image-names-ids.md`** - WIM image indexes and editions
- **`helper/key-management-services.md`** - Windows activation keys
- **`drivers/`** - VirtIO drivers organized by Windows version and component

## Critical Considerations

### Windows Version Support
- **Windows Server**: 2016 (1607), 2019 (1809), 2022 (2108), 2025 (2412)
- **Client OS**: Windows 10, Windows 11 (24H2)
- **Editions**: Standard, Datacenter, Core variants
- **Architecture**: x64 only (amd64)

### Build Environment
- **Tested on**: macOS Ventura, Packer 1.8.0+, VMware Fusion Pro 12.3.3+
- **Windows Updates**: Filtered to exclude previews and feature updates by default
- **Memory**: Minimum 2GB RAM, 2 CPUs for build performance
- **Network**: Uses NAT networking, VNC on ports 5980-5990

### Multi-Cloud Deployment
- **OpenTofu configs** - Ready-to-use IaC in `opentofu/{aws,azure,google,vsphere}/`
- **Terraform compatibility** - Uses HashiCorp provider syntax
- **Variable consistency** - Same naming across Packer and Terraform configs

When working with this codebase, always follow the established naming conventions, use the template system for new configurations, and ensure both `.pkr.hcl` and `.pkrvars.hcl` files exist for proper validation.