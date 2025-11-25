import XCTest

@testable import Volume_Grid

/// Performance tests for volume formatting and icon selection
/// Verifies efficiency under high-frequency operations
final class VolumePerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Volume Formatting Performance

    func testFormattingPerformance() {
        let formatter = VolumeFormatter.self

        measure {
            for i in 0...100 {
                _ = formatter.formattedVolumeString(for: i)
            }
        }
    }

    func testFormattingScalarPerformance() {
        let formatter = VolumeFormatter.self

        measure {
            for i in 0...100 {
                let scalar = CGFloat(i) / 100.0
                _ = formatter.formattedVolumeString(forScalar: scalar)
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

        // Should handle at least 100,000 operations per second
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

        // Should handle at least 50,000 operations per second
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

        print("Mixed operations elapsed: \(elapsed * 1000) ms for \(iterations) operations")

        // Should complete quickly (< 100ms for 1000 operations)
        XCTAssertLessThan(elapsed, 0.1)
    }

    // MARK: - Cache Efficiency Tests

    func testRepeatedOperationsEfficiency() {
        var results: [String] = []

        measure {
            // Repeated operations on same values should be efficient
            for _ in 0..<10 {
                for i in 0...100 {
                    results.append(VolumeFormatter.formattedVolumeString(for: i))
                }
            }
        }

        XCTAssertGreaterThan(results.count, 0)
    }
}
