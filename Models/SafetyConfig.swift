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
