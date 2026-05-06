import Foundation

// MARK: - Connection Mode

enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    case ble = "Bluetooth (BLE)"
    case http = "HTTP / WebSocket"

    static var allCases: [ConnectionMode] { [.ble, .http] }

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ble: return "antenna.radiowaves.left.and.right"
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

enum BLEProtocolVersion: String, Codable, CaseIterable, Identifiable {
    case gen1 = "Gen 1"
    case gen2 = "Gen 2"

    var id: String { rawValue }
}

enum BLEOutputMode: String, Codable, CaseIterable, Identifiable {
    case compatibility = "Compatibility"
    case realtime = "Realtime"

    var id: String { rawValue }
}

// MARK: - Connection Configuration

struct ConnectionConfig: Codable, Equatable {
    var mode: ConnectionMode

    // BLE settings
    var bleLastDeviceId: String?
    var bleLastDeviceName: String?
    var bleAutoConnect: Bool
    var bleProtocolVersion: BLEProtocolVersion
    var bleOutputMode: BLEOutputMode

    // HTTP settings
    var httpServerURL: String
    var httpAPIKey: String
    var httpCommandID: String
    var httpStopCommandID: String
    var httpAutoReconnect: Bool

    static let `default` = ConnectionConfig(
        mode: .ble,
        bleLastDeviceId: nil,
        bleLastDeviceName: nil,
        bleAutoConnect: false,
        bleProtocolVersion: .gen2,
        bleOutputMode: .compatibility,
        httpServerURL: "http://localhost:3001",
        httpAPIKey: "",
        httpCommandID: "hurt",
        httpStopCommandID: "_stop_all",
        httpAutoReconnect: true
    )

    private enum CodingKeys: String, CodingKey {
        case mode
        case bleLastDeviceId
        case bleLastDeviceName
        case bleAutoConnect
        case bleProtocolVersion
        case bleOutputMode
        case httpServerURL
        case httpAPIKey
        case httpCommandID
        case httpStopCommandID
        case httpAutoReconnect
    }

    init(mode: ConnectionMode,
         bleLastDeviceId: String?,
         bleLastDeviceName: String?,
         bleAutoConnect: Bool,
         bleProtocolVersion: BLEProtocolVersion,
         bleOutputMode: BLEOutputMode,
         httpServerURL: String,
         httpAPIKey: String,
         httpCommandID: String,
         httpStopCommandID: String,
         httpAutoReconnect: Bool) {
        self.mode = mode
        self.bleLastDeviceId = bleLastDeviceId
        self.bleLastDeviceName = bleLastDeviceName
        self.bleAutoConnect = bleAutoConnect
        self.bleProtocolVersion = bleProtocolVersion
        self.bleOutputMode = bleOutputMode
        self.httpServerURL = httpServerURL
        self.httpAPIKey = httpAPIKey
        self.httpCommandID = httpCommandID
        self.httpStopCommandID = httpStopCommandID
        self.httpAutoReconnect = httpAutoReconnect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ConnectionConfig.default
        mode = try container.decodeIfPresent(ConnectionMode.self, forKey: .mode) ?? defaults.mode
        bleLastDeviceId = try container.decodeIfPresent(String.self, forKey: .bleLastDeviceId)
        bleLastDeviceName = try container.decodeIfPresent(String.self, forKey: .bleLastDeviceName)
        bleAutoConnect = try container.decodeIfPresent(Bool.self, forKey: .bleAutoConnect) ?? defaults.bleAutoConnect
        bleProtocolVersion = try container.decodeIfPresent(BLEProtocolVersion.self, forKey: .bleProtocolVersion) ?? defaults.bleProtocolVersion
        bleOutputMode = try container.decodeIfPresent(BLEOutputMode.self, forKey: .bleOutputMode) ?? defaults.bleOutputMode
        httpServerURL = try container.decodeIfPresent(String.self, forKey: .httpServerURL) ?? defaults.httpServerURL
        httpAPIKey = try container.decodeIfPresent(String.self, forKey: .httpAPIKey) ?? defaults.httpAPIKey
        httpCommandID = try container.decodeIfPresent(String.self, forKey: .httpCommandID) ?? defaults.httpCommandID
        httpStopCommandID = try container.decodeIfPresent(String.self, forKey: .httpStopCommandID) ?? defaults.httpStopCommandID
        httpAutoReconnect = try container.decodeIfPresent(Bool.self, forKey: .httpAutoReconnect) ?? defaults.httpAutoReconnect
    }
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
