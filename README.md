# whoami

<p align="center">
  <a href="./LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg"></a>
  <a href="https://github.com/luckeyfaraday/whoami/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/luckeyfaraday/whoami?style=flat"></a>
  <a href="https://github.com/luckeyfaraday/whoami/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/luckeyfaraday/whoami"></a>
  <a href="https://github.com/luckeyfaraday/whoami/issues"><img alt="Issues" src="https://img.shields.io/github/issues/luckeyfaraday/whoami"></a>
  <img alt="Claude Code skill" src="https://img.shields.io/badge/Claude%20Code-skill-7C5CFF">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white">
  <img alt="No network calls" src="https://img.shields.io/badge/network-zero%20calls-success">
  <a href="#contributing"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

> A Claude Code skill that builds a complete, portable picture of who you are and
> what you do — so any agent can load instant context instead of starting cold.

Every new agent session starts from zero: it doesn't know your name, your stack,
what you're building, or how you like to work. `whoami` fixes that once. It reads
the signals already on your machine, interviews you to fill the gaps, and writes a
dense profile any agent can load in seconds.

## How it works

Two passes, combined:

1. **Machine scan** (`scan.sh`) — objective signals already on disk:
   - git identity & repositories (remotes, recent commits, dominant languages)
   - installed toolchains, languages, and global packages
   - editor/dotfile config (presence only)
   - **AI-agent session history across CLIs** — Claude Code, Codex, Droid/Factory,
     OpenCode, Gemini, Qwen (counts, recent project dirs, recent prompts)
   - shell history (most-used + recent commands)
   - normal-file structure (folder layout, recently modified files)
2. **Interview** — the skill asks you many *grounded* onboarding questions (made
   specific by what the scan found) to capture intent, goals, and preferences the
   machine can't reveal.

**Output:** `~/.whoami/profile.md` (+ `scan-raw.txt`), optionally persisted into
Claude Code memory so it applies automatically in future sessions.

## Install

Clone, then symlink into Claude Code's skills directory:

```bash
git clone https://github.com/<you>/whoami.git
ln -sfn "$PWD/whoami" ~/.claude/skills/whoami
```

## Use

In Claude Code, run the skill:

```
/whoami
```

(or just ask: "onboard me" / "figure out who I am"). Re-running is idempotent —
it diffs against your existing profile and only asks about what changed.

Run the scan standalone (no agent needed):

```bash
bash scan.sh --max-repos 40 --depth 2
```

### Flags

| flag | default | meaning |
|------|---------|---------|
| `--home DIR`     | `$HOME` | root to scan |
| `--max-repos N`  | `40`    | cap on git repos reported |
| `--depth N`      | `2`     | folder-tree depth for normal files |

## What the profile looks like

```markdown
# whoami — <name>
## Snapshot          # 2–3 sentence elevator description
## Identity
## Role & focus
## Current work      # active projects, priorities, goals (dated)
## Expertise & stack
## Tooling & environment
## Working style & preferences   # how agents should behave with you
## Constraints & boundaries
## Goals
## Open questions / low-confidence
```

## Privacy

This tool reads your machine — privacy is the default posture, not an afterthought:

- **Conservative scope:** dev/work signals + normal-file *structure* only.
- **Secrets are redacted** — lines matching key/token/password patterns are dropped.
- **Personal-doc contents are never printed** — only names and paths.
- **Everything stays local.** Nothing is transmitted anywhere. The generated
  profile and raw scan live under `~/.whoami/` and are gitignored.
- Broader scope (browser history, SSH known_hosts, document contents) is **opt-in**
  only, and the skill confirms before extending.

Review `scan.sh` before running it — it's a single, readable shell script with no
network calls.

## Contributing

Issues and PRs welcome. Good first additions: support for more agent CLIs, more
package managers, and macOS/WSL coverage. Keep the privacy contract intact — no
secret material, no personal-doc contents, no network calls in `scan.sh`.

## License

[MIT](./LICENSE)
