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

    /// Complete: rounder, a touch lower.
    private lazy var doneBuf = makeBuffer(Self.bubblePop(sr: sr, startHz: 620, endHz: 170, decay: 75, click: 0.18))
    /// Add: smaller, higher, quieter.
    private lazy var addBuf = makeBuffer(Self.bubblePop(sr: sr, startHz: 900, endHz: 320, decay: 110, click: 0.1))

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

    func done(enabled: Bool) { if enabled { play(doneBuf, volume: 0.22) } }
    func add(enabled: Bool) { if enabled { play(addBuf, volume: 0.12) } }

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

    /// Bubble pop: a sine that drops in pitch fast, a soft wet click on top, all low-passed.
    static func bubblePop(sr: Double, startHz: Double, endHz: Double, decay: Double, click: Double) -> [Float] {
        let n = Int(sr * 0.07)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0, lp = 0.0
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        let a = 1 - exp(-2 * .pi * 2400 / sr) // one-pole low-pass ~2.4 kHz: no piercing highs
        for i in 0..<n {
            let t = Double(i) / sr
            let f = endHz + (startHz - endHz) * exp(-t * 95)
            phase += 2 * .pi * f / sr
            let attack = 1 - exp(-t / 0.0012)
            var s = sin(phase) * attack * exp(-t * decay)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double(seed >> 11) / Double(1 << 53) * 2 - 1
            s += noise * click * exp(-t * 900)
            lp += a * (s - lp)
            out[i] = Float(lp)
        }
        let fadeN = Int(sr * 0.008)
        for k in 0..<fadeN { out[n - 1 - k] *= Float(k) / Float(fadeN) }
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / peak * 0.7 }
    }
}
