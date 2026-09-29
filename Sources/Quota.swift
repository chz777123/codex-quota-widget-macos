import Foundation

struct LimitWindow: Codable, Equatable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double? { usedPercent.flatMap { $0.isFinite ? max(0, min(100, 100 - $0)) : nil } }
    var reset: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}
struct Bucket: Codable {
    let limitId: String?
    let limitName: String?
    let primary: LimitWindow?
    let secondary: LimitWindow?
    var weekly: LimitWindow? { [primary, secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 } }
}
struct LimitsResponse: Decodable {
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?
    var codex: Bucket? {
        if let buckets = rateLimitsByLimitId, !buckets.isEmpty { return buckets["codex"] }
        guard rateLimits?.limitId == nil || rateLimits?.limitId == "codex" else { return nil }
        return rateLimits
    }
}
struct Snapshot: Codable {
    var fetchedAt: Date?
    var weekly: LimitWindow?
    var error: String?
    var dailyUsage: DailyUsage?
    static let empty = Snapshot(error: "打开 Codex 周额度以同步")
    static var preview: Snapshot {
        let now = Date()
        return Snapshot(fetchedAt: now,
                        weekly: LimitWindow(usedPercent: 28, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(3 * 86400).timeIntervalSince1970),
                        dailyUsage: DailyUsage(day: DailyUsage.dayKey(now), timeZone: TimeZone.current.identifier,
                                               inputTokens: 2_350_000, outputTokens: 130_000, cachedInputTokens: 1_950_500,
                                               updatedAt: now, isComplete: true))
    }
    func expired(at date: Date) -> Bool { weekly?.reset.map { $0 <= date } ?? false }
    func stale(at date: Date) -> Bool { fetchedAt.map { date.timeIntervalSince($0) > 1800 } ?? true }
    func remaining(at date: Date) -> Double? { expired(at: date) ? nil : weekly?.remaining }
}
enum SnapshotStore {
    // Each process persists only in its own container; live data travels over loopback.
    static func url() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("CodexQuota/quota.json")
    }
    static func read() -> Snapshot {
        guard let url = try? url(), let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return .empty }
        return snapshot
    }
    static func write(_ snapshot: Snapshot) throws {
        let target = try url()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: target, options: .atomic)
    }
}
