import SwiftUI

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
    @State private var showEdgeSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                modeSwitch
                outputConsole
                controlTiles
                waveformStage
                presetRail
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showQuickPresets) {
            QuickPresetSheet()
        }
        .sheet(isPresented: $showChannelDetailA) {
            ChannelDetailView(isA: true)
        }
        .sheet(isPresented: $showChannelDetailB) {
            ChannelDetailView(isA: false)
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
        .sheet(isPresented: $showEdgeSettings) {
            EdgeModeSettingsSheet()
        }
        .alert("Safety Warning", isPresented: $controlVM.showSafetyWarning) {
            Button("Continue") {
                controlVM.showSafetyWarning = false
            }
            Button("Cancel", role: .cancel) {
                controlVM.updateChannelA { $0.strength = settingsVM.safetyConfig.confirmationThreshold }
                controlVM.showSafetyWarning = false
            }
        } message: {
            Text("Strength exceeds \(Int(settingsVM.safetyConfig.confirmationThreshold))%. Are you sure?")
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 8) {
            modeButton(title: "Manual", icon: "slider.horizontal.3", isActive: !settingsVM.edgeModeConfig.isEnabled) {
                setEdgeMode(false)
            }
            modeButton(title: "Edge", icon: "heart.circle.fill", isActive: settingsVM.edgeModeConfig.isEnabled) {
                setEdgeMode(true)
            }
            Button {
                showEdgeSettings = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    private func modeButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundColor(isActive ? .white : .primary)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var outputConsole: some View {
        VStack(spacing: 12) {
            HStack {
                Text(controlVM.isSynced ? "Channels A+B" : "Channels")
                    .font(.headline)
                Spacer()
                Toggle("Sync", isOn: Binding(
                    get: { controlVM.isSynced },
                    set: { _ in controlVM.toggleSync() }
                ))
                .font(.caption)
                .toggleStyle(.switch)
                .tint(.green)
            }

            if controlVM.isSynced {
                OutputMeterRow(
                    title: "A+B",
                    color: .accentColor,
                    channel: controlVM.channelA,
                    strength: Binding(
                        get: { controlVM.channelA.strength },
                        set: { controlVM.setChannelStrength(.a, $0) }
                    ),
                    enabled: Binding(
                        get: { controlVM.channelA.isEnabled || controlVM.channelB.isEnabled },
                        set: { enabled in
                            controlVM.updateChannelA { $0.isEnabled = enabled }
                            controlVM.updateChannelB { $0.isEnabled = enabled }
                        }
                    ),
                    onDetails: { showSyncedChannelDetail = true }
                )
            } else {
                OutputMeterRow(
                    title: "A",
                    color: .blue,
                    channel: controlVM.channelA,
                    strength: Binding(
                        get: { controlVM.channelA.strength },
                        set: { controlVM.setChannelStrength(.a, $0) }
                    ),
                    enabled: Binding(
                        get: { controlVM.channelA.isEnabled },
                        set: { enabled in controlVM.updateChannelA { $0.isEnabled = enabled } }
                    ),
                    onDetails: { showChannelDetailA = true }
                )
                OutputMeterRow(
                    title: "B",
                    color: .purple,
                    channel: controlVM.channelB,
                    strength: Binding(
                        get: { controlVM.channelB.strength },
                        set: { controlVM.setChannelStrength(.b, $0) }
                    ),
                    enabled: Binding(
                        get: { controlVM.channelB.isEnabled },
                        set: { enabled in controlVM.updateChannelB { $0.isEnabled = enabled } }
                    ),
                    onDetails: { showChannelDetailB = true }
                )
            }
        }
        .padding(14)
        .glassCard()
    }

    private var controlTiles: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            dashboardTile("Signal", value: controlVM.channelA.waveform.name, icon: "waveform") {
                showWaveformSettings = true
            }
            dashboardTile("Boost", value: boostText, icon: "bolt.circle") {
                showIntensitySettings = true
            }
            biometricTile
            dashboardTile("Device", value: settingsVM.connectionConfig.mode.rawValue, icon: settingsVM.connectionConfig.mode.icon) {
                showConnectionSetup = true
            }
        }
    }

    private func dashboardTile(_ title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 28, height: 28)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var biometricTile: some View {
        Button {
            showEdgeSettings = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: heartRateProgress)
                        .stroke(edgeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: biometricIcon)
                        .font(.caption.weight(.bold))
                        .foregroundColor(edgeColor)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Biometrics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(heartRateText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(biometricTileValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var waveformStage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(controlVM.channelA.waveform.name, systemImage: controlVM.channelA.waveform.icon)
                    .font(.headline)
                Spacer()
                Text("\(Int(controlVM.channelA.frequency)) Hz")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            WaveformPreviewView(points: controlVM.waveformPoints)
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .glassCard()
    }

    private var presetRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                Button("All") {
                    showQuickPresets = true
                }
                .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Preset.allBuiltins.prefix(10)) { preset in
                        Button {
                            controlVM.applyPreset(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: preset.icon)
                                    .font(.title3)
                                    .foregroundColor(Color(hex: preset.color))
                                Text(preset.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text("\(Int(preset.channelA.strength))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 92, height: 82, alignment: .leading)
                            .padding(10)
                            .background(Color(hex: preset.color).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    private var heartRateText: String {
        guard let bpm = controlVM.heartRateDisplayBPM else { return "-- BPM" }
        return "\(Int(bpm)) BPM"
    }

    private var heartRateProgress: Double {
        guard controlVM.isHeartRateLive, let bpm = controlVM.heartRateDisplayBPM else { return 0 }
        let minBPM = 60.0
        let maxBPM = max(settingsVM.edgeModeConfig.peakBPM, 150)
        return max(0.05, min(1, (bpm - minBPM) / (maxBPM - minBPM)))
    }

    private var edgeColor: Color {
        guard controlVM.isHeartRateLive else {
            return .secondary
        }

        switch controlVM.edgeModeState {
        case .inactive, .armed:
            return settingsVM.edgeModeConfig.isEnabled ? .accentColor : .secondary
        case .building:
            return .green
        case .holding:
            return .orange
        case .easing:
            return .red
        }
    }

    private var biometricIcon: String {
        guard controlVM.isHeartRateLive else { return "heart.slash" }
        return settingsVM.edgeModeConfig.isEnabled ? controlVM.edgeModeState.icon : "heart"
    }

    private var biometricTileValue: String {
        if settingsVM.edgeModeConfig.isEnabled, controlVM.isHeartRateLive {
            return controlVM.edgeModeState.label
        }
        return controlVM.heartRateSourceLabel
    }

    private var boostText: String {
        "\(controlVM.intensityBoost > 0 ? "+" : "")\(Int(controlVM.intensityBoost))%"
    }

    private func setEdgeMode(_ enabled: Bool) {
        settingsVM.edgeModeConfig.isEnabled = enabled
        settingsVM.saveAll()
        if enabled {
            Task { await controlVM.requestHeartRateAuthorization() }
        }
    }
}

private struct OutputMeterRow: View {
    let title: String
    let color: Color
    let channel: ChannelState
    @Binding var strength: Double
    @Binding var enabled: Bool
    let onDetails: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                Text("\(Int(strength))%")
                    .font(.title3.monospacedDigit().weight(.bold))
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(.green)
            }

            Slider(value: $strength, in: 0...100)
                .tint(color)

            HStack {
                Label(channel.waveform.name, systemImage: channel.waveform.icon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Label(padSummary, systemImage: channel.placement.icon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("\(Int(channel.frequency)) Hz")
                Button(action: onDetails) {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var padSummary: String {
        if channel.pad1Placement == channel.pad2Placement {
            return channel.pad1Placement.rawValue
        }
        return "\(channel.pad1Placement.rawValue) + \(channel.pad2Placement.rawValue)"
    }
}

struct EdgeModeSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var settingsVM: SettingsVM

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Toggle("Edge Mode", isOn: Binding(
                        get: { settingsVM.edgeModeConfig.isEnabled },
                        set: { enabled in
                            settingsVM.edgeModeConfig.isEnabled = enabled
                            settingsVM.saveAll()
                            if enabled {
                                Task { await controlVM.requestHeartRateAuthorization() }
                            }
                        }
                    ))

                    Label(controlVM.edgeModeState.label, systemImage: controlVM.edgeModeState.icon)
                        .foregroundColor(.secondary)

                    LabeledContent("HealthKit") {
                        Text(authorizationStatusLabel)
                            .foregroundColor(.secondary)
                    }

                    if let error = controlVM.heartRateAuthorizationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Heart Rate") {
                    LabeledContent("Recovery") {
                        Stepper("\(Int(settingsVM.edgeModeConfig.recoveryBPM)) BPM",
                                value: edgeDouble(\.recoveryBPM),
                                in: 60...140,
                                step: 1)
                    }
                    LabeledContent("Target") {
                        Stepper("\(Int(settingsVM.edgeModeConfig.targetBPM)) BPM",
                                value: edgeDouble(\.targetBPM),
                                in: 80...180,
                                step: 1)
                    }
                    LabeledContent("Peak") {
                        Stepper("\(Int(settingsVM.edgeModeConfig.peakBPM)) BPM",
                                value: edgeDouble(\.peakBPM),
                                in: 90...205,
                                step: 1)
                    }
                }

                Section("Output Bounds") {
                    LabeledContent("Floor") {
                        Text("\(Int(settingsVM.edgeModeConfig.minStrength))%")
                            .monospacedDigit()
                    }
                    Slider(value: edgeDouble(\.minStrength), in: 0...settingsVM.edgeModeConfig.maxStrength, step: 1)

                    LabeledContent("Ceiling") {
                        Text("\(Int(settingsVM.edgeModeConfig.maxStrength))%")
                            .monospacedDigit()
                    }
                    Slider(value: edgeDouble(\.maxStrength), in: settingsVM.edgeModeConfig.minStrength...100, step: 1)

                    LabeledContent("Step") {
                        Text("\(settingsVM.edgeModeConfig.rampStep, specifier: "%.1f")%")
                            .monospacedDigit()
                    }
                    Slider(value: edgeDouble(\.rampStep), in: 0.5...6, step: 0.5)
                }

                Section("Automation") {
                    Toggle("Adjust Strength", isOn: edgeBool(\.adjustsStrength))
                    Toggle("Adjust Frequency", isOn: edgeBool(\.adjustsFrequency))
                    Toggle("Adjust Waveform", isOn: edgeBool(\.adjustsWaveform))

                    LabeledContent("Frequency Floor") {
                        Text("\(Int(settingsVM.edgeModeConfig.frequencyFloor)) Hz")
                            .monospacedDigit()
                    }
                    Slider(value: edgeDouble(\.frequencyFloor), in: 1...settingsVM.edgeModeConfig.frequencyCeiling, step: 1)

                    LabeledContent("Frequency Ceiling") {
                        Text("\(Int(settingsVM.edgeModeConfig.frequencyCeiling)) Hz")
                            .monospacedDigit()
                    }
                    Slider(value: edgeDouble(\.frequencyCeiling), in: settingsVM.edgeModeConfig.frequencyFloor...50, step: 1)

                    Picker("Building Waveform", selection: edgeWaveform(\.buildingWaveform)) {
                        ForEach(WaveformType.allBuiltIn) { waveform in
                            Label(waveform.name, systemImage: waveform.icon).tag(waveform)
                        }
                    }

                    Picker("Holding Waveform", selection: edgeWaveform(\.holdingWaveform)) {
                        ForEach(WaveformType.allBuiltIn) { waveform in
                            Label(waveform.name, systemImage: waveform.icon).tag(waveform)
                        }
                    }

                    Picker("Easing Waveform", selection: edgeWaveform(\.easingWaveform)) {
                        ForEach(WaveformType.allBuiltIn) { waveform in
                            Label(waveform.name, systemImage: waveform.icon).tag(waveform)
                        }
                    }
                }
            }
            .navigationTitle("Edge Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func edgeDouble(_ keyPath: WritableKeyPath<EdgeModeConfig, Double>) -> Binding<Double> {
        Binding(
            get: { settingsVM.edgeModeConfig[keyPath: keyPath] },
            set: { value in
                settingsVM.edgeModeConfig[keyPath: keyPath] = value
                settingsVM.saveAll()
            }
        )
    }

    private func edgeBool(_ keyPath: WritableKeyPath<EdgeModeConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsVM.edgeModeConfig[keyPath: keyPath] },
            set: { value in
                settingsVM.edgeModeConfig[keyPath: keyPath] = value
                settingsVM.saveAll()
            }
        )
    }

    private func edgeWaveform(_ keyPath: WritableKeyPath<EdgeModeConfig, WaveformType>) -> Binding<WaveformType> {
        Binding(
            get: { settingsVM.edgeModeConfig[keyPath: keyPath] },
            set: { value in
                settingsVM.edgeModeConfig[keyPath: keyPath] = value
                settingsVM.saveAll()
            }
        )
    }

    private var authorizationStatusLabel: String {
        switch controlVM.heartRateAuthorizationStatus {
        case .unavailable:
            return "Unavailable"
        case .unknown:
            return "Unknown"
        case .shouldRequest:
            return "Needs Request"
        case .unnecessary:
            return "Already Checked"
        }
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
    @State private var previewWaveform: WaveformType = .pulse(count: .single)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    waveformPreviewPanel

                    if !controlVM.isSynced {
                        Picker("Channel", selection: $target) {
                            ForEach(WaveformTarget.allCases) { target in
                                Text(target.rawValue).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    waveformPickerGrid
                    signalControls
                }
                .padding()
            }
            .navigationTitle("Wave Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                previewWaveform = selectedWaveform
            }
            .onChange(of: target) {
                previewWaveform = selectedWaveform
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var waveformPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(previewWaveform.name, systemImage: previewWaveform.icon)
                    .font(.headline)
                Spacer()
                Text(target.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            WaveformMiniPreview(waveform: previewWaveform, frequency: previewFrequency)
                .frame(height: 108)
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                signalChip("\(Int(previewFrequency)) Hz", icon: "waveform")
                signalChip("\(selectedChannel.pulseWidth) us", icon: "ruler")
                signalChip("\(Int(selectedChannel.phaseOffset)) deg", icon: "circle")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var waveformPickerGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Waveform")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(WaveformType.allBuiltIn) { waveform in
                    Button {
                        apply(waveform)
                        previewWaveform = waveform
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: waveform.icon)
                                    .foregroundColor(isSelected(waveform) ? .accentColor : .secondary)
                                Text(waveform.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                                if isSelected(waveform) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }

                            WaveformMiniPreview(waveform: waveform, frequency: previewFrequency)
                                .frame(height: 48)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                        .background(isSelected(waveform) ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var signalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signal")
                .font(.headline)

            signalSlider(
                title: "Frequency",
                value: signalDouble(\.frequency),
                range: 1...50,
                step: 1,
                valueText: "\(Int(selectedChannel.frequency)) Hz"
            )

            signalSlider(
                title: "Pulse Width",
                value: pulseWidthBinding,
                range: 0...100,
                step: 1,
                valueText: "\(selectedChannel.pulseWidth) us"
            )

            signalSlider(
                title: "Phase",
                value: signalDouble(\.phaseOffset),
                range: 0...360,
                step: 5,
                valueText: "\(Int(selectedChannel.phaseOffset)) deg"
            )

            Picker("Duration", selection: durationBinding) {
                Text("Continuous").tag(0)
                Text("10s").tag(10_000)
                Text("30s").tag(30_000)
                Text("1 min").tag(60_000)
                Text("2 min").tag(120_000)
                Text("5 min").tag(300_000)
            }
            .pickerStyle(.menu)

            Toggle("Invert Output", isOn: signalBool(\.isInverted))
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func signalChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func signalSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)

            Slider(value: value, in: range, step: step)
        }
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

    private func updateTarget(_ block: @escaping (inout ChannelState) -> Void) {
        let resolvedTarget: WaveformTarget = controlVM.isSynced ? .both : target
        switch resolvedTarget {
        case .both:
            controlVM.updateChannelA(block)
            controlVM.updateChannelB(block)
        case .channelA:
            controlVM.updateChannelA(block)
        case .channelB:
            controlVM.updateChannelB(block)
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

    private var selectedWaveform: WaveformType {
        let resolvedTarget: WaveformTarget = controlVM.isSynced ? .both : target
        switch resolvedTarget {
        case .both, .channelA:
            return controlVM.channelA.waveform
        case .channelB:
            return controlVM.channelB.waveform
        }
    }

    private var selectedChannel: ChannelState {
        let resolvedTarget: WaveformTarget = controlVM.isSynced ? .both : target
        switch resolvedTarget {
        case .both, .channelA:
            return controlVM.channelA
        case .channelB:
            return controlVM.channelB
        }
    }

    private var previewFrequency: Double {
        let resolvedTarget: WaveformTarget = controlVM.isSynced ? .both : target
        switch resolvedTarget {
        case .both, .channelA:
            return controlVM.channelA.frequency
        case .channelB:
            return controlVM.channelB.frequency
        }
    }

    private func signalDouble(_ keyPath: WritableKeyPath<ChannelState, Double>) -> Binding<Double> {
        Binding(
            get: { selectedChannel[keyPath: keyPath] },
            set: { value in
                updateTarget { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func signalBool(_ keyPath: WritableKeyPath<ChannelState, Bool>) -> Binding<Bool> {
        Binding(
            get: { selectedChannel[keyPath: keyPath] },
            set: { value in
                updateTarget { $0[keyPath: keyPath] = value }
            }
        )
    }

    private var pulseWidthBinding: Binding<Double> {
        Binding(
            get: { Double(selectedChannel.pulseWidth) },
            set: { value in
                updateTarget { $0.pulseWidth = Int(value) }
            }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { selectedChannel.durationMs },
            set: { value in
                updateTarget { $0.durationMs = value }
            }
        )
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
                    Slider(value: syncedPulseWidth, in: 0...100, step: 1)

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

                Section("Pad Locations") {
                    Picker("A Pad 1", selection: channelAPad1Placement) {
                        ForEach(PadPlacement.allCases) { placement in
                            Label(placement.rawValue, systemImage: placement.icon).tag(placement)
                        }
                    }
                    Picker("A Pad 2", selection: channelAPad2Placement) {
                        ForEach(PadPlacement.allCases) { placement in
                            Label(placement.rawValue, systemImage: placement.icon).tag(placement)
                        }
                    }
                    Picker("B Pad 1", selection: channelBPad1Placement) {
                        ForEach(PadPlacement.allCases) { placement in
                            Label(placement.rawValue, systemImage: placement.icon).tag(placement)
                        }
                    }
                    Picker("B Pad 2", selection: channelBPad2Placement) {
                        ForEach(PadPlacement.allCases) { placement in
                            Label(placement.rawValue, systemImage: placement.icon).tag(placement)
                        }
                    }
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

    private var channelAPad1Placement: Binding<PadPlacement> {
        Binding(
            get: { controlVM.channelA.pad1Placement },
            set: { placement in controlVM.updateChannelA { $0.pad1Placement = placement } }
        )
    }

    private var channelAPad2Placement: Binding<PadPlacement> {
        Binding(
            get: { controlVM.channelA.pad2Placement },
            set: { placement in controlVM.updateChannelA { $0.pad2Placement = placement } }
        )
    }

    private var channelBPad1Placement: Binding<PadPlacement> {
        Binding(
            get: { controlVM.channelB.pad1Placement },
            set: { placement in controlVM.updateChannelB { $0.pad1Placement = placement } }
        )
    }

    private var channelBPad2Placement: Binding<PadPlacement> {
        Binding(
            get: { controlVM.channelB.pad2Placement },
            set: { placement in controlVM.updateChannelB { $0.pad2Placement = placement } }
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
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var deviceVM: DeviceVM

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
                        Picker("Device Generation", selection: $settingsVM.connectionConfig.bleProtocolVersion) {
                            ForEach(BLEProtocolVersion.allCases) { version in
                                Text(version.rawValue).tag(version)
                            }
                        }
                        Picker("Output Mode", selection: $settingsVM.connectionConfig.bleOutputMode) {
                            ForEach(BLEOutputMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Toggle("Auto Connect Last Device", isOn: $settingsVM.connectionConfig.bleAutoConnect)
                        if let device = deviceVM.device {
                            LabeledContent("Connected Device") {
                                Text(device.displayName)
                            }
                            if let battery = deviceVM.batteryLevel {
                                LabeledContent("Battery") {
                                    Text("\(battery)%")
                                }
                            }
                            if let firmware = deviceVM.firmwareVersion {
                                LabeledContent("Firmware") {
                                    Text(firmware)
                                }
                            }
                            Button(role: .destructive) {
                                controlVM.disconnect()
                                deviceVM.disconnect()
                            } label: {
                                Label("Disconnect Device", systemImage: "antenna.radiowaves.left.and.right.slash")
                            }
                        } else {
                            NavigationLink("Scan for Devices") {
                                DevicePairingView()
                            }
                        }
                    }
                case .http:
                    Section("HTTP / WebSocket") {
                        TextField("Server URL", text: $settingsVM.connectionConfig.httpServerURL)
                            .textInputAutocapitalization(.never)
                        TextField("API Key", text: $settingsVM.connectionConfig.httpAPIKey)
                            .textInputAutocapitalization(.never)
                        TextField("Command ID", text: $settingsVM.connectionConfig.httpCommandID)
                            .textInputAutocapitalization(.never)
                        TextField("Stop ID", text: $settingsVM.connectionConfig.httpStopCommandID)
                            .textInputAutocapitalization(.never)
                        Toggle("Auto Reconnect", isOn: $settingsVM.connectionConfig.httpAutoReconnect)
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settingsVM.connectionConfig) { settingsVM.saveAll() }
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
