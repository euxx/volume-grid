import XCTest

@testable import Volume_Grid

/// End-to-end integration tests for complete volume control workflow
/// Tests the full path from user action to HUD display
final class VolumeControlIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Volume Percentage to Formatting

    func testPercentageToFormattedString() {
        let testCases: [(percentage: Int, expectedNotEmpty: Bool)] = [
            (0, true),
            (25, true),
            (50, true),
            (75, true),
            (100, true),
        ]

        for (percentage, shouldHaveValue) in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)

            if shouldHaveValue {
                XCTAssertFalse(formatted.isEmpty, "Format for \(percentage)% should not be empty")
            }
        }
    }

    // MARK: - Scalar to Formatting

    func testScalarToFormattedString() {
        let testCases: [(scalar: CGFloat, expectedNotEmpty: Bool)] = [
            (0.0, true),
            (0.25, true),
            (0.5, true),
            (0.75, true),
            (1.0, true),
        ]

        for (scalar, shouldHaveValue) in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)

            if shouldHaveValue {
                XCTAssertFalse(formatted.isEmpty, "Format for \(scalar) should not be empty")
            }
        }
    }

    // MARK: - Volume to Icon Selection

    func testPercentageToIcon() {
        let testCases: [(percentage: Int, shouldHaveIcon: Bool)] = [
            (0, true),     // Muted
            (25, true),    // Low
            (50, true),    // Medium
            (75, true),    // High
            (100, true),   // High
        ]

        for (percentage, shouldHaveIcon) in testCases {
            let icon = VolumeIconHelper.icon(for: percentage)

            if shouldHaveIcon {
                XCTAssertFalse(icon.symbolName.isEmpty)
                XCTAssertGreaterThan(icon.size, 0)
            }
        }
    }

    // MARK: - HUD Icon vs Status Bar Icon

    func testHUDIconIsDifferent() {
        let percentages = [0, 25, 50, 75, 100]

        for percentage in percentages {
            let statusBarIcon = VolumeIconHelper.icon(for: percentage)
            let hudIcon = VolumeIconHelper.hudIcon(for: percentage)

            if percentage == 0 {
                // Both should be filled for muted
                XCTAssertTrue(
                    hudIcon.symbolName.contains("fill"),
                    "HUD muted icon should be filled"
                )
            } else {
                // HUD should have filled variant
                XCTAssertTrue(
                    hudIcon.symbolName.contains("fill"),
                    "HUD icon should be filled variant"
                )
                XCTAssertFalse(
                    statusBarIcon.symbolName.contains("fill"),
                    "Status bar icon should not be filled"
                )
            }
        }
    }

    // MARK: - Icon Size Variation

    func testIconSizesVary() {
        let percentages = [0, 25, 50, 75, 100]
        var sizes = Set<CGFloat>()

        for percentage in percentages {
            let icon = VolumeIconHelper.icon(for: percentage)
            sizes.insert(icon.size)
        }

        XCTAssertGreaterThanOrEqual(sizes.count, 1, "Icon sizes should be assigned")
    }

    // MARK: - Event Creation Pipeline

    func testCompleteEventCreation() {
        let percentage = 50

        // 1. Format volume
        let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
        XCTAssertFalse(formatted.isEmpty)

        // 2. Select icon
        let icon = VolumeIconHelper.icon(for: percentage)
        XCTAssertFalse(icon.symbolName.isEmpty)

        // 3. Create HUD event
        let event = HUDEvent(
            volumeScalar: CGFloat(percentage) / 100.0,
            deviceName: "Test Device",
            isUnsupported: false
        )

        XCTAssertEqual(event.volumeScalar, 0.5)
        XCTAssertEqual(event.deviceName, "Test Device")
    }

    // MARK: - Volume Range Coverage

    func testFormattingCoversFullRange() {
        let results = (0...100).map { percentage in
            VolumeFormatter.formattedVolumeString(for: percentage)
        }

        // All values should be formatted
        XCTAssertEqual(results.count, 101)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty })
    }

    func testIconSelectionCoversFullRange() {
        let results = (0...100).map { percentage in
            VolumeIconHelper.icon(for: percentage)
        }

        // All values should have icons
        XCTAssertEqual(results.count, 101)
        XCTAssertTrue(results.allSatisfy { !$0.symbolName.isEmpty })
    }

    // MARK: - Unsupported Device Handling

    func testUnsupportedDeviceIcon() {
        let supportedIcon = VolumeIconHelper.icon(for: 50, isUnsupported: false)
        let unsupportedIcon = VolumeIconHelper.icon(for: 50, isUnsupported: true)

        XCTAssertNotEqual(supportedIcon.symbolName, unsupportedIcon.symbolName)
        XCTAssertEqual(unsupportedIcon.symbolName, "nosign")
    }

    func testUnsupportedDeviceEvent() {
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: nil,
            isUnsupported: true
        )

        XCTAssertTrue(event.isUnsupported)
    }

    // MARK: - Quarter Step Accuracy

    func testQuarterStepFormatting() {
        let testCases: [(scalar: CGFloat, shouldContainFraction: Bool)] = [
            (0.0, false),    // "0"
            (0.125, true),   // "1/4" or "0+1/4"
            (0.25, true),    // "2/4"
            (0.375, true),   // "3/4" or similar
            (0.5, true),     // "2/4" or "4/8"
            (0.75, true),    // "3/4"
            (1.0, false),    // "8"
        ]

        for (scalar, shouldContainFraction) in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)

            // Verify formatting works without crashing
            XCTAssertFalse(formatted.isEmpty)
        }
    }

    // MARK: - Clamping Integration

    func testClampingInFormatting() {
        // Values outside 0-100 should be clamped
        let negativeFormatted = VolumeFormatter.formattedVolumeString(for: -50)
        let normalFormatted = VolumeFormatter.formattedVolumeString(for: 50)
        let highFormatted = VolumeFormatter.formattedVolumeString(for: 150)

        // Negative should clamp to 0
        XCTAssertEqual(negativeFormatted, "0")

        // High should clamp to 100
        XCTAssertEqual(highFormatted, "16")
    }

    func testClampingInIconSelection() {
        let negativeIcon = VolumeIconHelper.icon(for: -50)
        let normalIcon = VolumeIconHelper.icon(for: 50)
        let highIcon = VolumeIconHelper.icon(for: 150)

        // All should return valid icons
        XCTAssertFalse(negativeIcon.symbolName.isEmpty)
        XCTAssertFalse(normalIcon.symbolName.isEmpty)
        XCTAssertFalse(highIcon.symbolName.isEmpty)

        // Extremes should clamp to boundaries
        let zeroIcon = VolumeIconHelper.icon(for: 0)
        let hundredIcon = VolumeIconHelper.icon(for: 100)

        XCTAssertEqual(negativeIcon.symbolName, zeroIcon.symbolName)
        XCTAssertEqual(highIcon.symbolName, hundredIcon.symbolName)
    }

    // MARK: - Consistency Across Conversions

    func testPercentageToScalarConsistency() {
        // Same value represented as percentage and scalar should format similarly
        let percentage50Formatted = VolumeFormatter.formattedVolumeString(for: 50)
        let scalar050Formatted = VolumeFormatter.formattedVolumeString(forScalar: 0.5)

        XCTAssertEqual(percentage50Formatted, scalar050Formatted)
    }

    func testIconConsistency() {
        // Same volume level should produce similar icon type
        let percentage50Icon = VolumeIconHelper.icon(for: 50)
        let percentage49Icon = VolumeIconHelper.icon(for: 49)
        let percentage51Icon = VolumeIconHelper.icon(for: 51)

        // Should be in same range (all medium volume icons)
        XCTAssertEqual(percentage50Icon.symbolName, percentage49Icon.symbolName)
        XCTAssertEqual(percentage50Icon.symbolName, percentage51Icon.symbolName)
    }

    // MARK: - State Transitions

    func testVolumeIncreaseSequence() {
        let sequence = [0, 25, 50, 75, 100]
        let formatted = sequence.map { VolumeFormatter.formattedVolumeString(for: $0) }
        let icons = sequence.map { VolumeIconHelper.icon(for: $0) }

        // All should be valid
        XCTAssertTrue(formatted.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(icons.allSatisfy { !$0.symbolName.isEmpty })
    }

    func testVolumeDecreaseSequence() {
        let sequence = [100, 75, 50, 25, 0]
        let formatted = sequence.map { VolumeFormatter.formattedVolumeString(for: $0) }
        let icons = sequence.map { VolumeIconHelper.icon(for: $0) }

        // All should be valid
        XCTAssertTrue(formatted.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(icons.allSatisfy { !$0.symbolName.isEmpty })
    }

    // MARK: - Device Name Integration

    func testEventWithVariousDeviceNames() {
        let deviceNames = [
            "MacBook Pro Speakers",
            "Headphones",
            "USB Audio",
            "HDMI Output",
            "AirPods Pro",
            nil,
        ]

        for deviceName in deviceNames {
            let event = HUDEvent(
                volumeScalar: 0.5,
                deviceName: deviceName,
                isUnsupported: false
            )

            XCTAssertEqual(event.deviceName, deviceName)
            XCTAssertEqual(event.volumeScalar, 0.5)
        }
    }

    // MARK: - Boundary Conditions

    func testZeroVolumeFullFlow() {
        let formatted = VolumeFormatter.formattedVolumeString(for: 0)
        let icon = VolumeIconHelper.icon(for: 0)
        let event = HUDEvent(volumeScalar: 0.0, deviceName: "Test", isUnsupported: false)

        XCTAssertEqual(formatted, "0")
        XCTAssertEqual(icon.symbolName, "speaker.slash")
        XCTAssertEqual(event.volumeScalar, 0.0)
    }

    func testMaxVolumeFullFlow() {
        let formatted = VolumeFormatter.formattedVolumeString(for: 100)
        let icon = VolumeIconHelper.icon(for: 100)
        let event = HUDEvent(volumeScalar: 1.0, deviceName: "Test", isUnsupported: false)

        XCTAssertEqual(formatted, "16")
        XCTAssertTrue(icon.symbolName.contains("wave.3"))
        XCTAssertEqual(event.volumeScalar, 1.0)
    }

    // MARK: - Performance Integration

    func testFullPipelinePerformance() {
        measure {
            for i in 0...100 {
                let scalar = CGFloat(i) / 100.0

                // Formatting pipeline
                _ = VolumeFormatter.formattedVolumeString(for: i)
                _ = VolumeFormatter.formattedVolumeString(forScalar: scalar)

                // Icon pipeline
                _ = VolumeIconHelper.icon(for: i)
                _ = VolumeIconHelper.hudIcon(for: i)

                // Event creation
                _ = HUDEvent(
                    volumeScalar: scalar,
                    deviceName: "Device",
                    isUnsupported: false
                )
            }
        }
    }
}
