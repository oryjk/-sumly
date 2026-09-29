import SwiftUI

struct AccountView: View {
    @Bindable var session: AuthSession
    @State private var showLogin = false
    @State private var reauthentication: AccountDeletionIntent?
    @State private var deletionConfirmation: AccountDeletionIntent?
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我的").font(.largeTitle.bold()).foregroundStyle(GoldTheme.text)
                    Text("记下每一克，积累每一天。")
                        .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                }.padding(.top, 24)
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: session.user == nil ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44, weight: .light)).foregroundStyle(GoldTheme.gold)
                    if let user = session.user {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(user.nickname.isEmpty ? "记金用户" : user.nickname).font(.title2.bold())
                            Text(user.maskedIdentifier).font(.body.monospaced())
                            Text("通过 \(user.provider.title) 登录").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }
                    } else {
                        Text("让积累，有自己的名字。")
                            .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("登录或注册记金账户，继续记录你的黄金日常。")
                            .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                        Button("登录 / 注册") { openLogin() }
                            .buttonStyle(GoldPrimaryButtonStyle())
                            .accessibilityIdentifier("account.login")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).goldCard(padding: 24)
                VStack(alignment: .leading, spacing: 12) {
                    Label("持仓只保存在此设备", systemImage: "iphone")
                        .font(.headline).foregroundStyle(GoldTheme.goldSoft)
                    Text("登录暂不上传或同步持仓。行情、持仓和添加记录仍可匿名使用；切换或注销账户不会删除本机记录。")
                        .font(.subheadline).foregroundStyle(GoldTheme.textSecondary).lineSpacing(5)
                }.goldCard(padding: 20)
                if let user = session.user {
                    VStack(spacing: 14) {
                        Button("重新验证 \(user.provider.title) 登录") { openLogin() }
                            .foregroundStyle(GoldTheme.gold)
                        Button("退出登录") { confirmLogout = true }
                            .foregroundStyle(GoldTheme.text)
                        Divider().overlay(GoldTheme.cardStroke)
                        Button(role: .destructive) {
                            deletionConfirmation = session.beginAccountDeletion()
                            confirmDelete = deletionConfirmation != nil
                        } label: {
                            if deleting { ProgressView() } else { Text("注销账户") }
                        }.foregroundStyle(GoldTheme.up)
                    }.frame(maxWidth: .infinity).goldCard(padding: 20).disabled(deleting)
                }
                if let notice = session.notice { Text(notice).font(.footnote).foregroundStyle(GoldTheme.textSecondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(GoldTheme.up).accessibilityLabel("错误：" + error) }
            }.padding(.horizontal, 22).padding(.bottom, 30)
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .sheet(isPresented: $showLogin) { AuthenticationSheet(session: session, reauthentication: reauthentication) }
        .onChange(of: session.user?.id) { _, _ in
            deletionConfirmation = nil
            confirmDelete = false
        }
        .confirmationDialog("退出当前账户？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await session.logout() } }
        } message: { Text("本机持仓会保留。你仍可匿名查看行情和记录持仓。") }
        .confirmationDialog("永久注销此账户？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("永久注销账户", role: .destructive) {
                if let intent = deletionConfirmation { Task { await deleteAccount(confirming: intent) } }
            }
        } message: {
            if let intent = deletionConfirmation {
                Text("待注销账户：\(intent.provider.title) · \(intent.maskedIdentifier)\n\n账户身份与服务端登录会话将永久删除，无法恢复。需要最近 5 分钟内重新登录。本机游客持仓会保留，它们不是云端账户数据。")
            }
        }
    }
    private func openLogin() {
        session.cancelAccountDeletion()
        deletionConfirmation = nil
        reauthentication = nil
        showLogin = true
    }
    private func deleteAccount(confirming intent: AccountDeletionIntent) async {
        deleting = true; error = nil
        defer { deleting = false }
        do { try await session.deleteAccount(confirming: intent) }
        catch AuthError.reauthenticate {
            error = AuthError.reauthenticate.localizedDescription
            reauthentication = intent
            showLogin = true
        } catch { self.error = error.localizedDescription }
    }
}
