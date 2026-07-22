# Windows 11 — Citrix VDA + MCS master image (vSphere)

Builds a Windows 11 master (golden) image for **Citrix Machine Creation Services (MCS)** on
**vSphere** from install media (`vsphere-iso`): boots the Windows 11 ISO with an unattended
answer file, patches the OS, installs the Citrix Virtual Delivery Agent (VDA) in
master-image mode, runs the MCS master-image preparation, applies the Citrix VDI
optimization pass, gates the build with an in-image Pester test, cleans up, and generalizes
with Sysprep — then converts the VM to a vSphere template ready for an MCS catalog.

## Install-media wiring

| Piece | How it is wired |
|---|---|
| ISO | `iso_url` + `iso_checksum` (template vars, fed from `W11_ISO_URL` / `W11_ISO_CHECKSUM`). |
| Answer file | `autounattend/W11/vsphere/Autounattend-Enterprise.xml`, attached via `floppy_files` (var `autounattend_file`). Windows Setup consumes it unattended and sets the local Administrator password. |
| Boot | `boot_command: ["<spacebar>"]` (answers the "Press any key to boot from CD/DVD" prompt), `boot_wait: 3s`. |
| Communicator | top-level `connection: { type: winrm }` (`winrm_username` / `winrm_password`); the answer file enables WinRM in the guest. |

## Ordered action manifest

| # | Action | Why / notes |
|---|---|---|
| 1 | `windows-update` | Patch first. |
| 2 | `scripts/windows11-Install_Citrix_VDA.ps1` (`CITRIX_VDA_MODE=MCS`, `CITRIX_VDA_EDITION=Workstation`) | Installs the VDA in **MCS** master-image mode. Exits **3010** on reboot-required → `valid_exit_codes: [0, 3010]`. |
| 3 | *(windows-restart)* | Completes VDA installation before MCS prep. |
| 4 | `scripts/windows11-Prepare_Citrix_MCS.ps1` | MCS master-image preparation (**after** the VDA is installed). |
| 5 | `scripts/windows11-Configure_Citrix_Optimizations.ps1` | Citrix VDI optimization pass (**after** MCS prep). |
| 6 | `file` → `tests/CitrixVDA.Tests.ps1` + `pester-validate` | Stages and runs the Pester gate; a failed assertion aborts the build. |
| 7 | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 8 | `scripts/windows-server-Invoke_Sysprep.ps1` (`SYSPREP_VMMODE=1`) | Generalize for capture (`/generalize /oobe /mode:vm`). May exit `3010`. |

### Ordering constraints

- **VDA before MCS prep before optimizations.** The VDA (step 2) must be installed before
  `Prepare_Citrix_MCS` (step 4), and MCS prep must complete before
  `Configure_Citrix_Optimizations` (step 5) so the optimizer sees the final Citrix state.
- **VDA install requires a reboot.** `Install_Citrix_VDA.ps1` exits **3010** when the
  installer signals reboot-required; the action treats `3010` as success and a
  `windows-restart` runs before MCS prep. Sysprep likewise may exit `3010`.

## Required: Citrix VDA installer

`CITRIX_VDA_INSTALLER` is **REQUIRED** — the VDA has **no public download**. Stage the
installer (e.g. `VDAWorkstationSetup_2402.exe`) onto the build VM and set
`citrix_vda_installer` / `CITRIX_VDA_INSTALLER` to its path. With no installer, the VDA step
fails.

## Run in a XOAP workspace

1. **Vendor the scripts:** `pwsh examples/sync-demo-scripts.ps1 -Set w11-citrix-mcs` copies
   the referenced `scripts/*.ps1` into `alpaka/scripts/` (git-ignored build scratch).
2. **Add a vSphere Connection** to the workspace = your **vCenter credentials**
   (`VSPHERE_SERVER`, `VSPHERE_USERNAME`, `VSPHERE_PASSWORD`, `VSPHERE_CLUSTER`,
   `VSPHERE_DATASTORE`, `VSPHERE_DATACENTER`, `VSPHERE_NETWORK`).
3. **Assign a Connector device** in the workspace to execute the build against that vCenter
   (the Connector is the on-prem agent that reaches your vSphere environment).
4. Supply the media/secret variables: `W11_ISO_URL`, `W11_ISO_CHECKSUM`, `WINRM_PASSWORD`,
   and the **required** `CITRIX_VDA_INSTALLER` (plus optional `CITRIX_CONTROLLERS`).
5. Upload this set and run the build.

## Expected outcome

- A generalized **vSphere template** (`convert_to_template: true`) with the Citrix VDA
  installed in MCS master-image mode and the Citrix optimizations applied — ready to be
  registered as the master image of a **Citrix MCS machine catalog**.
- The in-build Pester gate has asserted the Citrix VDA service + `HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent`
  registry are present, so a broken image is never captured.

### Post-deploy

- Register the resulting MCS catalog against your Delivery Controllers (bake the controller
  list at build time via `CITRIX_CONTROLLERS`, or set it in Citrix Studio after capture).
- Assign the template to a Citrix MCS machine catalog (single-session per this Windows 11 edition).
