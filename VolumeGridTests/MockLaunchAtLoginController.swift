import Foundation

@testable import Volume_Grid

/// Mock implementation of LaunchAtLoginServiceable for testing
/// Allows tests to control behavior without affecting system settings
final class MockLaunchAtLoginController: LaunchAtLoginServiceable {
    var isEnabledValue: Bool = false
    var setEnabledExpectation: ((Bool) -> Void)?
    var setEnabledClosure: ((Bool, @escaping (Result<Bool, LaunchAtLoginError>) -> Void) -> Void)?

    func isEnabled() -> Bool {
        isEnabledValue
    }

    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, LaunchAtLoginError>) -> Void
    ) {
        setEnabledExpectation?(enabled)

        if let closure = setEnabledClosure {
            closure(enabled, completion)
        } else {
            // Default behavior: simulate successful update
            isEnabledValue = enabled
            DispatchQueue.main.async {
                completion(.success(enabled))
            }
        }
    }
}
