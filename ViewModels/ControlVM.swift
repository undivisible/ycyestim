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
    @Published var heartRateAuthorizationError: String?

    enum ConnectionStatus {
        case disconnected, connecting, connected, error(String)
    }

    // MARK: - Services

    private let bluetoothService = BluetoothService()
    private let httpService = HTTPService()
    private let heartRateService = HealthKitHeartRateService()
    private let waveformEngine = WaveformEngine()
    let presetStore = PresetStore()

    private var sessionTimer: Timer?
    private var rampTimer: Timer?
    private var sessionStartTime: Date = .now
    private var settingsVM: SettingsVM?

    // Retained haptic generators (prevent missed haptics)
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGen = UIImpactFeedbackGenerator(style: .heavy)

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

    // MARK: - Session Control

    func startSession() {
        guard !isEmergencyStopped else { return }

        sessionState = .starting
        sessionStartTime = .now
        isPaused = false
        intensityBoost = 0
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

        triggerHaptic(.heavy)
        try await sendEmergencyStop()
    }

    func resetEmergency() {
        isEmergencyStopped = false
        sessionState = .idle
        sessionElapsedMs = 0
        isPaused = false
        intensityBoost = 0
        triggerHaptic(.medium)
    }

    // MARK: - Channel Control

    func updateChannelA(_ update: (inout ChannelState) -> Void) {
        update(&channelA)
        applySafetyLimits(to: &channelA)
        if isSynced { channelB.sync(from: channelA) }
        updateWaveformPreview()
        if isSessionActive && !isPaused {
            Task { try? await applyChannelCommand("A", state: channelA) }
        }
    }

    func updateChannelB(_ update: (inout ChannelState) -> Void) {
        update(&channelB)
        applySafetyLimits(to: &channelB)
        if isSynced { channelA.sync(from: channelB) }
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
        triggerHaptic(.medium)
    }

    // MARK: - Intensity Boost

    func applyIntensityBoost(_ boost: Double) {
        intensityBoost = boost
        updateChannelA { ch in
            ch.strength = max(0, min(100, ch.strength + boost))
        }
        if !isSynced {
            updateChannelB { ch in
                ch.strength = max(0, min(100, ch.strength + boost))
            }
        }
    }

    // MARK: - Waveform Preview

    func updateWaveformPreview() {
        Task {
            waveformPoints = await waveformEngine.generate(
                channelA.waveform, samples: 500, frequency: channelA.frequency
            )
        }
    }

    // MARK: - Internal

    private func connectIfNeeded() async throws {
        guard let settings = settingsVM else { return }
        switch settings.connectionConfig.mode {
        case .ble:
            connectionStatus = .connecting
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
            try await bluetoothService.sendChannelControl(channel: channel, strength: strength, durationMs: state.durationMs)
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
            try await heartRateService.requestAuthorization()
            heartRateAuthorizationError = nil
            if settingsVM?.heartRateSafetyConfig.isEnabled == true {
                startHeartRateSafetyIfNeeded()
            }
        } catch {
            heartRateAuthorizationError = error.localizedDescription
            heartRateSafetyState = heartRateService.isAvailable ? .needsAuthorization : .unavailable
        }
    }

    private func startHeartRateSafetyIfNeeded() {
        guard let settingsVM else { return }
        guard settingsVM.heartRateSafetyConfig.isEnabled || settingsVM.safetyConfig.heartRateMonitoring else {
            heartRateSafetyState = .inactive
            return
        }

        let policy = HeartRateSafetyPolicy(config: settingsVM.heartRateSafetyConfig)
        do {
            try heartRateService.startMonitoring { [weak self] bpm in
                guard let self else { return }
                self.heartRateSafetyState = policy.evaluate(bpm: bpm)
                self.applyAdaptiveHeartRateLimits()
            }
        } catch {
            heartRateAuthorizationError = error.localizedDescription
            heartRateSafetyState = heartRateService.isAvailable ? .needsAuthorization : .unavailable
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
    }
}
