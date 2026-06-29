import XCTest
import AppKit
import Combine
@testable import VinylPod

/// NODE (d) — Memory_Leak_Prevention.
///
/// The 24/7 backend nodes own listeners/timers/closures that must NOT form
/// retain cycles, or a long-running session leaks. We assert via deinit
/// tracking that each owner deallocates when released:
///   • `BrowserBridge` — its NWConnection/listener handlers all capture
///     `[weak self]`; releasing the bridge must free it.
///   • `SettingsEffects` — holds `Set<AnyCancellable>` and `[weak self]` sinks
///     bound to a *live* `AppSettings`; the subscriptions must not retain it.
///   • `NowPlayingService.externalControl` — the app wires this as
///     `{ [weak bridge] in bridge?.send($0) }`; we prove the analogous weak
///     wiring lets the bridge die while the service lives.
@MainActor
final class MemoryLeakPreventionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // SettingsEffects touches `NSApp` (an implicitly-unwrapped
        // `NSApplication!`) in its Dock-policy sink. In the app, `start()` runs
        // from `applicationDidFinishLaunching`, so `NSApp` is always non-nil
        // there. In a headless XCTest host `NSApp` is nil until the shared
        // application is materialized — referencing `.shared` sets `NSApp`, so
        // the leak assertion can exercise the real sinks without tripping the
        // implicit unwrap. (See finding: SettingsEffects.applyDockPolicy.)
        _ = NSApplication.shared
    }

    // MARK: - BrowserBridge deallocates (no retained closures keep it alive)

    func testBrowserBridgeDeallocates() {
        weak var weakBridge: BrowserBridge?
        autoreleasepool {
            let svc = NowPlayingService()
            // Use a non-default port so we never collide with a running app's 8787.
            let bridge = BrowserBridge(nowPlaying: svc, port: 8799)
            weakBridge = bridge
            // We intentionally do NOT call start() (no live socket needed to prove
            // the object graph is cycle-free); construction wires the closures.
            XCTAssertNotNil(weakBridge)
        }
        XCTAssertNil(weakBridge, "BrowserBridge must deallocate — a retained self-capturing closure would leak it")
    }

    // MARK: - SettingsEffects deallocates while subscribed to a live AppSettings

    func testSettingsEffectsDeallocatesWhileObserving() {
        let settings = AppSettings()       // lives past the effects instance
        let svc = NowPlayingService()
        weak var weakEffects: SettingsEffects?

        autoreleasepool {
            let effects = SettingsEffects(settings: settings, nowPlaying: svc)
            weakEffects = effects
            effects.start()                // installs the Combine sinks
            // Emit changes so the sinks actually run at least once.
            settings.showArtworkInDock.toggle()
            settings.coverArtAsWallpaper.toggle()
            XCTAssertNotNil(weakEffects)
        }
        // settings is STILL alive here; if a sink captured self strongly, the
        // publisher (owned by settings) would keep effects alive → leak.
        XCTAssertNil(weakEffects, "SettingsEffects leaked: a Combine sink retained self")
        XCTAssertNotNil(settings, "the AppSettings it observed is intentionally still alive")
    }

    // MARK: - Weak externalControl wiring lets the bridge die independently

    func testExternalControlWeakWiringDoesNotRetainBridge() {
        let svc = NowPlayingService()
        weak var weakBridge: BrowserBridge?

        autoreleasepool {
            let bridge = BrowserBridge(nowPlaying: svc, port: 8798)
            weakBridge = bridge
            // Mirror AppDelegate's wiring exactly: weak capture of the bridge.
            svc.externalControl = { [weak bridge] action in bridge?.send(action) }
            XCTAssertNotNil(weakBridge)
        }
        // The service still holds the closure, but it captures the bridge weakly,
        // so the bridge must be freed.
        XCTAssertNil(weakBridge, "externalControl must capture the bridge weakly")
        // The dangling closure is safe to call (weak ref is now nil → no-op).
        svc.externalControl?(.playpause)
    }

    // MARK: - ShortcutStore.onChange weak wiring (AppDelegate uses [weak hotKeys])

    func testHotKeyManagerDeallocatesDespiteStoreOnChange() {
        let store = ShortcutStore()        // outlives the manager
        weak var weakManager: HotKeyManager?

        autoreleasepool {
            let manager = HotKeyManager()
            weakManager = manager
            // Mirror AppDelegate: onChange captures the manager weakly.
            store.onChange = { [weak manager] in manager?.reload(from: store) }
            store.set(nil, for: .playPause) // fire onChange
            XCTAssertNotNil(weakManager)
        }
        XCTAssertNil(weakManager, "HotKeyManager leaked via ShortcutStore.onChange strong capture")
    }
}
