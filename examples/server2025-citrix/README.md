# Windows Server 2025 — Citrix VDA (multi-session) master image (vSphere)

Builds a Windows Server 2025 master image with the **Citrix VDA in Server (multi-session)
edition** for **Machine Creation Services (MCS)** on **vSphere** from install media
(`vsphere-iso`): boots the Server 2025 ISO unattended, patches the OS, installs the VDA in
Server edition, applies the Citrix optimization pass, gates the build with an in-image
Pester test, cleans up, and generalizes with Sysprep — then converts the VM to a vSphere
template ready for a Citrix MCS catalog.

## Install-media wiring

| Piece | How it is wired |
|---|---|
| ISO | `iso_url` + `iso_checksum` (vars from `SERVER2025_ISO_URL` / `SERVER2025_ISO_CHECKSUM`). |
| Answer file | `autounattend/2025/vsphere/Autounattend-Standard.xml`, attached via `floppy_files` (var `autounattend_file`). |
| Boot | `boot_command: ["<spacebar>"]`, `boot_wait: 3s`. |
| Communicator | top-level `connection: { type: winrm }`. |

## Ordered action manifest

| # | Action | Why / notes |
|---|---|---|
| 1 | `windows-update` | Patch first. |
| 2 | `scripts/windows11-Install_Citrix_VDA.ps1` (`CITRIX_VDA_EDITION=Server`, `CITRIX_VDA_MODE=MCS`) | Installs the VDA in **Server** (multi-session) edition, MCS master-image mode. Exits **3010** → `valid_exit_codes: [0, 3010]`. |
| 3 | *(windows-restart)* | Completes VDA installation before the optimization pass. |
| 4 | `scripts/windows11-Configure_Citrix_Optimizations.ps1` | Citrix VDI optimization pass (**after** the VDA is installed). |
| 5 | `file` → `tests/CitrixVDA.Tests.ps1` + `pester-validate` | Stages and runs the Pester gate; a failed assertion aborts the build. |
| 6 | `scripts/windows-server-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 7 | `scripts/windows-server-Invoke_Sysprep.ps1` (`SYSPREP_VMMODE=1`) | Generalize for capture (`/generalize /oobe /mode:vm`). May exit `3010`. |

### Ordering constraints

- **VDA before optimizations.** The VDA (step 2) must be installed before the optimization
  pass (step 4) so the optimizer sees the final Citrix state.
- **VDA install requires a reboot.** `Install_Citrix_VDA.ps1` exits **3010**; a
  `windows-restart` runs before the optimization pass. Sysprep likewise may exit `3010`.

## Required: Citrix VDA installer

`CITRIX_VDA_INSTALLER` is **REQUIRED** — the VDA has **no public download**. Stage the
Server VDA installer (e.g. `VDAServerSetup_2402.exe`) on the build VM and set
`citrix_vda_installer` / `CITRIX_VDA_INSTALLER`. With no installer, the VDA step fails.

## Run in a XOAP workspace

1. **Vendor the scripts:** `pwsh examples/sync-demo-scripts.ps1 -Set server2025-citrix`.
2. **Add a vSphere Connection** = your **vCenter credentials** (`VSPHERE_SERVER`,
   `VSPHERE_USERNAME`, `VSPHERE_PASSWORD`, `VSPHERE_CLUSTER`, `VSPHERE_DATASTORE`,
   `VSPHERE_DATACENTER`, `VSPHERE_NETWORK`).
3. **Assign a Connector device** in the workspace to execute the build against that vCenter.
4. Supply `SERVER2025_ISO_URL`, `SERVER2025_ISO_CHECKSUM`, `WINRM_PASSWORD`, the **required**
   `CITRIX_VDA_INSTALLER`, and optionally `CITRIX_CONTROLLERS`.
5. Upload this set and run the build.

## Expected outcome

- A generalized **vSphere template** with the Citrix VDA installed in Server (multi-session)
  edition and the Citrix optimizations applied — ready to be registered as the master image
  of a **Citrix MCS machine catalog** (multi-session Server OS).
- The in-build Pester gate has asserted the Server SKU and the Citrix VDA service/registry,
  so a broken image is never captured.

### Post-deploy

- Register the resulting MCS catalog against your Delivery Controllers (`CITRIX_CONTROLLERS`
  can bake the list at build time, or set it in Citrix Studio after capture).
- Assign the template to a Citrix MCS machine catalog with a **Server OS** (multi-session)
  machine type and publish a shared desktop / apps.
