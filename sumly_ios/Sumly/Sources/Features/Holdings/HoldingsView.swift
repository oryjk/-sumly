import SwiftUI
import SwiftData

/// 持仓页：黄金克数记录、实时估值与收益。
struct HoldingsView: View {
    @Query(sort: \HoldingRecord.timestamp, order: .reverse)
    private var records: [HoldingRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var model = HoldingsViewModel()
    @State private var showingAdd = false
    @State private var hideAmounts = false
    @ScaledMetric(relativeTo: .largeTitle) private var gramsFontSize: CGFloat = 48

    var body: some View {
        ZStack {
            GoldTheme.background.ignoresSafeArea()
            content
        }
        .task { await model.start() }
        .sheet(isPresented: $showingAdd) {
            AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram)
        }
    }

    private var content: some View {
        List {
            Group {
                summaryCard
                Button {
                    showingAdd = true
                } label: {
                    Label("添加黄金", systemImage: "plus")
                }
                .buttonStyle(GoldPrimaryButtonStyle())
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            if records.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(records) { record in
                    HoldingRowView(
                        record: record,
                        profit: model.recordProfit(record),
                        hideAmounts: hideAmounts
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(16, for: .scrollContent)
    }

    // MARK: - 汇总卡（总克数 + 购入总价 / 最新估值 / 预估收益）

    private var summaryCard: some View {
        let stats = model.stats(for: records)
        let perGram = model.quote?.cnyPerGram ?? 0
        return VStack(spacing: 14) {
            HStack {
                Text("总持有（克）")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer()
                Button {
                    hideAmounts.toggle()
                } label: {
                    Image(systemName: hideAmounts ? "eye.slash" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .accessibilityLabel(hideAmounts ? "显示金额" : "隐藏金额")
            }

            Text(masked(stats.totalGrams.formatted(.number.precision(.fractionLength(2)))))
                .font(.system(size: gramsFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(GoldTheme.gold)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.4)
                .lineLimit(1)

            HStack(spacing: 0) {
                statCell("购入总价(元)", masked(stats.totalCost.moneyText))
                statDivider
                statCell(
                    "最新估值(元)",
                    stats.hasValuation ? masked(stats.totalValue.moneyText) : "—"
                )
                statDivider
                statCell(
                    "预估收益(元)",
                    stats.hasValuation ? masked(stats.profit.signedMoneyText) : "—",
                    color: stats.profit >= 0 ? GoldTheme.up : GoldTheme.down // 红涨绿跌
                )
            }

            HStack {
                if perGram > 0 {
                    Text("金价 \(perGram.formatted(.number.precision(.fractionLength(2)))) 元/克 · 实时刷新")
                } else {
                    Text("正在获取金价…")
                }
                Spacer()
                if let quote = model.quote {
                    Text(quote.asOf.formatted(.dateTime.hour().minute()))
                }
            }
            .font(.caption2)
            .foregroundStyle(GoldTheme.textFaint)
        }
        .goldCard()
        .animation(.snappy(duration: 0.25), value: model.quote)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(GoldTheme.gridline)
            .frame(width: 1, height: 28)
    }

    private func statCell(_ label: String, _ value: String, color: Color = GoldTheme.text) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44))
                .foregroundStyle(GoldTheme.gold)
            Text("还没有持仓记录")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(GoldTheme.text)
            Text("点击「添加黄金」，记录克数与买入时间，\n自动按最新金价估值")
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func delete(_ record: HoldingRecord) {
        modelContext.delete(record)
        try? modelContext.save()
    }

    /// 隐藏金额时统一用星号遮罩。
    private func masked(_ text: String) -> String {
        hideAmounts ? "✱✱✱" : text
    }
}

// MARK: - 记录行

private struct HoldingRowView: View {
    let record: HoldingRecord
    let profit: Double?
    let hideAmounts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(record.unitPriceCNY.formatted(.number.precision(.fractionLength(2))))元/克")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(GoldTheme.onGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                Spacer()
                if let profit {
                    Text(profit.signedMoneyText)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(profit >= 0 ? GoldTheme.up : GoldTheme.down) // 红涨绿跌
                }
            }

            Text(masked(
                "\(record.grams.formatted(.number.precision(.fractionLength(2))))克 · "
                    + (record.grams * record.unitPriceCNY).moneyText + "元"
            ))
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(GoldTheme.text)

            HStack(spacing: 8) {
                Label(
                    record.timestamp.formatted(.dateTime.year().month().day().hour().minute()),
                    systemImage: "clock"
                )
                if !record.note.isEmpty {
                    Text(record.note)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(GoldTheme.textFaint)
        }
        .padding(14)
        .background(GoldTheme.card, in: GoldTheme.cardShape)
        .overlay(GoldTheme.cardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func masked(_ text: String) -> String {
        hideAmounts ? "✱✱✱" : text
    }
}

// MARK: - 添加表单

struct AddHoldingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 进入表单时的当前「元/克」价，用于预填购入单价。
    let defaultUnitPrice: Double?

    @State private var gramsText = ""
    @State private var priceText = ""
    @State private var timestamp = Date.now
    @State private var note = ""
    @State private var errorMessage: String?
    @FocusState private var gramsFocused: Bool

    init(defaultUnitPrice: Double?) {
        self.defaultUnitPrice = defaultUnitPrice
        _priceText = State(
            initialValue: defaultUnitPrice.map { String(format: "%.2f", $0) } ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    fieldRow(label: "克数") {
                        TextField("例如 5.5", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .focused($gramsFocused)
                    }
                    fieldRow(label: "购入单价（元/克）") {
                        TextField(defaultUnitPrice != nil ? "当前金价 \(String(format: "%.2f", defaultUnitPrice!))" : "例如 900.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    fieldRow(label: "持有时间") {
                        DatePicker(
                            "持有时间",
                            selection: $timestamp,
                            in: ...Date.now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                    fieldRow(label: "备注（可选）") {
                        TextField("例如 金条、周大福", text: $note)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(GoldTheme.up)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(GoldTheme.background)
            .navigationTitle("添加黄金")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(GoldTheme.gold)
                }
            }
        }
        .presentationBackground(GoldTheme.background)
        .onAppear { gramsFocused = true }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
            content()
                .font(.system(.body, design: .rounded))
                .foregroundStyle(GoldTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GoldTheme.card, in: GoldTheme.cardShape)
                .overlay(GoldTheme.cardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    private func save() {
        let grams = Double(gramsText.trimmingCharacters(in: .whitespaces))
        var price = Double(priceText.trimmingCharacters(in: .whitespaces))
        if price == nil, let fallback = defaultUnitPrice, fallback > 0 {
            price = fallback // 单价留空时按当前金价计
        }

        guard let grams, grams > 0, grams <= 1_000_000 else {
            errorMessage = "请输入有效的克数（大于 0）"
            return
        }
        guard let price, price > 0, price <= 1_000_000 else {
            errorMessage = "请输入有效的购入单价（元/克）"
            return
        }
        guard timestamp <= .now else {
            errorMessage = "持有时间不能晚于当前时间"
            return
        }

        modelContext.insert(
            HoldingRecord(
                grams: grams,
                unitPriceCNY: price,
                timestamp: timestamp,
                note: note.trimmingCharacters(in: .whitespaces)
            )
        )
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 金额格式化

extension Double {
    /// 925.93
    var moneyText: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    /// +24.98 / −12.30
    var signedMoneyText: String {
        formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
    }
}
