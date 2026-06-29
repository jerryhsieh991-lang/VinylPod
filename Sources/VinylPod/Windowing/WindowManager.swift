import SwiftUI
import AppKit
import CoreGraphics

/// Owns VinylPod's on-screen panels and is the ONLY thing that touches
/// `NSWindow` state. It hosts SwiftUI views produced by injected factories; it
/// never builds playback UI itself, and it never touches audio/playback.
@MainActor
final class WindowManager {

    // MARK: Dependencies

    private let settings: AppSettings
    /// Factory that returns the SwiftUI view to host for a given mode.
    private let content: (WindowMode) -> AnyView
    /// Factory for the optional top-center dynamic island.
    private let dynamicIslandContent: (@escaping (Bool) -> Void) -> AnyView

    // MARK: Window state

    /// The single reusable window. Recreated ONLY when the required style mask
    /// must change (widget ⇄ non-widget), since those need different chrome.
    private var window: NSWindow?
    /// The mode the current `window` was built for.
    private var currentMode: WindowMode?
    /// Hosting controller for the SwiftUI content; we reuse it when only the
    /// content needs to change.
    private var hostingController: NSHostingController<AnyView>?

    /// Separate notch/dynamic-island panel so the widget can remain anywhere.
    private var dynamicIslandWindow: NSPanel?
    private var dynamicIslandHostingController: NSHostingController<AnyView>?
    private var dynamicIslandExpanded = false

    private let originDefaultsKey = "vinylWindowOrigin"

    // MARK: Init

    init(settings: AppSettings,
         content: @escaping (WindowMode) -> AnyView,
         dynamicIslandContent: @escaping (@escaping (Bool) -> Void) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.settings = settings
        self.content = content
        self.dynamicIslandContent = dynamicIslandContent
    }

    // MARK: - Public API

    /// Create the window for `mode` (if needed), host `content(mode)`, size,
    /// position, and show it.
    func show(_ mode: WindowMode) {
        let window = ensureWindow(for: mode)
        hostContent(for: mode, in: window)
        sizeAndPosition(window, for: mode, animated: false)

        window.makeKeyAndOrderFront(nil)
        if mode == .desktopWidget {
            // The widget is visual-first decor; it should not steal focus and
            // must adopt the persisted front/behind layer immediately.
            window.orderFront(nil)
            apply(desktopLayer: settings.desktopLayer)
        }
        currentMode = mode
        syncDynamicIsland()
    }

    /// Switch the current window to a new mode WITHOUT recreating playback.
    /// Resizes around the window's CENTER (grows/shrinks in place) and swaps the
    /// hosted content. If the style class changes (widget ⇄ non-widget) the
    /// window must be recreated, but audio is untouched either way.
    func apply(mode: WindowMode) {
        guard window != nil else {
            // Nothing on screen yet — treat as initial show.
            show(mode)
            return
        }

        let needsNewWindow = styleClassChanged(from: currentMode, to: mode)
        if needsNewWindow {
            // Style mask differs — rebuild the window, but keep the same content
            // factory so the hosted SwiftUI tree (and thus its environment-bound
            // playback state) is recreated cleanly without touching audio.
            recreateWindow(for: mode)
            return
        }

        guard let window else { return }
        hostContent(for: mode, in: window)
        sizeAndPosition(window, for: mode, animated: true)
        currentMode = mode

        if mode == .desktopWidget {
            apply(desktopLayer: settings.desktopLayer)
        }
        syncDynamicIsland()
    }

    /// Show/hide the top-center dynamic island based on the persisted setting.
    func syncDynamicIsland() {
        if settings.dynamicNotch {
            showDynamicIsland()
        } else {
            hideDynamicIsland()
        }
    }

