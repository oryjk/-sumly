import SwiftUI
import Charts

/// 参考稿高保真布局，行情统一由 Go 服务提供。
struct HomeView: View {
    @State private var model = MarketHomeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNotice = false

    var body: some View {
        Group {
            if model.showsInitialLoading {
                MarketLoadingView()
            } else {
                dashboard
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.start() }
        }
        .alert("订阅金价", isPresented: $showingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("订阅提醒暂未开放，敬请期待。")
        }
    }

    private var dashboard: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let scale = w / 430
            ZStack(alignment: .topLeading) {
                GoldTheme.background
                Text("黄金价格")
                    .font(.system(size: 22 * scale, weight: .regular))
                    .foregroundStyle(GoldTheme.gold)
                    .position(x: w / 2, y: h * 0.147)

                HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                    Text(model.price.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "—")
                        .font(.system(size: 46 * scale, weight: .bold))
                    Text("¥")
                        .font(.system(size: 22 * scale, weight: .bold))
                }
                .foregroundStyle(GoldTheme.gold)
                .position(x: w * 0.518, y: h * 0.198)
                .accessibilityLabel("黄金价格，\(model.price.map { String(format: "%.2f", $0) } ?? "暂无报价") 元每克")

                Button { showingNotice = true } label: {
                    HStack(spacing: 3 * scale) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 15 * scale))
                        Text("订阅金价")
                            .font(.system(size: 16 * scale, weight: .bold))
                    }
                    .foregroundStyle(GoldTheme.card)
                    .frame(width: 109 * scale, height: 31 * scale)
                    .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                }
                .buttonStyle(.plain)
                .position(x: w / 2, y: h * 0.256)

                HStack(spacing: 18 * scale) {
                    ForEach(MarketRange.allCases, id: \.self) { range in
                        Button {
                            model.range = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 16 * scale))
                                .foregroundStyle(model.range == range ? GoldTheme.card : GoldTheme.serviceText)
                                .frame(width: 63 * scale, height: 30 * scale)
                                .background(model.range == range ? GoldTheme.gold : GoldTheme.card,
                                            in: GoldTheme.rangeShape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.range == range ? .isSelected : [])
                    }
                }
                .position(x: w / 2, y: h * 0.416)

                VStack(spacing: 4 * scale) {
                    Text(model.range == .realtime ? "元/克 · 近20分钟走势" : "元/克 · 国际金价按最新汇率折算")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(GoldTheme.textSecondary)
                    if let message = model.message {
                        Button(message) { Task { await model.refresh() } }
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                }
                .position(x: w / 2, y: h * 0.307)

                trendChart
                    .frame(width: w * 0.944, height: h * 0.304)
                    .position(x: w / 2, y: h * (0.474 + 0.152))
                    .accessibilityLabel("\(model.range.rawValue)黄金价格走势图，\(model.points.count)个行情点")
            }
        }
        .ignoresSafeArea()
    }

    private var trendChart: some View {
        let data = model.points
        let domain = MarketHomeViewModel.chartDomain(data)
        let baseline = domain.lowerBound
        return ZStack {
            Chart {
                ForEach(data, id: \.date) { point in
                    AreaMark(x: .value("时间", point.date),
                             yStart: .value("基线", baseline),
                             yEnd: .value("元/克", point.price))
                        .foregroundStyle(LinearGradient(
                            colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("时间", point.date), y: .value("元/克", point.price))
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if data.count == 1 {
                        PointMark(x: .value("时间", point.date), y: .value("元/克", point.price))
                            .foregroundStyle(GoldTheme.gold)
                    }
                }
                if let point = model.selectedPoint {
                    RuleMark(x: .value("时间", point.date))
                        .foregroundStyle(GoldTheme.gold.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.6))
                    PointMark(x: .value("时间", point.date), y: .value("元/克", point.price))
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(32)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in plot.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let frame = geometry[plotFrame]
                            let x = min(max(value.location.x - frame.minX, 0), frame.width)
                            model.selectedDate = proxy.value(atX: x, as: Date.self)
                        })
                    if let point = model.selectedPoint, let x = proxy.position(forX: point.date) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("¥ " + point.price.formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 14, weight: .semibold))
                            Text(point.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)
                                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(GoldTheme.gold)
                        .padding(10)
                        .frame(width: 162, alignment: .leading)
                        .background(GoldTheme.card, in: GoldTheme.rangeShape)
                        .position(x: min(max(x + 82, 81), max(81, geometry.size.width - 81)), y: 32)
                        .allowsHitTesting(false)
                    }
                }
            }
            if data.isEmpty {
                Text(model.loading ? "正在加载走势…" : (model.range == .realtime ? "暂无最新走势" : "暂无走势数据"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
    }
}
