#!/usr/bin/env bash
# Jarvis installer. Puts a real Mac control stack on the machine and teaches
# your agent to use it. Idempotent. --dry-run changes nothing.
# https://github.com/calebnewtonusc/Jarvis
set -uo pipefail

REPO_URL="https://github.com/calebnewtonusc/Jarvis.git"
JARVIS_HOME="${JARVIS_HOME:-$HOME/.jarvis}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DRY=0
SKIP_MCP=0

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --no-mcp)  SKIP_MCP=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  esac
done

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!  \033[0m %s\n' "$*"; }
ok()   { printf '   %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
do_()  { if [ "$DRY" = 1 ]; then printf '   [dry-run] %s\n' "$*"; else "$@"; fi; }
done_() { [ "$DRY" = 1 ] || ok "$*"; }   # only claim success on a real run

[ "$(uname -s)" = "Darwin" ] || { echo "Jarvis is macOS only."; exit 1; }
[ "$DRY" = 1 ] && say "DRY RUN. Nothing will be changed."

# ---------------------------------------------------------------- source
say "Getting the repo"
if [ -f "$(dirname "$0")/bin/jarvis" ]; then
  SRC="$(cd "$(dirname "$0")" && pwd)"
  ok "using local checkout: $SRC"
elif [ -d "$JARVIS_HOME/.git" ]; then
  SRC="$JARVIS_HOME"
  do_ git -C "$JARVIS_HOME" pull --ff-only --quiet
  ok "updated $JARVIS_HOME"
else
  SRC="$JARVIS_HOME"
  do_ git clone --quiet --depth 1 "$REPO_URL" "$JARVIS_HOME"
  ok "cloned to $JARVIS_HOME"
fi

# ---------------------------------------------------------------- tools
say "Installing the control stack"

if ! have brew; then
  warn "Homebrew not found. Install it first: https://brew.sh"
  warn "Skipping peekaboo and cliclick."
else
  # layer 3/4/5, the widest macOS surface
  if have peekaboo; then ok "peekaboo already installed"
  else do_ brew install steipete/tap/peekaboo && done_ "peekaboo installed"; fi
  # layer 4, one job
  if have cliclick; then ok "cliclick already installed"
  else do_ brew install cliclick && done_ "cliclick installed"; fi
fi

if ! have npm; then
  warn "npm not found. Install Node 22+ and rerun. Skipping agent-desktop and the web bridge."
else
  # layer 3, the cleanest pure accessibility-tree driver
  if have agent-desktop; then ok "agent-desktop already installed"
  else do_ npm install -g agent-desktop >/dev/null 2>&1 && done_ "agent-desktop installed"; fi
  # layer 6, the Chrome DevTools bridge for web content
  if [ -d "$SRC/bridge" ] && [ ! -d "$SRC/bridge/node_modules" ]; then
    do_ sh -c "cd '$SRC/bridge' && npm install --silent >/dev/null 2>&1" && done_ "web bridge deps installed"
  else
    ok "web bridge deps present"
  fi
fi

# ---------------------------------------------------------------- jarvis
say "Installing the jarvis CLI"
do_ mkdir -p "$BIN_DIR"
if [ "$DRY" = 1 ]; then
  ok "[dry-run] ln -sf $SRC/bin/jarvis $BIN_DIR/jarvis"
else
  ln -sf "$SRC/bin/jarvis" "$BIN_DIR/jarvis"
  ok "$BIN_DIR/jarvis -> $SRC/bin/jarvis"
fi
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH. Add this to ~/.zshrc:"
     warn "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ---------------------------------------------------------------- agent files
say "Installing skills and commands for your agent"
do_ mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"
if [ -d "$SRC/skills" ]; then
  for s in "$SRC"/skills/*/; do
    n=$(basename "$s")
    do_ rm -rf "$CLAUDE_DIR/skills/$n"
    do_ cp -R "$s" "$CLAUDE_DIR/skills/$n"
    done_ "skill: $n"
  done
fi
if [ -d "$SRC/commands" ]; then
  for c in "$SRC"/commands/*.md; do
    [ -e "$c" ] || continue
    do_ cp "$c" "$CLAUDE_DIR/commands/$(basename "$c")"
    done_ "command: /$(basename "$c" .md)"
  done
fi

# ---------------------------------------------------------------- mcp
if [ "$SKIP_MCP" = 0 ]; then
  say "Registering MCP servers"
  if have claude; then
    # layer 2 over MCP: AppleScript and JXA with a callable script knowledge base
    if claude mcp list 2>/dev/null | grep -q macos-automator; then
      ok "macos-automator already registered"
    else
      do_ claude mcp add --scope user macos-automator \
        -- npx -y @steipete/macos-automator-mcp@latest \
        && done_ "macos-automator registered"
    fi
    if have peekaboo && ! claude mcp list 2>/dev/null | grep -q peekaboo; then
      do_ claude mcp add --scope user peekaboo -- peekaboo mcp serve \
        && done_ "peekaboo MCP registered"
    fi
  else
    warn "claude CLI not found. Register manually:"
    warn "  claude mcp add --scope user macos-automator -- npx -y @steipete/macos-automator-mcp@latest"
  fi
fi

# ---------------------------------------------------------------- permissions
echo
say "Permissions: the part only a human can do"
cat <<'PERMS'
   macOS has no API to grant these. tccutil can only remove grants, never add
   them. Only an MDM profile can pre-grant, and that needs an enrolled machine.
   So: a person clicks two toggles, once.

   System Settings > Privacy & Security >
     1. Accessibility     (layers 3 and 4: read the UI tree, click, type)
     2. Screen Recording  (layer 5: screenshots)

   Add the app hosting your agent: Terminal, Ghostty, iTerm, VS Code, Cursor.
   Not "Claude". Not "jarvis". Run `jarvis doctor` and it names the exact one.

   Optional, only for layer 1 (reading Messages, Notes, Safari history directly):
     3. Full Disk Access

   The prompt appears ONCE per app, ever. If it gets dismissed while your
   terminal is in the background, it never comes back and everything fails
   silently. `tccutil reset` that pair and trigger it again in the foreground.
PERMS

echo
if [ "$DRY" = 1 ]; then
  say "Dry run finished. Nothing changed."
else
  say "Installed. Now run:"
  echo "   jarvis doctor"
  echo
  echo "   Then read $SRC/CLAUDE.md before controlling anything."
  echo "   The one rule: climb the layers. Never start at screenshots."
fi
