import AppKit
import Carbon.HIToolbox

/// Physical key codes, not typed characters: bindings remain stable when the input source changes.
enum CanvasBindingAction: String, Codable, CaseIterable, Identifiable {
    case toggleOverview, showOverview, returnToWindow, centerInView, zoomIn, zoomOut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggleOverview: return "Canvas ↔ last window"
        case .showOverview: return "Show overview"
        case .returnToWindow: return "Return to last window"
        case .centerInView: return "Center the window in view"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        }
    }
}

struct CanvasBindingModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32
    static let command = Self(rawValue: 1)
    static let control = Self(rawValue: 2)
    static let option = Self(rawValue: 4)
    static let shift = Self(rawValue: 8)
    static let all: Self = [.command, .control, .option, .shift]
    init(rawValue: UInt32) { self.rawValue = rawValue }
    init(flags: CGEventFlags) {
        self = []
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskShift) { insert(.shift) }
    }
    var carbon: UInt32 {
        (contains(.command) ? UInt32(cmdKey) : 0) |
        (contains(.control) ? UInt32(controlKey) : 0) |
        (contains(.option) ? UInt32(optionKey) : 0) |
        (contains(.shift) ? UInt32(shiftKey) : 0)
    }
    var label: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") +
        (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

struct CanvasBindingTrigger: Codable, Hashable {
    enum Kind: String, Codable { case keyboard, mouse }
    var kind: Kind
    /// CG key code, or zero-based mouse button (2 = middle, 3 = first side button).
    var code: UInt32
    var modifiers: CanvasBindingModifiers = []

    static let missionControl = Self(kind: .keyboard, code: 160)
    static let f3 = Self(kind: .keyboard, code: 99)
    var isLegacyOverviewKey: Bool { self == .missionControl || self == .f3 }
    static let functionKeys: [UInt32: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
    static let physicalKeys: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
        1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 48: "Tab", 36: "Return", 53: "Escape", 123: "←", 124: "→", 125: "↓", 126: "↑",
        24: "+ / =", 27: "−", 43: ",", 47: ".", 44: "/", 50: "`", 33: "[", 30: "]", 41: ";", 39: "'", 42: "\\", 51: "Delete", 117: "Forward Delete"
    ]
    var label: String {
        let key: String
        if kind == .mouse { key = code == 2 ? "Middle mouse" : "Mouse button \(code + 1)" }
        else if code == 160 { key = "Mission Control" }
        else { key = Self.functionKeys[code] ?? Self.physicalKeys[code] ?? "Key \(code)" }
        return modifiers.label + key
    }
    var validationError: String? {
        guard modifiers.subtracting(.all).isEmpty else { return "Unsupported modifiers." }
        if kind == .mouse {
            return (2...31).contains(code) ? nil : "Use a middle or auxiliary mouse button (3–32)."
        }
        guard code <= 127 || code == 160 else { return "Invalid keyboard key code." }
        if modifiers.intersection([.command, .control, .option]).isEmpty,
           Self.functionKeys[code] == nil, code != 160 {
            return "Global letter and navigation keys need Command, Control or Option."
        }
        // Existing takeover/tiling commands win; do not silently register over them.
        if code == 103 && modifiers.intersection([.command, .control, .option]).isEmpty {
            return "F11 is reserved for Show Desktop."
        }
        if modifiers.contains([.control, .option]) { return "Control–Option is reserved for window commands." }
        if (123...126).contains(code), modifiers == .control {
            return "Control–arrow is reserved for Spaces and Mission Control."
        }
        if (123...126).contains(code), modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) {
            return "Command–arrow is reserved for the app switcher."
        }
        if code == 48 && modifiers.contains(.command) { return "Command–Tab is reserved for switching apps." }
        if code == 3 && modifiers == [.command, .control] { return "Control–Command–F is reserved for full screen." }
        if code == 44 && modifiers.contains(.command) { return "Command–? is reserved for help." }
        if code == 45 && modifiers == .command { return "Command–N is reserved for new windows." }
        return nil
    }
}

struct CanvasBinding: Codable, Equatable {
    var action: CanvasBindingAction
    var trigger: CanvasBindingTrigger
}

struct CanvasBindingConfiguration: Codable, Equatable {
    var version = 1
    var bindings: [CanvasBinding]
    static let defaults = Self(bindings: [
        CanvasBinding(action: .toggleOverview, trigger: .missionControl),
        CanvasBinding(action: .toggleOverview, trigger: .f3)
    ])
    /// The editor shows F3 as one choice, but its dedicated Apple hardware variant is a second key code.
    static func editorTriggers(_ triggers: [CanvasBindingTrigger], for action: CanvasBindingAction) -> [CanvasBindingTrigger] {
        guard action == .toggleOverview, triggers.contains(.f3), !triggers.contains(.missionControl) else { return triggers }
        return [.missionControl] + triggers
    }
    func triggers(for action: CanvasBindingAction) -> [CanvasBindingTrigger] {
        bindings.filter { $0.action == action }.map(\.trigger)
    }
    func action(for trigger: CanvasBindingTrigger) -> CanvasBindingAction? {
        bindings.first { $0.trigger == trigger }?.action
    }
    func conflict(for trigger: CanvasBindingTrigger, replacing action: CanvasBindingAction) -> String? {
        if let error = trigger.validationError { return error }
        if let other = bindings.first(where: { $0.action != action && $0.trigger == trigger }) {
            return "Already used by \(other.action.title)."
        }
        return nil
    }
    mutating func replace(_ action: CanvasBindingAction, with triggers: [CanvasBindingTrigger]) {
        bindings.removeAll { $0.action == action }
        bindings += triggers.map { CanvasBinding(action: action, trigger: $0) }
    }
    var isValid: Bool {
        version == 1 && bindings.allSatisfy {
            $0.trigger.validationError == nil && ($0.trigger.code != 160 ||
                ($0.trigger.kind == .keyboard && $0.trigger.modifiers.isEmpty && $0.action == .toggleOverview))
        } &&
        Set(bindings.map(\.trigger)).count == bindings.count
    }
}

/// Injectable defaults keep persistence tests away from the application's real preferences.
struct CanvasBindingStore {
    static let key = "CanvasInputBindings"
    var defaults: UserDefaults
    func load() -> CanvasBindingConfiguration {
        guard let data = defaults.data(forKey: Self.key),
              let config = try? JSONDecoder().decode(CanvasBindingConfiguration.self, from: data), config.isValid else {
            return .defaults
        }
        return config
    }
    @discardableResult func save(_ config: CanvasBindingConfiguration) -> Bool {
        guard config.isValid, let data = try? JSONEncoder().encode(config) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
    func reset() { defaults.removeObject(forKey: Self.key) }
}

extension Settings {
    static let canvasBindingsDidChange = Notification.Name("SunlightCanvasBindingsDidChange")
    static var canvasBindings: CanvasBindingConfiguration {
        get { CanvasBindingStore(defaults: .standard).load() }
        set {
            guard CanvasBindingStore(defaults: .standard).save(newValue) else { return }
            NotificationCenter.default.post(name: canvasBindingsDidChange, object: nil)
        }
    }
    static func resetCanvasBindings() {
        CanvasBindingStore(defaults: .standard).reset()
        NotificationCenter.default.post(name: canvasBindingsDidChange, object: nil)
    }
}
