# Windows 11 — Windows 365 CloudPC custom image

Builds a supported **Windows 365 CloudPC** custom image: patches the OS, removes built-in apps
while keeping the Windows 365-required inbox apps, applies the CloudPC preparation pass,
validates the image against CloudPC requirements as a build gate, cleans up, and generalizes
with Sysprep — then publishes a versioned **Gen2** image into an **Azure Compute Gallery** that
is selectable as a Windows 365 custom image.

This is an [alpaka](https://github.com/xoap-io/alpaka) **v6.0.0** demo set. It targets
`azure-arm`: alpaka spins up a temporary VM from the Windows 11 marketplace image, runs the
actions over WinRM, generalizes with Sysprep, captures a managed image, and creates a new
Compute Gallery image version.

> **Gen2 + Trusted Launch/TPM caveat:** Windows 365 custom images must be **Gen2**, so this set
> uses `win11-24h2-ent`. The azure-arm plugin does not set a VM SecurityProfile, so the VM is
> built with standard security — Trusted Launch/TPM cannot be asserted by the plugin today;
> treat that as a plugin gap to confirm, not a template error.

## Ordered script manifest

Scripts are vendored into `alpaka/scripts/` by the sync helper and referenced by basename.
Native typed actions (`windows-update`, `file`) need no script.

| # | Action | Script / type | Why / notes |
|---|--------|---------------|-------------|
| 1 | `patch` | `windows-update` (typed) | Patch first. |
| 2 | `remove-apps-cloudpc-safe` | `scripts/windows11-W11_24H2_Remove_Apps.ps1` | Debloat with `CLOUDPC_SAFE=1` so the Windows 365-required inbox apps and Store dependencies are **kept**. |
| 3 | `prepare-cloudpc` | `scripts/windows11-Prepare_CloudPC.ps1` | CloudPC-specific image preparation. |
| 4 | `stage-tests` | `file` (typed) | Uploads `tests/W11-CloudPC.Tests.ps1` to `C:\Alpaka\Tests`. |
| 5 | `pester-validate` | inline PowerShell | Runs Pester 5; **throws (fails the build)** on any failed assertion, before capture. |
| 6 | `cleanup` | `scripts/windows11-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 7 | `validate-cloudpc-image` | `scripts/windows11-Validate_CloudPC_Image.ps1` | **Gate, LAST before sysprep:** validates the fully-provisioned image against CloudPC hard requirements; exits non-zero (fails the build) on any violation. Set `CLOUDPC_FAILFAST=1` to stop at the first violation. |
| 8 | `sysprep-generalize` | `scripts/windows-server-Invoke_Sysprep.ps1` (VMMode) | Generalize for capture (`/generalize /oobe /mode:vm`). |

The build finishes with a `manifest` post-build step (`w11-cloudpc-manifest.json`).

### Ordering constraints

- **Do NOT add `windows11-Enable_Bitlocker.ps1`.** Windows 365 forbids BitLocker in the custom
  image (CloudPC manages disk encryption itself); a BitLocker-encrypted image is rejected. It is
  intentionally absent, and the Pester test asserts BitLocker is **OFF**.
- **Keep required inbox apps.** `CLOUDPC_SAFE=1` on step 2 preserves the Windows 365-required
  inbox apps and their Store dependencies — do not debloat without it.
- **Validate as the last gate.** `validate-cloudpc-image` runs **after** debloat, prep, and
  cleanup, and is the last action before sysprep, so it inspects the final image.

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
pwsh examples/sync-demo-scripts.ps1 -Set w11-cloudpc
```

This vendors the referenced scripts into `examples/w11-cloudpc/alpaka/scripts/`. Upload the
`examples/w11-cloudpc/` set (template, `scripts/`, and `tests/`) and point the workspace build
at `alpaka/template.yaml`.

### Build-time environment variables

| Variable | Purpose |
|----------|---------|
| `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` | Azure cloud credentials (supplied by the selected Connection). |

Debloat/validation behaviour and gallery/image naming are set in the template's `variables:`
block (`cloudpc_safe`, `cloudpc_failfast`, `gallery_name`, `images_rg`, `image_version`,
`location`, `vm_size`).

## Expected outcome

- A **versioned Gen2 image** (`windows-11-cloudpc`, version `1.0.0`) published in the named
  Azure Compute Gallery (`alpakaImageGallery`), replicated to `westeurope`, plus a retained
  managed image in `alpaka-images-rg`.
- The Gen2 gallery image version is **selectable as a Windows 365 custom image** — reference it
  from a CloudPC provisioning policy.
- Do not enable BitLocker on the image itself; CloudPC handles encryption.
