import Accelerate
import Foundation

// MARK: - Biquad IIR filter

/// Single-precision direct-form II transposed biquad.
struct Biquad {
    let b0, b1, b2: Float  // feedforward
    let a1, a2: Float  // feedback (denominator, sign convention:
    // y[n] = b0*x + b1*x[-1] + b2*x[-2] - a1*y[-1] - a2*y[-2])
    var z1: Float = 0  // delay line state
    var z2: Float = 0

    /// Process one sample and return the filtered output.
    @inline(__always)
    nonisolated mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    /// Reset internal state (call on device change or discontinuity).
    nonisolated mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

// MARK: - K-weighting filter coefficients

extension Biquad {
    /// ITU-R BS.1770-4 pre-filter (high-shelf at ~1.5 kHz, compensates for head diffraction).
    /// Coefficients computed via bilinear transform for the given sample rate.
    nonisolated static func kWeightingPrefilter(sampleRate: Double) -> Biquad {
        // Reference coefficients at 48000 Hz from ITU-R BS.1770-4 Annex 1.
        // For other rates we recompute via the analogue prototype + bilinear transform
        // using the matched-z / frequency-prewarped form described in the standard.
        if abs(sampleRate - 48000) < 1 {
            return Biquad(
                b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                a1: -1.69065929318241, a2: 0.73248077421585)
        }
        if abs(sampleRate - 44100) < 1 {
            return Biquad(
                b0: 1.54652241786807, b1: -2.67127917936765, b2: 1.15543897489713,
                a1: -1.66913968190215, a2: 0.71254913235498)
        }
        if abs(sampleRate - 96000) < 1 {
            return Biquad(
                b0: 1.52166064013929, b1: -2.71082986578613, b2: 1.21024285027814,
                a1: -1.71086507817686, a2: 0.74153022509192)
        }
        // Generic fallback: compute via first-order approximation scaled from 48kHz.
        // Accuracy is sufficient for perceptual loudness matching at non-standard rates.
        return Biquad.kWeightingPrefilterGeneric(sampleRate: sampleRate)
    }

    /// ITU-R BS.1770-4 second stage: high-pass filter at ~38 Hz (removes DC and sub-bass).
    nonisolated static func kWeightingHighPass(sampleRate: Double) -> Biquad {
        if abs(sampleRate - 48000) < 1 {
            return Biquad(
                b0: 1.0, b1: -2.0, b2: 1.0,
                a1: -1.99004745483398, a2: 0.99007225036621)
        }
        if abs(sampleRate - 44100) < 1 {
            return Biquad(
                b0: 1.0, b1: -2.0, b2: 1.0,
                a1: -1.98916700017829, a2: 0.98921133828629)
        }
        if abs(sampleRate - 96000) < 1 {
            return Biquad(
                b0: 1.0, b1: -2.0, b2: 1.0,
                a1: -1.99501896851843, a2: 0.99503615853040)
        }
        return Biquad.kWeightingHighPassGeneric(sampleRate: sampleRate)
    }

    // MARK: Generic coefficient computation (bilinear transform)

