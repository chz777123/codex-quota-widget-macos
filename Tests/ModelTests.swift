import Foundation

@main struct ModelTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quota-model-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "quota-tests-" + UUID().uuidString)!
        defaults.register(defaults: ["codexDataPath": root.path])
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1))
        let record: [String: Any] = ["timestamp": stamp, "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": 100, "output_tokens": 10, "cached_input_tokens": 50], "last_token_usage": ["input_tokens": 100, "output_tokens": 10, "cached_input_tokens": 50]]]]
        var data = try JSONSerialization.data(withJSONObject: record); data.append(10)
        try data.write(to: root.appendingPathComponent("sessions/test.jsonl"))
        let failure = QuotaModel(snapshot: .preview, defaults: defaults, reader: UsageReader(cacheURL: root.appendingPathComponent("index.json")), weeklyFetch: { throw NSError(domain: "test", code: 1) }, persist: { _ in })
        await failure.refresh()
        precondition(failure.snapshot.error != nil && failure.snapshot.dailyUsage?.totalTokens == 110)
        precondition(failure.snapshot.weekly?.usedPercent == 28)
        let success = QuotaModel(snapshot: .empty, defaults: defaults, reader: UsageReader(cacheURL: root.appendingPathComponent("index2.json")), weeklyFetch: {
            Thread.sleep(forTimeInterval: 0.1)
            return Snapshot.preview
        }, persist: { _ in })
        await success.refresh()
        precondition(success.snapshot.dailyUsage?.totalTokens == 110 && success.snapshot.weekly?.usedPercent == 28)
        let old = success.snapshot.dailyUsage
        try FileManager.default.removeItem(at: root.appendingPathComponent("sessions"))
        await success.refreshDaily()
        precondition(success.snapshot.dailyUsage?.totalTokens == old?.totalTokens && success.snapshot.dailyUsage?.error != nil)
        precondition(success.snapshot.weekly?.usedPercent == 28)
        print("PASS: weekly failures preserve daily updates, concurrent refresh merges fields, daily failures preserve last successful data")
    }
}
