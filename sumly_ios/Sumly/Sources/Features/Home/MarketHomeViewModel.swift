import Foundation
import Observation

struct MarketChartPoint: Sendable, Equatable {
    let date: Date
    let price: Double
}

protocol GoldIntradayServicing: Sendable {
    func fetchIntraday() async throws -> [MarketChartPoint]
}

protocol GoldRealtimeServicing: Sendable {
    func fetchRealtime() async throws -> [MarketChartPoint]
}

enum MarketRange: String, CaseIterable {
    case realtime = "实时"
    case month = "近一月"
    case quarter = "近三月"
}

@MainActor @Observable
final class MarketHomeViewModel {
    var range: MarketRange = .realtime { didSet { selectedDate = nil } }
    var selectedDate: Date?
    private(set) var quote: GoldQuote?
    private(set) var daily: [GoldDailyPrice] = []
    private(set) var realtime: [MarketChartPoint] = []
    private(set) var loading = true
    private var quoteFailed = false
    private var dailyFailed = false
    private var realtimeFailed = false
    private let dailyService: any GoldPriceServicing
    private let quoteService: any GoldQuoteServicing
    private let realtimeService: any GoldRealtimeServicing

    init(dailyService: any GoldPriceServicing = BackendGoldPriceService(),
         quoteService: any GoldQuoteServicing = BackendGoldPriceService(),
         realtimeService: any GoldRealtimeServicing = BackendGoldPriceService()) {
        self.dailyService = dailyService
        self.quoteService = quoteService
        self.realtimeService = realtimeService
    }

    var price: Double? {
        guard let quote, quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 else { return nil }
        return quote.cnyPerGram
    }

    var points: [MarketChartPoint] {
        if range == .realtime { return Self.realtimeWindow(realtime, now: .now) }
        guard let quote, let price, quote.usdCNY.isFinite, quote.usdCNY > 0 else { return [] }
        let factor = quote.usdCNY / 31.1034768
        var result: [MarketChartPoint]
        do {
            let months = range == .month ? 1 : 3
            let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: .now)!
            result = daily.filter { $0.date >= cutoff && $0.date <= Date.now }
                .map { MarketChartPoint(date: $0.date, price: $0.close * factor) }
            // 当日尚未收盘时，用当前报价代替日线中的当日收盘。
            result.removeAll { Calendar.current.isDate($0.date, inSameDayAs: quote.asOf) }
        }
        result = result.filter { $0.price.isFinite && $0.price > 0 }.sorted { $0.date < $1.date }
        if let last = result.last, last.date == quote.asOf {
            result[result.count - 1] = MarketChartPoint(date: quote.asOf, price: price)
        } else if result.last.map({ $0.date < quote.asOf }) ?? true {
            result.append(MarketChartPoint(date: quote.asOf, price: price))
        }
        return result
    }

    var showsInitialLoading: Bool { loading && price == nil && points.isEmpty }

    var message: String? {
        if loading { return "正在获取行情…" }
        if quoteFailed { return quote == nil ? "行情加载失败，点击重试" : "刷新失败，显示上次行情 · 点击重试" }
        if price == nil { return "人民币报价暂不可用 · 点击重试" }
        if range == .realtime ? realtimeFailed : dailyFailed { return "走势刷新失败 · 点击重试" }
        if let quote, Date.now.timeIntervalSince(quote.asOf) > 180 {
            return "最近报价 \(quote.asOf.formatted(.dateTime.month().day().hour().minute()))"
        }
        if range == .realtime {
            if realtime.isEmpty { return "暂无最新走势，请稍后再试" }
            if let last = realtime.last, Date.now.timeIntervalSince(last.date) > 20 {
                return "行情更新暂停，最近更新 \(last.date.formatted(.dateTime.hour().minute().second()))"
            }
        }
        return nil
    }

    nonisolated static func realtimeWindow(_ points: [MarketChartPoint], now: Date) -> [MarketChartPoint] {
        let valid = points.filter { $0.date <= now && $0.price.isFinite && $0.price > 0 }
            .sorted { $0.date < $1.date }
        guard let latest = valid.last else { return [] }
        let cutoff = latest.date.addingTimeInterval(-1200)
        return valid.filter { $0.date >= cutoff }
    }

    /// 纵轴保留呼吸空间，以半元为刻度边界，避免每次尾点变化都拉伸整条曲线。
    nonisolated static func chartDomain(_ points: [MarketChartPoint]) -> ClosedRange<Double> {
        let low = points.map(\.price).min() ?? 0
        let high = points.map(\.price).max() ?? 1
        let center = (low + high) / 2
        let span = max((high - low) * 1.5, 1)
        return (floor((center - span / 2) * 2) / 2)...(ceil((center + span / 2) * 2) / 2)
    }

    var selectedPoint: MarketChartPoint? {
        let values = points
        guard let selectedDate, let first = values.first, let last = values.last,
              selectedDate >= first.date, selectedDate <= last.date else { return nil }
        return values.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    func start() async {
        await refresh()
        var tick = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await loadQuote()
            tick += 1
            await loadRealtime()
            if tick % 12 == 0 { await loadDaily() }
        }
    }

    func refresh() async {
        if quote == nil && realtime.isEmpty && daily.isEmpty { loading = true }
        async let q: Void = loadQuote()
        async let d: Void = loadDaily()
        async let i: Void = loadRealtime()
        _ = await (q, d, i)
        loading = false
    }

    private func loadQuote() async {
        do { quote = try await quoteService.fetchQuote(); quoteFailed = false }
        catch { if !Task.isCancelled { quoteFailed = true } }
    }
    private func loadDaily() async {
        do { daily = try await dailyService.fetchDailyPrices(); dailyFailed = false }
        catch { if !Task.isCancelled { dailyFailed = true } }
    }
    private func loadRealtime() async {
        do { realtime = try await realtimeService.fetchRealtime(); realtimeFailed = false }
        catch { if !Task.isCancelled { realtimeFailed = true } }
    }
}
