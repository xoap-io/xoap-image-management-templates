# Windows 11 Enterprise — XenServer base golden image

Builds a clean **Windows 11 Enterprise** base golden image on **XenServer** from the install ISO
(UEFI, as Windows 11 requires): unattended install from the repo answer file, installs the XenServer
Guest Tools, applies the W11 optimization pass, cleans up, runs a Pester gate, then generalizes with
Sysprep and exports as an XVA.

## Ordered action manifest

| # | Action | Why / notes |
|---|--------|-------------|
| 1 | `scripts/Install_XenServer_Guest_Tools.ps1` | Installs the XenServer guest tools / PV drivers. |
| 2 | `scripts/windows11-Optimize_W11_25H2.ps1` | Windows 11 25H2 optimization pass. |
| 3 | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 4 | *(stage + Pester)* | Uploads and runs `tests/W11BaseXenServer.Tests.ps1` before sysprep; a failed assertion aborts the build. |
| 5 | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

**Autounattend:** `autounattend/W11/xenserver/Autounattend-Enterprise.xml` (attached via floppy).

## Run in a XOAP workspace

1. Vendor the scripts: `pwsh examples/sync-demo-scripts.ps1 -Set w11-base-xenserver`.
2. Upload this set (`alpaka/` + `tests/`) into your XOAP workspace.
3. **Connection:** a **XenServer** Connection (host + root credentials, target SR). Supply the
   Windows 11 install ISO URL and checksum via the `XEN_ISO_URL` / `XEN_ISO_CHECKSUM` environment
   variables.
4. **Connector:** a XOAP **Connector** device that can reach the XenServer host (SSH) and the build
   VM.
5. Start the build; alpaka creates the VM from ISO, runs the actions, and exports the result (XVA).

## Expected outcome

- A generalized **Windows 11 Enterprise base image** exported as an **XVA**
  (`output-w11-base-xenserver`), ready to import as a template.
- The image passes the in-build Pester gate: Windows 11 SKU, XenServer guest agent present, Sysprep
  present, and not-yet-generalized state before capture.
