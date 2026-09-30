import SwiftUI
import Charts

/// One complete pricing basis, used by both the live and frozen outgoing layer.
struct MarketHomeChartContent: View {
    @Bindable var model: MarketHomeViewModel
    let availableHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var showingNotice: Bool
    @Binding var showingHistorySources: Bool
    @Binding var showingDates: Bool

    var body: some View {
        MarketDashboardLayout(availableHeight: availableHeight) {
            quoteHeader
            chartControls
            VStack(alignment: .leading, spacing: 6) {
                chartCaption
                ChartWindowSummary(statistics: model.windowStatistics)
            }.frame(maxWidth: .infinity, alignment: .leading)

            if model.range == .realtime || model.range.dateBounds() != nil {
                trendChart
                    .accessibilityLabel("\(rangeTitle(model.range))黄金价格走势图，当前区间\(model.windowPoints.count)个行情点")
            } else {
                Text("今年暂无已收盘数据，首个交易日收盘后更新")
                    .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            navigator
        }
    }

    private var quoteHeader: some View {
        VStack(spacing: 4) {
            Text("黄金价格")
                .font(.caption.weight(.medium)).foregroundStyle(GoldTheme.goldSoft)
                .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.price.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "—")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("元/克").font(.caption)
            }.foregroundStyle(GoldTheme.gold)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 44)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("黄金价格，\(model.price.map { String(format: "%.2f", $0) } ?? "暂无报价") 元每克")
            ZStack {
                if let message = model.message {
                    Button(message) { Task { await model.refresh() } }
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }.frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
        }
        .overlay(alignment: .topTrailing) {
            Button { showingNotice = true } label: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("订阅金价")
                .accessibilityIdentifier("market.subscribe")
        }
    }

    @ViewBuilder private var chartControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                rangeMenu
                HStack(spacing: 8) { scalePicker; Spacer(minLength: 0); resetButton }
            }
        } else {
            HStack(spacing: 6) {
                rangeMenu
                Rectangle().fill(GoldTheme.cardStroke).frame(width: 1, height: 22)
                    .accessibilityHidden(true)
                scalePicker
                resetButton
            }
            .padding(.horizontal, 6)
            .background(GoldTheme.card, in: GoldTheme.rangeShape)
        }
    }

    private var rangeMenu: some View {
        Menu {
            Picker("时间区间", selection: $model.range) {
                ForEach(MarketRange.allCases, id: \.self) { range in
                    Text(rangeTitle(range)).tag(range)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(rangeTitle(model.range)).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }.font(.subheadline).foregroundStyle(GoldTheme.goldSoft)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("时间区间")
        .accessibilityValue(rangeTitle(model.range))
        .accessibilityIdentifier("chart.range")
    }

    private var scalePicker: some View {
        HStack(spacing: 2) {
            ForEach(ChartPriceScale.allCases, id: \.self) { scale in
                Button { model.priceScale = scale } label: {
                    Text(scale.rawValue).font(.system(.footnote, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(model.priceScale == scale ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .background(model.priceScale == scale ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.rangeShape)
                }.buttonStyle(.plain)
                    .accessibilityLabel(scale.rawValue + "价格刻度")
                    .accessibilityAddTraits(model.priceScale == scale ? .isSelected : [])
                    .accessibilityIdentifier(scale == .linear ? "chart.scale.linear" : "chart.scale.log")
            }
        }.padding(3).background(GoldTheme.card, in: GoldTheme.rangeShape).fixedSize()
    }

    private var resetButton: some View {
        Button { model.resetViewport() } label: {
            Label("复位", systemImage: "arrow.counterclockwise")
                .font(.footnote.weight(.semibold)).padding(.horizontal, 8).frame(minHeight: 44)
                .foregroundStyle(model.canReset ? GoldTheme.goldSoft : GoldTheme.textFaint)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!model.canReset)
            .fixedSize().accessibilityIdentifier("chart.reset")
    }

    private var navigator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if model.range == .realtime {
                    Text(windowLabel).font(.caption.monospacedDigit()).foregroundStyle(GoldTheme.text)
                } else {
                    Button { showingDates = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(windowLabel).monospacedDigit()
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(GoldTheme.goldSoft)
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("chart.dates")
                }
                Spacer(minLength: 0)
                Text("\(model.windowPoints.count) 个点").font(.caption).foregroundStyle(GoldTheme.textSecondary)
            }.lineLimit(1).minimumScaleFactor(0.8)
            ChartRangeNavigator(points: model.points, bounds: model.fullDomain, window: model.xDomain,
                                scale: model.priceScale, daily: model.range != .realtime,
                                begin: model.beginNavigatorGesture, move: model.moveNavigator, end: model.endChartGesture)
                .disabled(model.points.isEmpty)
            HStack {
                Text(overviewLabel(model.fullDomain.lowerBound))
                Spacer()
                Text(overviewLabel(model.fullDomain.upperBound))
            }.font(.system(size: 10)).foregroundStyle(GoldTheme.textFaint)
            Text("区间内拖动浏览 · 两端缩放 · 主图单指查价")
                .font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func rangeTitle(_ range: MarketRange) -> String {
        if model.basis == .domestic, range == .history { return "全部历史" }
        return range.rawValue
    }

    private var windowLabel: String {
        let window = model.xDomain
        if model.range == .realtime {
            return window.lowerBound.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)) + " — " + window.upperBound.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        }
        return window.lowerBound.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " — " + window.upperBound.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    private var chartCaption: some View {
        HStack(spacing: 8) {
            Text(model.range == .realtime
                 ? "元/克 · 最近 20 分钟"
                 : (model.basis == .domestic ? "截至昨天 · 元/克 · Au99.99" : "截至昨天 · 元/克 · 按最新汇率折算"))
            Button { showingHistorySources = true } label: {
                Image(systemName: "info.circle").foregroundStyle(GoldTheme.goldSoft)
            }.accessibilityLabel("历史数据说明")
        }.font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var trendChart: some View {
        let data = model.visiblePoints
        let domain = model.priceScale.domain(data.map(\.price))
        let baseline = domain.lowerBound
        let statistics = model.windowStatistics
        return ZStack {
            Chart {
                ForEach(data, id: \.date) { point in
                    AreaMark(x: .value("时间", point.date),
                             yStart: .value("基线", baseline),
                             yEnd: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(LinearGradient(
                            colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if data.count == 1 {
                        PointMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                            .foregroundStyle(GoldTheme.gold)
                    }
                }
                if let high = statistics.high {
                    PointMark(x: .value("时间", high.date), y: .value("价格刻度", model.priceScale.value(high.price) ?? baseline))
                        .foregroundStyle(GoldTheme.goldSoft).symbolSize(24)
                }
                if let low = statistics.low, low.price != statistics.high?.price {
                    PointMark(x: .value("时间", low.date), y: .value("价格刻度", model.priceScale.value(low.price) ?? baseline))
                        .foregroundStyle(GoldTheme.goldSoft).symbolSize(24)
                }
                if let point = model.selectedPoint {
                    RuleMark(x: .value("时间", point.date))
                        .foregroundStyle(GoldTheme.gold.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.6))
                    PointMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(32)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: model.xDomain)
            .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartXAxis {
                AxisMarks(values: model.axisDates) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : (value.index == model.axisDates.count - 1 ? .topTrailing : .top)) {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date)).font(.system(size: 10)).foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in plot.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        if model.selectedPoint == nil {
                            if let high = statistics.high {
                                extremumLabel(high, title: high.price == statistics.low?.price ? "最高 / 最低" : "最高", above: true, other: high.price == statistics.low?.price ? nil : statistics.low, proxy: proxy, frame: frame)
                            }
                            if let low = statistics.low, low.price != statistics.high?.price {
                                extremumLabel(low, title: "最低", above: false, other: statistics.high, proxy: proxy, frame: frame)
                            }
                        }
                        ChartGestureSurface(begin: model.beginChartGesture,
                                            transform: model.transformChart,
                                            end: model.endChartGesture,
                                            select: model.selectChart,
                                            reset: model.resetViewport)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityLabel("走势图时间轴")
                            .accessibilityValue("\(axisLabel(model.xDomain.lowerBound))至\(axisLabel(model.xDomain.upperBound))")
                            .accessibilityAction(named: "放大") { model.accessibleZoom(2) }
                            .accessibilityAction(named: "缩小") { model.accessibleZoom(0.5) }
                            .accessibilityAction(named: "复位") { model.resetViewport() }
                    }
                    if let point = model.selectedPoint, let x = proxy.position(forX: point.date) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("¥ " + point.price.formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 14, weight: .semibold))
                            Text(pointLabel(point))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(GoldTheme.gold)
                        .padding(10)
                        .frame(width: 162, alignment: .leading)
                        .background(GoldTheme.card, in: GoldTheme.rangeShape)
                        .position(x: min(max(x + (proxy.plotFrame.map { geometry[$0].minX } ?? 0) + 82, 81), max(81, geometry.size.width - 81)), y: 32)
                        .allowsHitTesting(false)
                    }
                }
            }
            if data.isEmpty {
                Text(model.chartLoading ? "正在加载走势…" : (model.range == .realtime ? "暂无最新走势" : "暂无走势数据"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
    }
    @ViewBuilder
    private func extremumLabel(_ point: MarketChartPoint, title: String, above: Bool, other: MarketChartPoint?, proxy: ChartProxy, frame: CGRect) -> some View {
        if let value = model.priceScale.value(point.price),
           let x = proxy.position(forX: point.date), let y = proxy.position(forY: value) {
            let width = min(126.0, frame.width)
            let centerX = min(max(frame.minX + x, frame.minX + width / 2), frame.maxX - width / 2)
            let otherY = other.flatMap { model.priceScale.value($0.price) }.flatMap { proxy.position(forY: $0) }
            let centerY = frame.minY + ChartExtremaLabelLayout.y(point: y, other: otherY.map { Double($0) }, height: frame.height, above: above)
            VStack(spacing: 3) {
                Text(title + " ¥" + point.price.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(GoldTheme.goldSoft)
                Text(pointLabel(point))
                    .font(.system(size: 9)).foregroundStyle(GoldTheme.textSecondary)
            }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: width, height: 40)
                .background(GoldTheme.card.opacity(0.95), in: GoldTheme.rangeShape)
                .position(x: centerX, y: centerY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title + " " + point.price.formatted(.number.precision(.fractionLength(2))) + " 元每克，" + pointLabel(point))
                .allowsHitTesting(false)
        }
    }

    private func overviewLabel(_ date: Date) -> String {
        if model.range != .realtime { return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) }
        return axisLabel(date)
    }
    private func axisLabel(_ date: Date) -> String {
        let span = model.xDomain.upperBound.timeIntervalSince(model.xDomain.lowerBound)
        if span > 730 * 86400 { return date.formatted(.dateTime.year()) }
        if model.range != .realtime { return date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)) }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
    private func pointLabel(_ point: MarketChartPoint) -> String {
        switch point.granularity {
        case .annual: return point.date.formatted(.dateTime.year()) + " · 年均价参考"
        case .daily: return point.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " · 收盘"
        case .realtime: return point.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        }
    }

}

/// Measure fixed controls first, then give the chart the actual remaining height.
/// Large accessibility text can exceed the screen and use the parent scroll view.
private struct MarketDashboardLayout: Layout {
    let availableHeight: CGFloat
    private let spacing: CGFloat = 10
    private let minimumChartHeight: CGFloat = 140

    private func measurements(width: CGFloat, subviews: Subviews) -> (heights: [CGFloat], total: CGFloat) {
        let proposal = ProposedViewSize(width: width, height: nil)
        var heights = subviews.enumerated().map { index, view in
            index == 3 ? 0 : view.sizeThatFits(proposal).height
        }
        let fixedHeight = heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        if heights.indices.contains(3) {
            heights[3] = max(minimumChartHeight, availableHeight - fixedHeight)
        }
        return (heights, heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: measurements(width: width, subviews: subviews).total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = measurements(width: bounds.width, subviews: subviews).heights
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
            y += heights[index] + spacing
        }
    }
}
