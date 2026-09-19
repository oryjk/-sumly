import SwiftUI
import SwiftData

@main
struct SumlyApp: App {
    /// 本地持仓存储；后续账号体系就绪后迁移到后端同步。
    private static let holdingsContainer: ModelContainer = {
        do {
            return try ModelContainer(for: HoldingRecord.self)
        } catch {
            fatalError("无法初始化本地持仓存储: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            GoldRootView()
                .tint(GoldTheme.gold)
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.holdingsContainer)
    }
}


private struct GoldRootView: View {
    @State private var selectedTab = 0
    @State private var showingAdd = false
    @State private var showingNotice = false

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 430
            ZStack(alignment: .bottom) {
                GoldTheme.background.ignoresSafeArea()
                if selectedTab == 0 {
                    HomeView()
                } else {
                    HoldingsView()
                        .padding(.bottom, 80 * scale)
                }
                tabBar(scale: scale)
                    .frame(height: 80 * scale)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showingAdd) {
            AddHoldingSheet(defaultUnitPrice: nil)
        }
        .alert("功能尚未接入", isPresented: $showingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("记账与个人中心暂未开放。")
        }
        .persistentSystemOverlays(.hidden)
    }

    private func tabBar(scale: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                GoldTabBarShape().fill(GoldTheme.card)
                tabItem("动态", symbol: "house.fill", index: 0, scale: scale)
                    .position(x: width * 0.1, y: 42 * scale)
                tabItem("攒金", symbol: "bag.fill", index: 1, scale: scale)
                    .position(x: width * 0.3, y: 42 * scale)
                tabItem("记账", symbol: "yensign.square.fill", index: 2, scale: scale)
                    .position(x: width * 0.7, y: 42 * scale)
                tabItem("我的", symbol: "person.fill", index: 3, scale: scale)
                    .position(x: width * 0.9, y: 42 * scale)
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 32 * scale, weight: .semibold))
                        .foregroundStyle(GoldTheme.card)
                        .frame(width: 65 * scale, height: 65 * scale)
                        .background(GoldTheme.gold, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加黄金")
                .position(x: width / 2, y: 16 * scale)
            }
        }
    }

    private func tabItem(_ title: String, symbol: String, index: Int, scale: CGFloat) -> some View {
        Button {
            if index < 2 { selectedTab = index } else { showingNotice = true }
        } label: {
            VStack(spacing: 7 * scale) {
                if index == 1 {
                    GoldMoneyBagShape()
                        .fill(selectedTab == index ? GoldTheme.gold : GoldTheme.textSecondary)
                        .frame(width: 25 * scale, height: 25 * scale)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 23 * scale, weight: .semibold))
                        .frame(height: 25 * scale)
                }
                Text(title)
                    .font(.system(size: 11 * scale))
            }
            .foregroundStyle(selectedTab == index ? GoldTheme.gold : GoldTheme.textSecondary)
            .frame(width: 64 * scale, height: 58 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }
}
