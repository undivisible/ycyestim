import Foundation
import SwiftUI

// MARK: - Control ViewModel

@MainActor
final class ControlVM: ObservableObject {
    // MARK: - Published State

    @Published var channelA: ChannelState = .init(id: .a)
    @Published var channelB: ChannelState = .init(id: .b)
    @Published var isSynced: Bool = false
    @Published var sessionState: SessionState = .idle
    @Published var sessionElapsedMs: Int = 0
    @Published var isEmergencyStopped: Bool = false
    @Published var showEmergencyConfirm: Bool = false
    @Published var showSafetyWarning: Bool = false
    @Published var isPaused: Bool = false
    @Published var intensityBoost: Double = 0
    @Published var activePreset: Preset?
    @Published var activeProgram: Program?
    @Published var currentProgramStep: Int = 0
    @Published var waveformPoints: [Double] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isRamping: Bool = false
    @Published var heartRateSafetyState: HeartRateSafetyState = .inactive
    @Published var edgeModeState: EdgeModeState = .inactive
    @Published var latestHeartRateReading: HeartRateReading?
    @Published var watchWorkoutStatus: String = "unknown"
    @Published var heartRateAuthorizationStatus: HeartRateAuthorizationStatus = .unknown
    @Published var heartRateAuthorizationError: String?

    enum ConnectionStatus {
        case disconnected, connecting, connected, error(String)
    }

    // MARK: - Services

    private let bluetoothService = BluetoothService.shared
    private let httpService = HTTPService()
    private let heartRateService = HealthKitHeartRateService()
    private var watchHeartRateReceiver: WatchHeartRateReceiver?
    private let waveformEngine = WaveformEngine()
    let presetStore = PresetStore()

    private var sessionTimer: Timer?
    private var rampTimer: Timer?
    private var waveformPreviewTask: Task<Void, Never>?
    private var appliedIntensityBoost: Double = 0
    private var lastEdgeAdjustmentAt: Date?
    private var sessionStartTime: Date = .now
    private var settingsVM: SettingsVM?
    private let liveHeartRateMaxAge: TimeInterval = 30
    private let lastControlStateKey = "ycy.lastControlState"

