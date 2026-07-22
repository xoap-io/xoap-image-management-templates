# Windows 11 Enterprise — Nutanix AHV base golden image

Builds a clean **Windows 11 Enterprise** base golden image on **Nutanix AHV** via Prism Central:
unattended install from the repo answer file, installs the Nutanix Guest Tools, applies the W11
optimization pass, cleans up, runs a Pester gate, then generalizes with Sysprep.

## Ordered action manifest

| # | Action | Why / notes |
|---|--------|-------------|
| 1 | `scripts/windows11-Install_Nutanix_Tools.ps1` | Installs the Nutanix Guest Tools (NGT). |
| 2 | `scripts/windows11-Optimize_W11_25H2.ps1` | Windows 11 25H2 optimization pass. |
| 3 | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 4 | *(stage + Pester)* | Uploads and runs `tests/W11BaseNutanix.Tests.ps1` before sysprep; a failed assertion aborts the build. |
| 5 | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

**Autounattend:** `autounattend/W11/nutanix/Autounattend-Enterprise.xml` (attached via CD).

## Run in a XOAP workspace

1. Vendor the scripts: `pwsh examples/sync-demo-scripts.ps1 -Set w11-base-nutanix`.
2. Upload this set (`alpaka/` + `tests/`) into your XOAP workspace.
3. **Connection:** a **Nutanix (Prism Central)** Connection (endpoint + credentials, target
   cluster). Register the Windows 11 install ISO in Prism and supply its name / subnet via the
   `NUTANIX_ISO_IMAGE` / `NUTANIX_SUBNET` environment variables.
4. **Connector:** a XOAP **Connector** device that can reach Prism Central and the build VM over
   WinRM.
5. Start the build; alpaka creates the VM, runs the actions, and registers the result as an image.

## Expected outcome

- A generalized **Windows 11 Enterprise base image** (`w11-base-<timestamp>`) registered in
  Nutanix, ready to clone/deploy.
- The image passes the in-build Pester gate: Windows 11 SKU, Nutanix Guest Tools present, Sysprep
  present, and not-yet-generalized state before capture.
