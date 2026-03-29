import CoreAudio
import XCTest

@testable import VolumeGrid

@MainActor
final class LoudnessNormalizerTests: XCTestCase {

    // MARK: - Initialization guard

    func testUpdateReturnsNilBeforeReset() {
        var normalizer = LoudnessNormalizer()
        let result = normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2)
        XCTAssertNil(result, "update() must return nil until resetWith() has been called")
    }

    func testUpdateReturnsNonNilAfterReset() {
        var normalizer = LoudnessNormalizer()
        normalizer.resetWith(currentVolume: 0.5)
        // measuredRMS=0.15 → perceivedRMS=0.15 > default targetRMSHigh=0.090 → outside zone
        let result = normalizer.update(measuredRMS: 0.15, currentVolume: 1.0, dt: 0.2)
        XCTAssertNotNil(result)
    }

    func testResetMakesUpdateReturnNilAgain() {
        var normalizer = LoudnessNormalizer()
        normalizer.resetWith(currentVolume: 0.5)
        normalizer.reset()
        XCTAssertNil(normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2))
    }

    // MARK: - Silence guard

    func testSilentSignalReturnsNil() {
        var normalizer = LoudnessNormalizer()  // default targetRMSLow = 0.020, gate = 0.004
        normalizer.resetWith(currentVolume: 0.5)
        XCTAssertNil(normalizer.update(measuredRMS: 0, currentVolume: 1.0, dt: 0.2))
        XCTAssertNil(normalizer.update(measuredRMS: 1e-6, currentVolume: 1.0, dt: 0.2))
        XCTAssertNil(normalizer.update(measuredRMS: 1e-5, currentVolume: 1.0, dt: 0.2))
        // below noise gate (0.004) even though above the bare epsilon
        XCTAssertNil(normalizer.update(measuredRMS: 0.003, currentVolume: 1.0, dt: 0.2))
    }

    func testJustAboveSilenceThresholdIsNotNil() {
        var normalizer = LoudnessNormalizer()  // default targetRMSLow = 0.020, gate = 0.004
        normalizer.resetWith(currentVolume: 0.5)
        // noise gate = targetRMSLow * 0.2 = 0.004; signal at 0.011 exceeds gate
        // and perceivedRMS = 0.011 < targetRMSLow = 0.020 → outside zone → non-nil
        XCTAssertNotNil(normalizer.update(measuredRMS: 0.011, currentVolume: 1.0, dt: 0.2))
    }

    /// Regression guard: noise gate uses pre-volume measuredRMS, not perceivedRMS.
    /// When currentVolume is very low, content that IS playing must still pass the gate
    /// so the AGC can raise volume back to a listenable level.
    func testNoisegateDoesNotBlockRecoveryAtLowVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.040
        normalizer.minVolumeScalar = 0.05
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.05)
        // measuredRMS = 0.1 (content IS audible) but perceivedRMS = 0.1 × 0.05 = 0.005,
        // which is below targetRMSLow (too quiet for perceived scale).
        // Gate = targetRMSLow * 0.2 = 0.008; measuredRMS = 0.1 >> 0.008 → passes gate.
        let result = normalizer.update(measuredRMS: 0.1, currentVolume: 0.05, dt: 0.2)
        XCTAssertNotNil(result, "AGC must not be gated by low volume when content is playing")
        XCTAssertGreaterThan(result!, 0.05, "AGC should raise volume toward target")
    }

    // MARK: - Boundary clamping

    func testOutputClampedToMinVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.0005
        normalizer.targetRMSHigh = 0.001  // very small upper bound → loud signal drives volume down
        normalizer.minVolumeScalar = 0.2
        normalizer.maxVolumeScalar = 1.0
        normalizer.attackSeconds = 0.1  // fast attack so 200 ticks are enough to converge
        normalizer.resetWith(currentVolume: 1.0)
        // Run many steps to approach the floor
        var result: Float = 1.0
        for _ in 0..<200 {
            result = normalizer.update(measuredRMS: 0.1, currentVolume: 1.0, dt: 0.2) ?? result
        }
        XCTAssertGreaterThanOrEqual(result, 0.2)
    }

    func testOutputClampedToMaxVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.5  // large lower bound → quiet signal drives volume up
        normalizer.targetRMSHigh = 0.8
        normalizer.minVolumeScalar = 0.1
        normalizer.maxVolumeScalar = 0.8
        normalizer.resetWith(currentVolume: 0.5)
        // measuredRMS=0.3 → perceivedRMS=0.3 < targetRMSLow=0.5 → too quiet → release toward 0.8
        var result: Float = 0.5
        for _ in 0..<200 {
            result = normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2) ?? result
        }
        XCTAssertLessThanOrEqual(result, 0.8)
    }

    // MARK: - IIR convergence

    func testIIRConvergesToTarget() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.10  // zone well above measuredRMS → always "too quiet"
        normalizer.targetRMSHigh = 0.20
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        // measuredRMS=0.05, currentVolume=1.0 → perceivedRMS=0.05 < targetRMSLow=0.10
        // rawTarget=2.0 → desiredVolume=2.0 → effectiveTarget=min(2.0, maxVol=1.0)=1.0
        // IIR converges to 1.0 from 0.3
        normalizer.resetWith(currentVolume: 0.3)
        var result: Float = 0.3
        for _ in 0..<500 {
            result = normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2) ?? result
        }
        // After 500 × 0.2 s = 100 s with releaseSeconds = 5 s, should be very close to 1.0
        XCTAssertEqual(result, 1.0, accuracy: 0.01)
    }

    func testAttackFasterThanRelease() {
        var attackNorm = LoudnessNormalizer()
        attackNorm.targetRMSHigh = 0.10  // measuredRMS=0.4 → perceivedRMS=0.4 > 0.10 → attack
        attackNorm.targetRMSLow = 0.001
        attackNorm.attackSeconds = 0.5
        attackNorm.releaseSeconds = 5.0
        attackNorm.minVolumeScalar = 0.0
        attackNorm.maxVolumeScalar = 2.0
        attackNorm.resetWith(currentVolume: 0.5)

        var releaseNorm = LoudnessNormalizer()
        releaseNorm.targetRMSLow = 0.08  // measuredRMS=0.04 → perceivedRMS=0.04 < 0.08 → release
        releaseNorm.targetRMSHigh = 0.50
        releaseNorm.attackSeconds = 0.5
        releaseNorm.releaseSeconds = 5.0
        releaseNorm.minVolumeScalar = 0.0
        releaseNorm.maxVolumeScalar = 2.0
        releaseNorm.resetWith(currentVolume: 0.5)

        // rawTarget_attack = 0.10/0.4 = 0.25 → desiredVolume = 0.25 < 0.5 → fast attack path
        let attackResult = attackNorm.update(measuredRMS: 0.4, currentVolume: 1.0, dt: 0.2)!
        // rawTarget_release = 0.08/0.04 = 2.0 → desiredVolume = 2.0 > 0.5 → slow release path
        let releaseResult = releaseNorm.update(measuredRMS: 0.04, currentVolume: 1.0, dt: 0.2)!

        let attackMovement = abs(attackResult - 0.5)
        let releaseMovement = abs(releaseResult - 0.5)
        XCTAssertGreaterThan(
            attackMovement, releaseMovement,
            "Attack (fast) should move more than release (slow) per step")
    }

    func testHoldFreezesVolumeAfterLoudSignal() {
        // With holdSeconds = 1.0, a quiet signal following a loud one must NOT raise
        // volume until the hold timer expires (Attack-Hold-Release behaviour).
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSHigh = 0.10  // measuredRMS=0.3 → perceivedRMS=0.3 > 0.10 → attack
        normalizer.targetRMSLow = 0.05  // measuredRMS=0.02 → perceivedRMS=0.02 < 0.05 → release
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.holdSeconds = 1.0
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.5)

        // Two attack ticks with a loud signal; holdCountdown is reset to 1.0 after each.
        _ = normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)
        let volAfterAttack = normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)!

        // 4 quiet ticks × 0.2 s = 0.8 s — volume must stay frozen during the hold.
        // With holdSeconds = 1.0 and pre-tick decrement, hold expires exactly at t = 1.0 s
        // (the 5th quiet tick), so only 4 ticks are within the freeze window.
        for _ in 0..<4 {
            let v =
                normalizer.update(measuredRMS: 0.02, currentVolume: 1.0, dt: 0.2) ?? volAfterAttack
            XCTAssertEqual(v, volAfterAttack, accuracy: 1e-4, "volume must not rise during hold")
        }

        // 5th quiet tick: t = 1.0 s elapsed since last attack → hold expires, release resumes.
        let volAfterHold = normalizer.update(measuredRMS: 0.02, currentVolume: 1.0, dt: 0.2)!
        XCTAssertGreaterThan(
            volAfterHold, volAfterAttack, "volume must start rising once hold expires")
    }

    func testHoldCountdownAdvancesDuringInZoneTicks() {
        // Regression test: hold timer must count down on in-zone ticks (return nil path) so
        // that a later quiet signal doesn't wait an extra full holdSeconds beyond the zone exit.
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSHigh = 0.10
        normalizer.targetRMSLow = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.holdSeconds = 1.0
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.5)

        // One attack tick: holdCountdown set to 1.0.
        _ = normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)

        // 4 in-zone ticks × 0.2 s = 0.8 s — hold should be nearly expired (≈ 0.2 s remaining).
        for _ in 0..<4 {
            XCTAssertNil(
                normalizer.update(measuredRMS: 0.07, currentVolume: 1.0, dt: 0.2),
                "in-zone tick should return nil")
        }

        // One more in-zone tick exhausts the hold (5 × 0.2 = 1.0 s total since attack).
        XCTAssertNil(
            normalizer.update(measuredRMS: 0.07, currentVolume: 1.0, dt: 0.2),
            "in-zone tick after hold expires should still return nil")

        // Immediately after zone exit, the first quiet tick must release without any further wait.
        let volAtRelease = normalizer.update(measuredRMS: 0.02, currentVolume: 1.0, dt: 0.2)
        XCTAssertNotNil(
            volAtRelease,
            "first quiet tick after in-zone hold should immediately start release")
    }

    // MARK: - Strength (compression ratio)

    func testStrengthZeroReturnsNil() {
        // strength=0 means "no correction" — update() returns nil so the coordinator
        // skips writing volume and does not override manual adjustments.
        var normalizer = LoudnessNormalizer()
        // default targetRMSLow=0.020, targetRMSHigh=0.090, gate=0.004
        normalizer.strength = 0.0
        normalizer.resetWith(currentVolume: 0.5)
        // Loud signal → outside zone (above high); with strength=0 must return nil.
        XCTAssertNil(normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2))
        // Quiet signal above noise gate (0.005 > 0.004) and below low → outside zone; still nil.
        XCTAssertNil(normalizer.update(measuredRMS: 0.005, currentVolume: 1.0, dt: 0.2))
    }

    func testStrengthOneIsFull() {
        // strength=1 must use the full unscaled rawTarget (no compression).
        // measuredRMS=0.2, currentVolume=1.0 → perceivedRMS=0.2 > targetRMSHigh=0.05
        // rawTarget = 0.05/0.2 = 0.25 (attack path from smoothedTargetVolume=0.8)
        // alpha = 1 - exp(-0.2/0.5) ≈ 0.3297; step ≈ 0.3297*(0.25-0.8) ≈ -0.1813.
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSHigh = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 2.0
        normalizer.strength = 1.0
        normalizer.resetWith(currentVolume: 0.8)
        let r = normalizer.update(measuredRMS: 0.2, currentVolume: 1.0, dt: 0.2)!
        let expectedAlpha = 1 - expf(-0.2 / 0.5)
        let expected = 0.8 + expectedAlpha * (0.25 - 0.8)
        XCTAssertEqual(
            r, expected, accuracy: 1e-5, "strength=1.0 must equal the uncompressed IIR step")
    }

    func testStrengthHalfReducesCorrection() {
        // With strength<1, the gain correction toward a rawTarget < 1 (loud signal)
        // should be less aggressive than with strength=1.
        var full = LoudnessNormalizer()
        full.targetRMSHigh = 0.05
        full.strength = 1.0
        full.attackSeconds = 0.5
        full.minVolumeScalar = 0.0
        full.maxVolumeScalar = 2.0
        full.resetWith(currentVolume: 0.8)

        var half = LoudnessNormalizer()
        half.targetRMSHigh = 0.05
        half.strength = 0.5
        half.attackSeconds = 0.5
        half.minVolumeScalar = 0.0
        half.maxVolumeScalar = 2.0
        half.resetWith(currentVolume: 0.8)

        // Loud signal: perceivedRMS=0.3 > targetRMSHigh=0.05 → rawTarget=0.05/0.3≈0.167 < 0.8 → attack direction.
        // strength=0.5 → correctedTarget = sqrt(0.167) ≈ 0.408 (less aggressive).
        let rFull = full.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)!
        let rHalf = half.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)!
        // rHalf should be larger (less reduction) than rFull.
        XCTAssertGreaterThan(rHalf, rFull, "strength=0.5 should reduce volume less than strength=1")
    }

    // MARK: - resetWith prevents first-frame jump

    func testResetWithSeedsFromCurrentVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.2)
        // measuredRMS=0.15 → perceivedRMS=0.15 > default targetRMSHigh=0.090 → outside zone
        // First update — IIR starts from 0.2, so the result should still be near 0.2
        let first = normalizer.update(measuredRMS: 0.15, currentVolume: 1.0, dt: 0.2)
        XCTAssertNotNil(first)
        XCTAssertEqual(
            first!, 0.2, accuracy: 0.05, "First step should be a small nudge, not a big jump")
    }

    // MARK: - Anti-windup

    func testAntiWindupPreventsSlowRecovery() {
        // Without anti-windup, 50 ticks of dead-silent content would wind smoothedTargetVolume
        // up toward maxVolumeScalar. When loud content arrives (rawTarget drops to 0.2),
        // the attack should respond within a few ticks, not dozens.
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSHigh = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.minVolumeScalar = 0.1
        normalizer.maxVolumeScalar = 0.8
        normalizer.resetWith(currentVolume: 0.5)

        // 50 quiet ticks — measuredRMS below noise gate so all return nil; IIR stays put
        for _ in 0..<50 {
            _ = normalizer.update(measuredRMS: 0.001, currentVolume: 1.0, dt: 0.2)
        }

        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.attackSeconds = 0.1  // fast attack for test speed

        // Loud signal: perceivedRMS=0.25 > targetRMSHigh=0.05 → rawTarget = 0.05/0.25 = 0.2
        var vol: Float = 1.0
        let loudRMS: Float = 0.05 / 0.2  // rawTarget = 0.2
        for _ in 0..<5 {
            vol = normalizer.update(measuredRMS: loudRMS, currentVolume: 1.0, dt: 0.2) ?? vol
        }
        XCTAssertLessThan(
            vol, 0.5,
            "With anti-windup, loud signal should drive volume down quickly from wound-up state")
    }

    // MARK: - Dead zone behaviour

    func testInsideComfortZoneReturnsNil() {
        // perceivedRMS inside [targetRMSLow, targetRMSHigh] → AGC is silent (nil)
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.020
        normalizer.targetRMSHigh = 0.090
        normalizer.resetWith(currentVolume: 1.0)
        // perceivedRMS = 0.050 × 1.0 = 0.050 ∈ [0.020, 0.090] → inside zone
        XCTAssertNil(
            normalizer.update(measuredRMS: 0.050, currentVolume: 1.0, dt: 0.2),
            "update() must return nil when perceivedRMS is inside the comfort zone")
    }

    func testAboveHighBoundReducesVolume() {
        // perceivedRMS > targetRMSHigh → too loud → AGC lowers volume
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.020
        normalizer.targetRMSHigh = 0.050
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.8)
        // perceivedRMS = 0.20 × 1.0 = 0.20 > 0.050 → too loud → attack
        let result = normalizer.update(measuredRMS: 0.20, currentVolume: 1.0, dt: 0.2)!
        XCTAssertLessThan(
            result, 0.8, "AGC should lower volume when signal is above the high bound")
    }

    func testBelowLowBoundRaisesVolume() {
        // perceivedRMS < targetRMSLow → too quiet → AGC raises volume
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMSLow = 0.050
        normalizer.targetRMSHigh = 0.15
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.5)
        // noiseGate = 0.050 * 0.2 = 0.010; measuredRMS=0.030 > gate ✓
        // perceivedRMS = 0.030 × 0.5 = 0.015 < targetRMSLow=0.050 → too quiet → release
        let result = normalizer.update(measuredRMS: 0.030, currentVolume: 0.5, dt: 0.2)!
        XCTAssertGreaterThan(
            result, 0.5, "AGC should raise volume when signal is below the low bound")
    }
}

