import AVFoundation
import Accelerate
import AudioToolbox
import CoreAudio
import os.lock
import os.log

@available(macOS 14.2, *)
final class AudioTapMonitor: @unchecked Sendable {

    private let log = Logger(subsystem: "one.eux.volumegrid", category: "AudioTapMonitor")

    // tapSampleRate is written once in start() before the IO proc starts, then only read.
    // nonisolated(unsafe): written once before IO proc starts, then only read from all threads.
    private(set) nonisolated(unsafe) var tapSampleRate: Float = 48000

    // These fields are accessed from the real-time IO proc (arbitrary thread) and from
    // drainMetrics() (timer queue). Both are nonisolated contexts. We protect them with
    // os_unfair_lock; nonisolated(unsafe) tells Swift's isolation checker we handle it manually.
    private nonisolated(unsafe) var rmsLock = os_unfair_lock_s()
    // Accumulated mean-square energy and frame count for the current AGC window.
    // The IO proc adds rms²×frameCount per callback so drainMetrics() computes the true
    // energy-averaged RMS over the whole window (not just the last IO-proc snapshot).
    private nonisolated(unsafe) var _accumulatedMeanSquare: Float = 0
    private nonisolated(unsafe) var _windowFrameCount: Int = 0
    private nonisolated(unsafe) var _tapFrameSize: Int = 512
    // IO proc sets this true each callback; drainMetrics() clears it.
    // Prevents coordinator from acting on stale data when the stream is quiet or paused.
    private nonisolated(unsafe) var _hasFreshData: Bool = false

    // MARK: - Classification sample accumulator
    //
    // Accumulates mono Float32 samples from channel 0 so the coordinator can feed
    // AVAudioPCMBuffer chunks to SoundSceneClassifier.
    //
    // Written inside the real-time IO proc while rmsLock is held; any mutation outside
    // the IO proc must also hold rmsLock.  [Float32] element access (subscript mutation)
    // is real-time safe: no ARC, no heap allocation for a pre-sized array whose count
    // never changes.
    //
    // Buffer size: ~0.5 s at 48 kHz = 24000 samples.
    private let classifCapacity: Int = 24000
    private nonisolated(unsafe) var classifBuf: [Float32] = [Float32](repeating: 0, count: 24000)
    private nonisolated(unsafe) var classifWritePos: Int = 0
    private nonisolated(unsafe) var classifReady: Bool = false

    /// Atomically read the window-averaged K-weighted RMS and frame size, then reset the
    /// accumulator for the next window.
    /// Returns nil if no new audio data has arrived since the last call (IO proc not invoked).
    nonisolated func drainMetrics() -> (rms: Float, frameSize: Int)? {
        os_unfair_lock_lock(&rmsLock)
        defer { os_unfair_lock_unlock(&rmsLock) }
        guard _hasFreshData else { return nil }
        _hasFreshData = false
        let rms =
            _windowFrameCount > 0
            ? sqrtf(_accumulatedMeanSquare / Float(_windowFrameCount)) : 0
        _accumulatedMeanSquare = 0
        _windowFrameCount = 0
        return (rms, _tapFrameSize)
    }

    /// Atomically drain the accumulated classification buffer if a full chunk is ready.
    ///
    /// Returns a mono Float32 array of `classifCapacity` samples, or nil if the buffer
    /// is not yet full.  The caller is responsible for wrapping it in an AVAudioPCMBuffer.
    ///
    /// - Note: Briefly holds `rmsLock`, blocking the IO proc for the duration of an
    ///         array copy (~5 μs for 96 KB on modern hardware).  This is acceptable given
    ///         the 10 ms IO proc interval.
    nonisolated func drainClassificationSamples() -> [Float32]? {
        os_unfair_lock_lock(&rmsLock)
        defer { os_unfair_lock_unlock(&rmsLock) }
        guard classifReady else { return nil }
        let copy = classifBuf
        classifReady = false
        return copy
    }

