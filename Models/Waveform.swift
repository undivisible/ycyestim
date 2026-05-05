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
    case heartbeat
    case staircase
    case alternating
    case sweep
    case tremolo
    case breath
    case glide
    case flutter
    case crescendo
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
        case .heartbeat: return "Heartbeat"
        case .staircase: return "Staircase"
        case .alternating: return "Alternating"
        case .sweep: return "Sweep"
        case .tremolo: return "Tremolo"
        case .breath: return "Breath"
        case .glide: return "Glide"
        case .flutter: return "Flutter"
        case .crescendo: return "Crescendo"
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
        case .heartbeat: return "heart.fill"
        case .staircase: return "chart.bar.fill"
        case .alternating: return "arrow.left.arrow.right"
        case .sweep: return "waveform.path.ecg"
        case .tremolo: return "waveform"
        case .breath: return "wind"
        case .glide: return "water.waves"
        case .flutter: return "sparkles"
        case .crescendo: return "chart.line.uptrend.xyaxis"
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
        .heartbeat,
        .staircase,
        .alternating,
        .sweep,
        .tremolo,
        .breath,
        .glide,
        .flutter,
        .crescendo,
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
        case .heartbeat:
            points = generateHeartbeat(samples: samples)
        case .staircase:
            points = generateStaircase(samples: samples)
        case .alternating:
            points = generateAlternating(samples: samples)
        case .sweep:
            points = generateSweep(samples: samples, frequency: frequency)
        case .tremolo:
            points = generateTremolo(samples: samples, frequency: frequency)
        case .breath:
            points = generateBreath(samples: samples)
        case .glide:
            points = generateGlide(samples: samples, frequency: frequency)
        case .flutter:
            points = generateFlutter(samples: samples, frequency: frequency)
        case .crescendo:
            points = generateCrescendo(samples: samples, frequency: frequency)
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

    private func generateHeartbeat(samples: Int) -> [Double] {
        (0..<samples).map { i in
            let phase = Double(i) / Double(max(1, samples - 1))
            let first = exp(-pow((phase - 0.22) / 0.035, 2))
            let second = 0.55 * exp(-pow((phase - 0.34) / 0.055, 2))
            let recovery = -0.2 * exp(-pow((phase - 0.5) / 0.09, 2))
            return max(-1, min(1, first + second + recovery))
        }
    }

    private func generateStaircase(samples: Int) -> [Double] {
        let steps = 6
        return (0..<samples).map { i in
            let index = min(steps - 1, i * steps / max(1, samples))
            return -1 + (Double(index) / Double(steps - 1)) * 2
        }
    }

    private func generateAlternating(samples: Int) -> [Double] {
        let segment = max(1, samples / 12)
        return (0..<samples).map { i in
            (i / segment).isMultiple(of: 2) ? 1 : -1
        }
    }

    private func generateSweep(samples: Int, frequency: Double) -> [Double] {
        let base = max(0.5, frequency / 20)
        return (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            let accelerated = t * t * (base * 12)
            return sin(2 * .pi * accelerated)
        }
    }

    private func generateTremolo(samples: Int, frequency: Double) -> [Double] {
        let carrier = max(1, frequency)
        return (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            let amplitude = 0.35 + 0.65 * abs(sin(2 * .pi * t * 3))
            return amplitude * sin(2 * .pi * t * carrier)
        }
    }

    private func generateBreath(samples: Int) -> [Double] {
        (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            let envelope = pow(sin(.pi * t), 1.8)
            return envelope * sin(2 * .pi * t * 2)
        }
    }

    private func generateGlide(samples: Int, frequency: Double) -> [Double] {
        let cycles = max(1, frequency / 8)
        return (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            let drift = 0.18 * sin(2 * .pi * t)
            return sin(2 * .pi * (cycles * t + drift))
        }
    }

    private func generateFlutter(samples: Int, frequency: Double) -> [Double] {
        let carrier = max(3, frequency / 2)
        return (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            let gate = sin(2 * .pi * t * 9) > 0.15 ? 1.0 : 0.2
            return gate * sin(2 * .pi * t * carrier)
        }
    }

    private func generateCrescendo(samples: Int, frequency: Double) -> [Double] {
        let cycles = max(1, frequency / 10)
        return (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            let envelope = min(1, 0.15 + t * 0.95)
            return envelope * sin(2 * .pi * t * cycles)
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
