import Foundation

// MARK: - Waveform Type

enum WaveformType: Codable, Equatable, Hashable, Identifiable {
    case pulse(count: PulseCount)
    case sine
    case square
    case triangle
    case rampUp
    case rampDown
    case sawtooth
    case random
    case custom(name: String, points: [Double])

    var id: String { name }

    var name: String {
        switch self {
        case .pulse(.single): return "Pulse"
        case .pulse(.double): return "Double Pulse"
        case .pulse(.triple): return "Triple Pulse"
        case .pulse(.quad): return "Quad Pulse"
        case .sine: return "Sine"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .rampUp: return "Ramp Up"
        case .rampDown: return "Ramp Down"
        case .sawtooth: return "Sawtooth"
        case .random: return "Random"
        case .custom(let name, _): return name
        }
    }

    var icon: String {
        switch self {
        case .pulse: return "bolt"
        case .sine: return "waveform"
        case .square: return "square"
        case .triangle: return "triangle"
        case .rampUp: return "arrow.up.right"
        case .rampDown: return "arrow.down.right"
        case .sawtooth: return "chart.xyaxis.line"
        case .random: return "sparkle"
        case .custom: return "pencil"
        }
    }
}

enum PulseCount: Int, Codable, CaseIterable {
    case single = 1
    case double = 2
    case triple = 3
    case quad = 4

    var label: String {
        switch self {
        case .single: return "1"
        case .double: return "2"
        case .triple: return "3"
        case .quad: return "4"
        }
    }
}

// MARK: - Built-in Waveforms

extension WaveformType {
    static let allBuiltIn: [WaveformType] = [
        .pulse(count: .single),
        .pulse(count: .double),
        .pulse(count: .triple),
        .pulse(count: .quad),
        .sine,
        .square,
        .triangle,
        .rampUp,
        .rampDown,
        .sawtooth,
        .random
    ]
}

// MARK: - Waveform Engine

actor WaveformEngine {
    /// Generate sample points for rendering or device output
    /// - Parameters:
    ///   - type: Waveform type
    ///   - samples: Number of points to generate
    ///   - frequency: Hz (affects time-domain waveforms)
    /// - Returns: Array of Double values in range [-1, 1]
    func generate(_ type: WaveformType, samples: Int = 500, frequency: Double = 20) -> [Double] {
        var points: [Double] = []

        switch type {
        case .pulse(let count):
            points = generatePulse(count: count, samples: samples)
        case .sine:
            points = generateSine(samples: samples, frequency: frequency)
        case .square:
            points = generateSquare(samples: samples, frequency: frequency)
        case .triangle:
            points = generateTriangle(samples: samples, frequency: frequency)
        case .rampUp:
            points = Array(stride(from: -1.0, through: 1.0, by: 2.0 / Double(samples - 1)))
        case .rampDown:
            points = Array(stride(from: 1.0, through: -1.0, by: -2.0 / Double(samples - 1)))
        case .sawtooth:
            points = generateSawtooth(samples: samples, frequency: frequency)
        case .random:
            points = (0..<samples).map { _ in Double.random(in: -1...1) }
        case .custom(_, let pts):
            points = pts
        }

        return points
    }

    private func generatePulse(count: PulseCount, samples: Int) -> [Double] {
        var result = Array(repeating: 0.0, count: samples)
        let width = max(3, samples / (count.rawValue * 4))
        let gap = (samples - count.rawValue * width) / max(1, count.rawValue - 1)

        for p in 0..<count.rawValue {
            let start = p * (width + gap)
            for i in 0..<min(width, samples - start) {
                result[start + i] = 1.0
            }
        }
        return result
    }

    private func generateSine(samples: Int, frequency: Double) -> [Double] {
        let period = Double(samples) / frequency
        return (0..<samples).map { i in
            sin(2 * Double.pi * Double(i) / period)
        }
    }

    private func generateSquare(samples: Int, frequency: Double) -> [Double] {
        let period = Double(samples) / frequency
        return (0..<samples).map { i in
            sin(2 * Double.pi * Double(i) / period) >= 0 ? 1.0 : -1.0
        }
    }

    private func generateTriangle(samples: Int, frequency: Double) -> [Double] {
        let period = Double(samples) / frequency
        return (0..<samples).map { i in
            let t = (Double(i).truncatingRemainder(dividingBy: period) / period) * 2 * .pi
            return 2 * asin(sin(t)) / .pi
        }
    }

    private func generateSawtooth(samples: Int, frequency: Double) -> [Double] {
        let period = Double(samples) / frequency
        return (0..<samples).map { i in
            let t = Double(i).truncatingRemainder(dividingBy: period) / period
            return 2 * t - 1
        }
    }

    /// Serialize custom waveform for export
    func serialize(_ type: WaveformType) -> [String: Any] {
        guard case .custom(let name, let points) = type else { return ["type": "builtin"] }
        return [
            "type": "custom",
            "name": name,
            "points": points
        ]
    }

    /// Deserialize custom waveform from import
    static func fromSerialization(_ dict: [String: Any]) -> WaveformType? {
        guard let type = dict["type"] as? String else { return nil }
        if type == "custom",
           let name = dict["name"] as? String,
           let points = dict["points"] as? [Double] {
            return .custom(name: name, points: points)
        }
        return nil
    }
}
