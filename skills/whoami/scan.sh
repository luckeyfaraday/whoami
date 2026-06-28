#!/usr/bin/env bash
# whoami scan — gathers signals about who the user is and what they do.
# Scope: conservative (dev/work signals) + normal-file structure. Secrets redacted.
# Output: human-readable sections on stdout. Safe to read; no secrets emitted.
#
# Usage: scan.sh [--home DIR] [--max-repos N] [--depth N]

set -uo pipefail

HOME_DIR="${HOME}"
MAX_REPOS=40
TREE_DEPTH=2
HIST_TOP=40

while [ $# -gt 0 ]; do
  case "$1" in
    --home) HOME_DIR="$2"; shift 2;;
    --max-repos) MAX_REPOS="$2"; shift 2;;
    --depth) TREE_DEPTH="$2"; shift 2;;
    *) shift;;
  esac
done

# Redaction filter: drop any line that looks like it carries a secret.
SECRET_RE='(api[_-]?key|secret|passw(or)?d|token|bearer|authorization|aws_|private[_-]?key|client[_-]?secret|-----BEGIN|ghp_|sk-[A-Za-z0-9]{12,}|xox[baprs]-)'
redact() { grep -aviE "$SECRET_RE" 2>/dev/null || true; }
have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n## %s\n' "$1"; }
sub() { printf '\n### %s\n' "$1"; }

echo "# whoami raw scan"
echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "home: $HOME_DIR"

# ---------------------------------------------------------------------------
section "Identity"
echo "user: ${USER:-$(id -un 2>/dev/null)}"
echo "hostname: $(hostname 2>/dev/null)"
if have git; then
  echo "git.name: $(git config --global user.name 2>/dev/null)"
  echo "git.email: $(git config --global user.email 2>/dev/null)"
  echo "git.editor: $(git config --global core.editor 2>/dev/null)"
fi
[ -n "${LANG:-}" ] && echo "locale: $LANG"
[ -n "${TZ:-}" ] && echo "tz: $TZ"

# ---------------------------------------------------------------------------
section "System"
echo "os: $(uname -srm 2>/dev/null)"
if [ -r /etc/os-release ]; then . /etc/os-release 2>/dev/null; echo "distro: ${PRETTY_NAME:-unknown}"; fi
have sw_vers && echo "macos: $(sw_vers -productVersion 2>/dev/null)"
echo "shell: ${SHELL:-unknown}"
echo "cpus: $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"

# ---------------------------------------------------------------------------
section "Toolchains & languages"
for t in node deno bun python3 python pip pipx ruby go rustc cargo java javac \
         php dotnet gcc clang make cmake docker podman kubectl terraform \
         psql mysql sqlite3 redis-cli aws gcloud az gh git nvim vim code \
         tmux zsh fish jq ffmpeg pandoc R julia swift lua perl; do
  if have "$t"; then
    v=$("$t" --version 2>/dev/null | head -1)
    [ -z "$v" ] && v=$("$t" version 2>/dev/null | head -1)
    echo "$t: ${v:-present}"
  fi
done

# ---------------------------------------------------------------------------
section "Installed packages (global)"
have brew    && { sub "brew";   brew leaves 2>/dev/null | head -100; }
have pipx    && { sub "pipx";   pipx list --short 2>/dev/null | head -60; }
if have npm; then sub "npm -g"; npm ls -g --depth=0 2>/dev/null | sed '1d' | head -60; fi
have cargo   && { sub "cargo";  ls "$HOME_DIR/.cargo/bin" 2>/dev/null | head -60; }
have pip     && { sub "pip (top-level)"; pip list 2>/dev/null | head -60; }
if have dpkg && ! have brew; then sub "apt (manually installed)"; (apt-mark showmanual 2>/dev/null | head -120) || true; fi

