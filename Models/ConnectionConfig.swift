import Foundation

// MARK: - Connection Mode

enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    case ble = "Bluetooth (BLE)"
    case http = "HTTP / WebSocket"

    static var allCases: [ConnectionMode] { [.ble, .http] }

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ble: return "bluetooth"
        case .http: return "server.rack"
        }
    }

    var description: String {
        switch self {
        case .ble: return "Direct Bluetooth connection. No internet needed."
        case .http: return "Connect to your own local API-bridge server."
        }
    }
}

// MARK: - Connection Configuration

struct ConnectionConfig: Codable, Equatable {
    var mode: ConnectionMode

    // BLE settings
    var bleLastDeviceId: String?
    var bleAutoConnect: Bool

    // HTTP settings
    var httpServerURL: String
    var httpAPIKey: String
    var httpAutoReconnect: Bool

    static let `default` = ConnectionConfig(
        mode: .ble,
        bleLastDeviceId: nil,
        bleAutoConnect: false,
        httpServerURL: "http://localhost:3001",
        httpAPIKey: "",
        httpAutoReconnect: true
    )
}

// MARK: - Appearance Config

struct AppearanceConfig: Codable, Equatable {
    var glassLevel: GlassLevel
    var accentColor: String         // hex
    var animationSpeed: AnimationSpeed
    var displayPrecision: DisplayPrecision

    enum GlassLevel: String, Codable, CaseIterable {
        case ultraThin = "Ultra Thin"
        case thin = "Thin"
        case regular = "Regular"
        case thick = "Thick"
    }

    enum AnimationSpeed: String, Codable, CaseIterable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
    }

    enum DisplayPrecision: String, Codable, CaseIterable {
        case integer = "Integer"
        case oneDecimal = "1 Decimal"
    }

    static let `default` = AppearanceConfig(
        glassLevel: .thin,
        accentColor: "#007AFF",
        animationSpeed: .normal,
        displayPrecision: .integer
    )
}

// MARK: - Notification Config

struct NotificationConfig: Codable, Equatable {
    var sessionStart: Bool
    var sessionStop: Bool
    var strengthThresholdAlert: Bool
    var timerWarningAlert: Bool
    var disconnectAlert: Bool
    var timerWarningMinutes: Int

    static let `default` = NotificationConfig(
        sessionStart: true,
        sessionStop: true,
        strengthThresholdAlert: true,
        timerWarningAlert: true,
        disconnectAlert: true,
        timerWarningMinutes: 5
    )
}
