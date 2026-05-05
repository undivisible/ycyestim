import SwiftUI

// MARK: - Device Pairing View

struct DevicePairingView: View {
    @EnvironmentObject var deviceVM: DeviceVM
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Discovered Devices") {
                    if deviceVM.discoveredPeripherals.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Scanning for YCY devices...")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                    }

                    ForEach(deviceVM.discoveredPeripherals) { peripheral in
                        Button {
                            deviceVM.connect(to: peripheral)
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(peripheral.name)
                                        .font(.headline)
                                    Text("Signal: \(peripheral.rssi) dBm")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
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
            }
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if deviceVM.isScanning {
                        Button("Stop") {
                            deviceVM.stopScan()
                        }
                    } else {
                        Button("Scan") {
                            deviceVM.startScan()
                        }
                    }
                }
            }
            .onAppear {
                deviceVM.startScan()
            }
            .onDisappear {
                deviceVM.stopScan()
            }
        }
    }
}
