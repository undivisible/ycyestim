import Foundation
import CoreBluetooth
import Combine

extension CBPeripheral: @unchecked @retroactive Sendable {}
extension CBCharacteristic: @unchecked @retroactive Sendable {}

@MainActor
final class BluetoothService: NSObject {
    static let shared = BluetoothService()

    private var _peripherals: [BLEPeripheralInfo] = []
    private var _peripheralMap: [UUID: CBPeripheral] = [:]
    private var _peripheralInfoMap: [UUID: BLEPeripheralInfo] = [:]
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var isScanning = false
    private var isConnected = false
    private var characteristics: [String: CBCharacteristic] = [:]
    private var _batteryLevel: Int? = nil
    private var _firmwareVersion: String? = nil
    private var connectContinuation: CheckedContinuation<Void, Error>?

    let peripheralSubject = PassthroughSubject<[BLEPeripheralInfo], Never>()
    let connectionSubject = PassthroughSubject<Bool, Never>()
    let batterySubject = PassthroughSubject<Int, Never>()
    let firmwareSubject = PassthroughSubject<String, Never>()

    private var onDiscover: (([BLEPeripheralInfo]) -> Void)?

    private let serviceUUID = CBUUID(string: "0000FF30-0000-1000-8000-00805F9B34FB")
    private let txCharUUID = CBUUID(string: "0000FF31-0000-1000-8000-00805F9B34FB")
    private let rxCharUUID = CBUUID(string: "0000FF32-0000-1000-8000-00805F9B34FB")

    // MARK: - Scanning

