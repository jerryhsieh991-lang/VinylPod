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

    /// `--dump-live [out.png]`: capture the REAL on-screen window's view
    /// hierarchy (TimelineView, materials placeholders and all) a few seconds
    /// after launch, then quit. Uses `bitmapImageRepForCachingDisplay`, which
    /// needs no screen-recording permission because we only render our own
    /// view tree. Call from `applicationDidFinishLaunching`.
    static func scheduleLiveDumpIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--dump-live") else { return }
        let outPath = args.indices.contains(flagIndex + 1)
            ? args[flagIndex + 1]
            : NSTemporaryDirectory() + "vinylpod-live.png"

        // Optional third arg "island" targets the Dynamic Island panel
        // (100–800 pt wide) instead of the main widget window (>800 pt).
        let wantIsland = args.indices.contains(flagIndex + 2) && args[flagIndex + 2] == "island"

        // The main widget window is created after launch; poll until a
        // real-sized window exists (the menu-bar extra doesn't count).
        var attempts = 0
        func tryDump() {
            attempts += 1
            guard let window = NSApp.windows.first(where: {
                      wantIsland ? ((100..<800).contains($0.frame.width) && $0.level.rawValue > NSWindow.Level.normal.rawValue)
                                 : $0.frame.width > 800
                  }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                if attempts < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { tryDump() }
                } else {
                    FileHandle.standardError.write(Data("dump-live: no widget window after \(attempts)s\n".utf8))
                    exit(1)
                }
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            // Also dump the layer tree with frames for coordinate forensics.
            var treeLines: [String] = []
            func walk(_ layer: CALayer, depth: Int) {
                let cls = String(describing: type(of: layer))
                let f = layer.frame
                treeLines.append(String(repeating: "  ", count: depth) + "\(cls) frame=(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height))) hidden=\(layer.isHidden) opacity=\(layer.opacity)")
                for sub in layer.sublayers ?? [] { walk(sub, depth: depth + 1) }
            }
            if let rootLayer = view.layer { walk(rootLayer, depth: 0) }
            try? treeLines.joined(separator: "\n").write(toFile: outPath + ".layers.txt", atomically: true, encoding: .utf8)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            do {
                try png.write(to: URL(fileURLWithPath: outPath))
                print("dump-live: wrote \(outPath) (\(Int(view.bounds.width))x\(Int(view.bounds.height)))")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("dump-live: \(error)\n".utf8))
                exit(1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { tryDump() }
    }

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
