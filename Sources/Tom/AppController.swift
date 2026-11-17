import AppKit
import SwiftUI

@MainActor
final class AppController {
    let store = TodoStore()
    let settings = AppSettings()
    private(set) lazy var model = PanelModel(store: store, settings: settings)
    private let panel = PanelWindow()
    private lazy var orb = OrbController(store: store, settings: settings)
    private var settingsWindow: NSWindow?
    private var isOpen = false
    private var lastClose: CFTimeInterval = 0
    private var openedAt: CFTimeInterval = 0
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    func start() {
        _ = MetalContext.shared
        if store.isFirstLaunch { seed() }

        let host = NSHostingView(rootView: PanelRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host

        model.requestClose = { [weak self] in self?.close() }
        model.requestSettings = { [weak self] in self?.showSettings() }
        orb.onClick = { [weak self] in self?.toggle() }
        settings.onLayoutChange = { [weak self] in self?.orb.rebuild() }
        settings.onHotKeyChange = { [weak self] in self?.registerHotKey() }
        HotKeyCenter.shared.onPress = { [weak self] in self?.toggle() }
        registerHotKey()
        orb.rebuild()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // launch-time activation shuffles can steal key right after opening: take it back instead of closing
                self.dbg("resign key dt=\(CACurrentMediaTime() - self.openedAt) active=\(NSApp.isActive) keyWin=\(String(describing: NSApp.keyWindow))")
                if ProcessInfo.processInfo.environment["TOM_CAPTURE"] != nil { return }
                if self.isOpen, CACurrentMediaTime() - self.openedAt < 0.8 {
                    self.panel.makeKey()
                    return
                }
                self.close()
            }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.orb.rebuild() }
        })
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { (self?.handleKey(e) ?? false) ? nil : e }
        }

        if let dir = ProcessInfo.processInfo.environment["TOM_CAPTURE"] {
            after(2.0) { DebugCapture.captureOwnWindows(to: dir) }
        }
        if CommandLine.arguments.contains("--open") { after(0.5) { [weak self] in self?.open() } }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            after(0.4) { [weak self] in self?.open() }
            if CommandLine.arguments.contains("--demo-complete") {
                after(1.2) { [weak self] in
                    guard let self, let id = self.store.active.first?.id else { return }
                    self.model.complete(id)
                    after(0.5) { print("burning:", self.model.burning.count, "overlay:", self.model.overlay != nil) }
                }
                after(3.0) { [weak self] in self?.model.showDone = true }
                after(3.6) { [weak self] in self?.debugSnapshot(path) }
            } else {
                after(2.0) { [weak self] in self?.debugSnapshot(path) }
            }
        }
    }

    private func seed() {
        let hk = settings.hotKey.display
        for t in ["welcome to tom ✦", "tick the circle and watch it burn", "\(hk) summons me from anywhere"] {
            store.add(t, atEnd: true)
        }
    }

    private func registerHotKey() {
        let ok = HotKeyCenter.shared.register(settings.hotKey)
        settings.hotKeyError = ok ? nil : "\(settings.hotKey.display) is taken by another app. Pick another."
    }

    // MARK: open / close

    func toggle() {
        if isOpen { close() } else if CACurrentMediaTime() - lastClose > 0.25 { open() }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        openedAt = CACurrentMediaTime()
        store.purgeOld()

        let g = ScreenLayout.panelGeometry(placement: settings.placement, anchor: orb.anchorRect())
        model.geometry = g
        model.selection = nil
        model.editing = nil
        model.expanded = false
        model.isOpen = true
        panel.setFrame(g.windowFrame, display: false)
        model.backingScale = panel.backingScaleFactor

        orb.setPanelOpen(true)
        SoundFX.shared.warmUp()
        panel.orderFrontRegardless()
        panel.makeKey()
        dbg("open: isKey=\(panel.isKeyWindow) active=\(NSApp.isActive) screen=\(panel.screen?.localizedName ?? "nil")")

        after(0.016) { [weak self] in
            guard let self, self.isOpen else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { self.model.expanded = true }
            self.model.focusInput += 1
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        lastClose = CACurrentMediaTime()
        model.editing = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9), completionCriteria: .logicallyComplete) {
            model.expanded = false
        } completion: { [weak self] in
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
            self.model.isOpen = false
            self.orb.setPanelOpen(false)
            SoundFX.shared.coolDown()
        }
    }

    func showSettings() {
        close()
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store))
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func debugSnapshot(_ path: String) {
        guard let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("geometry", model.geometry, "content", model.contentHeight, "frames", model.rowFrames.values.map { $0 })
        print("orb anchor", orb.anchorRect(), "panel frame", panel.frame, "key", panel.isKeyWindow)
        fflush(stdout)
    }

    private func dbg(_ m: String) {
        guard ProcessInfo.processInfo.environment["TOM_DEBUG"] != nil else { return }
        print(m); fflush(stdout)
    }

    // MARK: keyboard

    private func handleKey(_ e: NSEvent) -> Bool {
        guard isOpen, panel.isKeyWindow else { return false }
        let cmd = e.modifierFlags.contains(.command)
        let opt = e.modifierFlags.contains(.option)
        switch e.keyCode {
        case 53: // esc
            if model.editing != nil {
                model.editing = nil
                model.focusInput += 1
            } else {
                close()
            }
            return true
        case 125, 126: // down, up
            guard model.editing == nil else { return false }
            let d = e.keyCode == 125 ? 1 : -1
            if opt { model.shiftSelection(d) } else { model.moveSelection(d) }
            return true
        case 36 where cmd: // cmd+return
            model.completeSelectedOrFirst()
            return true
        case 51 where cmd: // cmd+backspace
            model.deleteSelected()
            return true
        case 13 where cmd: // cmd+w
            close()
            return true
        case 43 where cmd: // cmd+,
            showSettings()
            return true
        default:
            return false
        }
    }
}
