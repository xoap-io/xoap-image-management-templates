[![Maintained](https://img.shields.io/badge/Maintained%20by-XOAP-success)](https://xoap.io)
[![Packer](https://img.shields.io/badge/Packer-%3E%3D1.8.0-blue)](https://packer.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Guidelines](#guidelines)
  - [Share the Love](#share-the-love)
  - [Contributing](#contributing)
  - [Bug Reports and Feature Requests](#bug-reports--feature-requests)
  - [Developing](#developing)
    - [Usage](#usage)
      - [Installation](#installation)
      - [Prerequisites](#prerequisites)
      - [Windows Updates](#windows-updates)

---

## Introduction

This is the XOAP Image Management repository for automated Windows VM image creation.

It is part of our [XOAP](https://xoap.io) Automation Forces Open Source community library to give you a quick start into Infrastructure as Code deployments with Packer in addition to image.XO.

**Key Features:**

- 🖼️ **114 Autounattend Files** - Comprehensive unattended installation support for Windows Server (2016-2025) and Windows 11 across 5 hypervisor platforms
- ☁️ **Multi-Cloud Support** - AWS EC2, Azure VMs, Google Compute Engine with optimized provisioning scripts
- 🔧 **Hypervisor Coverage** - VMware vSphere, Nutanix AHV, Citrix XenServer, Hyper-V Gen1/Gen2, Proxmox VE
- 🎯 **Azure Stack HCI** - Dedicated support for Azure Stack HCI editions (Server 2022/2025)
- 📦 **Automated Provisioning** - PowerShell scripts for guest tools installation, performance optimization, and sysprep preparation

Please check the links for more info, including usage information and full documentation:

- [XOAP Website](https://xoap.io)
- [XOAP Documentation](https://docs.xoap.io)
- [Twitter](https://twitter.com/xoap_io)
- [LinkedIn](https://www.linkedin.com/company/xoap_io)

---

## Guidelines

We are using the following guidelines to write code and make it easier for everyone to follow a distinctive guideline.
Please check these links before starting to work on changes.

[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

Git Naming Conventions are an important part of the development process.
They describe how Branches, Commit Messages,
Pull Requests and Tags should look like to make them easily understandable for everybody in the development chain.

[Git Naming Conventions](https://namingconvention.org/git/)

He Conventional Commits specification is a lightweight convention on top of commit messages.
It provides an easy set of rules for creating an explicit commit history; which makes it easier to write automated tools on top of.

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)

The better a Pull Request description is, the better a review can understand and decide on how to review the changes.
This improves implementation speed and reduces communication between the requester,
and the reviewer is resulting in much less overhead.

[Writing A Great Pull Request Description](https://www.pullrequest.com/blog/writing-a-great-pull-request-description/)

Versioning is a crucial part for Terraform Stacks and Modules.
Without version tags you cannot clearly create a stable environment
and be sure that your latest changes will not crash your production environment (sure it still can happen,
but we are trying our best to implement everything that we can to reduce the risk)

[Semantic Versioning](https://semver.org)

---

## Share the Love

Like this project?
Please give it a ★ on [our GitHub](https://github.com/xoap-io/xoap-uberagent-kibana-dashboards)!
It helps us a lot.

---

## Contributing

### Bug Reports & Feature Requests

Please use the issue tracker to report any bugs or file feature requests.

### Developing

If you are interested in being a contributor and want to get involved in developing this project, we would love to hear from you! Email us.

PRs are welcome. We follow the typical "fork-and-pull" Git workflow.

- Fork the repo on GitHub
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull Request so that we can review your changes

> NOTE: Be sure to merge the latest changes from "upstream" before making a pull request!

---

## Usage

### Installation

You can install Packer from the Hashicorp website: https://developer.hashicorp.com/packer/downloads?product_intent=packer.

### Prerequisites

All the available Packer configurations are provided "as is" without any warranty.

They were tested and run with on following infrastructure:

- macOS Ventura 13.3.1
- Hashicorp Packer 1.8.0
- VMware Fusion Pro 12.3.3
- Windows 10 22H2 Enterprise with Hyper-V

### Supported Platforms

#### Hypervisors

- **VMware vSphere/ESXi** - BIOS boot with VMXNET3/PVSCSI drivers
- **Nutanix AHV** - BIOS boot with VirtIO drivers (2k19/2k22/2k25/w11)
- **Citrix XenServer** - BIOS boot with XenServer PV drivers
- **Hyper-V Gen1** - BIOS boot with Integration Services
- **Hyper-V Gen2** - UEFI boot with 4-partition layout
- **Proxmox VE** - QEMU/KVM with VirtIO drivers

#### Cloud Platforms

- **AWS EC2** - AMI creation with ENA drivers and IMDSv2 support
- **Azure VMs** - VM image creation with Accelerated Networking
- **Google Compute Engine** - GCE image creation with gVNIC support

#### Windows Versions

- **Windows Server 2016** (1607) - 4 editions
- **Windows Server 2019** (1809) - 4 editions
- **Windows Server 2022** (2108) - 5 editions (inc. Azure Stack HCI)
- **Windows Server 2025** (2412) - 5 editions (inc. Azure Stack HCI)
- **Windows 11 24H2** - 10 editions

### Autounattend Files

The `autounattend/` directory contains **114 hypervisor-specific unattended installation files** organized by Windows version and hypervisor:

```PowerSHell
autounattend/
├── 2019/               # Windows Server 2019
│   ├── vsphere/        # 4 editions
│   ├── nutanix/        # 4 editions with VirtIO
│   ├── xenserver/      # 4 editions
│   ├── hyperv/         # 4 editions (Gen1/BIOS)
│   └── hyperv-gen2/    # 4 editions (Gen2/UEFI)
├── 2022/               # Windows Server 2022
│   ├── vsphere/        # 5 editions (inc. Azure Stack HCI)
│   ├── nutanix/        # 5 editions
│   ├── xenserver/      # 5 editions
│   ├── hyperv/         # 5 editions
│   └── hyperv-gen2/    # 5 editions
├── 2025/               # Windows Server 2025
│   └── ...             # Same structure as 2022
└── W11/                # Windows 11 24H2
    └── ...             # 10 editions per hypervisor
```

**Available Editions:**

- StandardCore, Standard, DatacenterCore, Datacenter
- Azure Stack HCI (Server 2022/2025 only)
- Windows 11: Education, Enterprise, Pro, Pro for Workstations (all with N variants)

See [autounattend/README.md](autounattend/README.md) for complete documentation.

### Provisioning Scripts

PowerShell scripts for guest tools installation, optimization, and sysprep located in `scripts_wip/windows_server_2025_scripts/`:

#### Cloud Platform Scripts

- **AWS EC2**
  - `aws/Install_AWS_Tools.ps1` - AWS CLI, SSM Agent, CloudWatch Agent
  - `aws/Optimize_AWS_EC2_Performance.ps1` - ENA driver, NVMe storage optimization
  - `aws/amazon-ebs-sysprep.ps1` - EC2Launch v2 sysprep preparation

- **Azure VMs**
  - `azure/Install_Azure_Tools.ps1` - Azure VM Agent, CLI, Monitor Agent
  - `azure/Optimize_Azure_Performance.ps1` - Accelerated Networking, disk optimization
  - `azure/azure-vm-sysprep.ps1` - Azure-specific sysprep

- **Google Cloud**
  - `google/Install_GCP_Tools.ps1` - Cloud SDK, Operations Agent
  - `google/Optimize_GCP_Performance.ps1` - VirtIO network/storage tuning
  - `google/gcp-vm-sysprep.ps1` - GCE sysprep preparation

#### Hypervisor Scripts

- **VMware** - Tools installation, PVSCSI/vmxnet3 optimization
- **Hyper-V** - Integration Services, Enhanced Session Mode
- **Proxmox** - QEMU Guest Agent, VirtIO driver tuning
- **Nutanix** - NutanixGuestAgent, AHV optimization
- **XenServer** - PV drivers, platform-specific tuning

### Pre-Commit-Hooks

We added https://github.com/xoap-io/pre-commit-packer which enables validating and formatting the packer configuration files.

> Every time you commit a change to your packer configuration files, the pre-commit hook will run and validate the configuration.

Additionally it is crucial to have a pkrvars.hcl and a pkr.hcl file in every subfolder so that the packer configuration files are correctly formatted and validated.

### Windows Updates

The filters for the Windows Updates are set as follows:

filters = [
"exclude:$_.Title -like '*Preview*'",
"exclude:$_.Title -like '*Feature update*'",
"include:$true",
]

If you want your images to be updated to the latest feature level, remove the following line:

"exclude:$\_.Title -like '*Feature update*'",

### helper

We added the KMS keys for the Windows based operating systems in [helper/key-management-services.md](helper/key-management-services.md).

You can also find all the ISO image-related operating system keys and WIM image names in the same directory:

- [Windows Server 2016 Image Names](helper/w2016-1607-image-names-ids.md)
- [Windows Server 2019 Image Names](helper/w2019-1809-image-names-ids.md)
- [Windows Server 2022 Image Names](helper/w2022-2108-image-names-ids.md)
- [Windows Server 2025 Image Names](helper/w2025-2412-image-names-ids.md)
- [Windows 11 24H2 Image Names](helper/w11-24h2-image-names-ids.md)

Use these WIM image names in your autounattend files to select the correct Windows edition during installation.

### amazon-ebs builder

#### AMI-IDs

> Be aware of the fact that AMI-Ids are region-specific when defining them in the configuration.

#### Username and Password

> Do not change the winrm user and password because "Administrator" must be specified and the password is generated during the Packer build.

#### Sysprep and Password retrieval

See https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch-v2.html for more information.

#### AWS account access

> We recommend using a local credentials file or assuming a role instead of specifying an access key and secret.

### azure-arm builder

### vmware-iso builder

All VMware-based templates are located in the `vmware-iso/` directory. Use the autounattend files from `autounattend/{version}/vsphere/` for automated installations.

**Example:**

```hcl
vm_cdrom_path = "autounattend/2022/vsphere/Autounattend-Datacenter.xml"
```

### Hyper-V Support

Hyper-V templates support both Generation 1 (BIOS) and Generation 2 (UEFI) VMs:

- **Gen1 (BIOS):** Use files from `autounattend/{version}/hyperv/`
  - 2-partition layout (100MB boot + Windows)
  
- **Gen2 (UEFI):** Use files from `autounattend/{version}/hyperv-gen2/`
  - 4-partition layout (350MB Recovery + 100MB EFI + 128MB MSR + Windows)
  - Required for Windows 11 and modern UEFI systems

### Nutanix AHV

Nutanix templates require VirtIO drivers mounted as a second CD-ROM drive. The autounattend files in `autounattend/{version}/nutanix/` include all necessary VirtIO driver paths.

**VirtIO Driver Paths:**

- Windows Server 2019: `E:\viostor\2k19\amd64`
- Windows Server 2022: `E:\viostor\2k22\amd64`
- Windows Server 2025: `E:\viostor\2k25\amd64`
- Windows 11: `E:\viostor\w11\amd64`

### Azure Stack HCI

Azure Stack HCI editions are available for Windows Server 2022 and 2025 across all hypervisors:

- `autounattend/2022/hyperv/Autounattend-AzureStackHCI.xml`
- `autounattend/2022/hyperv-gen2/Autounattend-AzureStackHCI.xml`
- `autounattend/2025/hyperv/Autounattend-AzureStackHCI.xml`
- `autounattend/2025/hyperv-gen2/Autounattend-AzureStackHCI.xml`
