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

    static let `default` = EdgeModeConfig(
        isEnabled: false,
        targetBPM: 118,
        peakBPM: 138,
        recoveryBPM: 96,
        minStrength: 14,
        maxStrength: 58,
        rampStep: 2,
        cooldownSeconds: 8
    )
}

enum HeartRateSafetyState: Equatable {
    case inactive
    case unavailable
    case needsAuthorization
    case monitoring(bpm: Double, multiplier: Double)
    case elevated(bpm: Double, multiplier: Double)
    case high(bpm: Double, multiplier: Double)
    case critical(bpm: Double)

    var bpm: Double? {
        switch self {
        case .inactive, .unavailable, .needsAuthorization:
            return nil
        case .monitoring(let bpm, _), .elevated(let bpm, _), .high(let bpm, _), .critical(let bpm):
            return bpm
        }
    }

    var strengthMultiplier: Double {
        switch self {
        case .monitoring(_, let multiplier), .elevated(_, let multiplier), .high(_, let multiplier):
            return multiplier
        case .critical:
            return 0
        case .inactive, .unavailable, .needsAuthorization:
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

    private func clamped(_ strength: Double) -> Double {
        max(config.minStrength, min(config.maxStrength, strength))
    }
}
