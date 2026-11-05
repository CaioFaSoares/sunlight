import SwiftUI

/// Explicit key selection avoids a global shortcut firing while the user is trying to record it.
struct CanvasBindingsSettingsView: View {
    @State private var config = Settings.canvasBindings
    @State private var editing: CanvasBindingAction?
    @State private var problems = CanvasBindingRuntime.problems

    var body: some View {
        Form {
            Section {
                ForEach(CanvasBindingAction.allCases) { action in
                    HStack {
                        RowLabel(title: action.title, subtitle: summary(action))
                        Spacer()
                        Button("Edit…") { editing = action }
                        Button("Disable") { set(action, triggers: []) }
                            .disabled(config.triggers(for: action).isEmpty)
                    }
                }
                Button("Restore All Defaults") {
                    Settings.resetCanvasBindings()
                    config = Settings.canvasBindings
                }
            } header: {
                SectionHeader(title: "Canvas keys & mouse", detail: "Global shortcuts, even while another app is in front. Each action can have a keyboard and a mouse binding.")
            } footer: {
                Text("Default: F3 / Mission Control toggles the overview; hold to pick a window. Custom shortcuts fire once per press. Plain letters and navigation keys require Command, Control or Option. Trackpad gestures are unchanged.")
            }
            Section {
                Text("Mouse buttons: 3 is middle, 4 and 5 are usually side buttons. Primary and secondary clicks stay with apps. Mouse bindings require Accessibility permission.")
                Text("Sunlight detects duplicates and its reserved commands. Other apps and macOS may still reserve a shortcut: change it here or in System Settings › Keyboard › Keyboard Shortcuts.")
                ForEach(problems, id: \.self) { Text($0).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { action in
            CanvasBindingEditor(action: action, config: config) { triggers in
                set(action, triggers: triggers)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Settings.canvasBindingsDidChange)) { _ in
            config = Settings.canvasBindings
        }
        .onReceive(NotificationCenter.default.publisher(for: CanvasBindingRuntime.statusDidChange)) { _ in
            problems = CanvasBindingRuntime.problems
        }
    }
    private func summary(_ action: CanvasBindingAction) -> String {
        let labels = config.triggers(for: action).map(\.label)
        return labels.isEmpty ? "Disabled" : labels.joined(separator: " · ")
    }
    private func set(_ action: CanvasBindingAction, triggers: [CanvasBindingTrigger]) {
        config.replace(action, with: triggers)
        Settings.canvasBindings = config
    }
}

private struct CanvasBindingEditor: View {
    let action: CanvasBindingAction
    let config: CanvasBindingConfiguration
    let save: ([CanvasBindingTrigger]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyboard = true
    @State private var key: UInt32 = 99
    @State private var mouse = false
    @State private var button = 4
    @State private var keyModifiers: CanvasBindingModifiers = []
    @State private var mouseModifiers: CanvasBindingModifiers = []

    /// macOS virtual keys; the key picker names the US physical position, not a layout-dependent character.
    private static let keys: [(UInt32, String)] = [
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"),
        (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"),
        (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"),
        (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
        (22, "6"), (26, "7"), (28, "8"), (25, "9"), (49, "Space"), (48, "Tab"),
        (36, "Return"), (53, "Escape"), (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        (24, "+ / ="), (27, "−"), (43, ","), (47, "."), (44, "/"), (50, "`"),
        (33, "["), (30, "]"), (41, ";"), (39, "'"), (42, "\\"), (51, "Delete"), (117, "Forward Delete")
    ] + CanvasBindingTrigger.functionKeys.map { ($0.key, $0.value) }.sorted { Int($0.1.dropFirst())! < Int($1.1.dropFirst())! }

    private var triggers: [CanvasBindingTrigger] {
        var result: [CanvasBindingTrigger] = []
        if keyboard { result.append(.init(kind: .keyboard, code: key, modifiers: keyModifiers)) }
        if mouse { result.append(.init(kind: .mouse, code: UInt32(button - 1), modifiers: mouseModifiers)) }
        return CanvasBindingConfiguration.editorTriggers(result, for: action)
    }
    private var error: String? {
        triggers.compactMap { config.conflict(for: $0, replacing: action) }.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.title).font(.headline)
            Toggle("Keyboard", isOn: $keyboard)
            if keyboard {
                Picker("Physical key (US position)", selection: $key) {
                    ForEach(Self.keys, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                modifiers($keyModifiers)
            }
            Toggle("Mouse", isOn: $mouse)
            if mouse {
                Stepper("Mouse button \(button)", value: $button, in: 3...32)
                modifiers($mouseModifiers)
            }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Restore Default") {
                    save(CanvasBindingConfiguration.defaults.triggers(for: action)); dismiss()
                }
                .disabled(CanvasBindingConfiguration.defaults.triggers(for: action).contains {
                    config.conflict(for: $0, replacing: action) != nil
                })
                .help("Restore All Defaults can also clear another action using F3.")
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(triggers); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(error != nil)
            }
        }
        .padding(24).frame(width: 480)
        .onAppear {
            let existing = config.triggers(for: action)
            let k = existing.first { $0.kind == .keyboard && $0.code != 160 }
            let m = existing.first { $0.kind == .mouse }
            keyboard = k != nil; mouse = m != nil
            key = k?.code ?? 99; keyModifiers = k?.modifiers ?? []
            button = Int(m?.code ?? 3) + 1; mouseModifiers = m?.modifiers ?? []
        }
    }
    private func modifiers(_ selection: Binding<CanvasBindingModifiers>) -> some View {
        HStack {
            ForEach([CanvasBindingModifiers.control, .option, .shift, .command], id: \.rawValue) { modifier in
                Toggle(modifier.label, isOn: Binding(get: { selection.wrappedValue.contains(modifier) }, set: { on in
                    if on { selection.wrappedValue.insert(modifier) } else { selection.wrappedValue.remove(modifier) }
                }))
                .toggleStyle(.checkbox)
            }
        }
    }
}
