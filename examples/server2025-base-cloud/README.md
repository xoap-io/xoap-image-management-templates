# Windows Server 2025 — cloud base image (Azure / AWS / GCP)

Builds a hardened Windows Server 2025 **cloud base image**: patches the OS, applies CIS
benchmarks, disables legacy SMBv1, installs the cloud provider's guest tools/agents,
runs the cloud-specific performance pass, validates with **Pester** (a failed assertion
aborts the build), cleans up, and generalizes with Sysprep for capture.

The [`alpaka/template.yaml`](alpaka/template.yaml) targets **azure-arm** (Windows Server
2025 Datacenter Azure Edition, Gen2) and outputs both a zone-resilient **managed image**
and a **Compute Gallery** image version. The AWS and GCP flavors are documented below.

> No Trusted Launch: a standard **Gen2** SKU is used (the azure-arm plugin does not rely
> on Trusted Launch).

## Ordered action manifest (Azure)

| # | Action | Script / type | Why / notes |
|---|---|---|---|
| 1 | patch | `windows-update` | Patch first. |
| 2 | apply-cis-benchmarks | `scripts/windows_server/windows-server-Apply_CIS_Benchmarks.ps1` | CIS hardening baseline (UAC, SMB signing, …). |
| 3 | disable-smbv1 | `scripts/windows_server/windows-server-Disable_SMBv1_Legacy.ps1` | Remove the legacy SMBv1 protocol + weak auth. |
| 4 | install-cloud-tools | `scripts/windows_server/azure/Install_Azure_Tools.ps1` | Azure VM guest agent + tools. |
| 5 | optimize-cloud | `scripts/windows_server/azure/Optimize_Azure_Performance.ps1` | Azure performance tuning. |
| 6 | stage-tests + pester-validate | `tests/WindowsServer2025Base.Tests.ps1` | Pester asserts CIS / SMBv1 / tools; failure aborts the build. |
| 7 | cleanup | `scripts/windows_server/windows-server-Cleanup_Temporary_Files.ps1` | Reclaim space. |
| 8 | sysprep-generalize | `scripts/windows_server/windows-server-Invoke_Sysprep.ps1` | Generalize for capture (`/generalize /oobe /mode:vm`); may exit `3010`. |

### Ordering constraints

- **Cloud tools before cloud optimize.** Install the guest agent/tools (step 4) before the
  performance pass (step 5) so the optimizer tunes around the installed agent.
- **Validate before finalize.** Pester (step 6) runs before cleanup/Sysprep so a
  non-compliant image is never captured.
- **Sysprep last.** `Invoke_Sysprep.ps1` may exit `3010`; the action allows it
  (`valid_exit_codes: [0, 3010]`).

## Cloud flavors (AWS / GCP)

All flavors share steps 1-3 and 6-8. Only the **target platform** and the two
cloud-specific actions (4-5) differ:

| Flavor | Target `type:` | Cloud tools (step 4) | Cloud optimize (step 5) |
|---|---|---|---|
| **Azure** (default) | `azure-arm` | `scripts/azure/Install_Azure_Tools.ps1` | `scripts/azure/Optimize_Azure_Performance.ps1` |
| **AWS** | `amazon-ebs` | `scripts/aws/Install_AWS_Tools.ps1` | `scripts/aws/Optimize_AWS_EC2_Performance.ps1` |
| **GCP** | `googlecompute` | `scripts/google/Install_GCP_Tools.ps1` | `scripts/google/Optimize_GCP_Performance.ps1` |

**AWS variant notes.** Replace the `azure-arm` target platform with an `amazon-ebs` block
(`source_ami_filter` / `region` / `instance_type`, output is an AMI instead of a managed
image + gallery version) and swap the two script references above. Sysprep uses the AWS
EC2Launch path.

**GCP variant notes.** Replace the target with a `googlecompute` block (`project_id` /
`source_image_family` / `zone`, output is a GCE image) and swap the two script references.
Sysprep uses the GCEsysprep path.

## Run in a XOAP workspace

- **Connection** — an **Azure** Connection (service principal: tenant, subscription,
  client id/secret) supplying `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` /
  `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID`. For the AWS/GCP flavors use an AWS or GCP
  Connection instead.
- **Connector** — a Connector (device/agent) able to reach Azure Resource Manager; the
  build runs natively in Azure (temporary VM + temporary resource group), so no large
  image upload leaves the Connector.
- Vendor the referenced scripts, then build:

  ```bash
  pwsh examples/sync-demo-scripts.ps1 -Set server2025-base-cloud
  alpaka build examples/server2025-base-cloud/alpaka/template.yaml
  ```

## Expected outcome

- A temporary VM boots from the WS2025 marketplace image; actions 1-5 run over WinRM
  (HTTPS/5986), then Pester validates the image.
- On success alpaka captures the zone-resilient managed image `server2025-base-cloud-golden`
  into `alpaka-images-rg` and publishes gallery image `windows-server-2025-base` version
  `1.0.0` in `alpakaImageGallery`, plus the `server2025-base-cloud-azure-manifest.json`
  manifest.
- If any provisioning step or Pester assertion fails, the build aborts and **no** image
  is captured.
