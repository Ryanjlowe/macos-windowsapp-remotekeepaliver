import CoreGraphics
import Foundation

/// User-adjustable options for the keep-alive engine.
public struct KeepAliveSettings: Equatable {
    /// Seconds of real inactivity before the engine goes away.
    public var idleThreshold: TimeInterval = 120
    /// Seconds between jiggle cycles while away.
    public var jiggleInterval: TimeInterval = 60
    /// Distance in points of each jiggle move.
    public var jiggleDistance: CGFloat = 5
    public var keepSystemAwake = true
    public var keepDisplayAwake = true
    public var returnFocusAfterJiggle = true
    /// Also press F15 after the moves.
    public var pressKey = false
    public var enabled = true

    public init() {}
}

/// Persists `KeepAliveSettings` in UserDefaults under keys prefixed `rka.`.
public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let idleThreshold = "rka.idleThreshold"
        static let jiggleInterval = "rka.jiggleInterval"
        static let jiggleDistance = "rka.jiggleDistance"
        static let keepSystemAwake = "rka.keepSystemAwake"
        static let keepDisplayAwake = "rka.keepDisplayAwake"
        static let returnFocusAfterJiggle = "rka.returnFocusAfterJiggle"
        static let pressKey = "rka.pressKey"
        static let enabled = "rka.enabled"
    }

    /// Loads saved settings, using defaults for any missing key.
    public func load() -> KeepAliveSettings {
        var s = KeepAliveSettings()
        if let v = defaults.object(forKey: Key.idleThreshold) as? Double { s.idleThreshold = v }
        if let v = defaults.object(forKey: Key.jiggleInterval) as? Double { s.jiggleInterval = v }
        if let v = defaults.object(forKey: Key.jiggleDistance) as? Double { s.jiggleDistance = CGFloat(v) }
        if let v = defaults.object(forKey: Key.keepSystemAwake) as? Bool { s.keepSystemAwake = v }
        if let v = defaults.object(forKey: Key.keepDisplayAwake) as? Bool { s.keepDisplayAwake = v }
        if let v = defaults.object(forKey: Key.returnFocusAfterJiggle) as? Bool { s.returnFocusAfterJiggle = v }
        if let v = defaults.object(forKey: Key.pressKey) as? Bool { s.pressKey = v }
        if let v = defaults.object(forKey: Key.enabled) as? Bool { s.enabled = v }
        return s
    }

    public func save(_ s: KeepAliveSettings) {
        defaults.set(s.idleThreshold, forKey: Key.idleThreshold)
        defaults.set(s.jiggleInterval, forKey: Key.jiggleInterval)
        defaults.set(Double(s.jiggleDistance), forKey: Key.jiggleDistance)
        defaults.set(s.keepSystemAwake, forKey: Key.keepSystemAwake)
        defaults.set(s.keepDisplayAwake, forKey: Key.keepDisplayAwake)
        defaults.set(s.returnFocusAfterJiggle, forKey: Key.returnFocusAfterJiggle)
        defaults.set(s.pressKey, forKey: Key.pressKey)
        defaults.set(s.enabled, forKey: Key.enabled)
    }
}
