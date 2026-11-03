import Foundation
import IOKit.pwr_mgt

/// Holds IOPM assertions that keep the Mac (and optionally its display) awake.
public final class SleepAssertion {
    private var systemID = IOPMAssertionID(0)
    private var displayID = IOPMAssertionID(0)
    private var systemHeld = false
    private var displayHeld = false
    private let reason = "RemoteKeepAliver is keeping a remote session alive" as CFString

    public init() {}

    deinit { update(systemAwake: false, displayAwake: false) }

    public func update(systemAwake: Bool, displayAwake: Bool) {
        sync(want: systemAwake, held: &systemHeld, id: &systemID, type: kIOPMAssertionTypePreventUserIdleSystemSleep)
        sync(want: displayAwake, held: &displayHeld, id: &displayID, type: kIOPMAssertionTypePreventUserIdleDisplaySleep)
    }

    private func sync(want: Bool, held: inout Bool, id: inout IOPMAssertionID, type: String) {
        if want && !held {
            let result = IOPMAssertionCreateWithName(
                type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id)
            held = (result == kIOReturnSuccess)
        } else if !want && held {
            IOPMAssertionRelease(id)
            id = IOPMAssertionID(0)
            held = false
        }
    }
}
