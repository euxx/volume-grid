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
        normalizer.targetRMS = 0.05
        normalizer.resetWith(currentVolume: 0.5)
        let result = normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2)
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
        var normalizer = LoudnessNormalizer()  // default targetRMS = 0.05, gate = 0.01
        normalizer.resetWith(currentVolume: 0.5)
        XCTAssertNil(normalizer.update(measuredRMS: 0, currentVolume: 1.0, dt: 0.2))
        XCTAssertNil(normalizer.update(measuredRMS: 1e-6, currentVolume: 1.0, dt: 0.2))
        XCTAssertNil(normalizer.update(measuredRMS: 1e-5, currentVolume: 1.0, dt: 0.2))
        // below noise gate (0.01) even though above the bare epsilon
        XCTAssertNil(normalizer.update(measuredRMS: 0.005, currentVolume: 1.0, dt: 0.2))
    }

    func testJustAboveSilenceThresholdIsNotNil() {
        var normalizer = LoudnessNormalizer()  // default targetRMS = 0.05
        normalizer.resetWith(currentVolume: 0.5)
        // noise gate = targetRMS * 0.2 = 0.01; signal at 0.011 should produce a result
        XCTAssertNotNil(normalizer.update(measuredRMS: 0.011, currentVolume: 1.0, dt: 0.2))
    }

    /// Regression guard: noise gate uses pre-volume measuredRMS, not perceivedRMS.
    /// When currentVolume is very low, content that IS playing must still pass the gate
    /// so the AGC can raise volume back to a listenable level.
    func testNoisegateDoesNotBlockRecoveryAtLowVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMS = 0.040
        normalizer.minVolumeScalar = 0.05
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.05)
        // measuredRMS = 0.1 (content IS audible) but perceivedRMS = 0.1 × 0.05 = 0.005,
        // which is below the old perceived gate of 0.040 × 0.2 = 0.008.
        // With the gate on measuredRMS (0.1 > 0.008), AGC must return non-nil.
        let result = normalizer.update(measuredRMS: 0.1, currentVolume: 0.05, dt: 0.2)
        XCTAssertNotNil(result, "AGC must not be gated by low volume when content is playing")
        XCTAssertGreaterThan(result!, 0.05, "AGC should raise volume toward target")
    }

    // MARK: - Boundary clamping

    func testOutputClampedToMinVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.minVolumeScalar = 0.2
        normalizer.maxVolumeScalar = 1.0
        normalizer.targetRMS = 0.001  // very quiet target → wants to lower volume a lot
        normalizer.resetWith(currentVolume: 1.0)
        // Run many steps to approach the floor
        var result: Float = 1.0
        for _ in 0..<200 {
            result = normalizer.update(measuredRMS: 0.001, currentVolume: 1.0, dt: 0.2) ?? result
        }
        XCTAssertGreaterThanOrEqual(result, 0.2)
    }

    func testOutputClampedToMaxVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.minVolumeScalar = 0.1
        normalizer.maxVolumeScalar = 0.8
        normalizer.targetRMS = 1.0  // huge target → wants to push volume above 1
        normalizer.resetWith(currentVolume: 0.5)
        var result: Float = 0.5
        for _ in 0..<200 {
            result = normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2) ?? result
        }
        XCTAssertLessThanOrEqual(result, 0.8)
    }

    // MARK: - IIR convergence

    func testIIRConvergesToTarget() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMS = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        // Stable RMS exactly at target → steady-state volume should be whatever current is.
        // Test: start at 0.3, signal RMS == targetRMS, so rawTarget = 1.0, IIR goes toward 1.0.
        normalizer.resetWith(currentVolume: 0.3)
        var result: Float = 0.3
        for _ in 0..<500 {
            result = normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2) ?? result
        }
        // After 500 × 0.2 s = 100 s with releaseSeconds = 5 s, should be very close to 1.0
        XCTAssertEqual(result, 1.0, accuracy: 0.01)
    }

    func testAttackFasterThanRelease() {
        // Both scenarios start at volumeScalar=0.5 with equal distance (±0.25) to rawTarget.
        // Attack: rawTarget=0.25 < 0.5 → loud signal → fast path  (alpha_attack  ≈ 0.33)
        // Release: rawTarget=0.75 > 0.5 → quiet signal → slow path (alpha_release ≈ 0.04)
        // measuredRMS = targetRMS / rawTarget
        let targetRMS: Float = 0.05

        var attackNorm = LoudnessNormalizer()
        attackNorm.targetRMS = targetRMS
        attackNorm.attackSeconds = 0.5
        attackNorm.releaseSeconds = 5.0
        attackNorm.minVolumeScalar = 0.0  // no clamping for this test
        attackNorm.maxVolumeScalar = 2.0
        attackNorm.resetWith(currentVolume: 0.5)

        var releaseNorm = LoudnessNormalizer()
        releaseNorm.targetRMS = targetRMS
        releaseNorm.attackSeconds = 0.5
        releaseNorm.releaseSeconds = 5.0
        releaseNorm.minVolumeScalar = 0.0
        releaseNorm.maxVolumeScalar = 2.0
        releaseNorm.resetWith(currentVolume: 0.5)

        // One step each; measuredRMS drives rawTarget to exactly ±0.25 from start
        let attackResult = attackNorm.update(
            measuredRMS: targetRMS / 0.25, currentVolume: 1.0, dt: 0.2)!  // rawTarget=0.25
        let releaseResult = releaseNorm.update(
            measuredRMS: targetRMS / 0.75, currentVolume: 1.0, dt: 0.2)!  // rawTarget=0.75

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
        normalizer.targetRMS = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.holdSeconds = 1.0
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.5)

        // Two attack ticks with a loud signal; holdCountdown is set to 1.0 after each.
        _ = normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)
        let volAfterAttack = normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)!

        // 5 quiet ticks × 0.2 s = 1.0 s — volume must stay frozen during the hold.
        for _ in 0..<5 {
            let v =
                normalizer.update(measuredRMS: 0.02, currentVolume: 1.0, dt: 0.2) ?? volAfterAttack
            XCTAssertEqual(v, volAfterAttack, accuracy: 1e-4, "volume must not rise during hold")
        }

        // Next quiet tick lands after hold expires → release resumes.
        let volAfterHold = normalizer.update(measuredRMS: 0.02, currentVolume: 1.0, dt: 0.2)!
        XCTAssertGreaterThan(
            volAfterHold, volAfterAttack, "volume must start rising once hold expires")
    }

    // MARK: - Strength (compression ratio)

    func testStrengthZeroReturnsNil() {
        // strength=0 means "no correction" — update() returns nil so the coordinator
        // skips writing volume and does not override manual adjustments.
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMS = 0.05  // noiseGate = 0.05 * 0.2 = 0.01
        normalizer.strength = 0.0
        normalizer.resetWith(currentVolume: 0.5)
        // Loud signal → attack path; with strength=0 must return nil.
        XCTAssertNil(normalizer.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2))
        // Quiet signal above noise gate (0.02 > 0.01) → release path; still nil.
        XCTAssertNil(normalizer.update(measuredRMS: 0.02, currentVolume: 1.0, dt: 0.2))
    }

    func testStrengthOneIsFull() {
        // strength=1 must use the full unscaled rawTarget (no compression).
        // measuredRMS=0.2, targetRMS=0.05 → rawTarget=0.25 < 0.8 (attack path).
        // alpha = 1 - exp(-0.2/0.5) ≈ 0.3297; step ≈ 0.3297*(0.25-0.8) ≈ -0.1813.
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMS = 0.05
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
        full.targetRMS = 0.05
        full.strength = 1.0
        full.attackSeconds = 0.5
        full.minVolumeScalar = 0.0
        full.maxVolumeScalar = 2.0
        full.resetWith(currentVolume: 0.8)

        var half = LoudnessNormalizer()
        half.targetRMS = 0.05
        half.strength = 0.5
        half.attackSeconds = 0.5
        half.minVolumeScalar = 0.0
        half.maxVolumeScalar = 2.0
        half.resetWith(currentVolume: 0.8)

        // Loud signal: rawTarget = 0.05/0.3 ≈ 0.167 < 0.8 → attack direction.
        // strength=0.5 → correctedTarget = sqrt(0.167) ≈ 0.408 (less aggressive).
        let rFull = full.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)!
        let rHalf = half.update(measuredRMS: 0.3, currentVolume: 1.0, dt: 0.2)!
        // rHalf should be larger (less reduction) than rFull.
        XCTAssertGreaterThan(rHalf, rFull, "strength=0.5 should reduce volume less than strength=1")
    }

    // MARK: - resetWith prevents first-frame jump

    func testResetWithSeedsFromCurrentVolume() {
        var normalizer = LoudnessNormalizer()
        normalizer.targetRMS = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.resetWith(currentVolume: 0.2)
        // First update — IIR starts from 0.2, so the result should still be near 0.2
        let first = normalizer.update(measuredRMS: 0.05, currentVolume: 1.0, dt: 0.2)
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
        normalizer.targetRMS = 0.05
        normalizer.attackSeconds = 0.5
        normalizer.releaseSeconds = 5.0
        normalizer.minVolumeScalar = 0.1
        normalizer.maxVolumeScalar = 0.8
        normalizer.resetWith(currentVolume: 0.5)

        // 50 quiet ticks — without anti-windup, smoothedTargetVolume would wind far beyond 0.8
        for _ in 0..<50 {
            _ = normalizer.update(measuredRMS: 0.001, currentVolume: 1.0, dt: 0.2)  // very quiet → huge rawTarget
        }

        // Now a loud signal arrives: rawTarget = 0.05/0.25 = 0.2 < min(0.1)? No, 0.2 clamped to 0.1
        // Use a signal that gives rawTarget = 0.1 exactly at the floor — just below maxVolume
        // Actually use signal giving rawTarget = 0.2 to stay within bounds
        normalizer.minVolumeScalar = 0.0
        normalizer.maxVolumeScalar = 1.0
        normalizer.attackSeconds = 0.1  // fast attack for test speed

        // With anti-windup, the internal state is clamped to maxVolumeScalar=0.8 (before we
        // changed the max). After changing max to 1.0, it should respond immediately.
        // Test: after 5 ticks of loud signal (rawTarget=0.2), volume should be well below 0.8.
        var vol: Float = 1.0
        let loudRMS: Float = 0.05 / 0.2  // rawTarget = 0.2
        for _ in 0..<5 {
            vol = normalizer.update(measuredRMS: loudRMS, currentVolume: 1.0, dt: 0.2) ?? vol
        }
        XCTAssertLessThan(
            vol, 0.5,
            "With anti-windup, loud signal should drive volume down quickly from wound-up state")
    }
}

