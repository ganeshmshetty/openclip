// CopySound.swift
// OpenClip
//
// The short sounds offered for the "Play Sound on Copy" setting. They are synthesized once into
// in-memory WAVs, so the app ships no audio assets, and retained so the first play is as prompt as
// every later one.
import AppKit

public enum CopySound: String, CaseIterable, Identifiable, Sendable {
    case swoosh, tick, thock, bubble, glass

    public var id: String { rawValue }
    public static let `default`: CopySound = .swoosh

    /// English literal; also the localization key.
    public var title: String {
        switch self {
        case .swoosh: return "Swoosh"
        case .tick: return "Tick"
        case .thock: return "Thock"
        case .bubble: return "Bubble"
        case .glass: return "Glass"
        }
    }

    public init(stored: String) { self = CopySound(rawValue: stored) ?? .default }

    @MainActor private static var cache: [CopySound: NSSound] = [:]

    /// Restarts from the beginning, so rapid copies never go silent while the previous one plays.
    @MainActor public func play() {
        let sound: NSSound
        if let cached = Self.cache[self] {
            sound = cached
        } else {
            guard let made = NSSound(data: Self.wavData(samples: samples())) else { return }
            made.volume = 0.6
            Self.cache[self] = made
            sound = made
        }
        sound.stop()
        sound.play()
    }

    // MARK: - Synthesis

    private static let sampleRate = 44_100.0

    /// Deterministic white noise in -1...1, so a sound is identical every time it is built.
    private struct Noise {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    /// Paul Kellet's pink-noise filter over white noise.
    private struct Pink {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0
        mutating func next(_ white: inout Noise) -> Double {
            let w = white.next()
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            return (b0 + b1 + b2 + w * 0.1848) * 0.25
        }
    }

    func samples() -> [Double] {
        let rate = Self.sampleRate
        func render(_ duration: Double, _ body: (_ t: Double, _ p: Double) -> Double) -> [Double] {
            let count = Int(rate * duration)
            return (0..<count).map { i in max(-1, min(1, body(Double(i) / rate, Double(i) / Double(count)))) }
        }
        switch self {
        case .swoosh:
            // Pink noise through two cascaded band-pass filters whose centre rises 900 Hz -> 3.8 kHz,
            // under a smooth rise-and-fall envelope; normalized so its peak is 0.55.
            var noise = Noise(), pink = Pink()
            var low = [0.0, 0.0], band = [0.0, 0.0]
            let attack = 0.45
            let count = Int(rate * 0.16)
            var out = (0..<count).map { i -> Double in
                let p = Double(i) / Double(count)
                let centre = 900 * pow(3800.0 / 900.0, p)
                let f = 2 * sin(Double.pi * centre / rate)
                var x = pink.next(&noise)
                for stage in 0..<2 {
                    low[stage] += f * band[stage]
                    let high = x - low[stage] - band[stage] / 0.8
                    band[stage] += f * high
                    x = band[stage]
                }
                let envelope = p < attack
                    ? pow(sin(0.5 * .pi * p / attack), 2)
                    : pow(cos(0.5 * .pi * (p - attack) / (1 - attack)), 2)
                return x * envelope
            }
            let peak = out.map(abs).max() ?? 1
            if peak > 0 { out = out.map { $0 / peak * 0.55 } }
            return out
        case .tick:
            return render(0.05) { t, _ in sin(2 * .pi * 2200 * t) * exp(-t * 120) * 0.5 }
        case .thock:
            return render(0.14) { t, p in sin(2 * .pi * (180 - 90 * p) * t) * exp(-t * 35) * 0.7 }
        case .bubble:
            return render(0.09) { t, p in sin(2 * .pi * (300 + 900 * p) * t) * exp(-t * 30) * 0.5 }
        case .glass:
            return render(0.35) { t, _ in
                (sin(2 * .pi * 1760 * t) + 0.4 * sin(2 * .pi * 2637 * t)) * exp(-t * 18) * 0.28
            }
        }
    }

    /// 16-bit mono PCM WAV.
    static func wavData(samples: [Double]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        for sample in samples { append(Int16(sample * Double(Int16.max))) }
        return data
    }
}
