# Security model

This skill grants an AI agent real administrative and UI control of a Windows machine. The design goal is to make that as narrow, reversible, and auditable as possible — not to eliminate risk, which is inherent to the capability being granted.

## Threat model

In scope:

- A misconfigured or overly broad SSH exposure being reachable from untrusted networks.
- A shared or daily-use account being granted persistent remote administrative access.
- A private key or credential leaking through a removable-media transfer step.
- Automation silently "completing" a step that actually requires human/physical action (UAC, local sign-in, browser-extension install), producing false confidence.
- Browser remote-debugging (CDP) being exposed beyond the single disposable profile it is meant to control.

Out of scope / explicitly not solved by this skill:

- Compromise of either machine's OS below the account/network boundaries described here.
- Physical security of the USB drive in transit between machines (treat it as you would any other proximity-based trust bootstrap).
- Anything the user explicitly asks the agent to do that intentionally widens exposure — the skill will push back and explain the risk, but it follows the user's final decision.

## Invariants

The skill and its scripts enforce these at every step:

1. **No public exposure.** SSH (TCP 22), browser CDP, VNC, and WinRM are never bound or firewalled to the public Internet. The firewall rule created by `Enable-OmpLabAccess.ps1` is scoped to one address or subnet, supplied explicitly.
2. **Dedicated identity, not daily identity.** A dedicated local account (default name `omp-lab`) is created for remote automation. The user's domain or daily administrative account is never used for this purpose.
3. **Dedicated key, one direction.** A dedicated Ed25519 key pair is generated on the dev PC. Only the public key ever leaves that machine. `Initialize-LabPc.ps1` refuses any transfer bundle whose manifest claims to include a private key, and additionally scans the bundle for files that look like private-key material before proceeding.
4. **Key-only SSH, verified before hardening.** `sshd_config` is only switched to `PasswordAuthentication no` after the workflow instructs the operator to verify a fresh key-only login from a second session. The setup script does not do this automatically, specifically to avoid a self-inflicted lockout.
5. **Least-privilege ACLs.** `administrators_authorized_keys` is restricted to `SYSTEM` and `BUILTIN\Administrators` via `icacls`, matching OpenSSH's own requirement for administrator-key files.
6. **Separate capabilities, separate mechanisms.** SSH is for commands, files, and services. It is never treated as a substitute for native UI control. Native computer-use and the browser relay are configured and run directly on the target machine's own agent session, under the dedicated account, not proxied over SSH.
7. **Disposable browser surface.** Browser automation (whether via the relay extension or tunneled CDP) is confined to a dedicated, disposable browser profile. CDP is never bound to anything other than `127.0.0.1` on the target machine; reaching it from elsewhere requires an explicit SSH tunnel the operator sets up themselves.
8. **RDP session-state awareness.** RDP is treated as a setup/recovery tool, not a routine access mechanism, because connecting over RDP changes Windows session state in ways that can interfere with software that specifically observes session/connection behavior.
9. **Human confirmation at physical boundaries.** USB insertion, interactive local sign-in, UAC consent, browser-extension installation, VPN enrollment, and reboot/recovery-console verification are never assumed complete because a command was issued. The skill states the exact action needed and waits for the operator's observed result before advancing the recorded state.
10. **Reversibility.** Every setup action has a corresponding teardown action. `Disable-OmpLabAccess.ps1` removes only the firewall rule and key authorization (and, optionally, the account) that this skill's own setup script created — it does not touch OpenSSH Server itself or any other administrator's configuration, since another party may depend on it.

## What is stored, and where

**Dev PC registry** — `%USERPROFILE%\.omp\remote-windows-lab\devices.json`
**Lab PC local state** — `%ProgramData%\OmpRemoteLab\device-state.json`

Both validate against [`remote-windows-lab/references/device-state.schema.json`](../remote-windows-lab/references/device-state.schema.json) and contain only:

- Hostname, generated device ID, role (`dev_pc`/`lab_pc`), lifecycle state, and timestamps.
- Discovered network addresses.
- The configured SSH alias name and dedicated lab-account username (not its password).
- The project repository URL, if supplied.
- Non-secret boolean checks (e.g., `ssh_service_running`, `firewall_scoped`) and free-text operational notes.

**Never stored, anywhere, by this skill:**

- Private SSH keys.
- Account passwords (the setup script prompts for one interactively as a `SecureString` and does not persist it).
- GitHub tokens, Coordinator/API bearer tokens, or any other credential.
- Browser cookies, profiles, or session data.
- Full OMP/agent session transcripts.

## USB transfer bundle contents

```text
<USB>:\OMP-Remote-Lab\<transfer-id>\
  manifest.json        # non-secret: addresses, lab username, repo URL, alias, private_key_included=false
  controller.pub       # the dedicated public key — safe to share
  scripts\             # the PowerShell implementation, copied for offline use on the lab PC
  skill\                # a copy of this skill, staged for installation under the lab account
  lab-response.json    # written by the lab PC; same non-secret shape as manifest.json plus its own device record
```

`Initialize-LabPc.ps1` independently verifies `private_key_included == false` in the manifest and scans the bundle for filenames matching common private-key patterns (`id_rsa`, `id_ed25519`, `*.pem`, or anything containing `private`) before proceeding, regardless of what the manifest claims.

## Recommended operational hygiene

- Prefer a Windows Firewall rule scoped to a single address over a subnet whenever the dev PC's address is stable.
- If the two machines are not on the same trusted LAN, use an organization VPN, WireGuard, or Tailscale — never port-forward SSH from a home or office router to the public Internet.
- Reimage or restore a snapshot of the lab PC between installer- or security-sensitive experiments, since this skill grants real administrative capability to whatever runs there.
- Retire a lab machine (`Retire <hostname> from the lab`) as soon as it stops being actively used, and confirm afterward that its SSH port is unreachable from the dev PC if no other administrator relies on that service.
