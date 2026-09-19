import Foundation
import Observation

/// 首页状态与金价走势编排：加载、区间切片、十字光标选点、实时报价轮询与涨跌统计。
@MainActor
@Observable
final class HomeViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    /// 实时报价轮询间隔。
    static let quotePollInterval: Duration = .seconds(3)

    private(set) var phase: Phase = .loading
    private(set) var prices: [GoldDailyPrice] = []

    var range: PriceRange = .oneYear {
        didSet {
            recomputeVisibleSeries()
            selectedDate = nil
        }
    }

    private(set) var visiblePrices: [GoldDailyPrice] = []

    /// 绘图序列 = 可见区间做中心移动平均：端点保持精确值（最新价不失真），
    /// 中部过滤日级噪声让走势柔和；涨跌统计与大数字仍用 `visiblePrices` 真实值。
    private(set) var plottablePrices: [GoldDailyPrice] = []

    /// 图表十字光标选中的日期（由 `chartXSelection` 写入），自动吸附到最近交易日。
    var selectedDate: Date? {
        didSet { selectedPoint = nearestPoint(to: selectedDate) }
    }

    private(set) var selectedPoint: GoldDailyPrice?

    /// 最近一次实时报价；nil 表示尚未轮询成功。
    private(set) var liveQuote: GoldQuote?

    private let service: any GoldPriceServicing
    private let quoteService: (any GoldQuoteServicing)?
    /// date → 全量序列下标，用于定位某日的前收盘。
    private var indexByDate: [Date: Int] = [:]

    init(
        service: any GoldPriceServicing = BackendGoldPriceService(),
        quoteService: (any GoldQuoteServicing)? = BackendGoldPriceService()
    ) {
        self.service = service
        self.quoteService = quoteService
    }

    /// 页面入口：首次加载日线，随后每 3 秒轮询实时报价。
    /// 在视图 `.task` 中调用，视图销毁时任务自动取消。
    func start() async {
        await load()
        guard let quoteService else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.quotePollInterval)
            guard !Task.isCancelled else { return }
            await pollQuote()
        }
    }

    func load() async {
        if prices.isEmpty { phase = .loading }
        do {
            let fetched = try await service.fetchDailyPrices()
            liveQuote = nil
            replacePrices(fetched)
            selectedDate = nil
            phase = .loaded
        } catch is CancellationError {
            // 视图销毁导致任务取消，保留现有状态
        } catch {
            // 已有数据时刷新失败不打断浏览，仅空数据进入失败态
            if prices.isEmpty { phase = .failed }
        }
    }

    /// 拉一次实时报价；失败静默保留旧值（轮询不弹错误）。
    func pollQuote() async {
        guard phase == .loaded, let quoteService else { return }
        guard let quote = try? await quoteService.fetchQuote() else { return }
        applyQuote(quote)
    }

    /// 用实时报价更新最后一根日线：同日就地更新收盘（并放宽高低价），跨日追加新 bar。
    func applyQuote(_ quote: GoldQuote) {
        liveQuote = quote
        guard !prices.isEmpty else { return }

        let calendar = Calendar.current
        let lastIndex = prices.count - 1
        if calendar.isDate(quote.asOf, inSameDayAs: prices[lastIndex].date) {
            let last = prices[lastIndex]
            var updated = prices
            updated[lastIndex] = GoldDailyPrice(
                date: last.date,
                open: last.open,
                high: max(last.high, quote.price),
                low: min(last.low, quote.price),
                close: quote.price
            )
            replacePrices(updated)
        } else if let newDay = Self.noon(of: quote.asOf, calendar: calendar), newDay > prices[lastIndex].date {
            // 新交易日：以昨收开盘、当前价收盘的临时 bar
            let prevClose = prices[lastIndex].close
            var updated = prices
            updated.append(
                GoldDailyPrice(
                    date: newDay,
                    open: prevClose,
                    high: max(prevClose, quote.price),
                    low: min(prevClose, quote.price),
                    close: quote.price
                )
            )
            replacePrices(updated)
        }
    }

    private static func noon(of date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        return calendar.date(from: components)
    }

    /// 全量序列变更后的统一重算：索引、可见切片、平滑序列、光标重新吸附。
    private func replacePrices(_ updated: [GoldDailyPrice]) {
        prices = updated
        indexByDate = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($1.date, $0) })
        recomputeVisibleSeries()
        if selectedDate != nil {
            selectedPoint = nearestPoint(to: selectedDate)
        }
    }

    private func recomputeVisibleSeries() {
        visiblePrices = range.slice(prices)
        plottablePrices = Self.smoothed(visiblePrices, window: range.smoothingWindow)
    }

    /// 中心移动平均：首尾点保持原值（最新价/最老价不失真），中部窗口随边缘收缩。
    static func smoothed(_ prices: [GoldDailyPrice], window: Int) -> [GoldDailyPrice] {
        guard window >= 3, prices.count > 2 else { return prices }
        let half = window / 2
        let lastIndex = prices.count - 1
        return prices.enumerated().map { index, price in
            if index == 0 || index == lastIndex { return price }
            let radius = min(half, index, lastIndex - index)
            let slice = prices[(index - radius)...(index + radius)]
            let average = slice.map(\.close).reduce(0, +) / Double(slice.count)
            return GoldDailyPrice(date: price.date, open: price.open, high: price.high, low: price.low, close: average)
        }
    }

    private func nearestPoint(to date: Date?) -> GoldDailyPrice? {
        guard let date else { return nil }
        return plottablePrices.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    // MARK: 统计（供视图展示）

    /// 头条价格：优先取十字光标选中日，否则最新一日（实时报价已就地写入）。
    var headlinePoint: GoldDailyPrice? {
        selectedPoint ?? prices.last
    }

    /// 头条价格相对前一交易日收盘的涨跌（点值与百分比）。
    var headlineChange: (amount: Double, percent: Double)? {
        guard let point = headlinePoint,
              let index = indexByDate[point.date],
              index > 0
        else { return nil }
        let previous = prices[index - 1]
        let diff = point.close - previous.close
        guard previous.close > 0 else { return nil }
        return (diff, diff / previous.close * 100)
    }
}
