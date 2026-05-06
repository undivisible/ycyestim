import SwiftUI
import UIKit

// MARK: - Device Pairing View

struct DevicePairingView: View {
    @EnvironmentObject var deviceVM: DeviceVM
    @EnvironmentObject var settingsVM: SettingsVM
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    HStack(spacing: 12) {
                        if deviceVM.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                        }
                        Text(deviceVM.scanStatusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                knownDeviceSection

                Section("New Devices") {
                    if deviceVM.device != nil {
                        HStack {
                            Spacer()
                            Text("Disconnect the current device before scanning for another one.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .padding()
                    } else if newPeripherals.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                Text(newDeviceEmptyText)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .padding()
                    }

                    ForEach(newPeripherals) { peripheral in
                        peripheralRow(peripheral)
                    }
                }

                if let device = deviceVM.device {
                    Section("Connected") {
                        LabeledContent("Name") {
                            Text(device.displayName)
                        }
                        if let fw = device.firmwareVersion {
                            LabeledContent("Firmware") {
                                Text(fw)
                            }
                        }
                        if let battery = device.batteryLevel {
                            LabeledContent("Battery") {
                                HStack {
                                    Image(systemName: device.batteryIcon)
                                    Text("\(battery)%")
                                }
                            }
                        }
                    }
                }

                if case .error(let message) = deviceVM.connectionState {
                    Section("Connection Error") {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if deviceVM.device == nil && !deviceVM.isScanning {
                        Button("Scan") {
                            startScan()
                        }
                    }
                }
            }
            .onAppear {
                if deviceVM.device == nil {
                    startScan()
                }
            }
            .onDisappear {
                deviceVM.stopScan()
            }
            .onChange(of: deviceVM.connectionState) { _, state in
                switch state {
                case .connected:
                    notify(.success)
                case .error:
                    notify(.error)
                case .connecting:
                    notify(.warning)
                case .disconnected:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private var knownDeviceSection: some View {
        if let knownPeripheral {
            Section(deviceVM.device == nil ? "Known Device" : "Connected Device") {
                peripheralRow(knownPeripheral)
            }
        } else if let name = settingsVM.connectionConfig.bleLastDeviceName {
            Section("Known Device") {
                LabeledContent("Last paired") {
                    Text(name)
                }
            }
        }
    }

    private func peripheralRow(_ peripheral: BLEPeripheralInfo) -> some View {
        Button {
            connect(peripheral)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(peripheral.name)
                        .font(.headline)
                    Text("\(peripheral.signalQuality) · \(peripheral.rssi) dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(peripheral.matchDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if deviceVM.activeConnectionId == peripheral.id {
                    ProgressView()
                        .controlSize(.small)
                } else if isConnected(peripheral) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if peripheral.hasEstimService {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .disabled(deviceVM.activeConnectionId != nil || isConnected(peripheral))
    }

    private var newPeripherals: [BLEPeripheralInfo] {
        deviceVM.discoveredPeripherals.filter { !knownDeviceIds.contains($0.id) }
    }

    private var knownPeripheral: BLEPeripheralInfo? {
        deviceVM.discoveredPeripherals.first { knownDeviceIds.contains($0.id) }
    }

    private var knownDeviceIds: Set<UUID> {
        var ids = Set<UUID>()
        if let id = deviceVM.device.flatMap({ UUID(uuidString: $0.id) }) {
            ids.insert(id)
        }
        if let id = settingsVM.connectionConfig.bleLastDeviceId.flatMap(UUID.init(uuidString:)) {
            ids.insert(id)
        }
        return ids
    }

    private var newDeviceEmptyText: String {
        if deviceVM.isScanning {
            return "Scanning for new YCY devices..."
        }
        if !knownDeviceIds.isEmpty {
            return "No new devices found. Your known device is kept separate."
        }
        return "No new YCY devices found."
    }

    private func isConnected(_ peripheral: BLEPeripheralInfo) -> Bool {
        deviceVM.device?.id == peripheral.id.uuidString
    }

    private var statusIcon: String {
        switch deviceVM.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .error: return "exclamationmark.triangle.fill"
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var statusColor: Color {
        switch deviceVM.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private func startScan() {
        notify(.warning)
        deviceVM.startScan()
    }

    private func connect(_ peripheral: BLEPeripheralInfo) {
        notify(.warning)
        deviceVM.connect(to: peripheral) {
            settingsVM.connectionConfig.bleLastDeviceId = peripheral.id.uuidString
            settingsVM.connectionConfig.bleLastDeviceName = peripheral.name
            settingsVM.saveAll()
            dismiss()
        }
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
