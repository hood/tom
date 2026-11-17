import AppKit
import SwiftUI
import Metal
import UniformTypeIdentifiers

/// `Tom --vfx-test <dir>` renders orb + dissolve frames offscreen to PNGs, for eyeballing the shaders.
@MainActor
enum VFXTest {
    static func run(outDir: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let bg = CGColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1)

        let orbs = [0.0, 0.25, 0.5, 0.75, 1.0].map { f in
            renderPlasma(size: CGSize(width: 56, height: 56), scale: 4,
                         u: PlasmaUniforms(time: 3, fullness: Float(f), radiusMin: 15 / 56, radiusMax: 22 / 56, glow: 1))
        }
        save(hstack(orbs, bg: bg), "\(outDir)/orbs.png")

        let morphs = [0.0, 0.3, 0.6, 1.0].map { m in
            renderPlasma(size: CGSize(width: 180, height: 140), scale: 2,
                         u: PlasmaUniforms(time: 3, fullness: 0.6, morph: Float(m), radiusMin: 1, radiusMax: 1,
                                           glow: 0, intensity: 0.6))
        }
        save(hstack(morphs, bg: bg), "\(outDir)/morph.png")

        let accent = Palette.color(0.5)
        let row = TodoRowContent(text: "reply to the infra thread before standup", checked: true, accent: accent)
            .frame(width: 328, height: 42).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: row)
        r.scale = 2
        guard let snap = r.cgImage else { print("snapshot failed"); return }
        let tex = MetalContext.shared.texture(from: snap)!
        let frames = [0.0, 0.15, 0.3, 0.45, 0.65, 0.9, 1.3].map { t -> CGImage in
            renderParticles(tex: tex, time: Float(t), view: CGSize(width: 420, height: 200),
                            frame: CGRect(x: 40, y: 120, width: 328, height: 42), scale: 2)
        }
        save(vstack(frames, bg: bg), "\(outDir)/dissolve.png")
        let store = TodoStore()
        let model = PanelModel(store: store, settings: AppSettings())
        let panel = ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.1)
            PanelContent(model: model).fixedSize(horizontal: false, vertical: true)
        }
        .environment(\.colorScheme, .dark)
        let pr = ImageRenderer(content: panel)
        pr.scale = 2
        if let img = pr.cgImage { save(img, "\(outDir)/panel.png") }
        print("wrote \(outDir)")
    }

    private static func target(_ px: CGSize) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(px.width), height: Int(px.height), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        return MetalContext.shared.device.makeTexture(descriptor: d)!
    }

    private static func pass(_ t: MTLTexture) -> MTLRenderPassDescriptor {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = t
        p.colorAttachments[0].loadAction = .clear
        p.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        p.colorAttachments[0].storeAction = .store
        return p
    }

    static func renderPlasma(size: CGSize, scale: CGFloat, u: PlasmaUniforms) -> CGImage {
        let t = target(CGSize(width: size.width * scale, height: size.height * scale))
        var u = u
        u.sizeX = Float(size.width); u.sizeY = Float(size.height)
        let cb = MetalContext.shared.queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass(t))!
        enc.setRenderPipelineState(MetalContext.shared.plasmaPipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<PlasmaUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        return image(t)
    }

    static func renderParticles(tex: MTLTexture, time: Float, view: CGSize, frame: CGRect, scale: CGFloat) -> CGImage {
        let t = target(CGSize(width: view.width * scale, height: view.height * scale))
        let b = ParticleOverlayView.Burst(texture: tex, frame: frame, start: 0, seed: 7, texScale: Float(scale))
        var u = ParticleOverlayView.uniforms(b, time: time, view: view, pointScale: Float(scale))
        let cb = MetalContext.shared.queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass(t))!
        enc.setRenderPipelineState(MetalContext.shared.particlePipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
        enc.setVertexTexture(tex, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: tex.width * tex.height)
        enc.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        return image(t)
    }

    private static func image(_ t: MTLTexture) -> CGImage {
        let w = t.width, h = t.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        t.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        // clamp super-luminous (additive) pixels so CG accepts them as premultiplied
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = bytes[i + 3]
            if bytes[i] > a || bytes[i + 1] > a || bytes[i + 2] > a {
                bytes[i + 3] = max(bytes[i], bytes[i + 1], bytes[i + 2], a)
            }
        }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        return ctx.makeImage()!
    }

    private static func hstack(_ imgs: [CGImage], bg: CGColor) -> CGImage {
        let w = imgs.reduce(0) { $0 + $1.width }, h = imgs.map(\.height).max()!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var x = 0
        for i in imgs { ctx.draw(i, in: CGRect(x: x, y: 0, width: i.width, height: i.height)); x += i.width }
        return ctx.makeImage()!
    }

    private static func vstack(_ imgs: [CGImage], bg: CGColor) -> CGImage {
        let h = imgs.reduce(0) { $0 + $1.height }, w = imgs.map(\.width).max()!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var y = h
        for i in imgs {
            y -= i.height
            ctx.draw(i, in: CGRect(x: 0, y: y, width: i.width, height: i.height))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.1)); ctx.stroke(CGRect(x: 0, y: y, width: w, height: 1))
        }
        return ctx.makeImage()!
    }

    private static func save(_ img: CGImage, _ path: String) {
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}

