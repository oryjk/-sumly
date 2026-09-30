import Foundation
import Observation

struct HoldingPurchasePriceReference {
    let price: Double // CNY/g
    let date: Date
    let isHistorical: Bool
    let exchangeRate: Double?
}

/// 购入日期决定自动参考价；实际购入单价以用户填写为准。
@MainActor @Observable final class HoldingPurchasePriceModel {
    enum Issue { case missingDay, missingExchangeRate, unavailable }
    private(set) var selectedDay: Date
    private(set) var priceText = ""
    private(set) var isManual = false
    private(set) var isLoading = false
    private(set) var reference: HoldingPurchasePriceReference?
    private(set) var issue: Issue?

    private let basis: GoldMarketBasis
    private let service: any GoldPriceServicing & GoldQuoteServicing
    private let calendar = Calendar.current
    private var generation = 0

    init(date: Date, basis: GoldMarketBasis, initialPrice: Double? = nil,
         service: any GoldPriceServicing & GoldQuoteServicing) {
        selectedDay = Calendar.current.startOfDay(for: date)
        self.basis = basis
        self.service = service
        // 历史日期绝不预填当前报价。
        if Calendar.current.isDateInToday(date), let initialPrice, Self.isValid(initialPrice) {
            reference = .init(price: initialPrice, date: selectedDay, isHistorical: false, exchangeRate: nil)
            priceText = Self.format(initialPrice)
        }
    }

    var validPrice: Double? {
        guard let value = Double(priceText.trimmingCharacters(in: .whitespacesAndNewlines)), Self.isValid(value) else { return nil }
        return value
    }

    func selectDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        guard day != selectedDay else { return }
        generation += 1
        selectedDay = day
        reference = nil
        issue = nil
        isLoading = false
        if !isManual { priceText = "" }
    }

    func editPrice(_ text: String) {
        isManual = true
        priceText = text
    }

    func useReference() {
        guard let reference else { return }
        isManual = false
        priceText = Self.format(reference.price)
    }

    func load(now: Date = .now) async {
        generation += 1
        let request = generation
        let day = selectedDay
        isLoading = true
        issue = nil
        defer { if generation == request { isLoading = false } }
        do {
            let result: HoldingPurchasePriceReference
            if calendar.isDate(day, inSameDayAs: now) {
                let quote = try await service.fetchQuote()
                guard Self.isValid(quote.cnyPerGram) else { throw PriceFailure.unavailable }
                result = .init(price: quote.cnyPerGram, date: day, isHistorical: false, exchangeRate: nil)
            } else {
                // 已缓存的历史收盘价可立即复用；缺少所选日期才进行增量同步。
                let cached = await service.cachedDailyPrices()
                let prices: [GoldDailyPrice]
                if let cached, close(in: cached, on: day) != nil { prices = cached }
                else { prices = try await service.fetchDailyPrices() }
                guard let close = close(in: prices, on: day) else { throw PriceFailure.missingDay }
                if basis == .domestic {
                    result = .init(price: close, date: day, isHistorical: true, exchangeRate: nil)
                } else {
                    // 国际日线是 USD/oz；当前数据源没有历史汇率，必须明确标为参考折算价。
                    let quote: GoldQuote
                    do { quote = try await service.fetchQuote() }
                    catch {
                        guard let cachedQuote = await service.cachedQuote() else { throw PriceFailure.missingExchangeRate }
                        quote = cachedQuote
                    }
                    guard quote.usdCNY.isFinite, quote.usdCNY > 0 else { throw PriceFailure.missingExchangeRate }
                    let price = close * quote.usdCNY / 31.1034768
                    guard Self.isValid(price) else { throw PriceFailure.unavailable }
                    result = .init(price: price, date: day, isHistorical: true, exchangeRate: quote.usdCNY)
                }
            }
            guard generation == request, !Task.isCancelled else { return }
            reference = result
            if !isManual { priceText = Self.format(result.price) }
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            switch error {
            case PriceFailure.missingDay: issue = .missingDay
            case PriceFailure.missingExchangeRate: issue = .missingExchangeRate
            default: issue = .unavailable
            }
        }
    }

    private func close(in prices: [GoldDailyPrice], on day: Date) -> Double? {
        prices.first { calendar.isDate($0.date, inSameDayAs: day) && Self.isValid($0.close) }?.close
    }
    private enum PriceFailure: Error { case missingDay, missingExchangeRate, unavailable }
    private static func isValid(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= 1_000_000 }
    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
