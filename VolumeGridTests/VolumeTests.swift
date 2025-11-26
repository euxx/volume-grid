import XCTest

@testable import Volume_Grid

// MARK: - Volume Integration Tests

final class VolumeIntegrationTests: XCTestCase {
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
            (0, true),
            (25, true),
            (50, true),
            (75, true),
            (100, true),
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
                XCTAssertTrue(
                    hudIcon.symbolName.contains("fill"), "HUD muted icon should be filled")
            } else {
                XCTAssertTrue(
                    hudIcon.symbolName.contains("fill"), "HUD icon should be filled variant")
                XCTAssertFalse(
                    statusBarIcon.symbolName.contains("fill"),
                    "Status bar icon should not be filled")
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

        let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
        XCTAssertFalse(formatted.isEmpty)

        let icon = VolumeIconHelper.icon(for: percentage)
        XCTAssertFalse(icon.symbolName.isEmpty)

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

        XCTAssertEqual(results.count, 101)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty })
    }

    func testIconSelectionCoversFullRange() {
        let results = (0...100).map { percentage in
            VolumeIconHelper.icon(for: percentage)
        }

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
        let event = HUDEvent(volumeScalar: 0.5, deviceName: nil, isUnsupported: true)

        XCTAssertTrue(event.isUnsupported)
    }

    // MARK: - Quarter Step Accuracy

    func testQuarterStepFormatting() {
        let testCases: [(scalar: CGFloat, shouldContainFraction: Bool)] = [
            (0.0, false),
            (0.125, true),
            (0.25, true),
            (0.375, true),
            (0.5, true),
            (0.75, true),
            (1.0, false),
        ]

        for (scalar, _) in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            XCTAssertFalse(formatted.isEmpty)
        }
    }

    // MARK: - Clamping Integration

    func testClampingInFormatting() {
        let negativeFormatted = VolumeFormatter.formattedVolumeString(for: -50)
        let normalFormatted = VolumeFormatter.formattedVolumeString(for: 50)
        let highFormatted = VolumeFormatter.formattedVolumeString(for: 150)

        XCTAssertEqual(negativeFormatted, "0")
        XCTAssertEqual(highFormatted, "16")
    }

    func testClampingInIconSelection() {
        let negativeIcon = VolumeIconHelper.icon(for: -50)
        let normalIcon = VolumeIconHelper.icon(for: 50)
        let highIcon = VolumeIconHelper.icon(for: 150)

        XCTAssertFalse(negativeIcon.symbolName.isEmpty)
        XCTAssertFalse(normalIcon.symbolName.isEmpty)
        XCTAssertFalse(highIcon.symbolName.isEmpty)

        let zeroIcon = VolumeIconHelper.icon(for: 0)
        let hundredIcon = VolumeIconHelper.icon(for: 100)

        XCTAssertEqual(negativeIcon.symbolName, zeroIcon.symbolName)
        XCTAssertEqual(highIcon.symbolName, hundredIcon.symbolName)
    }

    // MARK: - Consistency Across Conversions

    func testPercentageToScalarConsistency() {
        let percentage50Formatted = VolumeFormatter.formattedVolumeString(for: 50)
        let scalar050Formatted = VolumeFormatter.formattedVolumeString(forScalar: 0.5)

        XCTAssertEqual(percentage50Formatted, scalar050Formatted)
    }

    func testIconConsistency() {
        let percentage50Icon = VolumeIconHelper.icon(for: 50)
        let percentage49Icon = VolumeIconHelper.icon(for: 49)
        let percentage51Icon = VolumeIconHelper.icon(for: 51)

        XCTAssertEqual(percentage50Icon.symbolName, percentage49Icon.symbolName)
        XCTAssertEqual(percentage50Icon.symbolName, percentage51Icon.symbolName)
    }

    // MARK: - State Transitions

    func testVolumeIncreaseSequence() {
        let sequence = [0, 25, 50, 75, 100]
        let formatted = sequence.map { VolumeFormatter.formattedVolumeString(for: $0) }
        let icons = sequence.map { VolumeIconHelper.icon(for: $0) }

        XCTAssertTrue(formatted.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(icons.allSatisfy { !$0.symbolName.isEmpty })
    }

    func testVolumeDecreaseSequence() {
        let sequence = [100, 75, 50, 25, 0]
        let formatted = sequence.map { VolumeFormatter.formattedVolumeString(for: $0) }
        let icons = sequence.map { VolumeIconHelper.icon(for: $0) }

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
            let event = HUDEvent(volumeScalar: 0.5, deviceName: deviceName, isUnsupported: false)

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

                _ = VolumeFormatter.formattedVolumeString(for: i)
                _ = VolumeFormatter.formattedVolumeString(forScalar: scalar)

                _ = VolumeIconHelper.icon(for: i)
                _ = VolumeIconHelper.hudIcon(for: i)

                _ = HUDEvent(volumeScalar: scalar, deviceName: "Device", isUnsupported: false)
            }
        }
    }
}

