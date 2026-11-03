import AppKit
import Foundation

/// Remembers and restores the frontmost app through NSWorkspace.
public final class WorkspaceFocusRestorer: FocusRestoring {
    /// Time to let Windows App process the last input before focus moves away.
    private let restoreDelay: TimeInterval

    public init(restoreDelay: TimeInterval = 0.3) {
        self.restoreDelay = restoreDelay
    }

    public func currentFrontmost() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApp(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
    }

    public func restore(_ app: FrontmostApp) {
        Thread.sleep(forTimeInterval: restoreDelay)
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }
        if #available(macOS 14.0, *) {
            running.activate()
        } else {
            running.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
