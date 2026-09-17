import AppKit

@MainActor
final class ShoreAppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: ShoreRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let runtime = ShoreRuntime()
        self.runtime = runtime
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        runtime = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
