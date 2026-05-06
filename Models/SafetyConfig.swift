import Foundation

struct SafetyConfig: Codable, Equatable {
    var maxStrength: Double
    var sessionTimeoutMinutes: Int
    var rampRateLimit: Double
    var confirmationThreshold: Double
    var emergencyGesture: EmergencyGesture
    var autoShutdownOnDisconnect: Bool
    var heartRateMonitoring: Bool
    var hapticIntensity: HapticIntensity

    enum EmergencyGesture: String, Codable, CaseIterable {
        case shake = "Shake device"
        case doubleTap = "Double-tap status bar"
        case hardwareButton = "Hardware button"
        case none = "None"
    }

    enum HapticIntensity: String, Codable, CaseIterable {
        case off = "Off"
        case light = "Light"
        case medium = "Medium"
        case heavy = "Heavy"
    }

    static let `default` = SafetyConfig(
        maxStrength: 80,
        sessionTimeoutMinutes: 60,
        rampRateLimit: 5.0,
        confirmationThreshold: 60,
        emergencyGesture: .shake,
        autoShutdownOnDisconnect: true,
        heartRateMonitoring: false,
        hapticIntensity: .medium
    )
}

struct HeartRateSafetyConfig: Codable, Equatable {
    var isEnabled: Bool
    var baselineBPM: Double
    var elevatedBPM: Double
    var highBPM: Double
    var criticalBPM: Double
    var elevatedStrengthMultiplier: Double
    var highStrengthMultiplier: Double
    var emergencyStopOnCritical: Bool

    static let `default` = HeartRateSafetyConfig(
        isEnabled: false,
        baselineBPM: 75,
        elevatedBPM: 115,
        highBPM: 135,
        criticalBPM: 155,
        elevatedStrengthMultiplier: 0.8,
        highStrengthMultiplier: 0.5,
        emergencyStopOnCritical: true
    )
}

struct EdgeModeConfig: Codable, Equatable {
    var isEnabled: Bool
    var targetBPM: Double
    var peakBPM: Double
    var recoveryBPM: Double
    var minStrength: Double
    var maxStrength: Double
    var rampStep: Double
    var cooldownSeconds: Double
    var adjustsStrength: Bool
    var adjustsFrequency: Bool
    var adjustsWaveform: Bool
    var frequencyFloor: Double
    var frequencyCeiling: Double
    var buildingWaveform: WaveformType
    var holdingWaveform: WaveformType
    var easingWaveform: WaveformType

    init(isEnabled: Bool,
         targetBPM: Double,
         peakBPM: Double,
         recoveryBPM: Double,
         minStrength: Double,
         maxStrength: Double,
         rampStep: Double,
         cooldownSeconds: Double,
         adjustsStrength: Bool = true,
         adjustsFrequency: Bool = false,
         adjustsWaveform: Bool = false,
         frequencyFloor: Double = 8,
         frequencyCeiling: Double = 40,
         buildingWaveform: WaveformType = .wave,
         holdingWaveform: WaveformType = .heartbeat,
         easingWaveform: WaveformType = .breath) {
        self.isEnabled = isEnabled
        self.targetBPM = targetBPM
        self.peakBPM = peakBPM
        self.recoveryBPM = recoveryBPM
        self.minStrength = minStrength
        self.maxStrength = maxStrength
        self.rampStep = rampStep
        self.cooldownSeconds = cooldownSeconds
        self.adjustsStrength = adjustsStrength
        self.adjustsFrequency = adjustsFrequency
        self.adjustsWaveform = adjustsWaveform
        self.frequencyFloor = frequencyFloor
        self.frequencyCeiling = frequencyCeiling
        self.buildingWaveform = buildingWaveform
        self.holdingWaveform = holdingWaveform
        self.easingWaveform = easingWaveform
    }

