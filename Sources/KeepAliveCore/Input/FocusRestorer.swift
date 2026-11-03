import AppKit
import ApplicationServices
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

    /// Re-activates `app`, confirming with the frontmost app and retrying once.
    /// Returns whether the app ended up frontmost.
    @discardableResult
    public func restore(_ app: FrontmostApp) -> Bool {
        Thread.sleep(forTimeInterval: restoreDelay)
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return false }
        for _ in 0..<2 {
            running.activate()
            _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.pid),
                                             kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            Thread.sleep(forTimeInterval: restoreDelay)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid { return true }
        }
        return false
    }
}
