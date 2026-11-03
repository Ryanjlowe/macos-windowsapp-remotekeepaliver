import AppKit
import ApplicationServices
import Foundation

/// Reports which app currently has focus.
///
/// `NSWorkspace.shared.frontmostApplication` and `NSRunningApplication.isActive`
/// are updated only when the main run loop runs. The engine blocks the main
/// thread with short sleeps while it activates, jiggles and restores, so those
/// properties are stale exactly when the code needs them. The Accessibility
/// system-wide element answers synchronously.
public enum Frontmost {
    /// The pid of the focused app, or nil when Accessibility is not trusted.
    public static func pid() -> pid_t? {
        var value: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value)
        guard err == .success, let ref = value else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        let element = unsafeBitCast(ref, to: AXUIElement.self)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        return pid
    }

    /// The focused app as a `FrontmostApp`, or nil when it cannot be resolved.
    public static func app() -> FrontmostApp? {
        guard let pid = pid() else { return nil }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return FrontmostApp(pid: pid, bundleIdentifier: bundle)
    }
}
