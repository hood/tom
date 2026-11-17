import AppKit

MainActor.assumeIsolated {
    if let i = CommandLine.arguments.firstIndex(of: "--vfx-test") {
        let out = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "vfx-test"
        VFXTest.run(outDir: out)
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
