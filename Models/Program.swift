import Foundation

// MARK: - Program (timed sequence of waveform changes)

struct Program: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var color: String
    var steps: [ProgramStep]
    var loopCount: Int          // 0 = infinite
    var autoProgress: Bool
    var transitionSmoothness: Double  // 0–1, how gradual the transition between steps is
    var pauseBetweenSteps: Int  // milliseconds

    struct ProgramStep: Identifiable, Codable, Equatable {
        let id: UUID
        var timeOffset: Int     // milliseconds from program start
        var channelA: ChannelSettings
        var channelB: ChannelSettings?

        struct ChannelSettings: Codable, Equatable {
            var strength: Double
            var waveform: WaveformType
            var frequency: Double
            var pulseWidth: Int
            var durationMs: Int
        }

        init(id: UUID = UUID(),
             timeOffset: Int,
             channelA: ChannelSettings,
             channelB: ChannelSettings? = nil) {
            self.id = id
            self.timeOffset = timeOffset
            self.channelA = channelA
            self.channelB = channelB
        }
    }

    var totalDurationMs: Int {
        steps.map(\.timeOffset).max() ?? 0
    }

    init(id: UUID = UUID(),
         name: String,
         icon: String = "timeline.selection",
         color: String = "#007AFF",
         steps: [ProgramStep],
         loopCount: Int = 0,
         autoProgress: Bool = true,
         transitionSmoothness: Double = 0.5,
         pauseBetweenSteps: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.steps = steps
        self.loopCount = loopCount
        self.autoProgress = autoProgress
        self.transitionSmoothness = transitionSmoothness
        self.pauseBetweenSteps = pauseBetweenSteps
    }
}

// MARK: - Built-in Programs

extension Program {
    static let warmupProgression = Program(
        name: "Warm-up Progression",
        icon: "arrow.up.right",
        color: "#FF9F0A",
        steps: [
            .init(timeOffset: 0, channelA: .init(strength: 10, waveform: .sine, frequency: 5, pulseWidth: 100, durationMs: 60_000)),
            .init(timeOffset: 60_000, channelA: .init(strength: 20, waveform: .pulse(count: .single), frequency: 10, pulseWidth: 150, durationMs: 60_000)),
            .init(timeOffset: 120_000, channelA: .init(strength: 30, waveform: .pulse(count: .double), frequency: 15, pulseWidth: 200, durationMs: 60_000)),
            .init(timeOffset: 180_000, channelA: .init(strength: 20, waveform: .sine, frequency: 10, pulseWidth: 200, durationMs: 60_000))
        ],
        loopCount: 0,
        autoProgress: true,
        transitionSmoothness: 0.8
    )

    static let intervalTraining = Program(
        name: "Interval Training",
        icon: "stopwatch.fill",
        color: "#FF375F",
        steps: [
            .init(timeOffset: 0, channelA: .init(strength: 20, waveform: .sine, frequency: 10, pulseWidth: 150, durationMs: 30_000)),
            .init(timeOffset: 30_000, channelA: .init(strength: 60, waveform: .pulse(count: .quad), frequency: 35, pulseWidth: 250, durationMs: 15_000)),
            .init(timeOffset: 45_000, channelA: .init(strength: 15, waveform: .sine, frequency: 5, pulseWidth: 100, durationMs: 30_000)),
            .init(timeOffset: 75_000, channelA: .init(strength: 65, waveform: .pulse(count: .quad), frequency: 40, pulseWidth: 300, durationMs: 15_000))
        ],
        loopCount: 3,
        autoProgress: true,
        transitionSmoothness: 0.6,
        pauseBetweenSteps: 2_000
    )

    static let tensionScene = Program(
        name: "Tension Scene",
        icon: "theatermasks.fill",
        color: "#5E5CE6",
        steps: [
            .init(timeOffset: 0, channelA: .init(strength: 12, waveform: .breath, frequency: 8, pulseWidth: 55, durationMs: 45_000)),
            .init(timeOffset: 45_000, channelA: .init(strength: 18, waveform: .wave, frequency: 12, pulseWidth: 60, durationMs: 45_000), channelB: .init(strength: 10, waveform: .pulse(count: .single), frequency: 10, pulseWidth: 55, durationMs: 45_000)),
            .init(timeOffset: 90_000, channelA: .init(strength: 24, waveform: .glide, frequency: 16, pulseWidth: 65, durationMs: 60_000), channelB: .init(strength: 16, waveform: .rampUp, frequency: 14, pulseWidth: 60, durationMs: 60_000)),
            .init(timeOffset: 150_000, channelA: .init(strength: 20, waveform: .heartbeat, frequency: 14, pulseWidth: 58, durationMs: 30_000), channelB: .init(strength: 12, waveform: .breath, frequency: 10, pulseWidth: 55, durationMs: 30_000)),
            .init(timeOffset: 180_000, channelA: .init(strength: 30, waveform: .staircase, frequency: 18, pulseWidth: 70, durationMs: 45_000), channelB: .init(strength: 18, waveform: .alternating, frequency: 16, pulseWidth: 62, durationMs: 45_000)),
            .init(timeOffset: 225_000, channelA: .init(strength: 14, waveform: .breath, frequency: 8, pulseWidth: 55, durationMs: 45_000), channelB: .init(strength: 8, waveform: .wave, frequency: 8, pulseWidth: 50, durationMs: 45_000))
        ],
        loopCount: 2,
        autoProgress: true,
        transitionSmoothness: 0.9,
        pauseBetweenSteps: 1_500
    )

    static let allBuiltins: [Program] = [tensionScene, warmupProgression, intervalTraining]
}
