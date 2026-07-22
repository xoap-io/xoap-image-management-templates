# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Hyper-V Gen1 (BIOS) support with 28 autounattend files
- Hyper-V Gen2 (UEFI) support with 28 autounattend files
- Azure Stack HCI edition support for Windows Server 2022 and 2025
- Comprehensive autounattend documentation in `autounattend/README.md`
- PowerShell scripts for cloud platform optimization (AWS, Azure, Google Cloud)
- Hypervisor-specific optimization scripts (VMware, Hyper-V, Proxmox, Nutanix, XenServer)
- Pre-commit hook exclusion for autounattend XML files
- Enhanced main README with platform support details
- Windows 11 24H2/25H2 hardware-requirement bypass (`LabConfig` TPM/Secure Boot/RAM/storage/CPU)
  in the BIOS/MBR answer-file trees (`vsphere`, `nutanix`, `xenserver`, `hyperv` Gen1)
- Explicit native-command exit-code checking (`$LASTEXITCODE`) in all application installers
- Functional `.github/CODEOWNERS`, expanded `.gitattributes` (CRLF pinning for scripts/answer files)
- PSScriptAnalyzer settings and CI, shellcheck CI, and `packer validate`/`packer fmt` CI

### Changed

- Reorganized autounattend structure by hypervisor type
- Updated Windows Server 2022/2025 editions to include Azure Stack HCI
- Improved autounattend file naming convention to `Autounattend-{Edition}.xml`
- Standardized the build credential on `xoap-admin` across Packer var files, Vagrant
  templates, and packer-local answer files (previously a mix of `Password01`);
  `winrm_password` is now a `sensitive` variable
- Re-pointed the Pester suite at the real `scripts/windows_server/**` tree; the standards
  and cloud-specific tests now execute (986 cases) instead of silently skipping

### Fixed

- XML validation issues with autounattend files in pre-commit hooks
- Windows 11 answer files carried `/IMAGE/NAME` values of `Windows 10 <edition>`; corrected to `Windows 11`
- Missing drive-letter colon in `autounattend/W11/nutanix/*.xml` (`E\qemupciserial` -> `E:\qemupciserial`)
- Removed a 60-minute `Start-Sleep` in error traps of 15 provisioning scripts that hung Packer builds on failure
- Repaired never-parsing data arrays in `windows-server-Optimize_w2k16.ps1` and a scope-qualifier
  syntax error in `hyperv/Install_HyperV_Integration_Services.ps1`
- Corrected all `.LINK` URLs from the old `xoap-packer-templates` repo name (78 files)

### Removed

- Root file with the illegal Windows name `C:\Windows\Temp\choco.ps1` (broke checkouts on Windows)
- Duplicate `windows-server_Configure_Azure_Services.ps1`, double-extension `Install_Winget.ps1.ps1`
- Windows 10 leftovers in the Windows 11 folder (`windows11-Optimize_W10_2004.ps1`, `windows11-W10_21H1_Remove_Apps.ps1`)
- Unreferenced `helper/tools/mkisofs.*`, `build/init.ps1`, empty `opentofu/nutanix/vm-nutanix.ps1`,
  committed CI artifact `tests/test-results.json`, and the non-functional root `CODEOWNERS.md`

## [2.0.0] - 2026-01-20

### Added

- 114 hypervisor-specific autounattend files
- VMware vSphere: 28 files (Windows Server 2019/2022/2025 + Windows 11)
- Nutanix AHV: 28 files with VirtIO driver support
- Citrix XenServer: 28 files
- Hyper-V Gen1: 28 files
- Hyper-V Gen2: 28 files with UEFI support
- Azure Stack HCI edition for Windows Server 2022 and 2025
- Complete PowerShell provisioning script suite:
- AWS EC2: Install, Optimize, Sysprep (3 scripts)
- Azure VMs: Install, Optimize, Sysprep (3 scripts)
- Google Cloud: Install, Optimize, Sysprep (3 scripts)
- VMware: Install Tools, Optimize (2 scripts)
- Hyper-V: Install Integration Services, Optimize (2 scripts)
- Proxmox: Install Guest Agent, Optimize (2 scripts)
- Nutanix: Optimize (1 script)
- XenServer: Install Tools, Configure Drivers, Optimize (3 scripts)
- Helper documentation for WIM image names:
- Windows Server 2016/2019/2022/2025
- Windows 11 24H2
- VirtIO drivers for QEMU/KVM platforms (Nutanix, Proxmox)

### Changed

- Migrated from basic autounattend files to hypervisor-specific organization
- Enhanced XOAP logging framework in all PowerShell scripts
- Updated WinRM configuration for better cloud compatibility
- Standardized user account to `xoap-admin` across all platforms

### Deprecated

- Legacy autounattend folder structure (`windows_server_*` directories)
- Files maintained for backward compatibility
- Will be removed in v3.0.0

## [1.0.0] - 2025-12-01

### Added

- Initial VMware vSphere/ESXi support
- Basic Windows Server autounattend files (2016/2019/2022)
- Windows 10/11 autounattend files
- KMS activation key documentation
- Basic Packer templates for VMware
- Pre-commit hooks for Packer validation
- OpenTofu deployment configurations for AWS, Azure, Google Cloud, vSphere

### Features

- Unattended Windows installation support
- WinRM remote access configuration
- Automated Windows Update installation with filters
- VMware Tools installation scripts
- Vagrant box post-processor support

## Version History Legend

### Types of Changes

- **Added** - New features, files, or functionality
- **Changed** - Changes to existing functionality
- **Deprecated** - Features marked for removal in future versions
- **Removed** - Features removed in this version
- **Fixed** - Bug fixes
- **Security** - Security vulnerability fixes

### Supported Windows Versions

- Windows Server 2016 (Build 1607)
- Windows Server 2019 (Build 1809)
- Windows Server 2022 (Build 2108)
- Windows Server 2025 (Build 2412)
- Windows 10 (21H2, 22H2)
- Windows 11 (24H2)

### Supported Hypervisors

- VMware vSphere/ESXi 6.7+
- Nutanix AHV
- Citrix XenServer/Hypervisor
- Microsoft Hyper-V (Gen1 & Gen2)
- Proxmox VE
- QEMU/KVM

### Supported Cloud Platforms

- AWS EC2
- Microsoft Azure
- Google Compute Engine

---

[Unreleased]: https://github.com/xoap-io/xoap-image-management-templates/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/xoap-io/xoap-image-management-templates/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/xoap-io/xoap-image-management-templates/releases/tag/v1.0.0
