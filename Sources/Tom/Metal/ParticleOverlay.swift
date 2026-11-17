import SwiftUI
import MetalKit

/// Full-window overlay that turns a snapshot of a row into ~50k pixels of burning ash.
final class ParticleOverlayView: MetalLayerView {
    static let lifetime: Double = 2.4

    struct Burst {
        let texture: MTLTexture
        let frame: CGRect
        let start: CFTimeInterval
        let seed: Float
        let texScale: Float
    }

    private var bursts: [Burst] = []

    override init() {
        super.init()
        preferredFramesPerSecond = 120
        isPaused = true
    }

    required init(coder: NSCoder) { fatalError() }

    func burst(image: CGImage, frame: CGRect, scale: CGFloat) {
        guard let tex = MetalContext.shared.texture(from: image) else { return }
        bursts.append(Burst(texture: tex, frame: frame, start: CACurrentMediaTime(),
                            seed: Float.random(in: 0...100), texScale: Float(scale)))
        isPaused = false
    }

    override func render() {
        let now = CACurrentMediaTime()
        bursts.removeAll { now - $0.start > Self.lifetime }
        guard bounds.width > 1, let (rpd, drawable) = beginFrame(),
              let cb = MetalContext.shared.queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let pointScale = Float(drawableSize.width / bounds.width)
        enc.setRenderPipelineState(MetalContext.shared.particlePipeline)
        for b in bursts {
            var u = Self.uniforms(b, time: Float(now - b.start), view: bounds.size, pointScale: pointScale)
            enc.setVertexBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
            enc.setVertexTexture(b.texture, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: b.texture.width * b.texture.height)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
        if bursts.isEmpty { isPaused = true }
    }

    static func uniforms(_ b: Burst, time: Float, view: CGSize, pointScale: Float) -> ParticleUniforms {
        ParticleUniforms(
            originX: Float(b.frame.minX), originY: Float(b.frame.minY),
            rowW: Float(b.frame.width), rowH: Float(b.frame.height),
            viewW: Float(view.width), viewH: Float(view.height),
            texW: Float(b.texture.width), texH: Float(b.texture.height),
            time: time, seed: b.seed, pointScale: pointScale, texScale: b.texScale)
    }
}

struct ParticleOverlay: NSViewRepresentable {
    let model: PanelModel

    func makeNSView(context: Context) -> ParticleOverlayView {
        let v = ParticleOverlayView()
        model.overlay = v
        return v
    }

    func updateNSView(_ nsView: ParticleOverlayView, context: Context) {
        model.overlay = nsView
    }
}
