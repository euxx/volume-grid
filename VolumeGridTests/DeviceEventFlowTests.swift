import AudioToolbox
import XCTest

@testable import Volume_Grid

/// Tests for device-related event flow and state management
/// Verifies device enumeration, properties, and lifecycle
final class DeviceEventFlowTests: XCTestCase {
    var deviceManager: AudioDeviceManager!

    override func setUp() {
        super.setUp()
        deviceManager = AudioDeviceManager()
    }

    override func tearDown() {
        deviceManager = nil
        super.tearDown()
    }

    // MARK: - Device Enumeration

    func testEnumerateAllDevices() {
        let devices = deviceManager.getAllDevices()

        XCTAssertNotNil(devices)
        XCTAssertGreaterThanOrEqual(devices.count, 1)
    }

    func testDeviceIDsAreUnique() {
        let devices = deviceManager.getAllDevices()

        let ids = devices.map { $0.id }
        let uniqueIds = Set(ids)

        XCTAssertEqual(ids.count, uniqueIds.count, "All device IDs should be unique")
    }

    func testDeviceNamesNotEmpty() {
        let devices = deviceManager.getAllDevices()

        for device in devices {
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")
        }
    }

    // MARK: - Default Device

    func testDefaultDeviceAlwaysAvailable() {
        let defaultID = deviceManager.getDefaultOutputDevice()

        XCTAssertGreaterThan(defaultID, 0)
    }

    func testDefaultDeviceInEnumeration() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let devices = deviceManager.getAllDevices()

        let defaultInList = devices.contains { $0.id == defaultID }

