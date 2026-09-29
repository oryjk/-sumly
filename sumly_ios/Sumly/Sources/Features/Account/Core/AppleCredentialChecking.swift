import Foundation

enum AppleCredentialState: Sendable { case authorized, revoked, notFound, transferred, unknown }
protocol AppleCredentialChecking: Sendable {
    func state(for userID: String) async throws -> AppleCredentialState
}
extension AuthSession {
    func checkAppleCredential(using checker: any AppleCredentialChecking) async {
        guard let userID = stored?.appleUserID else { return }
        let stamp = sessionGeneration
        do {
            let state = try await checker.state(for: userID)
            guard stamp == sessionGeneration else { return }
            switch state {
            case .revoked, .notFound, .transferred:
                clearLocal()
                notice = "Apple 授权已失效，请重新登录。"
            case .authorized, .unknown: break
            }
        } catch {
            // Offline credential checks cannot establish revocation; preserve the secure session.
        }
    }
}
