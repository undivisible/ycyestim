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

    static let heartbeat = Preset(
        name: "Heartbeat",
        icon: "heart.fill",
        color: "#FF375F",
        channelA: .init(strength: 18, waveform: .heartbeat, frequency: 12, pulseWidth: 180, phaseOffset: 0, durationMs: 120_000),
        isBuiltin: true
    )

    static let staircase = Preset(
        name: "Staircase",
        icon: "chart.bar.fill",
        color: "#0A84FF",
        channelA: .init(strength: 28, waveform: .staircase, frequency: 18, pulseWidth: 220, phaseOffset: 0, durationMs: 90_000),
        channelB: .init(strength: 24, waveform: .rampDown, frequency: 18, pulseWidth: 220, phaseOffset: 180, durationMs: 90_000),
        isBuiltin: true
    )

    static let alternate = Preset(
        name: "Alternate",
        icon: "arrow.left.arrow.right",
        color: "#64D2FF",
        channelA: .init(strength: 34, waveform: .alternating, frequency: 22, pulseWidth: 180, phaseOffset: 0, durationMs: 0),
        channelB: .init(strength: 34, waveform: .alternating, frequency: 22, pulseWidth: 180, phaseOffset: 180, durationMs: 0),
        isBuiltin: true
    )

    static let sweep = Preset(
        name: "Sweep",
        icon: "waveform.path.ecg",
        color: "#FFD60A",
        channelA: .init(strength: 38, waveform: .sweep, frequency: 18, pulseWidth: 240, phaseOffset: 0, durationMs: 180_000),
        isBuiltin: true
    )

    static let tremolo = Preset(
        name: "Tremolo",
        icon: "waveform",
        color: "#5E5CE6",
        channelA: .init(strength: 32, waveform: .tremolo, frequency: 24, pulseWidth: 200, phaseOffset: 0, durationMs: 0),
        channelB: .init(strength: 26, waveform: .sine, frequency: 8, pulseWidth: 300, phaseOffset: 90, durationMs: 0),
        isBuiltin: true
    )

    static let breath = Preset(
        name: "Breath",
        icon: "wind",
        color: "#34C759",
        channelA: .init(strength: 16, waveform: .breath, frequency: 8, pulseWidth: 260, phaseOffset: 0, durationMs: 180_000),
        isBuiltin: true
    )

    static let glide = Preset(
        name: "Glide",
        icon: "water.waves",
        color: "#0A84FF",
        channelA: .init(strength: 24, waveform: .glide, frequency: 16, pulseWidth: 210, phaseOffset: 0, durationMs: 0),
        channelB: .init(strength: 22, waveform: .breath, frequency: 10, pulseWidth: 260, phaseOffset: 120, durationMs: 0),
        isBuiltin: true
    )

    static let flutter = Preset(
        name: "Flutter",
        icon: "sparkles",
        color: "#FFCC00",
        channelA: .init(strength: 26, waveform: .flutter, frequency: 28, pulseWidth: 160, phaseOffset: 0, durationMs: 90_000),
        channelB: .init(strength: 24, waveform: .flutter, frequency: 24, pulseWidth: 160, phaseOffset: 180, durationMs: 90_000),
        isBuiltin: true
    )

    static let crescendo = Preset(
        name: "Crescendo",
        icon: "chart.line.uptrend.xyaxis",
        color: "#FF453A",
        channelA: .init(strength: 30, waveform: .crescendo, frequency: 18, pulseWidth: 240, phaseOffset: 0, durationMs: 120_000),
        channelB: .init(strength: 28, waveform: .rampDown, frequency: 12, pulseWidth: 260, phaseOffset: 180, durationMs: 120_000),
        isBuiltin: true
    )

    static let edgeSense = Preset(
        name: "Edge Sense",
        icon: "heart.circle.fill",
        color: "#FF375F",
        channelA: .init(strength: 22, waveform: .heartbeat, frequency: 14, pulseWidth: 190, phaseOffset: 0, durationMs: 0),
        channelB: .init(strength: 18, waveform: .glide, frequency: 12, pulseWidth: 230, phaseOffset: 90, durationMs: 0),
        isBuiltin: true
    )

    static let allBuiltins: [Preset] = [
        edgeSense,
        breath,
        glide,
        flutter,
        crescendo,
        warmup,
        training,
        play,
        edge,
        tease,
        deep,
        intensity,
        relaxation,
        heartbeat,
        staircase,
        alternate,
        sweep,
        tremolo
    ]
}
