import AudioToolbox
import XCTest

@testable import Volume_Grid

/// Basic tests for AudioDeviceManager to ensure safe CoreAudio interactions
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

    // MARK: - Initialization Tests

    func testAudioDeviceManagerInitialization() {
        XCTAssertNotNil(manager)
    }

    // MARK: - Property Address Creation Tests

    func testMakePropertyAddressWithDefaults() {
        let address = manager.makePropertyAddress(selector: kAudioDevicePropertyVolumeScalar)
        XCTAssertEqual(address.mSelector, kAudioDevicePropertyVolumeScalar)
    }

    // MARK: - Default Output Device Tests

    func testGetDefaultOutputDevice() {
        let deviceID = manager.getDefaultOutputDevice()
        XCTAssert(deviceID >= 0)
    }

    // MARK: - All Devices Retrieval Tests

    func testGetAllDevices() {
        let devices = manager.getAllDevices()
        XCTAssertNotNil(devices)

        // Validate all devices have valid structure
        for device in devices {
            XCTAssert(device.id >= 0)
            XCTAssertFalse(device.name.isEmpty)
        }
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
}
