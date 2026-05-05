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
}
