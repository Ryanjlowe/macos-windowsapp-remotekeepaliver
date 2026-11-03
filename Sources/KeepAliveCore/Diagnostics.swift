import CoreGraphics
import Foundation

/// Text reports used by the command-line flags of the executable.
public enum Diagnostics {
    public static func listWindows() -> String {
        var lines = ["Accessibility trusted: \(Permissions.isTrusted())"]
        guard WindowsApp.runningApplication() != nil else {
            lines.append("Windows App is not running.")
            return lines.joined(separator: "\n")
        }
        let all = AXWindowSource().sessionCandidates()
        let selected = Set(SessionWindowSelector.select(from: all).map(\.id))
        if all.isEmpty { lines.append("No windows returned by Accessibility.") }
        for window in all {
            let f = window.frame
            let marker = selected.contains(window.id) ? "selected" : "-"
            lines.append(String(
                format: "%-9@ id=%-6d onScreen=%-5@ frame=(%.0f, %.0f, %.0f x %.0f) title=\"%@\"",
                marker as NSString, window.id, "\(window.isOnScreen)" as NSString,
                f.origin.x, f.origin.y, f.width, f.height, window.title as NSString))
        }
        return lines.joined(separator: "\n")
    }

    public static func jiggleOnce(settings: KeepAliveSettings = KeepAliveSettings()) -> String {
        guard Permissions.isTrusted() else { return "Accessibility is not trusted; cannot jiggle." }
        let source = AXWindowSource()
        let activator = WindowActivator(source: source)
        let mouse = CGMousePoster(distance: settings.jiggleDistance)
        let focus = WorkspaceFocusRestorer()
        let targets = SessionWindowSelector.select(from: source.sessionCandidates())
        guard !targets.isEmpty else { return "No session window found." }

        var lines: [String] = []
        let previous = focus.currentFrontmost()
        lines.append("Previous frontmost pid: \(previous.map { String($0.pid) } ?? "none")")
        var jiggled = false
        for target in targets {
            let ok = activator.activateAndRaise(target)
            lines.append("Activate \"\(target.title)\": \(ok ? "ok" : "failed")")
            guard ok else { continue }
            let burst = mouse.jiggle(in: target.frame, pressKey: settings.pressKey)
            jiggled = true
            lines.append(String(format: "Jiggled \"%@\" in %.0f ms", target.title as NSString,
                                burst.end.timeIntervalSince(burst.start) * 1000))
        }
        if jiggled, settings.returnFocusAfterJiggle, let previous,
           previous.bundleIdentifier != windowsAppBundleID,
           !targets.contains(where: { $0.pid == previous.pid }) {
            focus.restore(previous)
            lines.append("Restored focus to pid \(previous.pid)")
        }
        return lines.joined(separator: "\n")
    }

    /// Prints the measured idle time once per second.
    public static func sampleIdle(seconds: Int) -> String {
        let source = CGIdleSource()
        var lines: [String] = []
        for i in 0..<max(seconds, 1) {
            lines.append(String(format: "t=%2ds idle=%.2f", i, source.secondsSinceLastInput()))
            if i < seconds - 1 { Thread.sleep(forTimeInterval: 1) }
        }
        return lines.joined(separator: "\n")
    }
}
