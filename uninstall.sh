#!/usr/bin/env bash
# Remove Infiniarchy: plugin link, CLI link, bind file and the loader block
# in hyprland.lua (backed up first). Pass --purge to also delete the config.
set -euo pipefail

PLUGIN_ID="io.github.lmajs.infiniarchy"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
MARK_BEGIN="-- >>> infiniarchy >>>"
MARK_END="-- <<< infiniarchy <<<"
STAMP="$(date +%s)"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true

if [[ -f "$HYPR_MAIN" ]] && grep -qF -- "$MARK_BEGIN" "$HYPR_MAIN"; then
  cp -p "$HYPR_MAIN" "$HYPR_MAIN.bak.$STAMP"
  python3 - "$HYPR_MAIN" "$MARK_BEGIN" "$MARK_END" <<'PY'
import re, sys
path, begin, end = sys.argv[1:4]
text = open(path).read()
text = re.sub(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "\n", text, flags=re.S)
open(path, "w").write(text)
PY
  say "Removed loader block from hyprland.lua (backup: $HYPR_MAIN.bak.$STAMP)"
fi

rm -f "$HOME/.config/hypr/infiniarchy.lua"
[[ -L "$HOME/.config/omarchy/plugins/$PLUGIN_ID" ]] && rm "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
[[ -L "$HOME/.local/bin/infiniarchy" ]] && rm "$HOME/.local/bin/infiniarchy"
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$HOME/.config/infiniarchy"
  say "Deleted ~/.config/infiniarchy"
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
hyprctl reload config-only >/dev/null 2>&1 || true
say "Infiniarchy removed."
