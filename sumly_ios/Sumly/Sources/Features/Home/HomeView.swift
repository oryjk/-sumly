import SwiftUI
import Charts

/// 参考稿高保真布局，行情统一由 Go 服务提供。
struct HomeView: View {
    @Binding private var marketBasis: GoldMarketBasis
    @State private var model: MarketHomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNotice = false
    @State private var showingHistorySources = false
    @State private var showingDates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var basisHighlight
    @State private var highlightedBasis: GoldMarketBasis
    @State private var pendingBasis: GoldMarketBasis?
    @State private var outgoing: MarketHomeViewModel?
    @State private var crossfadeProgress = 1.0
    @State private var basisSwitchTask: Task<Void, Never>?
    @State private var showingBasisError = false
    @State private var transitionID: UUID?

    init(marketBasis: Binding<GoldMarketBasis>) {
        _highlightedBasis = State(initialValue: marketBasis.wrappedValue)
        _marketBasis = marketBasis
        _model = State(initialValue: MarketHomeViewModel(basis: marketBasis.wrappedValue))
    }

    var body: some View {
        Group {
            if model.showsInitialLoading {
                MarketLoadingView()
            } else {
                dashboard
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketCacheCleared)) { _ in
            stopBasisTransition()
            model.clearMarketCache()
        }
        .onDisappear { stopBasisTransition() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopBasisTransition() }
        }
        .alert("口径切换失败", isPresented: $showingBasisError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("已保留原口径数据，请检查网络后重试。")
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.start() }
        }
        .task(id: model.range) {
            if model.range != .realtime { await model.loadHistory() }
        }
        .sheet(isPresented: $showingDates) {
            ChartDateRangeSheet(bounds: model.fullDomain, window: model.xDomain, apply: model.setDateWindow)
        }
        .sheet(isPresented: $showingHistorySources) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.basis == .domestic {
                            Text("国内 · Au99.99").font(.headline)
                            Text("实时价格来自新浪 Au99.99 报价，历史日线来自上海黄金交易所。价格原始单位就是人民币/克，不做美元汇率换算。")
                            Text("走势图只展示真实可用交易数据；周末、休市及缺失日期不补造价格。")
                        } else {
                            Text("1900–2015 · 年度均价参考").font(.headline)
                            Text("来源为 USGS Data Series 140 的名义美元金价统计，按每吨换算为每金衡盎司。1900–1967 年依据世界市场均价，1968 年起依据 Engelhard 年均报价；不是同一市场的逐日收盘序列。年度点仅用当年 7 月定位。")
                            Link("查看 USGS 原始资料", destination: URL(string: "https://www.usgs.gov/media/files/gold-historical-statistics-data-series-140")!)
                            Text("2016 年起 · 每日收盘价").font(.headline)
                            Text("来源为新浪伦敦金日线，仅展示截至昨天已有的交易日收盘数据。当天报价仅在实时走势中显示。周末、休市及缺失数据不补点。")
                            Text("图中元/克按最新美元兑人民币汇率折算，不代表当年的人民币价格，也未作通胀调整。")
                        }
                    }.padding(24)
                }.background(GoldTheme.background).foregroundStyle(GoldTheme.text)
                    .navigationTitle("历史数据说明")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingHistorySources = false } } }
            }.preferredColorScheme(.dark).tint(GoldTheme.gold)
        }
        .alert("订阅金价", isPresented: $showingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("订阅提醒暂未开放，敬请期待。")
        }
    }

    private var dashboard: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    marketBasisPicker
                        .padding(.top, 8)

                    MarketHomeChartContent(model: model, chartHeight: max(200, min(280, geometry.size.height * 0.30)),
                        showingNotice: $showingNotice, showingHistorySources: $showingHistorySources, showingDates: $showingDates)
                        .transaction { $0.animation = nil }
                        .opacity(crossfadeProgress)
                        .overlay(alignment: .top) {
                            if let outgoing {
                                MarketHomeChartContent(model: outgoing, chartHeight: max(200, min(280, geometry.size.height * 0.30)),
                                    showingNotice: $showingNotice, showingHistorySources: $showingHistorySources, showingDates: $showingDates)
                                    .transaction { $0.animation = nil }
                                    .opacity(1 - crossfadeProgress)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                    .onAppear { beginCrossfade() }
                            }
                        }
                        .allowsHitTesting(outgoing == nil)
                }.padding(.horizontal, 18).padding(.bottom, 110)
            }.scrollIndicators(.hidden).background(GoldTheme.background)
        }
    }
    private var marketBasisPicker: some View {
        HStack(spacing: 4) {
            ForEach(GoldMarketBasis.allCases) { basis in
                Button { switchBasis(to: basis) } label: {
                    Text(basis.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(highlightedBasis == basis ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if highlightedBasis == basis {
                                if reduceMotion {
                                    GoldTheme.capsuleShape.fill(GoldTheme.gold)
                                } else {
                                    GoldTheme.capsuleShape.fill(GoldTheme.gold)
                                        .matchedGeometryEffect(id: "basisHighlight", in: basisHighlight)
                                }
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if pendingBasis == basis && outgoing == nil {
                                ProgressView().controlSize(.mini).tint(GoldTheme.goldSoft)
                                    .padding(.trailing, 6)
                            }
                        }
                }
                .buttonStyle(BasisPressStyle())
                .disabled(pendingBasis != nil)
                .accessibilityLabel("黄金口径，" + basis.title)
                .accessibilityAddTraits(model.basis == basis ? .isSelected : [])
                .accessibilityValue(pendingBasis == basis ? "正在切换" : (model.basis == basis ? "已选中" : ""))
                .accessibilityIdentifier("market.basis.\(basis.rawValue)")
            }
        }
        .padding(4)
        .frame(width: 190)
        .background(GoldTheme.card, in: GoldTheme.capsuleShape)

    }

    private func switchBasis(to basis: GoldMarketBasis) {
        guard pendingBasis == nil, basis != model.basis else { return }
        pendingBasis = basis
        transitionID = UUID()
        basisSwitchTask = Task { @MainActor in
            let success = await model.switchBasis(to: basis, beforeCommit: {
                // Capture immediately before the atomic commit, so slow requests
                // never fade the current view out while the next basis is loading.
                outgoing = model.makeDisplaySnapshot()
                crossfadeProgress = 0
            })
            guard !Task.isCancelled else { return }
            guard success else {
                pendingBasis = nil; basisSwitchTask = nil; transitionID = nil
                showingBasisError = true
                return
            }
            marketBasis = basis
            basisSwitchTask = nil
            // The outgoing layer starts the fade on appearance, after SwiftUI
            // has installed the initial old=1/new=0 presentation values.
        }
    }

    private func beginCrossfade() {
        guard let id = transitionID, outgoing != nil, crossfadeProgress == 0 else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.25), completionCriteria: .removed) {
            crossfadeProgress = 1
            highlightedBasis = model.basis
        } completion: {
            guard transitionID == id else { return }
            outgoing = nil
            pendingBasis = nil
            transitionID = nil
        }
    }

    private func stopBasisTransition() {
        basisSwitchTask?.cancel()
        model.cancelBasisSwitch()
        basisSwitchTask = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionID = nil
            outgoing = nil
            crossfadeProgress = 1
            pendingBasis = nil
            highlightedBasis = model.basis
        }
    }
}

private struct BasisPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
