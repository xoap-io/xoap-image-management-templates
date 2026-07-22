# Windows Server 2022 — vSphere base golden image

Builds a clean **Windows Server 2022 Standard** base golden image on **vCenter / vSphere** from the
install ISO: unattended install via the repo answer file, patch, optimize, clean up, a Pester gate,
then generalize with Sysprep and convert to a reusable **vSphere template**.

## Ordered action manifest

| # | Action | Why / notes |
|---|--------|-------------|
| 1 | `windows-update` | Patch first. |
| 2 | `scripts/windows-server-Optimize_System.ps1` | Server optimization pass (services/tasks/registry). |
| 3 | `scripts/windows-server-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 4 | *(stage + Pester)* | Uploads and runs `tests/Server2022Base.Tests.ps1` before sysprep; a failed assertion aborts the build. |
| 5 | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

**Autounattend:** `autounattend/2022/vsphere/Autounattend-Standard.xml` (attached via floppy).

## Run in a XOAP workspace

1. Vendor the scripts: `pwsh examples/sync-demo-scripts.ps1 -Set server2022-base-vsphere`.
2. Upload this set (`alpaka/` + `tests/`) into your XOAP workspace.
3. **Connection:** a **vCenter (vSphere)** Connection (vCenter URL + credentials, target
   datacenter / cluster / datastore). Provide the install ISO path and checksum via the
   `VSPHERE_ISO_PATH` / `VSPHERE_ISO_CHECKSUM` environment variables.
4. **Connector:** a XOAP **Connector** device inside the vSphere network that can reach vCenter and
   the build VM over WinRM.
5. Start the build; alpaka creates the VM from ISO, runs the actions, and converts it to a template.

## Expected outcome

- A generalized, patched **Windows Server 2022 Standard vSphere template** (`server2022-base`) in
  the `Templates` folder, ready to clone for new VMs.
- The image passes the in-build Pester gate: correct OS build (`10.0.20348`), Sysprep present, and
  not-yet-generalized state before capture.
