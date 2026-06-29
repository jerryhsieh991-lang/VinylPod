import SwiftUI
import AppKit

/// The dark "Keyboard shortcuts" preferences pane. Renders the three
/// `ShortcutAction.groups` as visually separated blocks of rows, each row a
/// right-aligned title label paired with a `ShortcutRecorderView` pill.
struct KeyboardShortcutsView: View {
    @EnvironmentObject var store: ShortcutStore

    /// Fixed width of the right-aligned title column (left side of each row).
    private let labelColumnWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // One VStack per group; the outer spacing (24) creates the visible
            // gap between the three blocks in the screenshot.
            ForEach(Array(ShortcutAction.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group) { action in
                        row(for: action)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.001).background(.black)) // fill the window
    }

    private func row(for action: ShortcutAction) -> some View {
        HStack(spacing: 16) {
            Text(action.title)
                .font(VPTheme.body(12))
                .foregroundColor(VPTheme.textSecondary)
                .frame(width: labelColumnWidth, alignment: .trailing)

            ShortcutRecorderView(action: action)
        }
        .padding(.vertical, 8)
    }
}

/// Owns the single reusable "Keyboard shortcuts" `NSWindow` and hosts the
/// SwiftUI view inside it.
@MainActor
final class KeyboardShortcutsWindowController {
    static let shared = KeyboardShortcutsWindowController()

    /// Strong reference so the window survives between shows. With
    /// `isReleasedWhenClosed = false`, closing just hides it and we reuse the
    /// same instance on the next `show()`.
    private var window: NSWindow?

    private init() {}

    func show() {
        // Reuse the existing window if we've already built one.
        if window == nil {
            let hosting = NSHostingView(
                rootView: KeyboardShortcutsView()
                    .environmentObject(AppEnvironment.shared.shortcuts)
            )

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 546, height: 458),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Keyboard shortcuts"
            win.isReleasedWhenClosed = false       // keep the instance for reuse
            win.appearance = NSAppearance(named: .darkAqua)
            win.contentView = hosting
            win.setContentSize(NSSize(width: 546, height: 458))
            win.center()
            window = win
        }

        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