# ---------------------------------------------------------------------------
section "Git repositories"
echo "scanning under $HOME_DIR (depth-limited, skipping caches)..."
count=0
# Find .git dirs but prune noisy locations.
while IFS= read -r gitdir; do
  [ "$count" -ge "$MAX_REPOS" ] && { echo "... (truncated at $MAX_REPOS repos)"; break; }
  repo="$(dirname "$gitdir")"
  count=$((count+1))
  sub "$repo"
  ( cd "$repo" 2>/dev/null || exit
    remote=$(git config --get remote.origin.url 2>/dev/null)
    [ -n "$remote" ] && echo "remote: $remote"
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    echo "branch: ${branch:-?}  commits: $(git rev-list --count HEAD 2>/dev/null || echo 0)"
    last=$(git log -1 --format='%cs %s' 2>/dev/null)
    [ -n "$last" ] && echo "last: $last"
    # Dominant languages by tracked file extension.
    git ls-files 2>/dev/null | sed -n 's/.*\.\([A-Za-z0-9]\{1,5\}\)$/\1/p' \
      | sort | uniq -c | sort -rn | head -5 | awk '{printf "  %s(%s)", $2, $1}'
    echo ""
  )
done < <(find "$HOME_DIR" -maxdepth 5 -type d -name .git \
          \( -path '*/node_modules/*' -o -path '*/.cache/*' -o -path '*/Library/*' \
             -o -path '*/.local/*' -o -path '*/vendor/*' \) -prune -o \
          -type d -name .git -print 2>/dev/null)
echo "total repos found (capped): $count"

# ---------------------------------------------------------------------------
section "Editor & dotfile config (presence only)"
for f in .vimrc .config/nvim .zshrc .bashrc .bash_profile .profile .gitconfig \
         .tmux.conf .config/Code/User/settings.json .config/fish/config.fish \
         .editorconfig .inputrc .config/starship.toml .aliases .functions; do
  [ -e "$HOME_DIR/$f" ] && echo "present: $f"
done

# ---------------------------------------------------------------------------
section "Claude Code context"
CL="$HOME_DIR/.claude"
if [ -d "$CL" ]; then
  [ -d "$CL/skills" ] && { sub "skills"; ls "$CL/skills" 2>/dev/null; }
  [ -d "$CL/agents" ] && { sub "agents"; ls "$CL/agents" 2>/dev/null; }
  # Surface memory indexes (these are user-authored summaries, safe + rich).
  while IFS= read -r mem; do
    sub "memory: ${mem#$HOME_DIR/}"
    head -60 "$mem" 2>/dev/null | redact
  done < <(find "$CL" -maxdepth 4 -name MEMORY.md 2>/dev/null | head -10)
  [ -f "$HOME_DIR/.claude.json" ] && { sub "configured MCP servers"; (jq -r '.mcpServers // {} | keys[]' "$HOME_DIR/.claude.json" 2>/dev/null || true); }
else
  echo "(no ~/.claude)"
fi

# ---------------------------------------------------------------------------
section "AI agent sessions (cross-CLI)"
# Decode an encoded cwd dir name (leading '-' + '/'->'-') back to a readable path.
decode_cwd() { sed -E 's#^-#/#; s#-#/#g'; }
agent_present() { [ -e "$HOME_DIR/$1" ]; }

# Claude Code — project dirs encode the cwd; jsonl files are sessions.
if agent_present .claude/projects; then
  sub "Claude Code"
  echo "projects worked in: $(ls "$HOME_DIR/.claude/projects" 2>/dev/null | wc -l)"
  echo "session files: $(find "$HOME_DIR/.claude/projects" -name '*.jsonl' 2>/dev/null | wc -l)"
  echo "most recent project dirs:"
  ls -1t "$HOME_DIR/.claude/projects" 2>/dev/null | head -12 | decode_cwd
fi

# Codex (OpenAI) — sessions by date + history.jsonl with prompt text.
if agent_present .codex; then
  sub "Codex (OpenAI)"
  echo "session files: $(find "$HOME_DIR/.codex/sessions" -name '*.jsonl' 2>/dev/null | wc -l)"
  if [ -f "$HOME_DIR/.codex/history.jsonl" ] && have jq; then
    echo "recent prompts:"
    tail -200 "$HOME_DIR/.codex/history.jsonl" 2>/dev/null \
      | jq -r '.text // empty' 2>/dev/null | redact | grep -vE '^$' | tail -10 | cut -c1-100
  fi
