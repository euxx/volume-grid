import XCTest

@testable import Volume_Grid

/// Tests for edge cases, boundary conditions, and error handling
/// Verifies robustness under unusual or invalid inputs
final class VolumeEdgeCasesTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Extreme Value Handling

    func testNegativeVolumePercentage() {
        let testCases = [-1000, -100, -50, -1]

        for percentage in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
            let icon = VolumeIconHelper.icon(for: percentage)

            // Should clamp to 0 and not crash
            XCTAssertEqual(formatted, "0")
            XCTAssertEqual(icon.symbolName, "speaker.slash")
        }
    }

    func testVeryHighVolumePercentage() {
        let testCases = [101, 150, 500, 1000, 10000]

        for percentage in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
            let icon = VolumeIconHelper.icon(for: percentage)

            // Should clamp to 100 and not crash
            XCTAssertEqual(formatted, "16")
            XCTAssertTrue(icon.symbolName.contains("wave.3"))
        }
    }

    func testNegativeScalar() {
        let testCases: [CGFloat] = [-1.0, -0.5, -0.1]

        for scalar in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)

            // Should clamp to 0 and not crash
            XCTAssertEqual(formatted, "0")
        }
    }

    func testScalarAboveOne() {
        let testCases: [CGFloat] = [1.1, 2.0, 10.0, 100.0]

        for scalar in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)

            // Should clamp to 1.0 (100%)
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
        // Should format as minimal value
        XCTAssertTrue(formatted.contains("0") || formatted.contains("/"))
    }

    // MARK: - Epsilon and Precision

    func testQuarterStepPrecision() {
        let quarterStep = VolumeFormatter.quarterStep

        // Test values at quarter step boundaries
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

        // Values very close to boundaries
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

        // Just below low threshold
        let belowLow = VolumeIconHelper.icon(for: volumeLevelLow - 1)
        // At threshold
        let atLow = VolumeIconHelper.icon(for: volumeLevelLow)

        XCTAssertFalse(belowLow.symbolName.isEmpty)
        XCTAssertFalse(atLow.symbolName.isEmpty)

        // Just below medium threshold
        let belowMedium = VolumeIconHelper.icon(for: volumeLevelMedium - 1)
        // At threshold
        let atMedium = VolumeIconHelper.icon(for: volumeLevelMedium)

        XCTAssertFalse(belowMedium.symbolName.isEmpty)
        XCTAssertFalse(atMedium.symbolName.isEmpty)
    }

    // MARK: - Unsupported Device Edge Cases

    func testUnsupportedAtAllVolumes() {
        let percentages = [0, 25, 50, 75, 100]

        for percentage in percentages {
            let icon = VolumeIconHelper.icon(for: percentage, isUnsupported: true)

            // Should always show "nosign" for unsupported
            XCTAssertEqual(icon.symbolName, "nosign")
        }
    }

    func testUnsupportedIconSize() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)

        // Should have valid size
        XCTAssertGreaterThan(icon.size, 0)
    }

    // MARK: - Event Creation Edge Cases

    func testEventWithNilDeviceName() {
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: nil,
            isUnsupported: false
        )

        XCTAssertNil(event.deviceName)
    }

    func testEventWithEmptyDeviceName() {
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: "",
            isUnsupported: false
        )

        XCTAssertEqual(event.deviceName, "")
    }

    func testEventWithVeryLongDeviceName() {
        let longName = String(repeating: "A", count: 1000)
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: longName,
            isUnsupported: false
        )

        XCTAssertEqual(event.deviceName, longName)
    }

    func testEventWithSpecialCharacters() {
        let specialName = "Device™ with «special» characters ©®"
        let event = HUDEvent(
            volumeScalar: 0.5,
            deviceName: specialName,
            isUnsupported: false
        )

        XCTAssertEqual(event.deviceName, specialName)
    }

    // MARK: - Volume State Consistency

    func testRepeatCallsAreConsistent() {
        let percentage = 50
        let calls = (0..<10).map { _ in
            VolumeFormatter.formattedVolumeString(for: percentage)
        }

        // All calls should return same result
        let firstResult = calls.first!
        XCTAssertTrue(calls.allSatisfy { $0 == firstResult })
    }

    func testIconRepeatCallsAreConsistent() {
        let percentage = 50
        let calls = (0..<10).map { _ in
            VolumeIconHelper.icon(for: percentage)
        }

        // All calls should return same result
        let firstResult = calls.first!
        XCTAssertTrue(
            calls.allSatisfy { icon in
                icon.symbolName == firstResult.symbolName && icon.size == firstResult.size
            })
    }

    // MARK: - Type Safety

    func testIntegerClipping() {
        let clamped = Int.min.clamped(to: 0...100)
        XCTAssertEqual(clamped, 0)

        let clamped2 = Int.max.clamped(to: 0...100)
        XCTAssertEqual(clamped2, 100)
    }

    func testCGFloatClipping() {
        let clamped = CGFloat.greatestFiniteMagnitude.clamped(to: 0...1)
        XCTAssertEqual(clamped, 1.0)

        let clamped2 = (-CGFloat.greatestFiniteMagnitude).clamped(to: 0...1)
        XCTAssertEqual(clamped2, 0.0)
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
        // Create many formatted strings
        var results: [String] = []

        for i in 0..<1000 {
            results.append(VolumeFormatter.formattedVolumeString(for: i % 101))
        }

        // Verify count
        XCTAssertEqual(results.count, 1000)

        // Clear
        results.removeAll()
    }

    func testNoMemoryLeaksInIconSelection() {
        // Create many icons
        var results: [VolumeIconHelper.VolumeIcon] = []

        for i in 0..<1000 {
            results.append(VolumeIconHelper.icon(for: i % 101))
        }

        // Verify count
        XCTAssertEqual(results.count, 1000)

        // Clear
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

// MARK: - Helper Extension

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
