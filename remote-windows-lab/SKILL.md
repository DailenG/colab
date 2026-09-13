---
name: remote-windows-lab
description: Use when the user says initialize this device as a dev PC, initialize this device as a lab PC, show remote lab state, or asks to set up, validate, manage, or remove secure OMP access to Windows test devices. Orchestrates USB transfer bundles, multi-device state, OpenSSH, dedicated lab accounts, native computer-use, Edge relay/CDP, verification, and user-guided physical steps.
globs:
  - "**/*.ps1"
  - "**/.omp/config.yml"
---

# Remote Windows Lab

Use this skill when a project needs a disposable or dedicated Windows endpoint that OMP can administer and test. Prefer a separate lab account and reversible configuration over broad access to a daily-use machine.

## Conversational operations

This is a workflow skill, not a background daemon. When it is loaded, interpret these natural-language requests as explicit operations:

| User request | Operation |
|---|---|
| `Initialize this device as a dev PC` | Run the controller workflow with `scripts/Initialize-DevPc.ps1`. |
| `Initialize this device as a lab PC` | Run the target workflow with `scripts/Initialize-LabPc.ps1`. |
| `Finish OMP setup for this lab user` | Run `scripts/Initialize-OmpLabUser.ps1` in the interactive lab-user session. |
| `Import the lab PC response` | Run `scripts/Import-LabPcResponse.ps1` on the dev PC. |
| `Show remote lab state` | Run `scripts/Get-RemoteLabState.ps1`; explain incomplete checkpoints. |
| `Mark <host> SSH verified` | Actually test SSH first, then run `scripts/Set-RemoteLabDeviceState.ps1`. |
| `Retire <host> from the lab` | Guide teardown, verify access removal, then record `retired`. |

Natural-language matching loads this skill, but it does not bypass tool approval, UAC, or physical boundaries. Perform every discoverable/programmatic step. When a USB insertion, local sign-in, UAC approval, browser-extension action, VPN enrollment, reboot, or recovery-console check is required:

1. finish all work possible before the boundary;
2. persist the current state;
3. give the user one exact physical action and the command that follows it;
4. wait for the user's observed result;
5. resume at that checkpoint rather than restarting.

Never report a checkpoint complete merely because a command was issued. Verify its observable result.

## State and transfer contract

The dev PC maintains the multi-device registry at:

```text
%USERPROFILE%\.omp\remote-windows-lab\devices.json
```

Each lab PC maintains its local state at:

```text
%ProgramData%\OmpRemoteLab\device-state.json
```

The schema is `references/device-state.schema.json`. Device lifecycle values are:

```text
discovered
transfer_prepared
bootstrap_applied
ssh_verified
omp_pending
ready
retired
error
```

The registry may contain any number of lab devices. Match devices by stable `device_id`; hostname is a human lookup key and may be updated if renamed. Store hostnames, roles, addresses, SSH aliases, project repository, non-secret checks, timestamps, and operational notes. Never store private keys, passwords, GitHub tokens, device bearer tokens, recovery codes, or browser cookies.

USB transfer bundles use:

```text
<USB>:\OMP-Remote-Lab\<transfer-id>\
  manifest.json
  controller.pub
  scripts\
  skill\
  lab-response.json       # created by the lab PC
```

The dev initializer creates the bundle and explicitly asserts `private_key_included=false`. The lab initializer refuses incompatible manifests and possible private-key files. The private SSH key always remains on the dev PC.

## Dev PC orchestration

For `initialize this device as a dev PC`:

1. Inspect hostname, Windows version, network addresses, current OMP configuration, existing dedicated key, removable drives, and current registry. Do not ask for facts tools can discover.
2. If no removable drive exists, tell the user: `Connect a USB thumb drive, wait for its drive letter to appear, then tell me it is connected.` Do not select a network share or copy a private key as a shortcut.
3. If several removable drives exist, show drive letters, volume labels, and sizes, then ask which one to use.
4. Determine the controller address conservatively. If multiple plausible interfaces exist, ask the user to choose LAN or VPN reachability.
5. Run:

```powershell
& <skill-dir>\scripts\Initialize-DevPc.ps1 `
  -TransferRoot '<usb-root>' `
  -AllowedRemoteAddress '<controller-ip-or-subnet>' `
  -LabUser 'omp-lab' `
  -ProjectRepository '<private-repository-url>' `
  -SshAlias '<planned-alias>'
