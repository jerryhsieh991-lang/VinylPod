import SwiftUI
import AppKit
import Carbon.HIToolbox

/// One recorded key combination (a non-modifier key + at least one modifier).
/// Stored in Carbon terms so it can be handed straight to `RegisterEventHotKey`.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32         // Carbon/AppKit virtual key code
    var carbonModifiers: UInt32 // cmdKey | shiftKey | optionKey | controlKey
    var display: String         // e.g. "⌘⇧P" — captured at record time

    /// Build a combo from a key-down NSEvent. Returns nil if no modifier is held
    /// (we require a modifier so shortcuts don't fire on plain typing).
    static func from(_ event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }

        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option)  { symbols += "⌥" }
        if flags.contains(.shift)   { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }

        let keyName = Self.keyName(for: event)
        guard !keyName.isEmpty else { return nil }

        return KeyCombo(keyCode: UInt32(event.keyCode),
                        carbonModifiers: carbon,
                        display: symbols + keyName)
    }

    /// Human-readable name for the pressed key (letters/digits via characters,
    /// special keys via a small keyCode table).
    private static func keyName(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        // Ignore pure-modifier presses.
        return chars.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]
}

/// Every action that can be bound to a global shortcut. Titles match the
/// "Keyboard shortcuts" window exactly.
enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case playPause
    case nextTrack
    case previousTrack
    case openPlayer
    case toggleNotch
    case toggleMenuBar
    case togglePopover
    case widgetSize
    case displayFullscreen
    case windowTopBottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause:        return "Play/pause"
        case .nextTrack:        return "Next track"
        case .previousTrack:    return "Previous track"
        case .openPlayer:       return "Open player"
        case .toggleNotch:      return "Toggle notch open"
        case .toggleMenuBar:    return "Toggle menu bar visibility"
        case .togglePopover:    return "Toggle popover"
        case .widgetSize:       return "Widget size"
        case .displayFullscreen:return "Display in fullscreen"
        case .windowTopBottom:  return "Window top/bottom"
        }
    }

    /// Visual grouping in the window (matches the three blocks in the screenshot).
    static let groups: [[ShortcutAction]] = [
        [.playPause, .nextTrack, .previousTrack, .openPlayer],
        [.toggleNotch, .toggleMenuBar, .togglePopover],
        [.widgetSize, .displayFullscreen, .windowTopBottom]
    ]
}

/// Persistent store of action → combo, backed by UserDefaults JSON.
@MainActor
final class ShortcutStore: ObservableObject {

    @Published private(set) var combos: [ShortcutAction: KeyCombo] = [:]

    /// Called whenever a binding changes so the HotKeyManager can re-register.
    var onChange: (() -> Void)?

    private let defaultsKey = "keyboardShortcuts"

    init() { load() }

    func combo(for action: ShortcutAction) -> KeyCombo? { combos[action] }

    func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        if let combo { combos[action] = combo } else { combos.removeValue(forKey: action) }
        save()
        onChange?()
    }

    func clear(_ action: ShortcutAction) { set(nil, for: action) }

    // MARK: - Persistence (JSON map keyed by raw action string)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let raw = try? JSONDecoder().decode([String: KeyCombo].self, from: data)
        else { return }
        var result: [ShortcutAction: KeyCombo] = [:]
        for (k, v) in raw { if let action = ShortcutAction(rawValue: k) { result[action] = v } }
        combos = result
    }

    private func save() {
        let raw = Dictionary(uniqueKeysWithValues: combos.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
