import Foundation
import Testing
@testable import Sumly

private func reviewLogin(_ id: Int64 = 42, token: String = "original") -> LoginResult {
    LoginResult(token: token, refreshToken: token + "-refresh", expiresIn: 900,
                user: NativeUser(id: id, nickname: "test", avatarURL: "", email: "test\(id)@example.com", phoneNumber: nil, status: "active", provider: .email))
}
@MainActor private final class ReviewStore: CredentialStoring {
    var value: StoredSession?
    func load() throws -> StoredSession? { value }
    func save(_ session: StoredSession) throws { value = session }
    func clear() throws { value = nil }
}
private actor ReviewService: AuthServicing {
    var nextLogin = reviewLogin()
    var loginFails = false
    var pendingRefresh: CheckedContinuation<Data, any Error>?
    var revoked: [String] = []
    var deletes = 0
    func configureLogin(_ result: LoginResult, fails: Bool = false) { nextLogin = result; loginFails = fails }
    func waitingForRefresh() -> Bool { pendingRefresh != nil }
    func releaseRefresh() throws {
        let pending = pendingRefresh; pendingRefresh = nil
        pending?.resume(returning: try JSONEncoder().encode(reviewLogin(token: "rotated")))
    }
    func execute(_ request: AuthRequest) async throws -> Data {
        switch request.path {
        case "refresh": return try await withCheckedThrowingContinuation { pendingRefresh = $0 }
        case "logout": revoked.append(request.fields["refresh_token"] ?? ""); return Data("{}".utf8)
        case "account": deletes += 1; return Data("{}".utf8)
        case "capabilities": return Data(#"{"apple":false,"phone":true,"email":true}"#.utf8)
        case "email/code": return Data(#"{"retry_after":60,"expires_in":300}"#.utf8)
        case "me": return try JSONEncoder().encode(nextLogin.user)
        default:
            if loginFails { throw AuthError.unauthorized }
            return try JSONEncoder().encode(nextLogin)
        }
    }
}
private let reviewRequest = AuthRequest.emailLogin(email: "test42@example.com", password: "abcdefghijkl")

@MainActor @Test func committedRefreshSurvivesLoginSheetDismissal() async throws {
    let service = ReviewService(); let store = ReviewStore()
    let session = AuthSession(service: service, store: store)
    try await session.login(reviewRequest)
    let refresh = Task { try await session.refresh() }
    while !(await service.waitingForRefresh()) { await Task.yield() }
    AuthFormModel(session: session).cancel()
    try await service.releaseRefresh()
    _ = await refresh.result
    #expect(session.stored?.result.refreshToken == "rotated-refresh")
    #expect(store.value?.result.refreshToken == "rotated-refresh")
}

@MainActor @Test func committedRefreshSurvivesFailedLogin() async throws {
    let service = ReviewService(); let store = ReviewStore()
    let session = AuthSession(service: service, store: store)
    try await session.login(reviewRequest)
    let refresh = Task { try await session.refresh() }
    while !(await service.waitingForRefresh()) { await Task.yield() }
    await service.configureLogin(reviewLogin(99), fails: true)
    await #expect(throws: AuthError.unauthorized) { try await session.login(reviewRequest) }
    try await service.releaseRefresh()
    _ = await refresh.result
    #expect(session.user?.id == 42)
    #expect(store.value?.result.refreshToken == "rotated-refresh")
}

@MainActor @Test func successfulReplacementDiscardsOldAccountRefresh() async throws {
    let service = ReviewService(); let store = ReviewStore()
    let session = AuthSession(service: service, store: store)
    try await session.login(reviewRequest)
    let refresh = Task { try await session.refresh() }
    while !(await service.waitingForRefresh()) { await Task.yield() }
    await service.configureLogin(reviewLogin(99, token: "replacement"))
    try await session.login(reviewRequest)
    try await service.releaseRefresh()
    _ = await refresh.result
    #expect(session.user?.id == 99)
    #expect(store.value?.result.refreshToken == "replacement-refresh")
}

@MainActor @Test func emailCooldownIsSharedBetweenRegisterAndReset() async {
    let form = AuthFormModel(session: AuthSession(service: ReviewService(), store: ReviewStore()))
    await form.load()
    form.changeMode(.register)
    form.email = " Test42@Example.com "
    await form.sendCode()
    form.changeMode(.reset)
    form.email = "test42@example.com"
    #expect(!form.canSend)
    #expect(form.remaining(at: Date()) > 0)
}

@MainActor @Test func dismissedLoginFormCannotSubmit() async {
    let session = AuthSession(service: ReviewService(), store: ReviewStore())
    let form = AuthFormModel(session: session)
    await form.load()
    form.cancel()
    form.email = "test42@example.com"; form.password = "abcdefghijkl"; form.mode = .email
    await form.submit()
    #expect(session.user == nil)
}

@Test func authenticationPrivacyManifestDeclaresOnlyLinkedAccountData() throws {
    // On iOS this reads the actual host app bundle, so packaging mistakes fail the parent suite.
    #if os(iOS)
    let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    #else
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sumly/Resources/PrivacyInfo.xcprivacy")
    #endif
    let plist = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    let collected = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    #expect(Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }) == Set([
        "NSPrivacyCollectedDataTypeName", "NSPrivacyCollectedDataTypeEmailAddress",
        "NSPrivacyCollectedDataTypePhoneNumber", "NSPrivacyCollectedDataTypeUserID"
    ]))
    for entry in collected {
        #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
        #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        #expect(entry["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }
    #expect(plist["NSPrivacyTracking"] as? Bool == false)
    #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    let accessed = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    #expect(accessed.contains { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" && $0["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"] })
}