```

6. Inspect `manifest.json`; prove that no private key exists in the bundle.
7. Persist controller state as `transfer_prepared`.
8. Tell the user to safely eject the USB, connect it to the lab PC, start OMP there, and say `initialize this device as a lab PC using the connected USB drive`.

When the USB returns, run `Import-LabPcResponse.ps1`, add/update that lab device, configure an SSH alias only after resolving the returned hostname/address, and test key login. Mark `ssh_verified` only after a fresh connection succeeds. Mark `ready` only after the lab-side OMP capability and browser checks pass.

## Lab PC orchestration

For `initialize this device as a lab PC`:

1. Inspect hostname, OS/build/architecture, domain membership, current user/elevation, removable drives, existing OpenSSH use, and any local device state.
2. Require local administrative elevation for the bootstrap. If the session is not elevated, give the user the exact instruction to reopen OMP or PowerShell as Administrator; do not weaken UAC.
3. Locate exactly one compatible USB manifest. If none exists, instruct the user to connect the dev-prepared USB. If multiple exist, refuse ambiguity and identify them.
4. Explain the changes before approval: OpenSSH capability/service, dedicated local account, Administrators membership, authorized public key, source-scoped TCP 22 firewall rule, local state, and staged skill.
5. Run `scripts/Initialize-LabPc.ps1 -TransferRoot '<usb-root>'`. Allow the secure password prompt to remain interactive; never request or echo the password in chat.
6. Verify `sshd` is running, the firewall remote address matches the manifest, the authorized-key ACL is SYSTEM/Administrators only, and `sshd.exe -t` succeeds.
7. Persist `omp_pending` and write `lab-response.json` to the USB.
8. Tell the user to return the USB to the dev PC and to sign in locally as the lab user.
9. In that interactive user session, run `Initialize-OmpLabUser.ps1`. It installs the skill under the user's native OMP skill directory and configures computer/browser settings when `omp` is available.
10. Ask the user to install/reload the OMP extension in a dedicated Edge lab profile; this browser action is intentionally manual.
11. Restart OMP. Verify `computer.capabilities()`, list windows, take a read-only screenshot, and verify browser relay against a dedicated test tab.
12. Keep local state `omp_pending` until those checks pass. Then record `ready` and instruct the dev PC to import/update the returned state.

## Invariants

- Never publish SSH, VNC, WinRM, CDP, or browser-relay ports to the public Internet.
- Prefer trusted LAN, organization VPN, WireGuard, or Tailscale reachability.
- Require a dedicated Ed25519 key and scope the inbound firewall rule to the controlling workstation or VPN subnet.
- Use a dedicated local administrator, not a domain administrator or daily account.
- Keep browser automation in a disposable/dedicated Edge profile without personal secrets.
- Treat SSH and UI automation as separate capabilities: SSH controls commands/files/services; native OMP computer-use controls the Windows desktop.
- RDP changes session state. For software that observes RDP/session behavior, use RDP only for setup or explicitly label it as part of the test.
- Do not automate away the final key-login check, UAC consent, VPN enrollment, browser-extension installation, or recovery-console verification. Guide the user through these steps and wait for their observed result.

## Choose the control model

1. **Recommended — OMP runs on the laptop:** use SSH for bootstrap/recovery, enable OMP `computer`, and install the browser relay. This provides native Win32 capture/input/UI Automation plus browser DOM automation.
2. **Browser-only from another host:** run a disposable Edge profile with CDP bound to `127.0.0.1`, tunnel it through SSH, and attach OMP to the local tunnel. Never expose CDP to the LAN.
3. **VNC/RustDesk viewer controlled locally:** fallback only. Pixel scaling, stale coordinates, weak accessibility, clipboard ambiguity, and secure-desktop restrictions make it unreliable.
4. **RDP:** manual setup/recovery. Avoid for test cases where connection/session detection is under test.

## Setup workflow

### 1. Gather facts without asking for discoverable data

Determine:

- laptop hostname and Windows version
- controlling workstation IP or VPN subnet
- whether the laptop is domain joined
- whether OpenSSH is already used by another administrator
- intended local lab username
- public key path/content
- whether OMP and Edge relay will run locally on the laptop
- whether the test requires local console, RDP, or both

Use tools to discover these facts when access already exists. Ask the user only for physical/UAC/VPN actions or a materially different network/account choice.

### 2. Create a dedicated key on the controlling workstation

```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\omp_windows_lab"
```

Do not overwrite an existing key. Never copy the private key to the laptop.

### 3. Bootstrap the laptop

Copy `scripts/Enable-OmpLabAccess.ps1` from this skill to the laptop and run it from elevated PowerShell:

```powershell
.\Enable-OmpLabAccess.ps1 `
  -PublicKey (Get-Content "$env:USERPROFILE\Desktop\omp_windows_lab.pub" -Raw) `
  -AllowedRemoteAddress '192.0.2.25' `
  -LabUser 'omp-lab'
```

