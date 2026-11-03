import AppKit
import KeepAliveCore
import os

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let log = Logger(subsystem: "com.ryanlowe.RemoteKeepAliver", category: "menu")
    private let engine: KeepAliveEngine
    private let store: SettingsStore
    private let onSettingsChanged: () -> Void
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var statusLine: NSMenuItem?
    private var targetLine: NSMenuItem?
    private var showRelaunchNote = false

    init(engine: KeepAliveEngine, store: SettingsStore, onSettingsChanged: @escaping () -> Void) {
        self.engine = engine
        self.store = store
        self.onSettingsChanged = onSettingsChanged
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        item.menu = menu
        rebuild()
        refresh()
    }

    // MARK: Text

    private func statusText() -> String {
        switch engine.state {
        case .disabled: return "Status: Disabled"
        case .needsPermission: return "Status: Accessibility access needed"
        case .watching(let idle):
            let s = Int(idle)
            return String(format: "Status: Watching (idle %d:%02d)", s / 60, s % 60)
        case .away where engine.lastCycleActivationFailed:
            return "Status: Away, could not activate session window"
        case .away: return "Status: Away, jiggling every \(intervalLabel(engine.settings.jiggleInterval))"
        case .awayNoTarget: return "Status: Away, no session window"
        }
    }

    private func targetText() -> String {
        let titles = engine.lastTargets.map(\.title)
        return titles.isEmpty ? "No session window" : "Target: " + titles.joined(separator: ", ")
    }

    private func intervalLabel(_ t: TimeInterval) -> String {
        t < 60 ? "\(Int(t)) s" : "\(Int(t / 60)) min"
    }

    // MARK: Refresh

    /// Updates the icon and the live lines. Called every tick.
    func refresh() {
        let (symbol, alpha): (String, CGFloat)
        switch engine.state {
        case .disabled: (symbol, alpha) = ("cursorarrow.motionlines", 0.4)
        case .needsPermission: (symbol, alpha) = ("exclamationmark.triangle", 1)
        case .away: (symbol, alpha) = ("cursorarrow.motionlines.click", 1)
        default: (symbol, alpha) = ("cursorarrow.motionlines", 1)
        }
        if let button = item.button {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RemoteKeepAliver")
            image?.isTemplate = true
            button.image = image
            button.alphaValue = alpha
            button.setAccessibilityLabel("RemoteKeepAliver, \(statusText())")
        }
        statusLine?.title = statusText()
        targetLine?.title = targetText()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        engine.refreshTargets()
        rebuild()
        refresh()
    }

    // MARK: Build

    private func rebuild() {
        menu.removeAllItems()
        let s = engine.settings

        let header = NSMenuItem(title: "RemoteKeepAliver", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let st = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        st.isEnabled = false
        let tg = NSMenuItem(title: targetText(), action: nil, keyEquivalent: "")
        tg.isEnabled = false
        statusLine = st
        targetLine = tg
        menu.addItem(st)
        menu.addItem(tg)
        menu.addItem(.separator())

        menu.addItem(toggle("Enabled", s.enabled, #selector(toggleEnabled)))
        menu.addItem(submenu("Start after idle", [60, 120, 300, 600], current: s.idleThreshold,
                             action: #selector(pickIdle(_:))))
        menu.addItem(submenu("Jiggle every", [30, 60, 120, 240], current: s.jiggleInterval,
                             action: #selector(pickInterval(_:))))
        menu.addItem(toggle("Keep Mac awake", s.keepSystemAwake, #selector(toggleSystemAwake)))
        menu.addItem(toggle("Keep display awake", s.keepDisplayAwake, #selector(toggleDisplayAwake)))
        menu.addItem(toggle("Return focus after jiggle", s.returnFocusAfterJiggle, #selector(toggleReturnFocus)))
        menu.addItem(toggle("Also press a key (F15)", s.pressKey, #selector(togglePressKey)))
        menu.addItem(toggle("Launch at login", LoginItem.isEnabled, #selector(toggleLogin)))
        menu.addItem(.separator())

        menu.addItem(action("Jiggle now", #selector(jiggleNow)))
        if !Permissions.isTrusted() {
            menu.addItem(action("Grant Accessibility access\u{2026}", #selector(grantAccess)))
            if showRelaunchNote {
                let note = NSMenuItem(title: "Relaunch after granting", action: nil, keyEquivalent: "")
                note.isEnabled = false
                menu.addItem(note)
            }
        }
        menu.addItem(.separator())
        let quit = action("Quit", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let i = action(title, sel)
        i.state = on ? .on : .off
        return i
    }

    private func submenu(_ title: String, _ values: [TimeInterval], current: TimeInterval,
                         action sel: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        for v in values {
            let i = action(intervalLabel(v), sel)
            i.representedObject = v
            i.state = v == current ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    private func change(_ edit: (inout KeepAliveSettings) -> Void) {
        var s = engine.settings
        edit(&s)
        engine.settings = s
        store.save(s)
        onSettingsChanged()
        log.info("settings changed")
        engine.tick()
        rebuild()
        refresh()
    }

    @objc private func toggleEnabled() { change { $0.enabled.toggle() } }
    @objc private func toggleSystemAwake() { change { $0.keepSystemAwake.toggle() } }
    @objc private func toggleDisplayAwake() { change { $0.keepDisplayAwake.toggle() } }
    @objc private func toggleReturnFocus() { change { $0.returnFocusAfterJiggle.toggle() } }
    @objc private func togglePressKey() { change { $0.pressKey.toggle() } }

    @objc private func pickIdle(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? TimeInterval { change { $0.idleThreshold = v } }
    }

    @objc private func pickInterval(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? TimeInterval { change { $0.jiggleInterval = v } }
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
            log.info("launch at login: \(LoginItem.isEnabled)")
        } catch {
            log.error("launch at login failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuild()
    }

    @objc private func jiggleNow() {
        let ok = engine.jiggleNow()
        log.info("manual jiggle, success: \(ok)")
        refresh()
    }

    @objc private func grantAccess() {
        showRelaunchNote = true
        Permissions.requestTrust()
        Permissions.openAccessibilitySettings()
        rebuild()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
