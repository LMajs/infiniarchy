# omarchy-canvas

An infinite canvas for [Omarchy](https://omarchy.org/). Every app window is its
own free-floating item on one endless plane, and your desktop is a viewport onto
that plane. Press **Right Alt + Q** and the desktop zooms out into the canvas
(seen through a curved "lens"), with live thumbnails of every window from every
workspace. Drag windows to arrange them, pan and zoom around, then click a
window and the canvas zooms back into it. Arranging only changes the canvas:
your real desktop stays tiled the way Hyprland lays it out (unless you opt into
"Arrange the real desktop too", below).

It runs inside the Omarchy shell (Quickshell) as an overlay plugin, so opening
it is an IPC call into an already-running process. It follows your Omarchy
theme's colors and fonts.

## Install

Requires Omarchy with the Lua Hyprland config (Hyprland 0.55+) and the
`omarchy-shell` Quickshell host.

```bash
git clone <this repo> ~/Projects/omarchy-canvas   # or keep it where it is
~/Projects/omarchy-canvas/install.sh
```

The installer:

| What | Where |
|------|-------|
| Plugin (symlink) | `~/.config/omarchy/plugins/lmajs.canvas` → `plugin/` |
| CLI (symlink) | `~/.local/bin/omarchy-canvas` → `bin/omarchy-canvas` |
| Settings | `~/.config/omarchy-canvas/config.json` |
| Generated bind file | `~/.config/hypr/omarchy-canvas.lua` |
| Loader block (marked `>>> omarchy-canvas >>>`) | end of `~/.config/hypr/hyprland.lua` |

`hyprland.lua` and `~/.config/omarchy/shell.json` are backed up to
`*.bak.<timestamp>` before they are touched. Your own `bindings.lua` is never
edited. Re-running the installer is safe.

Uninstall with `./uninstall.sh` (add `--purge` to delete the settings too).

## Use

| | Click | Drag |
|---|---|---|
| **Left** | on a window: go to it · on the background: clear selection | a window: move it (with its chain and the selection) · the background: pan |
| **Middle** | on a window: close it | anywhere: pan |
| **Right** | on a window: unlink it (see below) · on the background: clear selection | anywhere: box-select windows |

- **Linking:** drop a window right next to, above or below another and they
  link up (a thin line bridges the gap); dragging one moves the whole chain.
- **Unlinking:** right-click a lone window to drop all its links. Right-drag to
  select several windows, then right-click one of them: the selection keeps
  its links inside but is cut loose from every unselected window.
- **Keyboard:** Right Alt + Q (or your hotkey) toggles, Esc clears the
  selection / closes, hold `W` `A` `S` `D` to pan, `Q` / `E` jump to the
  previous / next window and centre it, arrows or `hjkl` select, Enter goes
  there, Shift + arrows move the selected window (and its chain), `U` unlinks
  it, Tab cycles, `+`/`-` zoom, `0`/`F` fit, Ctrl + , settings (the panel ends
  with a "How to navigate" reference of every control).
- **Zoom:** mouse wheel (smooth), pinch, Ctrl + two-finger scroll; two-finger
  scroll pans. Double-click the background or the grid button to fit everything.
- **Flat view:** keep zooming in and, past a threshold, the dark curved
  overview lights up and jumps to a straight, flat 1:1 view of the canvas
  (like the reference video). Pan, arrange and click windows there as usual;
  scroll out to drop back into the curved overview. Toggle: "Flat view when
  zoomed in".

Canvas positions persist in `~/.local/state/omarchy-canvas/layout.json`,
including across restarts: a window of the same app reopens in the spot the
previous one had. The minimap (bottom right) shows the whole canvas and your
view; click or drag in it to jump around.

### Optional: arrange the real desktop too

Off by default. With **Arrange the real desktop too** on (settings, or
`omarchy-canvas config set canvasDesktop true`), going to a window or a spot
makes that workspace a viewport onto the canvas, like the reference video:

- every window inside the screen-sized view floats at its canvas position, so
  neighbours sit partly off-screen at the edges,
- windows in view from **other workspaces are moved onto this one**. That's
  how you move windows between workspaces: drag them next to each other on the
  canvas and go there,
- windows already on that workspace but outside the view are parked off-screen
  at their canvas positions,
- windows you open on a canvas workspace float next to the window you were
  using, inside the view,
- moving a floating window on the desktop moves it on the canvas too, and
  dragging a window in the overview moves the real window right away.

Workspaces you never "go to" are left alone (tiled as usual) until you do.
To undo everything:

```bash
omarchy-canvas release    # windows go back to their original workspace and tiling
```

(or **Release windows** in settings). Switching the setting off in the panel
releases windows automatically.

## Change the hotkey

**In the canvas:** open settings (slider button or Ctrl + ,), press **R** or
click **Change**, press the new shortcut, then **Enter** / **Save**. If the
shortcut is already used by another bind, the panel says what it is used for
and the button becomes **Replace**. While recording, all Hyprland shortcuts are
paused so you can record the current one too; it gives up after 20 seconds.
(`SUPER + CTRL + SHIFT + ALT + ESCAPE` also exits recording.)

**From a terminal:**

```bash
omarchy-canvas hotkey                      # show current
omarchy-canvas hotkey set "SUPER + O"      # change
omarchy-canvas hotkey set "SUPER + RETURN" --replace   # take over a used key
omarchy-canvas hotkey reset                # back to RALT + Q
omarchy-canvas settings                    # open the settings panel
```

Modifiers: `SUPER`, `CTRL`, `SHIFT`, `ALT` (either Alt), `RALT` (right Alt
only). The key is any xkb key name (`Q`, `F5`, `SPACE`, `GRAVE`, `PAGE_UP`...).
The CLI validates the key, refuses keys that are already bound unless you pass
`--replace`, rewrites `~/.config/hypr/omarchy-canvas.lua`, reloads Hyprland, and
rolls back if Hyprland reports an error.

### Why Right Alt needs a trick

On a plain `us` layout, Right Alt is an ordinary Alt (keysym `Alt_R`,
modifier `ALT`), so Hyprland can't tell Left and Right Alt apart by modifier.
The generated bind listens on `ALT + Q`, checks `hl.is_key_down("Alt_R")`, and
opens the canvas only for Right Alt. For Left Alt it returns
`{ pass_event = true }`, so **Left Alt + Q still reaches your apps**. If you
ever switch to a layout where Right Alt is AltGr (`ISO_Level3_Shift`), a second
`MOD5 + Q` bind covers that case.

## Other settings

`~/.config/omarchy-canvas/config.json` (also editable from the settings panel;
the overlay picks changes up live):

| Key | Default | Meaning |
|-----|---------|---------|
| `hotkey` | `"RALT + Q"` | Change with `omarchy-canvas hotkey set`, not by hand |
| `lens` | `0.55` | Lens curvature, `0` = flat, `1` = strongest |
| `liveThumbnails` | `true` | Stream window contents; `false` = one snapshot per open |
| `showMinimap` | `true` | Minimap in the corner |
| `showLabels` | `false` | Always show window titles (otherwise on hover/selection) |
| `showDots` | `true` | Dot grid on the canvas background |
| `showHints` | `true` | One-line control hints at the bottom of the canvas |
| `attachWindows` | `true` | Windows dropped edge to edge chain together and move as a group |
| `flatView` | `true` | Zooming in past a threshold snaps to a flat 1:1 view of the canvas |
| `canvasDesktop` | `false` | Going to a spot also arranges the real workspace like the canvas |

```bash
omarchy-canvas config set lens 0.3
omarchy-canvas config set liveThumbnails false
```

## How it works

- `plugin/CanvasModel.js`: the canvas model. It merges `hyprctl -j
  clients/workspaces/monitors` with the saved layout: known windows keep their
  spot, windows on canvas workspaces take their position from the desktop, and
  new windows are placed next to the focused one (or claim the saved spot of a
  closed window of the same app). `landingPlan()` turns "workspace W shows
  viewport V" into Hyprland Lua (`hl.dsp.window.move/float/resize`), touching
  only windows that actually change.
- `plugin/Canvas.qml`: the overlay (layer-shell, focused monitor). Live
  thumbnails via Quickshell's `ScreencopyView` (hyprland-toplevel-export, works
  for hidden workspaces too), a `ScriptModel` so tiles survive refreshes,
  dragging with snapping, smooth zoom and landing animations. It stays loaded, so
  it also places new windows on canvas workspaces while the overlay is closed.
