import Foundation
import Combine

// MARK: - Device ViewModel

@MainActor
final class DeviceVM: ObservableObject {
    @Published var device: Device?
    @Published var discoveredPeripherals: [BLEPeripheralInfo] = []
    @Published var isScanning: Bool = false
    @Published var connectionState: DeviceConnectionState = .disconnected
    @Published var batteryLevel: Int?
    @Published var firmwareVersion: String?
    @Published var scanStatusText: String = "Ready to scan"
    @Published var activeConnectionId: UUID?

    enum DeviceConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    private let bluetoothService = BluetoothService.shared
    private var scanTask: Task<Void, Never>?
    private var autoConnectTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?

    // MARK: - Scanning

    func startScan() {
        scanTask?.cancel()
        isScanning = true
        discoveredPeripherals = []
        scanStatusText = "Scanning for YCY Gen 2 devices..."
        scanTask = Task { [weak self] in
            guard let self else { return }
            bluetoothService.startScan { [weak self] peripherals in
                self?.discoveredPeripherals = peripherals
                self?.scanStatusText = peripherals.isEmpty
                    ? "No compatible devices yet. Wake the device and keep it close."
                    : "\(peripherals.count) compatible device\(peripherals.count == 1 ? "" : "s") found"
            }
            while !Task.isCancelled && isScanning {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let peripherals = bluetoothService.peripherals
                discoveredPeripherals = peripherals
                scanStatusText = peripherals.isEmpty
                    ? "No compatible devices yet. Wake the device and keep it close."
                    : "\(peripherals.count) compatible device\(peripherals.count == 1 ? "" : "s") found"
            }
        }
    }

    func stopScan() {
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        if discoveredPeripherals.isEmpty && connectionState != .connected {
            scanStatusText = "No compatible YCY Gen 2 devices found."
        }
        bluetoothService.stopScan()
    }

    func autoConnectLastDevice(id: String, onConnected: (() -> Void)? = nil) {
        guard connectionState == .disconnected else { return }
        autoConnectTask?.cancel()
        startScan()

        autoConnectTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(12)
            while !Task.isCancelled && Date() < deadline {
                if let peripheral = discoveredPeripherals.first(where: { $0.id.uuidString == id }) {
                    connect(to: peripheral, onConnected: onConnected)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            stopScan()
        }
    }

    // MARK: - Connection

    func connect(to peripheral: BLEPeripheralInfo, onConnected: (() -> Void)? = nil) {
        connectionTask?.cancel()
        connectionState = .connecting
        activeConnectionId = peripheral.id
        scanStatusText = "Connecting to \(peripheral.name)..."
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await bluetoothService.connect(to: peripheral.id)
                guard !Task.isCancelled else { return }
                device = Device(
                    id: peripheral.id.uuidString,
                    name: peripheral.name,
                    batteryLevel: nil,
                    isCharging: false,
                    channelCount: 2,
                    generation: .gen2
                )
                connectionState = .connected
                activeConnectionId = nil
                scanStatusText = "Connected to \(peripheral.name)"
                onConnected?()
                readDeviceInfo()
            } catch {
                activeConnectionId = nil
                connectionState = .error(error.localizedDescription)
                scanStatusText = error.localizedDescription
            }
        }
    }

    func disconnect() {
        autoConnectTask?.cancel()
        connectionTask?.cancel()
        connectionState = .disconnected
        device = nil
        batteryLevel = nil
        firmwareVersion = nil
        activeConnectionId = nil
        scanStatusText = "Disconnected"
        bluetoothService.disconnect()
    }

    // MARK: - Device Info

    private func readDeviceInfo() {
        let battery = bluetoothService.batteryLevel
        let firmware = bluetoothService.firmwareVersion
        batteryLevel = battery
        firmwareVersion = firmware

        if let device {
            self.device = Device(
                id: device.id,
                name: device.name,
                firmwareVersion: firmware,
                batteryLevel: battery,
                isCharging: battery == 100,
                channelCount: device.channelCount,
                generation: device.generation,
                lastConnected: .now
            )
        }
    }

    deinit {
        scanTask?.cancel()
        autoConnectTask?.cancel()
        connectionTask?.cancel()
    }
}
