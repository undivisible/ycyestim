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
    var pad1Placement: PadPlacement
    var pad2Placement: PadPlacement

    enum ChannelID: String, Codable, CaseIterable {
        case a = "A"
        case b = "B"

        var label: String { rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case strength
        case durationMs
        case waveform
        case frequency
        case pulseWidth
        case phaseOffset
        case isInverted
        case placement
        case pad1Placement
        case pad2Placement
    }

    init(id: ChannelID,
         isEnabled: Bool = false,
         strength: Double = 0,
         durationMs: Int = 0,
         waveform: WaveformType = .pulse(count: .single),
         frequency: Double = 20,
         pulseWidth: Int = 200,
         phaseOffset: Double = 0,
         isInverted: Bool = false,
         placement: PadPlacement = .generalPads,
         pad1Placement: PadPlacement? = nil,
         pad2Placement: PadPlacement? = nil) {
        self.id = id
        self.isEnabled = isEnabled
        self.strength = strength
        self.durationMs = durationMs
        self.waveform = waveform
        self.frequency = frequency
        self.pulseWidth = pulseWidth
        self.phaseOffset = phaseOffset
        self.isInverted = isInverted
        self.pad1Placement = pad1Placement ?? placement
        self.pad2Placement = pad2Placement ?? placement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ChannelID.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        strength = try container.decodeIfPresent(Double.self, forKey: .strength) ?? 0
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        waveform = try container.decodeIfPresent(WaveformType.self, forKey: .waveform) ?? .pulse(count: .single)
        frequency = try container.decodeIfPresent(Double.self, forKey: .frequency) ?? 20
        pulseWidth = try container.decodeIfPresent(Int.self, forKey: .pulseWidth) ?? 200
        phaseOffset = try container.decodeIfPresent(Double.self, forKey: .phaseOffset) ?? 0
        isInverted = try container.decodeIfPresent(Bool.self, forKey: .isInverted) ?? false
        let legacyPlacement = try container.decodeIfPresent(PadPlacement.self, forKey: .placement) ?? .generalPads
        pad1Placement = try container.decodeIfPresent(PadPlacement.self, forKey: .pad1Placement) ?? legacyPlacement
        pad2Placement = try container.decodeIfPresent(PadPlacement.self, forKey: .pad2Placement) ?? legacyPlacement
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(strength, forKey: .strength)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encode(waveform, forKey: .waveform)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(pulseWidth, forKey: .pulseWidth)
        try container.encode(phaseOffset, forKey: .phaseOffset)
        try container.encode(isInverted, forKey: .isInverted)
        try container.encode(pad1Placement, forKey: .pad1Placement)
        try container.encode(pad2Placement, forKey: .pad2Placement)
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

    var placement: PadPlacement {
        get { pad1Placement.mostRestrictive(with: pad2Placement) }
        set {
            pad1Placement = newValue
            pad2Placement = newValue
        }
    }

    var padPairProfile: PadPlacementProfile {
        PadPlacementProfile.combined(pad1Placement, pad2Placement)
    }
}

enum PadPlacement: String, Codable, CaseIterable, Identifiable, Equatable {
    case generalPads = "General Pads"
    case abdomen = "Abdomen"
    case lowerBack = "Lower Back"
    case sacrum = "Sacrum"
    case glutes = "Glutes"
    case outerThigh = "Outer Thigh"
    case innerThigh = "Inner Thigh"
    case perineum = "Perineum"
    case penis = "Penis"
    case insertable = "Insertable"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .generalPads: return "square.grid.2x2"
        case .abdomen: return "figure.core.training"
        case .lowerBack: return "figure.strengthtraining.traditional"
        case .sacrum: return "figure.stand"
        case .glutes: return "figure.walk"
        case .outerThigh: return "figure.run"
        case .innerThigh: return "figure.flexibility"
        case .perineum: return "scope"
        case .penis: return "bolt.heart"
        case .insertable: return "capsule"
        }
    }

    var profile: PadPlacementProfile {
        switch self {
        case .generalPads:
            return PadPlacementProfile(maxStrength: 100, minFrequency: 1, maxFrequency: 50, maxPulseWidth: 100, smoothsSharpWaveforms: false, normalWaveform: nil, elevatedWaveform: nil, highWaveform: .breath, sensitivity: 0.05, mobility: 0.55)
        case .abdomen:
            return PadPlacementProfile(maxStrength: 80, minFrequency: 4, maxFrequency: 40, maxPulseWidth: 90, smoothsSharpWaveforms: false, normalWaveform: nil, elevatedWaveform: .wave, highWaveform: .breath, sensitivity: 0.28, mobility: 0.42)
        case .lowerBack:
            return PadPlacementProfile(maxStrength: 80, minFrequency: 4, maxFrequency: 45, maxPulseWidth: 95, smoothsSharpWaveforms: false, normalWaveform: nil, elevatedWaveform: .glide, highWaveform: .breath, sensitivity: 0.24, mobility: 0.36)
        case .sacrum:
            return PadPlacementProfile(maxStrength: 60, minFrequency: 5, maxFrequency: 35, maxPulseWidth: 80, smoothsSharpWaveforms: true, normalWaveform: .glide, elevatedWaveform: .wave, highWaveform: .breath, sensitivity: 0.48, mobility: 0.3)
        case .glutes:
            return PadPlacementProfile(maxStrength: 85, minFrequency: 4, maxFrequency: 45, maxPulseWidth: 100, smoothsSharpWaveforms: false, normalWaveform: nil, elevatedWaveform: .wave, highWaveform: .breath, sensitivity: 0.22, mobility: 0.5)
        case .outerThigh:
            return PadPlacementProfile(maxStrength: 70, minFrequency: 5, maxFrequency: 40, maxPulseWidth: 90, smoothsSharpWaveforms: false, normalWaveform: nil, elevatedWaveform: .glide, highWaveform: .breath, sensitivity: 0.34, mobility: 0.58)
        case .innerThigh:
            return PadPlacementProfile(maxStrength: 55, minFrequency: 6, maxFrequency: 32, maxPulseWidth: 70, smoothsSharpWaveforms: true, normalWaveform: .wave, elevatedWaveform: .glide, highWaveform: .breath, sensitivity: 0.62, mobility: 0.5)
        case .perineum:
            return PadPlacementProfile(maxStrength: 38, minFrequency: 8, maxFrequency: 24, maxPulseWidth: 55, smoothsSharpWaveforms: true, normalWaveform: .wave, elevatedWaveform: .breath, highWaveform: .breath, sensitivity: 0.82, mobility: 0.24)
        case .penis:
            return PadPlacementProfile(maxStrength: 32, minFrequency: 8, maxFrequency: 22, maxPulseWidth: 50, smoothsSharpWaveforms: true, normalWaveform: .wave, elevatedWaveform: .breath, highWaveform: .breath, sensitivity: 0.9, mobility: 0.32)
        case .insertable:
            return PadPlacementProfile(maxStrength: 25, minFrequency: 8, maxFrequency: 18, maxPulseWidth: 45, smoothsSharpWaveforms: true, normalWaveform: .breath, elevatedWaveform: .breath, highWaveform: .breath, sensitivity: 1, mobility: 0.18)
        }
    }

    func mostRestrictive(with other: PadPlacement) -> PadPlacement {
        profile.sensitivity >= other.profile.sensitivity ? self : other
    }
}