    /// Apply the desktop-widget stacking layer. Only meaningful in
    /// `.desktopWidget` mode.
    ///
    /// - `.front`: float above ALL windows.
    /// - `.back`:  sit BELOW the desktop icons (behind everything).
    func apply(desktopLayer: DesktopLayer) {
        guard currentMode == .desktopWidget, let window else { return }

        switch desktopLayer {
        case .front:
            // Above normal windows AND above other floating helpers. The status
            // window level sits above .floating, putting the widget on top.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
            window.collectionBehavior = [.stationary, .ignoresCycle]

        case .back:
            // THE SUBTLE PART — "behind desktop icons".
            //
            // macOS draws the desktop icons in a window that lives at the
            // `kCGDesktopIconWindowLevelKey` level. To sit *behind* those icons
            // we must drop to the `kCGDesktopWindowLevelKey` level (the desktop
            // wallpaper layer), which is strictly below the icon layer. We read
            // that level via CGWindowLevelForKey(.desktopWindow) rather than
            // hardcoding a magic number, so it tracks the OS.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            // Stay pinned to this screen/Space, but do not join every Space.
            window.collectionBehavior = [.stationary, .ignoresCycle]
        }
    }

    /// Apply window stacking from the in-art "Window behavior" popover, in ANY
    /// mode. In the desktop widget this defers to the desktop-icon-aware logic;
    /// for the floating card modes it maps to ordinary window levels.
    ///   - `.front`: float above other app windows.
    ///   - `.back`:  drop to the normal level so other windows can cover it
    ///               (full behind-desktop-icons placement only applies to the widget).
    func applyStacking(_ layer: DesktopLayer) {
        guard let window else { return }
        if currentMode == .desktopWidget {
            apply(desktopLayer: layer)
            return
        }
        switch layer {
        case .front: window.level = .floating
        case .back:  window.level = .normal
        }
    }

    // MARK: - Window construction

    /// Returns the existing window if it already matches the style class for
    /// `mode`, otherwise builds a fresh one.
    private func ensureWindow(for mode: WindowMode) -> NSWindow {
        if let window, !styleClassChanged(from: currentMode, to: mode) {
            return window
        }
        let window = makeWindow(for: mode)
        self.window = window
        return window
    }

    private func makeWindow(for mode: WindowMode) -> NSWindow {
        let isWidget = (mode == .desktopWidget)

        // Borderless + non-activating panel: no title bar, never becomes the
        // active app's key window in a disruptive way. Good fit for a calm
        // now-playing companion.
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: mode.defaultSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        // Transparent, chrome-free background so the SwiftUI content can render
        // rounded corners / glass itself.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = !isWidget
        panel.isMovable = !isWidget
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // Non-activating panels shouldn't steal key/main from the user's apps.
        panel.becomesKeyOnlyIfNeeded = true

        if isWidget {
            // Full-screen decor: no shadow, transparent, accepts mouse so
            // hover-reveal controls work. It stays pinned to the chosen screen
            // and intentionally does not join every Space.
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.stationary, .ignoresCycle]
        } else {
            // Small/Normal/Large: a floating rounded card with a drop shadow,
            // above normal windows since it's a now-playing companion.
            panel.hasShadow = true
            panel.level = .floating
            panel.ignoresMouseEvents = false
        }

