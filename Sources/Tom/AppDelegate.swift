import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = AppController()
        controller = c
        c.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.open()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.store.flush()
    }
}

@MainActor
func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        body()
    }
}
