import Foundation

enum GoldMarketBasis: String, CaseIterable, Identifiable, Sendable {
    case domestic
    case international

    var id: String { rawValue }

    var title: String {
        switch self {
        case .domestic: "国内"
        case .international: "国际"
        }
    }

    /// 国内走 Au99.99 显式品种；国际沿用伦敦金默认链路。
    var instrumentID: String? {
        switch self {
        case .domestic: "au9999"
        case .international: nil
        }
    }
}
