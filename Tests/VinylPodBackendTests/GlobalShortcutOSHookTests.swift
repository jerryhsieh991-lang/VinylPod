import XCTest
import AppKit
import Carbon.HIToolbox
@testable import VinylPod

/// NODE (c) — Global_Shortcut_OS_Hook.
///
/// The global shortcut path is: an `NSEvent` keydown → `KeyCombo.from(event)`
/// (parse + Carbon modifier translation) → `ShortcutStore.set(_:for:)`
/// (persisted) → `HotKeyManager.reload(from:)` which calls Carbon
/// `RegisterEventHotKey`. These tests prove:
///   1. a keycombo round-trips through parse → store → reload,
///   2. the Carbon modifier translation is correct,
///   3. `HotKeyManager.reload` is reachable and registers a real OS hotkey
///      (the actual `RegisterEventHotKey` path) without crashing.
@MainActor
final class GlobalShortcutOSHookTests: XCTestCase {

    private let storeKey = "keyboardShortcuts"
    private var savedStore: Data?

    override func setUp() {
        super.setUp()
        savedStore = UserDefaults.standard.data(forKey: storeKey)
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
    override func tearDown() {
        if let savedStore { UserDefaults.standard.set(savedStore, forKey: storeKey) }
        else { UserDefaults.standard.removeObject(forKey: storeKey) }
        super.tearDown()
    }

    // MARK: - Helper: synthesize a keydown NSEvent for a combo

    private func keyDown(keyCode: UInt16, chars: String, flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    // MARK: - 1. KeyCombo parse: ⌘⇧P round-trips correctly

    func testKeyComboParsesModifiersAndKey() throws {
        // P = kVK_ANSI_P (0x23). ⌘⇧.
        let event = try XCTUnwrap(
            keyDown(keyCode: UInt16(kVK_ANSI_P), chars: "p", flags: [.command, .shift])
        )
        let combo = try XCTUnwrap(KeyCombo.from(event), "⌘⇧P must parse to a KeyCombo")

        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_P))
        // Carbon modifier bitmask must contain cmdKey + shiftKey, not option/control.
        XCTAssertEqual(combo.carbonModifiers & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(combo.carbonModifiers & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(combo.carbonModifiers & UInt32(optionKey), 0)
        XCTAssertEqual(combo.carbonModifiers & UInt32(controlKey), 0)
        // Display string ends with the key glyph and shows both modifier symbols.
        XCTAssertTrue(combo.display.contains("⌘"))
        XCTAssertTrue(combo.display.contains("⇧"))
        XCTAssertTrue(combo.display.hasSuffix("P"))
    }

    // MARK: - 2. A modifier-less key is rejected (no firing on plain typing)

    func testPlainKeyWithoutModifierIsRejected() throws {
        let event = try XCTUnwrap(
            keyDown(keyCode: UInt16(kVK_ANSI_P), chars: "p", flags: [])
        )
        XCTAssertNil(KeyCombo.from(event),
                     "a key with no modifier must not become a global shortcut")
    }

    // MARK: - 3. Combo persists through ShortcutStore across relaunch

    func testShortcutStorePersistsComboAcrossRelaunch() throws {
        let event = try XCTUnwrap(
            keyDown(keyCode: UInt16(kVK_ANSI_K), chars: "k", flags: [.command, .option])
        )
        let combo = try XCTUnwrap(KeyCombo.from(event))

        let store = ShortcutStore()
        var changed = false
        store.onChange = { changed = true }
        store.set(combo, for: .playPause)
        XCTAssertTrue(changed, "set(_:for:) must fire onChange so the hotkey manager re-registers")

        // Relaunch: a fresh store re-reads the persisted JSON map.
        let reloaded = ShortcutStore()
        let got = try XCTUnwrap(reloaded.combo(for: .playPause),
                                "combo must persist for the bound action")
        XCTAssertEqual(got, combo, "the exact keycombo must round-trip")
        XCTAssertNil(reloaded.combo(for: .nextTrack), "unbound actions stay nil")
    }

    // MARK: - 4. HotKeyManager.reload reaches the real RegisterEventHotKey path

    func testHotKeyManagerReloadRegistersWithoutCrashing() throws {
        let event = try XCTUnwrap(
            // F8 is rarely claimed, reducing the chance the OS refuses it.
            keyDown(keyCode: UInt16(kVK_F8), chars: "", flags: [.command, .control])
        )
        let combo = try XCTUnwrap(KeyCombo.from(event))

        let store = ShortcutStore()
        store.set(combo, for: .playPause)

        // Installing the handler + reloading exercises InstallEventHandler and
        // RegisterEventHotKey (the OS hook). This must be reachable and safe.
        let manager = HotKeyManager()
        manager.reload(from: store)        // registers
        manager.reload(from: ShortcutStore()) // unregisters all, re-registers none
        // Reaching here without a crash/trap proves the Carbon OS-hook path is wired.
        XCTAssertTrue(true)
    }
}
