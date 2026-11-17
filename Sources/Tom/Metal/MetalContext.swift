import Metal
import MetalKit
import QuartzCore

struct PlasmaUniforms {
    var time: Float = 0, fullness: Float = 0, hover: Float = 0, morph: Float = 0
    var sizeX: Float = 1, sizeY: Float = 1, radiusMin: Float = 0.3, radiusMax: Float = 0.4
    var glow: Float = 1, intensity: Float = 0.5, pad: Float = 0, pulse: Float = 0
}

struct ParticleUniforms {
    var originX: Float = 0, originY: Float = 0, rowW: Float = 0, rowH: Float = 0
    var viewW: Float = 1, viewH: Float = 1, texW: Float = 1, texH: Float = 1
    var time: Float = 0, seed: Float = 0, pointScale: Float = 2, texScale: Float = 2
}

@MainActor
final class MetalContext {
    static let shared = MetalContext()
    static let epoch = CACurrentMediaTime()

    /// Shared clock so the orb and the panel morph render the same plasma. Wrapped to keep float precision.
    static var time: Float { Float((CACurrentMediaTime() - epoch).truncatingRemainder(dividingBy: 1800)) }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let plasmaPipeline: MTLRenderPipelineState
    let particlePipeline: MTLRenderPipelineState

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("tom needs Metal")
        }
        self.device = device
        self.queue = queue
        let lib: MTLLibrary
        do { lib = try device.makeLibrary(source: ShaderSource.code, options: nil) } catch {
            fatalError("shader compile failed: \(error)")
        }
        func pipe(_ v: String, _ f: String) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: v)
            d.fragmentFunction = lib.makeFunction(name: f)
            let ca = d.colorAttachments[0]!
            ca.pixelFormat = .bgra8Unorm
            ca.isBlendingEnabled = true
            ca.rgbBlendOperation = .add
            ca.alphaBlendOperation = .add
            ca.sourceRGBBlendFactor = .one
            ca.sourceAlphaBlendFactor = .one
            ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            do { return try device.makeRenderPipelineState(descriptor: d) } catch {
                fatalError("pipeline \(v)/\(f) failed: \(error)")
            }
        }
        plasmaPipeline = pipe("plasma_vertex", "plasma_fragment")
        particlePipeline = pipe("particle_vertex", "particle_fragment")
    }
}

extension MetalContext {
    /// CGImage -> premultiplied RGBA8 texture. ImageRenderer output can be float/extended, which MTKTextureLoader rejects.
    func texture(from img: CGImage) -> MTLTexture? {
        let w = img.width, h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        return t
    }
}

/// Layer-hosting CAMetalLayer view driven by a display link. Never eats clicks.
/// Not MTKView: on this macOS its layer composites as fully transparent inside non-opaque windows.
class MetalLayerView: NSView {
    let metalLayer = CAMetalLayer()
    var preferredFramesPerSecond = 60 { didSet { if oldValue != preferredFramesPerSecond { updateLink() } } }
    var isPaused = false { didSet { if oldValue != isPaused { updateLink() } } }
    private var link: CADisplayLink?

    init() {
        super.init(frame: .zero)
        metalLayer.device = MetalContext.shared.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = .clear
        layer = metalLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var drawableSize: CGSize { metalLayer.drawableSize }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncDrawableSize()
        updateLink()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncDrawableSize()
    }

    private func syncDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let px = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if metalLayer.drawableSize != px { metalLayer.drawableSize = px }
    }

    private func updateLink() {
        link?.invalidate()
        link = nil
        guard window != nil, !isPaused else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        let fps = Float(preferredFramesPerSecond)
        l.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, fps), maximum: fps, preferred: fps)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) { render() }

    /// Subclasses encode a frame here.
    func render() {}

    /// Clear pass on the next drawable, or nil if there's nothing to draw into.
    func beginFrame() -> (MTLRenderPassDescriptor, CAMetalDrawable)? {
        guard bounds.width > 1, bounds.height > 1, let d = metalLayer.nextDrawable() else { return nil }
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = d.texture
        p.colorAttachments[0].loadAction = .clear
        p.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        p.colorAttachments[0].storeAction = .store
        return (p, d)
    }
}