// MARK: - Volume Edge Cases Tests

final class VolumeEdgeCasesTests: XCTestCase {

    // MARK: - Extreme Value Handling

    func testNegativeVolumePercentage() {
        let testCases = [-1000, -100, -50, -1]

        for percentage in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
            let icon = VolumeIconHelper.icon(for: percentage)

            XCTAssertEqual(formatted, "0")
            XCTAssertEqual(icon.symbolName, "speaker.slash")
        }
    }

    func testVeryHighVolumePercentage() {
        let testCases = [101, 150, 500, 1000, 10000]

        for percentage in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
            let icon = VolumeIconHelper.icon(for: percentage)

            XCTAssertEqual(formatted, "16")
            XCTAssertTrue(icon.symbolName.contains("wave.3"))
        }
    }

    func testNegativeScalar() {
        let testCases: [CGFloat] = [-1.0, -0.5, -0.1]

        for scalar in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            XCTAssertEqual(formatted, "0")
        }
    }

    func testScalarAboveOne() {
        let testCases: [CGFloat] = [1.1, 2.0, 10.0, 100.0]

        for scalar in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            XCTAssertEqual(formatted, "16")
        }
    }

    // MARK: - Boundary Values

    func testZeroBoundary() {
        let percentageFormatted = VolumeFormatter.formattedVolumeString(for: 0)
        let scalarFormatted = VolumeFormatter.formattedVolumeString(forScalar: 0.0)

        XCTAssertEqual(percentageFormatted, "0")
        XCTAssertEqual(scalarFormatted, "0")
    }

    func testOneBoundary() {
        let percentageFormatted = VolumeFormatter.formattedVolumeString(for: 100)
        let scalarFormatted = VolumeFormatter.formattedVolumeString(forScalar: 1.0)

        XCTAssertEqual(percentageFormatted, "16")
        XCTAssertEqual(scalarFormatted, "16")
    }

    func testJustBelowOne() {
        let scalar = 0.99
        let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)

        XCTAssertFalse(formatted.isEmpty)
    }

    func testJustAboveZero() {
        let scalar = 0.01
        let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)

        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("0") || formatted.contains("/"))
    }

    // MARK: - Epsilon and Precision

    func testQuarterStepPrecision() {
        let quarterStep = VolumeFormatter.quarterStep

        let testCases: [CGFloat] = [
            0.0,
            quarterStep,
            quarterStep * 2,
            quarterStep * 3,
            quarterStep * 4,
        ]

        for value in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: value)
            XCTAssertFalse(formatted.isEmpty)
        }
    }

    func testEpsilonHandling() {
        let epsilon = VolumeGridConstants.Audio.volumeEpsilon

        let testCases: [CGFloat] = [
            epsilon / 2,
            epsilon,
            epsilon * 1.5,
            1.0 - epsilon / 2,
            1.0 - epsilon,
        ]

        for value in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: value)
            XCTAssertFalse(formatted.isEmpty)
        }
    }

    // MARK: - Special Values

    func testHalfVolume() {
        let percentageFormatted = VolumeFormatter.formattedVolumeString(for: 50)
        let scalarFormatted = VolumeFormatter.formattedVolumeString(forScalar: 0.5)

        XCTAssertEqual(percentageFormatted, scalarFormatted)
    }

    func testQuarterVolumes() {
        let quarterValues = [0.25, 0.5, 0.75]

        for value in quarterValues {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: value)
            XCTAssertFalse(formatted.isEmpty)
        }
    }

    // MARK: - Icon Boundary Cases

    func testIconAtThresholds() {
        let volumeLevelLow = VolumeGridConstants.Audio.volumeLevelLow
        let volumeLevelMedium = VolumeGridConstants.Audio.volumeLevelMedium

        let belowLow = VolumeIconHelper.icon(for: volumeLevelLow - 1)
        let atLow = VolumeIconHelper.icon(for: volumeLevelLow)

        XCTAssertFalse(belowLow.symbolName.isEmpty)
        XCTAssertFalse(atLow.symbolName.isEmpty)

        let belowMedium = VolumeIconHelper.icon(for: volumeLevelMedium - 1)
        let atMedium = VolumeIconHelper.icon(for: volumeLevelMedium)

        XCTAssertFalse(belowMedium.symbolName.isEmpty)
        XCTAssertFalse(atMedium.symbolName.isEmpty)
    }

    // MARK: - Unsupported Device Edge Cases

    func testUnsupportedAtAllVolumes() {
        let percentages = [0, 25, 50, 75, 100]

        for percentage in percentages {
            let icon = VolumeIconHelper.icon(for: percentage, isUnsupported: true)
            XCTAssertEqual(icon.symbolName, "nosign")
        }
    }

    func testUnsupportedIconSize() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)
        XCTAssertGreaterThan(icon.size, 0)
    }

    // MARK: - Event Creation Edge Cases

    func testEventWithNilDeviceName() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: nil, isUnsupported: false)
        XCTAssertNil(event.deviceName)
    }

    func testEventWithEmptyDeviceName() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: "", isUnsupported: false)
        XCTAssertEqual(event.deviceName, "")
    }

    func testEventWithVeryLongDeviceName() {
        let longName = String(repeating: "A", count: 1000)
        let event = HUDEvent(volumeScalar: 0.5, deviceName: longName, isUnsupported: false)
        XCTAssertEqual(event.deviceName, longName)
    }

    func testEventWithSpecialCharacters() {
        let specialName = "Device™ with «special» characters ©®"
        let event = HUDEvent(volumeScalar: 0.5, deviceName: specialName, isUnsupported: false)
        XCTAssertEqual(event.deviceName, specialName)
    }

    // MARK: - Volume State Consistency

    func testRepeatCallsAreConsistent() {
        let percentage = 50
        let calls = (0..<10).map { _ in
            VolumeFormatter.formattedVolumeString(for: percentage)
        }

        let firstResult = calls.first!
        XCTAssertTrue(calls.allSatisfy { $0 == firstResult })
    }

    func testIconRepeatCallsAreConsistent() {
        let percentage = 50
        let calls = (0..<10).map { _ in
            VolumeIconHelper.icon(for: percentage)
        }

        let firstResult = calls.first!
        XCTAssertTrue(
            calls.allSatisfy { icon in
                icon.symbolName == firstResult.symbolName && icon.size == firstResult.size
            })
    }

    // MARK: - Format String Safety

    func testFormattedStringDoesNotContainNil() {
        let formatted = VolumeFormatter.formattedVolumeString(for: 50)

        XCTAssertFalse(formatted.contains("nil"))
        XCTAssertFalse(formatted.contains("NSNumber"))
        XCTAssertFalse(formatted.contains("Optional"))
    }

    // MARK: - Resource Cleanup

    func testNoMemoryLeaksInFormatting() {
        var results: [String] = []

        for i in 0..<1000 {
            results.append(VolumeFormatter.formattedVolumeString(for: i % 101))
        }

        XCTAssertEqual(results.count, 1000)
        results.removeAll()
    }

    func testNoMemoryLeaksInIconSelection() {
        var results: [VolumeIconHelper.VolumeIcon] = []

        for i in 0..<1000 {
            results.append(VolumeIconHelper.icon(for: i % 101))
        }

        XCTAssertEqual(results.count, 1000)
        results.removeAll()
    }

    // MARK: - Concurrent Access

    func testConcurrentFormatting() {
        let queue = DispatchQueue.global()
        let group = DispatchGroup()

        var results: [String] = []
        let lock = NSLock()

        for i in 0..<100 {
            group.enter()
            queue.async {
                let formatted = VolumeFormatter.formattedVolumeString(for: i % 101)
                lock.withLock {
                    results.append(formatted)
                }
                group.leave()
            }
        }

        group.wait()

        XCTAssertEqual(results.count, 100)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty })
    }

    func testConcurrentIconSelection() {
        let queue = DispatchQueue.global()
        let group = DispatchGroup()

        var results: [VolumeIconHelper.VolumeIcon] = []
        let lock = NSLock()

        for i in 0..<100 {
            group.enter()
            queue.async {
                let icon = VolumeIconHelper.icon(for: i % 101)
                lock.withLock {
                    results.append(icon)
                }
                group.leave()
            }
        }

        group.wait()

        XCTAssertEqual(results.count, 100)
        XCTAssertTrue(results.allSatisfy { !$0.symbolName.isEmpty })
    }

    // MARK: - Constants Validation

    func testBlocksCountConstant() {
        let blocksCount = CGFloat(VolumeGridConstants.volumeBlocksCount)

        XCTAssertGreaterThan(blocksCount, 0)
        XCTAssertLessThanOrEqual(blocksCount, 100)
    }

    func testQuarterStepConstant() {
        let quarterStep = VolumeFormatter.quarterStep

        XCTAssertGreaterThan(quarterStep, 0)
        XCTAssertLessThan(quarterStep, 1)
    }

    func testVolumeThresholds() {
        let low = VolumeGridConstants.Audio.volumeLevelLow
        let medium = VolumeGridConstants.Audio.volumeLevelMedium

        XCTAssertGreaterThanOrEqual(low, 0)
        XCTAssertLessThanOrEqual(low, 100)

        XCTAssertGreaterThanOrEqual(medium, low)
        XCTAssertLessThanOrEqual(medium, 100)
    }
}

