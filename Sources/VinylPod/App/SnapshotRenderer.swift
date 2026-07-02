import SwiftUI
import AppKit

/// Headless dev tool: `VinylPod --render-snapshot [out.png] [WxH]` renders the
/// desktop widget canvas to a PNG and exits, without windows, compositor, or
/// screen-recording permissions. Used to pixel-verify layout changes from CI /
/// agent sessions where screenshots are TCC-blocked.
///
/// Limitations (fine for geometry checks): `ImageRenderer` skips
/// `NSViewRepresentable` layers (the behind-window blur) and renders
/// `TimelineView` at its initial tick only.
@MainActor
enum SnapshotRenderer {

    /// Call first thing at startup; returns normally unless the flag is present,
    /// in which case it writes the PNG and terminates the process.
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--render-snapshot") else { return }

        let outPath = args.indices.contains(flagIndex + 1)
            ? args[flagIndex + 1]
            : NSTemporaryDirectory() + "vinylpod-snapshot.png"

        var size = CGSize(width: 1470, height: 918)
        if args.indices.contains(flagIndex + 2) {
            let parts = args[flagIndex + 2].split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] > 100, parts[1] > 100 {
                size = CGSize(width: parts[0], height: parts[1])
            }
        }

        let env = AppEnvironment.shared
        let canvas = DesktopWidgetCanvas(onSelectSize: { _ in }, onQuit: {})
            .environmentObject(env.nowPlaying)
            .environmentObject(env.settings)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2.0

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: outPath))
            print("snapshot: wrote \(outPath) (\(Int(size.width))x\(Int(size.height))@2x)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }
}
