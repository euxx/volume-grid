import AudioToolbox
import Foundation

// Manages audio device detection and property queries
class AudioDeviceManager {
    // Fetch the default output device ID.
    @discardableResult
    func getDefaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if status == noErr {
            #if DEBUG
                print("Got default device ID: \(deviceID)")
            #endif
            return deviceID
        } else {
            #if DEBUG
                print("Error getting default output device: \(status)")
            #endif
            return 0
        }
    }

    // Update available volume elements (prefer main, then left/right channels).
    @discardableResult
    func detectVolumeElements(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2,
        ]

        var detected: [AudioObjectPropertyElement] = []

        for element in candidates {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            if AudioObjectHasProperty(deviceID, &address) {
                if element == kAudioObjectPropertyElementMain {
                    return [element]
                }
                detected.append(element)
            }
        }

        return detected
    }

    @discardableResult
    func detectMuteElements(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2,
        ]

        var detected: [AudioObjectPropertyElement] = []

        for element in candidates {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            if AudioObjectHasProperty(deviceID, &address) {
                // Verify we can actually read the mute value before considering it supported
                var muted: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                let readStatus = AudioObjectGetPropertyData(
                    deviceID, &address, 0, nil, &size, &muted)

                if readStatus == noErr {
                    if element == kAudioObjectPropertyElementMain {
                        return [element]
                    }
                    detected.append(element)
                }
            }
        }

        return detected
    }

    // Check whether the device supports volume control.
    func supportsVolumeControl(_ deviceID: AudioDeviceID) -> Bool {
        return !detectVolumeElements(for: deviceID).isEmpty
    }

    func supportsMute(_ deviceID: AudioDeviceID) -> Bool {
        return !detectMuteElements(for: deviceID).isEmpty
    }

    // Get the current volume for a device
    func getCurrentVolume(for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement])
        -> Float32?
    {
        guard !elements.isEmpty else { return nil }

        var channelVolumes: [Float32] = []

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            var volume: Float32 = 0.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)

            if status == noErr {
                channelVolumes.append(volume)
            } else {
                #if DEBUG
                    print("Error getting volume for element \(element): \(status)")
                #endif
            }
        }

        guard !channelVolumes.isEmpty else { return nil }

        let total = channelVolumes.reduce(0, +)
        return total / Float32(channelVolumes.count)
    }

    // Set volume for a device
    func setVolume(
        _ scalar: Float32, for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool {
        guard !elements.isEmpty else { return false }

        let value = max(0, min(scalar, 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        var success = false

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            var mutableValue = value
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, size, &mutableValue)
            if status == noErr {
                success = true
            } else {
                #if DEBUG
                    print("Error setting volume for element \(element): \(status)")
                #endif
            }
        }

        return success
    }

    // Set mute state for a device
    func setMuteState(
        _ muted: Bool, for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Bool {
        guard !elements.isEmpty else { return false }

        let muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var success = false

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var mutableValue = muteValue
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, size, &mutableValue)
            if status == noErr {
                success = true
            } else {
                #if DEBUG
                    print("Error setting mute for element \(element): \(status)")
                #endif
            }
        }

        return success
    }

    // Get mute state for a device
    func getMuteState(for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]) -> Bool?
    {
        guard !elements.isEmpty else { return nil }

        var muteDetected = false
        var readAnyChannel = false

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
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

    // Fetch all audio devices
    func getAllDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            #if DEBUG
                print("Error getting devices size: \(status)")
            #endif
            return []
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else {
            #if DEBUG
                print("Error getting devices: \(status)")
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

    // Resolve the device name.
    func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanaged = unmanagedName else {
            #if DEBUG
                print("Error getting device name for \(deviceID): \(status)")
            #endif
            return nil
        }
        let name = unmanaged.takeRetainedValue() as String
        return name
    }
}
