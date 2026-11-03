import AppKit
import KeepAliveCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.ryanlowe.RemoteKeepAliver", category: "engine")
    private let store = SettingsStore()
    private let sleep = SleepAssertion()
    private var engine: KeepAliveEngine!
    private var menu: StatusMenuController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = store.load()
        let source = AXWindowSource()
        engine = KeepAliveEngine(
            settings: settings,
            clock: SystemClock(),
            idleSource: CGIdleSource(),
            windows: source,
            activator: WindowActivator(source: source),
            mouse: CGMousePoster(distance: settings.jiggleDistance),
            focus: WorkspaceFocusRestorer(),
            hasPermission: { Permissions.isTrusted() }
        )
        engine.onStateChange = { [log] state in log.info("state: \(String(describing: state))") }
        engine.onLog = { [log] line in log.info("\(line)") }

        menu = StatusMenuController(engine: engine, store: store) { [weak self] in
            self?.applySleep()
        }
        if !Permissions.isTrusted() { Permissions.requestTrust() }
        applySleep()
        engine.tick()
        menu.refresh()

        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engine.tick()
                self?.menu.refresh()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        sleep.update(systemAwake: false, displayAwake: false)
    }

    private func applySleep() {
        let s = engine.settings
        sleep.update(systemAwake: s.enabled && s.keepSystemAwake,
                     displayAwake: s.enabled && s.keepDisplayAwake)
    }
}
