import XCTest
@testable import YCYEStim

final class HeartRateSafetyPolicyTests: XCTestCase {
    func testBelowElevatedKeepsFullStrength() {
        let policy = HeartRateSafetyPolicy(config: .default)

        let state = policy.evaluate(bpm: 90)

        XCTAssertEqual(state.strengthMultiplier, 1)
    }

    func testElevatedHeartRateReducesStrength() {
        let policy = HeartRateSafetyPolicy(config: .default)

        let state = policy.evaluate(bpm: 120)

        XCTAssertEqual(state.strengthMultiplier, 0.8)
    }

    func testHighHeartRateReducesStrengthMoreAggressively() {
        let policy = HeartRateSafetyPolicy(config: .default)

        let state = policy.evaluate(bpm: 140)

        XCTAssertEqual(state.strengthMultiplier, 0.5)
    }

    func testCriticalHeartRateCutsStrength() {
        let policy = HeartRateSafetyPolicy(config: .default)

        let state = policy.evaluate(bpm: 160)

        XCTAssertEqual(state.strengthMultiplier, 0)
    }

    func testMultiplierClampsToSafeRange() {
        let config = HeartRateSafetyConfig(
            isEnabled: true,
            baselineBPM: 75,
            elevatedBPM: 100,
            highBPM: 130,
            criticalBPM: 170,
            elevatedStrengthMultiplier: 1.5,
            highStrengthMultiplier: -0.2,
            emergencyStopOnCritical: true
        )
        let policy = HeartRateSafetyPolicy(config: config)

        XCTAssertEqual(policy.evaluate(bpm: 110).strengthMultiplier, 1)
        XCTAssertEqual(policy.evaluate(bpm: 140).strengthMultiplier, 0)
    }

    func testEdgeModeBuildsBelowTarget() {
        let policy = EdgeModePolicy(config: enabledEdgeConfig)

        let state = policy.evaluate(bpm: 90, currentStrength: 20)

        XCTAssertEqual(state, .building(bpm: 90, targetStrength: 23))
    }

    func testEdgeModeHoldsAtTarget() {
        let policy = EdgeModePolicy(config: enabledEdgeConfig)

        let state = policy.evaluate(bpm: 125, currentStrength: 32)

        XCTAssertEqual(state, .holding(bpm: 125, targetStrength: 32))
    }

    func testEdgeModeEasesAtPeak() {
        let policy = EdgeModePolicy(config: enabledEdgeConfig)

        let state = policy.evaluate(bpm: 145, currentStrength: 42)

        XCTAssertEqual(state, .easing(bpm: 145, targetStrength: 38))
    }

    func testEdgeModeStaysWithinConfiguredBounds() {
        let config = EdgeModeConfig(
            isEnabled: true,
            targetBPM: 120,
            peakBPM: 130,
            recoveryBPM: 95,
            minStrength: 10,
            maxStrength: 30,
            rampStep: 4,
            cooldownSeconds: 5
        )
        let policy = EdgeModePolicy(config: config)

        XCTAssertEqual(policy.evaluate(bpm: 80, currentStrength: 29), .building(bpm: 80, targetStrength: 30))
        XCTAssertEqual(policy.evaluate(bpm: 140, currentStrength: 12), .easing(bpm: 140, targetStrength: 10))
    }

    func testEdgeModeFrequencyTracksHeartRateWithinBounds() {
        let config = EdgeModeConfig(
            isEnabled: true,
            targetBPM: 120,
            peakBPM: 140,
            recoveryBPM: 100,
            minStrength: 10,
            maxStrength: 50,
            rampStep: 2,
            cooldownSeconds: 5,
            adjustsFrequency: true,
            frequencyFloor: 10,
            frequencyCeiling: 50
        )
        let policy = EdgeModePolicy(config: config)

        XCTAssertEqual(policy.targetFrequency(bpm: 90), 10, accuracy: 0.000001)
        XCTAssertEqual(policy.targetFrequency(bpm: 120), 30, accuracy: 0.000001)
        XCTAssertEqual(policy.targetFrequency(bpm: 150), 50, accuracy: 0.000001)
    }

