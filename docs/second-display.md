# A second display

What Sunlight can and can't do with more than one screen, as this fork builds it (upstream 0.2.4 plus
the fork's patches). The reference desk is a 2560×1440 main display at `(0, 0)` and a 2294×1490 one at
`(2560, 0)` — side by side, different sizes, different scales.

## Two modes

Settings › Experimental › **Multiple displays** decides which of the two the app is in. It is off by
default and applies at once (the canvases are made and retired as displays are when plugged).

| | **On** — a canvas per display | **Off** — one canvas |
| --- | --- | --- |
| Screens | each display has its own canvas window | only the main display has one; the others are macOS's own |
| Windows | each window is on the canvas of the display it's on (`Desk.owner`) | every window is on the one canvas |
| Moving one | a real move to the other display, or ⌃⌥⇧ →/← | a real move keeps it on the canvas — its place is a global point |
| Drawing | each canvas draws only its display; live windows are clipped to it (sunlight-58) | nothing of the canvas is drawn on another screen (same clip) and a released window is kept on the canvas's display (sunlight-60) |

Both modes share one world: global coordinates, the main display's top-left at zero, y down, points. A
canvas's camera is its own (remembered per display UUID), and a window's *place* is the same number on
every canvas — only the canvas it belongs to changes when it moves.

## What works

- **A canvas on every display.** Live or captured, with its own camera, minimap, background, PiP chrome
  and Dock icon handling. On the add-on that holds a lease per canvas (sunlight-13 and up; this fork
  ships 60), every display is live. With an older add-on only the lead canvas is live and the others
  show pictures through Screen Recording.
- **One window in use at a time, across the desk.** Entering a window on the other display leaves the
  first canvas in place and brings the other forward; the kept windows around it stay where they are.
- **The Mission Control key is desk-wide** (fork #5). The first press fits every display at once; the
  second restores each canvas's camera, and returns into the window the overview started in, if any.
  See All and the four-finger gesture use the same path.
- **Moving a window between displays.** Window › Move to Next Display (⌃⌥⇧ →/←) takes the window in
  focus to the middle of the next display's visible area and to its canvas. A move made from inside the
  window (dragging it in the app) is followed the same way; the old canvas lets go before the new one
  takes it, and the window's place is redrawn on its new canvas.
- **Windows can overlap displays.** A canvas place is global, so a window can hang over an edge or sit
  entirely past it. Live windows are clipped to their own display: a window hanging over the edge is
  cut at the seam, and one entirely off the display draws a single point of itself — it keeps its place,
  level and lease but has no pixel on any screen. Single-display setups send no clips.
- **The handoff's kept windows** are real, at 1:1, in front of the canvas; their clips ride along with
  the handoff (sunlight-59), so a window kept beside the entered one stays on this display, cut at the
  edge, and one the app raised out of view is shaped to nothing instead of showing on another screen.
- **New windows.** A window announced while the canvas is away (or opened by an app on the other
  display) is claimed by the canvas the person is looking at, placed in view there and entered — rather
  than left untransformed on the other display (fork #4).
- **The other screens in one-canvas mode** are untouched: their desktop, their windows at their own
  level. Sunlight's clip and the reopened window path mean nothing of the canvas appears on them, and
  windows whose canvas place lies there stay on the canvas.

## What doesn't work, or has a limit

- **macOS always draws something on the second display.** In one-canvas mode that is the real desktop,
  with the windows macOS has there. Sunlight doesn't cover it and doesn't draw on it. Replacing that
  desktop with a canvas is exactly what Multiple displays does (and what costs a second canvas window,
  a second backdrop and a lease).
- **A window can't be both native on another display and drawn by the canvas.** While the canvas is up
  the live window is a transformed, leased window at the canvas's level, clipped to the display. When
  the canvas steps aside for another app, the window has to be somewhere real: sunlight-60 puts it back
  on its canvas's display, so it no longer appears whole on the other screen — but it is then a window
  of that display, not a window at its canvas place.
- **A window entirely past the display's edge has no pixels anywhere while the canvas is up.** That is
  deliberate (it keeps its place and comes back as the camera reaches it), but it means a window can
  look "lost" until you pan or zoom to it; Center in View and Entering a window centers it (both in
  Settings › Keys & Mouse / Windows) bring it back to the middle of the screen.
- **Native full-screen apps** own a Space of their own; a canvas can't cover them, and an entered
  window that goes full screen is kept only as a known-away window until it comes back.
- **Spaces are one Desktop per display, the canvas's.** Other Desktops are folded into it (their windows
  moved there, the empty ones removed), full-screen Spaces are left alone. Folding another app's window
  between Desktops and removing a Desktop only work through the Dock add-on (sunlight-55): with SIP on
  Sunlight's own process can't, so with an older add-on folding is a no-op that says so.
- **One Sunlight, one Dock add-on.** The add-on lives in the Dock's process: up to eight leases (one
  per canvas), and a second copy of Sunlight (or a different app asking) is turned away while they last.
  A Dock restart unloads it; every live canvas falls back to pictures until the app loads it back.
