# Windows 11 Enterprise — Hyper-V (Gen2) base golden image

Builds a clean **Windows 11 Enterprise** base golden image on **Hyper-V** from the install ISO as a
**Generation 2** VM (UEFI + Secure Boot + vTPM, as Windows 11 requires): unattended install from the
repo answer file, installs Hyper-V Integration Services, applies the W11 optimization pass, cleans
up, runs a Pester gate, then generalizes with Sysprep.

## Ordered action manifest

| # | Action | Why / notes |
|---|--------|-------------|
| 1 | `scripts/windows11-Install_HyperV_Integration.ps1` | Ensures the Hyper-V Integration Services / drivers. |
| 2 | `scripts/windows11-Optimize_W11_25H2.ps1` | Windows 11 25H2 optimization pass. |
| 3 | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 4 | *(stage + Pester)* | Uploads and runs `tests/W11BaseHyperV.Tests.ps1` before sysprep; a failed assertion aborts the build. |
| 5 | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

**Autounattend:** `autounattend/W11/hyperv-gen2/Autounattend-Enterprise.xml` (attached via CD —
Gen2 VMs have no floppy drive).

## Run in a XOAP workspace

1. Vendor the scripts: `pwsh examples/sync-demo-scripts.ps1 -Set w11-base-hyperv`.
2. Upload this set (`alpaka/` + `tests/`) into your XOAP workspace.
3. **Connection:** a **Hyper-V** Connection (target Hyper-V host). Supply the Windows 11 install ISO
   URL and checksum via the `HYPERV_ISO_URL` / `HYPERV_ISO_CHECKSUM` environment variables.
4. **Connector:** a XOAP **Connector** device running on / with access to the Hyper-V host and the
   build VM over WinRM.
5. Start the build; alpaka creates the Gen2 VM from ISO, runs the actions, and exports the result.

## Expected outcome

- A generalized **Windows 11 Enterprise base image** (`w11-base-hyperv`) exported to
  `output-w11-base-hyperv`, ready to import as a template.
- The image passes the in-build Pester gate: Windows 11 SKU, Hyper-V integration service present,
  Sysprep present, and not-yet-generalized state before capture.
