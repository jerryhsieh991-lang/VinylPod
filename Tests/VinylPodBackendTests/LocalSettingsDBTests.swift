import XCTest
@testable import VinylPod

/// NODE (b) — Local_Settings_DB.
///
/// `AppSettings` is the app's local settings store, persisted to
/// `UserDefaults`. Each property writes on `didSet` and is re-read in `init()`.
/// These tests prove a write → read round-trip SURVIVES a simulated relaunch:
/// we mutate a fresh `AppSettings`, then construct a brand-new `AppSettings`
/// (the relaunch) and assert it re-reads the persisted value from the store.
///
/// To avoid polluting the real user domain, every test runs against an isolated
/// `UserDefaults` suite that is registered as `.standard`-equivalent by writing
/// through the same keys `AppSettings` uses, and is wiped in tearDown.
@MainActor
final class LocalSettingsDBTests: XCTestCase {

    // AppSettings reads/writes `UserDefaults.standard`. We snapshot and restore
    // the specific keys it touches so the developer's real prefs are untouched.
    private let keys = [
        "windowMode", "desktopLayer", "useAdaptiveAccent", "customBackgroundURL",
        "musicSource", "vinylStyle", "showProgress", "keepWindowInFront",
        "dynamicNotch", "showInMenuBar", "launchAtLogin", "showArtworkInDock",
        "hideDockIcon", "coverArtAsWallpaper", "hideNotchInFullscreen"
    ]
    private var saved: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        for k in keys { saved[k] = d.object(forKey: k) }
        for k in keys { d.removeObject(forKey: k) }
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for k in keys {
            if let v = saved[k], let value = v { d.set(value, forKey: k) }
            else { d.removeObject(forKey: k) }
        }
        saved.removeAll()
        super.tearDown()
    }

    // MARK: - Boolean toggle survives relaunch

    func testBooleanToggleRoundTripsAcrossRelaunch() {
        let a = AppSettings()
        // Defaults: launchAtLogin = false. Flip it.
        a.launchAtLogin = true
        a.showProgress = false           // default true → flip
        a.coverArtAsWallpaper = true     // default false → flip

        // Simulate relaunch: brand new instance re-reads from the store.
        let b = AppSettings()
        XCTAssertTrue(b.launchAtLogin, "launchAtLogin must persist across relaunch")
        XCTAssertFalse(b.showProgress, "showProgress=false must persist")
        XCTAssertTrue(b.coverArtAsWallpaper, "coverArtAsWallpaper must persist")
    }

    // MARK: - Enum-backed settings survive relaunch

    func testEnumSettingsRoundTripAcrossRelaunch() {
        let a = AppSettings()
        a.windowMode = .desktopWidget
        a.musicSource = .appleMusic
        a.vinylStyle = .vinyl
        a.desktopLayer = .back

        let b = AppSettings()
        XCTAssertEqual(b.windowMode, .desktopWidget)
        XCTAssertEqual(b.musicSource, .appleMusic)
        XCTAssertEqual(b.vinylStyle, .vinyl)
        XCTAssertEqual(b.desktopLayer, .back)
    }

    // MARK: - URL-backed setting survives relaunch

    func testCustomBackgroundURLRoundTrips() {
        let url = URL(fileURLWithPath: "/tmp/vinylpod-test-bg.png")
        let a = AppSettings()
        a.customBackgroundURL = url

        let b = AppSettings()
        XCTAssertEqual(b.customBackgroundURL, url,
                       "customBackgroundURL must persist across relaunch")
    }

    // MARK: - Defaults are honored on a clean store (no stale reads)

    func testDefaultsOnCleanStore() {
        // setUp removed all keys → a fresh AppSettings must use code defaults.
        let a = AppSettings()
        XCTAssertEqual(a.windowMode, .small,         "default windowMode")
        XCTAssertFalse(a.launchAtLogin,              "default launchAtLogin=false")
        XCTAssertTrue(a.showProgress,                "default showProgress=true")
        XCTAssertTrue(a.useAdaptiveAccent,           "default useAdaptiveAccent=true")
        XCTAssertEqual(a.musicSource, .spotify,      "default musicSource")
    }
}
