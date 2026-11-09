# Caio's Sunlight fork

Fork: https://github.com/CaioFaSoares/sunlight. Issues and changes belong here, not upstream.

This is a patch set on top of upstream `main`, not a release frozen on one upstream version. The source
`Info.plist` stays exactly as upstream ships it; the built app is stamped
`<upstream>-caio.<FORK_REVISION>` with a build number derived from upstream's plus the revision.

Last synced: upstream 0.2.4 (`cf7aa16`), revision 13. The rebase conflicted in `CanvasController`,
`WindowCapture`, `Hotkey` and `RealWindowDriver`; every conflict was the fork's own change against
upstream's `Log.note` rewrite or its closed-by-app fix, and both sides were kept.

## Tracking upstream

`scripts/sync-upstream.sh` fetches `spacefarm-digital/sunlight`, rebases this patch set onto its `main`,
bumps `FORK_REVISION` when the base release changed, and optionally runs the tests. Resolve conflicts by
hand; never push to the upstream remote. `scripts/fork-version.sh` prints the derived version/build, and
`scripts/package.sh` stamps only the built app.

## Feature set

### #1 — Window discovery, including new private-browser windows

Window-server metadata is the source of truth in both renderers. A missing title or ScreenCaptureKit handle no longer prevents creating a tracked window. Capture handles are attached later, with bounded retry backoff rather than permanent suppression after three quick attempts. Accessibility frame fallback never substitutes a different known window ID or an ambiguous overlapping window.

This does not bypass macOS capture protections. A protected window can be tracked without being capturable; Live Windows and capture rendering have different capabilities. App/system utility windows outside the existing eligibility policy remain excluded.

### #2 — Configurable canvas controls

Settings → Keys & Mouse provides actions for toggling the canvas/last window, showing the overview, returning to the last window, zooming in, and zooming out. Assign a keyboard shortcut or middle/auxiliary mouse button, disable an action, or restore defaults. Defaults preserve Mission Control/F3 and its existing hold behavior. Custom shortcuts are press actions. Left/right mouse clicks are never intercepted. Bindings persist in the existing preferences domain and stop when Sunlight is off.

Global mouse bindings need Accessibility. Registration conflicts and missing permissions are shown in Settings. Some hardware utilities consume buttons before Sunlight sees them; macOS shortcuts may need to be released in System Settings.

### #3 — Rendering after display/canvas transitions

The live renderer retains the newest complete snapshot even when newer partial camera frames arrive while the Dock is busy. A partial frame cannot replace a pending membership/order/park-wake checkpoint. At most two frames are retained.

A display ownership transfer synchronously releases the source canvas's live lease before the destination can acquire the window, then rebuilds the source frame. Discovery and delayed capture-handle attachment respect current display ownership, so a stale response cannot recreate a proxy on the old display.

### #4 — New windows enter the canvas

When an app opens a window while the canvas is away, the add-on may lift it to the front level so the
app is usable. On return, those windows are now lowered together before the listing runs; otherwise the
listing rejects anything above the normal level and the window stays above every canvas, untracked.
The lift/lower bookkeeping is per canvas; on return the tracked windows are lowered, and the actual
listing is swept for any remaining front-level window (one lifted before this build, or whose
bookkeeping was lost) before reconciliation. Nothing is lowered while a canvas is in an entered window.

A new window is also claimed by the canvas the user is looking at when it is announced, even if the app
put it on another display; existing windows keep their display. It is then placed by the existing
`placeNewWindows` path: into the visible canvas, beside what is already there, or with the camera moved
just enough to reveal it. The fix does not broaden which windows are legitimate canvas material (menus,
system panels, overlays and tiny utility windows remain excluded).

### #5 — Overview on every display

With multiple displays, the Mission Control/F3 overview is now one desk-wide state: the first press fits
every display at once, so both canvases are zoomed out and windows on either can be rearranged. The
second press restores each canvas's previous camera. If the overview began in a window, the canvas that
had that window returns into it after restoring the others. The same path is used by See All, the
configured Show Overview/Toggle actions and the four-finger See All gesture. A single-display setup
keeps the old behaviour.

### #6 — Every display's windows keep to it

Each canvas places its windows in the desk's global coordinates (`Display`), but covers one display. A
window whose canvas place was past that display's edge therefore landed on a neighbouring display's
screen: the live renderer drew the real window there — at the canvas level, in that display's stacking
order — so it showed over the other canvas, and came back cut, stuck or occluded when the camera came
back. Capture proxies never showed it: they are subviews of their own canvas window. The parking margin
(one screen around the view) left such windows live, and with the display to the left or right of the
main one, a horizontal row of windows on the canvas walked straight into it.

A live frame now carries, per window, the part of the window's own points that is still on its canvas's
display (add-on sunlight-58, `SUNBEAM_FRAME_CLIPS`: 44-byte records, the clip after the transform), and
the add-on gives the window that shape with the window server's shape call — the one the Picture in
Picture tiles already use for their corners. A window wholly on its display gets its whole bounds, which
changes nothing; one hanging over the edge is cut at the edge, as a captured proxy was; one wholly off
its display is drawn as a single point of itself, so it keeps its place, its level and its lease but has
no pixel on any display. The window's own shape goes back whenever it is put back under the canvas,
handed off, or its lease ends, so a window used at 1:1 is never clipped to where it was on a canvas, and
a tile keeps its rounded corners. Single-display setups send no clips: nothing can show past the one
screen anyway.

The windows a handoff keeps on show around the entered one are real, at 1:1, in front of the canvas,
and no frame reaches them while the canvas is away: the handoff itself now carries each one's clip
(sunlight-59, 28-byte kept entries) and the add-on shapes them once they have landed, so a window kept beside the
entered one stays on show when it is on this display — whole, or cut at the edge — and one the app
raised out of view is shaped to nothing rather than put over another display. A window entered later,
from a canvas whose lease was dropped, has its clip put back by ID alone, so it never shows cut.

