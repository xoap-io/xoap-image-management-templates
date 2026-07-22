# Provisioning Script Contract

This repository's provisioning scripts are consumed today by **Packer** (PowerShell
and shell provisioners) and, mid-term, by **alpaka** (the in-house .NET image builder).
Both tools invoke a script the same way — upload it to the guest, run it via
`powershell -ExecutionPolicy Bypass` (or a shell), and judge the result **solely by the
process exit code** — so a single contract lets every script serve both without change.

This document is the reference for authoring and reviewing scripts under `scripts/`.

## 1. Exit codes are the contract

- **`exit 0`** — success.
- **`exit 3010`** — success, but a reboot is required. Packer (`valid_exit_codes`) and
  alpaka (`valid_exit_codes`) can both be told to treat this as success; scripts that may
  trigger a reboot should surface `3010` rather than swallowing it.
- **`exit 1`** (or any other non-zero) — failure. The build must stop.
- Never let a native tool's failure pass silently. After `winget`, `choco`, `dism`,
  `reg`, `sysprep`, etc., check `$LASTEXITCODE` and translate it:

  ```powershell
  winget install --id Some.Package --silent --accept-package-agreements --accept-source-agreements -e
  if ($LASTEXITCODE -notin @(0, 3010, -1978335189)) {
      throw "winget install failed (exit code $LASTEXITCODE)"
  }
  ```

- `$ErrorActionPreference = 'Stop'` does **not** catch native-command exit codes in
  Windows PowerShell 5.1 — you must check `$LASTEXITCODE` explicitly.

## 2. stdout is the log channel — uniform state output

Packer streams a provisioner's stdout into the build log; alpaka relays a script's
`StandardOutput` into its live (SignalR) build log. There is **no structured JSON event
contract** — plain stdout is what an operator reads. Every script MUST emit its state the
same way so a build log reads consistently across scripts:

- Log with `Write-Host` (PowerShell) / `echo` (shell), not `Write-Output`.
- **Line format (exact):**

  ```
  [yyyy-MM-dd HH:mm:ss] [LEVEL] [Component] message
  ```

  `LEVEL` is one of `INFO` / `WARN` / `ERROR`. `Component` is a short PascalCase/′kebab
  tag naming the script's subject (e.g. `FSLogix`, `Citrix-VDA`, `Sysprep`, `Cleanup`).
- **ASCII only.** No box-drawing or check/cross glyphs (`✓`, `✗`, `│`, `└`) — they mojibake
  over WinRM/cp437 consoles. Use `[OK]`, `[FAIL]`, `[MISSING]`, `->`.
- **Start banner** (first log line): `===== <ScriptName> starting =====`, optionally with
  key parameters, e.g. `===== Invoke_Sysprep starting (Mode=OOBE, VMMode=True) =====`.
- **Per-change lines:** log each state-changing action as it happens (`INFO` for applied,
  `WARN` for skipped/non-fatal, `ERROR` for failures) — the log is the record of *what
  changed*.
- **End summary** (last log line before exit): a single block reporting outcome and
  elapsed seconds, e.g.
  `===== <ScriptName> complete in 42s; applied=7 skipped=1 failed=0 =====`.
  Maintain simple counters (`$applied`, `$skipped`, `$failed`) as the script runs.
- **Explicit exit:** end success paths with `exit 0` (or `exit 3010` when a reboot is
  required); the error `trap`/`catch` ends with `exit 1`. Do not fall off the end
  implicitly.
### File logging — one uniform mechanism

A local copy of the log is kept **in addition to** stdout, and every script keeps it the
**same way**: a PowerShell transcript to `C:\xoap-logs\<script-basename>-<timestamp>.log`.