    func testEdgeModeWaveformsFollowState() {
        let config = EdgeModeConfig(
            isEnabled: true,
            targetBPM: 120,
            peakBPM: 140,
            recoveryBPM: 100,
            minStrength: 10,
            maxStrength: 50,
            rampStep: 2,
            cooldownSeconds: 5,
            adjustsWaveform: true,
            buildingWaveform: .wave,
            holdingWaveform: .heartbeat,
            easingWaveform: .breath
        )
        let policy = EdgeModePolicy(config: config)

        XCTAssertEqual(policy.targetWaveform(for: .building(bpm: 90, targetStrength: 20)), .wave)
        XCTAssertEqual(policy.targetWaveform(for: .holding(bpm: 125, targetStrength: 20)), .heartbeat)
        XCTAssertEqual(policy.targetWaveform(for: .easing(bpm: 145, targetStrength: 20)), .breath)
    }

    func testWaveformWaveHasCleanAlternatingShape() async {
        let points = await WaveformEngine().generate(.wave, samples: 9, frequency: 20)

        XCTAssertEqual(points[0], 0, accuracy: 0.000001)
        XCTAssertEqual(points[1], 1, accuracy: 0.000001)
        XCTAssertEqual(points[3], -1, accuracy: 0.000001)
        XCTAssertEqual(points[5], 1, accuracy: 0.000001)
        XCTAssertEqual(points[7], -1, accuracy: 0.000001)
    }

    func testWaveformEchoDecaysOverTime() async {
        let points = await WaveformEngine().generate(.echo, samples: 25, frequency: 20)

        XCTAssertGreaterThan(abs(points[1]), abs(points[23]))
        XCTAssertTrue(points.allSatisfy { (-1...1).contains($0) })
    }

    func testPlacementPolicyCapsSensitiveLocations() {
        let policy = PlacementOutputPolicy(heartRateConfig: .default)
        let channel = ChannelState(
            id: .a,
            isEnabled: true,
            strength: 80,
            waveform: .square,
            frequency: 45,
            pulseWidth: 200,
            placement: .penis
        )

        let output = policy.adapted(channel, bpm: nil, adaptiveStrengthLimit: 100)

        XCTAssertEqual(output.strength, 29.44, accuracy: 0.000001)
        XCTAssertEqual(output.frequency, 20.416, accuracy: 0.000001)
        XCTAssertEqual(output.pulseWidth, 50)
        XCTAssertEqual(output.waveform, .wave)
    }

    func testPlacementPolicyUsesHeartRateLoad() {
        let policy = PlacementOutputPolicy(heartRateConfig: .default)
        let channel = ChannelState(
            id: .a,
            isEnabled: true,
            strength: 50,
            waveform: .glide,
            frequency: 30,
            pulseWidth: 90,
            placement: .innerThigh
        )

        let output = policy.adapted(channel, bpm: 140, adaptiveStrengthLimit: 100)

        XCTAssertEqual(output.strength, 26.8163808, accuracy: 0.000001)
        XCTAssertEqual(output.frequency, 23.113728, accuracy: 0.000001)
        XCTAssertEqual(output.pulseWidth, 48)
        XCTAssertEqual(output.waveform, .breath)
    }

    func testChannelStateDecodesMissingPlacementAsGeneralPadsForBothPads() throws {
        let data = #"{"id":"A"}"#.data(using: .utf8)!

        let channel = try JSONDecoder().decode(ChannelState.self, from: data)

        XCTAssertEqual(channel.placement, .generalPads)
        XCTAssertEqual(channel.pad1Placement, .generalPads)
        XCTAssertEqual(channel.pad2Placement, .generalPads)
    }

    func testChannelStateDecodesLegacyPlacementIntoBothPads() throws {
        let data = #"{"id":"A","placement":"Penis"}"#.data(using: .utf8)!

        let channel = try JSONDecoder().decode(ChannelState.self, from: data)

        XCTAssertEqual(channel.pad1Placement, .penis)
        XCTAssertEqual(channel.pad2Placement, .penis)
    }

    private var enabledEdgeConfig: EdgeModeConfig {
        var config = EdgeModeConfig.default
        config.isEnabled = true
        return config
    }
}