@MainActor
final class SmartVolumeSettingsTests: XCTestCase {

    func testDefaultsAreLoaded() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.targetRMS, 0.040, accuracy: 1e-6)
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

    // MARK: - targetRMS validation

    func testTargetRMS_ClampedAboveZero() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        // A negative value written via defaults write must not corrupt the normalizer.
        ud.set(Float(-0.1), forKey: "smartVolume.targetRMS")
        // Trigger a live reload by posting the didChange notification directly.
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification, object: ud)
        // Allow the async Task inside the observer to execute.
        await Task.yield()
        await Task.yield()
        XCTAssertGreaterThan(settings.targetRMS, 0, "targetRMS must never be zero or negative")
        ud.removePersistentDomain(forName: suiteName)
    }

    func testTargetRMS_ClampedToMaximum() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        settings.targetRMS = 5.0
        XCTAssertEqual(
            settings.targetRMS, 0.30, accuracy: 1e-6, "targetRMS > 0.30 should clamp to maximum")
        ud.removePersistentDomain(forName: suiteName)
    }

    /// Verifies that reloadFromDefaults() uses perceived-loudness defaults (0.040 / 0.040)
    /// as fallback, not old K-weighted or plain-RMS values.  If a
    /// UserDefaults.didChangeNotification fires before the keys are persisted, settings
    /// must not silently revert to an old scale.
    func testReloadFromDefaultsUsesPerceivedLoudnessFallback() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        // Create fresh settings; keys are not yet written to this suite.
        let settings = SmartVolumeSettings(ud)
        // Confirm fresh-init values are perceived-loudness defaults.
        XCTAssertEqual(settings.targetRMS, 0.040, accuracy: 1e-5)
        XCTAssertEqual(settings.speechTargetRMS, 0.055, accuracy: 1e-5)
        // Remove any persisted keys so reload falls through to the fallback path.
        ud.removeObject(forKey: "smartVolume.targetRMS")
        ud.removeObject(forKey: "smartVolume.speechTargetRMS")
        ud.removeObject(forKey: "smartVolume.rmsVersion")
        // Trigger reloadFromDefaults via notification.
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: ud)
        await Task.yield()
        await Task.yield()
        // Values must stay at perceived-loudness defaults.
        XCTAssertEqual(
            settings.targetRMS, 0.040, accuracy: 1e-5,
            "reloadFromDefaults fallback must use perceived-loudness default 0.040")
        XCTAssertEqual(
            settings.speechTargetRMS, 0.055, accuracy: 1e-5,
            "speechTargetRMS default must be 0.055 (higher than music 0.040 so speech mode differs)"
        )
        ud.removePersistentDomain(forName: suiteName)
    }

    /// Verify that upgrading from kweighted_perceived_v1 → v2 preserves user-calibrated
    /// values (no reset), since both versions are in the same perceived-loudness scale.
    func testMigrationPreservesPerceivedV1CalibratedValues() async {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        // Simulate a user who carefully calibrated their values on v1.
        ud.set(Float(0.065), forKey: "smartVolume.targetRMS")
        ud.set(Float(0.055), forKey: "smartVolume.speechTargetRMS")
        ud.set("kweighted_perceived_v1", forKey: "smartVolume.rmsVersion")
        let settings = SmartVolumeSettings(ud)
        // Values must be preserved — they're already in perceived-loudness scale.
        XCTAssertEqual(settings.targetRMS, 0.065, accuracy: 1e-6)
        XCTAssertEqual(settings.speechTargetRMS, 0.055, accuracy: 1e-6)
        // Version tag must be bumped to current.
        XCTAssertEqual(
            ud.string(forKey: "smartVolume.rmsVersion"), "kweighted_perceived_v2",
            "version must be updated to current even when values are preserved")
        ud.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Per-device calibration

    func testSaveCalibrationPersistsToUserDefaults() {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        let uid = "BuiltInSpeakerDevice"
        let cal = SmartVolumeSettings.DeviceCalibration(targetRMS: 0.045, speechTargetRMS: 0.060)
        settings.saveCalibration(cal, forDeviceUID: uid)

        // Value must be readable back via calibration(forDeviceUID:).
        guard let loaded = settings.calibration(forDeviceUID: uid) else {
            return XCTFail("expected non-nil calibration after save")
        }
        XCTAssertEqual(loaded.targetRMS, Float(0.045), accuracy: Float(1e-6))
        XCTAssertEqual(loaded.speechTargetRMS, Float(0.060), accuracy: Float(1e-6))

        // A second SmartVolumeSettings instance (simulating app relaunch) must also see
        // the persisted calibration from UserDefaults.
        let settings2 = SmartVolumeSettings(ud)
        guard let reloaded = settings2.calibration(forDeviceUID: uid) else {
            return XCTFail("calibration must survive round-trip through UserDefaults")
        }
        XCTAssertEqual(reloaded.targetRMS, Float(0.045), accuracy: Float(1e-6))
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
            SmartVolumeSettings.DeviceCalibration(targetRMS: 0.030, speechTargetRMS: 0.040),
            forDeviceUID: "HeadphonesUID"
        )
        settings.saveCalibration(
            SmartVolumeSettings.DeviceCalibration(targetRMS: 0.080, speechTargetRMS: 0.100),
            forDeviceUID: "ExternalSpeakerUID"
        )
        XCTAssertEqual(
            settings.calibration(forDeviceUID: "HeadphonesUID")?.targetRMS ?? -1, Float(0.030),
            accuracy: Float(1e-6))
        XCTAssertEqual(
            settings.calibration(forDeviceUID: "ExternalSpeakerUID")?.targetRMS ?? -1,
            Float(0.080), accuracy: Float(1e-6))
        ud.removePersistentDomain(forName: suiteName)
    }

    /// Regression guard: saveCalibration must persist both targetRMS *and* speechTargetRMS
    /// independently so a speech calibration on one device does not clobber its music target.
    func testSpeechCalibrationPreservesMusicTarget() {
        let suiteName = "smartVolumeTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        let settings = SmartVolumeSettings(ud)
        let uid = "BuiltInSpeakerDevice"

        // Simulate Calibrate while playing music → saves a music target.
        settings.saveCalibration(
            SmartVolumeSettings.DeviceCalibration(targetRMS: 0.035, speechTargetRMS: 0.055),
            forDeviceUID: uid)

        // Now simulate Calibrate while in speech mode → only speechTargetRMS should change.
        // (Mirrors what SmartVolumeCoordinator.calibrateTargetRMS() does.)
        let existingCal = settings.calibration(forDeviceUID: uid)
        let newCal = SmartVolumeSettings.DeviceCalibration(
            targetRMS: existingCal?.targetRMS ?? settings.targetRMS,
            speechTargetRMS: 0.070
        )
        settings.saveCalibration(newCal, forDeviceUID: uid)

        guard let reloaded = settings.calibration(forDeviceUID: uid) else {
            return XCTFail("calibration must exist after double save")
        }
        // Music target must be unchanged.
        XCTAssertEqual(
            reloaded.targetRMS, Float(0.035), accuracy: Float(1e-6),
            "music calibration must survive a speech re-calibration on the same device")
        // Speech target must reflect the new value.
        XCTAssertEqual(reloaded.speechTargetRMS, Float(0.070), accuracy: Float(1e-6))
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
            up: true, currentVolume: 0.5, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertEqual(effect.newMax ?? 0, 0.5 + step, accuracy: 1e-5)
        XCTAssertNil(effect.newTargetRMS, "at ceiling: targetRMS must not change")
        XCTAssertEqual(effect.seedVolume, 0.5 + step, accuracy: 1e-5)
    }

    func testAtCeilingDownLowersCeiling() {
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.5, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertEqual(effect.newMax ?? 0, 0.5 - step, accuracy: 1e-5)
        XCTAssertNil(effect.newTargetRMS, "at ceiling: targetRMS must not change")
        XCTAssertEqual(effect.seedVolume, 0.5 - step, accuracy: 1e-5)
    }

    func testAtCeilingUpClampedAtOne() {
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 1.0, activeMax: 1.0, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertEqual(effect.newMax ?? 0, 1.0, accuracy: 1e-5, "ceiling must not exceed 1.0")
        XCTAssertEqual(effect.seedVolume, 1.0, accuracy: 1e-5)
    }

    func testAtCeilingDownClampedAtMinVolume() {
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.1, activeMax: 0.1, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertEqual(
            effect.newMax ?? 0, 0.1, accuracy: 1e-5, "ceiling must not fall below minVolume")
        XCTAssertEqual(effect.seedVolume, 0.1, accuracy: 1e-5)
    }

    // MARK: - Mid-range

    func testBelowCeilingUpKeepsCeilingAdjustsTargetRMS() {
        // vol=0.3 is well below ceiling=0.5: ceiling must stay, targetRMS recalibrated upward.
        // desiredVolume = min(0.5, 0.3 + step) = 0.3625
        // newTargetRMS  = (0.05 * 0.3625).clamped(to: 0.01...0.30) = 0.018125
        let desiredVolume = min(0.5, 0.3 + step)
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.3, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertNil(effect.newMax, "ceiling must not change when vol is below ceiling")
        XCTAssertEqual(effect.newTargetRMS ?? 0, 0.05 * desiredVolume, accuracy: 1e-5)
        XCTAssertEqual(effect.seedVolume, desiredVolume, accuracy: 1e-5)
    }

    func testBelowCeilingDownKeepsCeilingAdjustsTargetRMS() {
        // desiredVolume = max(0.1, 0.3 - step) = 0.2375
        // newTargetRMS  = (0.05 * 0.2375).clamped(to: 0.01...0.30) = 0.011875
        let desiredVolume = max(0.1, 0.3 - step)
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.3, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertNil(effect.newMax, "ceiling must not change when vol is below ceiling")
        XCTAssertEqual(effect.newTargetRMS ?? 0, 0.05 * desiredVolume, accuracy: 1e-5)
        XCTAssertEqual(effect.seedVolume, desiredVolume, accuracy: 1e-5)
    }

    // MARK: - targetRMS clamp boundaries

    func testTargetRMS_clampedToUpperBound() {
        // smoothedRMS=0.5, desiredVolume ≈ 0.8625 → product 0.43125 must clamp to 0.30.
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.8, activeMax: 0.9, minVolume: 0.1, smoothedRMS: 0.5)
        XCTAssertNil(effect.newMax)
        XCTAssertEqual(
            effect.newTargetRMS ?? 0, 0.30, accuracy: 1e-5, "must clamp to 0.30 upper bound")
    }

    func testTargetRMS_clampedToLowerBound() {
        // smoothedRMS=0.05, desiredVolume=0.1 (at floor) → product 0.005 must clamp to 0.01.
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.15, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertNil(effect.newMax)
        XCTAssertEqual(
            effect.newTargetRMS ?? 0, 0.01, accuracy: 1e-5, "must clamp to 0.01 lower bound")
    }

    // MARK: - desiredVolume boundary clamping

    func testMidRangeUp_desiredVolumeClampedToActiveMax() {
        // vol=0.44 < ceiling-step/2=0.469, but vol+step=0.503 > ceiling=0.5.
        // desiredVolume must be clamped to activeMax.
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.44, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertNil(effect.newMax, "ceiling must not change")
        XCTAssertEqual(effect.seedVolume, 0.5, accuracy: 1e-5, "desiredVolume clamped to activeMax")
    }

    func testMidRangeDown_desiredVolumeClampedToMinVolume() {
        // vol=0.15, down: vol-step=0.0875 < minVolume=0.1 → must clamp to 0.1.
        let effect = VolumeKeyEffect.compute(
            up: false, currentVolume: 0.15, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.05)
        XCTAssertNil(effect.newMax, "ceiling must not change")
        XCTAssertEqual(effect.seedVolume, 0.1, accuracy: 1e-5, "desiredVolume clamped to minVolume")
    }

    // MARK: - Silent content

    func testSilentContent_AtCeiling_CeilingChangesButNoTargetRMS() {
        // At ceiling, targetRMS is never changed regardless of smoothedRMS.
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.5, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.0)
        XCTAssertEqual(effect.newMax ?? 0, 0.5 + step, accuracy: 1e-5)
        XCTAssertNil(effect.newTargetRMS, "at ceiling: targetRMS never changes")
    }

    func testSilentContent_MidRange_NoChanges() {
        let effect = VolumeKeyEffect.compute(
            up: true, currentVolume: 0.3, activeMax: 0.5, minVolume: 0.1, smoothedRMS: 0.0)
        XCTAssertNil(effect.newMax, "ceiling unchanged mid-range")
        XCTAssertNil(effect.newTargetRMS, "targetRMS unchanged with no audio")
    }
}
