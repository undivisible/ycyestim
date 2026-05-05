import Foundation
import CoreBluetooth
import Combine

// MARK: - Bluetooth Service

actor BluetoothService: NSObject {
    // Published state for consumers
    private var _peripherals: [BLEPeripheralInfo] = []
    private var _peripheralMap: [UUID: CBPeripheral] = [:]
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var isScanning = false
    private var isConnected = false
    private var characteristics: [String: CBCharacteristic] = [:]
    private var _batteryLevel: Int? = nil
    private var _firmwareVersion: String? = nil

    // Combine subjects for pushing state to consumers
    let peripheralSubject = PassthroughSubject<[BLEPeripheralInfo], Never>()
    let connectionSubject = PassthroughSubject<Bool, Never>()
    let batterySubject = PassthroughSubject<Int, Never>()
    let firmwareSubject = PassthroughSubject<String, Never>()

    private var onDiscover: (([BLEPeripheralInfo]) -> Void)?

    // Gen 2 BLE service/characteristic UUIDs
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let txCharUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    private let rxCharUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")

    // MARK: - Scanning

    func startScan(onDiscover: @escaping ([BLEPeripheralInfo]) -> Void) {
        self.onDiscover = onDiscover
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func stopScan() {
        isScanning = false
        centralManager?.stopScan()
    }

    var peripherals: [BLEPeripheralInfo] {
        _peripherals
    }

    // MARK: - Connection

    func connect(to peripheralId: UUID) async throws {
        stopScan()

        guard let p = _peripheralMap[peripheralId] else {
            throw BLEError.connectionFailed
        }

        centralManager?.connect(p, options: nil)
        // Connection completion handled by delegate callback
    }

    func disconnect() {
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        peripheral = nil
        isConnected = false
        connectionSubject.send(false)
    }

    // MARK: - Commands

    func sendChannelControl(channel: String, strength: Int, durationMs: Int) async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }

        let command = buildChannelCommand(channel: channel, strength: strength, durationMs: durationMs)
        p.writeValue(command, for: char, type: .withResponse)
    }

    func emergencyStop() async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }
        p.writeValue(buildEmergencyCommand(), for: char, type: .withResponse)
    }

    // MARK: - Command Builders

    private func buildChannelCommand(channel: String, strength: Int, durationMs: Int) -> Data {
        var data = Data()
        data.append(0x01)                           // Header
        data.append(UInt8(channel == "A" ? 0x0A : (channel == "B" ? 0x0B : 0xAB)))
        data.append(UInt8(max(0, min(100, strength))))
        data.append(UInt8((durationMs >> 8) & 0xFF))
        data.append(UInt8(durationMs & 0xFF))
        data.append(checksum(data))
        return data
    }

    private func buildEmergencyCommand() -> Data {
        var data = Data()
        data.append(0x01)
        data.append(0xFF)
        data.append(0x00)
        data.append(checksum(data))
        return data
    }

    private func checksum(_ data: Data) -> UInt8 {
        var sum: UInt8 = 0
        for byte in data { sum ^= byte }
        return sum
    }

    // MARK: - Status

    var batteryLevel: Int? { _batteryLevel }
    var firmwareVersion: String? { _firmwareVersion }
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
        let name = peripheral.name ?? "Unknown"
        guard name.contains("YCY") || name.contains("役次元") else { return }

        let info = BLEPeripheralInfo(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            isPaired: false
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Deduplicate
            var current = await self._peripherals
            current.removeAll { $0.id == info.id }
            current.append(info)
            current.sort { abs($0.rssi) < abs($1.rssi) }
            await MainActor.run {
                self._peripherals = current
            }
            await MainActor.run {
                self._peripheralMap[peripheral.identifier] = peripheral
                self.onDiscover?(current)
                self.peripheralSubject.send(current)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self as? CBPeripheralDelegate
        peripheral.discoverServices(nil)
        Task { @MainActor in
            await MainActor.run {
                self.isConnected = true
            }
            await MainActor.run {
                self.connectionSubject.send(true)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            await MainActor.run {
                self.isConnected = false
            }
            await MainActor.run {
                self.peripheral = nil
                self.connectionSubject.send(false)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(
                [CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB"),
                 CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        guard let chars = service.characteristics else { return }
        Task { @MainActor in
            for char in chars {
                if char.uuid.uuidString.contains("FFE1") {
                    await MainActor.run { self.characteristics["tx"] = char }
                } else if char.uuid.uuidString.contains("FFE2") {
                    await MainActor.run { self.characteristics["rx"] = char }
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        guard let data = characteristic.value, let raw = String(data: data, encoding: .utf8) else { return }

        Task { @MainActor in
            // Parse device status updates
            if raw.hasPrefix("BAT:") {
                let level = Int(raw.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? 0
                await MainActor.run { self._batteryLevel = level }
                self.batterySubject.send(level)
            } else if raw.hasPrefix("FW:") {
                let version = String(raw.dropFirst(3).trimmingCharacters(in: .whitespaces))
                await MainActor.run { self._firmwareVersion = version }
                self.firmwareSubject.send(version)
            }
        }
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