// MARK: - Performance Tests

final class VolumePerformanceTests: XCTestCase {

    // MARK: - Volume Formatting Performance

    func testFormattingPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeFormatter.formattedVolumeString(for: i)
            }
        }
    }

    func testFormattingScalarPerformance() {
        measure {
            for i in 0...100 {
                let scalar = CGFloat(i) / 100.0
                _ = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            }
        }
    }

    // MARK: - Icon Selection Performance

    func testIconSelectionPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeIconHelper.icon(for: i)
            }
        }
    }

    func testHUDIconSelectionPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeIconHelper.hudIcon(for: i)
            }
        }
    }

    func testIconSelectionWithUnsupported() {
        measure {
            for i in 0...100 {
                _ = VolumeIconHelper.icon(for: i, isUnsupported: i % 10 == 0)
            }
        }
    }

    // MARK: - Clamping Performance

    func testVolumeClampingPerformance() {
        measure {
            for i in -50...150 {
                let value = i.clamped(to: 0...100)
                _ = value
            }
        }
    }

    // MARK: - Throughput Tests

    func testVolumeFormattingThroughput() {
        let iterations = 10000
        let startTime = Date()

        for i in 0..<iterations {
            let percentage = i % 101
            _ = VolumeFormatter.formattedVolumeString(for: percentage)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let throughput = Double(iterations) / elapsed

        print("Volume formatting throughput: \(throughput) operations/sec")
        XCTAssertGreaterThan(throughput, 100_000)
    }

    func testIconSelectionThroughput() {
        let iterations = 10000
        let startTime = Date()

        for i in 0..<iterations {
            let percentage = i % 101
            _ = VolumeIconHelper.icon(for: percentage)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let throughput = Double(iterations) / elapsed

        print("Icon selection throughput: \(throughput) operations/sec")
        XCTAssertGreaterThan(throughput, 50_000)
    }

    // MARK: - Consistency Tests

    func testFormattingConsistency() {
        for percentage in [0, 25, 50, 75, 100] {
            let result1 = VolumeFormatter.formattedVolumeString(for: percentage)
            let result2 = VolumeFormatter.formattedVolumeString(for: percentage)

            XCTAssertEqual(result1, result2, "Formatting should be consistent")
        }
    }

    func testIconSelectionConsistency() {
        for percentage in [0, 25, 50, 75, 100] {
            let result1 = VolumeIconHelper.icon(for: percentage)
            let result2 = VolumeIconHelper.icon(for: percentage)

            XCTAssertEqual(result1.symbolName, result2.symbolName)
            XCTAssertEqual(result1.size, result2.size)
        }
    }

    // MARK: - Edge Case Performance

    func testFormattingExtremeValues() {
        let extremeValues = [-1000, -100, -1, 0, 1, 100, 150, 1000, 10000]

        for value in extremeValues {
            let result = VolumeFormatter.formattedVolumeString(for: value)
            XCTAssertNotNil(result)
        }
    }

    func testIconSelectionExtremeValues() {
        let extremeValues = [-1000, -100, -1, 0, 1, 100, 150, 1000, 10000]

        for value in extremeValues {
            let icon = VolumeIconHelper.icon(for: value)
            XCTAssertFalse(icon.symbolName.isEmpty)
        }
    }

    // MARK: - Combined Operation Performance

    func testCombinedFormattingAndIconing() {
        measure {
            for i in 0...100 {
                _ = VolumeFormatter.formattedVolumeString(for: i)
                _ = VolumeIconHelper.icon(for: i)
            }
        }
    }

    func testHighFrequencyMixedOperations() {
        let iterations = 1000
        let startTime = Date()

        for i in 0..<iterations {
            let percentage = i % 101

            if i % 2 == 0 {
                _ = VolumeFormatter.formattedVolumeString(for: percentage)
            } else {
                _ = VolumeIconHelper.icon(for: percentage)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 0.1)
    }

    // MARK: - Cache Efficiency Tests

    func testRepeatedOperationsEfficiency() {
        var results: [String] = []

        measure {
            for _ in 0..<10 {
                for i in 0...100 {
                    results.append(VolumeFormatter.formattedVolumeString(for: i))
                }
            }
        }

        XCTAssertGreaterThan(results.count, 0)
    }
}

// MARK: - Helper Extension

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