    private nonisolated static func kWeightingPrefilterGeneric(sampleRate: Double) -> Biquad {
        // Analogue prototype zero/poles from BS.1770-4, warped to digital domain.
        // Ωc = 2π × 1681.974450955533 rad/s (shelf frequency).
        let fs = sampleRate
        let vh: Double = 1.584864701 * 1.584864701  // Vh^2 from standard
        let vb: Double = 1.584864701
        let q: Double = 0.7071067812
        let omegaP: Double = 2.0 * Double.pi * 1681.974450955533
        let k = tan(omegaP / (2.0 * fs))
        let kp2 = k * k
        let norm = 1.0 / (kp2 * q + k + q * vh * vb)
        let b0 = Float((kp2 * q + k * vb + q * vh) * norm)
        let b1 = Float(2.0 * (kp2 * q - q * vh) * norm)
        let b2 = Float((kp2 * q - k * vb + q * vh) * norm)
        let a1 = Float(2.0 * (kp2 * q - q) * norm)
        let a2 = Float((kp2 * q - k + q) * norm)
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    private nonisolated static func kWeightingHighPassGeneric(sampleRate: Double) -> Biquad {
        // Second-order Butterworth high-pass at fc = 38.13547087602444 Hz.
        let fs = sampleRate
        let fc: Double = 38.13547087602444
        let k = tan(Double.pi * fc / fs)
        let norm = 1.0 / (1.0 + k * sqrt(2.0) + k * k)
        let b0 = Float(norm)
        let b1 = Float(-2.0 * norm)
        let b2 = Float(norm)
        let a1 = Float(2.0 * (k * k - 1.0) * norm)
        let a2 = Float((1.0 - k * sqrt(2.0) + k * k) * norm)
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
}

// MARK: - K-weighting filter

/// Two-stage K-weighting filter per ITU-R BS.1770-4.
///
/// Applies a high-shelf pre-filter (head diffraction compensation) followed by a
/// high-pass filter (removes sub-bass below ~38 Hz).  The resulting signal closely
/// approximates perceived loudness, as required for EBU R128 / LUFS measurements.
///
/// Each audio channel is filtered independently to avoid corrupting the biquad
/// delay-line state with samples from a different signal.
///
/// Usage:
/// ```swift
/// var filter = KWeightingFilter(sampleRate: 48000, channelCount: 2)
/// let rms = filter.process(interleavedSamples, frameCount: n, channelCount: 2)
/// ```
struct KWeightingFilter {
    // Per-channel filter pair.  Stored as a flat array of (stage1, stage2) pairs to
    // avoid heap allocations: ChannelFilter is a pure value type with 10 Floats.
    struct ChannelState {
        var stage1: Biquad
        var stage2: Biquad
        @inline(__always)
        nonisolated mutating func process(_ x: Float) -> Float {
            stage2.process(stage1.process(x))
        }
        nonisolated mutating func reset() {
            stage1.reset()
            stage2.reset()
        }
    }

    private var channelStates: [ChannelState]

    /// - Parameters:
    ///   - sampleRate: Device sample rate in Hz.
    ///   - channelCount: Number of audio channels to track simultaneously (≥ 1).
    ///                   All channels are processed with equal weight.
    ///                   LFE channels contribute minimally due to K-weighting's
    ///                   low-frequency attenuation.
    nonisolated init(sampleRate: Double, channelCount: Int = 2) {
        let count = max(1, channelCount)
        channelStates = (0..<count).map { _ in
            ChannelState(
                stage1: .kWeightingPrefilter(sampleRate: sampleRate),
                stage2: .kWeightingHighPass(sampleRate: sampleRate))
        }
    }

    /// Process contiguous mono Float32 samples and return the K-weighted RMS.
    nonisolated mutating func process(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSq: Float = 0
        for i in 0..<samples.count {
            let y = channelStates[0].process(samples[i])
            sumSq += y * y
        }
        return sqrt(sumSq / Float(samples.count))
    }

    /// Process interleaved multi-channel samples, returning the average K-weighted RMS
    /// across channels (channels averaged in the mean-square domain for accuracy).
    ///
    /// Each channel is filtered with its own independent biquad state.
    ///
    /// - Parameters:
    ///   - samples: Pointer to interleaved frame data (ch0, ch1, ch0, ch1, …).
    ///   - frameCount: Number of audio frames.
    ///   - channelCount: Number of interleaved channels in `samples` (≥ 1).
    nonisolated mutating func processInterleaved(
        _ samples: UnsafeBufferPointer<Float>, frameCount: Int, channelCount: Int
    ) -> Float {
        guard frameCount > 0, channelCount >= 1 else { return 0 }
        if channelCount == 1 {
            return process(samples)
        }
        let activeCh = min(channelCount, channelStates.count)
        var totalMeanSquare: Float = 0
        for ch in 0..<activeCh {
            var sumSq: Float = 0
            for frame in 0..<frameCount {
                let s = samples[frame * channelCount + ch]
                let y = channelStates[ch].process(s)
                sumSq += y * y
            }
            totalMeanSquare += sumSq / Float(frameCount)
        }
        // Average across channels so mono and stereo content of equal loudness produce
        // the same K-weighted RMS value.  This is appropriate for an AGC controller.
        return sqrt(totalMeanSquare / Float(activeCh))
    }

    /// Process a strided single-channel buffer, returning K-weighted RMS.
    ///
    /// Use this when iterating over an `AudioBufferList` to process each physical
    /// channel independently with its own accumulator state.
    ///
    /// - Parameters:
    ///   - channelIndex: Physical channel index; must be < `channelStates.count`.
    ///   - samples: Pointer to the first sample of this channel.
    ///   - stride: Sample stride (1 for non-interleaved; channelCount for interleaved).
    ///   - frameCount: Number of frames to process.
    nonisolated mutating func processChannel(
        _ channelIndex: Int, samples: UnsafePointer<Float>, stride: Int, frameCount: Int
    ) -> Float {
        guard frameCount > 0, channelIndex < channelStates.count else { return 0 }
        var sumSq: Float = 0
        for i in 0..<frameCount {
            let y = channelStates[channelIndex].process(samples[i * stride])
            sumSq += y * y
        }
        return sqrt(sumSq / Float(frameCount))
    }

    /// Reset all channel delay-line states.
    nonisolated mutating func reset() {
        for i in channelStates.indices { channelStates[i].reset() }
    }
}
