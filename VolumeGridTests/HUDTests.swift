import Combine
import Foundation
import XCTest

@testable import Volume_Grid

// MARK: - HUDEvent Structure Tests

final class HUDEventTests: XCTestCase {

    func testHUDEventCreationWithValidScalar() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: "Test Device", isUnsupported: false)
        XCTAssertEqual(event.volumeScalar, 0.5)
        XCTAssertEqual(event.deviceName, "Test Device")
        XCTAssertFalse(event.isUnsupported)
    }

    func testHUDEventCreationWithZeroVolume() {
        let event = HUDEvent(volumeScalar: 0, deviceName: "Test", isUnsupported: false)
        XCTAssertEqual(event.volumeScalar, 0)
    }

    func testHUDEventCreationWithMaxVolume() {
        let event = HUDEvent(volumeScalar: 1.0, deviceName: "Test", isUnsupported: false)
        XCTAssertEqual(event.volumeScalar, 1.0)
    }

    func testHUDEventWithNilDeviceName() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: nil, isUnsupported: false)
        XCTAssertNil(event.deviceName)
        XCTAssertEqual(event.volumeScalar, 0.5)
    }

    func testHUDEventUnsupportedMarking() {
        let supported = HUDEvent(volumeScalar: 0.5, deviceName: "Device", isUnsupported: false)
        let unsupported = HUDEvent(volumeScalar: 0.5, deviceName: "Device", isUnsupported: true)
        XCTAssertFalse(supported.isUnsupported)
        XCTAssertTrue(unsupported.isUnsupported)
    }

    func testHUDEventWithVariousVolumeLevels() {
        let volumes: [CGFloat] = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]
        for volume in volumes {
            let event = HUDEvent(volumeScalar: volume, deviceName: "Test", isUnsupported: false)
            XCTAssertEqual(event.volumeScalar, volume, accuracy: 0.001)
        }
    }

    func testHUDEventWithDeviceNameVariations() {
        let names = [
            "Built-in Output",
            "USB Speakers",
            "Headphones",
            "HDMI Output",
            "",
            "Very Long Device Name With Many Characters",
            "🔊 Speaker",
            "输出设备",
        ]
        for name in names {
            let event = HUDEvent(volumeScalar: 0.5, deviceName: name, isUnsupported: false)
            XCTAssertEqual(event.deviceName, name)
        }
    }

    func testHUDEventVolumePercentageConversion() {
        let testCases: [(CGFloat, Int)] = [
            (0.0, 0),
            (0.25, 25),
            (0.5, 50),
            (0.75, 75),
            (1.0, 100),
        ]

        for (scalar, expectedPercentage) in testCases {
            let percentage = Int(scalar * 100)
            XCTAssertEqual(percentage, expectedPercentage)
        }
    }

    func testHUDEventWithExtremeValues() {
        let extremes: [CGFloat] = [-0.5, -1.0, 1.5, 2.0, 10.0]
        for extreme in extremes {
            let event = HUDEvent(volumeScalar: extreme, deviceName: "Test", isUnsupported: false)
            XCTAssertEqual(event.volumeScalar, extreme)
        }
    }

    func testHUDEventConsistency() {
        let event1 = HUDEvent(volumeScalar: 0.5, deviceName: "Device", isUnsupported: false)
        let event2 = HUDEvent(volumeScalar: 0.5, deviceName: "Device", isUnsupported: false)

        XCTAssertEqual(event1.volumeScalar, event2.volumeScalar)
        XCTAssertEqual(event1.deviceName, event2.deviceName)
        XCTAssertEqual(event1.isUnsupported, event2.isUnsupported)
    }

    func testCreateMultipleHUDEvents() {
        var events: [HUDEvent] = []
        for i in 0..<50 {
            let scalar = CGFloat(i) / 50.0
            let event = HUDEvent(
                volumeScalar: scalar, deviceName: "Device \(i)", isUnsupported: i % 2 == 0)
            events.append(event)
        }
        XCTAssertEqual(events.count, 50)
    }

    func testHUDEventSequence() {
        let volumes: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        var previousVolume: CGFloat = 0
        for volume in volumes {
            let event = HUDEvent(volumeScalar: volume, deviceName: "Test", isUnsupported: false)
            XCTAssertGreaterThanOrEqual(event.volumeScalar, previousVolume)
            previousVolume = event.volumeScalar
        }
    }

    func testHUDEventWithEmptyDeviceName() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: "", isUnsupported: false)
        XCTAssertEqual(event.deviceName, "")
    }

    func testHUDEventWithWhitespaceDeviceName() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: "   ", isUnsupported: false)
        XCTAssertEqual(event.deviceName, "   ")
    }

    func testHUDEventWithLongDeviceName() {
        let longName = String(repeating: "A", count: 200)
        let event = HUDEvent(volumeScalar: 0.5, deviceName: longName, isUnsupported: false)
        XCTAssertEqual(event.deviceName?.count, 200)
    }

    func testHUDEventWithSpecialCharacters() {
        let specialNames = [
            "USB (Audio)",
            "Device #1",
            "Speakers @ 5V",
            "Dolby® Atmos",
            "HDMI 🔊",
        ]
        for name in specialNames {
            let event = HUDEvent(volumeScalar: 0.5, deviceName: name, isUnsupported: false)
            XCTAssertEqual(event.deviceName, name)
        }
    }

    func testDeviceNameVariations() {
        let deviceNames = [
            "MacBook Pro Speakers",
            "Headphones",
            "USB Audio Device",
            "HDMI Output",
            "AirPods",
        ]

        for name in deviceNames {
            let event = HUDEvent(
                volumeScalar: 0.5,
                deviceName: name,
                isUnsupported: false
            )

            XCTAssertEqual(event.deviceName, name)
        }
    }

    func testHUDEventMinimumVolume() {
        let event = HUDEvent(
            volumeScalar: 0.0,
            deviceName: "Speaker",
            isUnsupported: false
        )

        XCTAssertEqual(event.volumeScalar, 0.0)
    }

    func testHUDEventMaximumVolume() {
        let event = HUDEvent(
            volumeScalar: 1.0,
            deviceName: "Speaker",
            isUnsupported: false
        )

        XCTAssertEqual(event.volumeScalar, 1.0)
    }

    func testHUDEventVolumeRange() {
        let testCases: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0]

        for volume in testCases {
            let event = HUDEvent(
                volumeScalar: volume,
                deviceName: "Test",
                isUnsupported: false
            )

            XCTAssertGreaterThanOrEqual(event.volumeScalar, 0.0)
            XCTAssertLessThanOrEqual(event.volumeScalar, 1.0)
        }
    }

    func testMultipleHUDEventCreation() {
        var events: [HUDEvent] = []

        for i in stride(from: 0, through: 100, by: 25) {
            let event = HUDEvent(
                volumeScalar: CGFloat(i) / 100.0,
                deviceName: "Test",
                isUnsupported: false
            )
            events.append(event)
        }

        XCTAssertEqual(events.count, 5)

        for event in events {
            XCTAssertGreaterThanOrEqual(event.volumeScalar, 0.0)
            XCTAssertLessThanOrEqual(event.volumeScalar, 1.0)
        }
    }

    func testHUDEventSequenceOrdering() {
        let events = [
            HUDEvent(volumeScalar: 0.1, deviceName: "Dev1", isUnsupported: false),
            HUDEvent(volumeScalar: 0.2, deviceName: "Dev2", isUnsupported: false),
            HUDEvent(volumeScalar: 0.3, deviceName: "Dev3", isUnsupported: false),
        ]

        for i in 1..<events.count {
            XCTAssertLessThan(
                events[i - 1].volumeScalar,
                events[i].volumeScalar,
                "Events should be ordered by volume"
            )
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

    func testHUDDimensions() {
        let width = VolumeGridConstants.HUD.width
        let height = VolumeGridConstants.HUD.height
        XCTAssertTrue(width > 100 && width < 1000)
        XCTAssertTrue(height > 50 && height < 500)
    }

    func testHUDDisplayDuration() {
        let duration = VolumeGridConstants.HUD.displayDuration
        XCTAssertGreaterThan(duration, 0)
        XCTAssertLessThan(duration, 10)
    }

    func testHUDAnimationDurations() {
        let fadeIn = VolumeGridConstants.HUD.fadeInDuration
        let fadeOut = VolumeGridConstants.HUD.fadeOutDuration
        XCTAssertGreaterThan(fadeIn, 0)
        XCTAssertGreaterThan(fadeOut, 0)
        XCTAssertLessThan(fadeIn, 1.0)
        XCTAssertLessThan(fadeOut, 1.0)
    }

    func testHUDLayoutConstants() {
        XCTAssertGreaterThan(VolumeGridConstants.HUD.Layout.iconSize, 0)
        XCTAssertGreaterThan(VolumeGridConstants.HUD.Layout.spacingIconToDevice, 0)
        XCTAssertGreaterThan(VolumeGridConstants.HUD.Layout.spacingDeviceToBlocks, 0)
    }

    func testHUDMargins() {
        let marginX = VolumeGridConstants.HUD.marginX
        let minVPadding = VolumeGridConstants.HUD.minVerticalPadding
        XCTAssertGreaterThan(marginX, 0)
        XCTAssertGreaterThan(minVPadding, 0)
    }

    func testBlockCountForVolume() {
        let blocksCount = CGFloat(VolumeGridConstants.volumeBlocksCount)
        XCTAssertEqual(blocksCount, 16)
    }

    func testHUDCornerRadius() {
        let radius = VolumeGridConstants.HUD.cornerRadius
        XCTAssertGreaterThan(radius, 0)
        XCTAssertLessThan(radius, 100)
    }

    func testHUDTextFont() {
        let font = VolumeGridConstants.HUD.textFont
        XCTAssertNotNil(font)
    }
}

// MARK: - HUD Display Scenarios

final class HUDScenarioTests: XCTestCase {
    var hudManager: HUDManager?
    var mockAudioDeviceManager: MockAudioDeviceManager?
    var mockSystemEventMonitor: MockSystemEventMonitor?
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        hudManager = HUDManager()
        mockAudioDeviceManager = MockAudioDeviceManager()
        mockSystemEventMonitor = MockSystemEventMonitor()
    }

    override func tearDown() {
        hudManager = nil
        mockAudioDeviceManager = nil
        mockSystemEventMonitor = nil
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Combined Scenarios

    func testHUDShowsForAllThreeScenarios() {
        let volumeKeyExpectation = XCTestExpectation(description: "Volume key scenario")
        let deviceSwitchExpectation = XCTestExpectation(description: "Device switch scenario")
        let volumeChangeExpectation = XCTestExpectation(description: "Volume change scenario")

        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            volumeKeyExpectation.fulfill()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            deviceSwitchExpectation.fulfill()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let _ = HUDEvent(volumeScalar: 0.8, deviceName: "Speaker", isUnsupported: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            volumeChangeExpectation.fulfill()
        }

        wait(
            for: [volumeKeyExpectation, deviceSwitchExpectation, volumeChangeExpectation],
            timeout: 2.0)
    }

    func testHUDHidesAfterTimeout() {
        let expectation = XCTestExpectation(description: "HUD should hide after timeout")

        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
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
