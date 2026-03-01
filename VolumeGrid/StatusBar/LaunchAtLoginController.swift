import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

protocol LaunchAtLoginServiceable {
    nonisolated func isEnabled() -> Bool
    nonisolated func setEnabled(
        _ enabled: Bool,
        completion: @escaping @Sendable (Result<Bool, LaunchAtLoginError>) -> Void
    )
}

final class LaunchAtLoginController: LaunchAtLoginServiceable {
    nonisolated func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    nonisolated func setEnabled(
        _ enabled: Bool,
        completion: @escaping @Sendable (Result<Bool, LaunchAtLoginError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Bool, LaunchAtLoginError>
            if enabled {
                result = Self.enable()
            } else {
                result = Self.disable()
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private nonisolated static func enable() -> Result<Bool, LaunchAtLoginError> {
        do {
            try SMAppService.mainApp.register()
            return .success(true)
        } catch {
            return .failure(
                .message("Failed to enable launch at login: \(error.localizedDescription)"))
        }
    }

    private nonisolated static func disable() -> Result<Bool, LaunchAtLoginError> {
        do {
            try SMAppService.mainApp.unregister()
            return .success(false)
        } catch {
            return .failure(
                .message("Failed to disable launch at login: \(error.localizedDescription)"))
        }
    }
}
