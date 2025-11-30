import Foundation
import XCTest

@testable import Volume_Grid

// MARK: - HUDEvent Structure Tests

final class HUDEventTests: XCTestCase {

    // MARK: - Basic Event Creation

    func testHUDEventCreation() {
        let testCases: [(scalar: CGFloat, deviceName: String?, isUnsupported: Bool)] = [
            (0.5, "Test Device", false),
            (0.0, "Speaker", false),
            (1.0, "Headphones", false),
            (0.5, nil, false),
            (0.5, "", true),
            (0.75, "USB Audio", true),
        ]

        for testCase in testCases {
            let event = HUDEvent(
                volumeScalar: testCase.scalar,
                deviceName: testCase.deviceName,
                isUnsupported: testCase.isUnsupported
            )

            XCTAssertEqual(event.volumeScalar, testCase.scalar, accuracy: 0.001)
            XCTAssertEqual(event.deviceName, testCase.deviceName)
            XCTAssertEqual(event.isUnsupported, testCase.isUnsupported)
        }
    }

    // MARK: - Device Name Handling

    func testHUDEventWithVariousDeviceNames() {
        let deviceNames = [
            "Built-in Output",
            "USB Speakers",
            "Headphones",
            "HDMI Output",
            "",
            "Very Long Device Name With Many Characters",
            "🔊 Speaker",
            "输出设备",
            nil,
        ]

        for deviceName in deviceNames {
            let event = HUDEvent(volumeScalar: 0.5, deviceName: deviceName, isUnsupported: false)
            XCTAssertEqual(event.deviceName, deviceName)
        }
    }

    // MARK: - Unsupported Device Marking

    func testHUDEventUnsupportedFlag() {
        let supported = HUDEvent(volumeScalar: 0.5, deviceName: "Device", isUnsupported: false)
        let unsupported = HUDEvent(volumeScalar: 0.5, deviceName: "Device", isUnsupported: true)

        XCTAssertFalse(supported.isUnsupported)
        XCTAssertTrue(unsupported.isUnsupported)
    }

    // MARK: - Volume Range

    func testHUDEventVolumeRange() {
        let testVolumes: [CGFloat] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]

        for volume in testVolumes {
            let event = HUDEvent(volumeScalar: volume, deviceName: "Test", isUnsupported: false)
            XCTAssertEqual(event.volumeScalar, volume, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(event.volumeScalar, 0.0)
            XCTAssertLessThanOrEqual(event.volumeScalar, 1.0)
        }
    }
}

// MARK: - HUDConstants Tests

final class HUDConstantsTests: XCTestCase {

    func testHUDConstantsExist() {
        XCTAssertGreaterThan(VolumeGridConstants.HUD.width, 0)
        XCTAssertGreaterThan(VolumeGridConstants.HUD.height, 0)
        XCTAssertGreaterThan(VolumeGridConstants.HUD.alpha, 0)
        XCTAssertLessThanOrEqual(VolumeGridConstants.HUD.alpha, 1.0)
    }

    func testHUDAnimationLogicalOrder() {
        let fadeIn = VolumeGridConstants.HUD.fadeInDuration
        let fadeOut = VolumeGridConstants.HUD.fadeOutDuration
        let displayDuration = VolumeGridConstants.HUD.displayDuration

        XCTAssertGreaterThan(fadeIn, 0)
        XCTAssertGreaterThan(fadeOut, fadeIn, "Fade-out should be longer than fade-in")
        XCTAssertGreaterThan(displayDuration, fadeOut, "Display duration should exceed fade-out")
    }

    func testHUDLayoutConstraints() {
        XCTAssertGreaterThan(VolumeGridConstants.HUD.Layout.iconSize, 0)
        XCTAssertGreaterThanOrEqual(VolumeGridConstants.HUD.Layout.spacingIconToDevice, 0)
        XCTAssertGreaterThanOrEqual(VolumeGridConstants.HUD.Layout.spacingDeviceToBlocks, 0)
        XCTAssertGreaterThan(VolumeGridConstants.HUD.VolumeBlocksView.blockHeight, 0)
    }

    func testHUDDimensionsConsistency() {
        // Dimensions should form reasonable proportions
        let width = VolumeGridConstants.HUD.width
        let height = VolumeGridConstants.HUD.height

        XCTAssert(width > 100 && width < 1000, "HUD width should be reasonable")
        XCTAssert(height > 50 && height < 500, "HUD height should be reasonable")
    }
}

// MARK: - Mock Helpers

class MockSystemEventMonitor {
    var volumeKeyPressHandler: (() -> Void)?

    func simulateVolumeKeyPress(keyCode: Int) {
        volumeKeyPressHandler?()
    }
}

class MockAudioDeviceManager {
    private var devices: [String: AudioDevice] = [:]
    private var currentDevice: String?

    func addDevice(name: String) {
        devices[name] = AudioDevice(id: UInt32(devices.count), name: name)
    }

    func setDefaultOutputDevice(name: String) {
        currentDevice = name
    }

    func switchToDevice(name: String) {
        currentDevice = name
    }

    func getCurrentDevice() -> String? {
        currentDevice
    }
}
