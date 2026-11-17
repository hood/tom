import SwiftUI

@MainActor @Observable
final class HoverState {
    var isHovering = false
}

struct PeekLabel: View {
    let store: TodoStore
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            if let first = store.active.first {
                Text(first.text).lineLimit(1)
                if store.activeCount > 1 {
                    Text("+\(store.activeCount - 1)").foregroundStyle(accent)
                }
            } else {
                Text("Mind clear").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}

struct CornerOrbView: View {
    let store: TodoStore
    let settings: AppSettings
    let hover: HoverState
    let leftSide: Bool

    var body: some View {
        let f = settings.fullness(for: store.activeCount)
        let accent = Palette.color(f)
        let box = ScreenLayout.orbBox
        HStack(spacing: 0) {
            if !leftSide { Spacer(minLength: 0); peek(accent) }
            PlasmaView(fullness: f, hover: hover.isHovering,
                       radius: Double(ScreenLayout.orbDiameter(0) / box)...Double(ScreenLayout.orbDiameter(1) / box),
                       glow: true, fps: 40)
                .frame(width: box, height: box)
            if leftSide { peek(accent); Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func peek(_ accent: Color) -> some View {
        if hover.isHovering {
            PeekLabel(store: store, accent: accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .frame(maxWidth: 270, alignment: leftSide ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: leftSide ? .leading : .trailing).combined(with: .opacity),
                    removal: .opacity))
        }
    }
}

struct StatusOrbView: View {
    let store: TodoStore
    let settings: AppSettings

    var body: some View {
        GeometryReader { g in
            let m = max(min(g.size.width, g.size.height), 1)
            let lo = Double(min(ScreenLayout.smallOrbDiameter(0), m - 4) / m)
            let hi = Double(min(ScreenLayout.smallOrbDiameter(1), m - 4) / m)
            PlasmaView(fullness: settings.fullness(for: store.activeCount),
                       radius: max(lo, 0.1)...max(hi, lo, 0.1),
                       glow: true, fps: 30)
        }
    }
}
