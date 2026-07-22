# Windows 11 — Citrix VDA + PVS target-device master image (vSphere)

Builds a Windows 11 master image for **Citrix Provisioning Services (PVS)** streaming on
**vSphere** from install media (`vsphere-iso`): boots the Windows 11 ISO unattended, patches
the OS, installs the Citrix VDA in **PVS** mode, prepares the image as a **PVS Target
Device**, applies the Citrix VDI optimization pass, gates the build with an in-image Pester
test, cleans up, and generalizes with Sysprep — then converts the VM to a vSphere template
ready to be captured to a PVS vDisk.

This mirrors the MCS set (`../w11-citrix-mcs`) but follows the **PVS** flow: `Install_Citrix_VDA`
with `CITRIX_VDA_MODE=PVS`, `Prepare_For_Citrix_PVS`, then `Configure_Citrix_Optimizations`.

## Install-media wiring

| Piece | How it is wired |
|---|---|
| ISO | `iso_url` + `iso_checksum` (vars from `W11_ISO_URL` / `W11_ISO_CHECKSUM`). |
| Answer file | `autounattend/W11/vsphere/Autounattend-Enterprise.xml`, attached via `floppy_files` (var `autounattend_file`). |
| Boot | `boot_command: ["<spacebar>"]`, `boot_wait: 3s`. |
| Communicator | top-level `connection: { type: winrm }`. |

## Ordered action manifest

| # | Action | Why / notes |
|---|---|---|
| 1 | `windows-update` | Patch first. |
| 2 | `scripts/windows11-Install_Citrix_VDA.ps1` (`CITRIX_VDA_MODE=PVS`) | Installs the VDA in **PVS** master-image mode. Exits **3010** → `valid_exit_codes: [0, 3010]`. |
| 3 | *(windows-restart)* | Completes VDA installation before PVS prep. |
| 4 | `scripts/windows11-Prepare_For_Citrix_PVS.ps1` (`PVS_INSTALLER_PATH`) | Prepares the PVS Target Device (**after** the VDA is installed). Optionally installs the PVS Target Device software if `PVS_INSTALLER_PATH` is set. |
| 5 | `scripts/windows11-Configure_Citrix_Optimizations.ps1` | Citrix VDI optimization pass (**after** PVS prep). |
| 6 | `file` → `tests/CitrixPVS.Tests.ps1` + `pester-validate` | Stages and runs the Pester gate; a failed assertion aborts the build. |
| 7 | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 8 | `scripts/windows-server-Invoke_Sysprep.ps1` (`SYSPREP_VMMODE=1`) | Generalize for capture. May exit `3010`. |

### Ordering constraints

- **VDA before PVS prep before optimizations.** The VDA (step 2) must be installed before
  `Prepare_For_Citrix_PVS` (step 4), which must complete before the optimization pass (step 5).
- **VDA install requires a reboot.** `Install_Citrix_VDA.ps1` exits **3010**; a
  `windows-restart` runs before PVS prep. Sysprep likewise may exit `3010`.

## PVS target-device specifics

- **Cache in device RAM with overflow to disk** is the recommended PVS write-cache mode for
  a streamed target; configure it on the vDisk / target-device properties in the PVS
  console after capture (it is a stream-time setting, not baked into the master).
- **Pagefile via CIM.** `Prepare_For_Citrix_PVS.ps1` sets the pagefile to system-managed
  using `Get-CimInstance` / `Set-CimInstance` (`wmic` is removed on Windows 11 24H2+), sized
  for the RAM cache overflow. The Pester gate asserts `AutomaticManagedPagefile = True`.
- The script also disables services that are unnecessary or harmful on a streamed target and
  skips defrag by default (`PVS_DEFRAG=false`).

## Required: Citrix VDA installer

`CITRIX_VDA_INSTALLER` is **REQUIRED** — the VDA has **no public download**. Stage the
installer on the build VM and set `citrix_vda_installer` / `CITRIX_VDA_INSTALLER`. The PVS
Target Device installer (`PVS_INSTALLER_PATH`) is optional; when omitted, install it
separately on the streamed target.

## Run in a XOAP workspace

1. **Vendor the scripts:** `pwsh examples/sync-demo-scripts.ps1 -Set w11-citrix-pvs`.
2. **Add a vSphere Connection** = your **vCenter credentials** (`VSPHERE_SERVER`,
   `VSPHERE_USERNAME`, `VSPHERE_PASSWORD`, `VSPHERE_CLUSTER`, `VSPHERE_DATASTORE`,
   `VSPHERE_DATACENTER`, `VSPHERE_NETWORK`).
3. **Assign a Connector device** in the workspace to execute the build against that vCenter.
4. Supply `W11_ISO_URL`, `W11_ISO_CHECKSUM`, `WINRM_PASSWORD`, the **required**
   `CITRIX_VDA_INSTALLER`, and optionally `CITRIX_CONTROLLERS` / `PVS_INSTALLER_PATH`.
5. Upload this set and run the build.

## Expected outcome

- A generalized **vSphere template** with the Citrix VDA installed in PVS mode and the PVS
  target-device preparation + Citrix optimizations applied — ready to be captured to a
  **PVS vDisk** for streaming.
- The in-build Pester gate has asserted the Citrix VDA service/registry and the
  system-managed pagefile, so a broken master is never captured.

### Post-deploy

- Capture the template to a PVS vDisk (BNImage / Imaging Wizard) and set the write-cache to
  **cache in device RAM with overflow to hard disk** on the vDisk / target device.
- Register the target device collection against your Delivery Controllers
  (`CITRIX_CONTROLLERS` can bake the list at build time).
