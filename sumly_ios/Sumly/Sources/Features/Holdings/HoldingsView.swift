import SwiftUI
import SwiftData

struct HoldingsView: View {
    @Query(sort: \HoldingRecord.timestamp, order: .reverse) private var records: [HoldingRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @State private var model = HoldingsDesignPreview.makeModel()
    @State private var search = ""
    @State private var filter = HoldingFilter.all
    @State private var sort = HoldingSort.newest
    @State private var sheet: HoldingPageSheet?
    @State private var newBook = ""
    @State private var showingNewBook = false
    @State private var batch = false
    @State private var selection: Set<UUID> = []
    @State private var deleteTargets: [HoldingRecord] = []
    @State private var showingDelete = false
    @State private var transferTargets: [HoldingRecord] = []
    @State private var showingTransfer = false
    @State private var disposing: HoldingRecord?
    @State private var error: String?

    private var books: [String] { Array(Set(savedBooks.components(separatedBy: "\n") + records.map(\.bookName) + ["默认账本"])).sorted() }
    private var bookRecords: [HoldingRecord] { records.filter { $0.bookName == book } }
    private var activeRecords: [HoldingRecord] { bookRecords.filter { $0.disposition == "holding" } }
    private var visibleRecords: [HoldingRecord] { HoldingsSelection.records(records, book: book, search: search, filter: filter, sort: sort, quote: model.quote?.cnyPerGram) }

    var body: some View {
        ZStack {
            GoldTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
                List {
                    summary.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    filters.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    if visibleRecords.isEmpty {
                        emptyState.listRowInsets(EdgeInsets(top: 25, leading: 16, bottom: 0, trailing: 16))
                    }
                    ForEach(visibleRecords) { record in
                        HStack(spacing: 8) {
                            if batch {
                                Button { if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) } } label: {
                                    Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(GoldTheme.gold)
                                }.buttonStyle(.plain).accessibilityLabel("选择持仓")
                            }
                            HoldingRowView(record: record, profit: model.recordProfit(record), hideAmounts: hideAmounts)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(GoldTheme.background)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTargets = [record]; showingDelete = true } label: { Label("删除", systemImage: "trash") }
                            Button { transferTargets = [record]; showingTransfer = true } label: { Label("迁移", systemImage: "folder") }.tint(GoldTheme.textSecondary)
                            Button { disposing = record } label: { Label("赠卖", systemImage: "gift") }.tint(GoldTheme.gold)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .listRowSpacing(0)
                if batch { batchBar.padding(.horizontal, 16).padding(.bottom, 10) }
            }
        }
        .task(id: scenePhase) { if scenePhase == .active { await model.start() } }
        .sheet(item: $sheet) { page in
            switch page {
            case .add: AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram)
            case .calendar: HoldingsCalendarSheet(initialBook: book, hideAmounts: hideAmounts)
            case .history: HoldingsHistorySheet(records: bookRecords.filter { $0.disposition != "holding" }, hideAmounts: hideAmounts)
            case .settings: settings
            }
        }
        .sheet(item: $disposing) { record in DisposeHoldingSheet(record: record) }
        .alert("新建账本", isPresented: $showingNewBook) {
            TextField("账本名称", text: $newBook)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let name = newBook.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                guard !name.isEmpty else { return }
                savedBooks = (books + [name]).joined(separator: "\n"); book = name; search = ""; selection = []
            }
        }
        .confirmationDialog("删除所选持仓？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除 \(deleteTargets.count) 条持仓", role: .destructive) { mutate { deleteTargets.forEach(context.delete) }; selection = [] }
        } message: { Text("删除后无法恢复，购入记录也会移除。") }
        .confirmationDialog("迁移到其他账本", isPresented: $showingTransfer, titleVisibility: .visible) {
            ForEach(books.filter { $0 != book }, id: \.self) { target in
                Button(target) { mutate { transferTargets.forEach { $0.bookName = target } }; selection = [] }
            }
            if books.count == 1 { Button("先新建账本") { newBook = ""; showingNewBook = true } }
        }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") {} } message: { Text(error ?? "请重试") }
        .onChange(of: book) { selection = []; filter = .all }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(books, id: \.self) { name in Button { book = name } label: { Label(name, systemImage: name == book ? "checkmark" : "book.closed") } }
                Divider()
                Button("新建账本", systemImage: "plus") { newBook = ""; showingNewBook = true }
            } label: {
                HStack(spacing: 7) { Text(book).font(.system(size: 18, weight: .bold)).lineLimit(1); Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12)) }
                .foregroundStyle(GoldTheme.text)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                TextField("搜索", text: $search).accessibilityLabel("搜索品牌或备注")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
            }
            .font(.system(size: 13)).foregroundStyle(GoldTheme.textSecondary)
            .padding(.horizontal, 12).frame(width: 126, height: 32).background(GoldTheme.card, in: GoldTheme.capsuleShape)
        }.frame(minHeight: 34)
    }

    private var summary: some View {
        let stats = model.stats(for: activeRecords)
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("总重量(克)").foregroundStyle(GoldTheme.textSecondary)
                Button { hideAmounts.toggle() } label: { Image(systemName: hideAmounts ? "eye.slash" : "eye").foregroundStyle(GoldTheme.text) }
                    .accessibilityLabel(hideAmounts ? "显示金额" : "隐藏金额")
            }.font(.system(size: 13, weight: .medium)).padding(.top, 20)
            Text(mask(stats.totalGrams.moneyText)).font(.system(size: 44, weight: .bold)).monospacedDigit()
                .foregroundStyle(GoldTheme.gold).lineLimit(1).minimumScaleFactor(0.5).frame(height: 60)
            HStack(spacing: 0) {
                metric("购入总价(元)", stats.totalCost.moneyText)
                metric("预估价值(元)", stats.hasValuation ? stats.totalValue.moneyText : "—")
                metric("预估收益(元)", stats.hasValuation ? stats.profit.moneyText : "—", color: stats.profit >= 0 ? GoldTheme.up : GoldTheme.down)
            }.padding(.top, 5)
            HStack(spacing: 16) {
                action("攒金日历", filled: false) { sheet = .calendar }
                action("添加黄金", filled: true) { sheet = .add }
                action("赠卖记录", filled: false) { sheet = .history }
            }.padding(.horizontal, 28).padding(.top, 17).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Button { sheet = .settings } label: { Image(systemName: "gearshape").font(.system(size: 17)) }.accessibilityLabel("攒金设置")
                Button { batch.toggle(); selection = [] } label: { Text(batch ? "完" : "批").font(.system(size: 11)).frame(width: 20, height: 20).overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.textSecondary, lineWidth: 1)) }.accessibilityLabel(batch ? "完成批量管理" : "批量管理")
            }.foregroundStyle(GoldTheme.textSecondary).padding(14)
        }
        .buttonStyle(.plain)
        .listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }

    private func metric(_ title: String, _ value: String, color: Color = GoldTheme.text) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(GoldTheme.textSecondary)
            Text(mask(value)).font(.system(size: 17, weight: .medium)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity)
    }
    private func action(_ title: String, filled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).frame(height: 36)
            .foregroundStyle(filled ? GoldTheme.onGold : GoldTheme.gold)
            .background(filled ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold, lineWidth: 1)) }.buttonStyle(.plain)
    }
    private var filters: some View {
        HStack(spacing: 8) {
            Menu { Picker("筛选", selection: $filter) { ForEach(HoldingFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { filterLabel(filter == .all ? "筛选" : filter.rawValue) }
            Menu { Picker("排序", selection: $sort) { ForEach(HoldingSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { filterLabel("排序") }
            Spacer(minLength: 2)
            Text("*左滑可赠卖、迁移或删除").font(.system(size: 10)).foregroundStyle(GoldTheme.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
        }.listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }
    private func filterLabel(_ title: String) -> some View {
        HStack(spacing: 6) { Text(title); Image(systemName: "chevron.down").font(.system(size: 10)) }.font(.system(size: 12, weight: .semibold)).foregroundStyle(GoldTheme.text).padding(.horizontal, 13).frame(height: 27).background(GoldTheme.card, in: GoldTheme.capsuleShape)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            GoldMoneyBagShape().fill(GoldTheme.gold).frame(width: 30, height: 33)
            Text(activeRecords.isEmpty ? "还没有攒金记录" : "没有符合条件的记录").font(.subheadline).foregroundStyle(GoldTheme.text)
            Text(activeRecords.isEmpty ? "从第一笔黄金开始，慢慢攒下你的底气" : "试试其他关键词或筛选条件").font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }.frame(maxWidth: .infinity).listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }
    private var batchBar: some View {
        HStack {
            Button("全选") { selection = Set(visibleRecords.map(\.id)) }
            Text("已选 \(selection.count) 笔").font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Spacer()
            Button("迁移") { transferTargets = activeRecords.filter { selection.contains($0.id) }; showingTransfer = true }.disabled(selection.isEmpty)
            Button("删除", role: .destructive) { deleteTargets = activeRecords.filter { selection.contains($0.id) }; showingDelete = true }.disabled(selection.isEmpty)
        }.font(.subheadline).padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("估值基准") {
                    LabeledContent("品种", value: "国内黄金 · Au99.99")
                    LabeledContent("来源", value: "新浪 / 上海黄金交易所")
                    LabeledContent("最近报价", value: model.quote.map { "\($0.cnyPerGram.moneyText) 元/克" } ?? "暂不可用")
                    if let quote = model.quote { Text(quote.asOf.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(GoldTheme.textSecondary) }
                }
                Section { Text("预估价值按总克数与最新可用报价计算，实际变现金额可能包含工费、回购价差等差异。持仓记录保存在当前设备。").font(.footnote).foregroundStyle(GoldTheme.textSecondary) }
                Toggle("隐藏金额", isOn: $hideAmounts)
            }.navigationTitle("攒金设置").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
        }.presentationBackground(GoldTheme.background)
    }
    private func mutate(_ operation: () -> Void) { operation(); do { try context.save() } catch { context.rollback(); self.error = "未能保存修改，请重试。" } }
    private func mask(_ text: String) -> String { hideAmounts ? "••••" : text }
}

enum HoldingPageSheet: String, Identifiable { case add, calendar, history, settings; var id: String { rawValue } }

struct HoldingRowView: View {
    let record: HoldingRecord
    let profit: Double?
    let hideAmounts: Bool
    var body: some View {
        VStack(spacing: 17) {
            HStack {
                Text(record.brand.isEmpty ? "未知" : record.brand).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer()
                Text(hideAmounts ? "收益：••••" : "收益：\(profit?.signedMoneyText ?? "—")")
                    .font(.system(size: 15)).monospacedDigit().foregroundStyle((profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 5) {
                Image(systemName: "tag.fill").foregroundStyle(GoldTheme.gold).font(.system(size: 13))
                Text(hideAmounts ? "••••" : "\(record.grams.formatted(.number.precision(.fractionLength(0...2))))克 \((record.grams * record.unitPriceCNY + record.extraFee).formatted(.number.precision(.fractionLength(0...2))))元").lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(HoldingsSelection.dateText(record.timestamp)).monospacedDigit()
            }.font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(GoldTheme.text).padding(.horizontal, 17).padding(.top, 20).padding(.bottom, 17)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(alignment: .topLeading) {
            Text(hideAmounts ? "••••元/克" : "\(record.unitPriceCNY.moneyText)元/克").font(.system(size: 11)).foregroundStyle(GoldTheme.onGold)
                .padding(.horizontal, 11).frame(height: 14).background(GoldTheme.gold, in: GoldTheme.holdingPriceShape)
        }
    }
}