fi

# Droid (Factory) — sessions keyed by cwd + history.json.
if agent_present .factory; then
  sub "Droid (Factory)"
  echo "session dirs: $(ls "$HOME_DIR/.factory/sessions" 2>/dev/null | wc -l)"
  ls -1t "$HOME_DIR/.factory/sessions" 2>/dev/null | head -10 | decode_cwd
fi

# OpenCode — storage holds sessions/messages.
if agent_present .local/share/opencode || agent_present .config/opencode; then
  sub "OpenCode"
  echo "storage entries: $(find "$HOME_DIR/.local/share/opencode/storage" -maxdepth 2 2>/dev/null | wc -l)"
  echo "repos tracked: $(ls "$HOME_DIR/.local/share/opencode/repos" 2>/dev/null | head -12)"
fi

# Gemini CLI — projects.json lists worked dirs.
if agent_present .gemini; then
  sub "Gemini CLI"
  if [ -f "$HOME_DIR/.gemini/projects.json" ] && have jq; then
    jq -r 'keys[]? // empty' "$HOME_DIR/.gemini/projects.json" 2>/dev/null | head -12
  fi
fi

# Qwen Code — projects dir.
if agent_present .qwen/projects; then
  sub "Qwen Code"
  ls -1t "$HOME_DIR/.qwen/projects" 2>/dev/null | head -10 | decode_cwd
fi

# Catch-all: any other assistant config dirs present.
sub "other assistant configs present"
for a in .cursor .continue .aider .ollama .config/github-copilot .windsurf .cline .aichat; do
  [ -e "$HOME_DIR/$a" ] && echo "present: $a"
done

# ---------------------------------------------------------------------------
section "Shell history (commands, redacted)"
HISTFILES=$(ls "$HOME_DIR"/.bash_history "$HOME_DIR"/.zsh_history "$HOME_DIR"/.local/share/fish/fish_history 2>/dev/null)
if [ -n "$HISTFILES" ]; then
  # Normalize: strip zsh ': time:0;' prefixes and fish '- cmd:' prefixes.
  raw=$(cat $HISTFILES 2>/dev/null \
        | sed -E 's/^: [0-9]+:[0-9]+;//; s/^- cmd: //' \
        | redact)
  sub "most-used commands"
  printf '%s\n' "$raw" | awk '{print $1}' | grep -vE '^$' | sort | uniq -c | sort -rn | head -"$HIST_TOP"
  sub "recent commands (tail)"
  printf '%s\n' "$raw" | tail -40
else
  echo "(no shell history found)"
fi

# ---------------------------------------------------------------------------
section "Home folder structure (normal files)"
echo "top-level of $HOME_DIR:"
ls -1 "$HOME_DIR" 2>/dev/null | grep -vE '^\.' | head -60
for d in Documents Desktop Downloads Projects projects code Code work dev notes Notes; do
  if [ -d "$HOME_DIR/$d" ]; then
    sub "$d/ (names, depth $TREE_DEPTH)"
    if have tree; then
      tree -L "$TREE_DEPTH" -a -I 'node_modules|.git|__pycache__|.venv|target' --noreport "$HOME_DIR/$d" 2>/dev/null | head -80
    else
      find "$HOME_DIR/$d" -maxdepth "$TREE_DEPTH" \
        \( -name node_modules -o -name .git -o -name .venv -o -name target \) -prune -o \
        -print 2>/dev/null | sed "s|$HOME_DIR/||" | head -80
    fi
  fi
done

# ---------------------------------------------------------------------------
section "Recently modified files (last 14 days, non-hidden)"
find "$HOME_DIR" -maxdepth 4 -type f -mtime -14 \
  \( -path '*/node_modules/*' -o -path '*/.cache/*' -o -path '*/.git/*' \
     -o -path '*/Library/*' -o -path '*/.local/*' -o -name '.*' \) -prune -o \
  -type f -mtime -14 -print 2>/dev/null \
  | grep -vE '/\.' | sed "s|$HOME_DIR/||" | head -60

echo ""
echo "# end of scan"
