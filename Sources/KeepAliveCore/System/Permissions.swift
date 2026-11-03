import AppKit
import ApplicationServices
import Foundation

/// Accessibility trust helpers.
public enum Permissions {
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open Accessibility settings.
    public static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
