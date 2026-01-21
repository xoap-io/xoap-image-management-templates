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

### Changed

- Reorganized autounattend structure by hypervisor type
- Updated Windows Server 2022/2025 editions to include Azure Stack HCI
- Improved autounattend file naming convention to `Autounattend-{Edition}.xml`

### Fixed

- XML validation issues with autounattend files in pre-commit hooks

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
