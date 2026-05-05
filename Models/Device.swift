import Foundation

// MARK: - Device

struct Device: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var firmwareVersion: String?
    var batteryLevel: Int?          // 0–100
    var isCharging: Bool
    var channelCount: Int
    var generation: DeviceGeneration
    var lastConnected: Date?

    enum DeviceGeneration: String, Codable {
        case gen1 = "Gen 1"
        case gen2 = "Gen 2"
        case unknown = "Unknown"
    }

    var displayName: String {
        name.isEmpty ? "YCY Device" : name
    }

    var batteryIcon: String {
        guard let level = batteryLevel else { return "battery.0" }
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
}

// MARK: - Discovered BLE Peripheral (for scanning)

struct BLEPeripheralInfo: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let isPaired: Bool
}
