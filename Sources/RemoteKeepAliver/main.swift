import Foundation
import KeepAliveCore

let arguments = CommandLine.arguments

if arguments.contains("--list-windows") {
    print(Diagnostics.listWindows())
    exit(0)
} else if arguments.contains("--jiggle-once") {
    print(Diagnostics.jiggleOnce(settings: SettingsStore().load()))
    exit(0)
} else if arguments.contains("--idle") {
    print(Diagnostics.sampleIdle(seconds: 15))
    exit(0)
} else {
    print("GUI not yet wired")
    exit(0)
}
