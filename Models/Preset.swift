import Foundation

// MARK: - Preset

struct Preset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var color: String         // hex color
    var channelA: ChannelSettings
    var channelB: ChannelSettings?  // nil = same as A
    var isBuiltin: Bool

    struct ChannelSettings: Codable, Equatable {
        var strength: Double
        var waveform: WaveformType
        var frequency: Double
        var pulseWidth: Int
        var phaseOffset: Double
        var durationMs: Int
    }

    init(id: UUID = UUID(),
         name: String,
         icon: String = "bolt.fill",
         color: String = "#007AFF",
         channelA: ChannelSettings,
         channelB: ChannelSettings? = nil,
         isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.channelA = channelA
        self.channelB = channelB
        self.isBuiltin = isBuiltin
    }
}

// MARK: - Built-in Presets

extension Preset {
    static let warmup = Preset(
        name: "Warm-up",
        icon: "flame.fill",
        color: "#FF9F0A",
        channelA: .init(strength: 15, waveform: .pulse(count: .single), frequency: 10, pulseWidth: 150, phaseOffset: 0, durationMs: 60_000),
        isBuiltin: true
    )

    static let training = Preset(
        name: "Training",
        icon: "target",
        color: "#30D158",
        channelA: .init(strength: 30, waveform: .pulse(count: .double), frequency: 20, pulseWidth: 200, phaseOffset: 0, durationMs: 120_000),
        isBuiltin: true
    )

    static let play = Preset(
        name: "Play",
        icon: "gamecontroller.fill",
        color: "#BF5AF2",
        channelA: .init(strength: 40, waveform: .sine, frequency: 25, pulseWidth: 200, phaseOffset: 0, durationMs: 0),
        channelB: .init(strength: 35, waveform: .triangle, frequency: 25, pulseWidth: 200, phaseOffset: 90, durationMs: 0),
        isBuiltin: true
    )

    static let edge = Preset(
        name: "Edge",
        icon: "sparkles",
        color: "#FF6B6B",
        channelA: .init(strength: 55, waveform: .pulse(count: .triple), frequency: 30, pulseWidth: 250, phaseOffset: 0, durationMs: 0),
        isBuiltin: true
    )

    static let tease = Preset(
        name: "Tease",
        icon: "bolt.heart.fill",
        color: "#FF375F",
        channelA: .init(strength: 20, waveform: .random, frequency: 15, pulseWidth: 150, phaseOffset: 0, durationMs: 0),
        channelB: .init(strength: 15, waveform: .rampUp, frequency: 10, pulseWidth: 200, phaseOffset: 0, durationMs: 30_000),
        isBuiltin: true
    )

    static let deep = Preset(
        name: "Deep Pulse",
        icon: "waveform.path.ecg",
        color: "#64D2FF",
        channelA: .init(strength: 45, waveform: .square, frequency: 5, pulseWidth: 500, phaseOffset: 0, durationMs: 0),
        isBuiltin: true
    )

    static let intensity = Preset(
        name: "Intensity",
        icon: "bolt.fill",
        color: "#FF453A",
        channelA: .init(strength: 70, waveform: .pulse(count: .quad), frequency: 40, pulseWidth: 300, phaseOffset: 0, durationMs: 60_000),
        channelB: .init(strength: 65, waveform: .pulse(count: .quad), frequency: 40, pulseWidth: 300, phaseOffset: 180, durationMs: 60_000),
        isBuiltin: true
    )

    static let relaxation = Preset(
        name: "Relaxation",
        icon: "leaf.fill",
        color: "#30D158",
        channelA: .init(strength: 10, waveform: .sine, frequency: 1, pulseWidth: 400, phaseOffset: 0, durationMs: 300_000),
        isBuiltin: true
    )

    static let allBuiltins: [Preset] = [warmup, training, play, edge, tease, deep, intensity, relaxation]
}
