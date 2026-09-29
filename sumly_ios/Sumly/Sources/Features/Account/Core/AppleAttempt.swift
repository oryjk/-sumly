import Foundation
import Security

struct AppleAttempt: Sendable {
    let challengeID: String
    let nonce: String
    let state: String
    let expiresAt: Date
    init(challenge: AppleChallenge, now: Date = Date()) throws {
        guard !challenge.challengeID.isEmpty, !challenge.nonce.isEmpty, challenge.expiresIn > 0 else { throw AuthError.malformed }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AuthError.malformed }
        challengeID = challenge.challengeID
        nonce = challenge.nonce // Server nonce is already the exact Apple request value. Do not hash.
        state = Data(bytes).base64EncodedString()
        expiresAt = now.addingTimeInterval(Double(min(challenge.expiresIn, 300)))
    }
    func accepts(state: String?, now: Date = Date()) -> Bool { state == self.state && now < expiresAt }
}
