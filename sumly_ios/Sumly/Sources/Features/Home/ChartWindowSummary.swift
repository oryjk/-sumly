import SwiftUI

struct ChartWindowSummary: View {
    let statistics: ChartWindowStatistics
    var body: some View {
        Group {
            if let change = statistics.change, let percent = statistics.percent {
                Text("区间 " + signed(change) + " 元/克（" + signed(percent) + "%）")
                    .foregroundStyle(change > 0 ? GoldTheme.up : change < 0 ? GoldTheme.down : GoldTheme.textSecondary)
            } else {
                Text("区间涨跌幅暂无").foregroundStyle(GoldTheme.textSecondary)
            }
        }
        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("chart.windowChange")
    }
    private func signed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return (rounded > 0 ? "+" : "") + String(format: "%.2f", rounded == 0 ? 0 : rounded)
    }
}
