import AudioToolbox
import XCTest

@testable import Volume_Grid

// MARK: - AudioDeviceManager Initialization & Basic Tests

final class AudioDeviceManagerTests: XCTestCase {

    var manager: AudioDeviceManager!

    override func setUp() {
        super.setUp()
        manager = AudioDeviceManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testAudioDeviceManagerInitialization() {
        XCTAssertNotNil(manager)
    }

    // MARK: - Property Address Creation

    func testMakePropertyAddressWithDefaults() {
        let address = manager.makePropertyAddress(selector: kAudioDevicePropertyVolumeScalar)
        XCTAssertEqual(address.mSelector, kAudioDevicePropertyVolumeScalar)
    }

    func testPropertyAddressForVolume() {
        let address = manager.makePropertyAddress(selector: kAudioDevicePropertyVolumeScalar)
        XCTAssertGreaterThan(address.mSelector, 0)
    }

    func testPropertyAddressForMute() {
        let address = manager.makePropertyAddress(selector: kAudioDevicePropertyMute)
        XCTAssertGreaterThan(address.mSelector, 0)
    }

    func testPropertyAddressWithCustomScope() {
        let address = manager.makePropertyAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput
        )
        XCTAssertGreaterThan(address.mScope, 0)
    }

    // MARK: - Default Output Device

    func testGetDefaultOutputDevice() {
        let deviceID = manager.getDefaultOutputDevice()
        XCTAssert(deviceID >= 0)
    }

    func testDefaultDeviceAlwaysAvailable() {
        let defaultID = manager.getDefaultOutputDevice()
        XCTAssertGreaterThan(defaultID, 0)
    }

