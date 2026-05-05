import Foundation

// MARK: - Safety Configuration

struct SafetyConfig: Codable, Equatable {
    /// Global maximum strength (0-100)
    var maxStrength: Double

    /// Session timeout in minutes (0 = no timeout)
    var sessionTimeoutMinutes: Int

    /// Ramp rate limit: strength units per second
    var rampRateLimit: Double

    /// Strength threshold that requires confirmation
    var confirmationThreshold: Double

    /// Emergency stop gesture type
    var emergencyGesture: EmergencyGesture

    /// Auto-shutdown on disconnect
    var autoShutdownOnDisconnect: Bool

    /// Heart rate monitor placeholder (future)
    var heartRateMonitoring: Bool

    /// Haptic intensity for controls
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
