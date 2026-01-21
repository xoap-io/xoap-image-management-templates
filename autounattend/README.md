# XOAP Autounattend Files - Complete Reference

## Overview

Comprehensive collection of Windows unattended installation files for automated image creation across multiple hypervisor platforms. All files follow XOAP standards with xoap-admin user, WinRM configuration, and unattended OOBE.

## Directory Structure

```PowerShell
autounattend/
├── 2019/                    # Windows Server 2019
├── 2022/                    # Windows Server 2022
├── 2025/                    # Windows Server 2025
├── W11/                     # Windows 11 24H2
```

## Supported Hypervisors

### VMware vSphere/ESXi

- **Path:** `{version}/vsphere/`
- **Firmware:** BIOS/Legacy boot
- **Partitions:** 2 (100MB boot + Windows)
- **Drivers:** VMware SVGA, VMXNET3, PVSCSI

### Nutanix AHV

- **Path:** `{version}/nutanix/`
- **Firmware:** BIOS/Legacy boot
- **Partitions:** 2 (100MB boot + Windows)
- **Drivers:** VirtIO (viostor, NetKVM, Balloon, etc.)
- **Driver Paths:**
  - Windows Server 2019: `E:\viostor\2k19\amd64`
  - Windows Server 2022: `E:\viostor\2k22\amd64`
  - Windows Server 2025: `E:\viostor\2k25\amd64`
  - Windows 11: `E:\viostor\w11\amd64`

### Citrix XenServer/Hypervisor

- **Path:** `{version}/xenserver/`
- **Firmware:** BIOS/Legacy boot
- **Partitions:** 2 (100MB boot + Windows)
- **Drivers:** XenServer PV drivers (post-install)

### Microsoft Hyper-V Gen1

- **Path:** `{version}/hyperv/`
- **Firmware:** BIOS/Legacy boot
- **Partitions:** 2 (100MB boot + Windows)
- **Drivers:** Hyper-V synthetic devices (native)

### Microsoft Hyper-V Gen2

- **Path:** `{version}/hyperv-gen2/`
- **Firmware:** UEFI boot
- **Partitions:** 4 (350MB Recovery + 100MB EFI + 128MB MSR + Windows)
- **Drivers:** Hyper-V synthetic devices (native)

## Windows Server Editions

### Windows Server 2019 (4 editions per hypervisor)

- **StandardCore** - `Windows Server 2019 SERVERSTANDARDCORE`
- **Standard** - `Windows Server 2019 SERVERSTANDARD`
- **DatacenterCore** - `Windows Server 2019 SERVERDATACENTERCORE`
- **Datacenter** - `Windows Server 2019 SERVERDATACENTER`

### Windows Server 2022 (5 editions per hypervisor)

- **StandardCore** - `Windows Server 2022 SERVERSTANDARDCORE`
- **Standard** - `Windows Server 2022 SERVERSTANDARD`
- **DatacenterCore** - `Windows Server 2022 SERVERDATACENTERCORE`
- **Datacenter** - `Windows Server 2022 SERVERDATACENTER`
- **AzureStackHCI** - `Azure Stack HCI SERVERAZURESTACKHCICORE` ⚡ NEW

### Windows Server 2025 (5 editions per hypervisor)

- **StandardCore** - `Windows Server 2025 SERVERSTANDARDCORE`
- **Standard** - `Windows Server 2025 SERVERSTANDARD`
- **DatacenterCore** - `Windows Server 2025 SERVERDATACENTERCORE`
- **Datacenter** - `Windows Server 2025 SERVERDATACENTER`
- **AzureStackHCI** - `Azure Stack HCI SERVERAZURESTACKHCICORE` ⚡ NEW

## Windows 11 24H2 Editions (10 editions per hypervisor)

