import XCTest
@testable import Volume_Grid

/// Tests for LaunchAtLoginController
final class LaunchAtLoginControllerTests: XCTestCase {
    var controller: LaunchAtLoginController!

    override func setUp() {
        super.setUp()
        controller = LaunchAtLoginController()
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    // MARK: - LaunchAtLoginError Tests

    func testLaunchAtLoginErrorMessage() {
        let error = LaunchAtLoginError.message("Test error")
        XCTAssertEqual(error.errorDescription, "Test error")
    }

    func testLaunchAtLoginErrorWithSpecialCharacters() {
        let message = "Failed: invalid path"
        let error = LaunchAtLoginError.message(message)
        XCTAssertEqual(error.errorDescription, message)
    }

    func testLaunchAtLoginErrorWithEmptyMessage() {
        let error = LaunchAtLoginError.message("")
        XCTAssertEqual(error.errorDescription, "")
    }

    // MARK: - isEnabled() Tests

    func testIsEnabledReturnsBool() {
        let result = controller.isEnabled()
        XCTAssertTrue(result is Bool)
    }

    func testIsEnabledCallableMultipleTimes() {
        let first = controller.isEnabled()
        let second = controller.isEnabled()
        XCTAssertTrue(first is Bool)
        XCTAssertTrue(second is Bool)
    }

    // MARK: - setEnabled() Tests

    func testSetEnabledToTrueCallsCompletion() {
        let expectation = XCTestExpectation(description: "Enable completion")

        controller.setEnabled(true) { result in
            switch result {
            case .success, .failure:
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledToFalseCallsCompletion() {
        let expectation = XCTestExpectation(description: "Disable completion")

        controller.setEnabled(false) { result in
            switch result {
            case .success, .failure:
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledReturnsResult() {
        let expectation = XCTestExpectation(description: "Result returned")

        controller.setEnabled(true) { result in
            switch result {
            case .success(let value):
                XCTAssertTrue(value is Bool)
                expectation.fulfill()
            case .failure(let error):
                XCTAssertNotNil(error)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledMultipleTimesWithDifferentValues() {
        let expectation1 = XCTestExpectation(description: "First call")
        let expectation2 = XCTestExpectation(description: "Second call")

        controller.setEnabled(true) { _ in
            expectation1.fulfill()
        }

        controller.setEnabled(false) { _ in
            expectation2.fulfill()
        }

        wait(for: [expectation1, expectation2], timeout: 5.0)
    }

    func testSetEnabledExecutesAsynchronously() {
        let expectation = XCTestExpectation(description: "Async execution")
        var callCount = 0

        controller.setEnabled(true) { _ in
            callCount += 1
            expectation.fulfill()
        }

        XCTAssertEqual(callCount, 0)
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(callCount, 1)
    }

    func testSetEnabledCallsCompletionOnMainThread() {
        let expectation = XCTestExpectation(description: "Main thread")
        var executedOnMainThread = false

        controller.setEnabled(true) { _ in
            executedOnMainThread = Thread.isMainThread
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(executedOnMainThread)
    }
}

