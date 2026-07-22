# SUSE — hardened cloud base image

Builds a hardened SUSE Linux Enterprise Server 15 **cloud base image**: updates the
system, installs common packages, configures time sync (chronyd), hardens SSH, hardens
the kernel (sysctl) and the host firewall (firewalld), applies the target cloud's guest
configuration, runs the optimization pass, validates with a staged shell script (a
non-zero exit aborts the build), and cleans up. There is **no Sysprep** step — Linux
images are generalized differently (see below).

The [`alpaka/template.yaml`](alpaka/template.yaml) targets **azure-arm** (SLES 15 SP5,
Gen2) and outputs a **managed image** plus a **Compute Gallery** image version. AWS/GCP
swaps are noted below.

## Ordered action manifest (Azure)

| # | Action | Script / type | Why / notes |
|---|---|---|---|
| 1 | update-system | `scripts/suse/suse-update_system.sh` | Update packages first. |
| 2 | install-common-packages | `scripts/suse/suse-install_common_packages.sh` | Baseline packages/tooling. |
| 3 | configure-chronyd | `scripts/suse/suse-configure_chronyd.sh` | Time synchronization (chronyd). |
| 4 | ssh-hardening | `scripts/suse/suse-ssh_hardening.sh` | SSH daemon hardening. |
| 5 | sysctl-hardening | `scripts/suse/suse-sysctl_hardening.sh` | Kernel/network `sysctl` hardening. |
| 6 | firewalld-hardening | `scripts/suse/suse-firewalld_hardening.sh` | Host firewall hardening (firewalld). |
| 7 | cloud-configure | `scripts/suse/suse-azure_configure.sh` | Cloud guest configuration (Azure). |
| 8 | optimize | `scripts/suse/suse-optimize.sh` | Optimization pass. |
| 9 | stage-tests + validate | `tests/suse-validate.sh` | Asserts SSH/sysctl/firewalld/chronyd/waagent; failure aborts the build. |
| 10 | cleanup | `scripts/suse/suse-cleanup.sh` | Reclaim space / remove build artifacts. |

### Cloud swap

Step 7 defaults to **Azure** (`scripts/suse/suse-azure_configure.sh`). For other clouds,
change the target platform `type:` and swap step 7:

| Flavor | Target `type:` | Cloud configure (step 7) |
|---|---|---|
| **Azure** (default) | `azure-arm` | `scripts/suse-azure_configure.sh` |
| **AWS** | `amazon-ebs` | `scripts/suse-aws_configure.sh` |
| **GCP** | `googlecompute` | `scripts/suse-gcp_configure.sh` |

### Ordering constraints

- **Update first, cleanup last.** Run `suse-update_system.sh` before installing packages,
  and `suse-cleanup.sh` as the final step so it removes caches/artifacts left by earlier
  steps.
- **Hardening before cloud configure.** SSH/sysctl/firewalld hardening (steps 4-6) run
  before the cloud guest configuration (step 7) so cloud-specific settings are not
  overwritten.
- **Validate before cleanup.** The staged validation (step 9) runs before cleanup so a
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
  pwsh examples/sync-demo-scripts.ps1 -Set suse-cloud-base
  alpaka build examples/suse-cloud-base/alpaka/template.yaml
  ```

## Expected outcome

- A temporary VM boots from the SLES 15 marketplace image; actions 1-8 run over SSH, then
  `suse-validate.sh` asserts the hardening/agents are in place.
- On success alpaka captures the managed image `suse-cloud-base-golden` into
  `alpaka-images-rg` and publishes gallery image `sles-15-base` version `1.0.0` in
  `alpakaImageGallery`, plus the `suse-cloud-base-azure-manifest.json` manifest.
- If any provisioning step or a validation assertion fails, the build aborts and **no**
  image is captured.
