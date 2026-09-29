import Foundation

struct MarketSyncPoint: Codable, Sendable, Equatable {
    let date: String
    let granularity: GoldPointGranularity
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let source: String
    let deleted: Bool
    var key: String { granularity.rawValue + ":" + date }
}
struct MarketSyncPage: Codable, Sendable {
    let series: String
    let unit: String
    let cursor: String
    let reset: Bool
    let points: [MarketSyncPoint]

    func validate(for requestedSeries: String) throws {
        let expectedUnit = requestedSeries == "au9999" ? "CNY/g" : "USD/troy_oz"
        guard series == requestedSeries, unit == expectedUnit, !cursor.isEmpty, cursor.count <= 160 else {
            throw BackendGoldPriceService.ServiceError.malformedPayload
        }
        var keys = Set<String>()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for p in points {
            let parts = p.date.split(separator: "-").compactMap { Int($0) }
            guard p.date.count == 10, parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
                  calendar.component(.year, from: date) == parts[0], calendar.component(.month, from: date) == parts[1],
                  calendar.component(.day, from: date) == parts[2],
                  keys.insert(p.key).inserted, p.granularity != .realtime,
                  (p.granularity != .annual || (series == "xauusd" && parts[0] >= 1900 && parts[0] <= 2015)),
                  !p.source.isEmpty else { throw BackendGoldPriceService.ServiceError.malformedPayload }
            if !p.deleted {
                guard [p.open, p.high, p.low, p.close].allSatisfy({ $0.isFinite && $0 > 0 }) else {
                    throw BackendGoldPriceService.ServiceError.malformedPayload
                }
            }
        }
    }
}
protocol MarketSyncTransport: Sendable {
    func fetchSync(series: String, cursor: String?) async throws -> MarketSyncPage
}
struct BackendMarketSyncTransport: MarketSyncTransport {
    let baseURL: URL
    let session: URLSession
    func fetchSync(series: String, cursor: String?) async throws -> MarketSyncPage {
        var components = URLComponents(url: baseURL.appending(path: "app/market/gold/sync"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "series", value: series)]
        if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendGoldPriceService.ServiceError.badResponse
        }
        struct Envelope: Decodable { let code: Int; let data: MarketSyncPage? }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.code == 0, let page = envelope.data else { throw BackendGoldPriceService.ServiceError.malformedPayload }
        return page
    }
}
