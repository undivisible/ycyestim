import SwiftUI

// MARK: - Session Live View (immersive full-screen during active session)

struct SessionLiveView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var settingsVM: SettingsVM
    @State private var showEmergencyConfirm = false
    @State private var showQuickPresets = false
    @State private var showQuickActions = false

    var body: some View {
        ZStack {
            // Dynamic background based on session state
            sessionBackground

            VStack(spacing: 0) {
                // Top status bar
                topStatusBar

                // Channel A meter
                channelLiveMeter(
                    channel: controlVM.channelA,
                    label: "Channel A",
                    color: .blue,
                    isA: true
                )

                // Channel B meter (if not synced or visible)
                if !controlVM.isSynced {
                    channelLiveMeter(
                        channel: controlVM.channelB,
                        label: "Channel B",
                        color: .purple,
                        isA: false
                    )
                }

                // Active waveform visualization
                liveWaveformVisualization

                // Active program info
                if let program = controlVM.activeProgram {
                    activeProgramInfo(program)
                }

                // Quick action buttons
                quickActionsRow

                Spacer()

                // Bottom controls
                bottomControls
            }
            .padding()
        }
        .ignoresSafeArea()
        .confirmationDialog("Emergency Stop", isPresented: $showEmergencyConfirm, titleVisibility: .visible) {
            Button("Confirm Emergency Stop", role: .destructive) {
                Task { try? await controlVM.emergencyStop() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will immediately cut all output to all channels.")
        }
        .fullScreenCover(isPresented: $controlVM.isEmergencyStopped) {
            EmergencyStoppedOverlay()
        }
        .sheet(isPresented: $showQuickPresets) {
            QuickPresetSheet()
        }
        .sheet(isPresented: $showQuickActions) {
            QuickActionsSheet()
        }
    }

    // MARK: - Background

    private var sessionBackground: some View {
        LinearGradient(
            colors: controlVM.isPaused
                ? [Color(hex: "#1A1A2E"), Color(hex: "#16213E")]
                : [Color(hex: "#0A0A1A"), Color(hex: "#1A0A2E")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Top Status Bar

    private var topStatusBar: some View {
        HStack {
            // Timer
            HStack(spacing: 6) {
                Image(systemName: controlVM.isPaused ? "pause.fill" : "timer")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(controlVM.sessionElapsedFormatted)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            // Preset badge
            if let preset = controlVM.activePreset {
                Label(preset.name, systemImage: preset.icon)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: preset.color).opacity(0.3))
                    .clipShape(Capsule())
            }

            Spacer()

            if settingsVM.edgeModeConfig.isEnabled {
                Label(controlVM.edgeModeState.label, systemImage: controlVM.edgeModeState.icon)
                    .font(.caption)
                    .foregroundColor(heartRateColor)
            } else if settingsVM.heartRateSafetyConfig.isEnabled {
                Label(controlVM.heartRateSafetyState.label, systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundColor(heartRateColor)
            }

            Spacer()

            // Connection mode
            Image(systemName: settingsVM.connectionConfig.mode.icon)
                .font(.subheadline)
                .foregroundColor(.green)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var heartRateColor: Color {
        switch controlVM.heartRateSafetyState {
        case .critical:
            return .red
        case .high:
            return .orange
        case .elevated:
            return .yellow
        case .monitoring:
            return .green
        case .inactive, .unavailable, .needsAuthorization:
            return .secondary
        }
    }

    // MARK: - Channel Live Meter

    private func channelLiveMeter(
        channel: ChannelState,
        label: String,
        color: Color,
        isA: Bool
    ) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(label)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                if channel.isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                if isA && controlVM.isSynced {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Animated strength bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.6), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * (channel.strength / 100))
                        .animation(.easeInOut(duration: 0.3), value: channel.strength)

                    // Glow effect
                    if channel.strength > 0 {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.3))
                            .frame(width: geometry.size.width * (channel.strength / 100))
                            .blur(radius: 8)
                    }
                }
            }
            .frame(height: 20)

            // Details
            HStack {
                Text("\(Int(channel.strength))%")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundColor(color)

                Spacer()

                Label(channel.waveform.name, systemImage: channel.waveform.icon)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(channel.frequency))Hz")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Live Waveform Visualization

    private var liveWaveformVisualization: some View {
        VStack(spacing: 8) {
            Text("Live Output")
                .font(.caption)
                .foregroundColor(.secondary)

            LiveWaveformView(
                waveform: controlVM.channelA.waveform,
                frequency: controlVM.channelA.frequency,
                strength: controlVM.currentMaxStrength,
                color: .blue
            )
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Active Program Info

    private func activeProgramInfo(_ program: Program) -> some View {
        HStack {
            Image(systemName: program.icon)
                .foregroundColor(Color(hex: program.color))
            Text(program.name)
                .font(.headline)
            Spacer()
            Text("Step \(controlVM.currentProgramStep + 1)/\(program.steps.count)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            Button {
                showQuickPresets = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.stack.fill")
                    Text("Presets")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showQuickActions = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text("Actions")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                controlVM.togglePause()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: controlVM.isPaused ? "play.fill" : "pause.fill")
                    Text(controlVM.isPaused ? "Resume" : "Pause")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Emergency stop
            Button {
                showEmergencyConfirm = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(.red.gradient)
                    .clipShape(Circle())
            }

            // Stop
            Button {
                controlVM.stopSession()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.secondary.gradient)
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Live Waveform View (animated)

struct LiveWaveformView: View {
    let waveform: WaveformType
    let frequency: Double
    let strength: Double
    let color: Color

    @State private var phase: Double = 0
    @State private var engine = WaveformEngine()
    @State private var points: [Double] = []

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2
                let amplitude = (height / 2 - 4) * (strength / 100)

                for (index, baseValue) in points.enumerated() {
                    let x = (Double(index) / Double(points.count - 1)) * width
                    // Animate by shifting phase
                    let animatedValue = sin(phase + Double(index) * 0.1) * baseValue
                    let y = midY - (animatedValue * amplitude)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [color.opacity(0.5), color, color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .task {
            let generated = await engine.generate(waveform, samples: 160, frequency: frequency)
            points = generated
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .onChange(of: waveform) {
            Task {
                let generated = await engine.generate(waveform, samples: 160, frequency: frequency)
                points = generated
            }
        }
    }
}

// MARK: - Emergency Stopped Overlay

struct EmergencyStoppedOverlay: View {
    @EnvironmentObject var controlVM: ControlVM

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Pulsing warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .modifier(PulseAnimation())

                Text("EMERGENCY STOP")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundColor(.red)

                Text("All output has been cut.\nTap below to resume.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    controlVM.resetEmergency()
                } label: {
                    Text("Resume")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.gradient)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - Quick Actions Sheet

struct QuickActionsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                    // Strength boost buttons
                    quickActionButton("−10%", systemImage: "arrow.down", color: .blue) {
                        controlVM.updateChannelA { $0.strength = max(0, $0.strength - 10) }
                    }
                    quickActionButton("+10%", systemImage: "arrow.up", color: .red) {
                        controlVM.updateChannelA { $0.strength = min(100, $0.strength + 10) }
                    }
                    quickActionButton("Reset", systemImage: "arrow.counterclockwise", color: .orange) {
                        controlVM.updateChannelA { $0.strength = 0 }
                        controlVM.updateChannelB { $0.strength = 0 }
                    }
                    quickActionButton("Max", systemImage: "bolt.fill", color: .yellow) {
                        controlVM.updateChannelA { $0.strength = 80 }
                        if !controlVM.isSynced {
                            controlVM.updateChannelB { $0.strength = 80 }
                        }
                    }

                    // Waveform quick change
                    ForEach(WaveformType.allBuiltIn.prefix(6), id: \.id) { wf in
                        quickActionButton(wf.name, systemImage: wf.icon, color: .accentColor) {
                            controlVM.updateChannelA { $0.waveform = wf }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func quickActionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}
