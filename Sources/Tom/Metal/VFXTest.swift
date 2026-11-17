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

        let morphs = [0.0, 0.08, 0.18, 0.32, 0.5, 0.75].map { b in
            renderPlasma(size: CGSize(width: 240, height: 200), scale: 1,
                         u: PlasmaUniforms(time: 3, fullness: 0.8, morph: Float(b), radiusMin: 1, radiusMax: 1,
                                           glow: 0, intensity: 0, wash: 1, centerX: 228, centerY: 12, orbPts: 9))
        }
        save(hstack(morphs, bg: bg), "\(outDir)/morph.png")

        // perf-mode look
        let perfOrbs = [0.0, 0.25, 0.5, 0.75, 1.0].map { f in
            renderPlasma(size: CGSize(width: 56, height: 56), scale: 2,
                         u: PlasmaUniforms(time: 3, fullness: Float(f), radiusMin: 15 / 56, radiusMax: 22 / 56, glow: 1, quality: 0))
        }
        save(hstack(perfOrbs, bg: bg), "\(outDir)/orbs-perf.png")
        let perfMorphs = [0.0, 0.18, 0.32, 0.5].map { b in
            renderPlasma(size: CGSize(width: 240, height: 200), scale: 1,
                         u: PlasmaUniforms(time: 3, fullness: 0.8, morph: Float(b), radiusMin: 1, radiusMax: 1,
                                           glow: 0, intensity: 0, wash: 1, centerX: 228, centerY: 12, orbPts: 9, quality: 0))
        }
        save(hstack(perfMorphs, bg: bg), "\(outDir)/morph-perf.png")

        // GPU cost: panel-sized wash frame and an orb, candy (2x) vs perf (1x)
        func gpuMs(size: CGSize, scale: CGFloat, u: PlasmaUniforms, frames: Int = 120) -> Double {
            let t = target(CGSize(width: size.width * scale, height: size.height * scale))
            var u = u
            u.sizeX = Float(size.width); u.sizeY = Float(size.height)
            var total = 0.0
            for i in 0..<frames {
                u.time = Float(i) / 60
                let cb = MetalContext.shared.queue.makeCommandBuffer()!
                let enc = cb.makeRenderCommandEncoder(descriptor: pass(t))!
                enc.setRenderPipelineState(MetalContext.shared.plasmaPipeline)
                enc.setFragmentBytes(&u, length: MemoryLayout<PlasmaUniforms>.stride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
                cb.commit(); cb.waitUntilCompleted()
                if i >= 10 { total += cb.gpuEndTime - cb.gpuStartTime }
            }
            return total / Double(frames - 10) * 1000
        }
        let panelSize = CGSize(width: 360, height: 480)
        let wash = PlasmaUniforms(fullness: 0.8, morph: 0.3, radiusMin: 1, radiusMax: 1, glow: 0, intensity: 0,
                                  wash: 1, centerX: 350, centerY: 10, orbPts: 9)
        var washPerf = wash; washPerf.quality = 0
        let orb = PlasmaUniforms(fullness: 0.8, radiusMin: 15 / 56, radiusMax: 22 / 56, glow: 1)
        var orbPerf = orb; orbPerf.quality = 0
        print(String(format: "GPU ms/frame  wash candy@2x %.3f  perf@1x %.3f", gpuMs(size: panelSize, scale: 2, u: wash), gpuMs(size: panelSize, scale: 1, u: washPerf)))
        print(String(format: "GPU ms/frame  orb  candy@2x %.3f  perf@1x %.3f", gpuMs(size: CGSize(width: 56, height: 56), scale: 2, u: orb), gpuMs(size: CGSize(width: 56, height: 56), scale: 1, u: orbPerf)))

        let accent = Palette.color(0.5)
        let row = TodoRowContent(text: "reply to the infra thread before standup", checked: true, accent: accent)
            .frame(width: 328, height: 42).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: row)
        r.scale = 2
        guard let snap = r.cgImage else { print("snapshot failed"); return }
        let tex = MetalContext.shared.texture(from: snap)!
        let frames = [0.0, 0.08, 0.16, 0.25, 0.35, 0.5, 0.7].map { t -> CGImage in
            renderParticles(tex: tex, time: Float(t), view: CGSize(width: 420, height: 200),
                            frame: CGRect(x: 40, y: 120, width: 328, height: 42), scale: 2)
        }
        save(vstack(frames, bg: bg), "\(outDir)/dissolve.png")
        let perfFrames = [0.0, 0.16, 0.35].map { t -> CGImage in
            renderParticles(tex: tex, time: Float(t), view: CGSize(width: 420, height: 200),
                            frame: CGRect(x: 40, y: 120, width: 328, height: 42), scale: 2, stride: 2)
        }
        save(vstack(perfFrames, bg: bg), "\(outDir)/dissolve-perf.png")
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

    static func renderParticles(tex: MTLTexture, time: Float, view: CGSize, frame: CGRect, scale: CGFloat, stride: Int = 1) -> CGImage {
        let t = target(CGSize(width: view.width * scale, height: view.height * scale))
        let b = ParticleOverlayView.Burst(texture: tex, frame: frame, start: 0, seed: 7, texScale: Float(scale), stride: stride)
        var u = ParticleOverlayView.uniforms(b, time: time, view: view, pointScale: Float(scale))
        let cb = MetalContext.shared.queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass(t))!
        enc.setRenderPipelineState(MetalContext.shared.particlePipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
        enc.setVertexTexture(tex, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: b.particleCount)
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

