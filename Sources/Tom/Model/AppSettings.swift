import Foundation
import Observation
import Carbon.HIToolbox

enum OrbPlacement: String, CaseIterable, Identifiable, Codable {
    case menuBar, topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Menu bar"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    var isCorner: Bool { self != .menuBar }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var growsUp: Bool { self == .bottomLeft || self == .bottomRight }
}

enum VisualQuality: String, CaseIterable, Identifiable {
    case candy, performance
    var id: String { rawValue }
    var title: String { self == .candy ? "Candy" : "Performance" }
}

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let standard = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), display: "⌥ Space")
}

@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored var onHotKeyChange: (() -> Void)?

    var placement: OrbPlacement {
        didSet { defaults.set(placement.rawValue, forKey: "placement"); onLayoutChange?() }
    }
    /// Invisible mode: no orb at all, hotkey only.
    var hidden: Bool {
        didSet { defaults.set(hidden, forKey: "hidden"); onLayoutChange?() }
    }
    var quality: VisualQuality {
        didSet { defaults.set(quality.rawValue, forKey: "quality"); RenderQuality.isPerformance = quality == .performance }
    }
    var soundOn: Bool {
        didSet { defaults.set(soundOn, forKey: "soundOn") }
    }
    /// Item count at which the orb is completely full (and red).
    var fullAt: Int {
        didSet { defaults.set(fullAt, forKey: "fullAt") }
    }
    var hotKey: HotKeyCombo {
        didSet {
            if let d = try? JSONEncoder().encode(hotKey) { defaults.set(d, forKey: "hotKey") }
            onHotKeyChange?()
        }
    }
    var hotKeyError: String?

    init() {
        let d = UserDefaults.standard
        placement = OrbPlacement(rawValue: d.string(forKey: "placement") ?? "") ?? .topRight
        hidden = d.bool(forKey: "hidden")
        soundOn = d.object(forKey: "soundOn") as? Bool ?? true
        let q = VisualQuality(rawValue: d.string(forKey: "quality") ?? "") ?? .candy
        quality = q
        RenderQuality.isPerformance = q == .performance
        let fa = d.integer(forKey: "fullAt")
        fullAt = fa == 0 ? 8 : fa
        if let data = d.data(forKey: "hotKey"), let hk = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            hotKey = hk
        } else {
            hotKey = .standard
        }
    }

    func fullness(for count: Int) -> Double {
        min(1, Double(count) / Double(max(fullAt, 1)))
    }
}
