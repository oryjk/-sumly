import AuthenticationServices
import Foundation

struct SystemAppleCredentialChecker: AppleCredentialChecking {
    func state(for userID: String) async throws -> AppleCredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if let error { continuation.resume(throwing: error); return }
                let result: AppleCredentialState
                switch state {
                case .authorized: result = .authorized
                case .revoked: result = .revoked
                case .notFound: result = .notFound
                case .transferred: result = .transferred
                @unknown default: result = .unknown
                }
                continuation.resume(returning: result)
            }
        }
    }
}
