# Caio's Sunlight fork

Fork: https://github.com/CaioFaSoares/sunlight. Issues and changes belong here, not upstream.

This is a patch set on top of upstream `main`, not a release frozen on one upstream version. The source
`Info.plist` stays exactly as upstream ships it; the built app is stamped
`<upstream>-caio.<FORK_REVISION>` with a build number derived from upstream's plus the revision.

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

## Build and safety

Run `swift test`, then `make app SIGN="Apple Development: …"` (or use your own signing identity). The application keeps `com.spacefarm.sunlight` to preserve layout/preferences. A different signing team may require granting Accessibility/Screen Recording again and approving the background helper. Do not change SIP or other system protections to install this fork.

Official Sparkle updates are disabled in fork builds so an upstream update cannot silently replace these changes. Release/tap destinations are fork-owned; no releases are published by a local build.

Before replacing `/Applications/Sunlight.app`, quit it normally and back up the app, `defaults export com.spacefarm.sunlight`, and `~/Library/Application Support/Sunlight`. Restoring the original signed app restores its identity; never reset TCC as part of an upgrade.

## Verification boundaries

The current suite has 588 tests, covering discovery eligibility, malformed metadata, retry timing,
AX identity matching, persistence/input matching, preservation of full render checkpoints, and
lift/lower bookkeeping for new windows. The existing suite covers capture limits, camera/display
coordinate conversion, parking, wire serialization, and fake Dock socket leases. Real-app/private-window
and multi-monitor visual behavior also needs a live smoke test with the installed build; passing unit
tests alone is not proof that every app or monitor topology works.
