import SwiftUI
import SwiftData

// MARK: - 添加表单

struct AddHoldingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let marketBasis: GoldMarketBasis

    @State private var gramsText = ""
    @State private var purchasePrice: HoldingPurchasePriceModel
    @State private var timestamp = Date.now
    @State private var note = ""
    @State private var brand = ""
    @State private var feeText = ""
    @State private var channel = ""
    private let targetBook: String?
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @State private var errorMessage: String?
    @FocusState private var gramsFocused: Bool

    init(defaultUnitPrice: Double?, date: Date = .now, book: String? = nil, marketBasis: GoldMarketBasis = .domestic) {
        targetBook = book
        _timestamp = State(initialValue: min(date, .now))
        self.marketBasis = marketBasis
        _purchasePrice = State(initialValue: HoldingPurchasePriceModel(
            date: min(date, .now), basis: marketBasis, initialPrice: defaultUnitPrice,
            service: BackendGoldPriceService(instrumentID: marketBasis.instrumentID)
        ))
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
                    fieldRow(label: "购入时间") {
                        DatePicker(
                            "购入时间",
                            selection: Binding(get: { timestamp }, set: {
                                timestamp = $0
                                purchasePrice.selectDate($0)
                            }),
                            in: ...Date.now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                    fieldRow(label: "购入单价（元/克）") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("请输入实际购入单价", text: Binding(get: { purchasePrice.priceText }, set: { purchasePrice.editPrice($0) }))
                                .keyboardType(.decimalPad)
                            priceReferenceStatus
                        }
                    }
                    fieldRow(label: "品牌（可选）") { TextField("例如 周生生、周大福", text: $brand) }
                    fieldRow(label: "额外费用（元，可选）") { TextField("0", text: $feeText).keyboardType(.decimalPad) }
                    fieldRow(label: "购买渠道（可选）") { TextField("例如 门店、银行", text: $channel) }
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
        .task(id: purchasePrice.selectedDay) { await purchasePrice.load() }
    }

    private var priceReferenceStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if purchasePrice.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在获取所选日期参考价…")
                }
            }
            if let reference = purchasePrice.reference {
                Text(referenceDescription(reference))
                if purchasePrice.isManual {
                    HStack {
                        Text("已手动填写，保存使用你的单价")
                        Spacer(minLength: 8)
                        Button("使用参考价") { purchasePrice.useReference() }
                            .foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                    }
                } else {
                    Text("参考价仅用于预填，可改为实际成交价")
                }
            }
            if let issue = purchasePrice.issue {
                HStack(alignment: .center, spacing: 8) {
                    Text(issueDescription(issue))
                    Spacer(minLength: 0)
                    if issue != .missingDay {
                        Button("重试") { Task { await purchasePrice.load() } }
                            .foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                            .disabled(purchasePrice.isLoading)
                    }
                }
            }
        }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
    }
    private func referenceDescription(_ reference: HoldingPurchasePriceReference) -> String {
        if !reference.isHistorical { return "参考 · \(marketBasis.title)最新可用金价 \(reference.price.moneyText) 元/克" }
        let day = HoldingsSelection.dateText(reference.date)
        if let fx = reference.exchangeRate {
            return "参考 · \(day)国际收盘价，按最新可用汇率 \(fx.formatted(.number.precision(.fractionLength(2...4)))) 折算为 \(reference.price.moneyText) 元/克（非历史人民币成交价）"
        }
        return "参考 · \(day)国内收盘价 \(reference.price.moneyText) 元/克"
    }
    private func issueDescription(_ issue: HoldingPurchasePriceModel.Issue) -> String {
        switch issue {
        case .missingDay: "当天没有日线报价，请填写实际购入单价"
        case .missingExchangeRate: "汇率暂不可用，请填写实际购入单价"
        case .unavailable: "参考价暂未获取成功，可手动填写购入单价"
        }
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
        let price = purchasePrice.validPrice

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

        let record = HoldingRecord(grams: grams, unitPriceCNY: price, timestamp: timestamp, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        record.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fee = Double(feeText.isEmpty ? "0" : feeText), fee.isFinite, fee >= 0 else {
            errorMessage = "请输入有效的额外费用"; return
        }
        record.extraFee = fee
        record.purchaseChannel = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        record.bookName = targetBook ?? book
        modelContext.insert(record)
        do { try modelContext.save() } catch {
            modelContext.rollback()
            errorMessage = "保存失败，请重试。"
            return
        }
        dismiss()
    }
}

// MARK: - 金额格式化

extension Double {
    /// 925.93
    var moneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)))
    }

    /// +24.98 / −12.30
    var signedMoneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)).sign(strategy: .always()))
    }
}
