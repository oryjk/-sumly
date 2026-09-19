import Foundation

/// sumly_go 后端行情接口适配（`/api/v1/app/market/gold/*`）。
/// 行情抓取与缓存由后端负责；这里只消费 `{ code, message, data }` envelope。
struct BackendGoldPriceService: GoldPriceServicing, GoldQuoteServicing, GoldIntradayServicing, GoldRealtimeServicing {
    /// 默认走线上 nginx 反代（`https://oryjk.cn/sumly/`，jd 部署）；
    /// 本地联调可在 Info.plist 用 SUMLY_API_BASE_URL 覆盖（如 http://127.0.0.1:18090/api/v1）。
    static let defaultBaseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SUMLY_API_BASE_URL") as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://oryjk.cn/sumly/api/v1")!
    }()

    var instrumentID: String? = nil
    var baseURL: URL = BackendGoldPriceService.defaultBaseURL
    var session: URLSession = .shared

    enum ServiceError: Error, Equatable {
        case badResponse
        case httpStatus(Int)
        case envelope(Int, String)
        case emptyData
        case malformedPayload
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let data: T?
    }

    struct QuoteDTO: Decodable {
        let symbol: String
        let price: Double
        let open: Double
        let high: Double
        let low: Double
        let prevClose: Double
        let usdCNY: Double
        let cnyPerGram: Double
        let asOf: String

        enum CodingKeys: String, CodingKey {
            case symbol, price, open, high, low
            case prevClose = "prev_close"
            case usdCNY = "usd_cny"
            case cnyPerGram = "cny_per_gram"
            case asOf = "as_of"
        }
    }

    struct DailyDTO: Decodable {
        let symbol: String
        let bars: [BarDTO]
    }

    struct BarDTO: Decodable {
        let date: String
        let open: Double
        let high: Double
        let low: Double
        let close: Double
    }

    // MARK: - GoldPriceServicing

    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        let daily: DailyDTO = try await get("app/market/gold/daily")
        return try Self.decodeDailyBars(daily.bars)
    }

    // MARK: - GoldQuoteServicing

    func fetchQuote() async throws -> GoldQuote {
        let path = instrumentID.map { "app/market/gold/instruments/\($0)/quote" } ?? "app/market/gold/quote"
        let dto: QuoteDTO = try await get(path)
        return try Self.decodeQuote(dto)
    }

    private struct IntradayDTO: Decodable {
        struct Point: Decodable { let time: String; let price: Double }
        let points: [Point]
    }

    func fetchIntraday() async throws -> [MarketChartPoint] {
        let dto: IntradayDTO = try await get("app/market/gold/intraday")
        let points = dto.points.compactMap { point -> MarketChartPoint? in
            guard let date = Self.parseRFC3339(point.time), point.price.isFinite, point.price > 0 else { return nil }
            return MarketChartPoint(date: date, price: point.price)
        }.sorted { $0.date < $1.date }
        guard !points.isEmpty else { throw ServiceError.emptyData }
        return points
    }

    private struct RealtimeDTO: Decodable {
        let unit: String
        let intervalSeconds: Int
        let windowSeconds: Int
        let points: [IntradayDTO.Point]
        enum CodingKeys: String, CodingKey {
            case unit, points
            case intervalSeconds = "interval_seconds"
            case windowSeconds = "window_seconds"
        }
    }

    func fetchRealtime() async throws -> [MarketChartPoint] {
        let dto: RealtimeDTO = try await get("app/market/gold/realtime")
        guard dto.unit == "CNY/g", [5, 60].contains(dto.intervalSeconds), dto.windowSeconds == 1200 else {
            throw ServiceError.malformedPayload
        }
        // 后端明确标记五秒采样或真实分钟回退；客户端不生成缺失点。
        return dto.points.compactMap { point -> MarketChartPoint? in
            guard let date = Self.parseRFC3339(point.time), point.price.isFinite, point.price > 0 else { return nil }
            return MarketChartPoint(date: date, price: point.price)
        }.sorted { $0.date < $1.date }
    }

    // MARK: - 解析（纯函数，供单测）

    static func decodeDailyBars(_ bars: [BarDTO]) throws -> [GoldDailyPrice] {
        let prices = bars.compactMap { bar -> GoldDailyPrice? in
            guard let date = GoldDailyPrice.parseDay(bar.date) else { return nil }
            return GoldDailyPrice(date: date, open: bar.open, high: bar.high, low: bar.low, close: bar.close)
        }.sorted { $0.date < $1.date }
        guard !prices.isEmpty else { throw ServiceError.emptyData }
        return prices
    }

    static func decodeQuote(_ dto: QuoteDTO) throws -> GoldQuote {
        guard let asOf = Self.parseRFC3339(dto.asOf) else { throw ServiceError.malformedPayload }
        return GoldQuote(
            symbol: dto.symbol,
            price: dto.price,
            open: dto.open,
            high: dto.high,
            low: dto.low,
            prevClose: dto.prevClose,
            usdCNY: dto.usdCNY,
            cnyPerGram: dto.cnyPerGram,
            asOf: asOf
        )
    }

    static func parseRFC3339(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    // MARK: - 请求

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.httpStatus(http.statusCode) }
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.code == 0, let payload = envelope.data else {
            throw ServiceError.envelope(envelope.code, envelope.message)
        }
        return payload
    }
}
