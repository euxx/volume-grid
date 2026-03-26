import XCTest

@testable import VolumeGrid

final class KWeightingFilterTests: XCTestCase {

    // MARK: - Helpers

    /// Generate a pure sine wave of `frameCount` mono samples at the given frequency.
    private func sine(hz: Double, sampleRate: Double = 48000, frameCount: Int = 4800) -> [Float] {
        (0..<frameCount).map { n in
            Float(sin(2.0 * Double.pi * hz * Double(n) / sampleRate))
        }
    }

    /// Compute plain RMS of an array.
    private func rms(_ samples: [Float]) -> Float {
        let sumSq = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSq / Float(samples.count))
    }

    // MARK: - Silence

    func testSilenceOutputsZero() {
        var filter = KWeightingFilter(sampleRate: 48000)
        let silence = [Float](repeating: 0, count: 4800)
        let result = silence.withUnsafeBufferPointer { filter.process($0) }
        XCTAssertEqual(result, 0, accuracy: 1e-9)
    }

    // MARK: - Frequency response

    func test1kHzApproximatesPlainRMS() {
        // 1 kHz is near the K-weighting reference: K-weighted ≈ plain within 10%.
        let samples = sine(hz: 1000)
        var filter = KWeightingFilter(sampleRate: 48000)
        let kRMS = samples.withUnsafeBufferPointer { filter.process($0) }
        let plain = rms(samples)
        XCTAssertEqual(
            Double(kRMS), Double(plain), accuracy: 0.1,
            "K-weighted RMS at 1 kHz should be close to plain RMS")
    }

    func test3500HzKWeightedExceedsPlain() {
        // 3.5 kHz falls in the pre-filter boost region; K-weighted RMS should exceed plain.
        let samples = sine(hz: 3500)
        var filter = KWeightingFilter(sampleRate: 48000)
        let kRMS = samples.withUnsafeBufferPointer { filter.process($0) }
        let plain = rms(samples)
        XCTAssertGreaterThan(
            kRMS, plain * 1.02,
            "K-weighted RMS at 3.5 kHz should exceed plain RMS (boost region)")
    }

    func test50HzKWeightedBelowPlain() {
        // 50 Hz is above the high-pass cutoff (~38 Hz) but close to it.
        // 2nd-order Butterworth at fc=38 Hz gives |H(50Hz)| ≈ 0.864 (i.e. ~86% of plain).
        // K-weighted RMS should be noticeably below plain.
        let samples = sine(hz: 50)
        var filter = KWeightingFilter(sampleRate: 48000)
        let kRMS = samples.withUnsafeBufferPointer { filter.process($0) }
        let plain = rms(samples)
        XCTAssertLessThan(
            kRMS, plain * 0.95,
            "K-weighted RMS at 50 Hz should be below plain RMS (approaching high-pass cutoff)")
    }

    func test20HzSubstantiallyAttenuated() {
        // 20 Hz is well into the stopband: |H(20Hz)| ≈ 0.265 (i.e. ~26% of plain).
        let samples = sine(hz: 20)
        var filter = KWeightingFilter(sampleRate: 48000)
        let kRMS = samples.withUnsafeBufferPointer { filter.process($0) }
        let plain = rms(samples)
        XCTAssertLessThan(
            kRMS, plain * 0.45,
            "K-weighted RMS at 20 Hz should be substantially attenuated (< 45% of plain)")
    }

    // MARK: - Reset

    func testResetRestoresFreshFilterBehavior() {
        // Filter two identical sine buffers: one freshly initialised, one reset.
        // Both should produce the same output up to floating-point noise.
        let samples = sine(hz: 440)

        var fresh = KWeightingFilter(sampleRate: 48000)
        let resultFresh = samples.withUnsafeBufferPointer { fresh.process($0) }

        var reused = KWeightingFilter(sampleRate: 48000)
        // Run arbitrary signal to corrupt state, then reset.
        let junk = sine(hz: 123, frameCount: 200)
        junk.withUnsafeBufferPointer { _ = reused.process($0) }
        reused.reset()
        let resultReset = samples.withUnsafeBufferPointer { reused.process($0) }

        XCTAssertEqual(
            resultFresh, resultReset, accuracy: 1e-6,
            "After reset(), filter output should match a fresh instance")
    }

    // MARK: - 44100 Hz sample rate

    func test44100HzHighFrequencyBoosted() {
        var filter = KWeightingFilter(sampleRate: 44100)
        let hi = sine(hz: 3500, sampleRate: 44100)
        let lo = sine(hz: 100, sampleRate: 44100)
        let kRmsHi = hi.withUnsafeBufferPointer { filter.process($0) }
        filter.reset()
        let kRmsLo = lo.withUnsafeBufferPointer { filter.process($0) }
        XCTAssertGreaterThan(
            kRmsHi / rms(hi), kRmsLo / rms(lo),
            "High-freq gain should exceed low-freq gain at 44100 Hz (K-weighting characteristic)")
    }

    // MARK: - Stereo interleaved

    func testInterleavedStereoMatchesMonoForIdenticalChannels() {
        // Stereo with L == R should produce the same K-weighted RMS as the mono signal,
        // because processInterleaved averages across channels.  This ensures stereo and
        // mono content of equal perceptual loudness yield the same AGC target.
        let mono = sine(hz: 1000)
        var interleaved = [Float](repeating: 0, count: mono.count * 2)
        for i in 0..<mono.count {
            interleaved[i * 2] = mono[i]
            interleaved[i * 2 + 1] = mono[i]
        }

        var filterMono = KWeightingFilter(sampleRate: 48000, channelCount: 1)
        let kRmsMono = mono.withUnsafeBufferPointer { filterMono.process($0) }

        var filterStereo = KWeightingFilter(sampleRate: 48000, channelCount: 2)
        let kRmsStereo = interleaved.withUnsafeBufferPointer {
            filterStereo.processInterleaved($0, frameCount: mono.count, channelCount: 2)
        }

        XCTAssertEqual(
            Double(kRmsStereo), Double(kRmsMono), accuracy: 0.001,
            "Stereo with identical channels should equal mono K-weighted RMS (channels averaged)")
    }

    func testInterleavedEmptyBufferReturnsZero() {
        var filter = KWeightingFilter(sampleRate: 48000, channelCount: 2)
        let empty = [Float]()
        let result = empty.withUnsafeBufferPointer {
            filter.processInterleaved($0, frameCount: 0, channelCount: 2)
        }
        XCTAssertEqual(result, 0)
    }
}
