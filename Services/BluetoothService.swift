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
    private let waveformEngine = WaveformEngine()

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
        write(command, to: char, on: p)
    }

    func sendRealtimeControl(channelA: ChannelState, channelB: ChannelState, adaptiveStrengthLimit: Double, protocolVersion: BLEProtocolVersion, outputMode: BLEOutputMode) async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }

        let maxPairs = max(1, min(100, (p.maximumWriteValueLength(for: .withoutResponse) - 7) / 2))
        let commands: [Data]
        switch protocolVersion {
        case .gen1:
            commands = buildGen1OutputCommands(channelA: channelA, channelB: channelB, adaptiveStrengthLimit: adaptiveStrengthLimit, outputMode: outputMode)
        case .gen2:
            commands = await buildGen2OutputCommands(
                channelA: channelA,
                channelB: channelB,
                adaptiveStrengthLimit: adaptiveStrengthLimit,
                maxPairs: maxPairs,
                outputMode: outputMode
            )
        }
        for command in commands {
            write(command, to: char, on: p)
            if commands.count > 1 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func emergencyStop(protocolVersion: BLEProtocolVersion = .gen2) async throws {
        guard let p = peripheral, let char = characteristics["tx"] else {
            throw BLEError.notConnected
        }
        write(buildEmergencyCommand(protocolVersion: protocolVersion), to: char, on: p)
    }

    private func write(_ command: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(command, for: characteristic, type: type)
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

    private func buildGen2OutputCommands(channelA: ChannelState, channelB: ChannelState, adaptiveStrengthLimit: Double, maxPairs: Int, outputMode: BLEOutputMode) async -> [Data] {
        if outputMode == .compatibility {
            return [buildFixedModeCommand(channelA: channelA, channelB: channelB, adaptiveStrengthLimit: adaptiveStrengthLimit)]
        }

        var commands = [
            buildRealtimeCommand(channelA: channelA, channelB: channelB, adaptiveStrengthLimit: adaptiveStrengthLimit)
        ]

        if let command = await buildFrequencyModeCommand(channelA, selector: 0x01, adaptiveStrengthLimit: adaptiveStrengthLimit, maxPairs: maxPairs) {
            commands.append(command)
        }
        if let command = await buildFrequencyModeCommand(channelB, selector: 0x02, adaptiveStrengthLimit: adaptiveStrengthLimit, maxPairs: maxPairs) {
            commands.append(command)
        }

        return commands
    }

    private func buildGen1OutputCommands(channelA: ChannelState, channelB: ChannelState, adaptiveStrengthLimit: Double, outputMode: BLEOutputMode) -> [Data] {
        if !channelA.isEnabled && !channelB.isEnabled {
            return [buildGen1ChannelCommand(channel: channelA, selector: 0x03, adaptiveStrengthLimit: adaptiveStrengthLimit, outputMode: outputMode)]
        }
        if channelA.isEnabled && channelB.isEnabled {
            var synced = channelA
            synced.strength = max(channelA.strength, channelB.strength)
            return [buildGen1ChannelCommand(channel: synced, selector: 0x03, adaptiveStrengthLimit: adaptiveStrengthLimit, outputMode: outputMode)]
        }
        return [
            buildGen1ChannelCommand(channel: channelA, selector: 0x01, adaptiveStrengthLimit: adaptiveStrengthLimit, outputMode: outputMode),
            buildGen1ChannelCommand(channel: channelB, selector: 0x02, adaptiveStrengthLimit: adaptiveStrengthLimit, outputMode: outputMode)
        ]
    }

    private func buildGen1ChannelCommand(channel: ChannelState, selector: UInt8, adaptiveStrengthLimit: Double, outputMode: BLEOutputMode = .realtime) -> Data {
        var data = Data()
        data.append(0x35)
        data.append(0x11)
        data.append(selector)
        data.append(channel.isEnabled && channel.strength > 0 ? 0x01 : 0x00)
        appendDeviceStrength(channel, adaptiveStrengthLimit: adaptiveStrengthLimit, to: &data)
        if channel.isEnabled && channel.strength > 0 {
            if outputMode == .realtime && channel.waveform.isCustom {
                data.append(0x11)
                data.append(UInt8(max(1, min(100, Int(channel.frequency.rounded())))))
                data.append(UInt8(max(1, min(100, channel.pulseWidth))))
            } else {
                data.append(fixedMode(for: channel.waveform))
                data.append(0x00)
                data.append(0x00)
            }
        } else {
            data.append(0x00)
            data.append(0x00)
            data.append(0x00)
        }
        data.append(checksum(data))
        return data
    }

    private func buildFixedModeCommand(channelA: ChannelState, channelB: ChannelState, adaptiveStrengthLimit: Double) -> Data {
        var data = Data()
        data.append(0x35)
        data.append(0x11)
        data.append(0x01)
        appendDeviceStrength(channelA, adaptiveStrengthLimit: adaptiveStrengthLimit, to: &data)
        data.append(channelA.isEnabled && channelA.strength > 0 ? fixedMode(for: channelA.waveform) : 0x00)
        appendDeviceStrength(channelB, adaptiveStrengthLimit: adaptiveStrengthLimit, to: &data)
        data.append(channelB.isEnabled && channelB.strength > 0 ? fixedMode(for: channelB.waveform) : 0x00)
        data.append(checksum(data))
        return data
    }

    private func buildFrequencyModeCommand(_ channel: ChannelState, selector: UInt8, adaptiveStrengthLimit: Double, maxPairs: Int) async -> Data? {
        guard channel.isEnabled, channel.strength > 0 else { return nil }
        let pairs = await waveformPairs(for: channel, maxPairs: maxPairs)
        guard !pairs.isEmpty else { return nil }

        var data = Data()
        data.append(0x35)
        data.append(0x11)
        data.append(0x03)
        data.append(selector)
        appendDeviceStrength(channel, adaptiveStrengthLimit: adaptiveStrengthLimit, to: &data)
        for pair in pairs {
            data.append(pair.frequency)
            data.append(pair.pulseWidth)
        }
        data.append(checksum(data))
        return data
    }

    private func appendRealtimeChannel(_ channel: ChannelState, adaptiveStrengthLimit: Double, to data: inout Data) {
        let deviceStrength = deviceStrength(for: channel, adaptiveStrengthLimit: adaptiveStrengthLimit)
        let frequency = UInt8(max(1, min(100, Int(channel.frequency.rounded()))))
        let pulseWidth = UInt8(max(0, min(100, channel.pulseWidth)))

        data.append(UInt8((deviceStrength >> 8) & 0xFF))
        data.append(UInt8(deviceStrength & 0xFF))
        data.append(frequency)
        data.append(pulseWidth)
    }

    private func appendDeviceStrength(_ channel: ChannelState, adaptiveStrengthLimit: Double, to data: inout Data) {
        let strength = deviceStrength(for: channel, adaptiveStrengthLimit: adaptiveStrengthLimit)
        data.append(UInt8((strength >> 8) & 0xFF))
        data.append(UInt8(strength & 0xFF))
    }

    private func deviceStrength(for channel: ChannelState, adaptiveStrengthLimit: Double) -> UInt16 {
        let strength = channel.isEnabled ? min(channel.strength, adaptiveStrengthLimit) : 0
        return UInt16(max(0, min(276, Int((strength / 100.0 * 276.0).rounded()))))
    }

    private func fixedMode(for waveform: WaveformType) -> UInt8 {
        switch waveform {
        case .pulse(let count):
            switch count {
            case .single: return 0x01
            case .double: return 0x02
            case .triple: return 0x03
            case .quad: return 0x04
            }
        case .sine, .wave:
            return 0x05
        case .square:
            return 0x06
        case .sawtooth:
            return 0x07
        case .triangle:
            return 0x08
        case .rampUp:
            return 0x09
        case .rampDown:
            return 0x0A
        case .random:
            return 0x0B
        case .heartbeat:
            return 0x0C
        case .staircase:
            return 0x0D
        case .alternating, .sweep:
            return 0x0E
        case .tremolo, .breath, .glide, .flutter, .crescendo:
            return 0x0F
        case .echo, .custom:
            return 0x10
        }
    }

    private func waveformPairs(for channel: ChannelState, maxPairs: Int) async -> [(frequency: UInt8, pulseWidth: UInt8)] {
        let samples = max(1, maxPairs)
        let points = await waveformEngine.generate(channel.waveform, samples: samples, frequency: channel.frequency)
        let baseFrequency = max(1, min(100, Int(channel.frequency.rounded())))
        let maxPulse = max(0, min(100, channel.pulseWidth))
        let swing = max(1, Int((Double(baseFrequency) * 0.24).rounded()))

        return points.prefix(samples).map { point in
            let normalized = max(0, min(1, (point + 1) / 2))
            let pulse = Int((Double(maxPulse) * (0.18 + normalized * 0.82)).rounded())
            let frequency = baseFrequency + Int((point * Double(swing)).rounded())
            return (
                frequency: UInt8(max(1, min(100, frequency))),
                pulseWidth: UInt8(max(0, min(100, pulse)))
            )
        }
    }

    private func buildEmergencyCommand(protocolVersion: BLEProtocolVersion) -> Data {
        switch protocolVersion {
        case .gen1:
            return buildGen1ChannelCommand(channel: .init(id: .a), selector: 0x03, adaptiveStrengthLimit: 100)
        case .gen2:
            return buildRealtimeCommand(channelA: .init(id: .a), channelB: .init(id: .b), adaptiveStrengthLimit: 100)
        }
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
        case .incompatibleDevice: return "This is not a supported YCY Bluetooth device."
        case .notConnectable: return "This Bluetooth advertisement is not connectable."
        case .writeFailed: return "Write to device failed"
        }
    }
}
