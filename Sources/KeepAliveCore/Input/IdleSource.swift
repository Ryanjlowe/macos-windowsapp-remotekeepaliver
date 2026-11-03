import CoreGraphics
import Foundation

/// Reports how long it has been since the last input event.
public protocol IdleSource {
    func secondsSinceLastInput() -> TimeInterval
}

/// Reads the HID system idle counter. Synthetic events posted to the HID tap
/// reset it too, which is why the engine keeps its own bookkeeping.
public struct CGIdleSource: IdleSource {
    public init() {}

    public func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType is ~0, which has no Swift enum case.
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }
}