- **Education** - `Windows 10 Education`
- **EducationN** - `Windows 10 Education N`
- **Enterprise** - `Windows 10 Enterprise`
- **EnterpriseN** - `Windows 10 Enterprise N`
- **Pro** - `Windows 10 Pro`
- **ProN** - `Windows 10 Pro N`
- **ProEducation** - `Windows 10 Pro Education`
- **ProEducationN** - `Windows 10 Pro Education N`
- **ProWorkstation** - `Windows 10 Pro for Workstations`
- **ProNWorkstation** - `Windows 10 Pro N for Workstations`

## File Count Summary

### Total Files by Platform

- **VMware vSphere:** 28 files (4+4+5+5 Server editions + 10 W11)
- **Nutanix AHV:** 28 files (4+4+5+5 Server editions + 10 W11)
- **XenServer:** 28 files (4+4+5+5 Server editions + 10 W11)
- **Hyper-V Gen1:** 28 files (4+4+5+5 Server editions + 10 W11)
- **Hyper-V Gen2:** 28 files (4+4+5+5 Server editions + 10 W11)

**Total Hypervisor-Specific Files:** 114 autounattend XML files

### Breakdown by Windows Version

- **Windows Server 2019:** 20 files (4 editions × 5 hypervisors)
- **Windows Server 2022:** 25 files (5 editions × 5 hypervisors)
- **Windows Server 2025:** 25 files (5 editions × 5 hypervisors)
- **Windows 11 24H2:** 50 files (10 editions × 5 hypervisors)

## XOAP Standards

All autounattend files include:

### User Configuration

- **Username:** `xoap-admin` (NOT Administrator for AWS/cloud compatibility)
- **Password:** `xoap-admin` (plaintext, changed post-build)
- **Organization:** XOAP.io
- **Password Expiration:** Disabled

### WinRM Configuration

- **Port:** 5985 (HTTP)
- **Authentication:** Basic auth enabled
- **Max Timeout:** 1800000ms (30 minutes)
- **Max Memory:** 2048MB per shell
- **Allow Unencrypted:** true (for initial provisioning)

### System Settings

- **Locale:** en-US (Input, System, UI, User)
- **Timezone:** UTC
- **UAC:** Disabled
- **Firewall:** WinRM + Remote Administration groups enabled
- **Server Manager:** Disabled at logon
- **IE ESC:** Disabled (Admin + User)
- **System Restore:** Disabled
- **CEIP:** Disabled
- **Auto Activation:** Skipped

### First Logon Commands (17 steps)

1. Set PowerShell execution policy (64-bit)
2. Set PowerShell execution policy (32-bit)
3. Configure network profile as Private
4. Allow WinRM over public profile
5. WinRM quickconfig
6. WinRM quickconfig HTTP transport
7. Set WinRM MaxTimeout
8. Set WinRM MaxMemoryPerShell
9. Enable unencrypted WinRM
10. Enable Basic auth (service)
11. Enable Basic auth (client)
12. Configure WinRM listener (port 5985)
13. Open firewall port 5985
14. Stop WinRM service
15. Configure WinRM autostart
16. Start WinRM service
17. Disable password expiration for xoap-admin

## Partition Layouts

### BIOS/Legacy Boot (Gen1)

```PowerShell
Disk 0:
├── Partition 1: 100MB NTFS (boot, active)
└── Partition 2: Rest NTFS (C:, Windows)
```

### UEFI Boot (Gen2)

```PowerShell
Disk 0:
├── Partition 1: 350MB NTFS (WinRE, Recovery)
├── Partition 2: 100MB FAT32 (System, EFI)
├── Partition 3: 128MB (MSR)
└── Partition 4: Rest NTFS (C:, Windows)
```

## VirtIO Drivers (Nutanix)

### Driver Components

- **viostor** - SCSI storage controller
- **NetKVM** - Network adapter (paravirtual)
- **Balloon** - Memory ballooning
- **pvpanic** - Panic notification
- **qemupciserial** - PCI serial port
- **qxldod** - Display adapter
- **vioinput** - Input devices
- **viorng** - Random number generator
- **vioscsi** - SCSI pass-through
- **vioserial** - Serial console

