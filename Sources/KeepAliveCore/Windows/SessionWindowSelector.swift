import CoreGraphics
import Foundation

/// Pure rules for choosing which Windows App windows are remote sessions.
public enum SessionWindowSelector {
    /// Titles of Windows App windows that are never sessions, lowercased.
    static let nonSessionTitles: Set<String> = [
        "windows app", "devices", "apps", "settings", "connection center", "preferences",
    ]

    public static func select(from windows: [WindowInfo]) -> [WindowInfo] {
        let candidates = windows.filter { window in
            guard window.isOnScreen else { return false }
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return false }
            return !nonSessionTitles.contains(title.lowercased())
        }
        let desktops = candidates.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix("desktop")
        }
        let chosen = desktops.isEmpty ? candidates : desktops
        return chosen.sorted { $0.area > $1.area }
    }
}
