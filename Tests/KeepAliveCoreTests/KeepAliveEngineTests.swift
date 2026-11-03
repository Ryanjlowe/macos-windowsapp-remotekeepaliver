import XCTest
@testable import KeepAliveCore

final class FakeClock: Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

final class FakeIdle: IdleSource {
    var value: TimeInterval = 0
    func secondsSinceLastInput() -> TimeInterval { value }
}

final class FakeWindows: WindowSource {
    var windows: [WindowInfo] = []
    func sessionCandidates() -> [WindowInfo] { windows }
}

final class FakeActivator: WindowActivating {
    var activated: [WindowInfo] = []
    var succeeds = true
    var failingIds: Set<Int> = []
    func activateAndRaise(_ window: WindowInfo) -> Bool {
        activated.append(window)
        return succeeds && !failingIds.contains(window.id)
    }
}

final class FakeMouse: MousePosting {
    let clock: FakeClock
    var jiggles: [(frame: CGRect, pressKey: Bool)] = []
    var lastBurst: (start: Date, end: Date)?
    init(clock: FakeClock) { self.clock = clock }
    func jiggle(in frame: CGRect, pressKey: Bool) -> (start: Date, end: Date) {
        jiggles.append((frame, pressKey))
        let burst = (start: clock.now, end: clock.now.addingTimeInterval(0.1))
        lastBurst = burst
        return burst
    }
}

final class FakeFocus: FocusRestoring {
    var frontmost: FrontmostApp? = FrontmostApp(pid: 100, bundleIdentifier: "com.apple.Terminal")
    var restored: [FrontmostApp] = []
    func currentFrontmost() -> FrontmostApp? { frontmost }
    func restore(_ app: FrontmostApp) -> Bool { restored.append(app); return true }
}

final class KeepAliveEngineTests: XCTestCase {
    var clock: FakeClock!
    var idle: FakeIdle!
    var windows: FakeWindows!
    var activator: FakeActivator!
    var mouse: FakeMouse!
    var focus: FakeFocus!
    var permission = true
    var engine: KeepAliveEngine!

    let session = WindowInfo(id: 1, pid: 500, title: "Australia Desktop",
                             frame: CGRect(x: 0, y: 0, width: 1000, height: 800), isOnScreen: true)

    override func setUp() {
        clock = FakeClock()
        idle = FakeIdle()
        windows = FakeWindows()
        windows.windows = [session]
        activator = FakeActivator()
        mouse = FakeMouse(clock: clock)
        focus = FakeFocus()
        permission = true
        makeEngine(KeepAliveSettings())
    }

    func makeEngine(_ settings: KeepAliveSettings) {
        engine = KeepAliveEngine(
            settings: settings, clock: clock, idleSource: idle, windows: windows,
            activator: activator, mouse: mouse, focus: focus,
            hasPermission: { [unowned self] in self.permission })
    }

    /// Advances time by `seconds` while the user stays idle (no real input).
    func idleFor(_ seconds: TimeInterval) {
        clock.advance(seconds)
        idle.value += seconds
    }

    /// Simulates the idle counter after only the app's own burst.
    func syntheticOnlyIdle() {
        idle.value = clock.now.timeIntervalSince(mouse.lastBurst!.end)
    }

    func goAway() {
        idleFor(120)
        engine.tick()
    }

    func testStaysWatchingUnderThreshold() {
        idleFor(60)
        engine.tick()
        XCTAssertEqual(engine.state, .watching(idle: 60))
        XCTAssertTrue(mouse.jiggles.isEmpty)
    }

    func testEntersAwayAtThresholdAndJigglesImmediately() {
        goAway()
        XCTAssertEqual(engine.state, .away)
        XCTAssertEqual(mouse.jiggles.count, 1)
        XCTAssertEqual(activator.activated, [session])
        XCTAssertEqual(engine.lastTargets, [session])
    }

    func testJigglesAgainOnlyAfterInterval() {
        goAway()
        clock.advance(30); syntheticOnlyIdle(); engine.tick()
        XCTAssertEqual(mouse.jiggles.count, 1)
        clock.advance(31); syntheticOnlyIdle(); engine.tick()
        XCTAssertEqual(mouse.jiggles.count, 2)
        XCTAssertEqual(engine.state, .away)
    }

    func testSyntheticBurstIsNotUserReturn() {
        goAway()
        for _ in 0..<5 {
            clock.advance(5)
            syntheticOnlyIdle()
            engine.tick()
            XCTAssertEqual(engine.state, .away)
        }
    }

    func testRealInputAfterBurstReturnsToWatching() {
        goAway()
        clock.advance(10)
        idle.value = 1 // Real input one second ago.
        engine.tick()
        XCTAssertEqual(engine.state, .watching(idle: 1))
    }

    func testReenteringAwayJigglesImmediately() {
        var s = KeepAliveSettings(); s.idleThreshold = 60; s.jiggleInterval = 240
        makeEngine(s)
        idleFor(60); engine.tick()
        XCTAssertEqual(mouse.jiggles.count, 1)
        clock.advance(10); idle.value = 1; engine.tick()
        XCTAssertEqual(engine.state, .watching(idle: 1))
        idleFor(60); engine.tick()
        XCTAssertEqual(engine.state, .away)
        XCTAssertEqual(mouse.jiggles.count, 2)
    }

