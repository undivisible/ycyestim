import Foundation
import CoreBluetooth
import Combine

// MARK: - Bluetooth Service

actor BluetoothService: NSObject {
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var discoveredPeripherals: [BLEPeripheralInfo] = []
    private var isScanning = false
    private var isConnected = false
    private var characteristics: [String: CBCharacteristic] = [:]

    // Gen 2 BLE service/characteristic UUIDs (update per device spec)
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let txCharUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")

    // MARK: - Scanning

    func startScan() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func stopScan() {
        centralManager?.stopScan()
        isScanning = false
    }

    var peripherals: [BLEPeripheralInfo] {
        discoveredPeripherals
    }

    // MARK: - Connection

    func connect(to peripheralId: UUID) async throws {
        // Find peripheral by ID (stored during scan)
        // In production, maintain a CBPeripheral map
        stopScan()

        // Connect to peripheral
        // centralManager?.connect(peripheral, options: nil)
        // Wait for connection callback
    }

    func disconnect() {
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        peripheral = nil
        isConnected = false
    }

    // MARK: - Commands

    func sendChannelControl(channel: String, strength: Int, durationMs: Int) async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }

        // Build command bytes per Gen 2 protocol
        // The actual byte format depends on the device spec from the PDF
        let command = buildChannelCommand(channel: channel, strength: strength, durationMs: durationMs)
        p.writeValue(command, for: char, type: .withResponse)
    }

    func emergencyStop() async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }

        let command = buildEmergencyCommand()
        p.writeValue(command, for: char, type: .withResponse)
    }

    // MARK: - Command Builders

    private func buildChannelCommand(channel: String, strength: Int, durationMs: Int) -> Data {
        // Gen 2 protocol: construct bytes
        // This is a placeholder — actual bytes depend on the protocol PDF spec
        var data = Data()
        data.append(0x01)                           // Header
        data.append(UInt8(channel == "A" ? 0x0A : 0x0B))
        data.append(UInt8(max(0, min(100, strength))))
        data.append(UInt8((durationMs >> 8) & 0xFF))
        data.append(UInt8(durationMs & 0xFF))
        data.append(checksum(data))
        return data
    }

    private func buildEmergencyCommand() -> Data {
        var data = Data()
        data.append(0x01)                           // Header
        data.append(0xFF)                           // Emergency stop opcode
        data.append(0x00)                           // Checksum placeholder
        data.append(checksum(data))
        return data
    }

    private func checksum(_ data: Data) -> UInt8 {
        var sum: UInt8 = 0
        for byte in data {
            sum ^= byte
        }
        return sum
    }

    // MARK: - Status

    var batteryLevel: Int? { nil } // Read from device characteristic
    var firmwareVersion: String? { nil } // Read from device characteristic
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil, options: nil)
        default:
            break
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any],
                                     rssi RSSI: NSNumber) {
        // Filter for YCY devices
        let name = peripheral.name ?? "Unknown"
        if name.contains("YCY") || name.contains("役次元") {
            let info = BLEPeripheralInfo(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                isPaired: false
            )
            Task { @MainActor in
                // Update discovered list via callback
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self as? CBPeripheralDelegate
        peripheral.discoverServices(nil)
    }
}

// MARK: - Errors

enum BLEError: Error, LocalizedError {
    case notConnected
    case scanFailed
    case connectionFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .scanFailed: return "BLE scan failed"
        case .connectionFailed: return "Connection failed"
        case .writeFailed: return "Write to device failed"
        }
    }
}
