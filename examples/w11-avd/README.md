# Windows 11 multi-session — Azure Virtual Desktop session host

Builds a **Windows 11 24H2 Enterprise multi-session** AVD session-host image with FSLogix
profile containers, the new Teams + WebRTC redirector, per-machine OneDrive, timezone
redirection, and a VDOT-aligned optimization pass — then validates it with Pester and
publishes a versioned image into an **Azure Compute Gallery**.

This is an [alpaka](https://github.com/xoap-io/alpaka) **v6.0.0** demo set. It targets
`azure-arm`: alpaka spins up a temporary VM from the Windows 11 marketplace image, runs the
actions over WinRM, generalizes with Sysprep, captures a managed image, and creates a new
Compute Gallery image version.

> **Trusted Launch / TPM caveat:** the azure-arm plugin does not set a VM SecurityProfile, so
> this set builds a **standard Gen2** VM (`win11-24h2-ent`). Trusted Launch/TPM cannot be
> asserted by the plugin today — treat that as a plugin gap to confirm, not a template error.

## Ordered script manifest

Scripts are vendored into `alpaka/scripts/` by the sync helper and referenced by basename.
Native typed actions (`windows-update`, `winget`, `file`) need no script.

| # | Action | Script / type | Why / notes |
|---|--------|---------------|-------------|
| 1 | `patch` | `windows-update` (typed) | Patch first. |
| 2 | `install-fslogix` | `scripts/windows11-Install_FSLogix.ps1` | FSLogix agent + profile-container registry. Set `FSLOGIX_VHD_LOCATIONS` to your share, or configure post-deploy. |
| 3 | `install-teams-avd` | `scripts/windows11-Install_Teams_AVD.ps1` | Sets `IsWVDEnvironment=1`, installs WebRTC redirector + new Teams machine-wide. |
| 4 | `install-onedrive-permachine` | `scripts/windows11-Install_OneDrive_PerMachine.ps1` | Per-machine OneDrive (AVD needs this; do **not** use the OneDrive/Teams *removal* script here). |
| 5 | `timezone-redirection` | `scripts/windows11-Configure_Timezone_Redirection.ps1` | Enables time-zone redirection for the session host. |
| 6 | `avd-optimizations` | `scripts/windows11-Configure_AVD_Optimizations.ps1` | VDOT-aligned services/tasks/registry pass; detects multi-session SKU. |
| 7 | `browsers` | `winget` (typed) | Microsoft Edge. |
| 8 | `stage-tests` | `file` (typed) | Uploads `tests/W11-AVD.Tests.ps1` to `C:\Alpaka\Tests`. |
| 9 | `pester-validate` | inline PowerShell | Runs Pester 5; **throws (fails the build)** on any failed assertion, before capture. |
| 10 | `cleanup` | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 11 | `sysprep-generalize` | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

The build finishes with a `manifest` post-build step (`w11-avd-manifest.json`).

### Ordering constraints

- FSLogix/Teams/OneDrive install **before** the optimization pass so the optimizer sees the
  final service set.
- Do **not** run a Defender-disable script before the optimization pass; `Configure_AVD_Optimizations`
  intentionally leaves Defender alone.
- Pester validation runs **before** cleanup/sysprep so a bad image is never captured.

## Run in a XOAP workspace

Prerequisites in the workspace:

1. An Azure **Connection** (cloud credential holding the target **subscription / client ID /
   client secret / tenant ID**) selected for the build. alpaka reads these as the
   `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID`
   environment variables.
2. A **Connector** device assigned to execute the build.
3. Accept the Windows 11 marketplace terms once for the subscription.

Then, from the repo root:

```bash
pwsh examples/sync-demo-scripts.ps1 -Set w11-avd
```

This vendors the referenced scripts into `examples/w11-avd/alpaka/scripts/`. Upload the
`examples/w11-avd/` set (template, `scripts/`, and `tests/`) and point the workspace build at
`alpaka/template.yaml`.

### Build-time environment variables

| Variable | Purpose |
|----------|---------|
| `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` | Azure cloud credentials (supplied by the selected Connection). |
| `FSLOGIX_VHD_LOCATIONS` | UNC path to the FSLogix profile share, e.g. `\\storage.file.core.windows.net\profiles`. May be left empty and set post-deploy via GPO/Intune. |

Gallery/image names, region, and VM size are set in the template's `variables:` block
(`gallery_name`, `images_rg`, `image_version`, `location`, `vm_size`).

## Expected outcome

- A **versioned image** (`windows-11-avd`, version `1.0.0`) published in the named Azure
  Compute Gallery (`alpakaImageGallery`), replicated to `westeurope`, plus a retained managed
  image in `alpaka-images-rg`.
- Attach the gallery image version to a **Windows 11 Enterprise multi-session** host pool as
  the session-host image.
- FSLogix `VHDLocations` must point at your profile share (set `FSLOGIX_VHD_LOCATIONS` at build
  time, or via GPO/Intune after deployment).