struct PadPlacementProfile: Equatable {
    var maxStrength: Double
    var minFrequency: Double
    var maxFrequency: Double
    var maxPulseWidth: Int
    var smoothsSharpWaveforms: Bool
    var normalWaveform: WaveformType?
    var elevatedWaveform: WaveformType?
    var highWaveform: WaveformType
    var sensitivity: Double
    var mobility: Double

    static func combined(_ pad1: PadPlacement, _ pad2: PadPlacement) -> PadPlacementProfile {
        let first = pad1.profile
        let second = pad2.profile
        let sensitive = max(first.sensitivity, second.sensitivity)
        let samePlacement = pad1 == pad2
        let bridgeMultiplier = samePlacement ? 0.92 : 1 - sensitive * 0.12
        let maxFrequency = min(first.maxFrequency, second.maxFrequency) * (1 - sensitive * 0.08)
        let highWaveform: WaveformType = sensitive > 0.6 ? .breath : first.highWaveform

        return PadPlacementProfile(
            maxStrength: min(first.maxStrength, second.maxStrength) * bridgeMultiplier,
            minFrequency: max(first.minFrequency, second.minFrequency),
            maxFrequency: max(max(first.minFrequency, second.minFrequency), maxFrequency),
            maxPulseWidth: min(first.maxPulseWidth, second.maxPulseWidth),
            smoothsSharpWaveforms: first.smoothsSharpWaveforms || second.smoothsSharpWaveforms || sensitive > 0.6,
            normalWaveform: first.normalWaveform ?? second.normalWaveform,
            elevatedWaveform: sensitive > 0.7 ? .breath : first.elevatedWaveform ?? second.elevatedWaveform,
            highWaveform: highWaveform,
            sensitivity: sensitive,
            mobility: (first.mobility + second.mobility) / 2
        )
    }
}