### #7 — Center the window in view

A canvas place is a global point, so a window can sit past the screen's edge — over another display's
screen area — while being perfectly reachable on the canvas. Settings › Keys & Mouse › **Center the
window in view** (and the window's right-click menu, **Center in View**) now glides the window in focus
to the middle of the visible area of the display you're looking at: the camera stays where it is, and the
windows around it stay on screen. The size is kept; a window bigger than the visible area keeps its
top-left in it, as entering one does. The window in focus is the one under the pointer, else the one
used last, else the topmost — the same rule ⌃⌥ and Tidy use. From inside a real window the canvas comes
forward first, as Tidy and Arrange do, then the window it was in is centered.

The movement is a `strength` away from the window's place towards the middle (1 is the middle): the
action is written so a Settings control for it can land on top without touching the geometry
(`CanvasController.centeredOrigin`).

### #8 — Entering a window centers it

Settings › Windows › **Entering a window centers it** (on by default) makes a click on the canvas take the
window to the middle of the visible area, the camera centring on it at 1:1, instead of entering it where
it is around the clicked spot. A window whose place on the canvas is past the screen's edge — over
another display's — is then entered on this screen, whole, rather than at the edge with part of it out of
view; the seam's in-place growth is what a click gets with the setting off. The plan still says a click
entered the window, so the way in lasts the double-click interval and a second click is never the app's.
The double-click / ⏎ entry is unchanged, and so is a pinch in (in place, the handoff gesture).

### #9 — One canvas, and the other screens stay clear

With Settings › Experimental › Multiple displays off, the main display's canvas is the only one. A
window's place on it is a global point, so a window can sit past the screen's edge — over another
display's area — and the live renderer used to draw it there; windows also drifted onto the other
display's canvas entirely and stayed there. Now every window is on that one canvas, never handed over to
another display, and the clip keeps what the canvas draws on its own display: nothing of it appears on
another screen. The clip applies with a single canvas too, since a desk can have displays the canvas
doesn't cover. A window an app opens on another display is taken onto the canvas through the new-window
path (fork #4), which places it in view, so it doesn't vanish there.

The setup window no longer opens at launch on a Mac already set up just because the add-on is missing
for the moment: a Dock restart at launch (takeover) unloads it and the canvas loads it back by itself.
Before, it opened on its last page at every such launch, with the canvas held back while it did.

### #10 — A released window stays on its canvas's display

With one canvas and a desk of more displays than it covers, a window's place on the canvas is a global
point, so a window can sit past the screen's edge — over another display's screen area. While the canvas
is up, sunlight-58's clip keeps it from drawing there. The canvas is not always up: when another app is
in front, Sunlight releases its live windows so they can be used, and a window the canvas had drawn at
1:1 is put back natively where the canvas drew it (sunlight-25/28, `sunbeam_settle`) — which on that desk
is the *other* display's screen. There the real window showed, whole, over that display, and the window
that was on the canvas here had vanished from it; navigating back to it and bring the canvas forward
made it jump between the two, and the WindowServer work that came with it stalled the Dock (the add-on
runs there) for seconds.

A canvas that doesn't cover the desk now says so in every live frame (`SUNBEAM_FRAME_CONFINE`,
add-on sunlight-60, set from `Display.all.count > canvases.count`). A window released at 1:1 from such a
canvas is moved natively onto the canvas's own display instead (`sunbeam_confined`), wholly on it, beside
the edge it went off, its title bar under the menu bar — so it is the window the canvas has, on the
screen it belongs to, and never a window on another screen. A window still on the canvas — even one
hanging over an edge — is left where it is: that is a window on its screen, as it is without a canvas.
The windows of an app that takes the front and stays above the canvas while the canvas goes behind it are
confined too (they are not ordered under the canvas, only placed on its display). On a desk the canvas covers (one display, or
a canvas per display) nothing changes: the flag is not sent, and a window put back out of view stays
where the canvas had it.

## Build and safety

Run `swift test`, then `make app SIGN="Apple Development: …"` (or use your own signing identity). The application keeps `com.spacefarm.sunlight` to preserve layout/preferences. A different signing team may require granting Accessibility/Screen Recording again and approving the background helper. Do not change SIP or other system protections to install this fork.

Official Sparkle updates are disabled in fork builds so an upstream update cannot silently replace these changes. Release/tap destinations are fork-owned; no releases are published by a local build.

Before replacing `/Applications/Sunlight.app`, quit it normally and back up the app, `defaults export com.spacefarm.sunlight`, and `~/Library/Application Support/Sunlight`. Restoring the original signed app restores its identity; never reset TCC as part of an upgrade.

## Verification boundaries

The current suite has 631 tests, covering discovery eligibility, malformed metadata, retry timing,
AX identity matching, persistence/input matching, preservation of full render checkpoints,
lift/lower bookkeeping for new windows, the clip geometry and clipped-frame layout of a
window on a display, the confine flag a canvas that doesn't cover the desk sends, and where Center in
View puts a window at each strength. The add-on's own harness (`LiveWindows/test-session.m`, fake window server)
covers the clip command: set once per change, left alone for a tile, put back at the lease's end
and on a handoff — and the confine geometry that keeps a released window on its canvas's display. The existing suite covers capture limits, camera/display coordinate conversion,
parking, wire serialization, and fake Dock socket leases. Real-app/private-window and multi-monitor
visual behavior also needs a live smoke test with the installed build; passing unit tests alone is
not proof that every app or monitor topology works.
