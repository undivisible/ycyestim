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

    enum DeviceConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    private let bluetoothService = BluetoothService()

    // MARK: - Scanning

    func startScan() {
        isScanning = true
        Task {
            await bluetoothService.startScan()
            // Update discovered peripherals periodically
            while isScanning {
                try? await Task.sleep(for: .seconds(1))
                let peripherals = await bluetoothService.peripherals
                discoveredPeripherals = peripherals
            }
        }
    }

    func stopScan() {
        isScanning = false
        Task {
            await bluetoothService.stopScan()
        }
    }

    // MARK: - Connection

    func connect(to peripheral: BLEPeripheralInfo) {
        connectionState = .connecting
        Task {
            do {
                try await bluetoothService.connect(to: peripheral.id)
                device = Device(
                    id: peripheral.id.uuidString,
                    name: peripheral.name,
                    batteryLevel: nil,
                    isCharging: false,
                    channelCount: 2,
                    generation: .gen2
                )
                connectionState = .connected
                readDeviceInfo()
            } catch {
                connectionState = .error(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        connectionState = .disconnected
        device = nil
        batteryLevel = nil
        firmwareVersion = nil
        Task {
            await bluetoothService.disconnect()
        }
    }

    // MARK: - Device Info

    private func readDeviceInfo() {
        Task {
            let battery = await bluetoothService.batteryLevel
            let firmware = await bluetoothService.firmwareVersion
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
    }

    deinit {
        stopScan()
    }
}
