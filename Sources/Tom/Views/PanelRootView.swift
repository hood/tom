import SwiftUI

struct PanelRootView: View {
    let model: PanelModel

    var body: some View {
        let g = model.geometry
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.requestClose() }
            MorphContainer(progress: model.expanded ? 1 : 0, contentHeight: model.contentHeight, bloom: model.bloom,
                           geometry: g, fullness: model.fullness, running: model.isOpen) {
                PanelContent(model: model)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                        guard abs(h - model.contentHeight) > 0.5 else { return }
                        if model.expanded {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.contentHeight = h }
                        } else {
                            model.contentHeight = h
                        }
                    }
            }
            ParticleOverlay(model: model)
                .allowsHitTesting(false)
        }
        .frame(width: g.windowFrame.width, height: g.windowFrame.height)
        .coordinateSpace(.named("root"))
    }
}

/// Interpolates the orb (start rect) into the panel (end rect).
/// Width leads and height follows, so the orb stretches into a pill and pours into the panel.
struct MorphContainer<Content: View>: View, Animatable {
    var progress: CGFloat
    var contentHeight: CGFloat
    var bloom: CGFloat
    let geometry: PanelGeometry
    let fullness: Double
    let running: Bool
    @ViewBuilder let content: () -> Content

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(progress, contentHeight), bloom) }
        set { progress = newValue.first.first; contentHeight = newValue.first.second; bloom = newValue.second }
    }

    var body: some View {
        let p = progress
        let cp = clamp01(p)
        let wp = p >= 1 ? p : min(1, p * 1.3)
        let hp = p >= 1 ? p : max(0, (p - 0.22) / 0.78)
        let s = geometry.start
        let e = geometry.endRect(height: contentHeight)
        let w = max(2, lerp(s.width, e.width, wp))
        let h = max(2, lerp(s.height, e.height, hp))
        // keep the orb's corner pinned while growing
        let x = lerp(s.minX, e.minX, wp)
        let y = geometry.growsUp ? lerp(s.maxY, e.maxY, hp) - h : lerp(s.minY, e.minY, hp)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let radius = min(lerp(geometry.startRadius, PanelGeometry.cornerRadius, cp), min(w, h) / 2)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let contentOpacity = smoothstep(0.15, 0.6, p)
        let orbCenter = CGPoint(x: s.midX - rect.minX, y: s.midY - rect.minY)

        ZStack(alignment: .top) {
            if running && bloom < 0.999 {
                PlasmaView(fullness: fullness, morph: bloom, radius: 1...1, glow: false, intensity: 0, running: running,
                           wash: true, center: orbCenter, orbRadius: min(s.width, s.height) / 2)
            }
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: PanelGeometry.width)
                .scaleEffect(lerp(0.96, 1, cp), anchor: geometry.growsUp ? .bottom : .top)
                .blur(radius: (1 - contentOpacity) * 6)
                .opacity(contentOpacity)
        }
        .frame(width: rect.width, height: rect.height, alignment: .top)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(0.18 * cp), radius: 14, y: 6)
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// Staggered entrance: item `index` fades, slides and sharpens in as `t` goes 0 -> 1.
struct Reveal: ViewModifier, Animatable {
    var t: CGFloat
    let index: Int
    let fromBelow: Bool

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let local = smoothstep(0, 1, (t - CGFloat(index) * 0.06) / 0.4)
        content
            .opacity(local)
            .offset(y: (1 - local) * (fromBelow ? 8 : -8))
            .blur(radius: (1 - local) * 3)
    }
}

extension View {
    func reveal(_ t: CGFloat, _ index: Int, fromBelow: Bool = false) -> some View {
        modifier(Reveal(t: t, index: index, fromBelow: fromBelow))
    }
}
