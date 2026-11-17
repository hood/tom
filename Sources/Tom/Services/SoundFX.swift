import AVFoundation

/// Tiny synthesized ASMR pops. No assets.
@MainActor
final class SoundFX {
    static let shared = SoundFX()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let sr: Double = 44100
    private let format: AVAudioFormat
    private var running = false
    private var stopTask: Task<Void, Never>?

    /// Complete: press + release, like a mechanical switch.
    private lazy var doneBuf = makeBuffer(Self.click(sr: sr, pitch: 1.0, release: true))
    /// Add: single, slightly higher tick.
    private lazy var addBuf = makeBuffer(Self.click(sr: sr, pitch: 1.25, release: false))

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
    }

    func warmUp() {
        stopTask?.cancel()
        if players.isEmpty {
            for _ in 0..<4 {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: engine.mainMixerNode, format: format)
                players.append(p)
            }
            _ = (doneBuf, addBuf)
        }
        guard !running else { return }
        do { try engine.start(); running = true } catch { running = false }
    }

    /// Stop the engine a bit after the panel closes so the audio device can sleep.
    func coolDown() {
        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            self.engine.stop()
            self.running = false
        }
    }

    func done(enabled: Bool) { if enabled { play(doneBuf, volume: 0.12) } }
    func add(enabled: Bool) { if enabled { play(addBuf, volume: 0.07) } }

    private func play(_ buf: AVAudioPCMBuffer, volume: Float) {
        warmUp()
        guard running else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.volume = volume
        p.scheduleBuffer(buf, at: nil)
        p.play()
    }

    private func makeBuffer(_ mono: [Float]) -> AVAudioPCMBuffer {
        let n = mono.count
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        b.frameLength = AVAudioFrameCount(n)
        mono.withUnsafeBufferPointer {
            b.floatChannelData![0].update(from: $0.baseAddress!, count: n)
            b.floatChannelData![1].update(from: $0.baseAddress!, count: n)
        }
        return b
    }

    /// Dry mechanical click: noise transient + two fast-dying modes + a tiny body thump. ~25ms, no tail.
    static func click(sr: Double, pitch: Double, release: Bool) -> [Float] {
        let n = Int(sr * (release ? 0.06 : 0.03))
        var out = [Float](repeating: 0, count: n)
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 2 - 1
        }
        func strike(at t0: Double, gain: Double, tune: Double) {
            let s0 = Int(t0 * sr)
            for i in s0..<n {
                let t = Double(i - s0) / sr
                var v = noise() * exp(-t * 3200) * 0.7
                v += sin(2 * .pi * 1850 * tune * t) * exp(-t * 520)
                v += 0.55 * sin(2 * .pi * 3050 * tune * t) * exp(-t * 700)
                v += 0.35 * sin(2 * .pi * 170 * t) * exp(-t * 160)
                out[i] += Float(v * gain)
            }
        }
        strike(at: 0, gain: 1, tune: pitch)
        if release { strike(at: 0.032, gain: 0.45, tune: pitch * 1.12) }
        // gentle low-pass (~6 kHz) to keep it from getting sharp
        let a = 1 - exp(-2 * .pi * 6000 / sr)
        var lp = 0.0
        for i in out.indices { lp += a * (Double(out[i]) - lp); out[i] = Float(lp) }
        let fadeN = Int(sr * 0.004)
        for k in 0..<fadeN { out[n - 1 - k] *= Float(k) / Float(fadeN) }
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / peak * 0.7 }
    }
}