- `plugin/shaders/lens.frag`: barrel distortion, vignette and rim fade.
  Pointer hit-testing runs the same mapping in JS, so clicks and drags land on
  what you see. `dots.frag` draws the infinite dot grid.
- `bin/omarchy-canvas`: Python CLI (stdlib only) for config, the hotkey bind
  and `release`.

## Development

```bash
# Rebuild shaders after editing plugin/shaders/*.frag
/usr/lib/qt6/bin/qsb --qt6 -o plugin/shaders/lens.frag.qsb plugin/shaders/lens.frag
/usr/lib/qt6/bin/qsb --qt6 -o plugin/shaders/dots.frag.qsb plugin/shaders/dots.frag

# The overlay is keepLoaded (so it can animate out), which means code changes
# need a shell restart to take effect:
omarchy restart shell
```

Test helpers in `tools/` use real input devices (your user has an ACL on
`/dev/uinput`), so Hyprland sees genuine keycodes:

```bash
tools/press-keys.py RIGHTALT+Q          # press a real chord
tools/pointer.py click 960 540          # warp + click
tools/probe.py status                   # overlay state over shell IPC
tools/demo-v2.sh /tmp/demo.mp4          # scripted v2 run with throwaway windows (+ recording)
tools/test-chains.py                    # chain / group-drag / detach test with throwaway windows
tools/test-gestures.py                  # full mouse-scheme test (select, unlink, close, pan)
tools/test-flat-view.py [out.mp4]       # scroll into the flat view, pan, scroll back out
```

## Limitations

- By default the canvas arrangement doesn't carry over to the real desktop
  (windows stay tiled). The optional desktop sync floats windows and can move
  them between workspaces; `omarchy-canvas release` undoes it.
- The desktop viewport moves only through the canvas (go to a spot); there's
  no separate "pan the desktop" gesture outside the overview.
- Freshly opened windows on hidden workspaces can show an app-icon placeholder
  until they have rendered once.
- The overlay opens on the focused monitor; I only tested with one monitor.
- Live thumbnails of many large windows cost GPU while the canvas is open. Turn
  off `liveThumbnails` if that matters.
- Recording shortcut punctuation assumes US key positions.