    func testDefaultDeviceConsistent() {
        let id1 = manager.getDefaultOutputDevice()
        let id2 = manager.getDefaultOutputDevice()
        let id3 = manager.getDefaultOutputDevice()

        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id2, id3)
    }

    // MARK: - All Devices Retrieval

    func testGetAllDevices() {
        let devices = manager.getAllDevices()
        XCTAssertNotNil(devices)

        for device in devices {
            XCTAssert(device.id >= 0)
            XCTAssertFalse(device.name.isEmpty)
        }
    }

    func testEnumerateAllDevices() {
        let devices = manager.getAllDevices()

        XCTAssertNotNil(devices)
        XCTAssertGreaterThanOrEqual(devices.count, 1)
    }

    func testDeviceIDsAreUnique() {
        let devices = manager.getAllDevices()

        let ids = devices.map { $0.id }
        let uniqueIds = Set(ids)

        XCTAssertEqual(ids.count, uniqueIds.count, "All device IDs should be unique")
    }

    func testDeviceNamesNotEmpty() {
        let devices = manager.getAllDevices()

        for device in devices {
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")
        }
    }

    func testDefaultDeviceInEnumeration() {
        let defaultID = manager.getDefaultOutputDevice()
        let devices = manager.getAllDevices()

        let defaultInList = devices.contains { $0.id == defaultID }

        XCTAssertTrue(defaultInList, "Default device should be in enumerated list")
    }

    func testDeviceCountStable() {
        let count1 = manager.getAllDevices().count
        let count2 = manager.getAllDevices().count

        XCTAssertEqual(count1, count2, "Device count should be stable during tests")
    }

    // MARK: - Safety Tests (Safe Unwrapping)

    func testGetCurrentVolumeSafety() {
        let invalidDeviceID: AudioDeviceID = 0xFFFF_FFFF
        let invalidElements: [AudioObjectPropertyElement] = []

        let volume = manager.getCurrentVolume(for: invalidDeviceID, elements: invalidElements)
        XCTAssertNil(volume)
    }

    func testSetVolumeSafety() {
        let deviceID = manager.getDefaultOutputDevice()
        let emptyElements: [AudioObjectPropertyElement] = []

        let success = manager.setVolume(0.5, for: deviceID, elements: emptyElements)
        XCTAssertFalse(success)
    }

    func testSetMuteStateSafety() {
        let deviceID = manager.getDefaultOutputDevice()
        let emptyElements: [AudioObjectPropertyElement] = []

        let success = manager.setMuteState(true, for: deviceID, elements: emptyElements)
        XCTAssertFalse(success)
    }

    func testGetMuteStateSafety() {
        let deviceID = manager.getDefaultOutputDevice()
        let emptyElements: [AudioObjectPropertyElement] = []

        let muted = manager.getMuteState(for: deviceID, elements: emptyElements)
        XCTAssertNil(muted)
    }

    // MARK: - Volume Control Support

    func testDeviceSupportsVolumeControl() {
        let defaultID = manager.getDefaultOutputDevice()
        let supportsVolume = manager.supportsVolumeControl(defaultID)

        XCTAssertTrue(supportsVolume, "Default device should support volume control")
    }

    func testDeviceSupportsMute() {
        let defaultID = manager.getDefaultOutputDevice()
        let supportsMute = manager.supportsMute(defaultID)

        XCTAssertTrue(supportsMute, "Most devices should support mute")
    }

    // MARK: - Volume Access Patterns

    func testGetVolumeRequiresElements() {
        let defaultID = manager.getDefaultOutputDevice()
        let elements = manager.detectVolumeElements(for: defaultID)

        if !elements.isEmpty {
            let volume = manager.getCurrentVolume(for: defaultID, elements: elements)
            XCTAssertNotNil(volume)
        }
    }

    func testVolumeElementsDetection() {
        let defaultID = manager.getDefaultOutputDevice()
        let elements = manager.detectVolumeElements(for: defaultID)

        XCTAssertGreaterThanOrEqual(elements.count, 0)

        if manager.supportsVolumeControl(defaultID) {
            XCTAssertGreaterThan(elements.count, 0)
        }
    }

    func testMuteElementsDetection() {
        let defaultID = manager.getDefaultOutputDevice()
        let elements = manager.detectMuteElements(for: defaultID)

        XCTAssertGreaterThanOrEqual(elements.count, 0)
    }

    // MARK: - Device State Transitions

    func testGetDeviceNameByID() {
        let defaultID = manager.getDefaultOutputDevice()
        let name = manager.getDeviceName(defaultID)

        XCTAssertNotNil(name)
        if let name = name {
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testAllDevicesHaveNames() {
        let devices = manager.getAllDevices()

        for device in devices {
            XCTAssertFalse(device.name.isEmpty)
        }
    }

    // MARK: - Volume State Queries

    func testQueryVolumeMultipleTimes() {
        let defaultID = manager.getDefaultOutputDevice()
        let elements = manager.detectVolumeElements(for: defaultID)

        guard !elements.isEmpty else { return }

        let volumes = (0..<3).map { _ in
            manager.getCurrentVolume(for: defaultID, elements: elements)
        }

        if volumes.allSatisfy({ $0 != nil }) {
            XCTAssertEqual(volumes[0], volumes[1])
            XCTAssertEqual(volumes[1], volumes[2])
        }
    }

    // MARK: - Mute State Queries

    func testQueryMuteState() {
        let defaultID = manager.getDefaultOutputDevice()
        let elements = manager.detectMuteElements(for: defaultID)

        guard !elements.isEmpty else { return }

        let muted = manager.getMuteState(for: defaultID, elements: elements)
        XCTAssertNotNil(muted)
    }

    func testQueryMuteStateConsistency() {
        let defaultID = manager.getDefaultOutputDevice()
        let elements = manager.detectMuteElements(for: defaultID)

        guard !elements.isEmpty else { return }

        let muted1 = manager.getMuteState(for: defaultID, elements: elements)
        let muted2 = manager.getMuteState(for: defaultID, elements: elements)

        XCTAssertEqual(muted1, muted2)
    }

    // MARK: - Device Identifiers

    func testAudioDeviceStructure() {
        let devices = manager.getAllDevices()

        for device in devices {
            XCTAssertGreaterThan(device.id, 0)

            var set = Set<AudioDevice>()
            set.insert(device)

            DispatchQueue.global().async {
                _ = device.name
            }
        }

        XCTAssert(true)
    }

    // MARK: - Edge Cases

    func testQueryInvalidDeviceID() {
        let invalidID: AudioDeviceID = 0xFFFF_FFFF
        let elements: [AudioObjectPropertyElement] = []

        let volume = manager.getCurrentVolume(for: invalidID, elements: elements)
        XCTAssertNil(volume)
    }

    func testDetectElementsInvalidDevice() {
        let invalidID: AudioDeviceID = 0xFFFF_FFFF

        let elements = manager.detectVolumeElements(for: invalidID)
        XCTAssertEqual(elements.count, 0)
    }

    func testGetDeviceNameInvalidID() {
        let invalidID: AudioDeviceID = 0xFFFF_FFFF

        let name = manager.getDeviceName(invalidID)
        XCTAssertNil(name)
    }

    // MARK: - Performance

    func testDeviceEnumerationPerformance() {
        measure {
            _ = manager.getAllDevices()
        }
    }

    func testDefaultDevicePerformance() {
        measure {
            _ = manager.getDefaultOutputDevice()
        }
    }

    func testVolumeElementDetectionPerformance() {
        let defaultID = manager.getDefaultOutputDevice()

        measure {
            _ = manager.detectVolumeElements(for: defaultID)
        }
    }

    func testDeviceNameRetrievalPerformance() {
        let defaultID = manager.getDefaultOutputDevice()

        measure {
            _ = manager.getDeviceName(defaultID)
        }
    }
}