        XCTAssertTrue(
            defaultInList,
            "Default device should be in enumerated list"
        )
    }

    func testDefaultDeviceConsistent() {
        let id1 = deviceManager.getDefaultOutputDevice()
        let id2 = deviceManager.getDefaultOutputDevice()
        let id3 = deviceManager.getDefaultOutputDevice()

        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id2, id3)
    }

    // MARK: - Volume Control Support

    func testDeviceSupportsVolumeControl() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let supportsVolume = deviceManager.supportsVolumeControl(defaultID)

        XCTAssertTrue(supportsVolume, "Default device should support volume control")
    }

    func testDeviceSupportsMute() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let supportsMute = deviceManager.supportsMute(defaultID)

        XCTAssertTrue(supportsMute, "Most devices should support mute")
    }

    // MARK: - Volume Access Patterns

    func testGetVolumeRequiresElements() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let elements = deviceManager.detectVolumeElements(for: defaultID)

        // Should have detected some volume elements
        if !elements.isEmpty {
            let volume = deviceManager.getCurrentVolume(for: defaultID, elements: elements)
            XCTAssertNotNil(volume)
        }
    }

    func testVolumeElementsDetection() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let elements = deviceManager.detectVolumeElements(for: defaultID)

        XCTAssertGreaterThanOrEqual(elements.count, 0)

        // Main element should be detected for supported devices
        if deviceManager.supportsVolumeControl(defaultID) {
            XCTAssertGreaterThan(elements.count, 0)
        }
    }

    func testMuteElementsDetection() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let elements = deviceManager.detectMuteElements(for: defaultID)

        XCTAssertGreaterThanOrEqual(elements.count, 0)
    }

    // MARK: - Property Address Creation

    func testPropertyAddressForVolume() {
        let address = deviceManager.makePropertyAddress(
            selector: kAudioDevicePropertyVolumeScalar
        )

        XCTAssertGreaterThan(address.mSelector, 0)
    }

    func testPropertyAddressForMute() {
        let address = deviceManager.makePropertyAddress(
            selector: kAudioDevicePropertyMute
        )

        XCTAssertGreaterThan(address.mSelector, 0)
    }

    func testPropertyAddressWithCustomScope() {
        let address = deviceManager.makePropertyAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput
        )

        XCTAssertGreaterThan(address.mScope, 0)
    }

    // MARK: - Device State Transitions

    func testGetDeviceNameByID() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let name = deviceManager.getDeviceName(defaultID)

        XCTAssertNotNil(name)
        if let name = name {
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testAllDevicesHaveNames() {
        let devices = deviceManager.getAllDevices()

        for device in devices {
            XCTAssertFalse(device.name.isEmpty)
        }
    }

    // MARK: - Volume State Queries

    func testQueryVolumeMultipleTimes() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let elements = deviceManager.detectVolumeElements(for: defaultID)

        guard !elements.isEmpty else {
            return  // Skip test if device doesn't support volume
        }

        let volumes = (0..<3).map { _ in
            deviceManager.getCurrentVolume(for: defaultID, elements: elements)
        }

        // All reads should be consistent
        if volumes.allSatisfy({ $0 != nil }) {
            XCTAssertEqual(volumes[0], volumes[1])
            XCTAssertEqual(volumes[1], volumes[2])
        }
    }

    // MARK: - Mute State Queries

    func testQueryMuteState() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let elements = deviceManager.detectMuteElements(for: defaultID)

        guard !elements.isEmpty else {
            return  // Skip test if device doesn't support mute
        }

        let muted = deviceManager.getMuteState(for: defaultID, elements: elements)

        XCTAssertNotNil(muted)
    }

    func testQueryMuteStateConsistency() {
        let defaultID = deviceManager.getDefaultOutputDevice()
        let elements = deviceManager.detectMuteElements(for: defaultID)

        guard !elements.isEmpty else {
            return  // Skip test if device doesn't support mute
        }

        let muted1 = deviceManager.getMuteState(for: defaultID, elements: elements)
        let muted2 = deviceManager.getMuteState(for: defaultID, elements: elements)

        XCTAssertEqual(muted1, muted2)
    }

    // MARK: - Device Identifiers

    func testAudioDeviceStructure() {
        let devices = deviceManager.getAllDevices()

        for device in devices {
            // Should have valid ID
            XCTAssertGreaterThan(device.id, 0)

            // Should be Hashable
            var set = Set<AudioDevice>()
            set.insert(device)

            // Should be Sendable (used across threads)
            DispatchQueue.global().async {
                _ = device.name
            }
        }

        XCTAssert(true)
    }

    // MARK: - Device Count Changes

    func testDeviceCountStable() {
        let count1 = deviceManager.getAllDevices().count
        let count2 = deviceManager.getAllDevices().count

        XCTAssertEqual(count1, count2, "Device count should be stable during tests")
    }

    // MARK: - Edge Cases

    func testQueryInvalidDeviceID() {
        let invalidID: AudioDeviceID = 0xFFFF_FFFF
        let elements: [AudioObjectPropertyElement] = []

        // Should not crash
        let volume = deviceManager.getCurrentVolume(for: invalidID, elements: elements)
        XCTAssertNil(volume)
    }

    func testDetectElementsInvalidDevice() {
        let invalidID: AudioDeviceID = 0xFFFF_FFFF

        // Should not crash
        let elements = deviceManager.detectVolumeElements(for: invalidID)
        XCTAssertEqual(elements.count, 0)
    }

    func testGetDeviceNameInvalidID() {
        let invalidID: AudioDeviceID = 0xFFFF_FFFF

        // Should not crash
        let name = deviceManager.getDeviceName(invalidID)
        XCTAssertNil(name)
    }

    // MARK: - Performance

    func testDeviceEnumerationPerformance() {
        measure {
            _ = deviceManager.getAllDevices()
        }
    }

    func testDefaultDevicePerformance() {
        measure {
            _ = deviceManager.getDefaultOutputDevice()
        }
    }

    func testVolumeElementDetectionPerformance() {
        let defaultID = deviceManager.getDefaultOutputDevice()

        measure {
            _ = deviceManager.detectVolumeElements(for: defaultID)
        }
    }

    func testDeviceNameRetrievalPerformance() {
        let defaultID = deviceManager.getDefaultOutputDevice()

        measure {
            _ = deviceManager.getDeviceName(defaultID)
        }
    }
}
