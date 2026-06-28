import SwiftUI
import AppKit

/// The glassmorphism primitive: a thin SwiftUI wrapper around AppKit's
/// `NSVisualEffectView`. We use the `.hudWindow` material with
/// `.behindWindow` blending so panels frost whatever sits *behind* the
/// window (the landscape, the desktop, other apps in widget mode) rather
/// than just blurring sibling SwiftUI layers.
///
/// Per the design system, panels are "light, translucent layers — never
/// opaque solid blocks", so this blur is always paired with a faint
/// `VPTheme.glassTint` and a `VPTheme.glassStroke` border (see `GlassPanel`).
struct VisualEffectBlur: NSViewRepresentable {

    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // `.active` keeps the blur live even when the window is not key,
        // which matters for the always-on desktop widget.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