        return panel
    }

    /// Rebuild the window when the style class changes between widget and
    /// non-widget. Audio/playback is owned by Core and is never touched here.
    private func recreateWindow(for mode: WindowMode) {
        let old = window
        hostingController = nil
        window = nil

        let fresh = makeWindow(for: mode)
        window = fresh
        hostContent(for: mode, in: fresh)
        sizeAndPosition(fresh, for: mode, animated: false)

        fresh.makeKeyAndOrderFront(nil)
        old?.orderOut(nil)
        old?.close()

        currentMode = mode
        if mode == .desktopWidget {
            apply(desktopLayer: settings.desktopLayer)
        }
        syncDynamicIsland()
    }

    // MARK: - Content hosting

    /// Host (or re-host) `content(mode)` in the window via NSHostingController.
    private func hostContent(for mode: WindowMode, in window: NSWindow) {
        let view = content(mode)

        if let controller = hostingController {
            // Reuse the controller and just swap the root view so we never tear
            // down the hosting layer unnecessarily.
            controller.rootView = view
            if window.contentView !== controller.view {
                window.contentView = controller.view
            }
        } else {
            let controller = NSHostingController(rootView: view)
            hostingController = controller
            window.contentView = controller.view
        }
        // Let the hosted SwiftUI content show through the transparent window.
        window.contentView?.wantsLayer = true
    }

    // MARK: - Dynamic island panel

    private func showDynamicIsland() {
        let panel = dynamicIslandWindow ?? makeDynamicIslandWindow()
        dynamicIslandWindow = panel
        hostDynamicIslandContent(in: panel)
        sizeAndPositionDynamicIsland(panel, expanded: dynamicIslandExpanded, animated: false)
        panel.orderFront(nil)
    }

    private func hideDynamicIsland() {
        dynamicIslandHostingController = nil
        dynamicIslandWindow?.orderOut(nil)
        dynamicIslandWindow?.close()
        dynamicIslandWindow = nil
        dynamicIslandExpanded = false
    }

    private func makeDynamicIslandWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: dynamicIslandFrame(expanded: false),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        // Stay on the current screen/Space; do not follow every desktop.
        panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }

    private func hostDynamicIslandContent(in window: NSWindow) {
        let view = dynamicIslandContent { [weak self] expanded in
            Task { @MainActor [weak self] in
                self?.setDynamicIslandExpanded(expanded)
            }
        }

        if let controller = dynamicIslandHostingController {
            controller.rootView = view
            if window.contentView !== controller.view {
                window.contentView = controller.view
            }
        } else {
            let controller = NSHostingController(rootView: view)
            dynamicIslandHostingController = controller
            window.contentView = controller.view
        }
        window.contentView?.wantsLayer = true
    }

    private func setDynamicIslandExpanded(_ expanded: Bool) {
        dynamicIslandExpanded = expanded
        guard let dynamicIslandWindow else { return }
        sizeAndPositionDynamicIsland(dynamicIslandWindow, expanded: expanded, animated: true)
    }

    private func sizeAndPositionDynamicIsland(_ window: NSWindow, expanded: Bool, animated: Bool) {
        let targetFrame = dynamicIslandFrame(expanded: expanded)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func dynamicIslandFrame(expanded: Bool) -> NSRect {
        let screen = window?.screen?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = expanded ? CGSize(width: 430, height: 700) : CGSize(width: 390, height: 30)
        let topInset: CGFloat = expanded ? 0 : 3
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.maxY - size.height - topInset
        )
        return NSRect(origin: origin, size: size)
    }

    // MARK: - Sizing & positioning

    private func sizeAndPosition(_ window: NSWindow, for mode: WindowMode, animated: Bool) {
        let targetFrame: NSRect

        if mode == .desktopWidget {
            // Widget covers the FULL main screen.
            targetFrame = NSScreen.main?.frame ?? NSRect(origin: .zero, size: mode.defaultSize)
        } else {
            let size = mode.defaultSize
            let origin: NSPoint

            if window.isVisible || currentMode != nil {
                // Resize around the CENTER so the card grows/shrinks in place
                // rather than from a corner.
                let current = window.frame
                origin = NSPoint(x: current.midX - size.width / 2,
                                 y: current.midY - size.height / 2)
            } else {
                // First appearance: restore persisted origin or center on screen.
                origin = restoredOrigin(for: size)
            }
            targetFrame = NSRect(origin: origin, size: size)
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }

        // Persist origin for non-widget modes (the widget is always screen-sized).
        if mode != .desktopWidget {
            persistOrigin(targetFrame.origin)
        }
    }

    /// Restore the saved window origin, or center on the main screen on first run.
    private func restoredOrigin(for size: CGSize) -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: originDefaultsKey) {
            let point = NSPointFromString(saved)
            // Guard against an off-screen / zeroed value.
            if point != .zero { return point }
        }
        // Center on the main screen.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.midX - size.width / 2,
                       y: screen.midY - size.height / 2)
    }

    private func persistOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: originDefaultsKey)
    }

    // MARK: - Helpers

    /// Whether moving from `old` to `new` crosses the widget / non-widget style
    /// boundary (which requires a different style mask, hence a new window).
    private func styleClassChanged(from old: WindowMode?, to new: WindowMode) -> Bool {
        guard let old else { return false }
        return (old == .desktopWidget) != (new == .desktopWidget)
    }
}
