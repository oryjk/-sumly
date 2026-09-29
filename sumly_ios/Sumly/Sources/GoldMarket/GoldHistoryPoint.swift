import Foundation

enum GoldPointGranularity: String, Decodable, Sendable {
    case annual, daily, realtime
    var label: String { switch self { case .annual: "年度均价参考"; case .daily: "日线收盘"; case .realtime: "实时报价" } }
}
struct GoldHistoryPoint: Sendable, Equatable {
    let date: Date
    let price: Double // USD per troy ounce
    let granularity: GoldPointGranularity
    let source: String
}
protocol GoldHistoryServicing: Sendable {
    func fetchHistory() async throws -> [GoldHistoryPoint]
}
