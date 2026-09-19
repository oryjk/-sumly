import Foundation

/// 新浪财经全球期货日线接口（伦敦金 XAU）。
///
/// 响应为 JSONP：`/*<script>…</script>*/var t=([{…},{…}]);`
/// 解析时取首个 `[` 到最后一个 `]` 之间的 JSON 数组。
struct SinaGoldPriceService: GoldPriceServicing {
    static let endpoint = URL(
        string: "https://stock.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=XAU"
    )!

    var session: URLSession = .shared
    var referer = "https://finance.sina.com.cn"

    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.parse(data)
    }

    enum ParseError: Error, Equatable {
        case emptyPayload
        case malformedJSONP
        case noValidRows
    }

    private struct DTO: Decodable {
        let date: String
        let open: String
        let high: String
        let low: String
        let close: String
    }

    static func parse(_ data: Data) throws -> [GoldDailyPrice] {
        let text = String(decoding: data, as: UTF8.self)
        guard
              let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end
        else { throw ParseError.emptyPayload }

        let payload = String(text[start...end])
        let rows: [DTO]
        do {
            rows = try JSONDecoder().decode([DTO].self, from: Data(payload.utf8))
        } catch {
            throw ParseError.malformedJSONP
        }

        let points = rows.compactMap(makePoint).sorted { $0.date < $1.date }
        guard !points.isEmpty else { throw ParseError.noValidRows }
        return points
    }

    private static func makePoint(_ dto: DTO) -> GoldDailyPrice? {
        guard let date = GoldDailyPrice.parseDay(dto.date),
              let open = Double(dto.open),
              let high = Double(dto.high),
              let low = Double(dto.low),
              let close = Double(dto.close)
        else { return nil }
        return GoldDailyPrice(date: date, open: open, high: high, low: low, close: close)
    }
}
