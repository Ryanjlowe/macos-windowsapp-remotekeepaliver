import AppKit
import ApplicationServices
import Foundation

/// Brings a Windows App window to the front using NSRunningApplication and AX.
public final class WindowActivator: WindowActivating {
    private let source: AXWindowSource
    /// Time to let activation settle before checking the frontmost app.
    private let settleDelay: TimeInterval

    public init(source: AXWindowSource, settleDelay: TimeInterval = 0.3) {
        self.source = source
        self.settleDelay = settleDelay
    }

    public func activateAndRaise(_ window: WindowInfo) -> Bool {
        for _ in 0..<2 {
            attempt(window)
            Thread.sleep(forTimeInterval: settleDelay)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid { return true }
        }
        return false
    }

    private func attempt(_ window: WindowInfo) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
        let appElement = source.appElement(for: window.pid)
        _ = AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard let element = source.element(for: window) else { return }
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