    // Retained haptic generators (prevent missed haptics)
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGen = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        restoreLastControlState()
        watchHeartRateReceiver = WatchHeartRateReceiver(
            onReading: { [weak self] reading in
                self?.handleWatchHeartRate(reading)
            },
            onWorkoutStatus: { [weak self] status in
                self?.handleWatchWorkoutStatus(status)
            },
            onEmergencyStop: { [weak self] in
                Task { try? await self?.emergencyStop() }
            }
        )
        watchHeartRateReceiver?.start()
    }

    deinit {
        MainActor.assumeIsolated {
            sessionTimer?.invalidate()
            rampTimer?.invalidate()
            waveformPreviewTask?.cancel()
            heartRateService.stopMonitoring()
        }
    }

    // MARK: - Computed

    var isSessionActive: Bool {
        if case .active = sessionState { return true }
        return false
    }

    var sessionElapsedFormatted: String {
        let totalSec = sessionElapsedMs / 1000
        return String(format: "%02d:%02d", totalSec / 60, totalSec % 60)
    }

    var currentMaxStrength: Double {
        let strengths = [channelA, channelB]
            .filter(\.isEnabled)
            .map(\.strength)
        return strengths.max() ?? 0
    }

    var adaptiveStrengthLimit: Double {
        guard let settingsVM else { return 100 }
        return settingsVM.safetyConfig.maxStrength * heartRateSafetyState.strengthMultiplier
    }

    var currentHeartRateBPM: Double? {
        isHeartRateLive ? latestHeartRateReading?.bpm : nil
    }

    var heartRateDisplayBPM: Double? {
        latestHeartRateReading?.bpm
    }

    var isHeartRateLive: Bool {
        guard let latestHeartRateReading else { return false }
        return isFresh(latestHeartRateReading)
    }

    var heartRateSourceLabel: String {
        guard let latestHeartRateReading else { return "No live HR" }
        if isFresh(latestHeartRateReading) { return "Live HR" }

        let ageSeconds = max(0, Int(Date().timeIntervalSince(latestHeartRateReading.sampleDate)))
        if ageSeconds < 60 {
            return "Stale \(ageSeconds)s"
        }
        return "Stale \(ageSeconds / 60)m"
    }

    // MARK: - Session Control

    func connect() {
        guard !isEmergencyStopped else { return }

        Task {
            do {
                try await connectIfNeeded()
            } catch {
                connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        if isSessionActive {
            stopSession()
        }
        switch settingsVM?.connectionConfig.mode ?? .ble {
        case .ble:
            bluetoothService.disconnect()
        case .http:
            Task { await httpService.disconnect() }
        }
        connectionStatus = .disconnected
    }

    func startSession() {
        guard !isEmergencyStopped else { return }

        sessionState = .starting
        sessionElapsedMs = 0
        sessionStartTime = .now
        isPaused = false
        intensityBoost = 0
        appliedIntensityBoost = 0
        currentProgramStep = 0

        Task {
            do {
                try await connectIfNeeded()
                sessionState = .active(elapsedMs: 0, currentStep: 0)
                startSessionTimer(resetElapsed: true)
                startHeartRateSafetyIfNeeded()
                startRampIfNeeded()
                try await applyCurrentSettings()
                triggerHaptic(.medium)
            } catch {
                sessionState = .idle
                connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    func stopSession() {
        sessionState = .stopping
        let finalElapsed = sessionElapsedMs
        let finalMaxStrength = currentMaxStrength
        let finalPreset = activePreset
        let mode = settingsVM?.connectionConfig.mode ?? .ble
        let startTime = sessionStartTime

        sessionTimer?.invalidate()
        rampTimer?.invalidate()
        stopHeartRateSafety()
        edgeModeState = .inactive

        Task {
            try? await sendEmergencyStop()

            // Save session record with actual elapsed time
            let record = SessionRecord(
                startTime: startTime,
                endTime: .now,
                durationMs: finalElapsed,
                presetsUsed: finalPreset.map { [$0.name] } ?? [],
                maxStrengthReached: finalMaxStrength,
                mode: mode
            )
            presetStore.saveSession(record)

            sessionState = .idle
            sessionElapsedMs = 0
            activePreset = nil
            activeProgram = nil
            currentProgramStep = 0
            intensityBoost = 0
            appliedIntensityBoost = 0
            isPaused = false
        }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            sessionTimer?.invalidate()
            rampTimer?.invalidate()
            isRamping = false
            Task {
                do {
                    try await sendZeroOutput()
                } catch {
                    connectionStatus = .error(error.localizedDescription)
                }
            }
        } else {
            startSessionTimer()
            Task {
                do {
                    try await applyCurrentSettings()
                } catch {
                    connectionStatus = .error(error.localizedDescription)
                }
            }
        }
        triggerHaptic(.light)
    }

    func emergencyStop() async throws {
        isEmergencyStopped = true
        sessionState = .emergencyStopped
        sessionTimer?.invalidate()
        rampTimer?.invalidate()
        stopHeartRateSafety()
        edgeModeState = .inactive

        triggerHaptic(.heavy)
        try await sendEmergencyStop()
    }

    func resetEmergency() {
        isEmergencyStopped = false
        sessionState = .idle
        sessionElapsedMs = 0
        isPaused = false
        intensityBoost = 0
        appliedIntensityBoost = 0
        triggerHaptic(.medium)
    }

    // MARK: - Channel Control

    func updateChannelA(_ update: (inout ChannelState) -> Void) {
        update(&channelA)
        normalizeEnabledDefaults(&channelA)
        applySafetyLimits(to: &channelA)
        if isSynced {
            channelB.sync(from: channelA)
            normalizeEnabledDefaults(&channelB)
            applySafetyLimits(to: &channelB)
        }
        persistLastControlState()
        updateWaveformPreview()
        if isSessionActive && !isPaused {
            Task { try? await applyCurrentSettings() }
        }
    }

    func updateChannelB(_ update: (inout ChannelState) -> Void) {
        update(&channelB)
        normalizeEnabledDefaults(&channelB)
        applySafetyLimits(to: &channelB)
        if isSynced {
            channelA.sync(from: channelB)
            normalizeEnabledDefaults(&channelA)
            applySafetyLimits(to: &channelA)
        }
        persistLastControlState()
        updateWaveformPreview()
        if isSessionActive && !isPaused {
            Task { try? await applyCurrentSettings() }
        }
    }

    func setChannelStrength(_ channel: ChannelState.ChannelID, _ value: Double) {
        if channel == .a {
            updateChannelA { $0.strength = value }
        } else {
            updateChannelB { $0.strength = value }
        }
    }

    func toggleSync() {
        isSynced.toggle()
        if isSynced { channelB.sync(from: channelA) }
        persistLastControlState()
        triggerHaptic(.light)
    }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        activePreset = preset

        updateChannelA { ch in
            ch.isEnabled = true
            ch.strength = preset.channelA.strength
            ch.waveform = preset.channelA.waveform
            ch.frequency = preset.channelA.frequency
            ch.pulseWidth = preset.channelA.pulseWidth
            ch.phaseOffset = preset.channelA.phaseOffset
            ch.durationMs = preset.channelA.durationMs
        }

        if let b = preset.channelB {
            updateChannelB { ch in
                ch.isEnabled = true
                ch.strength = b.strength
                ch.waveform = b.waveform
                ch.frequency = b.frequency
                ch.pulseWidth = b.pulseWidth
                ch.phaseOffset = b.phaseOffset
                ch.durationMs = b.durationMs
            }
        }

        if isSessionActive && !isPaused {
            Task { try? await applyCurrentSettings() }
        }
        persistLastControlState()
        triggerHaptic(.medium)
    }

    // MARK: - Intensity Boost

    func applyIntensityBoost(_ boost: Double) {
        let delta = boost - appliedIntensityBoost
        intensityBoost = boost
        appliedIntensityBoost = boost
        updateChannelA { ch in
            ch.strength = max(0, min(100, ch.strength + delta))
        }
        if !isSynced && channelB.isEnabled {
            updateChannelB { ch in
                ch.strength = max(0, min(100, ch.strength + delta))
            }
        }
        persistLastControlState()
    }

    // MARK: - Waveform Preview

    func updateWaveformPreview() {
        waveformPreviewTask?.cancel()

        let waveform = channelA.waveform
        let frequency = channelA.frequency
        let engine = waveformEngine

        waveformPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let points = await engine.generate(waveform, samples: 180, frequency: frequency)
            guard !Task.isCancelled else { return }

            waveformPoints = points
        }
    }

    // MARK: - Internal

    private func connectIfNeeded() async throws {
        guard let settings = settingsVM else { return }
        switch settings.connectionConfig.mode {
        case .ble:
            connectionStatus = .connecting
            guard bluetoothService.isReady else {
                connectionStatus = .disconnected
                throw BLEError.notConnected
            }
            connectionStatus = .connected
        case .http:
            connectionStatus = .connecting
            try await httpService.connect(
                url: settings.connectionConfig.httpServerURL,
                apiKey: settings.connectionConfig.httpAPIKey
            )
            connectionStatus = .connected
        }
    }

    private func applyCurrentSettings() async throws {
        guard let settings = settingsVM else { return }
        let policy = placementPolicy()
        let outputA = policy.adapted(channelA, bpm: currentHeartRateBPM, adaptiveStrengthLimit: adaptiveStrengthLimit)
        let outputB = policy.adapted(effectiveChannelBForOutput(), bpm: currentHeartRateBPM, adaptiveStrengthLimit: adaptiveStrengthLimit)

        switch settings.connectionConfig.mode {
        case .ble:
            try await bluetoothService.sendRealtimeControl(
                channelA: outputA,
                channelB: outputB,
                adaptiveStrengthLimit: adaptiveStrengthLimit,
                protocolVersion: settings.connectionConfig.bleProtocolVersion,
                outputMode: settings.connectionConfig.bleOutputMode
            )
        case .http:
            if outputA.isEnabled || outputB.isEnabled {
                try await httpService.sendChannelControl(commandID: settings.connectionConfig.httpCommandID)
            } else {
                try await httpService.emergencyStop(commandID: settings.connectionConfig.httpStopCommandID)
            }
        }
    }

    private func effectiveChannelBForOutput() -> ChannelState {
        var output = channelB
        if isSynced {
            output.sync(from: channelA)
        }
        return output
    }

    private func outputStrength(for channel: ChannelState) -> Int {
        guard channel.isEnabled else { return 0 }
        return Int(min(channel.strength, adaptiveStrengthLimit).rounded())
    }

    private func sendEmergencyStop() async throws {
        guard let settings = settingsVM else { return }
        switch settings.connectionConfig.mode {
        case .ble: try await bluetoothService.emergencyStop(protocolVersion: settings.connectionConfig.bleProtocolVersion)
        case .http: try await httpService.emergencyStop(commandID: settings.connectionConfig.httpStopCommandID)
        }
    }

    private func sendZeroOutput() async throws {
        guard let settings = settingsVM else { return }
        var zeroA = channelA
        var zeroB = isSynced ? channelA : channelB
        zeroA.strength = 0
        zeroA.isEnabled = false
        zeroB.strength = 0
        zeroB.isEnabled = false

        switch settings.connectionConfig.mode {
        case .ble:
            try await bluetoothService.sendRealtimeControl(
                channelA: zeroA,
                channelB: zeroB,
                adaptiveStrengthLimit: 100,
                protocolVersion: settings.connectionConfig.bleProtocolVersion,
                outputMode: settings.connectionConfig.bleOutputMode
            )
        case .http:
            try await httpService.emergencyStop(commandID: settings.connectionConfig.httpStopCommandID)
        }
    }

    private func applySafetyLimits(to channel: inout ChannelState) {
        guard let settings = settingsVM else { return }
        let config = settings.safetyConfig

        channel.strength = min(channel.strength, config.maxStrength)
        channel.strength = min(channel.strength, adaptiveStrengthLimit)

        let chConfig = channel.id == .a ? settings.channelAConfig : settings.channelBConfig
        channel.strength = max(chConfig.minStrength, min(channel.strength, chConfig.maxStrength))
        channel = placementPolicy().adapted(channel, bpm: nil, adaptiveStrengthLimit: adaptiveStrengthLimit)

        if channel.strength > config.confirmationThreshold && !showSafetyWarning {
            showSafetyWarning = true
        }
    }

    private func normalizeEnabledDefaults(_ channel: inout ChannelState) {
        guard channel.isEnabled, let settingsVM else { return }
        let chConfig = channel.id == .a ? settingsVM.channelAConfig : settingsVM.channelBConfig
        let profile = channel.padPairProfile
        if channel.strength <= 0 {
            channel.strength = min(max(chConfig.defaultStrength, chConfig.minStrength), chConfig.maxStrength, settingsVM.safetyConfig.maxStrength, adaptiveStrengthLimit, profile.maxStrength)
        }
        if channel.frequency < profile.minFrequency || channel.frequency > profile.maxFrequency {
            channel.frequency = max(profile.minFrequency, min(chConfig.defaultFrequency, profile.maxFrequency))
        }
        if channel.pulseWidth <= 0 || channel.pulseWidth > profile.maxPulseWidth {
            channel.pulseWidth = max(0, min(chConfig.defaultPulseWidth, profile.maxPulseWidth))
        }
    }

    // MARK: - Ramp Control

    private func startRampIfNeeded() {
        guard let settings = settingsVM else { return }
        guard settings.connectionConfig.mode == .ble else { return }
        let rampRate = settings.safetyConfig.rampRateLimit
        guard rampRate > 0 else { return }

        rampTimer?.invalidate()
        isRamping = true
        let targetA = channelA.strength
        let targetB = channelB.strength
        let shouldRampA = channelA.isEnabled
        let shouldRampB = channelB.isEnabled
        if shouldRampA {
            channelA.strength = 0
        }
        if shouldRampB {
            channelB.strength = 0
        }

        rampTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var done = true
                if shouldRampA && self.channelA.strength < targetA {
                    self.channelA.strength = min(self.channelA.strength + rampRate * 0.1, targetA)
                    done = false
                }
                if shouldRampB && self.channelB.strength < targetB {
                    self.channelB.strength = min(self.channelB.strength + rampRate * 0.1, targetB)
                    done = false
                }
                do {
                    try await self.applyCurrentSettings()
                } catch {
                    self.connectionStatus = .error(error.localizedDescription)
                }
                if done {
                    self.isRamping = false
                    self.rampTimer?.invalidate()
                }
            }
        }
    }

    // MARK: - Session Timer

    private func startSessionTimer(resetElapsed: Bool = false) {
        guard let settings = settingsVM else { return }

        if resetElapsed {
            sessionElapsedMs = 0
        }
        let timeoutMs = settings.safetyConfig.sessionTimeoutMinutes * 60 * 1000

        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.sessionElapsedMs += 1000

                if timeoutMs > 0 && self.sessionElapsedMs >= timeoutMs {
                    self.stopSession()
                }

                if let program = self.activeProgram, program.autoProgress {
                    self.advanceProgramStep(program)
                }
            }
        }
    }

    func requestHeartRateAuthorization() async {
        do {
            let status = try await heartRateService.authorizationStatus()
            heartRateAuthorizationStatus = status

            if status == .shouldRequest || status == .unknown {
                try await heartRateService.requestAuthorization()
                heartRateAuthorizationStatus = try await heartRateService.authorizationStatus()
            }

            heartRateAuthorizationError = nil
            if settingsVM?.heartRateSafetyConfig.isEnabled == true || settingsVM?.edgeModeConfig.isEnabled == true {
                startHeartRateSafetyIfNeeded()
            }
        } catch {
            heartRateAuthorizationError = error.localizedDescription
            heartRateSafetyState = heartRateService.isAvailable ? .needsAuthorization : .unavailable
        }
    }

    func refreshHeartRateAuthorizationStatus() async {
        do {
            let status = try await heartRateService.authorizationStatus()
            heartRateAuthorizationStatus = status
            heartRateAuthorizationError = nil

            switch status {
            case .unavailable:
                heartRateSafetyState = .unavailable
                edgeModeState = .inactive
            case .shouldRequest, .unknown:
                if settingsVM?.heartRateSafetyConfig.isEnabled == true || settingsVM?.edgeModeConfig.isEnabled == true {
                    heartRateSafetyState = .needsAuthorization
                    edgeModeState = settingsVM?.edgeModeConfig.isEnabled == true ? .armed : .inactive
                }
            case .unnecessary:
                if settingsVM?.heartRateSafetyConfig.isEnabled == true || settingsVM?.edgeModeConfig.isEnabled == true {
                    startHeartRateSafetyIfNeeded()
                }
            }
        } catch {
            heartRateAuthorizationError = error.localizedDescription
            heartRateAuthorizationStatus = heartRateService.isAvailable ? .unknown : .unavailable
            heartRateSafetyState = heartRateService.isAvailable ? .needsAuthorization : .unavailable
        }
    }

    private func startHeartRateSafetyIfNeeded() {
        guard let settingsVM else { return }
        guard settingsVM.heartRateSafetyConfig.isEnabled || settingsVM.safetyConfig.heartRateMonitoring || settingsVM.edgeModeConfig.isEnabled else {
            heartRateSafetyState = .inactive
            edgeModeState = .inactive
            return
        }

        let policy = HeartRateSafetyPolicy(config: settingsVM.heartRateSafetyConfig)
        do {
            try heartRateService.startMonitoring { [weak self] reading in
                guard let self else { return }
                self.handleHeartRateUpdate(reading, safetyPolicy: policy)
            }
        } catch {
            heartRateAuthorizationError = error.localizedDescription
            heartRateSafetyState = heartRateService.isAvailable ? .needsAuthorization : .unavailable
            edgeModeState = .inactive
        }
    }

    private func handleHeartRateUpdate(_ reading: HeartRateReading, safetyPolicy: HeartRateSafetyPolicy) {
        guard let settingsVM else { return }
        latestHeartRateReading = reading

        guard isFresh(reading) else {
            heartRateSafetyState = .stale(bpm: reading.bpm)
            edgeModeState = settingsVM.edgeModeConfig.isEnabled ? .armed : .inactive
            return
        }

        let bpm = reading.bpm
        if settingsVM.heartRateSafetyConfig.isEnabled || settingsVM.safetyConfig.heartRateMonitoring {
            heartRateSafetyState = safetyPolicy.evaluate(bpm: bpm)
        } else {
            heartRateSafetyState = .monitoring(bpm: bpm, multiplier: 1)
        }
        applyEdgeModeIfNeeded(bpm: bpm)
        applyAdaptiveHeartRateLimits()
    }

    private func handleWatchHeartRate(_ reading: HeartRateReading) {
        let policy = HeartRateSafetyPolicy(config: settingsVM?.heartRateSafetyConfig ?? .default)
        handleHeartRateUpdate(reading, safetyPolicy: policy)
    }

    private func handleWatchWorkoutStatus(_ status: String) {
        watchWorkoutStatus = status
        guard status != "running" else { return }
        if let latestHeartRateReading {
            self.latestHeartRateReading = HeartRateReading(
                bpm: latestHeartRateReading.bpm,
                sampleDate: Date().addingTimeInterval(-liveHeartRateMaxAge - 1)
            )
        }
        if settingsVM?.edgeModeConfig.isEnabled == true {
            edgeModeState = .armed
        }
    }

    private func applyEdgeModeIfNeeded(bpm: Double) {
        guard let settingsVM, settingsVM.edgeModeConfig.isEnabled else {
            edgeModeState = .inactive
            return
        }

        let policy = EdgeModePolicy(config: settingsVM.edgeModeConfig)
        let state = policy.evaluate(bpm: bpm, currentStrength: currentMaxStrength)
        edgeModeState = isSessionActive && !isPaused ? state : .armed

        guard isSessionActive, !isPaused else { return }
        let edgeInterval = min(settingsVM.edgeModeConfig.cooldownSeconds, 2.5)
        if let lastEdgeAdjustmentAt,
           Date().timeIntervalSince(lastEdgeAdjustmentAt) < edgeInterval {
            return
        }

        lastEdgeAdjustmentAt = .now
        var didUpdate = false

        if settingsVM.edgeModeConfig.adjustsStrength,
           let targetStrength = state.targetStrength {
            let target = min(targetStrength, adaptiveStrengthLimit)
            let delta = target - currentMaxStrength
            let smoothedDelta = delta * 0.45
            applyEdgeStrengthDelta(smoothedDelta)
            didUpdate = true
        }

        let profile = activePadProfile()

        if settingsVM.edgeModeConfig.adjustsFrequency {
            let frequency = policy.targetFrequency(bpm: bpm, placementProfile: profile)
            applyEdgeSignal { channel in
                channel.frequency += (frequency - channel.frequency) * 0.35
            }
            didUpdate = true
        }

        if settingsVM.edgeModeConfig.adjustsWaveform,
           let waveform = policy.targetWaveform(for: state, placementProfile: profile) {
            applyEdgeSignal { channel in
                channel.waveform = waveform
            }
            didUpdate = true
        }

        if didUpdate {
            applySafetyLimits(to: &channelA)
            applySafetyLimits(to: &channelB)
            persistLastControlState()
            updateWaveformPreview()
            Task { try? await applyCurrentSettings() }
        }
    }

    private func applyEdgeStrengthDelta(_ delta: Double) {
        if channelA.isEnabled {
            channelA.strength = max(0, min(100, channelA.strength + delta))
        }
        if channelB.isEnabled {
            channelB.strength = max(0, min(100, channelB.strength + delta))
        }
    }

    private func applyEdgeSignal(_ update: (inout ChannelState) -> Void) {
        if channelA.isEnabled {
            update(&channelA)
        }
        if channelB.isEnabled {
            update(&channelB)
        }
    }

    private func applyAdaptiveHeartRateLimits() {
        guard let settingsVM else { return }
        let policy = placementPolicy()
        if channelA.isEnabled {
            channelA = policy.adapted(channelA, bpm: currentHeartRateBPM, adaptiveStrengthLimit: adaptiveStrengthLimit)
        }
        if channelB.isEnabled {
            channelB = policy.adapted(channelB, bpm: currentHeartRateBPM, adaptiveStrengthLimit: adaptiveStrengthLimit)
        }

        if case .critical = heartRateSafetyState,
           settingsVM.heartRateSafetyConfig.emergencyStopOnCritical,
           isSessionActive {
            Task { try? await emergencyStop() }
        } else if isSessionActive && !isPaused {
            Task { try? await applyCurrentSettings() }
        }
    }

    private func stopHeartRateSafety() {
        heartRateService.stopMonitoring()
        if settingsVM?.heartRateSafetyConfig.isEnabled != true {
            heartRateSafetyState = .inactive
        }
        if settingsVM?.edgeModeConfig.isEnabled != true {
            edgeModeState = .inactive
        }
    }

    private func isFresh(_ reading: HeartRateReading) -> Bool {
        Date().timeIntervalSince(reading.sampleDate) <= liveHeartRateMaxAge
    }

    private func placementPolicy() -> PlacementOutputPolicy {
        PlacementOutputPolicy(heartRateConfig: settingsVM?.heartRateSafetyConfig ?? .default)
    }

    private func activePadProfile() -> PadPlacementProfile? {
        let channels = [channelA, effectiveChannelBForOutput()].filter(\.isEnabled)
        return channels
            .map(\.padPairProfile)
            .max { lhs, rhs in
                lhs.sensitivity < rhs.sensitivity
            }
    }

    private func advanceProgramStep(_ program: Program) {
        let currentMs = sessionElapsedMs
        for (index, step) in program.steps.enumerated() {
            if currentMs >= step.timeOffset && currentProgramStep != index {
                currentProgramStep = index
                updateChannelA { ch in
                    ch.strength = step.channelA.strength
                    ch.waveform = step.channelA.waveform
                    ch.frequency = step.channelA.frequency
                    ch.pulseWidth = step.channelA.pulseWidth
                    ch.durationMs = step.channelA.durationMs
                }
                if let b = step.channelB {
                    updateChannelB { ch in
                        ch.strength = b.strength
                        ch.waveform = b.waveform
                        ch.frequency = b.frequency
                        ch.pulseWidth = b.pulseWidth
                        ch.durationMs = b.durationMs
                    }
                }
                triggerHaptic(.light)
            }
        }
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic(_ intensity: SafetyConfig.HapticIntensity) {
        #if os(iOS)
        switch intensity {
        case .off: return
        case .light: lightGen.impactOccurred()
        case .medium: mediumGen.impactOccurred()
        case .heavy: heavyGen.impactOccurred()
        }
        #endif
    }

    func prepareHaptics() {
        #if os(iOS)
        lightGen.prepare()
        mediumGen.prepare()
        heavyGen.prepare()
        #endif
    }

    // MARK: - Injection

    func injectSettings(_ vm: SettingsVM) {
        settingsVM = vm
        applySafetyLimits(to: &channelA)
        applySafetyLimits(to: &channelB)
        persistLastControlState()
        updateWaveformPreview()
    }

    private struct LastControlState: Codable {
        var channelA: ChannelState
        var channelB: ChannelState
        var isSynced: Bool
        var intensityBoost: Double
    }

    private func restoreLastControlState() {
        guard let data = UserDefaults.standard.data(forKey: lastControlStateKey),
              let state = try? JSONDecoder().decode(LastControlState.self, from: data) else { return }
        channelA = state.channelA
        channelB = state.channelB
        isSynced = state.isSynced
        intensityBoost = state.intensityBoost
    }

    private func persistLastControlState() {
        let state = LastControlState(
            channelA: channelA,
            channelB: channelB,
            isSynced: isSynced,
            intensityBoost: intensityBoost
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: lastControlStateKey)
        }
    }
}
