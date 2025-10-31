import AudioToolbox
import Foundation

/// Audio device model.
struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
}

/// Manages audio device detection and property queries.
/// All methods are nonisolated and thread-safe as they only interact with CoreAudio APIs.
final class AudioDeviceManager: Sendable {
    private nonisolated let defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: 0
    )

    private nonisolated let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: 0
    )

    private nonisolated let deviceNameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: 0
    )

    nonisolated init() {}

    /// Creates an AudioObjectPropertyAddress with common defaults
    nonisolated private func makePropertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    nonisolated private func detectElements(
        for deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        verifyReadable: Bool = false
    ) -> [AudioObjectPropertyElement] {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain, 1, 2,
        ]

        var detected: [AudioObjectPropertyElement] = []

        for element in candidates {
            var address = makePropertyAddress(selector: selector, element: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            if verifyReadable {
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
                else { continue }
            }

            if element == kAudioObjectPropertyElementMain {
                return [element]
            }
            detected.append(element)
        }

        return detected
    }

    @discardableResult
    nonisolated func getDefaultOutputDevice() -> AudioDeviceID {
        var address = defaultOutputDeviceAddress
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : 0
    }

    @discardableResult
    nonisolated func detectVolumeElements(for deviceID: AudioDeviceID)
        -> [AudioObjectPropertyElement]
    {
        detectElements(for: deviceID, selector: kAudioDevicePropertyVolumeScalar)
    }

    @discardableResult
    nonisolated func detectMuteElements(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement]
    {
        detectElements(for: deviceID, selector: kAudioDevicePropertyMute, verifyReadable: true)
    }

    nonisolated func supportsVolumeControl(_ deviceID: AudioDeviceID) -> Bool {
        return !detectVolumeElements(for: deviceID).isEmpty
    }

    nonisolated func supportsMute(_ deviceID: AudioDeviceID) -> Bool {
        return !detectMuteElements(for: deviceID).isEmpty
    }

    nonisolated func getCurrentVolume(
        for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Float32? {
        guard !elements.isEmpty else { return nil }

        let channelVolumes = elements.compactMap { element -> Float32? in
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyVolumeScalar, element: element)
            var volume: Float32 = 0.0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr
                ? volume : nil
        }

        guard !channelVolumes.isEmpty else { return nil }
        return channelVolumes.reduce(0, +) / Float32(channelVolumes.count)
    }

    nonisolated func setVolume(
        _ scalar: Float32, for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool {
        guard !elements.isEmpty else { return false }

        let value = max(0, min(scalar, 1))
        var success = false

        for element in elements {
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyVolumeScalar, element: element)
            var mutableValue = value
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutableValue)
            if status == noErr {
                success = true
            }
        }

        return success
    }

    nonisolated func setMuteState(
        _ muted: Bool, for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool {
        guard !elements.isEmpty else { return false }

        let muteValue: UInt32 = muted ? 1 : 0
        var success = false

        for element in elements {
            var address = makePropertyAddress(selector: kAudioDevicePropertyMute, element: element)
            var mutableValue = muteValue
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mutableValue)
            if status == noErr {
                success = true
            }
        }

        return success
    }

    nonisolated func getMuteState(
        for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool? {
        guard !elements.isEmpty else { return nil }

        var muteDetected = false
        var readAnyChannel = false

        for element in elements {
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyMute,
                element: element
            )

            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(
                deviceID, &address, 0, nil, &size, &muted)
            if status == noErr {
                readAnyChannel = true
                if muted != 0 {
                    muteDetected = true
                    break
                }
            }
        }

        guard readAnyChannel else { return nil }
        return muteDetected
    }

    nonisolated func getAllDevices() -> [AudioDevice] {
        var address = devicesAddress
        var size: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
                == noErr
        else { return [] }

        return deviceIDs.compactMap { deviceID in
            getDeviceName(deviceID).map { AudioDevice(id: deviceID, name: $0) }
        }
    }

    nonisolated func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = deviceNameAddress
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanaged = unmanagedName else { return nil }
        return unmanaged.takeRetainedValue() as String
    }
}