    func testReenteringAwayFromNeedsPermissionJigglesImmediately() {
        var s = KeepAliveSettings(); s.idleThreshold = 60; s.jiggleInterval = 240
        makeEngine(s)
        idleFor(60); engine.tick()
        XCTAssertEqual(mouse.jiggles.count, 1)
        permission = false
        clock.advance(5); syntheticOnlyIdle(); engine.tick()
        XCTAssertEqual(engine.state, .needsPermission)
        permission = true
        clock.advance(5); syntheticOnlyIdle(); engine.tick()
        XCTAssertEqual(engine.state, .away)
        XCTAssertEqual(mouse.jiggles.count, 2)
    }

    func testActivationFailureJigglesNothingAndKeepsTargets() {
        var logs: [String] = []
        engine.onLog = { logs.append($0) }
        activator.succeeds = false
        goAway()
        XCTAssertTrue(mouse.jiggles.isEmpty)
        XCTAssertEqual(engine.state, .away)
        XCTAssertTrue(engine.lastCycleActivationFailed)
        XCTAssertEqual(engine.lastTargets, [session])
        XCTAssertTrue(focus.restored.isEmpty)
        XCTAssertFalse(engine.jiggleNow())
        XCTAssertTrue(logs.contains("activation failed for Australia Desktop"))
    }

    func testPartialActivationFailureJigglesOnlyTheSuccessfulWindow() {
        let berlin = WindowInfo(id: 2, pid: 500, title: "Berlin Desktop",
                                frame: CGRect(x: 0, y: 0, width: 600, height: 400), isOnScreen: true)
        windows.windows = [session, berlin]
        activator.failingIds = [session.id]
        goAway()
        XCTAssertEqual(mouse.jiggles.map(\.frame), [berlin.frame])
        XCTAssertEqual(engine.state, .away)
        XCTAssertFalse(engine.lastCycleActivationFailed)
    }

    func testTwoSessionsAreAllJiggledLargestFirstAndFocusRestoredOnce() {
        let berlin = WindowInfo(id: 2, pid: 500, title: "Berlin Desktop",
                                frame: CGRect(x: 0, y: 0, width: 600, height: 400), isOnScreen: true)
        windows.windows = [berlin, session]
        goAway()
        XCTAssertEqual(activator.activated, [session, berlin])
        XCTAssertEqual(mouse.jiggles.map(\.frame), [session.frame, berlin.frame])
        XCTAssertEqual(engine.lastTargets, [session, berlin])
        XCTAssertEqual(focus.restored.count, 1)
    }

    func testAwayNoTargetThenRecovers() {
        windows.windows = []
        goAway()
        XCTAssertEqual(engine.state, .awayNoTarget)
        XCTAssertTrue(mouse.jiggles.isEmpty)
        windows.windows = [session]
        clock.advance(61); idle.value += 61
        engine.tick()
        XCTAssertEqual(engine.state, .away)
        XCTAssertEqual(mouse.jiggles.count, 1)
    }

    func testConnectionCenterIsNotATarget() {
        windows.windows = [WindowInfo(id: 2, pid: 500, title: "Windows App",
                                      frame: CGRect(x: 0, y: 0, width: 500, height: 500), isOnScreen: true)]
        goAway()
        XCTAssertEqual(engine.state, .awayNoTarget)
    }

    func testDisabledDoesNothing() {
        var s = KeepAliveSettings(); s.enabled = false
        makeEngine(s)
        goAway()
        XCTAssertEqual(engine.state, .disabled)
        XCTAssertTrue(mouse.jiggles.isEmpty)
    }

    func testNeedsPermission() {
        permission = false
        goAway()
        XCTAssertEqual(engine.state, .needsPermission)
        XCTAssertTrue(mouse.jiggles.isEmpty)
        permission = true
        clock.advance(1); idle.value += 1
        engine.tick()
        XCTAssertEqual(engine.state, .away)
    }

    func testJiggleNowWorksFromWatching() {
        XCTAssertTrue(engine.jiggleNow())
        XCTAssertEqual(mouse.jiggles.count, 1)
        XCTAssertEqual(engine.state, .watching(idle: 0))
    }

    func testFocusRestoredByDefault() {
        goAway()
        XCTAssertEqual(focus.restored, [FrontmostApp(pid: 100, bundleIdentifier: "com.apple.Terminal")])
    }

    func testReturnFocusFalseSkipsRestore() {
        var s = KeepAliveSettings(); s.returnFocusAfterJiggle = false
        makeEngine(s)
        goAway()
        XCTAssertEqual(mouse.jiggles.count, 1)
        XCTAssertTrue(focus.restored.isEmpty)
    }

    func testFrontmostWindowsAppSkipsRestore() {
        focus.frontmost = FrontmostApp(pid: 500, bundleIdentifier: nil)
        goAway()
        XCTAssertEqual(mouse.jiggles.count, 1)
        XCTAssertTrue(focus.restored.isEmpty)
    }

    func testPressKeySettingIsPassedThrough() {
        var s = KeepAliveSettings(); s.pressKey = true
        makeEngine(s)
        goAway()
        XCTAssertEqual(mouse.jiggles.first?.pressKey, true)
    }

    func testStateChangeCallback() {
        var states: [KeepAliveState] = []
        engine.onStateChange = { states.append($0) }
        goAway()
        XCTAssertEqual(states, [.away])
        for _ in 0..<5 {
            clock.advance(5); syntheticOnlyIdle(); engine.tick()
        }
        XCTAssertEqual(states, [.away])
        idle.value = 1; engine.tick()
        XCTAssertEqual(states, [.away, .watching(idle: 1)])
    }
}