    static let `default` = EdgeModeConfig(
        isEnabled: false,
        targetBPM: 118,
        peakBPM: 138,
        recoveryBPM: 96,
        minStrength: 14,
        maxStrength: 58,
        rampStep: 2,
        cooldownSeconds: 8,
        adjustsStrength: true,
        adjustsFrequency: true,
        adjustsWaveform: true,
        frequencyFloor: 8,
        frequencyCeiling: 40,
        buildingWaveform: .wave,
        holdingWaveform: .heartbeat,
        easingWaveform: .breath
    )

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case targetBPM
        case peakBPM
        case recoveryBPM
        case minStrength
        case maxStrength
        case rampStep
        case cooldownSeconds
        case adjustsStrength
        case adjustsFrequency
        case adjustsWaveform
        case frequencyFloor
        case frequencyCeiling
        case buildingWaveform
        case holdingWaveform
        case easingWaveform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EdgeModeConfig.default
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        targetBPM = try container.decodeIfPresent(Double.self, forKey: .targetBPM) ?? defaults.targetBPM
        peakBPM = try container.decodeIfPresent(Double.self, forKey: .peakBPM) ?? defaults.peakBPM
        recoveryBPM = try container.decodeIfPresent(Double.self, forKey: .recoveryBPM) ?? defaults.recoveryBPM
        minStrength = try container.decodeIfPresent(Double.self, forKey: .minStrength) ?? defaults.minStrength
        maxStrength = try container.decodeIfPresent(Double.self, forKey: .maxStrength) ?? defaults.maxStrength
        rampStep = try container.decodeIfPresent(Double.self, forKey: .rampStep) ?? defaults.rampStep
        cooldownSeconds = try container.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? defaults.cooldownSeconds
        adjustsStrength = try container.decodeIfPresent(Bool.self, forKey: .adjustsStrength) ?? defaults.adjustsStrength
        adjustsFrequency = try container.decodeIfPresent(Bool.self, forKey: .adjustsFrequency) ?? defaults.adjustsFrequency
        adjustsWaveform = try container.decodeIfPresent(Bool.self, forKey: .adjustsWaveform) ?? defaults.adjustsWaveform
        frequencyFloor = try container.decodeIfPresent(Double.self, forKey: .frequencyFloor) ?? defaults.frequencyFloor
        frequencyCeiling = try container.decodeIfPresent(Double.self, forKey: .frequencyCeiling) ?? defaults.frequencyCeiling
        buildingWaveform = try container.decodeIfPresent(WaveformType.self, forKey: .buildingWaveform) ?? defaults.buildingWaveform
        holdingWaveform = try container.decodeIfPresent(WaveformType.self, forKey: .holdingWaveform) ?? defaults.holdingWaveform
        easingWaveform = try container.decodeIfPresent(WaveformType.self, forKey: .easingWaveform) ?? defaults.easingWaveform
    }
}

enum HeartRateSafetyState: Equatable {
    case inactive
    case unavailable
    case needsAuthorization
    case stale(bpm: Double)
    case monitoring(bpm: Double, multiplier: Double)
    case elevated(bpm: Double, multiplier: Double)
    case high(bpm: Double, multiplier: Double)
    case critical(bpm: Double)

    var bpm: Double? {
        switch self {
        case .inactive, .unavailable, .needsAuthorization:
            return nil
        case .stale(let bpm), .monitoring(let bpm, _), .elevated(let bpm, _), .high(let bpm, _), .critical(let bpm):
            return bpm
        }
    }

    var strengthMultiplier: Double {
        switch self {
        case .monitoring(_, let multiplier), .elevated(_, let multiplier), .high(_, let multiplier):
            return multiplier
        case .critical:
            return 0
        case .inactive, .unavailable, .needsAuthorization, .stale:
            return 1
        }
    }

    var label: String {
        switch self {
        case .inactive:
            return "Off"
        case .unavailable:
            return "Unavailable"
        case .needsAuthorization:
            return "Needs Permission"
        case .stale(let bpm):
            return "\(Int(bpm)) BPM Stale"
        case .monitoring(let bpm, _):
            return "\(Int(bpm)) BPM"
        case .elevated(let bpm, _):
            return "\(Int(bpm)) BPM Elevated"
        case .high(let bpm, _):
            return "\(Int(bpm)) BPM High"
        case .critical(let bpm):
            return "\(Int(bpm)) BPM Critical"
        }
    }
}

enum EdgeModeState: Equatable {
    case inactive
    case armed
    case building(bpm: Double, targetStrength: Double)
    case holding(bpm: Double, targetStrength: Double)
    case easing(bpm: Double, targetStrength: Double)

