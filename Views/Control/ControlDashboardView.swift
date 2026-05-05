import SwiftUI

// MARK: - Control Dashboard View (Polished)

struct ControlDashboardView: View {
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var settingsVM: SettingsVM
    @State private var showQuickPresets = false
    @State private var showChannelDetailA = false
    @State private var showChannelDetailB = false
    @State private var showConnectionSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection status bar
                connectionStatusBar

                // Session header with live timer
                sessionHeader

                // Channel cards
                HStack(spacing: 16) {
                    channelCard(channel: controlVM.channelA, isA: true)
                    channelCard(channel: controlVM.channelB, isA: false)
                }

                // Quick waveform selector per channel
                waveformQuickSelector

                // Sync toggle
                syncToggle

                // Waveform preview
                waveformPreview

                // Quick presets
                quickPresetsRow

                // Intensity boost
                intensityBoostSlider

                // Start/Stop
                sessionControlButton
            }
            .padding()
        }
        .navigationTitle("Control")
        .sheet(isPresented: $showQuickPresets) {
            QuickPresetSheet()
        }
        .sheet(isPresented: $showChannelDetailA) {
            ChannelDetailView(channel: controlVM.channelA, isA: true)
        }
        .sheet(isPresented: $showChannelDetailB) {
            ChannelDetailView(channel: controlVM.channelB, isA: false)
        }
        .sheet(isPresented: $showConnectionSetup) {
            ConnectionSetupView()
        }
        .alert("Safety Warning", isPresented: $controlVM.showSafetyWarning) {
            Button("Continue") {
                controlVM.showSafetyWarning = false
            }
            Button("Cancel", role: .cancel) {
                // Revert strength
                controlVM.updateChannelA { $0.strength = settingsVM.safetyConfig.confirmationThreshold }
                controlVM.showSafetyWarning = false
            }
        } message: {
            Text("Strength exceeds \(Int(settingsVM.safetyConfig.confirmationThreshold))%. Are you sure?")
        }
    }

    // MARK: - Connection Status Bar

    private var connectionStatusBar: some View {
        HStack {
            Button {
                showConnectionSetup = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: settingsVM.connectionConfig.mode.icon)
                        .foregroundColor(connectionStatusColor)
                    Text(settingsVM.connectionConfig.mode.rawValue)
                        .font(.subheadline)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            Spacer()

            if let device = controlVM.presetStore.sessions.first {
                Label("\(device.durationMs / 60_000)m total", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var connectionStatusColor: Color {
        switch settingsVM.connectionConfig.mode {
        case .ble: return .green
        case .http: return .orange
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(controlVM.isSessionActive ? "Session Active" : "Ready")
                    .font(.headline)
                    .foregroundColor(controlVM.isSessionActive ? .green : .secondary)

                Text(controlVM.isSessionActive ? controlVM.sessionElapsedFormatted : "Tap start to begin")
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(controlVM.isSessionActive ? .primary : .secondary)

                if settingsVM.heartRateSafetyConfig.isEnabled {
                    Label(controlVM.heartRateSafetyState.label, systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let preset = controlVM.activePreset {
                Label(preset.name, systemImage: preset.icon)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: preset.color).opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .glassCard()
    }

    // MARK: - Channel Card

    private func channelCard(channel: ChannelState, isA: Bool) -> some View {
        VStack(spacing: 12) {
            // Header with toggle
            HStack {
                Text("Channel \(channel.id.label)")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { channel.isEnabled },
                    set: { value in
                        if isA {
                            controlVM.updateChannelA { $0.isEnabled = value }
                        } else {
                            controlVM.updateChannelB { $0.isEnabled = value }
                        }
                    }
                ))
                .tint(.green)
            }

            // Strength with large display
            VStack(spacing: 4) {
                Text("\(Int(channel.strength))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(isA ? .blue : .purple)

                Slider(value: Binding(
                    get: { channel.strength },
                    set: { controlVM.setChannelStrength(channel.id, $0) }
                ), in: 0...100)
                .tint(isA ? .blue : .purple)
            }

            // Mini waveform preview
            WaveformMiniPreview(waveform: channel.waveform, frequency: channel.frequency)
                .frame(height: 32)

            // Info row
            HStack {
                Label("\(Int(channel.frequency)) Hz", systemImage: "waveform")
                    .font(.caption)
                Spacer()
                Label("\(channel.pulseWidth)μs", systemImage: "ruler")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            // Detail button
            Button("Details") {
                if isA { showChannelDetailA = true }
                else { showChannelDetailB = true }
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding()
        .glassCard()
    }

    // MARK: - Waveform Quick Selector

    private var waveformQuickSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Waveforms")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(WaveformType.allBuiltIn) { wf in
                    Button {
                        controlVM.updateChannelA { $0.waveform = wf }
                        if !controlVM.isSynced {
                            controlVM.updateChannelB { $0.waveform = wf }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: wf.icon)
                            Text(wf.name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 64, height: 52)
                        .background(
                            controlVM.channelA.waveform.id == wf.id
                                ? Color.accentColor.opacity(0.2)
                                : Color.secondary.opacity(0.1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Sync Toggle

    private var syncToggle: some View {
        HStack {
            Image(systemName: controlVM.isSynced ? "link" : "link.break")
                .foregroundColor(controlVM.isSynced ? .green : .secondary)
            Text("Channels synced")
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { controlVM.isSynced },
                set: { _ in controlVM.toggleSync() }
            ))
            .tint(.green)
        }
        .glassCard()
    }

    // MARK: - Waveform Preview

    private var waveformPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waveform Preview")
                .font(.headline)

            WaveformPreviewView(points: controlVM.waveformPoints)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Text(controlVM.channelA.waveform.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(controlVM.channelA.frequency)) Hz")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }

    // MARK: - Quick Presets Row

    private var quickPresetsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Presets")
                    .font(.headline)
                Spacer()
                Button("All") {
                    showQuickPresets = true
                }
                .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Preset.allBuiltins) { preset in
                        Button {
                            controlVM.applyPreset(preset)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: preset.icon)
                                    .font(.title2)
                                    .foregroundColor(Color(hex: preset.color))
                                Text(preset.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 80, height: 60)
                            .background(Color(hex: preset.color).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding()
        .glassCard()
    }

    // MARK: - Intensity Boost Slider

    private var intensityBoostSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intensity Boost")
                    .font(.headline)
                Spacer()
                Text("\(controlVM.intensityBoost > 0 ? "+" : "")\(Int(controlVM.intensityBoost))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(controlVM.intensityBoost > 0 ? .red : .secondary)
            }

            Slider(value: $controlVM.intensityBoost, in: -20...20, step: 1)
                .tint(.orange)
                .onChange(of: controlVM.intensityBoost) { _, newValue in
                    controlVM.applyIntensityBoost(newValue)
                }

            HStack {
                Text("−20%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("+20%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }

    // MARK: - Session Control Button

    private var sessionControlButton: some View {
        Button {
            if controlVM.isSessionActive {
                controlVM.stopSession()
            } else {
                controlVM.startSession()
            }
        } label: {
            HStack {
                Image(systemName: controlVM.isSessionActive ? "stop.fill" : "play.fill")
                    .font(.title3)
                Text(controlVM.isSessionActive ? "Stop Session" : "Start Session")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: controlVM.isSessionActive
                        ? [.orange.opacity(0.8), .orange]
                        : [.green.opacity(0.8), .green],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .glassCard()
    }
}

// MARK: - Connection Setup View

struct ConnectionSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settingsVM: SettingsVM

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection Mode") {
                    Picker("Mode", selection: $settingsVM.connectionConfig.mode) {
                        ForEach(ConnectionMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch settingsVM.connectionConfig.mode {
                case .ble:
                    Section("Bluetooth") {
                        Toggle("Auto Connect Last Device", isOn: $settingsVM.connectionConfig.bleAutoConnect)
                        NavigationLink("Scan for Devices") {
                            DevicePairingView()
                        }
                    }
                case .http:
                    Section("HTTP / WebSocket") {
                        TextField("Server URL", text: $settingsVM.connectionConfig.httpServerURL)
                            .textInputAutocapitalization(.never)
                        TextField("API Key", text: $settingsVM.connectionConfig.httpAPIKey)
                            .textInputAutocapitalization(.never)
                        Toggle("Auto Reconnect", isOn: $settingsVM.connectionConfig.httpAutoReconnect)
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Glass Card View Modifier

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
