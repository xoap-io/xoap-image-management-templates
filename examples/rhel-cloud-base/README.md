# RHEL — hardened cloud base image

Builds a hardened Red Hat Enterprise Linux 9 **cloud base image**: updates the system,
installs common packages, configures time sync (chronyd), hardens SSH, hardens the host
firewall (firewalld), applies the target cloud's guest configuration, runs the
optimization pass, validates with a staged shell script (a non-zero exit aborts the
build), and cleans up (dnf). There is **no Sysprep** step — Linux images are generalized
differently (see below).

The [`alpaka/template.yaml`](alpaka/template.yaml) targets **azure-arm** (RHEL 9, Gen2)
and outputs a **managed image** plus a **Compute Gallery** image version. AWS/GCP swaps
are noted below.

## Ordered action manifest (Azure)

| # | Action | Script / type | Why / notes |
|---|---|---|---|
| 1 | update-system | `scripts/rhel/rhel-update_system.sh` | Update packages first. |
| 2 | install-common-packages | `scripts/rhel/rhel-install_common_packages.sh` | Baseline packages/tooling. |
| 3 | configure-chronyd | `scripts/rhel/rhel-configure_chronyd.sh` | Time synchronization (chronyd). |
| 4 | ssh-hardening | `scripts/rhel/rhel-ssh_hardening.sh` | SSH daemon hardening. |
| 5 | firewalld-hardening | `scripts/rhel/rhel-firewalld_hardening.sh` | Host firewall hardening (firewalld). |
| 6 | cloud-configure | `scripts/rhel/rhel-azure_configure.sh` | Cloud guest configuration (Azure). |
| 7 | optimize | `scripts/rhel/rhel-optimize.sh` | Optimization pass. |
| 8 | stage-tests + validate | `tests/rhel-validate.sh` | Asserts SSH/firewalld/chronyd/waagent; failure aborts the build. |
| 9 | cleanup | `scripts/rhel/rhel-cleanup_dnf.sh` | Reclaim space (dnf cache/artifacts). |

### Cloud swap

Step 6 defaults to **Azure** (`scripts/rhel/rhel-azure_configure.sh`). For other clouds,
change the target platform `type:` and swap step 6:

| Flavor | Target `type:` | Cloud configure (step 6) |
|---|---|---|
| **Azure** (default) | `azure-arm` | `scripts/rhel-azure_configure.sh` |
| **AWS** | `amazon-ebs` | `scripts/rhel-aws_configure.sh` |
| **GCP** | `googlecompute` | `scripts/rhel-gcp_configure.sh` |

### Ordering constraints

- **Update first, cleanup last.** Run `rhel-update_system.sh` before installing packages,
  and `rhel-cleanup_dnf.sh` as the final step so it removes caches/artifacts left by
  earlier steps.
- **Hardening before cloud configure.** SSH/firewalld hardening (steps 4-5) run before the
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
  pwsh examples/sync-demo-scripts.ps1 -Set rhel-cloud-base
  alpaka build examples/rhel-cloud-base/alpaka/template.yaml
  ```

## Expected outcome

- A temporary VM boots from the RHEL 9 marketplace image; actions 1-7 run over SSH, then
  `rhel-validate.sh` asserts the hardening/agents are in place.
- On success alpaka captures the managed image `rhel-cloud-base-golden` into
  `alpaka-images-rg` and publishes gallery image `rhel-9-base` version `1.0.0` in
  `alpakaImageGallery`, plus the `rhel-cloud-base-azure-manifest.json` manifest.
- If any provisioning step or a validation assertion fails, the build aborts and **no**
  image is captured.
