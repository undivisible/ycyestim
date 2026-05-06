import Foundation

// MARK: - Channel State

struct ChannelState: Identifiable, Codable, Equatable {
    let id: ChannelID
    var isEnabled: Bool
    var strength: Double        // 0–100
    var durationMs: Int         // 0 = indefinite
    var waveform: WaveformType
    var frequency: Double       // Hz, 1–50
    var pulseWidth: Int         // microseconds
    var phaseOffset: Double     // degrees, 0–360
    var isInverted: Bool

    enum ChannelID: String, Codable, CaseIterable {
        case a = "A"
        case b = "B"

        var label: String { rawValue }
    }

    init(id: ChannelID,
         isEnabled: Bool = false,
         strength: Double = 0,
         durationMs: Int = 0,
         waveform: WaveformType = .pulse(count: .single),
         frequency: Double = 20,
         pulseWidth: Int = 200,
         phaseOffset: Double = 0,
         isInverted: Bool = false) {
        self.id = id
        self.isEnabled = isEnabled
        self.strength = strength
        self.durationMs = durationMs
        self.waveform = waveform
        self.frequency = frequency
        self.pulseWidth = pulseWidth
        self.phaseOffset = phaseOffset
        self.isInverted = isInverted
    }

    /// Sync this channel's settings from another channel
    mutating func sync(from other: ChannelState) {
        self.strength = other.strength
        self.durationMs = other.durationMs
        self.waveform = other.waveform
        self.frequency = other.frequency
        self.pulseWidth = other.pulseWidth
        self.phaseOffset = other.phaseOffset
        self.isInverted = other.isInverted
    }
}

// MARK: - Channel Config (persistent settings)

struct ChannelConfig: Codable, Equatable {
    var minStrength: Double
    var maxStrength: Double
    var defaultStrength: Double
    var defaultWaveform: WaveformType
    var defaultFrequency: Double
    var defaultPulseWidth: Int
    var defaultPhaseOffset: Double
    var isEnabled: Bool
    var isInverted: Bool

    static let standard = ChannelConfig(
        minStrength: 0,
        maxStrength: 100,
        defaultStrength: 20,
        defaultWaveform: .pulse(count: .single),
        defaultFrequency: 20,
        defaultPulseWidth: 200,
        defaultPhaseOffset: 0,
        isEnabled: true,
        isInverted: false
    )
}