    // K-weighting filter — initialized in start() with actual sample rate and channel count.
    // Accessed only from the real-time IO proc (single-threaded), except reset in start()
    // which runs before the IO proc starts, so no lock is needed.
    private nonisolated(unsafe) var kFilter: KWeightingFilter = KWeightingFilter(
        sampleRate: 48000, channelCount: 2)

    // Bitmask where bit N is 1 if channel N is an LFE channel (should be excluded from
    // loudness measurement per ITU-R BS.1770).  Written once in start() from the output
    // device's preferred channel layout, before the IO proc is registered.
    private nonisolated(unsafe) var lfeChannelMask: UInt64 = 0

    // Maximum number of channels to include in the K-weighted RMS.
    // Set to 2 when the channel layout cannot be determined for a multi-channel device,
    // so unidentified LFE content is excluded conservatively.  Int.max otherwise.
    private nonisolated(unsafe) var maxActiveChannels: Int = Int.max

    private nonisolated(unsafe) var tapID: AudioObjectID = kAudioObjectUnknown
    private nonisolated(unsafe) var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private nonisolated(unsafe) var deviceProcID: AudioDeviceIOProcID?
    private nonisolated(unsafe) var outputDeviceUID: String = ""

    enum TapError: Error {
        case createTapFailed(OSStatus)
        case readFormatFailed(OSStatus)
        case unsupportedFormat
        case createAggregateFailed(OSStatus)
        case startFailed(OSStatus)
    }

    func start(outputDeviceUID: String) throws {
        self.outputDeviceUID = outputDeviceUID
        // Reset accumulator state so a reused instance (e.g. via rebuildTap()) does not
        // carry stale energy from the previous session into the first AGC window.
        // The IO proc has not started yet, so no lock is required.
        _accumulatedMeanSquare = 0
        _windowFrameCount = 0
        _hasFreshData = false
        classifWritePos = 0
        classifReady = false

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapErr = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapErr == noErr else { throw TapError.createTapFailed(tapErr) }
        tapID = newTapID

        // Verify the tap format is Float32 PCM; measureRMSRealtime handles both
        // interleaved and non-interleaved via per-channel vDSP strides.
        var asbd = AudioStreamBasicDescription()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let fmtErr = AudioObjectGetPropertyData(newTapID, &addr, 0, nil, &sz, &asbd)
        guard fmtErr == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.readFormatFailed(fmtErr)
        }
        guard asbd.mFormatID == kAudioFormatLinearPCM,
            (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
            asbd.mBitsPerChannel == 32
        else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.unsupportedFormat
        }
        tapSampleRate = Float(asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000)
        let sr = Double(tapSampleRate)
        let ch = max(1, Int(asbd.mChannelsPerFrame))
        kFilter = KWeightingFilter(sampleRate: sr, channelCount: ch)
        if let lfe = AudioTapMonitor.queryLFEMask(outputDeviceUID: outputDeviceUID) {
            lfeChannelMask = lfe
            maxActiveChannels = Int.max
        } else if ch > 2 {
            // Channel layout unavailable for multi-channel device; conservatively limit to
            // front L+R so unidentified LFE cannot contaminate the loudness measurement.
            log.warning(
                "channel layout unavailable for \(ch)-ch device; AGC limited to front 2 channels"
            )
            lfeChannelMask = 0
            maxActiveChannels = 2
        } else {
            lfeChannelMask = 0
            maxActiveChannels = Int.max
        }

