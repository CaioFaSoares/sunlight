import AppKit

/// Global custom keys use Carbon (no Accessibility required); auxiliary mouse buttons need an event tap.
/// The two legacy overview keys stay in KeyTap, preserving its press/hold/release behavior.
@MainActor
final class CanvasBindingRuntime {
    static let statusDidChange = Notification.Name("SunlightCanvasBindingStatusDidChange")
    private(set) static var problems: [String] = []
    private let handler: (CanvasBindingAction) -> Void
    private var hotkeys: [Hotkey] = []
    private var mouse: CanvasBindingMouseTap?
    private var observer: NSObjectProtocol?
    private var enabled = false

    init(handler: @escaping (CanvasBindingAction) -> Void) {
        self.handler = handler
        observer = NotificationCenter.default.addObserver(forName: Settings.canvasBindingsDidChange,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
    func start() { enabled = true; reload() }
    func stop() {
        enabled = false
        hotkeys = []
        mouse?.stop()
        mouse = nil
        Self.problems = []
        NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
    }
    private func reload() {
        guard enabled else { return }
        hotkeys = []
        mouse?.stop()
        mouse = nil
        Self.problems = []
        let config = Settings.canvasBindings
        for binding in config.bindings where binding.trigger.kind == .keyboard {
            if binding.action == .toggleOverview && binding.trigger.isLegacyOverviewKey { continue }
            let hotkey = Hotkey(keyCode: binding.trigger.code, modifiers: binding.trigger.modifiers.carbon, repeats: false) { [weak self] in
                guard let self, self.enabled, Settings.sunlightOn else { return }
                self.handler(binding.action)
            }
            hotkeys.append(hotkey)
            if !hotkey.isRegistered {
                Self.problems.append("\(binding.trigger.label) could not be registered (\(hotkey.registrationStatus)); it may be used by another app.")
            }
        }
        let mouseBindings = config.bindings.filter { $0.trigger.kind == .mouse }
        if !mouseBindings.isEmpty {
            let tap = CanvasBindingMouseTap(bindings: mouseBindings) { [weak self] action in
                guard let self, self.enabled, Settings.sunlightOn else { return }
                self.handler(action)
            }
            mouse = tap
            if !tap.start() { Self.problems.append("Mouse bindings need Accessibility permission. Re-enable Sunlight after granting it.") }
        }
        NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
    }
}

/// Main-runloop tap: no AX or synchronous controller work runs in the callback. Unmatched events pass.
/// Claiming a down claims its matching up/drag, even if modifiers change before release.
final class CanvasBindingMouseTap {
    struct State {
        var bindings: [CanvasBinding]
        var held = Set<UInt32>()
        mutating func action(type: CGEventType, button: UInt32, modifiers: CanvasBindingModifiers) -> (swallow: Bool, action: CanvasBindingAction?) {
            if type == .otherMouseUp {
                return (held.remove(button) != nil, nil)
            }
            if type == .otherMouseDragged { return (held.contains(button), nil) }
            guard type == .otherMouseDown else { return (false, nil) }
            let trigger = CanvasBindingTrigger(kind: .mouse, code: button, modifiers: modifiers)
            guard let binding = bindings.first(where: { $0.trigger == trigger }) else { return (false, nil) }
            guard held.insert(button).inserted else { return (true, nil) }
            return (true, binding.action)
        }
    }
    private var state: State
    private let handler: @MainActor (CanvasBindingAction) -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    init(bindings: [CanvasBinding], handler: @escaping @MainActor (CanvasBindingAction) -> Void) {
        state = State(bindings: bindings)
        self.handler = handler
    }
    func start() -> Bool {
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<CanvasBindingMouseTap>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                tap.state.held = []
                if let port = tap.port { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let result = tap.state.action(type: type, button: UInt32(truncatingIfNeeded: event.getIntegerValueField(.mouseEventButtonNumber)), modifiers: CanvasBindingModifiers(flags: event.flags))
            if let action = result.action {
                let handler = tap.handler
                Task { @MainActor in handler(action) }
            }
            return result.swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
    func stop() {
        if let port { CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil; source = nil; state.held = []
    }
    deinit { stop() }
}
