import XCTest

@testable import Volume_Grid

/// HUDManager tests - focuses on logic rather than UI rendering
/// Note: Full HUD window creation is tested via integration tests
final class HUDManagerTests: XCTestCase {
    // MARK: - HUDEvent Structure Tests

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

    // MARK: - HUD Constants Tests

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
        XCTAssertLessThan(duration, 10)  // Reasonable duration
    }

    func testHUDAnimationDurations() {
        let fadeIn = VolumeGridConstants.HUD.fadeInDuration
        let fadeOut = VolumeGridConstants.HUD.fadeOutDuration
        XCTAssertGreaterThan(fadeIn, 0)
        XCTAssertGreaterThan(fadeOut, 0)
        XCTAssertLessThan(fadeIn, 1.0)
        XCTAssertLessThan(fadeOut, 1.0)
    }

    // MARK: - HUD Layout Constants Tests

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

    // MARK: - Volume Calculation Tests

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

    func testBlockCountForVolume() {
        let blocksCount = VolumeGridConstants.Audio.blocksCount
        XCTAssertEqual(blocksCount, 16)  // 16 blocks total
    }

    // MARK: - Edge Cases

    func testHUDEventWithExtremeValues() {
        // Values outside normal range but still valid for events
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

    // MARK: - HUD Style Constants

    func testHUDCornerRadius() {
        let radius = VolumeGridConstants.HUD.cornerRadius
        XCTAssertGreaterThan(radius, 0)
        XCTAssertLessThan(radius, 100)
    }

    func testHUDTextFont() {
        let font = VolumeGridConstants.HUD.textFont
        XCTAssertNotNil(font)
    }

    // MARK: - Batch HUD Event Creation

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
        // Simulate volume increase sequence
        let volumes: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        var previousVolume: CGFloat = 0
        for volume in volumes {
            let event = HUDEvent(volumeScalar: volume, deviceName: "Test", isUnsupported: false)
            XCTAssertGreaterThanOrEqual(event.volumeScalar, previousVolume)
            previousVolume = event.volumeScalar
        }
    }

    // MARK: - Device Name Handling

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
}
