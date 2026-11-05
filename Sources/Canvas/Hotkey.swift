import Carbon.HIToolbox
import Foundation

/// A global hotkey via Carbon's RegisterEventHotKey. Works without Accessibility permission
/// and fires even while another app is frontmost — that's what makes "come back to the canvas" possible.
final class Hotkey {
    // Registration must not retain its owner: otherwise clearing a runtime's hotkeys never unregisters them.
    private final class WeakHotkey {
        weak var value: Hotkey?
        init(_ value: Hotkey) { self.value = value }
    }
    private static var registry: [UInt32: WeakHotkey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private let callback: @MainActor () -> Void
    private let repeats: Bool
    private var pressed = false
    private var ref: EventHotKeyRef?
    private(set) var registrationStatus: OSStatus = noErr
    var isRegistered: Bool { registrationStatus == noErr && ref != nil }

    init(keyCode: UInt32, modifiers: UInt32, repeats: Bool = true, callback: @escaping @MainActor () -> Void) {
        self.callback = callback
        self.repeats = repeats
        id = Hotkey.nextID
        Hotkey.nextID += 1
        Hotkey.registry[id] = WeakHotkey(self)
        Hotkey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x4341_4E56) /* 'CANV' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        registrationStatus = status
        if status != noErr { Log.note("Hotkey: RegisterEventHotKey failed (\(status))") }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Hotkey.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            if let hotkey = Hotkey.registry[hotKeyID.id]?.value {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    hotkey.pressed = false
                } else if hotkey.repeats || !hotkey.pressed {
                    hotkey.pressed = true
                    let cb = hotkey.callback
                    Task { @MainActor in cb() }
                }
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}
