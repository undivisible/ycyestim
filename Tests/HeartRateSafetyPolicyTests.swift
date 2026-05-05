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

    private var enabledEdgeConfig: EdgeModeConfig {
        var config = EdgeModeConfig.default
        config.isEnabled = true
        return config
    }
}
