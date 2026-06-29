import AppKit
import Carbon.HIToolbox

/// Registers global system-wide hotkeys via Carbon `RegisterEventHotKey`.
///
/// Why Carbon and not an `NSEvent` global monitor: Carbon hotkeys fire even when
/// another app is focused, **without** the Accessibility permission, and they
/// actually *consume* the key so it doesn't leak to the focused app. That's the
/// right behavior for media hotkeys.
@MainActor
final class HotKeyManager {

    /// Invoked (on the main actor) when a registered hotkey fires.
    var onAction: ((ShortcutAction) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actionByID: [UInt32: ShortcutAction] = [:]
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x56504B59 // 'VPKY'

    init() { installHandler() }

    // MARK: - Carbon event handler (one for all hotkeys)

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // The callback must be a capture-free C function; we pass `self` through
        // `userData` and recover it inside.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr {
                    let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    let id = hkID.id
                    DispatchQueue.main.async { mgr.fire(id) }
                }
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )
    }

    private func fire(_ id: UInt32) {
        if let action = actionByID[id] { onAction?(action) }
    }

    // MARK: - (Re)registration

    /// Drop all current hotkeys and register the ones bound in `store`.
    func reload(from store: ShortcutStore) {
        unregisterAll()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = store.combo(for: action) else { continue }
            let id = UInt32(index + 1)
            let hotID = EventHotKeyID(signature: signature, id: id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                combo.keyCode, combo.carbonModifiers, hotID,
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
                actionByID[id] = action
            }
            // A non-noErr status usually means the combo is already taken by the
            // system or another app; we skip it silently (the UI still shows it).
        }
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actionByID.removeAll()
    }
}
