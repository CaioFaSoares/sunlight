import AppKit
import XCTest
@testable import Canvas

final class CanvasBindingsTests: XCTestCase {
    private func key(_ code: UInt32, _ modifiers: CanvasBindingModifiers = []) -> CanvasBindingTrigger {
        .init(kind: .keyboard, code: code, modifiers: modifiers)
    }
    private func isolatedStore() -> CanvasBindingStore {
        CanvasBindingStore(defaults: UserDefaults(suiteName: "CanvasBindingsTests.\(UUID().uuidString)")!)
    }
    func testDefaultsPreserveF3AndMissionControlWithoutAddingMouseGrabs() {
        let config = CanvasBindingConfiguration.defaults
        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.triggers(for: .toggleOverview), [.missionControl, .f3])
        XCTAssertTrue(config.bindings.allSatisfy { $0.trigger.kind == .keyboard })
        XCTAssertTrue(config.triggers(for: .returnToWindow).isEmpty)
    }
    func testSavingDefaultF3FromEditorPreservesHardwareMissionControlPair() {
        XCTAssertEqual(CanvasBindingConfiguration.editorTriggers([.f3], for: .toggleOverview), [.missionControl, .f3])
        XCTAssertEqual(CanvasBindingConfiguration.editorTriggers([.f3], for: .showOverview), [.f3])
        XCTAssertEqual(CanvasBindingConfiguration.editorTriggers([], for: .toggleOverview), [])
        let custom = key(0, [.command, .shift])
        XCTAssertEqual(CanvasBindingConfiguration.editorTriggers([custom], for: .toggleOverview), [custom])
        XCTAssertEqual(CanvasBindingConfiguration.editorTriggers([.missionControl, .f3], for: .toggleOverview), [.missionControl, .f3])
    }
    func testAbsentOrCorruptPreferencesFallBackToDefaults() {
        let store = isolatedStore()
        defer { store.reset() }
        XCTAssertEqual(store.load(), .defaults)
        store.defaults.set(Data("not json".utf8), forKey: CanvasBindingStore.key)
        XCTAssertEqual(store.load(), .defaults)
        store.defaults.set("old invalid format", forKey: CanvasBindingStore.key)
        XCTAssertEqual(store.load(), .defaults)
    }
    func testCustomKeyboardMouseDisableAndResetRoundTrip() {
        let store = isolatedStore()
        defer { store.reset() }
        var config = CanvasBindingConfiguration.defaults
        config.replace(.toggleOverview, with: [])
        config.replace(.showOverview, with: [key(0, [.command, .shift]), .init(kind: .mouse, code: 3)])
        config.replace(.returnToWindow, with: [key(15, [.control, .shift])])
        XCTAssertTrue(store.save(config))
        XCTAssertEqual(store.load(), config)
        XCTAssertTrue(store.load().triggers(for: .toggleOverview).isEmpty)
        store.reset()
        XCTAssertEqual(store.load(), .defaults)
    }
    func testDisabledAllDoesNotResurrectDefaultsOnNextLaunch() {
        let store = isolatedStore()
        defer { store.reset() }
        XCTAssertTrue(store.save(.init(bindings: [])))
        XCTAssertEqual(store.load().bindings, [])
    }
    func testUnknownVersionAndUnsafeSavedBindingFallBack() throws {
        let store = isolatedStore()
        defer { store.reset() }
        var config = CanvasBindingConfiguration.defaults
        config.version = 99
        store.defaults.set(try JSONEncoder().encode(config), forKey: CanvasBindingStore.key)
        XCTAssertEqual(store.load(), .defaults)
        config.version = 1
        config.replace(.showOverview, with: [key(0)])
        XCTAssertFalse(store.save(config))
        store.defaults.set(try JSONEncoder().encode(config), forKey: CanvasBindingStore.key)
        XCTAssertEqual(store.load(), .defaults)
    }
    func testPlainAndShiftOnlyTypingKeysAreNeverValidGlobalBindings() {
        for code: UInt32 in [0, 49, 36, 53, 123, 124, 125, 126] {
            XCTAssertNotNil(key(code).validationError)
            XCTAssertNotNil(key(code, .shift).validationError)
            XCTAssertNil(key(code, [.command, .control, .shift]).validationError)
        }
        XCTAssertNil(key(99).validationError)
        XCTAssertNil(key(100, .shift).validationError)
    }
    func testKnownSunlightConflictsAreRejected() {
        for trigger in [key(48, .command), key(3, [.command, .control]), key(44, [.command, .shift]), key(0, [.control, .option]), key(103), key(45, .command), key(123, .control), key(124, .command)] {
            XCTAssertNotNil(trigger.validationError, trigger.label)
        }
        XCTAssertNil(key(0, [.command, .shift]).validationError)
    }
    func testPrimaryAndSecondaryMouseButtonsCannotBeConfigured() {
        for code: UInt32 in [0, 1, 32, UInt32.max] {
            XCTAssertNotNil(CanvasBindingTrigger(kind: .mouse, code: code).validationError)
        }
        for code: UInt32 in [2, 3, 4, 31] {
            XCTAssertNil(CanvasBindingTrigger(kind: .mouse, code: code).validationError)
        }
    }
    func testDuplicateConflictsDoNotPreventReplacingSameAction() {
        let config = CanvasBindingConfiguration.defaults
        XCTAssertNil(config.conflict(for: .f3, replacing: .toggleOverview))
        XCTAssertNotNil(config.conflict(for: .f3, replacing: .showOverview))
        var duplicate = config
        duplicate.bindings.append(.init(action: .showOverview, trigger: .f3))
        XCTAssertFalse(duplicate.isValid)
    }
    func testUnknownModifierBitsAndInvalidKeyCodesAreRejected() {
        XCTAssertNotNil(key(0, .init(rawValue: 16)).validationError)
        XCTAssertNotNil(key(UInt32.max, .command).validationError)
        XCTAssertNotNil(key(128, .command).validationError)
    }
    func testModifiersMatchExactlyIgnoringUnrelatedEventFlags() {
        XCTAssertEqual(CanvasBindingModifiers(flags: [.maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn]), [.command, .shift])
        XCTAssertNotEqual(key(0, .command), key(0, [.command, .shift]))
        XCTAssertEqual(key(0, [.command, .shift]).label, "⇧⌘A")
    }
    func testLegacyKeysPassWhenRemappedOrDisabled() {
        var state = KeyTap.State()
        state.overviewKeys = []
        XCTAssertEqual(KeyTap.action(keyCode: 160, flags: [], state: &state), .pass)
        XCTAssertEqual(KeyTap.action(keyCode: 99, flags: [], state: &state), .pass)
        XCTAssertEqual(KeyTap.action(keyCode: 0, flags: [], state: &state), .pass)
        XCTAssertEqual(KeyTap.release(keyCode: 99, state: &state, timestamp: 1), .pass)
    }
    func testF3RetainsHoldAndReleaseSemantics() {
        var state = KeyTap.State()
        XCTAssertEqual(KeyTap.action(keyCode: 99, flags: [], state: &state, timestamp: 1_000_000_000), .send(.missionControl))
        state.swallowed.insert(99)
        XCTAssertEqual(KeyTap.action(keyCode: 99, flags: [], state: &state, autorepeat: true), .swallow)
        XCTAssertEqual(KeyTap.release(keyCode: 160, state: &state, timestamp: 1_100_000_000), .pass)
        XCTAssertEqual(KeyTap.release(keyCode: 99, state: &state, timestamp: 1_500_000_000), .send(.missionControlUp(held: 0.5)))
        XCTAssertEqual(KeyTap.release(keyCode: 99, state: &state, timestamp: 2_000_000_000), .pass)
    }
    func testModifiedLegacyKeysAreNotSwallowedByDefault() {
        for flags: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift] {
            var state = KeyTap.State()
            XCTAssertEqual(KeyTap.action(keyCode: 99, flags: flags, state: &state), .pass)
            XCTAssertEqual(KeyTap.action(keyCode: 160, flags: flags, state: &state), .pass)
        }
    }
    func testMouseOnlySwallowsExactConfiguredPressAndPairedRelease() {
        var state = CanvasBindingMouseTap.State(bindings: [.init(action: .showOverview, trigger: .init(kind: .mouse, code: 3, modifiers: .command))])
        XCTAssertFalse(state.action(type: .otherMouseDown, button: 3, modifiers: []).swallow)
        XCTAssertFalse(state.action(type: .otherMouseDown, button: 2, modifiers: .command).swallow)
        XCTAssertFalse(state.action(type: .otherMouseUp, button: 3, modifiers: .command).swallow)
        let down = state.action(type: .otherMouseDown, button: 3, modifiers: .command)
        XCTAssertTrue(down.swallow)
        XCTAssertEqual(down.action, .showOverview)
        XCTAssertNil(state.action(type: .otherMouseDown, button: 3, modifiers: .command).action)
        XCTAssertTrue(state.action(type: .otherMouseDragged, button: 3, modifiers: []).swallow)
        XCTAssertTrue(state.action(type: .otherMouseUp, button: 3, modifiers: []).swallow)
        XCTAssertFalse(state.action(type: .otherMouseUp, button: 3, modifiers: []).swallow)
    }
}
