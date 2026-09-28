import Foundation
@main
struct QuotaTests {
    static func main() throws {
        func decode(_ text: String) throws -> LimitsResponse { try JSONDecoder().decode(LimitsResponse.self, from: Data(text.utf8)) }
        let primary = try decode(#"{"rateLimits":{"primary":{"usedPercent":28,"windowDurationMins":10080}}}"#)
        precondition(primary.codex?.weekly?.remaining == 72)
        let multi = try decode(#"{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":11,"windowDurationMins":300},"secondary":{"usedPercent":35,"windowDurationMins":10080}},"spark":{"primary":{"usedPercent":5,"windowDurationMins":10080}}}}"#)
        precondition(multi.codex?.weekly?.remaining == 65)
        let missing = try decode(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300}}}"#)
        precondition(missing.codex?.weekly == nil)
        let other = try decode(#"{"rateLimitsByLimitId":{"spark":{"primary":{"usedPercent":5,"windowDurationMins":10080}}}}"#)
        precondition(other.codex == nil)
        let unknown = LimitWindow(usedPercent: nil, windowDurationMins: 10080, resetsAt: nil)
        precondition(unknown.remaining == nil)
        precondition(LimitWindow(usedPercent: 150, windowDurationMins: 10080, resetsAt: nil).remaining == 0)
        precondition(LimitWindow(usedPercent: -5, windowDurationMins: 10080, resetsAt: nil).remaining == 100)
        let now = Date()
        let expired = Snapshot(fetchedAt: now, weekly: LimitWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(-1).timeIntervalSince1970))
        precondition(expired.remaining(at: now) == nil)
        precondition(Snapshot(fetchedAt: now.addingTimeInterval(-1801)).stale(at: now))
        let roundtrip = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(expired))
        precondition(roundtrip.weekly == expired.weekly)
        print("PASS: weekly window location, multi-bucket priority, absent data, clamp, expiry, staleness, persistence")
    }
}