The script installs/starts OpenSSH Server, creates the local administrator when absent, writes `administrators_authorized_keys`, applies SYSTEM/Administrators ACLs, and creates a narrowly scoped firewall rule. It does not disable passwords automatically because doing so before key verification can lock out the operator.

### 4. Verify before hardening

From a second terminal on the controlling workstation:

```powershell
ssh -i "$HOME\.ssh\omp_windows_lab" omp-lab@SPARE-LAPTOP
```

Verify identity and elevation context:

```powershell
whoami
whoami /groups
Get-Service sshd
```

Only after successful key login, edit `%ProgramData%\ssh\sshd_config`:

```text
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
AllowUsers omp-lab
```

Validate configuration and restart:

```powershell
& "$env:WINDIR\System32\OpenSSH\sshd.exe" -t
Restart-Service sshd
```

Keep the successful SSH terminal open until a new key-only connection succeeds.

### 5. Configure OMP native UI control on the laptop

Write `%USERPROFILE%\.omp\agent\config.yml` for the lab account:

```yaml
computer:
  enabled: true
  display: all
  maxWidth: 1920
  maxHeight: 1200
browser:
  enabled: true
tools:
  approvalMode: write
```

Restart OMP. Confirm with `computer.capabilities()`, then enumerate windows and take a read-only screenshot before sending input. Prefer accessibility actions over pixel coordinates. UAC secure desktop may require a person at the laptop.

### 6. Configure browser automation

Install/reload the OMP extension in a dedicated Edge profile and confirm relay connectivity. Use `browser.open({ app: { relay: true }, app.target: ... })` or the session's supported relay syntax with a precise target. Never navigate an unrelated visible personal tab.

For remote CDP, launch only a disposable profile:

```powershell
msedge.exe --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 --user-data-dir=C:\Temp\OmpLabEdge
```

Tunnel from the controlling workstation:

```powershell
ssh -N -L 9223:127.0.0.1:9222 omp-windows-lab
```

Attach OMP to `http://127.0.0.1:9223`. Confirm the laptop firewall does not expose 9222.

## Project bootstrap

Use the project's private source remote, then verify the actual build/test command. Example:

```powershell
New-Item C:\Development -ItemType Directory -Force
Set-Location C:\Development
gh auth login
gh auth setup-git
git clone <private-repository-url>
```

Do not place GitHub tokens in scripts or remote URLs. Use Git Credential Manager, SSH keys, or the GitHub CLI credential store.

## Validation checklist

- SSH key login works after a fresh connection.
- Password login is disabled only after key verification.
- The firewall rule is limited to the intended source address/subnet.
- The account is local, dedicated, and in Administrators only when required.
- `computer.capabilities()` reports expected Windows capture/input/AX support.
- OMP can list the target app window, capture it, and use an accessibility action.
- Browser relay or tunneled CDP controls only the disposable profile.
- UAC/reboot/recovery access has a human fallback.
- No private key, bearer token, browser profile, or session transcript enters source control.
- Project status records the laptop name, setup state, verification, and teardown owner without recording secrets.

## Teardown

Use `scripts/Disable-OmpLabAccess.ps1`. It removes the skill-owned firewall rule and optionally the lab account/key authorization. It deliberately does not uninstall OpenSSH Server or remove unrelated administrators' configuration.

Before teardown, preserve project logs and push code. After teardown, confirm port 22 is unreachable from the controlling workstation if no other SSH firewall rule is intended.

## Troubleshooting

- **Permission denied (publickey):** confirm the public key is one line; for an administrator, use `%ProgramData%\ssh\administrators_authorized_keys`; reapply SYSTEM/Administrators ACLs; run `sshd.exe -t`; inspect OpenSSH event logs.
- **Connection timeout:** verify `sshd` is running, the firewall source address is correct, VPN routing exists, and no public NAT assumption was made.
- **OMP computer prelude missing:** enable `computer.enabled`, restart the session, and inspect `computer.capabilities()`.
- **Browser relay unavailable:** ensure the extension is enabled in the intended Edge profile and reload it; target a dedicated tab.
- **UAC cannot be clicked:** use the local console or approved remote-support tooling. Never weaken UAC to make automation easier.
- **RDP test is inconsistent:** document whether the RDP window was closed, disconnected, or signed out; these create different Windows session transitions.
