# Packer -> alpaka Transition

This repository supports **Packer today** and is being migrated **mid-term to
[alpaka](https://github.com/xoap-io/alpaka)**, the in-house .NET image builder that is
the successor to XOAP Image Management. The goal of this document is a **dual-support**
posture: the same provisioning scripts and answer files drive both builders during the
transition, so nothing has to be rewritten twice.

## Why dual-support is cheap here

Packer and alpaka invoke a script almost identically:

| Concern | Packer | alpaka |
|---|---|---|
| Upload + run | uploads to `C:\Windows\Temp`, runs `powershell -ExecutionPolicy Bypass` | uploads to `C:\Windows\Temp\alpaka_ps_<guid>.ps1`, runs the same command |
| Success/failure | `valid_exit_codes` (default `[0]`) | `valid_exit_codes` (default `[0]`) |
| Log channel | provisioner stdout -> build log | script stdout -> live (SignalR) build log |
| Parameters | env vars (`environment_vars`) | env vars (`environment:`) — no PowerShell params |

Because both judge a script purely by its **exit code** and surface its **stdout**, a
script that follows [SCRIPT_CONTRACT.md](SCRIPT_CONTRACT.md) drops into either builder
unchanged. There is no structured-event contract to target — stdout + exit code is it.

## alpaka template shape (v2.0, v6 taxonomy)

alpaka templates are YAML (`docs/TEMPLATE_FORMAT_V2.md` in the alpaka repo).

> **alpaka 6.0.0 renamed the template taxonomy with no back-compat aliases:**
> `platform_targets:` -> `target_platforms:` (Target platform),
> `post_conversions:`/`post_conversions_nested:` -> `post_build:`/`post_build_nested:` (Post-build),
> and `connector:`/`connector_profiles:` -> `connection:`/`connection_profiles:` (Connection).
> Everything below uses the v6 keys; templates written for <=5.x must be migrated.

```yaml
version: "2.0"
variables:
  vhd_locations: ""
target_platforms:
  - type: vsphere-iso            # from alpaka-plugin-vsphere
    # ... builder settings ...
actions:
  - type: powershell
    script: "./scripts/windows11-Install_FSLogix.ps1"
    environment:
      FSLOGIX_VHD_LOCATIONS: "{{ vhd_locations }}"
  - type: winget                 # typed action replaces a per-app install script
    packages: [Google.Chrome, 7zip.7zip]
  - type: windows-restart
post_build:
  - type: ...
```

Key rules that shape how this repo's assets map in:

- **In-tree paths only.** `extends`/`imports`/`bundles` and script references must resolve
  **inside the template's own directory** — no `../` escapes. So an alpaka template must
  have the scripts it calls at or below its own folder (see the demo sets under
  `examples/*/alpaka/`, which vendor/sync the scripts they use).
- **`{{ }}` is reserved** — alpaka interpolates `{{identifier}}` inside script content, so
  scripts must not contain literal double-brace sequences (already covered by the contract).
- **Typed actions** can replace whole script categories (see mapping table below); prefer
  them over porting a script when alpaka offers a native action.

## Mapping this repo's scripts to alpaka actions

Port genuinely custom logic as `powershell`/`shell` `script:` actions; replace the rote
categories with alpaka's typed actions:

| This repo | alpaka action | Notes |
|---|---|---|
| `scripts/applications/winget/Install_*_Winget.ps1` | `winget` | one action, `packages:` list — the per-app scripts become a few lines |
| `scripts/applications/chocolatey/Install_*_Chocolatey.ps1` | `chocolatey` | as above |
| `windows-server-Install_Windows_Updates.ps1` | `windows-update` | native update action |
| `windows-server-Manage_Windows_Features.ps1`, `Install_RDSH_Role.ps1` | `windows-feature` | feature install/remove |
| registry-tweak scripts (`Configure_Registry_Optimizations`, timezone redirection, etc.) | `registry` | for simple key writes; keep a script when logic is conditional |
| `*Restart*` / reboot points | `windows-restart` | |
| `windows-server-Invoke_Sysprep.ps1` | `powershell` `script:` action | keep as a script (parameterized via env) |
| guest-tools installers, FSLogix, Teams-AVD, Citrix VDA, CloudPC prep/validate, optimization passes | `powershell` `script:` actions | genuinely custom -> stay scripts |
| Linux `scripts/{rhel,suse,ubuntu}/*.sh` | `shell` `script:` actions | |
| `autounattend/**/*.xml` | target-platform answer-file input | the 114-file hypervisor library is a natural upstream contribution to `alpaka-resources` |

## Migration steps (incremental)

1. **Now:** keep `scripts/` as the single source of truth. Packer consumes them directly;
   the demo sets (`examples/*/`) carry both a Packer var-file and an alpaka `template.yaml`.
2. Bring every script to [SCRIPT_CONTRACT.md](SCRIPT_CONTRACT.md) (done for new scripts;
   ongoing for legacy ones).
3. Author alpaka scenarios per use case (mirroring
   `alpaka-resources/examples/scenarios/avd-session-host-win11.yaml` and
   `citrix-session-host-win11.yaml`) — the demo sets in `examples/` are the seed.
4. Replace rote install/update/feature/registry scripts with typed actions in the alpaka
   templates; keep the custom scripts.
5. **Upstream** the polished, generic scripts and the autounattend library to
   `alpaka-resources/examples/` following its conventions (kebab-case script names, a
   folder `README.md`, stdout logging). Note `alpaka-resources` CI validates YAML only, so
   carry this repo's `tests/` Pester harness alongside any scripts contributed there.
6. For any remaining Packer HCL, use alpaka's built-in **Packer -> Alpaka importer**
   (new in v6: full HCL2/JSON parsing, rewrites Packer variables to the native
   `{{ x }}` interpolation): `alpaka import <template.pkr.hcl>` — then review the
   emitted YAML against the v6 taxonomy and validate.
7. When alpaka reaches parity for a use case, switch that image's pipeline to alpaka and
   retire the corresponding Packer variant.

## Validating alpaka templates

From a checkout of the alpaka repo:

```bash
alpaka validate examples/**/alpaka/template.yaml
# or, without a built binary:
dotnet run --project src/Alpaka.CLI -- validate <template.yaml>
```
