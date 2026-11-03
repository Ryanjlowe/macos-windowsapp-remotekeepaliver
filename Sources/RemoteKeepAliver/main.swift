import AppKit
import KeepAliveCore

let arguments = CommandLine.arguments

if arguments.contains("--list-windows") {
    print(Diagnostics.listWindows())
    exit(0)
} else if arguments.contains("--jiggle-once") {
    print(Diagnostics.jiggleOnce(settings: SettingsStore().load()))
    exit(0)
} else if arguments.contains("--idle") {
    Diagnostics.sampleIdle(seconds: 15)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
