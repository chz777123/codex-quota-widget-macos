import Foundation

struct DailyUsage: Codable, Equatable {
    var day: String
    var timeZone: String
    var inputTokens: Int64?
    var outputTokens: Int64?
    var cachedInputTokens: Int64?
    var updatedAt: Date?
    var isComplete: Bool
    var error: String?
    var averageOutputTokensPerSecond: Double? = nil
    var latestOutputTokensPerSecond: Double? = nil
    var speedSampleCount: Int? = nil

    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    func isToday(_ date: Date, timeZone zone: TimeZone = .current) -> Bool {
        timeZone == zone.identifier && day == Self.dayKey(date, timeZone: zone)
    }
    var totalTokens: Int64? {
        guard let inputTokens, let outputTokens else { return nil }
        let sum = inputTokens.addingReportingOverflow(outputTokens)
        return sum.overflow ? nil : sum.partialValue
    }
    var cacheHitRate: Double? {
        guard let inputTokens, inputTokens > 0, let cachedInputTokens,
              cachedInputTokens >= 0, cachedInputTokens <= inputTokens else { return nil }
        return Double(cachedInputTokens) / Double(inputTokens) * 100
    }
    func stale(at date: Date) -> Bool { updatedAt.map { date.timeIntervalSince($0) > 180 } ?? true }
    static func unavailable(at date: Date, zone: TimeZone, error: String) -> DailyUsage {
        DailyUsage(day: dayKey(date, timeZone: zone), timeZone: zone.identifier, isComplete: false, error: error)
    }
}

enum TokenFormat {
    static func compact(_ count: Int64?) -> String {
        guard let count else { return "—" }
        // Promote before rounding so 999,999 renders as 1M instead of 1000K.
        let n = Double(count)
        for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] where n >= scale * 0.9995 {
            let value = n / scale
            let result = String(format: value >= 100 ? "%.0f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
            return (result.hasSuffix(".0") ? String(result.dropLast(2)) : result) + suffix
        }
        return String(count)
    }
    static func speed(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        if value >= 1000 {
            let n = value / 1000
            let result = String(format: n >= 100 ? "%.0f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), n)
            return (result.hasSuffix(".0") ? String(result.dropLast(2)) : result) + "K"
        }
        let result = String(format: value >= 100 ? "%.0f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        return (result.hasSuffix(".0") ? String(result.dropLast(2)) : result)
    }
}
