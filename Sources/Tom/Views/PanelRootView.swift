import SwiftUI

struct PanelRootView: View {
    let model: PanelModel

    var body: some View {
        let g = model.geometry
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.requestClose() }
            MorphContainer(progress: model.expanded ? 1 : 0, contentHeight: model.contentHeight,
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
            ForEach(model.shockwaves) { ShockwaveView(wave: $0) }
            ParticleOverlay(model: model)
                .allowsHitTesting(false)
        }
        .frame(width: g.windowFrame.width, height: g.windowFrame.height)
        .coordinateSpace(.named("root"))
    }
}

/// Interpolates the orb (start rect) into the panel (end rect). Spring overshoot gives the liquid wobble.
struct MorphContainer<Content: View>: View, Animatable {
    var progress: CGFloat
    var contentHeight: CGFloat
    let geometry: PanelGeometry
    let fullness: Double
    let running: Bool
    @ViewBuilder let content: () -> Content

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, contentHeight) }
        set { progress = newValue.first; contentHeight = newValue.second }
    }

    var body: some View {
        let p = progress
        let cp = clamp01(p)
        let s = geometry.start
        let e = geometry.endRect(height: contentHeight)
        let rect = CGRect(x: lerp(s.minX, e.minX, p), y: lerp(s.minY, e.minY, p),
                          width: max(2, lerp(s.width, e.width, p)), height: max(2, lerp(s.height, e.height, p)))
        let shape = RoundedRectangle(cornerRadius: lerp(geometry.startRadius, PanelGeometry.cornerRadius, cp), style: .continuous)
        let contentOpacity = smoothstep(0.45, 0.95, p)

        ZStack(alignment: .top) {
            // the orb's plasma melts into the glass, then gets out of the way
            if cp < 0.98 {
                PlasmaView(fullness: fullness, morph: cp, radius: 1...1, glow: false, intensity: 0, running: running)
                    .opacity(Double(1 - smoothstep(0.3, 0.9, cp)))
            }
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: PanelGeometry.width)
                .scaleEffect(lerp(0.94, 1, cp), anchor: geometry.growsUp ? .bottom : .top)
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

struct ShockwaveView: View {
    let wave: Shockwave
    @State private var go = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(wave.color, lineWidth: go ? 0.5 : 5)
                .frame(width: 22, height: 22)
                .scaleEffect(go ? 8 : 0.5)
                .opacity(go ? 0 : 0.95)
            Circle()
                .stroke(Color.white, lineWidth: go ? 0.3 : 2)
                .frame(width: 22, height: 22)
                .scaleEffect(go ? 5 : 0.5)
                .opacity(go ? 0 : 0.8)
            Circle()
                .fill(RadialGradient(colors: [.white, wave.color.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 34))
                .frame(width: 68, height: 68)
                .scaleEffect(go ? 1.7 : 0.3)
                .opacity(go ? 0 : 1)
                .blendMode(.plusLighter)
        }
        .position(wave.center)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.75)) { go = true } }
    }
}
