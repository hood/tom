import SwiftUI
import MetalKit

final class PlasmaMTKView: MetalLayerView {
    var targetFullness: Float = 0
    var targetHover: Float = 0
    var morph: Float = 0
    var radiusMin: Float = 0.3
    var radiusMax: Float = 0.4
    var glow: Float = 1
    var intensity: Float = 0.5
    var wash: Float = 0
    var center = CGPoint(x: -1, y: -1)
    var orbPts: Float = 0
    var lastPulseToken = 0

    private var fullness: Float = -1
    private var hover: Float = 0
    private var pulse: Float = 0
    private var lastTime = CACurrentMediaTime()

    override init() {
        super.init()
        preferredFramesPerSecond = 60
    }

    required init(coder: NSCoder) { fatalError() }

    func firePulse() { pulse = 1 }

    override func render() {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTime, 0.1))
        lastTime = now
        if fullness < 0 { fullness = targetFullness }
        fullness += (targetFullness - fullness) * min(1, dt * 2.5)
        hover += (targetHover - hover) * min(1, dt * 9)
        pulse = max(0, pulse - dt * 1.6)

        guard bounds.width > 1, bounds.height > 1,
              let (rpd, drawable) = beginFrame(),
              let cb = MetalContext.shared.queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var u = PlasmaUniforms(
            time: MetalContext.time, fullness: fullness, hover: hover, morph: morph,
            sizeX: Float(bounds.width), sizeY: Float(bounds.height), radiusMin: radiusMin, radiusMax: radiusMax,
            glow: glow, intensity: intensity, wash: wash, pulse: pulse,
            centerX: Float(center.x), centerY: Float(center.y), orbPts: orbPts)
        enc.setRenderPipelineState(MetalContext.shared.plasmaPipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<PlasmaUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

/// The liquid plasma orb. `radius` is in units of half the view's shorter side.
struct PlasmaView: NSViewRepresentable {
    var fullness: Double
    var hover: Bool = false
    var morph: Double = 0
    var radius: ClosedRange<Double> = 0.3...0.4
    var glow: Bool = true
    var intensity: Double = 0.5
    var running: Bool = true
    /// Panel-open energy wash bursting from `center` (points, top-left origin).
    var wash: Bool = false
    var center: CGPoint = CGPoint(x: -1, y: -1)
    var orbRadius: CGFloat = 0
    var fps: Int = 60
    var pulseToken: Int = 0

    func makeNSView(context: Context) -> PlasmaMTKView { PlasmaMTKView() }

    func updateNSView(_ v: PlasmaMTKView, context: Context) {
        v.targetFullness = Float(fullness)
        v.targetHover = hover ? 1 : 0
        v.morph = Float(morph)
        v.radiusMin = Float(radius.lowerBound)
        v.radiusMax = Float(radius.upperBound)
        v.glow = glow ? 1 : 0
        v.intensity = Float(intensity)
        v.wash = wash ? 1 : 0
        v.center = center
        v.orbPts = Float(orbRadius)
        if v.preferredFramesPerSecond != fps { v.preferredFramesPerSecond = fps }
        if v.isPaused == running { v.isPaused = !running }
        if pulseToken != v.lastPulseToken { v.lastPulseToken = pulseToken; v.firePulse() }
    }
}
