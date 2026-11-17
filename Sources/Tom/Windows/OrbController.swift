import AppKit
import SwiftUI

/// Builds the idle indicator: an orb in the chosen corner of every display, a menu bar orb, or nothing.
@MainActor
final class OrbController: NSObject {
    let store: TodoStore
    let settings: AppSettings
    var onClick: () -> Void = {}

    /// One orb window per display.
    @MainActor private final class Slot {
        let window: OrbWindow
        let hover = HoverState()
        let screenID: CGDirectDisplayID
        let base: CGRect
        let peek: CGRect
        var hoverTask: Task<Void, Never>?

        init(window: OrbWindow, screenID: CGDirectDisplayID, base: CGRect, peek: CGRect) {
            self.window = window
            self.screenID = screenID
            self.base = base
            self.peek = peek
        }
    }

    private var slots: [Slot] = []
    private var statusItem: NSStatusItem?
    private var placement: OrbPlacement = .topRight
    private var hiddenSlot: Slot?
    private var panelOpen = false

    init(store: TodoStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func rebuild() {
        teardown()
        placement = settings.placement
        guard !settings.hidden else { return }
        switch placement {
        case .menuBar: buildStatusItem()
        default: NSScreen.screens.forEach(buildCorner)
        }
    }

    /// Where the panel should morph out of (screen coords), on the display you're using.
    func anchorRect() -> CGRect {
        let f = settings.fullness(for: store.activeCount)
        let active = ScreenLayout.activeScreen
        if settings.hidden { return ScreenLayout.fallbackAnchor(placement, fullness: f, on: active) }
        switch placement {
        case .menuBar:
            if let w = statusItem?.button?.window, w.screen == active {
                let d = ScreenLayout.smallOrbDiameter(f)
                return CGRect(x: w.frame.midX - d / 2, y: w.frame.midY - d / 2, width: d, height: d)
            }
            return ScreenLayout.fallbackAnchor(placement, fullness: f, on: active)
        default:
            guard let slot = slot(for: active) else { return ScreenLayout.fallbackAnchor(placement, fullness: f, on: active) }
            let d = ScreenLayout.orbDiameter(f)
            return CGRect(x: slot.base.midX - d / 2, y: slot.base.midY - d / 2, width: d, height: d)
        }
    }

    /// Hides the orb the panel morphs out of while it's open.
    func setPanelOpen(_ open: Bool) {
        panelOpen = open
        if open {
            hiddenSlot = slot(for: ScreenLayout.activeScreen)
            hiddenSlot?.window.alphaValue = 0
        } else {
            for s in slots {
                s.hoverTask?.cancel()
                s.hover.isHovering = false
                s.window.setFrame(s.base, display: false)
                s.window.alphaValue = 1
            }
            hiddenSlot = nil
        }
    }

    // MARK: builders

    private func slot(for screen: NSScreen) -> Slot? {
        slots.first { $0.screenID == screen.displayID } ?? slots.first
    }

    private func buildCorner(on s: NSScreen) {
        let c = ScreenLayout.cornerCenter(placement, s)
        let box = ScreenLayout.orbBox
        let base = CGRect(x: c.x - box / 2, y: c.y - box / 2, width: box, height: box)
        let peekW: CGFloat = 280
        let peek = placement.isLeft
            ? CGRect(x: base.minX, y: base.minY, width: box + peekW, height: box)
            : CGRect(x: base.maxX - box - peekW, y: base.minY, width: box + peekW, height: box)

        let w = OrbWindow()
        let slot = Slot(window: w, screenID: s.displayID, base: base, peek: peek)
        let host = OrbHostView(rootView: CornerOrbView(store: store, settings: settings, hover: slot.hover, leftSide: placement.isLeft))
        host.onClick = { [weak self] in self?.onClick() }
        host.onHover = { [weak self, weak slot] inside in
            guard let self, let slot else { return }
            self.hoverChanged(slot, inside)
        }
        w.contentView = host
        w.setFrame(base, display: true)
        w.orderFrontRegardless()
        slots.append(slot)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 26)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked)
            let wrap = PassthroughView(frame: button.bounds)
            wrap.autoresizingMask = [.width, .height]
            let host = NSHostingView(rootView: StatusOrbView(store: store, settings: settings))
            host.frame = wrap.bounds
            host.autoresizingMask = [.width, .height]
            wrap.addSubview(host)
            button.addSubview(wrap)
        }
        statusItem = item
    }

    @objc private func statusClicked() { onClick() }

    private func teardown() {
        for s in slots {
            s.hoverTask?.cancel()
            s.window.orderOut(nil)
        }
        slots = []
        hiddenSlot = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: hover peek

    private func hoverChanged(_ slot: Slot, _ inside: Bool) {
        guard !panelOpen else { return }
        slot.hoverTask?.cancel()
        if inside {
            slot.hoverTask = Task { @MainActor [weak slot] in
                try? await Task.sleep(for: .milliseconds(140))
                guard let slot, !Task.isCancelled else { return }
                slot.window.setFrame(slot.peek, display: true)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { slot.hover.isHovering = true }
            }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { slot.hover.isHovering = false }
            slot.hoverTask = Task { @MainActor [weak slot] in
                try? await Task.sleep(for: .milliseconds(380))
                guard let slot, !Task.isCancelled, !slot.hover.isHovering else { return }
                slot.window.setFrame(slot.base, display: true)
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

extension NSView {
    func firstDescendant(where f: (NSView) -> Bool) -> NSView? {
        for v in subviews {
            if f(v) { return v }
            if let d = v.firstDescendant(where: f) { return d }
        }
        return nil
    }
}