@MainActor @Test func deletionReauthenticationRejectsOtherAccountBeforeSaving() async throws {
    let service = ReviewService(); let store = ReviewStore()
    let session = AuthSession(service: service, store: store)
    try await session.login(reviewRequest)
    let intent = try #require(session.beginAccountDeletion())
    await service.configureLogin(reviewLogin(99, token: "other"))
    await #expect(throws: AuthError.accountMismatch) {
        try await session.login(reviewRequest, reauthentication: intent)
    }
    #expect(session.user?.id == 42)
    #expect(store.value?.result.refreshToken == "original-refresh")
    #expect(session.deletionIntent == intent)
    #expect(await service.revoked == ["other-refresh"])
    #expect(await service.deletes == 0)
}

@MainActor @Test func matchingDeletionReauthenticationStillNeedsExplicitConfirmation() async throws {
    let service = ReviewService(); let session = AuthSession(service: service, store: ReviewStore())
    try await session.login(reviewRequest)
    let intent = try #require(session.beginAccountDeletion())
    await service.configureLogin(reviewLogin(token: "reauthenticated"))
    try await session.login(reviewRequest, reauthentication: intent)
    #expect(session.deletionIntent == intent)
    #expect(session.stored?.result.token == "reauthenticated")
    #expect(await service.deletes == 0)
    try await session.deleteAccount(confirming: intent)
    #expect(session.user == nil)
}

@MainActor @Test func accountSwitchInvalidatesPendingDeletionConfirmation() async throws {
    let service = ReviewService(); let session = AuthSession(service: service, store: ReviewStore())
    try await session.login(reviewRequest)
    let originalIntent = try #require(session.beginAccountDeletion())
    await service.configureLogin(reviewLogin(99, token: "other"))
    try await session.login(reviewRequest)
    #expect(session.deletionIntent == nil)
    await #expect(throws: AuthError.stale) { try await session.deleteAccount(confirming: originalIntent) }
    #expect(await service.deletes == 0)
    #expect(session.user?.id == 99)
}

@MainActor private final class ReviewKeychain: KeychainDataStoring {
    var data: Data?
    var failDelete = true
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func remove() throws { if failDelete { throw AuthError.keychain(-1) }; data = nil }
}
@MainActor @Test func durableLogoutMarkerBlocksRelaunchedSessionAfterKeychainDeleteFailure() async throws {
    let suite = "sumly-auth-test-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let keychain = ReviewKeychain()
    do {
        let store = KeychainCredentialStore(defaults: defaults, keychain: keychain)
        let session = AuthSession(service: ReviewService(), store: store)
        try await session.login(reviewRequest)
        await session.logout()
        #expect(session.user == nil)
        #expect(keychain.data != nil) // Simulates a committed save whose delete was rejected by Keychain.
    }
    let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
    let relaunchedStore = KeychainCredentialStore(defaults: reopenedDefaults, keychain: keychain)
    let relaunchedSession = AuthSession(service: ReviewService(), store: relaunchedStore)
    await relaunchedSession.restore()
    #expect(relaunchedSession.user == nil)
    keychain.failDelete = false
    await relaunchedSession.restore()
    #expect(relaunchedSession.user == nil)
    #expect(keychain.data == nil)
}
