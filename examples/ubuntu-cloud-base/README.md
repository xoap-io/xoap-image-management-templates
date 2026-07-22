# Ubuntu — hardened cloud base image

Builds a hardened Ubuntu 24.04 LTS **cloud base image**: updates the system, installs
common packages, configures time sync (chrony), hardens SSH and the kernel (sysctl),
applies the target cloud's guest configuration, runs the optimization pass, validates
with a staged shell script (a non-zero exit aborts the build), and cleans up. There is
**no Sysprep** step — Linux images are generalized differently (see below).

The [`alpaka/template.yaml`](alpaka/template.yaml) targets **azure-arm** (Canonical Ubuntu
24.04 LTS) and outputs a **managed image** plus a **Compute Gallery** image version
replicated westeurope -> northeurope. AWS/GCP swaps are noted below.

## Ordered action manifest (Azure)

| # | Action | Script / type | Why / notes |
|---|---|---|---|
| 1 | update-system | `scripts/ubuntu/ubuntu-update_system.sh` | Update package index + upgrade first. |
| 2 | install-common-packages | `scripts/ubuntu/ubuntu-install_common_packages.sh` | Baseline packages/tooling. |
| 3 | configure-chrony | `scripts/ubuntu/ubuntu-configure_chrony.sh` | Time synchronization (chrony). |
| 4 | ssh-hardening | `scripts/ubuntu/ubuntu-ssh_hardening.sh` | SSH daemon hardening. |
| 5 | sysctl-hardening | `scripts/ubuntu/ubuntu-sysctl_hardening.sh` | Kernel/network `sysctl` hardening. |
| 6 | cloud-configure | `scripts/ubuntu/ubuntu-azure_configure.sh` | Cloud guest configuration (Azure). |
| 7 | optimize | `scripts/ubuntu/ubuntu-optimize.sh` | Optimization pass. |
| 8 | stage-tests + validate | `tests/ubuntu-validate.sh` | Asserts SSH/sysctl/chrony/waagent; failure aborts the build. |
| 9 | cleanup | `scripts/ubuntu/ubuntu-cleanup.sh` | Reclaim space / reset cloud-init. |

### Cloud swap

Step 6 defaults to **Azure** (`scripts/ubuntu/ubuntu-azure_configure.sh`). For other
clouds, change the target platform `type:` and swap step 6:

| Flavor | Target `type:` | Cloud configure (step 6) |
|---|---|---|
| **Azure** (default) | `azure-arm` | `scripts/ubuntu-azure_configure.sh` |
| **AWS** | `amazon-ebs` | `scripts/ubuntu-aws_configure.sh` |
| **GCP** | `googlecompute` | `scripts/ubuntu-gcp_configure.sh` |

### Ordering constraints

- **Update first, cleanup last.** Run `ubuntu-update_system.sh` before installing packages,
  and `ubuntu-cleanup.sh` as the final step so it removes caches/artifacts left by earlier
  steps.
- **Hardening before cloud configure.** SSH/sysctl hardening (steps 4-5) run before the
  cloud guest configuration (step 6) so cloud-specific settings are not overwritten.
- **Validate before cleanup.** The staged validation (step 8) runs before cleanup so a
  non-compliant image is never captured.

### Generalize (no Sysprep)

There is no Windows-style Sysprep for Linux. The image is generalized via **cloud-init /
waagent**: before capture, run `waagent -deprovision+user` (or `cloud-init clean --logs`,
truncate `/etc/machine-id`, and remove persistent SSH host keys) so each instance
provisioned from the image regenerates its own identity on first boot. The azure-arm
builder performs the Azure generalize/deprovision as part of capture.

## Run in a XOAP workspace

- **Connection** — an **Azure** Connection (service principal) supplying `AZURE_CLIENT_ID`
  / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID`. Use an AWS or GCP
  Connection for those flavors.
- **Connector** — a Connector (device/agent) able to reach Azure Resource Manager; the
  build runs natively in Azure (temporary VM + temporary resource group) over SSH, so no
  large image upload leaves the Connector.
- Vendor the referenced scripts, then build:

  ```bash
  pwsh examples/sync-demo-scripts.ps1 -Set ubuntu-cloud-base
  alpaka build examples/ubuntu-cloud-base/alpaka/template.yaml
  ```

## Expected outcome

- A temporary VM boots from the Ubuntu 24.04 marketplace image; actions 1-7 run over SSH,
  then `ubuntu-validate.sh` asserts the hardening/agents are in place.
- On success alpaka captures the managed image `ubuntu-cloud-base-golden` into
  `alpaka-images-rg` and publishes gallery image `ubuntu-2404-base` version `1.0.0` in
  `alpakaImageGallery`, replicated westeurope -> northeurope, plus the
  `ubuntu-cloud-base-azure-manifest.json` manifest.
- If any provisioning step or a validation assertion fails, the build aborts and **no**
  image is captured.
