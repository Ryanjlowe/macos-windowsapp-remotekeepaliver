import AppKit
import ApplicationServices
import Foundation

/// Namespace for facts about the Windows App client.
public enum WindowsApp {
    public static let bundleIdentifier = windowsAppBundleID

    /// The first running Windows App process, if any.
    public static func runningApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }
}

/// Enumerates Windows App windows through the Accessibility API.
public final class AXWindowSource: WindowSource {
    /// Signature of the private `_AXUIElementGetWindow` function.
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindowFn? = {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindowFn.self)
    }()

    /// AX references from the latest enumeration, keyed by `WindowInfo.id`.
    private var windowElements: [Int: AXUIElement] = [:]
    private var appElements: [pid_t: AXUIElement] = [:]

    public init() {}

    public func sessionCandidates() -> [WindowInfo] {
        windowElements = [:]
        appElements = [:]
        guard let app = WindowsApp.runningApplication() else { return [] }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        appElements[pid] = appElement

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let elements = value as? [AXUIElement] else { return [] }

        var result: [WindowInfo] = []
        for (index, element) in elements.enumerated() {
            let title = Self.string(element, kAXTitleAttribute) ?? ""
            guard let position = Self.point(element, kAXPositionAttribute),
                  let size = Self.size(element, kAXSizeAttribute) else { continue }
            let minimized = Self.bool(element, kAXMinimizedAttribute) ?? false
            let id = Self.windowID(of: element) ?? index
            let info = WindowInfo(
                id: id,
                pid: pid,
                title: title,
                frame: CGRect(origin: position, size: size),
                isOnScreen: !minimized && size.width > 0 && size.height > 0
            )
            windowElements[id] = element
            result.append(info)
        }
        return result
    }

    /// The AX element for a window from the latest enumeration.
    func element(for window: WindowInfo) -> AXUIElement? {
        windowElements[window.id]
    }

    /// The AX application element for a process from the latest enumeration.
    func appElement(for pid: pid_t) -> AXUIElement {
        appElements[pid] ?? AXUIElementCreateApplication(pid)
    }

    private static func windowID(of element: AXUIElement) -> Int? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(element, &id) == .success, id != 0 else { return nil }
        return Int(id)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        (attribute(element, name) as? NSNumber)?.boolValue
    }

    private static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
