import Foundation

/// Single-pole IIR loudness normalizer.
///
/// Call `resetWith(currentVolume:)` before the first `update()` call and on any
/// discontinuity (start, unmute). `update()` returns `nil` until that happens.
struct LoudnessNormalizer {
    var targetRMS: Float = 0.05 {
        didSet { if targetRMS < 1e-5 { targetRMS = max(1e-5, oldValue) } }
    }
    var minVolumeScalar: Float = 0.1
    var maxVolumeScalar: Float = 1.0
    /// Time constant for loudness decrease (signal too loud → reduce volume fast).
    var attackSeconds: Float = 0.5 {
        didSet { if attackSeconds <= 0 { attackSeconds = max(1e-4, oldValue) } }
    }
    /// Time constant for loudness increase (signal too quiet → raise volume slowly).
    var releaseSeconds: Float = 5.0 {
        didSet { if releaseSeconds <= 0 { releaseSeconds = max(1e-4, oldValue) } }
    }
    /// Seconds to freeze volume after a loud signal ends before allowing release.
    /// This prevents the AGC from chasing up during natural speech pauses, where
    /// the signal temporarily drops to background-music or ambient-noise levels.
    var holdSeconds: Float = 2.0
    /// Normalisation strength (compression ratio).
    /// 1.0 = full normalisation (current AGC drives output to exactly targetRMS).
    /// 0.5 = square-root compression — halves the gain correction, preserving more original dynamics.
    /// 0.0 = no correction.
    var strength: Float = 1.0

    private var smoothedTargetVolume: Float = 0.5
    private var holdCountdown: Float = 0.0
    private var initialized = false

    /// Compute the next volume scalar.
    ///
    /// - Parameters:
    ///   - measuredRMS: RMS of the captured audio signal (pre-volume tap assumed).
    ///   - dt: AGC update interval in seconds (= coordinator `timerInterval`, ≈ 0.2 s).
    ///         Do NOT pass `frameSize / sampleRate` — that is the per-IO-buffer duration,
    ///         much smaller than the timer interval.
    /// - Returns: Clamped volume scalar, or `nil` if silent / not yet initialised.
    mutating func update(measuredRMS: Float, dt: Float) -> Float? {
        // Noise gate: ignore audio that is less than 20 % of targetRMS.
        // This prevents the AGC from ramping volume to maximum during quiet background
        // passages (ambient music, crowd noise) between meaningful speech bursts.
        let noiseGate = max(1e-5, targetRMS * 0.2)
        guard measuredRMS > noiseGate else { return nil }
        guard initialized else { return nil }
        let rawTarget = targetRMS / measuredRMS
        // Apply compression strength: strength=1 gives full normalisation; lower values
        // reduce the gain correction so content with different native loudness isn't
        // over-corrected.  pow(1.0, s) == 1.0 and pow(0.0, s) == 0.0 remain correct.
        // strength=0 means "no correction" — hold current volume.
        guard strength > 0 else { return smoothedTargetVolume }
        let correctedTarget = strength >= 1 ? rawTarget : powf(rawTarget, strength)
        // alpha = 1 − exp(−dt/τ) converts a physical time constant τ (seconds) to a
        // per-step coefficient, making the AGC speed independent of the timer frequency.
        if correctedTarget < smoothedTargetVolume {
            // Attack: loud signal — reduce volume quickly and arm the hold timer so that
            // a following quiet patch (background music, pause) doesn't immediately
            // trigger the release ramp.
            holdCountdown = holdSeconds
            let alpha = 1 - expf(-dt / attackSeconds)
            smoothedTargetVolume += alpha * (correctedTarget - smoothedTargetVolume)
        } else {
            // Release: content is quieter than target.
            if holdCountdown > 1e-6 {
                // Hold phase: keep volume frozen until the timer expires.
                holdCountdown = max(0, holdCountdown - dt)
            } else {
                // Cap the effective IIR target at the ceiling so a very quiet signal
                // (correctedTarget >> maxVolumeScalar) doesn't produce large upward steps.
                let effectiveTarget = min(correctedTarget, maxVolumeScalar)
                let alpha = 1 - expf(-dt / releaseSeconds)
                smoothedTargetVolume += alpha * (effectiveTarget - smoothedTargetVolume)
            }
        }
        // Anti-windup: clamp internal state so the IIR doesn't drift beyond the allowed
        // range during sustained loud/quiet passages.  Without this, recovery after a
        // content transition takes many extra ticks to unwind the accumulated error.
        smoothedTargetVolume = max(minVolumeScalar, min(maxVolumeScalar, smoothedTargetVolume))
        return smoothedTargetVolume
    }

    /// Seed the IIR state with the current system volume so the first AGC step starts
    /// from the right position rather than jumping to a computed target.
    /// Call this in `start()` and whenever a mute→unmute transition occurs.
    mutating func resetWith(currentVolume: Float) {
        smoothedTargetVolume = currentVolume
        holdCountdown = 0
        initialized = true
    }

    /// Disable AGC until the next `resetWith` call. Used when the tap is stopped.
    mutating func reset() {
        initialized = false
    }
}
