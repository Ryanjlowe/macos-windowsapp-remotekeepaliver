import Foundation

/// A source of the current time, replaceable in tests.
public protocol Clock {
    var now: Date { get }
}

/// The wall clock.
public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}
