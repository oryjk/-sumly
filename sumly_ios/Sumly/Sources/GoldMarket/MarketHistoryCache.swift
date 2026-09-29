import Foundation
import CryptoKit

extension Notification.Name {
    static let marketCacheCleared = Notification.Name("sumly.marketCacheCleared")
}

/// Dedicated public market cache. Neither SwiftData holdings nor authentication
/// storage are opened here. A generation prevents pre-clear requests resurrecting data.
actor MarketHistoryCache {
    static let shared = MarketHistoryCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "SumlyMarketHistory"))
    private struct Snapshot: Codable {
        let schema: Int
        let scope: String
        let series: String
        let cursor: String
        let checkedAt: Date
        let points: [MarketSyncPoint]
    }
    private let directory: URL
    private var snapshots: [String: Snapshot] = [:]
    private struct Flight { let id: UUID; let task: Task<[MarketSyncPoint], Error> }
    private var flights: [String: Flight] = [:]
    private var generation: UInt = 0
    init(directory: URL) { self.directory = directory }
    func token() -> UInt { generation }

    private func key(_ scope: String, _ series: String) -> String {
        SHA256.hash(data: Data((scope + "\n" + series).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func file(_ key: String) -> URL { directory.appending(path: key + ".json") }
    private func snapshot(scope: String, series: String) -> Snapshot? {
        let id = key(scope, series)
        if let snapshot = snapshots[id] { return snapshot }
        guard let data = try? Data(contentsOf: file(id)),
              let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.schema == 1,
              saved.scope == scope, saved.series == series,
              (try? MarketSyncPage(series: series, unit: series == "au9999" ? "CNY/g" : "USD/troy_oz", cursor: saved.cursor, reset: true, points: saved.points).validate(for: series)) != nil else { return nil }
        snapshots[id] = saved
        return saved
    }
    func cached(scope: String, series: String) -> [MarketSyncPoint]? {
        snapshot(scope: scope, series: series)?.points
    }
    func sync(scope: String, series: String, transport: any MarketSyncTransport, now: Date = .now) async throws -> [MarketSyncPoint] {
        let id = key(scope, series)
        let expectedGeneration = generation
        while true {
            try Task.checkCancellation()
            guard generation == expectedGeneration else { throw CancellationError() }
            let previous = snapshot(scope: scope, series: series)
            if let previous, now.timeIntervalSince(previous.checkedAt) >= 0, now.timeIntervalSince(previous.checkedAt) < 900 { return previous.points }
            let flight: Flight
            if let existing = flights[id] { flight = existing }
            else {
                flight = Flight(id: UUID(), task: Task {
                    try await self.download(scope: scope, series: series, previous: previous, transport: transport, now: now, generation: expectedGeneration)
                })
                flights[id] = flight
            }
            do {
                let points = try await withTaskCancellationHandler {
                    let result = try await flight.task.value
                    try Task.checkCancellation()
                    return result
                } onCancel: {
                    // Cancel synchronously, before a pending response can pass its
                    // cancellation check. Other active callers retry below.
                    flight.task.cancel()
                }
                if flights[id]?.id == flight.id { flights[id] = nil }
                return points
            } catch {
                if flights[id]?.id == flight.id { flights[id] = nil }
                if error is CancellationError, !Task.isCancelled, generation == expectedGeneration { continue }
                throw error
            }
        }
    }
    private func download(scope: String, series: String, previous: Snapshot?, transport: any MarketSyncTransport, now: Date, generation expected: UInt) async throws -> [MarketSyncPoint] {
        let page: MarketSyncPage
        do { page = try await transport.fetchSync(series: series, cursor: previous?.cursor) }
        catch {
            guard expected == generation, !Task.isCancelled else { throw CancellationError() }
            if let previous { return previous.points }
            throw error
        }
        try Task.checkCancellation()
        guard expected == generation else { throw CancellationError() }
        try page.validate(for: series)
        guard previous != nil || page.reset else { throw BackendGoldPriceService.ServiceError.malformedPayload }
        var merged = Dictionary(uniqueKeysWithValues: (page.reset ? [] : (previous?.points ?? [])).map { ($0.key, $0) })
        for point in page.points {
            if point.deleted { merged[point.key] = nil } else { merged[point.key] = point }
        }
        let points = merged.values.sorted { $0.date == $1.date ? $0.key < $1.key : $0.date < $1.date }
        let saved = Snapshot(schema: 1, scope: scope, series: series, cursor: page.cursor, checkedAt: now, points: points)
        // One atomic file contains both cursor and records; no partially advanced cursor.
        let data = try JSONEncoder().encode(saved)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(key(scope, series)), options: .atomic)
        snapshots[key(scope, series)] = saved
        return points
    }
    private struct QuoteSnapshot: Codable {
        let scope: String
        let series: String
        let quote: GoldQuote
    }
    func cachedQuote(scope: String, series: String) -> GoldQuote? {
        guard let data = try? Data(contentsOf: file(key(scope, series) + "-quote")),
              let saved = try? JSONDecoder().decode(QuoteSnapshot.self, from: data),
              saved.scope == scope, saved.series == series,
              saved.quote.price.isFinite, saved.quote.price > 0 else { return nil }
        return saved.quote
    }
    func saveQuote(_ quote: GoldQuote, scope: String, series: String, generation expected: UInt) throws {
        guard generation == expected else { throw CancellationError() }
        let data = try JSONEncoder().encode(QuoteSnapshot(scope: scope, series: series, quote: quote))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(key(scope, series) + "-quote"), options: .atomic)
    }
    func clear() async throws {
        generation &+= 1
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        snapshots.removeAll()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        await MainActor.run { NotificationCenter.default.post(name: .marketCacheCleared, object: nil) }
    }
}