    var label: String {
        switch self {
        case .inactive:
            return "Edge Off"
        case .armed:
            return "Edge Armed"
        case .building(let bpm, _):
            return "\(Int(bpm)) BPM Building"
        case .holding(let bpm, _):
            return "\(Int(bpm)) BPM Holding"
        case .easing(let bpm, _):
            return "\(Int(bpm)) BPM Easing"
        }
    }

    var icon: String {
        switch self {
        case .inactive:
            return "heart"
        case .armed:
            return "heart.circle"
        case .building:
            return "arrow.up.circle"
        case .holding:
            return "heart.fill"
        case .easing:
            return "arrow.down.circle"
        }
    }

    var targetStrength: Double? {
        switch self {
        case .inactive, .armed:
            return nil
        case .building(_, let targetStrength), .holding(_, let targetStrength), .easing(_, let targetStrength):
            return targetStrength
        }
    }
}

struct HeartRateSafetyPolicy {
    let config: HeartRateSafetyConfig

    func evaluate(bpm: Double) -> HeartRateSafetyState {
        if bpm >= config.criticalBPM {
            return .critical(bpm: bpm)
        }
        if bpm >= config.highBPM {
            return .high(bpm: bpm, multiplier: clamped(config.highStrengthMultiplier))
        }
        if bpm >= config.elevatedBPM {
            return .elevated(bpm: bpm, multiplier: clamped(config.elevatedStrengthMultiplier))
        }
        return .monitoring(bpm: bpm, multiplier: 1)
    }

    private func clamped(_ multiplier: Double) -> Double {
        max(0, min(1, multiplier))
    }
}

struct EdgeModePolicy {
    let config: EdgeModeConfig

    func evaluate(bpm: Double, currentStrength: Double) -> EdgeModeState {
        guard config.isEnabled else { return .inactive }

        let boundedCurrent = clamped(currentStrength)
        let targetBPM = config.targetBPM
        let peakBPM = max(config.peakBPM, targetBPM + 1)
        let recoveryBPM = min(config.recoveryBPM, targetBPM - 1)

        if bpm >= peakBPM {
            let target = clamped(boundedCurrent - config.rampStep * 2)
            return .easing(bpm: bpm, targetStrength: target)
        }
        if bpm >= targetBPM {
            return .holding(bpm: bpm, targetStrength: boundedCurrent)
        }

        let multiplier = bpm < recoveryBPM ? 1.5 : 1
        let target = clamped(boundedCurrent + config.rampStep * multiplier)
        return .building(bpm: bpm, targetStrength: target)
    }

    func targetFrequency(bpm: Double, placementProfile: PadPlacementProfile? = nil) -> Double {
        let lower = min(config.frequencyFloor, config.frequencyCeiling)
        let upper = max(config.frequencyFloor, config.frequencyCeiling)
        let boundedLower = placementProfile.map { max(lower, $0.minFrequency) } ?? lower
        let boundedUpper = placementProfile.map { min(upper, $0.maxFrequency) } ?? upper
        let span = max(1, config.peakBPM - config.recoveryBPM)
        let progress = max(0, min(1, (bpm - config.recoveryBPM) / span))
        let curve = progress * progress * (3 - 2 * progress)
        let target = boundedLower + (boundedUpper - boundedLower) * curve
        guard let placementProfile else { return target }
        let focus = boundedLower + (boundedUpper - boundedLower) * (0.38 + placementProfile.mobility * 0.22)
        return target + (focus - target) * placementProfile.sensitivity * 0.22
    }

    func targetWaveform(for state: EdgeModeState, placementProfile: PadPlacementProfile? = nil) -> WaveformType? {
        switch state {
        case .building:
            if placementProfile?.sensitivity ?? 0 > 0.75 {
                return placementProfile?.normalWaveform ?? .wave
            }
            return config.buildingWaveform
        case .holding:
            if placementProfile?.sensitivity ?? 0 > 0.65 {
                return placementProfile?.elevatedWaveform ?? .breath
            }
            return config.holdingWaveform
        case .easing:
            return placementProfile?.highWaveform ?? config.easingWaveform
        case .inactive, .armed:
            return nil
        }
    }

    private func clamped(_ strength: Double) -> Double {
        max(config.minStrength, min(config.maxStrength, strength))
    }
}