    func startScan(onDiscover: @escaping ([BLEPeripheralInfo]) -> Void) {
        self.onDiscover = onDiscover
        isScanning = true
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            beginScan()
        }
    }

    func stopScan() {
        isScanning = false
        onDiscover = nil
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
        guard _peripheralInfoMap[peripheralId]?.isConnectable != false else {
            throw BLEError.notConnectable
        }

        characteristics.removeAll()

        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            centralManager?.connect(p, options: nil)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.connectContinuation != nil else { return }
                self.centralManager?.cancelPeripheralConnection(p)
                self.failPendingConnection(BLEError.connectionTimedOut)
            }
        }
    }

    func disconnect() {
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        peripheral = nil
        isConnected = false
        connectionSubject.send(false)
    }

    var isReady: Bool {
        isConnected && peripheral != nil && characteristics["tx"] != nil
    }

    func sendChannelControl(channel: String, strength: Int, durationMs: Int) async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }

        let command = buildChannelCommand(channel: channel, strength: strength, durationMs: durationMs)
        p.writeValue(command, for: char, type: .withoutResponse)
    }

    func sendRealtimeControl(channelA: ChannelState, channelB: ChannelState, adaptiveStrengthLimit: Double) async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }

        let command = buildRealtimeCommand(
            channelA: channelA,
            channelB: channelB,
            adaptiveStrengthLimit: adaptiveStrengthLimit
        )
        p.writeValue(command, for: char, type: .withoutResponse)
    }

    func emergencyStop() async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }
        p.writeValue(buildEmergencyCommand(), for: char, type: .withoutResponse)
    }

    private func buildChannelCommand(channel: String, strength: Int, durationMs: Int) -> Data {
        let state = ChannelState(
            id: channel == "B" ? .b : .a,
            isEnabled: strength > 0,
            strength: Double(strength),
            durationMs: durationMs
        )
        if channel == "B" {
            return buildRealtimeCommand(channelA: .init(id: .a), channelB: state, adaptiveStrengthLimit: 100)
        }
        return buildRealtimeCommand(channelA: state, channelB: .init(id: .b), adaptiveStrengthLimit: 100)
    }

    private func buildRealtimeCommand(channelA: ChannelState, channelB: ChannelState, adaptiveStrengthLimit: Double) -> Data {
        var data = Data()
        data.append(0x35)
        data.append(0x11)
        data.append(0x02)
        appendRealtimeChannel(channelA, adaptiveStrengthLimit: adaptiveStrengthLimit, to: &data)
        appendRealtimeChannel(channelB, adaptiveStrengthLimit: adaptiveStrengthLimit, to: &data)
        data.append(checksum(data))
        return data
    }

    private func appendRealtimeChannel(_ channel: ChannelState, adaptiveStrengthLimit: Double, to data: inout Data) {
        let strength = channel.isEnabled ? min(channel.strength, adaptiveStrengthLimit) : 0
        let deviceStrength = UInt16(max(0, min(276, Int((strength / 100.0 * 276.0).rounded()))))
        let frequency = UInt8(max(1, min(100, Int(channel.frequency.rounded()))))
        let pulseWidth = UInt8(max(0, min(100, channel.pulseWidth / 10)))

        data.append(UInt8((deviceStrength >> 8) & 0xFF))
        data.append(UInt8(deviceStrength & 0xFF))
        data.append(frequency)
        data.append(pulseWidth)
    }

    private func buildEmergencyCommand() -> Data {
        buildRealtimeCommand(channelA: .init(id: .a), channelB: .init(id: .b), adaptiveStrengthLimit: 100)
    }

    private func checksum(_ data: Data) -> UInt8 {
        data.reduce(UInt8(0)) { partial, byte in partial &+ byte }
    }

    // MARK: - Status

    var batteryLevel: Int? { _batteryLevel }
    var firmwareVersion: String? { _firmwareVersion }

    private func beginScan() {
        isScanning = true
        _peripherals.removeAll()
        _peripheralMap.removeAll()
        _peripheralInfoMap.removeAll()
        onDiscover?([])
        peripheralSubject.send([])
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func completeConnectionIfReady() {
        guard characteristics["tx"] != nil else { return }
        isConnected = true
        connectionSubject.send(true)
        connectContinuation?.resume()
        connectContinuation = nil
    }

    private func failPendingConnection(_ error: Error) {
        connectContinuation?.resume(throwing: error)
        connectContinuation = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Task { @MainActor [weak self] in
                guard self?.isScanning == true else { return }
                self?.beginScan()
            }
        default:
            break
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any],
                                     rssi RSSI: NSNumber) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? localName ?? "Unknown"
        let primaryServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflowServices = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        let solicitedServices = advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceUUIDs = primaryServices + overflowServices + solicitedServices
        let serviceStrings = serviceUUIDs.map { $0.uuidString.uppercased() }
        let matchesService = serviceStrings.contains("FF30") || serviceStrings.contains("0000FF30-0000-1000-8000-00805F9B34FB")
        let matchesName = ["YCY", "YOKONEX", "YSKJ", "役次元"].contains { name.localizedCaseInsensitiveContains($0) }
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool)
            ?? (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
            ?? true
        let rssi = RSSI.intValue
        let strongEnoughForNameMatch = rssi >= -85
        guard isConnectable, matchesService || (matchesName && strongEnoughForNameMatch) else { return }
        let matchDescription = matchesService ? "YCY service" : "Name match"

        let info = BLEPeripheralInfo(
            id: peripheral.identifier,
            name: name,
            rssi: rssi,
            isPaired: false,
            hasEstimService: matchesService,
            isConnectable: isConnectable,
            matchDescription: matchDescription
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            var current = self._peripherals
            current.removeAll { $0.id == info.id }
            current.append(info)
            current.sort { abs($0.rssi) < abs($1.rssi) }
            self._peripherals = current
            self._peripheralMap[peripheral.identifier] = peripheral
            self._peripheralInfoMap[peripheral.identifier] = info
            self.onDiscover?(current)
            self.peripheralSubject.send(current)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.peripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didFailToConnect peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor [weak self] in
            self?.failPendingConnection(error ?? BLEError.connectionFailed)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.peripheral = nil
            self.characteristics.removeAll()
            self.connectionSubject.send(false)
            self.failPendingConnection(error ?? BLEError.connectionFailed)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverServices error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard error == nil, let services = peripheral.services else {
                self.failPendingConnection(error ?? BLEError.connectionFailed)
                return
            }

            let matchingServices = services.filter { $0.uuid == self.serviceUUID || $0.uuid.uuidString.uppercased() == "FF30" }
            guard !matchingServices.isEmpty else {
                self.failPendingConnection(BLEError.incompatibleDevice)
                return
            }

            for service in matchingServices {
                peripheral.discoverCharacteristics(
                    [CBUUID(string: "0000FF31-0000-1000-8000-00805F9B34FB"),
                     CBUUID(string: "0000FF32-0000-1000-8000-00805F9B34FB")],
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        guard error == nil, let chars = service.characteristics else {
            Task { @MainActor [weak self] in self?.failPendingConnection(error ?? BLEError.connectionFailed) }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for char in chars {
                if char.uuid == self.txCharUUID || char.uuid.uuidString.uppercased() == "FF31" {
                    self.characteristics["tx"] = char
                } else if char.uuid == self.rxCharUUID || char.uuid.uuidString.uppercased() == "FF32" {
                    self.characteristics["rx"] = char
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            if self.characteristics["tx"] == nil {
                self.failPendingConnection(BLEError.incompatibleDevice)
            } else {
                self.completeConnectionIfReady()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        guard let data = characteristic.value else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if data.count >= 5, data[0] == 0x35, data[1] == 0x71, data[2] == 0x04 {
                let level = Int(data[3])
                self._batteryLevel = level
                self.batterySubject.send(level)
            } else if let raw = String(data: data, encoding: .utf8) {
                if raw.hasPrefix("BAT:") {
                    let level = Int(raw.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? 0
                    self._batteryLevel = level
                    self.batterySubject.send(level)
                } else if raw.hasPrefix("FW:") {
                    let version = String(raw.dropFirst(3).trimmingCharacters(in: .whitespaces))
                    self._firmwareVersion = version
                    self.firmwareSubject.send(version)
                }
            }
        }
    }
}

// MARK: - Errors

enum BLEError: Error, LocalizedError {
    case notConnected
    case scanFailed
    case connectionFailed
    case connectionTimedOut
    case incompatibleDevice
    case notConnectable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .scanFailed: return "BLE scan failed"
        case .connectionFailed: return "Connection failed"
        case .connectionTimedOut: return "Connection timed out. Move the device closer, wake it, then scan again."
        case .incompatibleDevice: return "This is not a supported YCY Gen 2 Bluetooth device."
        case .notConnectable: return "This Bluetooth advertisement is not connectable."
        case .writeFailed: return "Write to device failed"
        }
    }
}