enum PlacementLoad: Equatable {
    case normal
    case elevated
    case high
    case critical
}

struct PlacementOutputPolicy {
    var heartRateConfig: HeartRateSafetyConfig

    func adapted(_ channel: ChannelState, bpm: Double?, adaptiveStrengthLimit: Double) -> ChannelState {
        guard channel.isEnabled else { return channel }
        var output = channel
        let profile = channel.padPairProfile
        let load = placementLoad(bpm)
        let progress = loadProgress(bpm)
        let maxStrength = min(profile.maxStrength, adaptiveStrengthLimit) * strengthMultiplier(for: load) * placementTrim(profile: profile, progress: progress)
        output.strength = max(0, min(output.strength, maxStrength))
        output.frequency = adaptiveFrequency(output.frequency, profile: profile, load: load, progress: progress)
        output.pulseWidth = adaptivePulseWidth(output.pulseWidth, profile: profile, load: load, progress: progress)
        output.waveform = waveform(for: output.waveform, profile: profile, load: load)
        return output
    }

    func placementLoad(_ bpm: Double?) -> PlacementLoad {
        guard let bpm else { return .normal }
        if bpm >= heartRateConfig.criticalBPM { return .critical }
        if bpm >= heartRateConfig.highBPM { return .high }
        if bpm >= heartRateConfig.elevatedBPM { return .elevated }
        return .normal
    }

    private func strengthMultiplier(for load: PlacementLoad) -> Double {
        switch load {
        case .normal: return 1
        case .elevated: return 0.86
        case .high: return 0.64
        case .critical: return 0
        }
    }

    private func loadProgress(_ bpm: Double?) -> Double {
        guard let bpm else { return 0 }
        let span = max(1, heartRateConfig.criticalBPM - heartRateConfig.baselineBPM)
        return max(0, min(1, (bpm - heartRateConfig.baselineBPM) / span))
    }

    private func placementTrim(profile: PadPlacementProfile, progress: Double) -> Double {
        1 - progress * (0.1 + profile.sensitivity * 0.18)
    }

    private func adaptiveFrequency(_ frequency: Double, profile: PadPlacementProfile, load: PlacementLoad, progress: Double) -> Double {
        let upper = maxFrequency(for: profile, load: load)
        let center = profile.minFrequency + (upper - profile.minFrequency) * (0.42 + profile.mobility * 0.24)
        let blended = frequency + (center - frequency) * progress * (0.28 + profile.sensitivity * 0.18)
        return max(profile.minFrequency, min(blended, upper))
    }

    private func adaptivePulseWidth(_ pulseWidth: Int, profile: PadPlacementProfile, load: PlacementLoad, progress: Double) -> Int {
        let upper = maxPulseWidth(for: profile, load: load)
        let softened = Double(pulseWidth) * (1 - progress * (0.08 + profile.sensitivity * 0.16))
        return max(0, min(Int(softened.rounded()), upper))
    }

    private func maxFrequency(for profile: PadPlacementProfile, load: PlacementLoad) -> Double {
        let multiplier: Double
        switch load {
        case .normal: multiplier = 1
        case .elevated: multiplier = 0.9
        case .high: multiplier = 0.76
        case .critical: multiplier = 0.62
        }
        return max(profile.minFrequency, profile.maxFrequency * multiplier)
    }

    private func maxPulseWidth(for profile: PadPlacementProfile, load: PlacementLoad) -> Int {
        let multiplier: Double
        switch load {
        case .normal: multiplier = 1
        case .elevated: multiplier = 0.86
        case .high: multiplier = 0.68
        case .critical: multiplier = 0.42
        }
        return max(0, Int((Double(profile.maxPulseWidth) * multiplier).rounded()))
    }

    private func waveform(for waveform: WaveformType, profile: PadPlacementProfile, load: PlacementLoad) -> WaveformType {
        switch load {
        case .normal:
            if profile.smoothsSharpWaveforms && waveform.isSharpForSensitivePlacement {
                return profile.normalWaveform ?? .wave
            }
            return waveform
        case .elevated:
            return profile.elevatedWaveform ?? waveform
        case .high, .critical:
            return profile.highWaveform
        }
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
        defaultPulseWidth: 60,
        defaultPhaseOffset: 0,
        isEnabled: true,
        isInverted: false
    )
}
