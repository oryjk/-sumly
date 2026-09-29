import Foundation
import Testing
@testable import Sumly

private actor SyncQueue: MarketSyncTransport {
    var pages: [MarketSyncPage]
    var cursors: [String?] = []
    init(_ pages: [MarketSyncPage]) { self.pages = pages }
    func fetchSync(series: String, cursor: String?) async throws -> MarketSyncPage {
        cursors.append(cursor)
        guard !pages.isEmpty else { throw URLError(.notConnectedToInternet) }
        return pages.removeFirst()
    }
}
private func point(_ day: String, _ price: Double, deleted: Bool = false) -> MarketSyncPoint {
    MarketSyncPoint(date: day, granularity: .daily, open: price, high: price, low: price, close: price, source: "sina-xauusd", deleted: deleted)
}
private func page(_ cursor: String, reset: Bool, _ points: [MarketSyncPoint]) -> MarketSyncPage {
    MarketSyncPage(series: "xauusd", unit: "USD/troy_oz", cursor: cursor, reset: reset, points: points)
}
@Test func marketCachePersistsCursorAndMergesOldCorrectionsAndDeletions() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let transport = SyncQueue([page("v1", reset: true, [point("2016-01-04", 1000), point("2020-01-02", 1500)]), page("v2", reset: false, [point("2016-01-04", 1010), point("2020-01-02", 1500, deleted: true), point("2026-09-28", 4000)])])
    let cache = MarketHistoryCache(directory: folder)
    _ = try await cache.sync(scope: "a", series: "xauusd", transport: transport, now: Date(timeIntervalSince1970: 1000))
    let reopened = MarketHistoryCache(directory: folder)
    #expect(await reopened.cached(scope: "a", series: "xauusd")?.count == 2)
    let merged = try await reopened.sync(scope: "a", series: "xauusd", transport: transport, now: Date(timeIntervalSince1970: 2000))
    #expect(merged.map(\.close) == [1010, 4000])
    #expect(await transport.cursors == [nil, "v1"])
    #expect(await reopened.cached(scope: "another-origin", series: "xauusd") == nil)
    let offline = try await reopened.sync(scope: "a", series: "xauusd", transport: transport, now: Date(timeIntervalSince1970: 3000))
    #expect(offline == merged)
}
@Test func marketCacheRejectsMalformedDeltaWithoutAdvancingCursor() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = MarketHistoryCache(directory: folder)
    let transport = SyncQueue([page("v1", reset: true, [point("2016-01-04", 1000)]), page("bad", reset: false, [point("2026-02-30", 1)]), page("v2", reset: false, [])])
    _ = try await cache.sync(scope: "a", series: "xauusd", transport: transport, now: Date(timeIntervalSince1970: 1000))
    _ = try? await cache.sync(scope: "a", series: "xauusd", transport: transport, now: Date(timeIntervalSince1970: 2000))
    let result = try await cache.sync(scope: "a", series: "xauusd", transport: transport, now: Date(timeIntervalSince1970: 3000))
    #expect(result.count == 1)
    #expect(await transport.cursors == [nil, "v1", "v1"])
}
private actor SuspendedSync: MarketSyncTransport {
    var continuation: CheckedContinuation<MarketSyncPage, Never>?
    func fetchSync(series: String, cursor: String?) async throws -> MarketSyncPage {
        await withCheckedContinuation { continuation = $0 }
    }
    func started() -> Bool { continuation != nil }
    func finish() { continuation?.resume(returning: page("v1", reset: true, [point("2016-01-04", 1000)])); continuation = nil }
}
@Test func clearingMarketCacheInvalidatesPendingDownload() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = MarketHistoryCache(directory: folder)
    let transport = SuspendedSync()
    let pending = Task { try await cache.sync(scope: "a", series: "xauusd", transport: transport) }
    while !(await transport.started()) { await Task.yield() }
    try await cache.clear()
    await transport.finish()
    do { _ = try await pending.value; Issue.record("cleared download was applied") } catch { }
    #expect(await cache.cached(scope: "a", series: "xauusd") == nil)
    #expect(await MarketHistoryCache(directory: folder).cached(scope: "a", series: "xauusd") == nil)
}
@Test func lastQuoteCacheIsScopedAndCannotBeWrittenAfterClear() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = MarketHistoryCache(directory: folder)
    let generation = await cache.token()
    let quote = GoldQuote(symbol: "XAUUSD", price: 4000, open: 3900, high: 4100, low: 3800, prevClose: 3950, usdCNY: 7, cnyPerGram: 900, asOf: .now)
    try await cache.saveQuote(quote, scope: "a", series: "xauusd", generation: generation)
    #expect(await MarketHistoryCache(directory: folder).cachedQuote(scope: "a", series: "xauusd") == quote)
    #expect(await cache.cachedQuote(scope: "b", series: "xauusd") == nil)
    try await cache.clear()
    do { try await cache.saveQuote(quote, scope: "a", series: "xauusd", generation: generation); Issue.record("stale quote saved") } catch { }
    #expect(await cache.cachedQuote(scope: "a", series: "xauusd") == nil)
}
@Test func corruptMarketCacheFallsBackToFullSnapshot() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = MarketHistoryCache(directory: folder)
    let transport = SyncQueue([page("v1", reset: true, [point("2016-01-04", 1000)]), page("v2", reset: true, [point("2016-01-04", 1010)])])
    _ = try await first.sync(scope: "a", series: "xauusd", transport: transport)
    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
        try Data("truncated".utf8).write(to: file)
    }
    let reopened = MarketHistoryCache(directory: folder)
    #expect(await reopened.cached(scope: "a", series: "xauusd") == nil)
    let points = try await reopened.sync(scope: "a", series: "xauusd", transport: transport)
    #expect(points.first?.close == 1010)
    #expect(await transport.cursors == [nil, nil])
}
@Test func cancelledMarketSyncDoesNotAdvanceCursor() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = MarketHistoryCache(directory: folder)
    let transport = SuspendedSync()
    let pending = Task { try await cache.sync(scope: "a", series: "xauusd", transport: transport) }
    while !(await transport.started()) { await Task.yield() }
    pending.cancel()
    await transport.finish()
    do { _ = try await pending.value; Issue.record("cancelled caller committed its download") } catch { }
    #expect(await cache.cached(scope: "a", series: "xauusd") == nil)
    #expect(await MarketHistoryCache(directory: folder).cached(scope: "a", series: "xauusd") == nil)
}
@Test func syncPreservesSourceCloseWhenHistoricalOHLCBoundsDisagree() throws {
    let original = MarketSyncPoint(date: "2012-12-25", granularity: .daily, open: 1660.69, high: 1657.01, low: 1656.51, close: 1658.79, source: "sina-xauusd", deleted: false)
    try page("v1", reset: true, [original]).validate(for: "xauusd")
}
