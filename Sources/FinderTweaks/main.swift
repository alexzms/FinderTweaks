import AppKit

let arguments = CommandLine.arguments
if arguments.count >= 3 && arguments[1] == "--snapshot" {
    // Dev aid: render UI states to PNGs without touching Finder (`make snapshot`).
    _ = NSApplication.shared
    Snapshot.render(to: arguments[2])
    exit(0)
}
if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
    exit(0)  // already running
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