@MainActor
final class SmartVolumeSettingsTests: XCTestCase {

    func testDefaultsAreLoaded() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.targetRMSLow, 0.020, accuracy: 1e-6)
        XCTAssertEqual(settings.targetRMSHigh, 0.090, accuracy: 1e-6)
        XCTAssertEqual(settings.minVolume, 0.1, accuracy: 1e-6)
        XCTAssertEqual(settings.maxVolume, 1.0, accuracy: 1e-6)
        ud.removePersistentDomain(forName: suiteName)
    }

    // MARK: - init invariant enforcement

    func testInitWithInvertedMinMax_ClampsMaxToMin() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.set(Float(0.8), forKey: "smartVolume.minVolume")
        ud.set(Float(0.2), forKey: "smartVolume.maxVolume")
        let settings = SmartVolumeSettings(ud)
        XCTAssertEqual(settings.minVolume, 0.8, accuracy: 1e-6)
        XCTAssertEqual(
            settings.maxVolume, 0.8, accuracy: 1e-6,
            "max should be clamped to min when stored inverted")
        ud.removePersistentDomain(forName: suiteName)
    }

    func testInitWithNormalValues_Preserved() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.set(Float(0.2), forKey: "smartVolume.minVolume")
        ud.set(Float(0.8), forKey: "smartVolume.maxVolume")
        let settings = SmartVolumeSettings(ud)
        XCTAssertEqual(settings.minVolume, 0.2, accuracy: 1e-6)
        XCTAssertEqual(settings.maxVolume, 0.8, accuracy: 1e-6)
        ud.removePersistentDomain(forName: suiteName)
    }

    // MARK: - setter invariant enforcement

    func testSetterMinVolume_PushesMaxUp() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.maxVolume = 0.5
        settings.minVolume = 0.8
        XCTAssertGreaterThanOrEqual(
            settings.maxVolume, settings.minVolume,
            "maxVolume must be >= minVolume after setter")
        XCTAssertEqual(settings.maxVolume, 0.8, accuracy: 1e-6)
        ud.removePersistentDomain(forName: suiteName)
    }

    func testSetterMaxVolume_PullsMinDown() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.minVolume = 0.7
        settings.maxVolume = 0.3
        XCTAssertLessThanOrEqual(
            settings.minVolume, settings.maxVolume,
            "minVolume must be <= maxVolume after setter")
        XCTAssertEqual(settings.minVolume, 0.3, accuracy: 1e-6)
        ud.removePersistentDomain(forName: suiteName)
    }

    // MARK: - smoothing range clamping

    func testSetterSmoothing_ClampsToUnitInterval() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.smoothing = 1.5
        XCTAssertEqual(settings.smoothing, 1.0, accuracy: 1e-6, "smoothing > 1 should clamp to 1")
        settings.smoothing = -0.5
        XCTAssertEqual(settings.smoothing, 0.0, accuracy: 1e-6, "smoothing < 0 should clamp to 0")
        ud.removePersistentDomain(forName: suiteName)
    }

    // MARK: - derived time constant properties

    func testAttackSecondsAtSmoothing0() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.smoothing = 0.0
        XCTAssertEqual(settings.attackSeconds, 0.5, accuracy: 1e-4)
        ud.removePersistentDomain(forName: suiteName)
    }

    func testAttackSecondsAtSmoothing1() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.smoothing = 1.0
        XCTAssertEqual(settings.attackSeconds, 5.0, accuracy: 1e-4)
        ud.removePersistentDomain(forName: suiteName)
    }

    func testReleaseSecondsAtSmoothing0() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.smoothing = 0.0
        XCTAssertEqual(settings.releaseSeconds, 3.0, accuracy: 1e-4)
        ud.removePersistentDomain(forName: suiteName)
    }

    func testReleaseSecondsAtSmoothing1() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.smoothing = 1.0
        XCTAssertEqual(settings.releaseSeconds, 12.0, accuracy: 1e-4)
        ud.removePersistentDomain(forName: suiteName)
    }

    func testSetterStrength_ClampsToUnitInterval() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.strength = 1.5
        XCTAssertEqual(settings.strength, 1.0, accuracy: 1e-6, "strength > 1 should clamp to 1")
        settings.strength = -0.5
        XCTAssertEqual(settings.strength, 0.0, accuracy: 1e-6, "strength < 0 should clamp to 0")
        ud.removePersistentDomain(forName: suiteName)
    }

    func testTargetRMSLow_ClampedAboveZero() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        // A negative value written via defaults write must not corrupt the normalizer.
        ud.set(Float(-0.1), forKey: "smartVolume.targetRMSLow")
        // Trigger a live reload by posting the didChange notification directly.
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification, object: ud)
        // Allow the async Task inside the observer to execute.
        await Task.yield()
        await Task.yield()
        XCTAssertGreaterThan(
            settings.targetRMSLow, 0, "targetRMSLow must never be zero or negative")
        ud.removePersistentDomain(forName: suiteName)
    }

    func testTargetRMSBounds_ClampedToMaximum() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.targetRMSLow = 5.0
        XCTAssertEqual(
            settings.targetRMSLow, 0.30, accuracy: 1e-6,
            "targetRMSLow > 0.30 should clamp to maximum")
        settings.targetRMSHigh = 5.0
        XCTAssertEqual(
            settings.targetRMSHigh, 0.30, accuracy: 1e-6,
            "targetRMSHigh > 0.30 should clamp to maximum")
        ud.removePersistentDomain(forName: suiteName)
    }

    func testReloadFromDefaultsUsesDeadzoneFallback() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        // Create fresh settings; keys are not yet written to this suite.
        let settings = SmartVolumeSettings(ud)
        // Confirm fresh-init values are deadzone defaults.
        XCTAssertEqual(settings.targetRMSLow, 0.020, accuracy: 1e-5)
        XCTAssertEqual(settings.targetRMSHigh, 0.090, accuracy: 1e-5)
        // Remove any persisted keys so reload falls through to the fallback path.
        ud.removeObject(forKey: "smartVolume.targetRMSLow")
        ud.removeObject(forKey: "smartVolume.targetRMSHigh")
        ud.removeObject(forKey: "smartVolume.rmsVersion")
        // Trigger reloadFromDefaults via notification.
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: ud)
        await Task.yield()
        await Task.yield()
        // Values must stay at deadzone defaults.
        XCTAssertEqual(
            settings.targetRMSLow, 0.020, accuracy: 1e-5,
            "reloadFromDefaults fallback must use deadzone default 0.020")
        XCTAssertEqual(
            settings.targetRMSHigh, 0.090, accuracy: 1e-5,
            "reloadFromDefaults fallback must use deadzone default 0.090")
        ud.removePersistentDomain(forName: suiteName)
    }

    func testMigrationFromOldVersionResetsToDeadzoneDefaults() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        // Simulate old kweighted version with stale targetRMS keys.
        ud.set(Float(0.065), forKey: "smartVolume.targetRMS")
        ud.set("kweighted_perceived_v2", forKey: "smartVolume.rmsVersion")
        let settings = SmartVolumeSettings(ud)
        // Values must reset to new deadzone defaults since version != "deadzone_v1".
        XCTAssertEqual(settings.targetRMSLow, 0.020, accuracy: 1e-6)
        XCTAssertEqual(settings.targetRMSHigh, 0.090, accuracy: 1e-6)
        // Version tag must be bumped to current.
        XCTAssertEqual(
            ud.string(forKey: "smartVolume.rmsVersion"), "deadzone_v1",
            "version must be updated to deadzone_v1 after migration")
        ud.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Per-device calibration

    func testSaveCalibrationPersistsToUserDefaults() {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        let uid = "BuiltInSpeakerDevice"
        let cal = SmartVolumeSettings.DeviceCalibration(targetRMSLow: 0.020, targetRMSHigh: 0.070)
        settings.saveCalibration(cal, forDeviceUID: uid)

        // Value must be readable back via calibration(forDeviceUID:).
        guard let loaded = settings.calibration(forDeviceUID: uid) else {
            return XCTFail("expected non-nil calibration after save")
        }
        XCTAssertEqual(loaded.targetRMSLow, Float(0.020), accuracy: Float(1e-6))
        XCTAssertEqual(loaded.targetRMSHigh, Float(0.070), accuracy: Float(1e-6))

        // A second SmartVolumeSettings instance (simulating app relaunch) must also see
        // the persisted calibration from UserDefaults.
        let settings2 = SmartVolumeSettings(ud)
        guard let reloaded = settings2.calibration(forDeviceUID: uid) else {
            return XCTFail("calibration must survive round-trip through UserDefaults")
        }
        XCTAssertEqual(reloaded.targetRMSLow, Float(0.020), accuracy: Float(1e-6))
        XCTAssertEqual(reloaded.targetRMSHigh, Float(0.070), accuracy: Float(1e-6))
        ud.removePersistentDomain(forName: suiteName)
    }

    func testCalibrationForUnknownDeviceReturnsNil() {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        XCTAssertNil(settings.calibration(forDeviceUID: "NoSuchDevice-XYZ"))
        ud.removePersistentDomain(forName: suiteName)
    }

    func testMultipleDevicesCalibratedIndependently() {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.saveCalibration(
            SmartVolumeSettings.DeviceCalibration(targetRMSLow: 0.015, targetRMSHigh: 0.060),
            forDeviceUID: "HeadphonesUID"
        )
        settings.saveCalibration(
            SmartVolumeSettings.DeviceCalibration(targetRMSLow: 0.030, targetRMSHigh: 0.120),
            forDeviceUID: "ExternalSpeakerUID"
        )
        XCTAssertEqual(
            settings.calibration(forDeviceUID: "HeadphonesUID")?.targetRMSLow ?? -1, Float(0.015),
            accuracy: Float(1e-6))
        XCTAssertEqual(
            settings.calibration(forDeviceUID: "ExternalSpeakerUID")?.targetRMSHigh ?? -1,
            Float(0.120), accuracy: Float(1e-6))
        ud.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - AudioTapMonitor RMS tests

@available(macOS 14.2, *)
@MainActor
final class AudioTapMonitorRMSTests: XCTestCase {

    // MARK: - Mono

    func testMonoBufferRMSIsCorrect() {
        let frameCount = 8
        var samples = [Float32](repeating: 0.6, count: frameCount)
        samples.withUnsafeMutableBytes { rawPtr in
            var abl = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(rawPtr.count),
                    mData: rawPtr.baseAddress
                )
            )
            withUnsafePointer(to: &abl) { ablPtr in
                let (rms, fc) = AudioTapMonitor.measureRMSRealtime(bufferList: ablPtr)
                XCTAssertEqual(rms, 0.6, accuracy: 0.001)
                XCTAssertEqual(fc, frameCount)
            }
        }
    }

    // MARK: - Interleaved stereo

    func testInterleavedStereo_AveragesChannels() {
        // Left = 1.0, Right = 0.0 → RMS_L = 1.0, RMS_R = 0.0, mean = 0.5
        let frameCount = 4
        var samples: [Float32] = (0..<frameCount).flatMap { _ in [Float32(1.0), Float32(0.0)] }
        samples.withUnsafeMutableBytes { rawPtr in
            var abl = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(rawPtr.count),
                    mData: rawPtr.baseAddress
                )
            )
            withUnsafePointer(to: &abl) { ablPtr in
                let (rms, fc) = AudioTapMonitor.measureRMSRealtime(bufferList: ablPtr)
                XCTAssertEqual(
                    rms, 0.5, accuracy: 0.001, "avg of RMS_L=1.0 and RMS_R=0.0 should be 0.5")
                XCTAssertEqual(fc, frameCount)
            }
        }
    }

    // MARK: - Non-interleaved stereo

    func testNonInterleavedStereo_AveragesBuffers() {
        // Buffer 0 (L) = all 1.0, Buffer 1 (R) = all 0.0 → mean = 0.5
        let frameCount = 4
        var lSamples = [Float32](repeating: 1.0, count: frameCount)
        var rSamples = [Float32](repeating: 0.0, count: frameCount)
        lSamples.withUnsafeMutableBytes { lRaw in
            rSamples.withUnsafeMutableBytes { rRaw in
                let ablPtr = AudioBufferList.allocate(maximumBuffers: 2)
                defer { ablPtr.unsafeMutablePointer.deallocate() }
                ablPtr.count = 2
                ablPtr[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(lRaw.count),
                    mData: lRaw.baseAddress
                )
                ablPtr[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(rRaw.count),
                    mData: rRaw.baseAddress
                )
                let (rms, fc) = AudioTapMonitor.measureRMSRealtime(
                    bufferList: UnsafePointer(ablPtr.unsafeMutablePointer))
                XCTAssertEqual(rms, 0.5, accuracy: 0.001)
                XCTAssertEqual(fc, frameCount)
            }
        }
    }

    // MARK: - Edge cases

    func testEmptyABL_ReturnsZero() {
        var abl = AudioBufferList(
            mNumberBuffers: 0,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        withUnsafePointer(to: &abl) { ablPtr in
            let (rms, fc) = AudioTapMonitor.measureRMSRealtime(bufferList: ablPtr)
            XCTAssertEqual(rms, 0.0)
            XCTAssertEqual(fc, 0)
        }
    }

    func testZeroByteBuffer_IsSkipped() {
        var samples = [Float32](repeating: 1.0, count: 4)
        samples.withUnsafeMutableBytes { rawPtr in
            var abl = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: 0, mData: rawPtr.baseAddress)
            )
            withUnsafePointer(to: &abl) { ablPtr in
                let (rms, _) = AudioTapMonitor.measureRMSRealtime(bufferList: ablPtr)
                XCTAssertEqual(rms, 0.0, "buffer with mDataByteSize=0 should be skipped")
            }
        }
    }

    // MARK: - drainMetrics freshness

    func testDrainMetricsBeforeDataReturnsNil() {
        let monitor = AudioTapMonitor()
        XCTAssertNil(
            monitor.drainMetrics(), "drainMetrics() must return nil before any IO callback fires")
    }
}

