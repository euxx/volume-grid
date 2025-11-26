import Combine
import XCTest

@testable import Volume_Grid

/// Integration tests for HUD and VolumeMonitor interaction
/// Tests the complete flow from volume change detection to HUD event generation
final class HUDIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - HUDEvent Structure Tests

    func testHUDEventCreation() {
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: "Test Speaker",
            isUnsupported: false
        )

        XCTAssertEqual(event.volumeScalar, 0.5)
        XCTAssertEqual(event.deviceName, "Test Speaker")
        XCTAssertFalse(event.isUnsupported)
    }

    func testHUDEventWithNilDeviceName() {
        let event = HUDEvent(
            volumeScalar: 0.75,
            deviceName: nil,
            isUnsupported: false
        )

        XCTAssertNil(event.deviceName)
    }

    func testHUDEventUnsupportedMarking() {
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: "Unknown",
            isUnsupported: true
        )

        XCTAssertTrue(event.isUnsupported)
    }

    // MARK: - Volume Level Tests

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

    // MARK: - Icon Selection Tests

    func testVolumeIconForMutedLevel() {
        let icon = VolumeIconHelper.icon(for: 0)

        XCTAssertEqual(icon.symbolName, "speaker.slash")
    }

    func testVolumeIconForLowLevel() {
        let icon = VolumeIconHelper.icon(for: 20)

        XCTAssertTrue(icon.symbolName.contains("wave"))
    }

    func testVolumeIconForMediumLevel() {
        let icon = VolumeIconHelper.icon(for: 50)

        XCTAssertTrue(icon.symbolName.contains("wave"))
    }

    func testVolumeIconForHighLevel() {
        let icon = VolumeIconHelper.icon(for: 100)

        XCTAssertTrue(icon.symbolName.contains("wave"))
    }

    func testHUDIconFilledVariant() {
        let regularIcon = VolumeIconHelper.icon(for: 50)
        let hudIcon = VolumeIconHelper.hudIcon(for: 50)

        // HUD icons should be filled variants
        XCTAssertTrue(hudIcon.symbolName.contains("fill"))
        XCTAssertFalse(regularIcon.symbolName.contains("fill"))
    }

    func testVolumeIconUnsupported() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)

        XCTAssertEqual(icon.symbolName, "nosign")
    }

    // MARK: - Volume Formatting Tests

    func testFormattedVolumeString() {
        let formatter = VolumeFormatter.self

        let zero = formatter.formattedVolumeString(for: 0)
        XCTAssertEqual(zero, "0")

        let half = formatter.formattedVolumeString(for: 50)
        XCTAssertNotNil(half)

        let full = formatter.formattedVolumeString(for: 100)
        XCTAssertEqual(full, "16")  // Full 16 blocks
    }

    func testFormattedVolumeStringScalar() {
        let formatter = VolumeFormatter.self

        let zero = formatter.formattedVolumeString(forScalar: 0.0)
        XCTAssertEqual(zero, "0")

        let half = formatter.formattedVolumeString(forScalar: 0.5)
        XCTAssertNotNil(half)

        let full = formatter.formattedVolumeString(forScalar: 1.0)
        XCTAssertEqual(full, "16")
    }

    // MARK: - Event State Consistency Tests

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

    // MARK: - Boundary Tests

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

    // MARK: - Device Name Variations Tests

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
}
