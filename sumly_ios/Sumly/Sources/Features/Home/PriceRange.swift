import Foundation

/// 走势图时间区间。
enum PriceRange: String, CaseIterable, Identifiable, Sendable {
    case oneMonth = "1月"
    case threeMonths = "3月"
    case sixMonths = "6月"
    case oneYear = "1年"
    case all = "全部"

    var id: String { rawValue }

    /// 走势平滑窗口（天）：短区间保留细节，长区间过滤日级噪声。
    var smoothingWindow: Int {
        switch self {
        case .oneMonth: 3
        case .threeMonths: 5
        case .sixMonths, .oneYear: 7
        case .all: 9
        }
    }

    /// 从日线序列（升序或乱序均可）中截取截至 `now` 的该区间。
    func slice(_ prices: [GoldDailyPrice], calendar: Calendar = .current, now: Date = .now) -> [GoldDailyPrice] {
        guard let offset else { return prices }
        guard let cutoff = calendar.date(byAdding: offset.component, value: -offset.count, to: now) else {
            return prices
        }
        return prices.filter { $0.date >= cutoff }
    }

    private var offset: (component: Calendar.Component, count: Int)? {
        switch self {
        case .oneMonth: (.month, 1)
        case .threeMonths: (.month, 3)
        case .sixMonths: (.month, 6)
        case .oneYear: (.year, 1)
        case .all: nil
        }
    }
}
