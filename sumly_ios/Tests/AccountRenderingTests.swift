import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Sumly

/// Rendering-only fixtures. No real network, Keychain, user accounts or provider calls.
private struct AccountRenderService: AuthServicing {
    let phoneEnabled: Bool
    func execute(_ request: AuthRequest) async throws -> Data {
        switch request.path {
        case "capabilities":
            return Data("{\"apple\":true,\"phone\":\(phoneEnabled),\"email\":true}".utf8)
        case "apple/challenge":
            return try JSONSerialization.data(withJSONObject: [
                "challenge_id": "render-only-challenge",
                "nonce": String(repeating: "n", count: 43),
                "expires_in": 300,
            ])
        default:
            throw AuthError.unavailable
        }
    }
}

@MainActor private final class AccountRenderStore: CredentialStoring {
    func load() throws -> StoredSession? { nil }
    func save(_ session: StoredSession) throws {}
    func clear() throws {}
}

@MainActor private func captureAccountView<Content: View>(_ content: Content, name: String) async throws {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene)
    let controller = UIHostingController(rootView: content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoldTheme.background)
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold))
    window.rootViewController = controller
    window.overrideUserInterfaceStyle = .dark
    window.makeKeyAndVisible()
    defer {
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }
    // These are rendering artifacts, not timing-sensitive auth assertions. Allow
    // SwiftUI's task and UIKit layout/display passes to finish before capturing.
    try await Task.sleep(for: .milliseconds(500))
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    #expect(image.size.width > 300)
    #expect(image.size.height > 600)
    let data = try #require(image.pngData())
    #expect(data.count > 10_000)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-auth-ui-review", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(name + ".png")
    try data.write(to: destination, options: .atomic)
    print("AUTH_RENDER_ARTIFACT: \(destination.path)")
}

@MainActor @Test func renderGuestAccountForVisualReview() async throws {
    let session = AuthSession(service: AccountRenderService(phoneEnabled: true), store: AccountRenderStore())
    try await captureAccountView(AccountView(session: session), name: "account-guest")
}

@MainActor @Test func renderPhoneAndAppleLoginForVisualReview() async throws {
    let session = AuthSession(service: AccountRenderService(phoneEnabled: true), store: AccountRenderStore())
    try await captureAccountView(AuthenticationSheet(session: session), name: "login-phone-apple")
}

@MainActor @Test func renderEmailAndAppleLoginForVisualReview() async throws {
    let session = AuthSession(service: AccountRenderService(phoneEnabled: false), store: AccountRenderStore())
    try await captureAccountView(AuthenticationSheet(session: session), name: "login-email-apple")
}
