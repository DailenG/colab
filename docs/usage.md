# Usage

## Conversational workflow

Once the skill is installed (see [`installation.md`](installation.md)), the whole pairing process is driven by plain-language requests. The skill maps them to scripts and orchestrates the physical handoff between machines:

| You say | What happens |
|---|---|
| `Initialize this device as a dev PC` | The agent inspects this machine, generates a dedicated SSH key if needed, and — after you connect a USB drive — writes a transfer bundle (public key + scripts + this skill; no private key) to it. |
| `Initialize this device as a lab PC using the connected USB drive` | The agent (running elevated) reads the bundle, installs/configures OpenSSH Server, creates a dedicated local account, scopes a firewall rule to the dev PC's address, and writes a response back to the USB. |
| `Finish OMP setup for this lab user` | Run while interactively signed in as the new dedicated account on the lab PC. Installs the skill for that user's agent and enables native computer-use / browser relay configuration. |
| `Import the lab PC response` | Run on the dev PC after the USB returns. Registers the lab PC in the local device registry and prepares it for an SSH alias. |
| `Show remote lab state` | Either machine: lists every known device, its role, and its lifecycle state. |
| `Mark <hostname> SSH verified` | After you've personally confirmed a fresh key-only SSH connection succeeds. |
| `Retire <hostname> from the lab` | Guides teardown (remove firewall rule, optionally remove the account) and records the final state. |

At each physical boundary — inserting a USB, signing in locally, approving a UAC prompt, installing a browser extension — the agent stops, tells you exactly what to do and what to say when you're done, and waits. It does not attempt to fabricate completion of a step it cannot perform itself.

## End-to-end example

Assume:

| Role | Example |
|---|---|
| Dev PC | `DEV-PC`, `192.168.10.25` |
| Lab PC | `TEST-LAPTOP`, `192.168.10.80` |
| Dedicated lab account | `omp-lab` |
| Project repository | `https://github.com/youruser/yourproject` |

### 1. On the dev PC

```text
Initialize this device as a dev PC for https://github.com/youruser/yourproject.
```

The agent will:

- Check for an existing dedicated key at `~/.ssh/omp_windows_lab`; generate one if absent.
- Ask you to connect a USB drive if none is present, or ask which one to use if several are.
- Determine (or ask you to confirm) which local network address the lab PC should be allowed to reach.
- Run `Initialize-DevPc.ps1`, producing a bundle at `<usb>\OMP-Remote-Lab\<transfer-id>\`.
- Show you the manifest and confirm no private key is present.
- Tell you: *"Safely eject the USB drive, connect it to the lab PC, start OMP there, and say: initialize this device as a lab PC using the connected USB drive."*

### 2. On the lab PC

Open an elevated PowerShell/agent session, then:

```text
Initialize this device as a lab PC using the connected USB drive.
```

The agent will:

- Confirm it is running elevated (and tell you exactly how to relaunch if not).
- Locate the bundle on the USB drive and refuse it if ambiguous or suspicious.
- Explain the changes about to be made (OpenSSH, dedicated account, firewall rule, ACLs) before running `Initialize-LabPc.ps1`.
- Prompt securely for the new account's initial password (never echoed to chat).
- Verify `sshd` is running, the firewall rule is correctly scoped, and the authorized-key file's ACL is SYSTEM/Administrators-only.
- Write a response file back to the USB and tell you to return it to the dev PC, then sign in locally as `omp-lab`.

### 3. Back on the dev PC

```text
Import the lab PC response.
```

The agent registers the lab PC, offers to add an SSH alias, and — only after you confirm a fresh key-only connection succeeds — marks it `ssh_verified`.

### 4. On the lab PC, signed in as the dedicated account

```text
Finish OMP setup for this lab user.
```

This installs the skill for that account's agent and applies computer-use/browser-relay configuration. You will still be asked to manually install or reload the browser extension in a dedicated profile — that step is intentionally not automated.

### 5. Anywhere

```text
Show remote lab state.
```

Lists every known device, its role (`dev_pc`/`lab_pc`), and its lifecycle state, so you always know what's configured and what's still pending — even across many lab machines.

## First smoke test on a freshly paired lab PC

A reasonable first exercise once a lab PC reaches `ready`:

1. Run whatever your target application's console/dev-mode entry point is on the lab PC.
2. From the dev PC, confirm you can reach the lab PC over the SSH alias and inspect its process/service state.
3. On the lab PC's agent session, confirm `computer.capabilities()` reports expected capture/input support, then take a read-only screenshot of the application under test.
4. Confirm the browser relay can open and read a page in the dedicated Edge profile without touching any other browser profile.
5. Disconnect network access temporarily and confirm the application under test degrades the way you expect, then restore it.

## Manual CLI reference

Every operation is a plain PowerShell script with no agent dependency. Useful if you want to run a step yourself, script it into CI, or audit exactly what an agent will do before approving it.

```powershell
# On the dev PC — prepare a transfer bundle
.\remote-windows-lab\scripts\Initialize-DevPc.ps1 `
    -TransferRoot 'E:\' `
    -AllowedRemoteAddress '192.168.10.25' `
    -LabUser 'omp-lab' `
    -ProjectRepository 'https://github.com/youruser/yourproject' `
    -SshAlias 'ticktockdock-lab'

# On the lab PC (elevated) — bootstrap SSH and the dedicated account
.\remote-windows-lab\scripts\Initialize-LabPc.ps1 -TransferRoot 'E:\'

# On the lab PC, signed in as the dedicated account — finish agent setup
.\remote-windows-lab\scripts\Initialize-OmpLabUser.ps1

# On the dev PC — import the lab PC's response from the returned USB
.\remote-windows-lab\scripts\Import-LabPcResponse.ps1 -TransferRoot 'E:\' -SshAlias 'ticktockdock-lab'

# Either machine — inspect the local device registry
.\remote-windows-lab\scripts\Get-RemoteLabState.ps1

# Either machine — record a manually verified state transition
.\remote-windows-lab\scripts\Set-RemoteLabDeviceState.ps1 -Hostname 'TEST-LAPTOP' -State ssh_verified

# On the lab PC (elevated) — remove access this skill granted
.\remote-windows-lab\scripts\Disable-OmpLabAccess.ps1 -PublicKey (Get-Content .\controller.pub -Raw) -LabUser 'omp-lab'
```

`-TransferRoot` is optional wherever a script needs the USB drive; omit it and the script will auto-detect a single removable drive, or ask you to disambiguate if more than one is connected.

## Registry location

- Dev PC (controller) registry: `%USERPROFILE%\.omp\remote-windows-lab\devices.json`
- Lab PC local state: `%ProgramData%\OmpRemoteLab\device-state.json`

Both are plain JSON validated against [`remote-windows-lab/references/device-state.schema.json`](../remote-windows-lab/references/device-state.schema.json). Neither ever contains a private key, password, token, or session transcript — see [`security.md`](security.md) for the full list of what is and is not stored.

## Multiple lab machines

The registry is a list, keyed by a stable `device_id`. Repeat the dev PC → lab PC → dev PC handshake for each additional lab machine; `Show remote lab state` will list all of them with their independent lifecycle states. There is no limit on how many lab machines one dev PC can track.
