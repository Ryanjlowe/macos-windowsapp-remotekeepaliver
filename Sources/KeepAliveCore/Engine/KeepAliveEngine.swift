import CoreGraphics
import Foundation

/// Bundle id of the Windows App remote desktop client.
public let windowsAppBundleID = "com.microsoft.rdc.macos"

/// The app that was frontmost before a jiggle cycle.
public struct FrontmostApp: Equatable {
    public var pid: pid_t
    public var bundleIdentifier: String?

    public init(pid: pid_t, bundleIdentifier: String? = nil) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum KeepAliveState: Equatable {
    case disabled
    case needsPermission
    case watching(idle: TimeInterval)
    case away
    case awayNoTarget

    /// The case without its payload, so `.watching(idle:)` ticks are not transitions.
    var kind: String {
        switch self {
        case .disabled: return "disabled"
        case .needsPermission: return "needsPermission"
        case .watching: return "watching"
        case .away: return "away"
        case .awayNoTarget: return "awayNoTarget"
        }
    }
}

/// The outcome of one away-mode cycle.
public enum CycleResult: Equatable {
    case noTarget
    case activationFailed
    case jiggled
}

public protocol WindowSource {
    /// All Windows App windows; the engine filters them with `SessionWindowSelector`.
    func sessionCandidates() -> [WindowInfo]
}

public protocol WindowActivating {
    /// Brings the window's app and the window to the front. Returns whether it succeeded.
    func activateAndRaise(_ window: WindowInfo) -> Bool
}

public protocol MousePosting {
    /// Posts the jiggle inside `frame` and returns when the burst started and ended.
    func jiggle(in frame: CGRect, pressKey: Bool) -> (start: Date, end: Date)
}

public protocol FocusRestoring {
    func currentFrontmost() -> FrontmostApp?
    func restore(_ app: FrontmostApp) -> Bool
}

/// The keep-alive state machine. Pure logic: no AppKit and no timers. The
/// shell calls `tick()` every few seconds.
public final class KeepAliveEngine {
    /// Slack around the recorded synthetic burst when attributing input to the app.
    static let burstTolerance: TimeInterval = 0.5

    public private(set) var state: KeepAliveState {
        didSet { if state.kind != oldValue.kind { onStateChange?(state) } }
    }
    public private(set) var lastTargets: [WindowInfo] = []
    /// True when the last cycle found session windows but could not activate any of them.
    public private(set) var lastCycleActivationFailed = false
    public var settings: KeepAliveSettings
    public var onStateChange: ((KeepAliveState) -> Void)?
    /// Receives short log lines for targets and each jiggle.
    public var onLog: ((String) -> Void)?

    private let clock: Clock
    private let idleSource: IdleSource
    private let windows: WindowSource
    private let activator: WindowActivating
    private let mouse: MousePosting
    private let focus: FocusRestoring
    private let hasPermission: () -> Bool

    private var lastRealInputAt: Date
    private var lastBurst: (start: Date, end: Date)?
    private var nextCycleAt: Date?

    public init(
        settings: KeepAliveSettings = KeepAliveSettings(),
        clock: Clock,
        idleSource: IdleSource,
        windows: WindowSource,
        activator: WindowActivating,
        mouse: MousePosting,
        focus: FocusRestoring,
        hasPermission: @escaping () -> Bool
    ) {
        self.settings = settings
        self.clock = clock
        self.idleSource = idleSource
        self.windows = windows
        self.activator = activator
        self.mouse = mouse
        self.focus = focus
        self.hasPermission = hasPermission
        self.lastRealInputAt = clock.now
        self.state = settings.enabled ? .watching(idle: 0) : .disabled
    }

    /// Advances the state machine. Call every few seconds.
    public func tick() {
        guard settings.enabled else {
            nextCycleAt = nil
            state = .disabled
            return
        }
        guard hasPermission() else {
            nextCycleAt = nil
            state = .needsPermission
            return
        }

        let now = clock.now
        updateRealInput(now: now)
        let idle = max(0, now.timeIntervalSince(lastRealInputAt))

        guard idle >= settings.idleThreshold else {
            nextCycleAt = nil
            state = .watching(idle: idle)
            return
        }

        // Away: run a cycle immediately on entry, then every interval.
        if let due = nextCycleAt, now < due {
            return
        }
        let result = runCycle()
        nextCycleAt = clock.now.addingTimeInterval(settings.jiggleInterval)
        state = result == .noTarget ? .awayNoTarget : .away
    }

    /// Runs one cycle in any state. Returns whether a window was jiggled.
    @discardableResult
    public func jiggleNow() -> Bool {
        runCycle() == .jiggled
    }

    private func updateRealInput(now: Date) {
        let lastEventAt = now.addingTimeInterval(-idleSource.secondsSinceLastInput())
        if let burst = lastBurst {
            let lo = burst.start.addingTimeInterval(-Self.burstTolerance)
            let hi = burst.end.addingTimeInterval(Self.burstTolerance)
            if lastEventAt >= lo && lastEventAt <= hi { return }
        }
        if lastEventAt > lastRealInputAt { lastRealInputAt = lastEventAt }
    }

    private func runCycle() -> CycleResult {
        let targets = SessionWindowSelector.select(from: windows.sessionCandidates())
        if targets.map(\.id) != lastTargets.map(\.id) {
            onLog?("targets: \(targets.map(\.title).joined(separator: ", "))")
        }
        lastTargets = targets
        guard !targets.isEmpty else {
            lastCycleActivationFailed = false
            return .noTarget
        }

        let previous = focus.currentFrontmost()
        var burstStart: Date?
        var burstEnd: Date?
        for target in targets {
            guard activator.activateAndRaise(target) else {
                onLog?("activation failed for \(target.title)")
                continue
            }
            let burst = mouse.jiggle(in: target.frame, pressKey: settings.pressKey)
            burstStart = min(burstStart ?? burst.start, burst.start)
            burstEnd = max(burstEnd ?? burst.end, burst.end)
        }
        guard let start = burstStart, let end = burstEnd else {
            lastCycleActivationFailed = true
            return .activationFailed
        }
        lastCycleActivationFailed = false
        lastBurst = (start, end)
        onLog?("jiggled \(targets.count) window(s)")

        if settings.returnFocusAfterJiggle, let previous,
           previous.bundleIdentifier != windowsAppBundleID,
           !targets.contains(where: { $0.pid == previous.pid }) {
            if !focus.restore(previous) {
                onLog?("focus restore failed for pid \(previous.pid)")
            }
        }
        return .jiggled
    }
}
