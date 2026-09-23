#!/usr/bin/env bash
# Install Infiniarchy for the current user.
#
#   - links this checkout into ~/.config/omarchy/plugins/io.github.lmajs.infiniarchy
#     (skipped when it already lives there, e.g. after `omarchy plugin add`)
#   - links the CLI to ~/.local/bin/infiniarchy
#   - writes ~/.config/infiniarchy/config.json (if missing) and the generated
#     bind file ~/.config/hypr/infiniarchy.lua
#   - adds a small, marked loader block to ~/.config/hypr/hyprland.lua
#     (backed up first) so the bind file is sourced after your own bindings
#   - enables the plugin and reloads Hyprland
#
# Safe to re-run.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.lmajs.infiniarchy"
PLUGIN_LINK="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_LINK="$HOME/.local/bin/infiniarchy"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
MARK_BEGIN="-- >>> infiniarchy >>>"
MARK_END="-- <<< infiniarchy <<<"
STAMP="$(date +%s)"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

for cmd in hyprctl python3 omarchy-shell omarchy; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done
[[ -f "$HYPR_MAIN" ]] || die "$HYPR_MAIN not found (this installer targets Omarchy's Lua Hyprland config)"

link() {
  local target="$1" link="$2"
  mkdir -p "$(dirname "$link")"
  if [[ -L "$link" ]]; then
    ln -sfn "$target" "$link"
  elif [[ -e "$link" ]]; then
    mv "$link" "$link.bak.$STAMP"
    warn "moved existing $link to $link.bak.$STAMP"
    ln -s "$target" "$link"
  else
    ln -s "$target" "$link"
  fi
}

say "Linking CLI → $BIN_LINK"
chmod +x "$REPO/bin/infiniarchy"
link "$REPO/bin/infiniarchy" "$BIN_LINK"

if [[ "$(realpath -m "$PLUGIN_LINK")" == "$REPO" ]]; then
  say "Plugin already installed at $PLUGIN_LINK"
else
  say "Linking plugin → $PLUGIN_LINK"
  link "$REPO" "$PLUGIN_LINK"
fi

say "Writing config and bind file"
"$BIN_LINK" apply --no-reload

if ! grep -qF -- "$MARK_BEGIN" "$HYPR_MAIN"; then
  cp -p "$HYPR_MAIN" "$HYPR_MAIN.bak.$STAMP"
  say "Backed up hyprland.lua → $HYPR_MAIN.bak.$STAMP"
  cat >>"$HYPR_MAIN" <<EOF

$MARK_BEGIN
-- Infiniarchy hotkey (managed by $REPO/install.sh).
-- The bind lives in hypr/infiniarchy.lua; change it with: infiniarchy hotkey set "..."
do
  local infiniarchy_binds = (os.getenv("HOME") or "") .. "/.config/hypr/infiniarchy.lua"
  local f = io.open(infiniarchy_binds, "r")
  if f then
    f:close()
    dofile(infiniarchy_binds)
  end
end
$MARK_END
EOF
  say "Added loader block to hyprland.lua"
else
  say "hyprland.lua already loads infiniarchy"
fi

plugin_enabled() {
  omarchy-shell shell listPlugins 2>/dev/null | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
sys.exit(0 if any(p.get("id") == sys.argv[1] and p.get("enabled") for p in plugins) else 1)' "$PLUGIN_ID"
}

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 0.5
if plugin_enabled; then
  say "omarchy-shell plugin already enabled"
else
  say "Enabling omarchy-shell plugin"
  [[ -f "$SHELL_JSON" ]] && cp -p "$SHELL_JSON" "$SHELL_JSON.bak.$STAMP"
  omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 \
    || omarchy-shell shell setPluginEnabled "$PLUGIN_ID" true >/dev/null 2>&1 || true
  plugin_enabled || warn "could not enable $PLUGIN_ID; run: omarchy plugin enable $PLUGIN_ID"
fi

say "Reloading Hyprland"
hyprctl reload config-only >/dev/null
sleep 0.4
errors="$(hyprctl configerrors 2>/dev/null || true)"
if [[ -n "${errors//[[:space:]]/}" && "$errors" != *"no errors"* ]]; then
  warn "hyprctl configerrors reports:"
  printf '%s\n' "$errors" >&2
fi

# The overlay is keepLoaded; a hot rescan of an already-loaded copy can leave
# the host without a live instance, so fall back to a clean shell restart.
sleep 1
if [[ "$(omarchy-shell shell call "$PLUGIN_ID" status '' 2>/dev/null)" != \{* ]]; then
  say "Restarting omarchy-shell to load the overlay"
  omarchy restart shell >/dev/null 2>&1 || warn "run: omarchy restart shell"
  sleep 3
fi

"$BIN_LINK" status
hotkey="$("$BIN_LINK" hotkey)"
echo
say "Done. Press $hotkey to open Infiniarchy."
echo "    Change the hotkey:  infiniarchy hotkey set \"SUPER + O\"   (or the gear icon in the canvas)"
