# Demo sets — image builds for a XOAP workspace

Fifteen end-to-end **[alpaka](https://github.com/xoap-io/alpaka) v6.0.0** demo sets, one per
common use case (AVD, Cloud PC, Citrix, plain golden images, and Linux cloud bases). Each set is
a self-contained folder you can upload into a XOAP workspace and build as-is, then adapt.

Every set is the same shape:

```text
<set>/
  alpaka/template.yaml   # the v6 build definition — point the workspace build here
  alpaka/scripts/        # vendored provisioning scripts (git-ignored; filled by the sync helper)
  tests/                 # Pester (Windows) or shell (Linux) validation, staged + run in-build
  README.md              # what it builds, the ordered script manifest, and the run guide
```

The scripts a set runs live once in the repo-root [`scripts/`](../scripts/) tree and are
**vendored** into each set's `alpaka/scripts/` on demand — alpaka resolves script paths inside the
template's own directory, so they must sit next to the template before a build. `alpaka/scripts/`
is git-ignored (build scratch, not source); the sync helper repopulates it.

## The sets

| Set | Target platform | Use case |
|---|---|---|
| [w11-avd](w11-avd/) | `azure-arm` + Compute Gallery | Windows 11 multi-session AVD session host (FSLogix, Teams-AVD, OneDrive, timezone redirection, VDOT-aligned optimization) |
| [w11-cloudpc](w11-cloudpc/) | `azure-arm` (Gen2) | Windows 365 Cloud PC custom image (CLOUDPC_SAFE debloat, Cloud PC prep, validation gate; no BitLocker) |
| [w11-citrix-mcs](w11-citrix-mcs/) | `vsphere-iso` | Windows 11 Citrix VDA image for MCS provisioning |
| [w11-citrix-pvs](w11-citrix-pvs/) | `vsphere-iso` | Windows 11 Citrix VDA image tuned for PVS streaming |
| [server2025-citrix](server2025-citrix/) | `vsphere-iso` | Windows Server 2025 Citrix VDA session host |
| [server2025-avd-rdsh](server2025-avd-rdsh/) | `azure-arm` | Windows Server 2025 AVD RDSH (RDSH role + server FSLogix) |
| [server2019-base-vsphere](server2019-base-vsphere/) | `vsphere-iso` | Windows Server 2019 golden base image |
| [server2022-base-vsphere](server2022-base-vsphere/) | `vsphere-iso` | Windows Server 2022 golden base image |
| [server2025-base-cloud](server2025-base-cloud/) | `azure-arm` (+ AWS/GCP doc flavors) | Windows Server 2025 cloud golden base |
| [w11-base-nutanix](w11-base-nutanix/) | `nutanix` | Windows 11 golden base on Nutanix AHV |
| [w11-base-hyperv](w11-base-hyperv/) | `hyperv-iso` (Gen2) | Windows 11 golden base on Hyper-V |
| [w11-base-xenserver](w11-base-xenserver/) | `xenserver` | Windows 11 golden base on XenServer/XCP-ng |
| [ubuntu-cloud-base](ubuntu-cloud-base/) | `azure-arm` (Linux) | Ubuntu cloud golden base (shell provisioning + validation) |
| [rhel-cloud-base](rhel-cloud-base/) | `azure-arm` (Linux) | RHEL cloud golden base |
| [suse-cloud-base](suse-cloud-base/) | `azure-arm` (Linux) | SUSE cloud golden base |

The Windows sets build on the answer files under [../autounattend/](../autounattend/)
(vSphere/Nutanix/Hyper-V-Gen2/XenServer flavors) and the scripts under [../scripts/](../scripts/);
the Linux sets use the `{ubuntu,rhel,suse}` shell scripts under [../scripts/](../scripts/). All
scripts follow [../docs/SCRIPT_CONTRACT.md](../docs/SCRIPT_CONTRACT.md).

## Run in a XOAP workspace

XOAP runs an alpaka build with three pieces of workspace state — know these before you start:

- **Connection** — stored cloud/hypervisor credentials (an Azure service principal, an AWS key,
  vSphere/Nutanix/XenServer host creds). Selected per build; alpaka reads them as environment
  variables (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, …). *This is XOAP's "Connection", distinct
  from the alpaka template's own `connection:` block, which is the WinRM/SSH transport to the
  build VM.*
- **Connector** — the device that actually executes the build (it must reach the target platform's
  API and the build VM).
- **Target platform** — where the image is built and published, declared in the template's
  `target_platforms:` block.

### Steps

1. **Provision the workspace prerequisites** the set's own README lists — for Azure sets that's an
   Azure Connection plus accepting any marketplace terms; for vSphere/Nutanix/Hyper-V/XenServer,
   the host Connection and a reachable Connector; for the ISO sets, the install media the answer
   file expects.
2. **Vendor the scripts** from the repo root:

   ```bash
   pwsh examples/sync-demo-scripts.ps1 -Set <set>     # e.g. w11-avd; omit -Set to do all 15
   ```

   This copies each script the template references from `scripts/` into
   `examples/<set>/alpaka/scripts/`. It reports `copied`/`missing` and exits non-zero if any
   referenced script is missing.
3. **Upload the set folder** (`alpaka/template.yaml`, the populated `alpaka/scripts/`, and `tests/`)
   into the workspace and point the build at `alpaka/template.yaml`.
4. **Set the build-time variables** the set's README documents (share paths, image names, region,
   installer locations). Cloud credentials come from the selected Connection, not the template.
5. **Build.** Each set stages its `tests/` into the image and runs them **before** capture — a
   failed assertion aborts the build so a bad image is never published. The set README's *Expected
   outcome* says what you get (a Compute Gallery version, a vSphere template, etc.) and how to
   consume it (attach to a host pool, a Cloud PC provisioning policy, a Citrix catalog, …).

### Validate a template locally first (optional)

From a checkout of the [alpaka](https://github.com/xoap-io/alpaka) repo:

```bash
alpaka validate <path>/examples/<set>/alpaka/template.yaml
# or without a built binary:
dotnet run --project src/Alpaka.CLI -- validate <path>/examples/<set>/alpaka/template.yaml
```

## Notes

- These target alpaka **v6.0.0** taxonomy (`target_platforms:`, `connection:`, `post_build:`). If
  you are still on Packer or migrating, see [../docs/ALPAKA_TRANSITION.md](../docs/ALPAKA_TRANSITION.md)
  — including the v6 `alpaka import` Packer→Alpaka converter.
- **Trusted Launch / TPM on azure-arm:** the plugin does not set a VM SecurityProfile today, so the
  Azure Windows sets build a standard Gen2 VM. Each affected README flags this as a plugin gap to
  confirm, not a template error.
- The build credentials shown in the templates' `variables:` blocks (WinRM/SSH usernames and
  passwords) are throwaway values used only for the transient build VM — rotate/replace them for
  anything beyond a demo.