// MARK: - VolumeKeyEffect tests

@MainActor
final class VolumeKeyEffectTests: XCTestCase {
    private let step = Float(1.0) / Float(VolumeGridConstants.volumeBlocksCount)

    // MARK: - At ceiling

    func testAtCeilingUpRaisesCeiling() {
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.5, activeMax: 0.5, minVolume: 0.1)
        XCTAssertEqual(effect.newMax ?? 0, 0.5 + step, accuracy: 1e-5)
        XCTAssertEqual(effect.seedVolume, 0.5 + step, accuracy: 1e-5)
    }

    func testAtCeilingDownLowersCeiling() {
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.5, activeMax: 0.5, minVolume: 0.1)
        XCTAssertEqual(effect.newMax ?? 0, 0.5 - step, accuracy: 1e-5)
        XCTAssertEqual(effect.seedVolume, 0.5 - step, accuracy: 1e-5)
    }

    func testAtCeilingUpClampedAtOne() {
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 1.0, activeMax: 1.0, minVolume: 0.1)
        XCTAssertEqual(effect.newMax ?? 0, 1.0, accuracy: 1e-5, "ceiling must not exceed 1.0")
        XCTAssertEqual(effect.seedVolume, 1.0, accuracy: 1e-5)
    }

    func testAtCeilingDownClampedAtMinVolume() {
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.1, activeMax: 0.1, minVolume: 0.1)
        XCTAssertEqual(
            effect.newMax ?? 0, 0.1, accuracy: 1e-5, "ceiling must not fall below minVolume")
        XCTAssertEqual(effect.seedVolume, 0.1, accuracy: 1e-5)
    }

    // MARK: - Mid-range

    func testBelowCeilingUpKeepsCeiling() {
        // vol=0.3 is well below ceiling=0.5: ceiling must stay, seedVolume advances by step.
        let desiredVolume = min(0.5, 0.3 + step)
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.3, activeMax: 0.5, minVolume: 0.1)
        XCTAssertNil(effect.newMax, "ceiling must not change when vol is below ceiling")
        XCTAssertEqual(effect.seedVolume, desiredVolume, accuracy: 1e-5)
    }

    func testBelowCeilingDownKeepsCeiling() {
        let desiredVolume = max(0.1, 0.3 - step)
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.3, activeMax: 0.5, minVolume: 0.1)
        XCTAssertNil(effect.newMax, "ceiling must not change when vol is below ceiling")
        XCTAssertEqual(effect.seedVolume, desiredVolume, accuracy: 1e-5)
    }

    // MARK: - desiredVolume boundary clamping

    func testMidRangeUp_desiredVolumeClampedToActiveMax() {
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.44, activeMax: 0.5, minVolume: 0.1)
        XCTAssertNil(effect.newMax, "ceiling must not change")
        XCTAssertEqual(effect.seedVolume, 0.5, accuracy: 1e-5, "desiredVolume clamped to activeMax")
    }

    func testMidRangeDown_desiredVolumeClampedToMinVolume() {
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.15, activeMax: 0.5, minVolume: 0.1)
        XCTAssertNil(effect.newMax, "ceiling must not change")
        XCTAssertEqual(effect.seedVolume, 0.1, accuracy: 1e-5, "desiredVolume clamped to minVolume")
    }
}
