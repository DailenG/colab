# Installation

`remote-windows-lab/` is a portable [Agent Skill](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills): a `SKILL.md` file with YAML frontmatter plus supporting scripts and reference material. The same folder works for OMP and Claude Code without modification. Codex CLI and other agents without a native skill loader can still use it by reading the instructions directly.

Install it once per machine, on whichever machine(s) will run the agent — typically just the dev PC and, after pairing, the lab PC.

## OMP

1. Clone this repository somewhere durable, e.g.:

   ```powershell
   git clone https://github.com/DailenG/colab.git C:\Syncs\Resilio\Code\Github\daileng\Win-CoLab-Assistant
   ```

2. Add its skill directory (or a directory containing it) to `skills.customDirectories` in your OMP configuration file, typically `%USERPROFILE%\.omp\agent\config.yml`:

   ```yaml
   skills:
     customDirectories:
       - C:\Syncs\Resilio\Code\Github\daileng\Win-CoLab-Assistant
   ```

   `customDirectories` entries are directories that *contain* skill folders (each with its own `SKILL.md`), so point it at the repository root, not at `remote-windows-lab/` itself.

   If you keep a separate personal skills directory, symlink instead:

   ```powershell
   New-Item -ItemType SymbolicLink `
       -Path 'C:\Syncs\Resilio\Code\Skills\remote-windows-lab' `
       -Target 'C:\Syncs\Resilio\Code\Github\daileng\Win-CoLab-Assistant\remote-windows-lab'
   ```

3. Restart the OMP session. Confirm the skill loads:

   ```text
   Read skill://remote-windows-lab
   ```

   or ask the agent to list available skills and confirm `remote-windows-lab` appears.

## Claude Code

Claude Code reads Agent Skills from `.claude/skills/<name>/` (project-scoped) or `~/.claude/skills/<name>/` (user-scoped), using the same `SKILL.md` format.

Project-scoped (recommended when the paired lab machine is dedicated to one project):

```powershell
New-Item 'C:\path\to\project\.claude\skills' -ItemType Directory -Force
Copy-Item `
    'C:\Syncs\Resilio\Code\Github\daileng\Win-CoLab-Assistant\remote-windows-lab' `
    'C:\path\to\project\.claude\skills\remote-windows-lab' `
    -Recurse
```

User-scoped (recommended when you pair machines across many projects):

```powershell
New-Item "$HOME\.claude\skills" -ItemType Directory -Force
Copy-Item `
    'C:\Syncs\Resilio\Code\Github\daileng\Win-CoLab-Assistant\remote-windows-lab' `
    "$HOME\.claude\skills\remote-windows-lab" `
    -Recurse
```

A symlink instead of a copy keeps the skill in sync with future updates to this repository — use `New-Item -ItemType SymbolicLink` as shown in the OMP section, targeting the Claude Code skills path instead.

Restart Claude Code and confirm the skill is recognized (it should activate automatically on a matching request, or list under available skills if your Claude Code version exposes that).

## Codex CLI (or other agents without a native skill loader)

As of this writing, Codex CLI does not have a dedicated Agent Skills loader. Two practical options:

**Option A — point Codex at the repository and its `AGENTS.md`.** Codex reads `AGENTS.md` files for project context. Clone this repository as a sibling of (or inside) your working project, then tell Codex:

```text
Read AGENTS.md in Win-CoLab-Assistant and follow it to initialize this
device as a dev PC / lab PC.
```

Codex will read `AGENTS.md`, which points to `remote-windows-lab/SKILL.md` as the authoritative behavior definition, and proceed manually through the same workflow, invoking the PowerShell scripts itself.

**Option B — inline the instructions.** Copy the relevant sections of `remote-windows-lab/SKILL.md` into the target project's own `AGENTS.md` or custom-instructions file, under a clearly delimited heading, so Codex picks it up as part of normal project context without a separate read step.

Either way, the actual work is done by the PowerShell scripts in `remote-windows-lab/scripts/`, which have no agent-specific dependency — see [`usage.md`](usage.md#manual-cli-reference) to run them directly if you prefer not to rely on the agent's judgment for a given step.

## Verifying the install

Regardless of agent, confirm:

- The agent can locate and read `remote-windows-lab/SKILL.md` (or its inlined equivalent).
- `remote-windows-lab/scripts/RemoteLab.Common.ps1` parses without error:

  ```powershell
  $tokens = $null; $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
      'C:\Syncs\Resilio\Code\Github\daileng\Win-CoLab-Assistant\remote-windows-lab\scripts\RemoteLab.Common.ps1',
      [ref]$tokens, [ref]$errors) | Out-Null
  $errors.Count
  ```

  should print `0`.
- Asking the agent to "show remote lab state" runs `Get-RemoteLabState.ps1` and reports either an empty registry or existing devices — not an error about a missing skill.

If any of these fail, re-check the `customDirectories`/skills-folder path and restart the agent session; skill discovery only happens at session start.