- **Frame size.** A live frame carries at most 128 windows — 92 when every record carries a clip — the
  ones nearest the view; further windows wait under the backdrop until the camera brings them near.
- **Cost of clipping.** A shape is a window-server call of its own, made whenever a window's clip
  changes. During a camera move across the seam that is a call per window per change; the clip is
  compared in the add-on and a repeated one costs nothing, but a long, continuous pan over many
  overhanging windows is the most expensive thing the live renderer does.
- **Picture in Picture is this screen's.** Moving a window to another display ends its tile; tiles don't
  follow to other Spaces or over full-screen apps.
- **Layouts and widgets are the main display's.** Saved layouts, the widget gallery and the desktop
  floor act on the lead canvas only; a display's camera is remembered, its windows are remembered in the
  one layout, per display, when layouts learn to restore them.
- **A change of main display starts every canvas over** (the lid closed on an external display): global
  coordinates move under every window, so each is listed afresh where it is now, at home.
- **The app can still put a window on the other display while the canvas is away.** Sunlight isn't in
  control then (its windows are the app's for the duration); on the next release the window is kept on
  its canvas's display again, but a move made in that window by the app is the app's to make.
- **No SIP changes, no virtual displays.** Everything here is public window-server state or the Dock
  add-on's own calls; nothing asks for a display the system doesn't have.

## What the fork adds to this

- `#5` desk-wide overview: one key press fits every display, the second restores them.
- `#6` clips: live windows can't be drawn on another display, and neither can the windows a handoff
  keeps on show (sunlight-58/59).
- `#7` Center in View: a window whose place is over another display comes to the middle of the screen
  the camera is looking at, without moving the camera.
- `#8` Entering a window centers it: a click takes it to the middle of the visible area, so entering a
  window whose place is past the edge doesn't enter it half out of view.
- `#9` one canvas, every window on it, nothing of it on another screen.
- `#10` a window released at 1:1 is kept on the canvas's display (sunlight-60), never on another screen
  while the canvas is away.

## How this is checked

The unit suite covers the display geometry (`Display.quartz`, `index(for:)`, the home camera), ownership
across canvases, the clip geometry and clipped-frame layout, the confine flag, and the handoff's kept
clips. The add-on's harness (`LiveWindows/test-session.m`) covers the wire side: clip set once per
change, left alone for a tile, cleared at the lease's end, and `sunbeam_confined` keeping a released
window on the canvas's display. None of that proves a real desk: pixel-level behavior across two
monitors — the seam, the release, a Space switch, a full-screen app — needs the live smoke test
(`scripts/smoke-displays.swift`) against an installed build, with the log at
`~/Library/Logs/Sunlight/Sunlight.log` open.
