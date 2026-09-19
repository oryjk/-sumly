import Foundation
import SwiftData

/// 一条黄金持仓记录：买入克数、买入单价（元/克）与持有时点。
/// `timestamp` 是用户指定的精确时间点（补录历史时可为过去时间），
/// 后续画持仓走势 / 收益曲线时按它对齐历史行情。
@Model
final class HoldingRecord {
    @Attribute(.unique) var id: UUID
    var grams: Double
    /// 购入单价，元/克。
    var unitPriceCNY: Double
    /// 持有时间点（用户指定）。
    var timestamp: Date
    var note: String
    var createdAt: Date
    // 新字段有默认值，旧持仓通过 SwiftData 轻量迁移保留。
    var brand: String = ""
    var bookName: String = "默认账本"
    var disposition: String = "holding"
    var disposedAt: Date?
    var disposalAmount: Double = 0

    init(
        grams: Double,
        unitPriceCNY: Double,
        timestamp: Date,
        note: String = "",
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.grams = grams
        self.unitPriceCNY = unitPriceCNY
        self.timestamp = timestamp
        self.note = note
        self.createdAt = createdAt
    }
}
