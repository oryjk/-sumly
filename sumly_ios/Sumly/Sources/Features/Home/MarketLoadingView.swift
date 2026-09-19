import SwiftUI

/// 首次进入行情时的加载页面；后台刷新不遮挡已有数据。
struct MarketLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            GoldTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(GoldTheme.gold)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .frame(width: 88, height: 88)
                    .background(GoldTheme.gold.opacity(0.08), in: GoldTheme.cardShape)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(GoldTheme.gold)
                        .accessibilityHidden(true)
                    Text("正在获取行情…")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在获取行情，请稍候")
    }
}
