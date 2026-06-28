import SwiftUI

/// A tiny shared holder so SwiftUI views (the MenuBarExtra content) and the
/// AppDelegate's keyboard monitor can reach the single `WindowManager`.
///
/// The `WindowManager` is `@MainActor` and is built once at launch by the
/// `AppDelegate`, which sets `manager` here. Views call
/// `WindowCoordinator.shared.manager?.apply(...)` to drive window changes.
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()
    var manager: WindowManager?
    private init() {}
}
