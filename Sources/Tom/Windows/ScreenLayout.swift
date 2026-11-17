import AppKit

/// Where the panel lives and how it morphs out of the orb. Rects in window-local, top-left-origin points.
struct PanelGeometry: Equatable {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 12

    var windowFrame: CGRect = CGRect(x: 0, y: 0, width: 440, height: 640)
    var start: CGRect = CGRect(x: 200, y: 20, width: 20, height: 20)
    var endX: CGFloat = 40
    /// Top edge (grows down) or bottom edge (grows up) of the expanded panel.
    var anchorY: CGFloat = 40
    var growsUp = false
    var maxHeight: CGFloat = 560
    var startRadius: CGFloat = 10

    func endRect(height: CGFloat) -> CGRect {
        let h = min(max(height, 60), maxHeight)
        return CGRect(x: endX, y: growsUp ? anchorY - h : anchorY, width: Self.width, height: h)
    }
}

@MainActor
enum ScreenLayout {
    static let orbBox: CGFloat = 56
    static let cornerInset: CGFloat = 14
    static let maxOrb: CGFloat = 22

    static var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }
    /// The display you're working on: the one under the mouse.
    static var activeScreen: NSScreen {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? screen
    }

    static func orbDiameter(_ f: Double) -> CGFloat { 15 + 7 * f }
    static func smallOrbDiameter(_ f: Double) -> CGFloat { 11 + 5 * f }

    static func cornerCenter(_ p: OrbPlacement, _ s: NSScreen) -> CGPoint {
        let vf = s.visibleFrame
        let r = maxOrb / 2
        let x = p.isLeft ? vf.minX + cornerInset + r : vf.maxX - cornerInset - r
        let y = p.growsUp ? vf.minY + cornerInset + r : vf.maxY - cornerInset - r
        return CGPoint(x: x, y: y)
    }

    /// Virtual anchor (screen coords) used when the orb is invisible or not built.
    static func fallbackAnchor(_ p: OrbPlacement, fullness f: Double, on s: NSScreen) -> CGRect {
        switch p {
        case .menuBar:
            let d = smallOrbDiameter(f)
            return CGRect(x: s.frame.midX - d / 2, y: s.visibleFrame.maxY - d - 8, width: d, height: d)
        default:
            let c = cornerCenter(p, s), d = orbDiameter(f)
            return CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        }
    }

    /// The panel always stays inside the visible frame: never under the menu bar, notch or dock.
    static func panelGeometry(placement p: OrbPlacement, anchor: CGRect) -> PanelGeometry {
        let s = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? activeScreen
        let vf = s.visibleFrame
        let W = PanelGeometry.width
        let pad: CGFloat = 48
        let x: CGFloat
        let edgeY: CGFloat   // screen coords: top edge, or bottom edge if growing up
        switch p {
        case .menuBar:
            x = min(max(anchor.midX - W / 2, vf.minX + 8), vf.maxX - W - 8)
            edgeY = vf.maxY - 6
        case .topLeft:
            x = anchor.minX; edgeY = anchor.maxY
        case .topRight:
            x = anchor.maxX - W; edgeY = anchor.maxY
        case .bottomLeft:
            x = anchor.minX; edgeY = anchor.minY
        case .bottomRight:
            x = anchor.maxX - W; edgeY = anchor.minY
        }
        let avail = p.growsUp ? (vf.maxY - 16 - edgeY) : (edgeY - vf.minY - 16)
        let maxH = min(580, max(240, avail))
        let panelMax = CGRect(x: x, y: p.growsUp ? edgeY : edgeY - maxH, width: W, height: maxH)
        // shadow/particle padding, but never over the menu bar, tray icons or dock
        var win = panelMax.insetBy(dx: -pad, dy: -pad)
        if p != .menuBar { win = win.union(anchor) }
        win = win.intersection(CGRect(x: s.frame.minX, y: vf.minY, width: s.frame.width, height: vf.height))

        func local(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX - win.minX, y: win.maxY - r.maxY, width: r.width, height: r.height)
        }
        var g = PanelGeometry()
        g.windowFrame = win
        g.start = local(anchor)
        g.endX = x - win.minX
        g.anchorY = win.maxY - edgeY
        g.growsUp = p.growsUp
        g.maxHeight = maxH
        g.startRadius = min(anchor.width, anchor.height) / 2
        return g
    }
}
