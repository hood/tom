import AppKit
import SwiftUI

private let floatingBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

/// The expanded list. Non-activating: typing works without stealing the frontmost app.
final class PanelWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = floatingBehavior
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class OrbWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = floatingBehavior
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Owns clicks + hover for the orb windows, so the first click works even when tom is in the background.
final class OrbHostView<Content: View>: NSView {
    let hosting: NSHostingView<Content>
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    init(rootView: Content) {
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
