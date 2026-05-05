import SwiftUI

// MARK: - Control Dashboard View (Polished)

struct ControlDashboardView: View {
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var settingsVM: SettingsVM
    @State private var showQuickPresets = false
    @State private var showChannelDetailA = false
    @State private var showChannelDetailB = false
    @State private var showConnectionSetup = false
    @State private var showSyncedChannelDetail = false
    @State private var showWaveformSettings = false
    @State private var showIntensitySettings = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                connectionStatusBar
                sessionHeader
                if controlVM.isSynced {
                    syncedChannelCard
                } else {
                    HStack(spacing: 10) {
                        channelCard(channel: controlVM.channelA, isA: true)
                        channelCard(channel: controlVM.channelB, isA: false)
                    }
                }
                settingsRows
                waveformPreview
                quickPresetsRow
                sessionControlButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("Control")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showSyncedChannelDetail) {
            SyncedChannelDetailView()
        }
        .sheet(isPresented: $showWaveformSettings) {
            WaveformSettingsSheet()
        }
        .sheet(isPresented: $showIntensitySettings) {
            IntensitySettingsSheet()
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
        .padding(12)
        .glassCard()
    }

    // MARK: - Channel Card

    private func channelCard(channel: ChannelState, isA: Bool) -> some View {
        VStack(spacing: 8) {
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(isA ? .blue : .purple)

                Slider(value: Binding(
                    get: { channel.strength },
                    set: { controlVM.setChannelStrength(channel.id, $0) }
                ), in: 0...100)
                .tint(isA ? .blue : .purple)
            }

            // Mini waveform preview
            WaveformMiniPreview(waveform: channel.waveform, frequency: channel.frequency)
                .frame(height: 24)

            // Info row
            HStack {
                Label("\(Int(channel.frequency)) Hz", systemImage: "waveform")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Label("\(channel.pulseWidth)μs", systemImage: "ruler")
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)

            // Detail button
            Button("Details") {
                if isA { showChannelDetailA = true }
                else { showChannelDetailB = true }
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .glassCard()
    }

    private var syncedChannelCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Channels A+B")
                        .font(.headline)
                    Text("Synced output")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { controlVM.channelA.isEnabled || controlVM.channelB.isEnabled },
                    set: { enabled in
                        controlVM.updateChannelA { $0.isEnabled = enabled }
                        controlVM.updateChannelB { $0.isEnabled = enabled }
                    }
                ))
                .tint(.green)
            }

            HStack(alignment: .center, spacing: 14) {
                Text("\(Int(controlVM.channelA.strength))%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .frame(width: 88, alignment: .leading)

                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { controlVM.channelA.strength },
                        set: { controlVM.setChannelStrength(.a, $0) }
                    ), in: 0...100)

                    HStack {
                        Label(controlVM.channelA.waveform.name, systemImage: controlVM.channelA.waveform.icon)
                        Spacer()
                        Text("\(Int(controlVM.channelA.frequency)) Hz")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Button {
                showSyncedChannelDetail = true
            } label: {
                Label("Channel Settings", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding(12)
        .glassCard()
    }

    // MARK: - Waveform Quick Selector

    private var settingsRows: some View {
        VStack(spacing: 0) {
            settingButton(
                title: "Waveforms",
                value: controlVM.channelA.waveform.name,
                icon: "waveform",
                action: { showWaveformSettings = true }
            )
            Divider().padding(.leading, 36)
            settingButton(
                title: "Intensity",
                value: "\(controlVM.intensityBoost > 0 ? "+" : "")\(Int(controlVM.intensityBoost))%",
                icon: "slider.horizontal.3",
                action: { showIntensitySettings = true }
            )
            Divider().padding(.leading, 36)
            HStack {
                Image(systemName: controlVM.isSynced ? "link" : "xmark.circle")
                    .foregroundColor(controlVM.isSynced ? .green : .secondary)
                    .frame(width: 24)
                Text("Sync A+B")
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { controlVM.isSynced },
                    set: { _ in controlVM.toggleSync() }
                ))
                .tint(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .glassCard()
    }

    private func settingButton(title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Waveform Preview

    private var waveformPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waveform Preview")
                .font(.headline)

            WaveformPreviewView(points: controlVM.waveformPoints)
                .frame(height: 72)
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
                            .frame(width: 72, height: 56)
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

// MARK: - Waveform Settings

private enum WaveformTarget: String, CaseIterable, Identifiable {
    case both = "A+B"
    case channelA = "A"
    case channelB = "B"

    var id: String { rawValue }
}

struct WaveformSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM
    @State private var target: WaveformTarget = .both

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !controlVM.isSynced {
                        Picker("Channel", selection: $target) {
                            ForEach(WaveformTarget.allCases) { target in
                                Text(target.rawValue).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(WaveformType.allBuiltIn) { waveform in
                            Button {
                                apply(waveform)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: waveform.icon)
                                        .font(.title2)
                                    Text(waveform.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    WaveformMiniPreview(waveform: waveform, frequency: controlVM.channelA.frequency)
                                        .frame(height: 22)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected(waveform) ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Waveforms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func apply(_ waveform: WaveformType) {
        let resolvedTarget: WaveformTarget = controlVM.isSynced ? .both : target
        switch resolvedTarget {
        case .both:
            controlVM.updateChannelA { $0.waveform = waveform }
            controlVM.updateChannelB { $0.waveform = waveform }
        case .channelA:
            controlVM.updateChannelA { $0.waveform = waveform }
        case .channelB:
            controlVM.updateChannelB { $0.waveform = waveform }
        }
    }

    private func isSelected(_ waveform: WaveformType) -> Bool {
        let resolvedTarget: WaveformTarget = controlVM.isSynced ? .both : target
        switch resolvedTarget {
        case .both:
            return controlVM.channelA.waveform == waveform && controlVM.channelB.waveform == waveform
        case .channelA:
            return controlVM.channelA.waveform == waveform
        case .channelB:
            return controlVM.channelB.waveform == waveform
        }
    }
}

// MARK: - Intensity Settings

struct IntensitySettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM

    var body: some View {
        NavigationStack {
            Form {
                Section("Boost") {
                    HStack {
                        Text("Output")
                        Spacer()
                        Text("\(controlVM.intensityBoost > 0 ? "+" : "")\(Int(controlVM.intensityBoost))%")
                            .monospacedDigit()
                            .foregroundColor(controlVM.intensityBoost > 0 ? .red : .secondary)
                    }

                    Slider(value: $controlVM.intensityBoost, in: -20...20, step: 1)
                        .tint(.orange)
                        .onChange(of: controlVM.intensityBoost) { _, newValue in
                            controlVM.applyIntensityBoost(newValue)
                        }

                    Button("Reset Boost") {
                        controlVM.applyIntensityBoost(0)
                    }
                }
            }
            .navigationTitle("Intensity")
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

// MARK: - Synced Channel Detail

struct SyncedChannelDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM

    var body: some View {
        NavigationStack {
            Form {
                Section("Channels A+B") {
                    Toggle("Enabled", isOn: Binding(
                        get: { controlVM.channelA.isEnabled || controlVM.channelB.isEnabled },
                        set: { enabled in
                            updateBoth { $0.isEnabled = enabled }
                        }
                    ))

                    LabeledContent("Strength") {
                        Text("\(Int(controlVM.channelA.strength))%")
                            .monospacedDigit()
                    }
                    Slider(value: syncedDouble(\.strength), in: 0...100)
                }

                Section("Signal") {
                    Picker("Waveform", selection: syncedWaveform) {
                        ForEach(WaveformType.allBuiltIn) { waveform in
                            Label(waveform.name, systemImage: waveform.icon).tag(waveform)
                        }
                    }

                    LabeledContent("Frequency") {
                        Text("\(Int(controlVM.channelA.frequency)) Hz")
                            .monospacedDigit()
                    }
                    Slider(value: syncedDouble(\.frequency), in: 1...50)

                    LabeledContent("Pulse Width") {
                        Text("\(controlVM.channelA.pulseWidth) us")
                            .monospacedDigit()
                    }
                    Slider(value: syncedPulseWidth, in: 50...1000, step: 10)

                    LabeledContent("Phase") {
                        Text("\(Int(controlVM.channelA.phaseOffset)) deg")
                            .monospacedDigit()
                    }
                    Slider(value: syncedDouble(\.phaseOffset), in: 0...360)
                }

                Section("Timing") {
                    Picker("Duration", selection: syncedDuration) {
                        Text("Continuous").tag(0)
                        Text("10s").tag(10_000)
                        Text("30s").tag(30_000)
                        Text("1 min").tag(60_000)
                        Text("2 min").tag(120_000)
                        Text("5 min").tag(300_000)
                        Text("10 min").tag(600_000)
                    }
                    Toggle("Invert Output", isOn: syncedBool(\.isInverted))
                }
            }
            .navigationTitle("Channels A+B")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var syncedWaveform: Binding<WaveformType> {
        Binding(
            get: { controlVM.channelA.waveform },
            set: { waveform in updateBoth { $0.waveform = waveform } }
        )
    }

    private var syncedPulseWidth: Binding<Double> {
        Binding(
            get: { Double(controlVM.channelA.pulseWidth) },
            set: { value in updateBoth { $0.pulseWidth = Int(value) } }
        )
    }

    private var syncedDuration: Binding<Int> {
        Binding(
            get: { controlVM.channelA.durationMs },
            set: { value in updateBoth { $0.durationMs = value } }
        )
    }

    private func syncedDouble(_ keyPath: WritableKeyPath<ChannelState, Double>) -> Binding<Double> {
        Binding(
            get: { controlVM.channelA[keyPath: keyPath] },
            set: { value in updateBoth { $0[keyPath: keyPath] = value } }
        )
    }

    private func syncedBool(_ keyPath: WritableKeyPath<ChannelState, Bool>) -> Binding<Bool> {
        Binding(
            get: { controlVM.channelA[keyPath: keyPath] },
            set: { value in updateBoth { $0[keyPath: keyPath] = value } }
        )
    }

    private func updateBoth(_ block: @escaping (inout ChannelState) -> Void) {
        controlVM.updateChannelA(block)
        controlVM.updateChannelB(block)
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
