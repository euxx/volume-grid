import AudioToolbox
import Foundation
import os.log

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
}

private let logger = Logger(subsystem: "one.eux.volumegrid", category: "AudioDevice")

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

    nonisolated func makePropertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }

    nonisolated private func getPropertyData<T>(
        deviceID: AudioDeviceID,
        address: inout AudioObjectPropertyAddress,
        value: inout T
    ) -> Bool {
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, baseAddress)
                == noErr
        }
    }

    nonisolated private func setPropertyData<T>(
        deviceID: AudioDeviceID,
        address: inout AudioObjectPropertyAddress,
        value: T
    ) -> Bool {
        var mutableValue = value
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafeBytes(of: &mutableValue) { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, baseAddress)
                == noErr
        }
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
        !detectVolumeElements(for: deviceID).isEmpty
    }

    nonisolated func supportsMute(_ deviceID: AudioDeviceID) -> Bool {
        !detectMuteElements(for: deviceID).isEmpty
    }

    nonisolated func getCurrentVolume(
        for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]
    ) -> Float32? {
        let channelVolumes = elements.compactMap { element -> Float32? in
            var address = makePropertyAddress(
                selector: kAudioDevicePropertyVolumeScalar, element: element)
            var volume: Float32 = 0.0
            return getPropertyData(deviceID: deviceID, address: &address, value: &volume)
                ? volume : nil
        }

        return channelVolumes.isEmpty
            ? nil : channelVolumes.reduce(0, +) / Float32(channelVolumes.count)
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
            success =
                setPropertyData(deviceID: deviceID, address: &address, value: value) || success
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
            success =
                setPropertyData(deviceID: deviceID, address: &address, value: muteValue) || success
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
            if getPropertyData(deviceID: deviceID, address: &address, value: &muted) {
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

    nonisolated func getOutputDevices() -> [AudioDevice] {
        let allDevices = getAllDevices()
        return allDevices.filter { device in
            let supportsAudio = supportsVolumeControl(device.id) || supportsMute(device.id)
            let transportType = getDeviceTransportType(device.id)
            let isNotVirtual = transportType != "Virtual"
            logger.debug(
                "'\(device.name)' (ID: \(device.id), Type: \(transportType), Audio: \(supportsAudio))"
            )
            return supportsAudio && isNotVirtual
        }
    }

    nonisolated func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = deviceNameAddress
        var unmanagedName: Unmanaged<CFString>?
        return getPropertyData(deviceID: deviceID, address: &address, value: &unmanagedName)
            && unmanagedName != nil
            ? unmanagedName!.takeRetainedValue() as String : nil
    }

    nonisolated func getDeviceTransportType(_ deviceID: AudioDeviceID) -> String {
        var address = makePropertyAddress(
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var transportType: UInt32 = 0
        if getPropertyData(deviceID: deviceID, address: &address, value: &transportType) {
            switch transportType {
            case kAudioDeviceTransportTypeBuiltIn:
                return "BuiltIn"
            case kAudioDeviceTransportTypeUSB:
                return "USB"
            case kAudioDeviceTransportTypeFireWire:
                return "FireWire"
            case kAudioDeviceTransportTypeVirtual:
                return "Virtual"
            default:
                return "Unknown(\(transportType))"
            }
        }
        return "Unknown"
    }

    nonisolated func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = defaultOutputDeviceAddress
        return setPropertyData(
            deviceID: AudioObjectID(kAudioObjectSystemObject), address: &address, value: deviceID)
    }
}
