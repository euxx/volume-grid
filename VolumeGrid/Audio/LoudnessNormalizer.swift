import Foundation

/// Single-pole IIR loudness normalizer with a dead-zone comfort range.
///
/// Call `resetWith(currentVolume:)` before the first `update()` call and on any
/// discontinuity (start, unmute). `update()` returns `nil` until that happens.
struct LoudnessNormalizer {
    /// Lower bound of the acceptable perceived-loudness range.
    /// When perceivedRMS drops below this, the AGC raises volume to meet this bound.
    var targetRMSLow: Float = 0.020 {
        didSet { if targetRMSLow < 1e-5 { targetRMSLow = max(1e-5, oldValue) } }
    }
    /// Upper bound of the acceptable perceived-loudness range.
    /// When perceivedRMS rises above this, the AGC lowers volume to meet this bound.
    var targetRMSHigh: Float = 0.090 {
        didSet { if targetRMSHigh < 1e-5 { targetRMSHigh = max(1e-5, oldValue) } }
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
    ///   - measuredRMS: K-weighted RMS of the captured audio signal (pre-volume tap).
    ///   - currentVolume: Current system volume scalar.  Combined with `measuredRMS` to
    ///     compute perceived loudness (`= measuredRMS × currentVolume`).  The comfort
    ///     zone `[targetRMSLow, targetRMSHigh]` is defined in the same perceived-loudness
    ///     space, so the feedback loop closes on what the user actually hears.
    ///   - dt: AGC update interval in seconds (= coordinator `timerInterval`, ≈ 0.2 s).
    ///         Do NOT pass `frameSize / sampleRate` — that is the per-IO-buffer duration,
    ///         much smaller than the timer interval.
    /// - Returns: Clamped volume scalar, or `nil` if silent / not yet initialised / in the
    ///            comfort zone / `strength` is 0.
    mutating func update(measuredRMS: Float, currentVolume: Float, dt: Float) -> Float? {
        // Noise gate: ignore audio that is genuinely inaudible or below the content floor.
        // Uses the pre-volume signal (measuredRMS) rather than perceived RMS so that a
        // very low system volume does not prevent the AGC from detecting and raising volume.
        // Gate = 20% of targetRMSLow on the raw signal scale.
        // Noise gate is handled by the coordinator (adaptive gate); skip here if signal
        // is truly inaudible (safety floor only).
        guard measuredRMS > 1e-5 else { return nil }
        guard initialized else { return nil }
        // Advance the hold timer on every valid-audio tick, not just in the release branch.
        // This ensures time spent inside the comfort zone counts toward hold expiry; without
        // this, the hold clock would be paused for the entire in-zone period and the
        // effective hold time after a loud event could far exceed `holdSeconds`.
        if holdCountdown > 0 { holdCountdown = max(0, holdCountdown - dt) }
        // Perceived loudness: what the user actually hears.
        let perceivedRMS = measuredRMS * max(1e-5, currentVolume)
        // Dead-zone check: only act when perceived loudness is outside the comfort range.
        // rawTarget < 1 → perceived too loud   → lower volume (attack).
        // rawTarget > 1 → perceived too quiet  → raise volume (release).
        let rawTarget: Float
        if perceivedRMS > targetRMSHigh {
            rawTarget = targetRMSHigh / perceivedRMS  // too loud — push volume down
        } else if perceivedRMS < targetRMSLow {
            rawTarget = targetRMSLow / perceivedRMS  // too quiet — push volume up
        } else {
            return nil  // inside comfort zone — do not touch volume
        }
        // Apply compression strength: strength=1 gives full normalisation; lower values
        // reduce the gain correction so content with different native loudness isn't
        // over-corrected.  pow(1.0, s) == 1.0 and pow(0.0, s) == 0.0 remain correct.
        // strength=0 means "no correction" — skip AGC this tick so manual adjustments
        // are not overridden.
        guard strength > 0 else { return nil }
        let correctedRatio = strength >= 1 ? rawTarget : powf(rawTarget, strength)
        // Desired absolute volume: scale the current volume by the per-step ratio.
        // At steady state with strength=1: desiredVolume = targetRMS / measuredRMS,
        // which is the exact volume needed so that desiredVolume × measuredRMS = targetRMS.
        let desiredVolume = currentVolume * correctedRatio
        // alpha = 1 − exp(−dt/τ) converts a physical time constant τ (seconds) to a
        // per-step coefficient, making the AGC speed independent of the timer frequency.
        if desiredVolume < smoothedTargetVolume {
            // Attack: proportional hold — scale duration by overshoot magnitude.
            // Mild overshoot (1.1×) → short hold; heavy overshoot (2×+) → full hold.
            let overshoot = perceivedRMS / targetRMSHigh
            holdCountdown = holdSeconds * min(1.0, max(0, overshoot - 1.0))
            let alpha = 1 - expf(-dt / attackSeconds)
            smoothedTargetVolume += alpha * (desiredVolume - smoothedTargetVolume)
        } else {
            // Release: perceived signal is quieter than target → raise volume slowly.
            if holdCountdown > 1e-6 {
                // Hold phase: keep volume frozen until the timer expires.
                // (holdCountdown is already being decremented above on every valid tick.)
            } else {
                // Cap the effective IIR target at the ceiling so a very quiet signal
                // (desiredVolume >> maxVolumeScalar) doesn't produce large upward steps.
                let effectiveTarget = min(desiredVolume, maxVolumeScalar)
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

    /// Called each tick that the AGC is bypassed due to externally classified silence.
    ///
    /// Anchors `smoothedTargetVolume` to `currentVolume` to prevent the IIR from drifting
    /// toward a large raise while no volume change is applied.  Simultaneously advances
    /// `holdCountdown` so it expires with real wall-clock time rather than only during
    /// content — without this, hold would freeze indefinitely across a long silence gap,
    /// delaying the raise that should follow when quiet content resumes.
    mutating func silenceTick(currentVolume: Float, dt: Float) {
        smoothedTargetVolume = currentVolume
        if holdCountdown > 0 { holdCountdown = max(0, holdCountdown - dt) }
    }

    /// Disable AGC until the next `resetWith` call. Used when the tap is stopped.
    mutating func reset() {
        initialized = false
    }
}
