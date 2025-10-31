import AudioToolbox
import Foundation

/// Audio device model.
struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
}

/// Manages audio device detection and property queries.
final class AudioDeviceManager: @unchecked Sendable {
    // Pre-defined addresses for common operations
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

    /// Detects available elements for a given property selector
    nonisolated private func detectElements(
        for deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        verifyReadable: Bool = false
    ) -> [AudioObjectPropertyElement] {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2,
        ]

        var detected: [AudioObjectPropertyElement] = []

        for element in candidates {
            var address = makePropertyAddress(selector: selector, element: element)

            if AudioObjectHasProperty(deviceID, &address) {
                if verifyReadable {
                    // Verify we can actually read the value
                    var value: UInt32 = 0
                    var size = UInt32(MemoryLayout<UInt32>.size)
                    let readStatus = AudioObjectGetPropertyData(
                        deviceID, &address, 0, nil, &size, &value)
                    guard readStatus == noErr else { continue }
                }

                if element == kAudioObjectPropertyElementMain {
                    return [element]
                }
                detected.append(element)
            }
        }

        return detected
    }

    #if DEBUG
        /// Logs debug messages
        nonisolated private func log(_ message: String) {
            print("[AudioDeviceManager] \(message)")
        }
    #endif

    // Fetch the default output device ID.
    @discardableResult
    nonisolated func getDefaultOutputDevice() -> AudioDeviceID {
        var address = defaultOutputDeviceAddress

        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if status == noErr {
            #if DEBUG
                log("Got default device ID: \(deviceID)")
            #endif
            return deviceID
        } else {
            #if DEBUG
                log("Error getting default output device: \(status)")
            #endif
            return 0
        }
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
    )
        -> Float32?
    {
        guard !elements.isEmpty else { return nil }

        var channelVolumes: [Float32] = []

        for element in elements {
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )

            var volume: Float32 = 0.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)

            if status == noErr {
                channelVolumes.append(volume)
            } else {
                #if DEBUG
                    log("Error getting volume for element \(element): \(status)")
                #endif
            }
        }

        guard !channelVolumes.isEmpty else { return nil }

        let total = channelVolumes.reduce(0, +)
        return total / Float32(channelVolumes.count)
    }

    nonisolated func setVolume(
        _ scalar: Float32, for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool {
        guard !elements.isEmpty else { return false }

        let value = max(0, min(scalar, 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        var success = false

        for element in elements {
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )

            var mutableValue = value
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, size, &mutableValue)
            if status == noErr {
                success = true
            } else {
                #if DEBUG
                    log("Error setting volume for element \(element): \(status)")
                #endif
            }
        }

        return success
    }

    nonisolated func setMuteState(
        _ muted: Bool, for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool {
        guard !elements.isEmpty else { return false }

        let muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var success = false

        for element in elements {
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyMute,
                element: element
            )
            var mutableValue = muteValue
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, size, &mutableValue)
            if status == noErr {
                success = true
            } else {
                #if DEBUG
                    log("Error setting mute for element \(element): \(status)")
                #endif
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
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            #if DEBUG
                log("Error getting devices size: \(status)")
            #endif
            return []
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else {
            #if DEBUG
                log("Error getting devices: \(status)")
            #endif
            return []
        }

        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            if let name = getDeviceName(deviceID) {
                devices.append(AudioDevice(id: deviceID, name: name))
            }
        }

        return devices
    }

    nonisolated func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = deviceNameAddress

        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanaged = unmanagedName else {
            #if DEBUG
                log("Error getting device name for \(deviceID): \(status)")
            #endif
            return nil
        }
        let name = unmanaged.takeRetainedValue() as String
        return name
    }
}
