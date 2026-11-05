// Local, opt-in Live Windows smoke test. Run with: swift scripts/smoke-displays.swift
// Creates and moves ONLY its own disposable window; never inspects other apps' titles/content.
// It deliberately never activates itself, so Sunlight can stay on the canvas throughout. Press the
// Mission Control key first to bring the canvas up, then run this from a terminal. The check is
// window-server visibility/level across display ownership changes, not pixel-perfect rendering.
import AppKit
import CoreGraphics

private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DisplaySmoke {
    let app = NSApplication.shared
    var window: NSWindow!
    var failures = 0
    var observations = 0
    var screens: [NSScreen] = []
    var stage = 0
    var warned = false
    let sunlightPID: pid_t?

    init() {
        sunlightPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spacefarm.sunlight")
            .first?.processIdentifier
    }

    func start() {
        screens = NSScreen.screens
        guard screens.count >= 2 else {
            print("SKIP: connect at least two displays")
            exit(2)
        }
        waitForCanvas(deadline: Date().addingTimeInterval(120))
    }

    /// The canvas is brought up by its own global key, not by another process: wait for the user to
    /// press Mission Control instead of stealing activation (which LSUIElement ignores anyway).
    func waitForCanvas(deadline: Date) {
        guard let pid = sunlightPID, let sun = NSRunningApplication(processIdentifier: pid), !sun.isTerminated else {
            print("SKIP: Sunlight is not running")
            exit(2)
        }
        if sun.isActive {
            begin()
            return
        }
        guard Date() < deadline else {
            print("SKIP: canvas was not brought to the front within 120 s")
            exit(2)
        }
        if !warned {
            warned = true
            print("WAITING: press Mission Control/F3 to bring Sunlight's canvas to the front…")
            fflush(stdout)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in waitForCanvas(deadline: deadline) }
    }

    func begin() {
        app.setActivationPolicy(.accessory)
        // A nonactivating panel shows at layer 0 (so Sunlight tracks it) without taking activation
        // away from the canvas: a normal window ordered front can make its app frontmost.
        let panel = NonKeyPanel(contentRect: CGRect(x: 0, y: 0, width: 520, height: 300),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        window = panel
        window.isReleasedWhenClosed = false
        window.title = "Sunlight — disposable display regression probe"
        window.backgroundColor = .systemTeal
        let label = NSTextField(labelWithString: "Sunlight display round trip\nDisposable test window — closes automatically")
        label.frame = CGRect(x: 30, y: 100, width: 460, height: 80)
        label.font = .systemFont(ofSize: 20)
        label.textColor = .white
        window.contentView?.addSubview(label)
        place(on: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in observe() }
    }

    func place(on index: Int) {
        let screen = screens[index].visibleFrame
        window.setFrameOrigin(CGPoint(x: screen.midX - 260, y: screen.midY - 150))
        window.orderFrontRegardless()
    }

    func observe() {
        let id = CGWindowID(window.windowNumber)
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        let own = entries.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
        let visible = own?[kCGWindowIsOnscreen as String] as? Bool ?? false
        let level = (own?[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let canvasFront = front == "com.spacefarm.sunlight"
        // Layer 1 is the canvas's owned-window level; 2 is its front/entered level. Layer 0 means the
        // window server no longer has it under the canvas.
        let managed = visible && level >= 1 && canvasFront
        observations += 1
        if !managed { failures += 1 }
        print("\(managed ? "PASS" : "FAIL") stage=\(stage) screen=\(stage % screens.count) ownWindow=\(id) onscreen=\(visible) level=\(level) canvasFront=\(canvasFront) front=\(front)")
        fflush(stdout)

        stage += 1
        guard stage < 7 else {
            window.close()
            print("Live Windows smoke: \(observations - failures)/\(observations) observations passed across \(screens.count) displays.")
            print("Visual confirmation of the window's pixels is still required.")
            exit(failures == 0 ? 0 : 1)
        }
        // Move to the other display, then back, then once more: each leg exercises a canvas transfer.
        place(on: stage % screens.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in observe() }
    }
}

let smoke = DisplaySmoke()
DispatchQueue.main.async { smoke.start() }
NSApplication.shared.run()