- Open it once, near the top, tolerating failure (a read-only or locked disk must not fail
  the build):

  ```powershell
  $LogDir = 'C:\xoap-logs'
  try {
      if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
      $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f `
          [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
      Start-Transcript -Path $script:LogFile -Append | Out-Null
  } catch { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] [<Component>] Transcript unavailable: $($_.Exception.Message)" }
  ```

- `Stop-Transcript` in the `finally`/`trap` and before any `exit` (wrap in
  `try { Stop-Transcript | Out-Null } catch {}`; also stop it right before `sysprep`/reboot
  steps that tear down the session).
- **`Write-Log` does `Write-Host` only.** Do **not** also `Add-Content` to the log file —
  the transcript already captures every host line (and native-command output that
  `Add-Content` would miss). Mixing the two double-writes each line and produces an
  inconsistent file.
- Never log *only* to a file — stdout is the channel Packer/alpaka surface.

## 2a. Timeouts belong to the orchestrator, not the script

A script must **not** implement its own wall-clock execution timeout (no
`Wait-Process -Timeout` / job-with-timeout / `Start-Sleep`-then-kill around its own work).
Bounding how long a step may run is the **orchestrator's** responsibility, configured on
the provisioner/action so it is visible and tunable per build:

- **Packer** — set `timeout` on the `powershell`/`shell` provisioner:

  ```hcl
  provisioner "powershell" {
    scripts = var.provision_scripts
    timeout = "30m"
  }
  ```

- **alpaka** — set `timeout` on the `powershell`/`shell` action:

  ```yaml
  - type: powershell
    script: "scripts/windows11-Install_FSLogix.ps1"
    timeout: "15m"
  ```

The script's only duty is to run to completion, log its state, and return the right exit
code; if it exceeds the configured `timeout`, the orchestrator kills it and fails the step.
(This is why the 60-minute in-script "sleep in the error trap" pattern was removed — it
usurped the orchestrator's job and hung builds.)

**Exception — network calls, not execution.** A short `-TimeoutSec` on `Invoke-RestMethod`
/ `Invoke-WebRequest` to a metadata endpoint (e.g. a 2 s probe of `169.254.169.254` to
detect the cloud platform) is a *request* timeout, not an execution timeout, and is
correct to keep in-script.

## 3. Parameters: defaults + environment overrides

alpaka's `script:` invocation does **not** pass PowerShell parameters — it can only inject
**environment variables**. Packer behaves the same way (`environment_vars`). So:

- Give every `param()` a sane default so the script runs correctly with no arguments.
- Allow environment-variable overrides for anything configurable, e.g.
  `[string]$FslogixVersion = $env:FSLOGIX_VERSION ?? '2.9.8884.27471'`.
- Do not rely on positional arguments.

## 4. `{{ }}` is reserved

alpaka interpolates `{{identifier}}` sequences **inside script content** before upload.
Never write a literal `{{name}}` in a script (rare in PowerShell, but possible in format
strings and here-strings). Treat double braces as reserved.

## 5. Secrets

- Never echo secrets to stdout. alpaka masks declared `sensitive_variables` engine-side,
  but only values it knows; keep the discipline in-script.
- Build-time credentials (the `xoap-admin` build account, certificate import passwords)
  are throwaway — the image is generalized with Sysprep afterwards — but still must not be
  printed.

## 6. Robustness baseline (PowerShell)

Every PowerShell provisioning script should open with:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # avoids WinRM progress-stream noise
```

and be **idempotent** (safe to re-run), **non-interactive** (no prompts), and fail fast.
Error traps must `exit 1` immediately — never `Start-Sleep` to "allow investigation",
which hangs unattended builds.

## 7. Robustness baseline (shell)

Every `.sh` provisioning script should open with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

log with a leveled `echo` matching the format above, and return a non-zero exit on failure.

## 8. Header (comment-based help)

Every PowerShell script carries comment-based help with at least `.SYNOPSIS`,
`.DESCRIPTION`, `.COMPONENT`, and a `.LINK` to
`https://github.com/xoap-io/xoap-image-management-templates`.

---

Scripts that follow this contract drop unchanged into a Packer `powershell`/`shell`
provisioner **and** an alpaka `powershell`/`shell` action. See
[ALPAKA_TRANSITION.md](ALPAKA_TRANSITION.md) for how script categories map onto alpaka's
typed actions during the migration.
