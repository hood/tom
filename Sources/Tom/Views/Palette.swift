import SwiftUI

/// Mirrors `palette()` in the shader: cyan (calm) -> violet -> magenta -> red (full).
enum Palette {
    private static let stops: [(Double, SIMD3<Double>)] = [
        (0.0, [0.20, 0.85, 1.00]),
        (0.33, [0.55, 0.40, 1.00]),
        (0.66, [1.00, 0.30, 0.60]),
        (1.0, [1.00, 0.10, 0.08]),
    ]

    static func rgb(_ f: Double) -> SIMD3<Double> {
        let f = min(max(f, 0), 1)
        for i in 1..<stops.count where f <= stops[i].0 {
            let (a, ca) = stops[i - 1], (b, cb) = stops[i]
            let t = (f - a) / (b - a)
            return ca + (cb - ca) * t
        }
        return stops.last!.1
    }

    static func color(_ f: Double) -> Color {
        let c = rgb(f)
        return Color(red: c.x, green: c.y, blue: c.z)
    }

    static let indigo = Color(red: 0.40, green: 0.48, blue: 1.0)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func clamp01(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
