import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsVM
    @EnvironmentObject var controlVM: ControlVM
    @StateObject private var deviceVM = DeviceVM()

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Device Settings
                Section {
                    LabeledContent("Channel A Enabled") {
                        Toggle("", isOn: $settingsVM.channelAConfig.isEnabled)
                    }

                    LabeledContent("A Min Strength") {
                        Slider(value: $settingsVM.channelAConfig.minStrength, in: 0...settingsVM.channelAConfig.maxStrength)
                    }

                    LabeledContent("A Max Strength") {
                        Slider(value: $settingsVM.channelAConfig.maxStrength, in: settingsVM.channelAConfig.minStrength...100)
                    }

                    LabeledContent("A Default Strength") {
                        Slider(value: $settingsVM.channelAConfig.defaultStrength, in: settingsVM.channelAConfig.minStrength...settingsVM.channelAConfig.maxStrength)
                    }

                    Toggle("A Invert Output", isOn: $settingsVM.channelAConfig.isInverted)

                    Divider()

                    LabeledContent("Channel B Enabled") {
                        Toggle("", isOn: $settingsVM.channelBConfig.isEnabled)
                    }

                    LabeledContent("B Min Strength") {
                        Slider(value: $settingsVM.channelBConfig.minStrength, in: 0...settingsVM.channelBConfig.maxStrength)
                    }

                    LabeledContent("B Max Strength") {
                        Slider(value: $settingsVM.channelBConfig.maxStrength, in: settingsVM.channelBConfig.minStrength...100)
                    }

                    LabeledContent("B Default Strength") {
                        Slider(value: $settingsVM.channelBConfig.defaultStrength, in: settingsVM.channelBConfig.minStrength...settingsVM.channelBConfig.maxStrength)
                    }

                    Toggle("B Invert Output", isOn: $settingsVM.channelBConfig.isInverted)
                } header: {
                    Label("Device", systemImage: "cpu")
                }

                // MARK: - Connection Settings
                Section {
                    Picker("Mode", selection: $settingsVM.connectionConfig.mode) {
                        ForEach(ConnectionMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if settingsVM.connectionConfig.mode == .ble {
                        Toggle("Auto Connect Last Device", isOn: $settingsVM.connectionConfig.bleAutoConnect)
                        NavigationLink("Scan for Devices") {
                            DevicePairingView()
                        }
                    }

                    if settingsVM.connectionConfig.mode == .http {
                        TextField("Server URL", text: $settingsVM.connectionConfig.httpServerURL)
                        TextField("API Key", text: $settingsVM.connectionConfig.httpAPIKey)
                        Toggle("Auto Reconnect", isOn: $settingsVM.connectionConfig.httpAutoReconnect)
                    }
                } header: {
                    Label("Connection", systemImage: "network")
                }

                // MARK: - Safety Settings
                Section {
                    LabeledContent("Max Strength") {
                        HStack {
                            Slider(value: $settingsVM.safetyConfig.maxStrength, in: 0...100)
                            Text("\(Int(settingsVM.safetyConfig.maxStrength))%")
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }

                    LabeledContent("Session Timeout") {
                        Picker("Minutes", selection: $settingsVM.safetyConfig.sessionTimeoutMinutes) {
                            ForEach([0, 5, 10, 15, 30, 60, 90, 120], id: \.self) { min in
                                Text(min == 0 ? "None" : "\(min) min")
                            }
                        }
                    }

                    LabeledContent("Ramp Rate Limit") {
                        HStack {
                            Slider(value: $settingsVM.safetyConfig.rampRateLimit, in: 1...20, step: 0.5)
                            Text("\(settingsVM.safetyConfig.rampRateLimit, specifier: "%.1f")")
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }

                    LabeledContent("Confirm Above") {
                        HStack {
                            Slider(value: $settingsVM.safetyConfig.confirmationThreshold, in: 0...100)
                            Text("\(Int(settingsVM.safetyConfig.confirmationThreshold))%")
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }

                    Picker("Emergency Gesture", selection: $settingsVM.safetyConfig.emergencyGesture) {
                        ForEach(SafetyConfig.EmergencyGesture.allCases, id: \.self) { gesture in
                            Text(gesture.rawValue)
                        }
                    }

                    Toggle("Auto Shutdown on Disconnect", isOn: $settingsVM.safetyConfig.autoShutdownOnDisconnect)

                    Picker("Haptic Intensity", selection: $settingsVM.safetyConfig.hapticIntensity) {
                        ForEach(SafetyConfig.HapticIntensity.allCases, id: \.self) { intensity in
                            Text(intensity.rawValue)
                        }
                    }
                } header: {
                    Label("Safety", systemImage: "shield.fill")
                }
                .foregroundColor(.red)

                Section {
                    Toggle("Adaptive Heart Rate Safety", isOn: $settingsVM.heartRateSafetyConfig.isEnabled)
                    Toggle("Edge Mode", isOn: $settingsVM.edgeModeConfig.isEnabled)

                    HStack {
                        Label(controlVM.heartRateSafetyState.label, systemImage: "heart.fill")
                        Spacer()
                        Button("Authorize") {
                            Task { await controlVM.requestHeartRateAuthorization() }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let error = controlVM.heartRateAuthorizationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    LabeledContent("Baseline") {
                        Stepper("\(Int(settingsVM.heartRateSafetyConfig.baselineBPM)) BPM",
                                value: $settingsVM.heartRateSafetyConfig.baselineBPM,
                                in: 45...120,
                                step: 1)
                    }

                    LabeledContent("Elevated") {
                        Stepper("\(Int(settingsVM.heartRateSafetyConfig.elevatedBPM)) BPM",
                                value: $settingsVM.heartRateSafetyConfig.elevatedBPM,
                                in: 80...180,
                                step: 1)
                    }

                    LabeledContent("High") {
                        Stepper("\(Int(settingsVM.heartRateSafetyConfig.highBPM)) BPM",
                                value: $settingsVM.heartRateSafetyConfig.highBPM,
                                in: 90...200,
                                step: 1)
                    }

                    LabeledContent("Critical") {
                        Stepper("\(Int(settingsVM.heartRateSafetyConfig.criticalBPM)) BPM",
                                value: $settingsVM.heartRateSafetyConfig.criticalBPM,
                                in: 100...220,
                                step: 1)
                    }

                    LabeledContent("Elevated Cap") {
                        Slider(value: $settingsVM.heartRateSafetyConfig.elevatedStrengthMultiplier, in: 0.25...1, step: 0.05)
                    }

                    LabeledContent("High Cap") {
                        Slider(value: $settingsVM.heartRateSafetyConfig.highStrengthMultiplier, in: 0.1...0.75, step: 0.05)
                    }

                    Toggle("Emergency Stop at Critical", isOn: $settingsVM.heartRateSafetyConfig.emergencyStopOnCritical)

                    LabeledContent("Edge Target") {
                        Stepper("\(Int(settingsVM.edgeModeConfig.targetBPM)) BPM",
                                value: $settingsVM.edgeModeConfig.targetBPM,
                                in: 80...180,
                                step: 1)
                    }

                    LabeledContent("Edge Peak") {
                        Stepper("\(Int(settingsVM.edgeModeConfig.peakBPM)) BPM",
                                value: $settingsVM.edgeModeConfig.peakBPM,
                                in: 90...205,
                                step: 1)
                    }

                    LabeledContent("Edge Ceiling") {
                        Slider(value: $settingsVM.edgeModeConfig.maxStrength, in: settingsVM.edgeModeConfig.minStrength...80, step: 1)
                    }

                    LabeledContent("Edge Step") {
                        Slider(value: $settingsVM.edgeModeConfig.rampStep, in: 0.5...6, step: 0.5)
                    }
                } header: {
                    Label("Biometrics", systemImage: "heart.text.square.fill")
                }

                // MARK: - Program Settings
                Section {
                    Toggle("Auto Progress Between Steps", isOn: $settingsVM.programConfig.autoProgress)

                    LabeledContent("Default Loop Count") {
                        Stepper("\(settingsVM.programConfig.defaultLoopCount == 0 ? "Infinite" : String(settingsVM.programConfig.defaultLoopCount))", value: $settingsVM.programConfig.defaultLoopCount, in: 0...10)
                    }

                    LabeledContent("Transition Smoothness") {
                        HStack {
                            Slider(value: $settingsVM.programConfig.defaultTransitionSmoothness, in: 0...1)
                            Text("\(Int(settingsVM.programConfig.defaultTransitionSmoothness * 100))%")
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }

                    LabeledContent("Pause Between Steps") {
                        Picker("Seconds", selection: $settingsVM.programConfig.defaultPauseBetweenSteps) {
                            ForEach([0, 1, 2, 5, 10], id: \.self) { sec in
                                Text("\(sec)s")
                            }
                        }
                    }
                } header: {
                    Label("Programs", systemImage: "timeline.selection")
                }

                // MARK: - Appearance Settings
                Section {
                    Picker("Glass Level", selection: $settingsVM.appearanceConfig.glassLevel) {
                        ForEach(AppearanceConfig.GlassLevel.allCases, id: \.self) { level in
                            Text(level.rawValue)
                        }
                    }

                    LabeledContent("Accent Color") {
                        HStack {
                            ForEach(["#007AFF", "#BF5AF2", "#FF6B6B", "#FF9F0A", "#30D158", "#64D2FF"], id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(settingsVM.appearanceConfig.accentColor == color ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        settingsVM.appearanceConfig.accentColor = color
                                    }
                            }
                        }
                    }

                    Picker("Animation Speed", selection: $settingsVM.appearanceConfig.animationSpeed) {
                        ForEach(AppearanceConfig.AnimationSpeed.allCases, id: \.self) { speed in
                            Text(speed.rawValue)
                        }
                    }

                    Picker("Display Precision", selection: $settingsVM.appearanceConfig.displayPrecision) {
                        ForEach(AppearanceConfig.DisplayPrecision.allCases, id: \.self) { precision in
                            Text(precision.rawValue)
                        }
                    }
                } header: {
                    Label("Appearance", systemImage: "paintbrush")
                }

                // MARK: - Notification Settings
                Section {
                    Toggle("Session Start", isOn: $settingsVM.notificationConfig.sessionStart)
                    Toggle("Session Stop", isOn: $settingsVM.notificationConfig.sessionStop)
                    Toggle("Strength Threshold Alert", isOn: $settingsVM.notificationConfig.strengthThresholdAlert)
                    Toggle("Timer Warning", isOn: $settingsVM.notificationConfig.timerWarningAlert)
                    Toggle("Disconnect Alert", isOn: $settingsVM.notificationConfig.disconnectAlert)

                    if settingsVM.notificationConfig.timerWarningAlert {
                        LabeledContent("Timer Warning Before") {
                            Picker("Minutes", selection: $settingsVM.notificationConfig.timerWarningMinutes) {
                                ForEach([1, 2, 5, 10], id: \.self) { min in
                                    Text("\(min)m")
                                }
                            }
                        }
                    }
                } header: {
                    Label("Notifications", systemImage: "bell.fill")
                }

                // MARK: - About
                Section {
                    LabeledContent("Version") {
                        Text("1.0.0")
                    }
                    LabeledContent("Build") {
                        Text("1")
                    }
                    Link("YCY-YOKONEX Docs", destination: URL(string: "https://github.com/YCY-YOKONEX/YCY-YOKONEX-OpenSource")!)
                } header: {
                    Label("About", systemImage: "info.circle")
                }

                // MARK: - Reset
                Section {
                    Button("Reset All Settings", role: .destructive) {
                        settingsVM.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: settingsVM.safetyConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.connectionConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.appearanceConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.notificationConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.heartRateSafetyConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.edgeModeConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.channelAConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.channelBConfig) { settingsVM.saveAll() }
            .onChange(of: settingsVM.programConfig) { settingsVM.saveAll() }
        }
    }
}
