import Foundation

@main struct UsageTests {
    static func main() async throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("quota-usage-tests-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let utc = TimeZone(secondsFromGMT: 0)!, shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let iso = ISO8601DateFormatter()
        func date(_ s: String) -> Date { iso.date(from: s)! }
        let now = date("2026-09-29T01:00:00Z")
        func fixture(_ name: String) throws -> (URL, URL, UsageReader) {
            let root = temp.appendingPathComponent(name)
            try fm.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
            return (root, root.appendingPathComponent("sessions/a.jsonl"), UsageReader(cacheURL: temp.appendingPathComponent(name + ".index")))
        }
        func counts(_ i: Int64, _ o: Int64, _ c: Int64?) -> [String: Any] {
            var d: [String: Any] = ["input_tokens": i, "output_tokens": o, "reasoning_output_tokens": o / 2, "total_tokens": i + o]
            if let c { d["cached_input_tokens"] = c }
            return d
        }
        func event(_ timestamp: String, _ total: [String: Any], _ last: [String: Any]) throws -> Data {
            var d = try JSONSerialization.data(withJSONObject: ["timestamp": timestamp, "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": total, "last_token_usage": last]]], options: [.sortedKeys])
            d.append(10); return d
        }
        func session(_ id: String) throws -> Data {
            var d = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": id]], options: [.sortedKeys])
            d.append(10); return d
        }
        func append(_ d: Data, _ url: URL) throws {
            let f = try FileHandle(forWritingTo: url); defer { try? f.close() }
            try f.seekToEnd(); try f.write(contentsOf: d)
        }
        let (root, log, reader) = try fixture("daily")
        let first = try event("2026-09-28T15:59:00Z", counts(100, 20, 60), counts(100, 20, 60))
        let second = try event("2026-09-28T16:01:00Z", counts(300, 50, 200), counts(200, 30, 140))
        try (first + second + second).write(to: log)
        let a = await reader.read(root: root, now: now, timeZone: shanghai)
        precondition(a.totalTokens == 230 && a.cachedInputTokens == 140 && a.cacheHitRate == 70 && a.isComplete)
        let again = await reader.read(root: root, now: now, timeZone: shanghai)
        let bytes = await reader.bytesRead
        precondition(again.totalTokens == 230 && bytes == 0, "Unchanged files must not be reread")
        let otherZone = await reader.read(root: root, now: now, timeZone: utc)
        precondition(otherZone.totalTokens == 0 && otherZone.cacheHitRate == nil)
        precondition(!a.isToday(now, timeZone: utc))
        let tomorrow = await reader.read(root: root, now: now.addingTimeInterval(86400), timeZone: shanghai)
        precondition(tomorrow.totalTokens == 0)
        let third = try event("2026-09-29T00:00:00Z", counts(400, 80, 250), counts(100, 30, 50))
        try append(Data(third.dropLast(8)), log)
        let partialLine = await reader.read(root: root, now: now, timeZone: shanghai)
        precondition(partialLine.totalTokens == 230)
        try append(Data(third.suffix(8)), log)
        let incremental = await reader.read(root: root, now: now, timeZone: shanghai)
        let fresh = UsageReader(cacheURL: temp.appendingPathComponent("fresh.index"))
        let full = await fresh.read(root: root, now: now, timeZone: shanghai)
        precondition(incremental == full && full.totalTokens == 360)
        let restarted = UsageReader(cacheURL: temp.appendingPathComponent("daily.index"))
        let restored = await restarted.read(root: root, now: now, timeZone: shanghai)
        let restoredBytes = await restarted.bytesRead
        precondition(restored == full && restoredBytes == 0)
        // A fork replays old numerical events, then adds its own new work.
        let fork = root.appendingPathComponent("sessions/fork.jsonl")
        let fourth = try event("2026-09-29T00:30:00Z", counts(410, 82, 255), counts(10, 2, 5))
        try (first + second + third + fourth).write(to: fork)
        let forked = await reader.read(root: root, now: now, timeZone: shanghai)
        precondition(forked.totalTokens == 372, "Replayed history must not double count")
        let archive = root.appendingPathComponent("archived_sessions")
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.moveItem(at: log, to: archive.appendingPathComponent("a.jsonl"))
        let moved = await reader.read(root: root, now: now, timeZone: shanghai)
        precondition(moved.totalTokens == 372)
        // Truncation removes prior contributions; fresh and incremental agree.
        try fourth.write(to: fork)
        let truncated = await reader.read(root: root, now: now, timeZone: shanghai)
        let rebuilt = await UsageReader(cacheURL: temp.appendingPathComponent("rebuilt.index")).read(root: root, now: now, timeZone: shanghai)
        precondition(truncated == rebuilt && truncated.totalTokens == 372 && !truncated.isComplete)
        let (resetRoot, resetLog, resetReader) = try fixture("reset")
        let r1 = try event("2026-09-29T00:00:00Z", counts(100, 10, 50), counts(100, 10, 50))
        let r2 = try event("2026-09-29T00:01:00Z", counts(20, 2, 10), counts(20, 2, 10))
        try (r1+r2).write(to: resetLog)
        let reset = await resetReader.read(root: resetRoot, now: now, timeZone: utc)
        precondition(reset.totalTokens == 132 && reset.cachedInputTokens == 60)
        let missingCache = try event("2026-09-29T00:02:00Z", counts(30, 5, nil), counts(10, 3, nil))
        try append(missingCache, resetLog)
        let missing = await resetReader.read(root: resetRoot, now: now, timeZone: utc)
        precondition(missing.totalTokens == 145 && missing.cacheHitRate == nil && !missing.isComplete)
        let (emptyRoot, emptyLog, emptyReader) = try fixture("empty")
        let zero = try event("2026-09-29T00:00:00Z", counts(0, 0, 0), counts(0, 0, 0))
        try zero.write(to: emptyLog)
        let empty = await emptyReader.read(root: emptyRoot, now: now, timeZone: utc)
        precondition(empty.totalTokens == 0 && empty.cacheHitRate == nil && empty.isComplete)
        let absent = await emptyReader.read(root: temp.appendingPathComponent("absent"), now: now, timeZone: utc)
        precondition(absent.totalTokens == nil && absent.error != nil)
        try append(Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",bad}\n".utf8), emptyLog)
        let corrupt = await emptyReader.read(root: emptyRoot, now: now, timeZone: utc)
        precondition(!corrupt.isComplete)
        let (rewriteRoot, rewriteLog, rewriteReader) = try fixture("rewrite")
        let sameSizeA = try event("2026-09-29T00:00:00Z", counts(100, 10, 50), counts(100, 10, 50))
        let sameSizeB = try event("2026-09-29T00:00:00Z", counts(200, 12, 60), counts(200, 12, 60))
        precondition(sameSizeA.count == sameSizeB.count)
        try sameSizeA.write(to: rewriteLog)
        _ = await rewriteReader.read(root: rewriteRoot, now: now, timeZone: utc)
        try sameSizeB.write(to: rewriteLog)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: rewriteLog.path)
        let rewritten = await rewriteReader.read(root: rewriteRoot, now: now, timeZone: utc)
        precondition(rewritten.totalTokens == 212)
        let (missingRoot, missingLog, missingReader) = try fixture("missing-fields")
        let absentCounts = try event("2026-09-29T00:00:00Z", [:], [:])
        try absentCounts.write(to: missingLog)
        let noCounts = await missingReader.read(root: missingRoot, now: now, timeZone: utc)
        precondition(noCounts.totalTokens == nil && noCounts.cacheHitRate == nil && !noCounts.isComplete)
        let old = try JSONDecoder().decode(Snapshot.self, from: Data("{\"error\":\"old\"}".utf8))
        precondition(old.dailyUsage == nil)
        let oldUsage = try JSONDecoder().decode(DailyUsage.self, from: Data("{\"day\":\"2026-09-29\",\"timeZone\":\"UTC\",\"inputTokens\":10,\"outputTokens\":2,\"cachedInputTokens\":1,\"isComplete\":true}".utf8))
        precondition(oldUsage.averageOutputTokensPerSecond == nil && oldUsage.latestOutputTokensPerSecond == nil && oldUsage.speedSampleCount == nil)
        let cache = try String(contentsOf: temp.appendingPathComponent("daily.index"), encoding: .utf8)
        precondition(!cache.contains("last_token_usage") && !cache.contains("reasoning_output_tokens"))
        precondition(TokenFormat.compact(999_999) == "1M" && TokenFormat.compact(nil) == "—")
        precondition(TokenFormat.speed(7.142857) == "7.1")
        precondition(TokenFormat.speed(1_260) == "1.3K")
        precondition(TokenFormat.speed(nil) == "—")

        // Output speed uses only adjacent, same-session events and weights
        // the daily average by valid elapsed seconds.
        let (speedRoot, speedLog, speedReader) = try fixture("speed")
        let s1 = try event("2026-09-29T00:00:00Z", counts(100, 100, 50), counts(100, 100, 50))
        let s2 = try event("2026-09-29T00:00:10Z", counts(300, 300, 150), counts(200, 200, 100))
        let s3 = try event("2026-09-29T00:01:10Z", counts(600, 600, 300), counts(300, 300, 150))
        let zeroOutput = try event("2026-09-29T00:02:10Z", counts(610, 600, 305), counts(10, 0, 5))
        let s4 = try event("2026-09-29T00:02:20Z", counts(710, 700, 355), counts(100, 100, 50))
        let longGap = try event("2026-09-29T00:10:00Z", counts(810, 800, 405), counts(100, 100, 50))
        try (s1 + s2 + s3 + zeroOutput + s4 + longGap).write(to: speedLog)
        let speed = await speedReader.read(root: speedRoot, now: now, timeZone: utc)
        precondition(speed.totalTokens == 1_610 && speed.speedSampleCount == 3)
        precondition(abs((speed.averageOutputTokensPerSecond ?? 0) - (600.0 / 80.0)) < 0.0001)
        precondition(abs((speed.latestOutputTokensPerSecond ?? 0) - 10.0) < 0.0001)

        // A session change breaks the window; a replayed copy is deduped.
        let sessionLog = speedRoot.appendingPathComponent("sessions/session.jsonl")
        let q1 = try session("A")
        let q2 = try event("2026-09-29T00:20:00Z", counts(900, 900, 450), counts(90, 100, 45))
        let q3 = try session("B")
        let q4 = try event("2026-09-29T00:20:10Z", counts(1_000, 1_000, 500), counts(100, 100, 50))
        try (q1 + q2 + q3 + q4).write(to: sessionLog)
        let sessionResult = await speedReader.read(root: speedRoot, now: now, timeZone: utc)
        precondition(sessionResult.speedSampleCount == 3, "Cross-session events must not add a speed sample")
        let replay = speedRoot.appendingPathComponent("sessions/replay.jsonl")
        try (s1 + s2 + s3 + zeroOutput + s4 + longGap).write(to: replay)
        let replayResult = await speedReader.read(root: speedRoot, now: now, timeZone: utc)
        precondition(replayResult.speedSampleCount == sessionResult.speedSampleCount && replayResult.averageOutputTokensPerSecond == sessionResult.averageOutputTokensPerSecond)
        print("PASS: daily/timezone boundaries, weighted cache rate, replay/fork/duplicate/archival dedup, incremental/restart equivalence, truncation, resets, incomplete tails, missing cache, zero input, invalid roots, malformed records, old snapshots")
    }
}
