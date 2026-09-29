import Foundation

enum AuthProvider: String, Codable, Sendable {
    case apple, phone, email
    var title: String { switch self { case .apple: "Apple"; case .phone: "手机号"; case .email: "邮箱" } }
}
struct NativeUser: Codable, Sendable, Equatable {
    let id: Int64
    let nickname: String
    let avatarURL: String
    let email: String?
    let phoneNumber: String?
    let status: String
    let provider: AuthProvider
    enum CodingKeys: String, CodingKey {
        case id, nickname, email, status, provider
        case avatarURL = "avatar_url", phoneNumber = "phone_number"
    }
    var maskedIdentifier: String {
        if let phoneNumber { return String(phoneNumber.prefix(6)) + "****" + String(phoneNumber.suffix(4)) }
        if let email, let at = email.firstIndex(of: "@") { return String(email.prefix(1)) + "***" + email[at...] }
        return "Apple 私密账户"
    }
}
struct LoginResult: Codable, Sendable {
    let token: String
    let refreshToken: String
    let expiresIn: Int
    let user: NativeUser
    enum CodingKeys: String, CodingKey { case token, user; case refreshToken = "refresh_token", expiresIn = "expires_in" }
}
struct StoredSession: Codable, Sendable {
    var result: LoginResult
    var expiresAt: Date
    var primaryLoginAt: Date
    var appleUserID: String?
}
struct AuthCapabilities: Decodable, Sendable {
    let apple: Bool; let phone: Bool; let email: Bool
    static let disabled = Self(apple: false, phone: false, email: false)
}
struct AppleChallenge: Decodable, Sendable {
    let challengeID: String; let nonce: String; let expiresIn: Int
    enum CodingKeys: String, CodingKey { case nonce; case challengeID = "challenge_id", expiresIn = "expires_in" }
}
struct CodeDelivery: Decodable, Sendable {
    let retryAfter: Int; let expiresIn: Int
    enum CodingKeys: String, CodingKey { case retryAfter = "retry_after", expiresIn = "expires_in" }
}
enum AuthCoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
enum AuthValidation {
    // Unicode scalars agree with the backend's Unicode code-point count; never trim passwords.
    static func validPassword(_ value: String) -> Bool {
        (12...128).contains(value.unicodeScalars.count) && value.utf8.count <= 512
    }
    static func email(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func validEmail(_ value: String) -> Bool {
        let normalized = email(value)
        return normalized.utf8.count <= 254 && normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    static func phone(_ value: String) -> String? {
        var number = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.hasPrefix("+86") { number.removeFirst(3) }
        guard number.range(of: #"^1[3-9][0-9]{9}$"#, options: .regularExpression) != nil else { return nil }
        return "+86" + number
    }
    static func validCode(_ value: String) -> Bool { value.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil }
}
enum AuthError: Error, LocalizedError, Equatable {
    case unauthorized, reauthenticate, accountMismatch, unavailable, network, malformed, stale, insecureURL, keychain(Int32)
    case server(Int, String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: "登录已失效，请重新登录。"
        case .accountMismatch: "登录的账户与待注销账户不一致，未切换账户。请使用原账户重新验证。"
        case .reauthenticate: "注销账户前请重新登录，并在 5 分钟内再次确认注销。"
        case .unavailable: "此登录方式暂未开放，请稍后再试。"
        case .network: "网络连接失败，请稍后重试。已保存的登录状态会保留。"
        case .malformed: "服务返回异常，请稍后重试。"
        case .stale: "操作已取消，请重试。"
        case .insecureURL: "登录服务地址必须使用 HTTPS（本机开发地址除外）。"
        case .keychain: "无法访问安全凭据，请解锁设备后重试。"
        case .server(_, let message): message.isEmpty ? "操作失败，请稍后重试。" : message
        }
    }
}

struct AuthRequest: Sendable {
    let path: String
    var method = "POST"
    var fields: [String: String] = [:]
    var bearer: String? = nil
    static var capabilities: Self { .init(path: "capabilities", method: "GET") }
    static var challenge: Self { .init(path: "apple/challenge") }
    static func appleLogin(challengeID: String, token: String, code: String, nickname: String?) -> Self {
        var fields = ["challenge_id": challengeID, "identity_token": token, "authorization_code": code]
        if let nickname, !nickname.isEmpty { fields["nickname"] = nickname }
        return .init(path: "apple/login", fields: fields)
    }
    static func phoneCode(_ phone: String) -> Self { .init(path: "phone/code", fields: ["phone_number": phone]) }
    static func phoneLogin(phone: String, code: String) -> Self { .init(path: "phone/login", fields: ["phone_number": phone, "code": code]) }
    static func emailCode(_ email: String, purpose: String) -> Self { .init(path: "email/code", fields: ["email": email, "purpose": purpose]) }
    static func emailLogin(email: String, password: String) -> Self { .init(path: "email/login", fields: ["email": email, "password": password]) }
    static func emailRegister(email: String, password: String, code: String) -> Self { .init(path: "email/register", fields: ["email": email, "password": password, "code": code]) }
    static func reset(email: String, password: String, code: String) -> Self { .init(path: "email/reset-password", fields: ["email": email, "new_password": password, "code": code]) }
    static func refresh(_ token: String) -> Self { .init(path: "refresh", fields: ["refresh_token": token]) }
    static func logout(_ token: String) -> Self { .init(path: "logout", fields: ["refresh_token": token]) }
    static func me(_ token: String) -> Self { .init(path: "me", method: "GET", bearer: token) }
    static func delete(_ token: String) -> Self { .init(path: "account", method: "DELETE", fields: ["confirmation": "DELETE"], bearer: token) }
}


struct AccountDeletionIntent: Equatable, Sendable {
    let id = UUID()
    let userID: Int64
    let provider: AuthProvider
    let maskedIdentifier: String
}