### Driver Paths in Autounattend

```xml
<PathAndCredentials wcm:action="add" wcm:keyValue="1">
    <Path>E:\viostor\2k22\amd64</Path>
</PathAndCredentials>
<PathAndCredentials wcm:action="add" wcm:keyValue="2">
    <Path>E:\NetKVM\2k22\amd64</Path>
</PathAndCredentials>
<!-- ... 9 more driver paths ... -->
```

## Usage with Packer

### VMware vSphere Example

```hcl
vm_cdrom_path = "autounattend/2022/vsphere/Autounattend-Datacenter.xml"
```

### Nutanix Example

```hcl
vm_cdrom_path = "autounattend/2022/nutanix/Autounattend-DatacenterCore.xml"
# Mount VirtIO ISO as second CD-ROM drive (E:\)
```

### Hyper-V Gen2 Example

```hcl
vm_cdrom_path = "autounattend/2025/hyperv-gen2/Autounattend-AzureStackHCI.xml"
vm_generation = 2  # UEFI boot
```

## Azure Stack HCI Support

Azure Stack HCI edition is available for Windows Server 2022 and 2025 across all hypervisors:

- `autounattend/2022/hyperv/Autounattend-AzureStackHCI.xml`
- `autounattend/2022/hyperv-gen2/Autounattend-AzureStackHCI.xml`
- `autounattend/2022/vsphere/` - Add manually if needed
- `autounattend/2022/nutanix/` - Add manually if needed
- `autounattend/2022/xenserver/` - Add manually if needed

Same for Windows Server 2025.

## Troubleshooting

### Common Issues

1. **WinRM not responding**
   - Verify network profile is set to Private
   - Check firewall rules for port 5985
   - Ensure Basic auth is enabled

2. **Wrong edition installed**
   - Verify WIM image name matches exactly (case-sensitive)
   - Check ISO contains the specified edition
   - Use `wiminfo.md` or DISM to list available editions

3. **Partition errors**
   - Gen1 (BIOS): Use 2-partition layout
   - Gen2 (UEFI): Use 4-partition layout
   - Ensure VM firmware mode matches autounattend

4. **VirtIO drivers not loading (Nutanix)**
   - Verify VirtIO ISO is mounted as second CD-ROM (E:\)
   - Check driver paths match Windows version (2k19/2k22/2k25/w11)
   - Ensure all 11 driver components are present

## File Naming Convention

Format: `Autounattend-{Edition}.xml`

Examples:

- `Autounattend-StandardCore.xml`
- `Autounattend-Datacenter.xml`
- `Autounattend-AzureStackHCI.xml`
- `Autounattend-Pro.xml`
- `Autounattend-Enterprise.xml`

## Version History

### v2.0 (January 2026)

- ✅ Added Hyper-V Gen1 support (28 files)
- ✅ Added Hyper-V Gen2 support (28 files)
- ✅ Added Azure Stack HCI edition (Server 2022/2025)
- ✅ Reorganized hypervisor-specific folders
- ✅ Total: 114 hypervisor-specific autounattend files

### v1.0 (January 2026)

- ✅ Initial VMware vSphere support (28 files)
- ✅ Initial Nutanix AHV support (28 files)
- ✅ Initial XenServer support (28 files)
- ✅ Total: 66 autounattend files

## Related Documentation

- [Key Management Services](../helper/key-management-services.md) - Windows activation keys
- [Windows Server 2019 Image Names](../helper/w2019-1809-image-names-ids.md)
- [Windows Server 2022 Image Names](../helper/w2022-2108-image-names-ids.md)
- [Windows Server 2025 Image Names](../helper/w2025-2412-image-names-ids.md)
- [Windows 11 24H2 Image Names](../helper/w11-24h2-image-names-ids.md)
- [WIM Info](../helper/wiminfo.md) - Extract WIM image information

## License

Part of XOAP Infrastructure as Code ecosystem. See [LICENSE](../LICENSE) for details.
