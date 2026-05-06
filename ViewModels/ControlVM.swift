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
        watchHeartRateReceiver = WatchHeartRateReceiver { [weak self] reading in
            self?.handleWatchHeartRate(reading)
        }
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
        max(channelA.strength, channelB.strength)
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

    func startSession() {
        guard !isEmergencyStopped else { return }

        sessionState = .starting
        sessionStartTime = .now
        isPaused = false
        intensityBoost = 0
        appliedIntensityBoost = 0
        currentProgramStep = 0

        Task {
            do {
                try await connectIfNeeded()
                sessionState = .active(elapsedMs: 0, currentStep: 0)
                startSessionTimer()
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
        } else {
            startSessionTimer()
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
        applySafetyLimits(to: &channelA)
        if isSynced { channelB.sync(from: channelA) }
        persistLastControlState()
        updateWaveformPreview()
        if isSessionActive && !isPaused {
            Task { try? await applyChannelCommand("A", state: channelA) }
        }
    }

    func updateChannelB(_ update: (inout ChannelState) -> Void) {
        update(&channelB)
        applySafetyLimits(to: &channelB)
        if isSynced { channelA.sync(from: channelB) }
        persistLastControlState()
        updateWaveformPreview()
        if isSessionActive && !isPaused {
            Task { try? await applyChannelCommand("B", state: channelB) }
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
        if !isSynced {
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
            await httpService.connect(url: settings.connectionConfig.httpServerURL)
            connectionStatus = .connected
        }
    }

    private func applyCurrentSettings() async throws {
        if channelA.isEnabled {
            try await applyChannelCommand("A", state: channelA)
        }
        if channelB.isEnabled && !isSynced {
            try await applyChannelCommand("B", state: channelB)
        }
    }

    private func applyChannelCommand(_ channel: String, state: ChannelState) async throws {
        guard let settings = settingsVM else { return }
        let strength = Int(min(state.strength, adaptiveStrengthLimit))

        switch settings.connectionConfig.mode {
        case .ble:
            try await bluetoothService.sendRealtimeControl(
                channelA: channelA,
                channelB: isSynced ? channelA : channelB,
                adaptiveStrengthLimit: adaptiveStrengthLimit
            )
        case .http:
            try await httpService.sendChannelControl(channel: channel, strength: strength, durationMs: state.durationMs)
        }
    }

    private func sendEmergencyStop() async throws {
        guard let settings = settingsVM else { return }
        switch settings.connectionConfig.mode {
        case .ble: try await bluetoothService.emergencyStop()
        case .http: try await httpService.emergencyStop()
        }
    }

    private func applySafetyLimits(to channel: inout ChannelState) {
        guard let settings = settingsVM else { return }
        let config = settings.safetyConfig

        channel.strength = min(channel.strength, config.maxStrength)
        channel.strength = min(channel.strength, adaptiveStrengthLimit)

        let chConfig = channel.id == .a ? settings.channelAConfig : settings.channelBConfig
        channel.strength = max(chConfig.minStrength, min(channel.strength, chConfig.maxStrength))

        if channel.strength > config.confirmationThreshold && !showSafetyWarning {
            showSafetyWarning = true
        }
    }

    // MARK: - Ramp Control

    private func startRampIfNeeded() {
        guard let settings = settingsVM else { return }
        let rampRate = settings.safetyConfig.rampRateLimit
        guard rampRate > 0 else { return }

        isRamping = true
        let targetA = channelA.strength
        channelA.strength = 0
        let targetB = isSynced ? targetA : channelB.strength
        channelB.strength = 0

        rampTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var done = true
                if self.channelA.strength < targetA {
                    self.channelA.strength = min(self.channelA.strength + rampRate * 0.1, targetA)
                    done = false
                }
                if self.channelB.strength < targetB {
                    self.channelB.strength = min(self.channelB.strength + rampRate * 0.1, targetB)
                    done = false
                }
                if done {
                    self.isRamping = false
                    self.rampTimer?.invalidate()
                }
            }
        }
    }

    // MARK: - Session Timer

    private func startSessionTimer() {
        guard let settings = settingsVM else { return }

        sessionElapsedMs = 0
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

    private func applyEdgeModeIfNeeded(bpm: Double) {
        guard let settingsVM, settingsVM.edgeModeConfig.isEnabled else {
            edgeModeState = .inactive
            return
        }

        let policy = EdgeModePolicy(config: settingsVM.edgeModeConfig)
        let state = policy.evaluate(bpm: bpm, currentStrength: currentMaxStrength)
        edgeModeState = isSessionActive && !isPaused ? state : .armed

        guard isSessionActive, !isPaused, let targetStrength = state.targetStrength else { return }
        if let lastEdgeAdjustmentAt,
           Date().timeIntervalSince(lastEdgeAdjustmentAt) < settingsVM.edgeModeConfig.cooldownSeconds {
            return
        }

        lastEdgeAdjustmentAt = .now
        let target = min(targetStrength, adaptiveStrengthLimit)
        let delta = target - currentMaxStrength

        updateChannelA { channel in
            channel.strength = max(0, min(100, channel.strength + delta))
        }

        if !isSynced {
            updateChannelB { channel in
                channel.strength = max(0, min(100, channel.strength + delta))
            }
        }
    }

    private func applyAdaptiveHeartRateLimits() {
        guard let settingsVM else { return }
        channelA.strength = min(channelA.strength, adaptiveStrengthLimit)
        channelB.strength = min(channelB.strength, adaptiveStrengthLimit)

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
