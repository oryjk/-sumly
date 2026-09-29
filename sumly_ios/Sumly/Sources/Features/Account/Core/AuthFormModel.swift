import Foundation
import Observation

enum AuthFormMode: String, CaseIterable {
    case phone, email, register, reset
    var title: String { switch self { case .phone: "手机号登录"; case .email: "邮箱登录"; case .register: "注册邮箱账户"; case .reset: "重设密码" } }
}
@MainActor @Observable final class AuthFormModel {
    let session: AuthSession
    let reauthentication: AccountDeletionIntent?
    var mode: AuthFormMode = .phone
    var phone = ""
    var email = ""
    var password = ""
    var confirmation = ""
    var code = ""
    private(set) var capabilities = AuthCapabilities.disabled
    private(set) var loadingCapabilities = false
    private(set) var busy = false
    private(set) var authenticated = false
    var message: String?
    var error: String?
    private(set) var appleAttempt: AppleAttempt?
    private(set) var appleInProgress = false
    private var preparingApple = false
    private var appleGeneration: Int?
    private var cooldowns: [String: Date] = [:]
    private var active = true
    private var operation = 0

    init(session: AuthSession, reauthentication: AccountDeletionIntent? = nil) {
        self.session = session
        self.reauthentication = reauthentication
        if reauthentication?.provider == .email { mode = .email }
    }
    func allowsProvider(_ provider: AuthProvider) -> Bool {
        reauthentication == nil || reauthentication?.provider == provider
    }
    var modeEnabled: Bool {
        if reauthentication != nil && (mode == .register || mode == .reset) { return false }
        return mode == .phone ? capabilities.phone && allowsProvider(.phone) : capabilities.email && allowsProvider(.email)
    }
    var canSubmit: Bool {
        if mode == .phone { return AuthValidation.phone(phone) != nil && AuthValidation.validCode(code) }
        guard AuthValidation.validEmail(email), AuthValidation.validPassword(password) else { return false }
        return mode == .email || (password == confirmation && AuthValidation.validCode(code))
    }
    private var destination: String { mode == .phone ? (AuthValidation.phone(phone) ?? phone) : AuthValidation.email(email) }
    private var cooldownKey: String { (mode == .phone ? "phone" : "email") + ":" + destination }
    func remaining(at now: Date) -> Int { max(0, Int(ceil((cooldowns[cooldownKey] ?? .distantPast).timeIntervalSince(now)))) }
    var canSend: Bool { active && !busy && remaining(at: Date()) == 0 && (mode == .phone ? AuthValidation.phone(phone) != nil : AuthValidation.validEmail(email)) }
    func load() async {
        guard !loadingCapabilities else { return }
        loadingCapabilities = true
        capabilities = .disabled
        defer { loadingCapabilities = false }
        error = nil
        do {
            let caps = try await session.service.fetch(AuthCapabilities.self, .capabilities)
            guard active else { return }
            capabilities = caps
            if reauthentication == nil && !caps.phone && caps.email { mode = .email }
            if caps.apple && allowsProvider(.apple) { await prepareApple() }
        } catch { if active { self.error = error.localizedDescription } }
    }
    func sendCode() async {
        guard canSend, modeEnabled else { return }
        let key = cooldownKey
        let request: AuthRequest = mode == .phone ? .phoneCode(destination) : .emailCode(destination, purpose: mode == .register ? "register" : "reset_password")
        busy = true; error = nil; message = nil
        defer { busy = false }
        do {
            let delivery = try await session.service.fetch(CodeDelivery.self, request)
            guard active else { return }
            cooldowns[key] = Date().addingTimeInterval(Double(max(0, delivery.retryAfter)))
            message = mode == .phone ? "验证码已发送，5 分钟内有效。" : "如果此邮箱符合条件，将收到验证码，请检查收件箱。"
        } catch { if active { self.error = error.localizedDescription } }
    }
    func submit() async {
        guard active, canSubmit, modeEnabled, !busy else { return }
        busy = true; error = nil; message = nil
        let current = operation
        let submittingMode = mode
        let sessionGeneration = session.sessionGeneration
        defer { busy = false }
        do {
            switch mode {
            case .phone:
                guard let phone = AuthValidation.phone(phone) else { return }
                try await session.login(.phoneLogin(phone: phone, code: code), reauthentication: reauthentication)
            case .email:
                try await session.login(.emailLogin(email: AuthValidation.email(email), password: password), reauthentication: reauthentication)
            case .register:
                try await session.login(.emailRegister(email: AuthValidation.email(email), password: password, code: code))
            case .reset:
                _ = try await session.service.execute(.reset(email: AuthValidation.email(email), password: password, code: code))
                guard active, current == operation else { return }
                if sessionGeneration == session.sessionGeneration,
                   let currentEmail = session.user?.email,
                   AuthValidation.email(currentEmail) == AuthValidation.email(email) {
                    session.clearLocal()
                }
                mode = .email
                message = "密码已重设，请使用新密码登录。原有登录会话已失效。"
            }
            if submittingMode != .reset { authenticated = true }
            clearSecrets()
        } catch { if active, current == operation { self.error = error.localizedDescription } }
    }
    func changeMode(_ next: AuthFormMode) { mode = next; clearSecrets(); error = nil; message = nil }
    func prepareApple() async {
        guard active, capabilities.apple, allowsProvider(.apple), !appleInProgress, !preparingApple else { return }
        preparingApple = true
        defer { preparingApple = false }
        appleAttempt = nil
        let current = operation
        do {
            let challenge = try await session.service.fetch(AppleChallenge.self, .challenge)
            guard active, current == operation else { return }
            appleAttempt = try AppleAttempt(challenge: challenge)
        } catch { if active { self.error = error.localizedDescription } }
    }
    func beginApple() -> AppleAttempt? {
        guard active, allowsProvider(.apple), !busy, let attempt = appleAttempt, attempt.expiresAt > Date() else { return nil }
        appleInProgress = true; busy = true; error = nil
        appleGeneration = session.loginGeneration
        return attempt
    }
    func completeApple(state: String?, token: String, authorizationCode: String, userID: String, nickname: String?) async {
        let attempt = appleAttempt
        appleAttempt = nil
        defer { appleInProgress = false; busy = false }
        do {
            guard active, let attempt, attempt.accepts(state: state), !token.isEmpty, !authorizationCode.isEmpty,
                  let appleGeneration else { throw AuthError.stale }
            try await session.login(.appleLogin(challengeID: attempt.challengeID, token: token, code: authorizationCode, nickname: nickname),
                                    appleUserID: userID, expectedGeneration: appleGeneration, reauthentication: reauthentication)
            authenticated = true
            clearSecrets()
        } catch { if active { self.error = error.localizedDescription } }
    }
    func appleFailed(_ failure: Error?) {
        appleAttempt = nil; appleGeneration = nil; appleInProgress = false; busy = false
        if let failure { error = failure.localizedDescription }
    }
    func cancel() { active = false; operation += 1; appleAttempt = nil; session.cancelPendingLogin(); clearSecrets() }
    private func clearSecrets() { password = ""; confirmation = ""; code = "" }
}
