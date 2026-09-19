import Foundation
import SwiftData

/// 部分赠卖拆出已处置记录，保留原购入日期与单价，避免剩余持仓成本改变。
enum HoldingDisposal {
    enum Failure: Error { case invalid }
    static func apply(record: HoldingRecord, grams: Double, proceeds: Double, kind: String, date: Date, context: ModelContext, counterparty: String? = nil) throws {
        guard record.disposition == "holding", grams.isFinite, grams > 0, grams <= record.grams, proceeds.isFinite, proceeds >= 0,
              ["sold", "gift"].contains(kind), date >= record.timestamp, date <= .now else { throw Failure.invalid }
        let disposed: HoldingRecord
        if grams < record.grams {
            disposed = HoldingRecord(grams: grams, unitPriceCNY: record.unitPriceCNY, timestamp: record.timestamp, note: record.note, createdAt: record.createdAt)
            disposed.brand = record.brand; disposed.bookName = record.bookName
            disposed.purchaseID = record.purchaseID ?? record.id
            disposed.extraFee = record.extraFee * grams / record.grams
            disposed.purchaseChannel = record.purchaseChannel
            disposed.counterparty = record.counterparty
            record.extraFee -= disposed.extraFee
            record.grams -= grams
            context.insert(disposed)
        } else { disposed = record }
        if let counterparty { disposed.counterparty = counterparty }
        disposed.disposition = kind
        disposed.disposedAt = date
        disposed.disposalAmount = kind == "gift" ? 0 : proceeds
        try context.save()
    }
}
