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
    private nonisolated(unsafe) var _latestRMS: Float = 0
    private nonisolated(unsafe) var _tapFrameSize: Int = 512
    // IO proc sets this true each callback; drainMetrics() clears it.
    // Prevents coordinator from acting on stale data when the stream is quiet or paused.
    private nonisolated(unsafe) var _hasFreshData: Bool = false

    /// Atomically read the latest RMS and frame size.
    /// Returns nil if no new audio data has arrived since the last call (IO proc not invoked).
    nonisolated func drainMetrics() -> (rms: Float, frameSize: Int)? {
        os_unfair_lock_lock(&rmsLock)
        defer { os_unfair_lock_unlock(&rmsLock) }
        guard _hasFreshData else { return nil }
        _hasFreshData = false
        return (_latestRMS, _tapFrameSize)
    }

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
            let (rms, frameCount) = AudioTapMonitor.measureRMSRealtime(bufferList: inInputData)
            os_unfair_lock_lock(&monitor.rmsLock)
            monitor._latestRMS = rms
            if frameCount > 0 { monitor._tapFrameSize = frameCount }
            monitor._hasFreshData = true
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

    // MARK: — Real-time measurement (static, no Swift object access)

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
