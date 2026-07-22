# Windows Server 2025 — AVD / RDSH multi-session host

Builds a Windows Server 2025 **Remote Desktop Session Host (RDSH)** golden image on **azure-arm**
and publishes it as a managed image **plus a new Azure Compute Gallery version**, ready to back a
Server 2025 multi-session **Azure Virtual Desktop** host pool. The build patches the OS, installs
the RD Session Host role, installs the FSLogix profile-container agent, applies the server
optimization pass, cleans up, runs a Pester gate, and generalizes with Sysprep for capture.

> Uses a **standard Gen2 SKU** (`2025-datacenter-azure-edition`). The azure-arm plugin does not set
> a VM SecurityProfile, so this template does **not** rely on Trusted Launch.

## Ordered action manifest

| # | Action | Why / notes |
|---|--------|-------------|
| 1 | `windows-update` | Patch first. |
| 2 | `scripts/windows-server-Install_RDSH_Role.ps1` | Installs the `RDS-RD-Server` role. Exits **3010** when a reboot is required (`valid_exit_codes: [0, 3010]`). |
| 3 | *(windows-restart)* | Reboot to complete the RDSH role install. |
| 4 | `scripts/windows-server-Install_FSLogix.ps1` | Installs the FSLogix Apps agent + profile-container config. Set `FSLOGIX_VHD_LOCATIONS` (variable) to your share, or configure post-deploy. |
| 5 | `scripts/windows-server-Optimize_System.ps1` | Server optimization pass (services/tasks/registry). |
| 6 | `scripts/windows-server-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 7 | *(stage + Pester)* | Uploads and runs `tests/ServerAvdRdsh.Tests.ps1` before sysprep; a failed assertion aborts the build. |
| 8 | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

### Ordering constraints

- **RDSH role before optimization.** Install the role (step 2) and reboot (step 3) before the
  optimization pass so the optimizer sees the final role/service set.
- **Pester before sysprep.** The gate must run before the machine is generalized/shut down.

## Run in a XOAP workspace

1. Vendor the scripts: `pwsh examples/sync-demo-scripts.ps1 -Set server2025-avd-rdsh`.
2. Upload this set (`alpaka/` + `tests/`) into your XOAP workspace.
3. **Connection:** an **Azure** Connection (service principal — client id/secret, tenant,
   subscription) targeting the subscription and `alpaka-images-rg`.
4. **Connector:** a XOAP **Connector** device with outbound access to Azure Resource Manager that
   runs the build.
5. Start the build; alpaka provisions a temp Gen2 VM, runs the actions, and captures the result.

## Expected outcome

- A generalized **managed image** `server2025-avd-rdsh-golden` in `alpaka-images-rg`.
- A **new Azure Compute Gallery version** `1.0.0` of image `server2025-avd-rdsh` in
  `alpakaImageGallery`, replicated in `westeurope`.
- The image has the `RDS-RD-Server` role and the FSLogix agent installed (asserted by the in-build
  Pester gate) and is ready to assign to a **Server 2025 multi-session AVD host pool**.
- Configure FSLogix `VHDLocations` (set `fslogix_vhd_locations` at build time, or via GPO/Intune
  post-deploy) to point profile containers at your share.