        let aggUID = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VolumeGridTapDevice",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                ]
            ],
        ]
        var newAggID: AudioObjectID = kAudioObjectUnknown
        let aggErr = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggErr == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.createAggregateFailed(aggErr)
        }
        aggregateDeviceID = newAggID

        // IO Proc — real-time safe: no allocations, no ARC, direct AudioBufferList access.
        var procID: AudioDeviceIOProcID?
        let unsafeSelf = Unmanaged.passUnretained(self)
        let procErr = AudioDeviceCreateIOProcIDWithBlock(&procID, newAggID, nil) {
            inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            let monitor = unsafeSelf.takeUnretainedValue()
            // K-weighted RMS: mutates monitor.kFilter (no lock — only IO proc accesses it)
            let (rms, frameCount) = monitor.measureKWeightedRMSFromIOProc(
                bufferList: inInputData)
            os_unfair_lock_lock(&monitor.rmsLock)
            // Accumulate mean square weighted by frame count for window-averaged RMS.
            monitor._accumulatedMeanSquare += rms * rms * Float(frameCount)
            monitor._windowFrameCount += frameCount
            if frameCount > 0 { monitor._tapFrameSize = frameCount }
            monitor._hasFreshData = true

            // Accumulate mono samples (channel 0) for scene classification.
            // Only when the previous chunk has been consumed (classifReady == false).
            if !monitor.classifReady, frameCount > 0 {
                let ablPtr = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: inInputData))
                if let buf = ablPtr.first, let data = buf.mData, buf.mDataByteSize > 0 {
                    let samples = data.assumingMemoryBound(to: Float32.self)
                    let channels = max(1, Int(buf.mNumberChannels))
                    let toAdd = min(frameCount, monitor.classifCapacity - monitor.classifWritePos)
                    for i in 0..<toAdd {
                        monitor.classifBuf[monitor.classifWritePos + i] = samples[i * channels]
                    }
                    monitor.classifWritePos += toAdd
                    if monitor.classifWritePos >= monitor.classifCapacity {
                        monitor.classifWritePos = 0
                        monitor.classifReady = true
                    }
                }
            }

            os_unfair_lock_unlock(&monitor.rmsLock)
        }
        guard procErr == noErr else {
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.startFailed(procErr)
        }
        guard let procID else {
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.startFailed(-1)
        }
        let startErr = AudioDeviceStart(newAggID, procID)
        guard startErr == noErr else {
            AudioDeviceDestroyIOProcID(newAggID, procID)
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.startFailed(startErr)
        }
        deviceProcID = procID
    }

    deinit {
        stop()
    }

    nonisolated func stop() {
        // CoreAudio teardown order: stop IO → destroy procID → destroy aggregate → destroy tap.
        if let procID = deviceProcID {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, procID)
            if stopStatus != noErr {
                log.error("stop: AudioDeviceStop failed, status=\(stopStatus)")
            }
            let destroyProcStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            if destroyProcStatus != noErr {
                log.error("stop: AudioDeviceDestroyIOProcID failed, status=\(destroyProcStatus)")
            }
            deviceProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            let destroyAggStatus = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if destroyAggStatus != noErr {
                log.error(
                    "stop: AudioHardwareDestroyAggregateDevice failed, status=\(destroyAggStatus)")
            }
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            let destroyTapStatus = AudioHardwareDestroyProcessTap(tapID)
            if destroyTapStatus != noErr {
                log.error("stop: AudioHardwareDestroyProcessTap failed, status=\(destroyTapStatus)")
            }
            tapID = kAudioObjectUnknown
        }
    }

    func rebuildTap() throws {
        stop()
        try start(outputDeviceUID: outputDeviceUID)
    }

    // MARK: — K-weighted real-time measurement (instance method, mutates kFilter)

    /// Compute K-weighted RMS from an AudioBufferList.
    ///
    /// Called exclusively from the real-time IO proc.  Mutates `kFilter` without holding
    /// a lock because only the IO proc accesses the filter (it is reset in `start()` before
    /// the IO proc is registered).
    nonisolated private func measureKWeightedRMSFromIOProc(
        bufferList: UnsafePointer<AudioBufferList>
    ) -> (rms: Float, frameCount: Int) {
        var totalMeanSquare: Float = 0
        var channelsSeen = 0  // global channel index across all buffers (includes LFE)
        var channelsIncluded = 0  // non-LFE channels contributing to the RMS average
        var detectedFrameCount = 0

        let ablPtr = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList))
        for buffer in ablPtr {
            guard buffer.mDataByteSize > 0, let data = buffer.mData else { continue }
            let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
            let frameCount =
                Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channelsInBuffer)
            guard frameCount > 0 else { continue }
            detectedFrameCount = frameCount
            let samples = data.assumingMemoryBound(to: Float32.self)
            for ch in 0..<channelsInBuffer {
                let absIndex = channelsSeen
                channelsSeen += 1
                // Skip LFE channels identified at start() from the device channel layout.
                // Also stop once maxActiveChannels are included (conservative fallback when
                // the layout is unavailable for a multi-channel device).
                guard
                    channelsIncluded < maxActiveChannels,
                    absIndex < 64,
                    (lfeChannelMask & (UInt64(1) << absIndex)) == 0
                else {
                    continue
                }
                let kRMS = kFilter.processChannel(
                    absIndex, samples: samples + ch,
                    stride: channelsInBuffer, frameCount: frameCount)
                totalMeanSquare += kRMS * kRMS
                channelsIncluded += 1
            }
        }

        guard channelsIncluded > 0 else { return (0, 0) }
        let finalRMS = sqrt(totalMeanSquare / Float(channelsIncluded))
        return (finalRMS, detectedFrameCount)
    }

    // MARK: — LFE channel detection

    /// Returns a bitmask where bit N is 1 if channel N is LFE.
    ///
    /// Resolves the UID to a device ID, queries `kAudioDevicePropertyPreferredChannelLayout`,
    /// and identifies `kAudioChannelLabel_LFEScreen` / `kAudioChannelLabel_LFE2` channels.
    /// Returns `nil` if the layout cannot be determined (callers treat this as "unknown").
    /// Returns 0 for layouts with no LFE (stereo, mono).
    private static func queryLFEMask(outputDeviceUID uid: String) -> UInt64? {
        var deviceID: AudioDeviceID = kAudioDeviceUnknown
        var cfUID: CFString = uid as CFString
        // AudioValueTranslation requires pointers that outlive the struct, so use nested
        // withUnsafeMutablePointer to keep cfUID and deviceID alive for the entire call.
        let lookupStatus = withUnsafeMutablePointer(to: &cfUID) { cfUIDPtr in
            withUnsafeMutablePointer(to: &deviceID) { devIDPtr in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(cfUIDPtr),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(devIDPtr),
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size))
                var sz = UInt32(MemoryLayout<AudioValueTranslation>.size)
                var uidAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDeviceForUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                return AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &uidAddr, 0, nil, &sz, &translation)
            }
        }
        guard lookupStatus == noErr, deviceID != kAudioDeviceUnknown else { return nil }

        var layoutAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelLayout,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var layoutSz: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(deviceID, &layoutAddr, 0, nil, &layoutSz) == noErr,
            layoutSz >= 12
        else { return nil }

        let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: Int(layoutSz), alignment: 8)
        defer { buf.deallocate() }
        guard
            AudioObjectGetPropertyData(
                deviceID, &layoutAddr, 0, nil, &layoutSz, buf.baseAddress!) == noErr
        else { return nil }

        return parseLFEMask(layoutBuffer: buf.baseAddress!, size: Int(layoutSz))
    }

    /// Parse an `AudioChannelLayout` buffer and return a bitmask of LFE channel indices.
    ///
    /// Returns `nil` for unknown tag-based layouts that cannot be expanded.
    /// Returns 0 for layouts with no LFE.
    private static func parseLFEMask(layoutBuffer ptr: UnsafeMutableRawPointer, size: Int)
        -> UInt64?
    {
        guard size >= 12 else { return nil }
        var tag = ptr.load(as: AudioChannelLayoutTag.self)

        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            let count = Int(ptr.advanced(by: 8).load(as: UInt32.self))
            let stride = MemoryLayout<AudioChannelDescription>.stride  // 20 bytes
            guard size >= 12 + count * stride else { return nil }
            var mask: UInt64 = 0
            for i in 0..<min(count, 63) {
                let label = ptr.advanced(by: 12 + i * stride).load(as: AudioChannelLabel.self)
                if label == kAudioChannelLabel_LFEScreen || label == kAudioChannelLabel_LFE2 {
                    mask |= UInt64(1) << i
                }
            }
            return mask
        }

        if tag == kAudioChannelLayoutTag_UseChannelBitmap {
            // kAudioChannelBit_LFEScreen = 1<<3, kAudioChannelBit_LFE2 = 1<<10
            let lfeBits: UInt32 = (1 << 3) | (1 << 10)
            let bitmap = ptr.advanced(by: 4).load(as: UInt32.self)
            var mask: UInt64 = 0
            var chIdx = 0
            for bit in 0..<32 {
                let bitVal = UInt32(1) << bit
                guard (bitmap & bitVal) != 0 else { continue }
                if (lfeBits & bitVal) != 0 { mask |= UInt64(1) << chIdx }
                chIdx += 1
            }
            return mask
        }

        // Expand a known layout tag to channel descriptions, then recurse once.
        var expandedSz: UInt32 = 0
        AudioFormatGetPropertyInfo(
            kAudioFormatProperty_ChannelLayoutForTag,
            UInt32(MemoryLayout<AudioChannelLayoutTag>.size), &tag, &expandedSz)
        guard expandedSz > 0 else { return nil }
        let expanded = UnsafeMutableRawBufferPointer.allocate(
            byteCount: Int(expandedSz), alignment: 8)
        defer { expanded.deallocate() }
        guard
            AudioFormatGetProperty(
                kAudioFormatProperty_ChannelLayoutForTag,
                UInt32(MemoryLayout<AudioChannelLayoutTag>.size), &tag,
                &expandedSz, expanded.baseAddress!) == noErr
        else { return nil }
        return parseLFEMask(layoutBuffer: expanded.baseAddress!, size: Int(expandedSz))
    }

    // MARK: — Real-time measurement (static, kept for unit tests)

    /// Compute per-channel RMS using vDSP, averaged across all channels.
    /// Handles both interleaved and non-interleaved formats by using per-channel strides.
    /// `internal` so unit tests can exercise RMS math without CoreAudio hardware.
    static func measureRMSRealtime(
        bufferList: UnsafePointer<AudioBufferList>
    ) -> (rms: Float, frameCount: Int) {
        var totalRMS: Float = 0
        var channelCount = 0
        var detectedFrameCount = 0

        // UnsafeMutableAudioBufferListPointer reads from the original allocation,
        // correctly handling the C flexible array member that follows AudioBufferList.
        // (Using withUnsafePointer on a pointee copy would be UB for mNumberBuffers > 1.)
        let ablPtr = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList))
        for buffer in ablPtr {
            guard buffer.mDataByteSize > 0, let data = buffer.mData else { continue }
            let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
            let stride = vDSP_Stride(channelsInBuffer)
            let frameCount =
                Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channelsInBuffer)
            guard frameCount > 0 else { continue }
            detectedFrameCount = frameCount

            let samples = data.assumingMemoryBound(to: Float32.self)

            // Iterate per channel with the correct interleaved stride so each channel
            // is measured independently whether the buffer is interleaved or non-interleaved.
            for ch in 0..<channelsInBuffer {
                // vDSP_rmsqv computes RMS directly; stride extracts the correct channel.
                var rms: Float = 0
                vDSP_rmsqv(samples + ch, stride, &rms, vDSP_Length(frameCount))
                totalRMS += rms
                channelCount += 1
            }
        }

        let finalRMS = channelCount > 0 ? totalRMS / Float(channelCount) : 0
        return (finalRMS, detectedFrameCount)
    }
}
