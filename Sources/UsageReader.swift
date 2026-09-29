import Foundation
import CryptoKit

/// Reads numerical usage events only. The cache never contains prompts, tool output or credentials.
actor UsageReader {
    private struct Counts: Codable, Equatable {
        var input_tokens: Int64?
        var output_tokens: Int64?
        var cached_input_tokens: Int64?
        var valid: Bool {
            guard let i = input_tokens, let o = output_tokens else { return false }
            return i >= 0 && o >= 0 && i <= Int64.max / 4 && o <= Int64.max / 4
        }
        var cache: Int64? {
            guard let c = cached_input_tokens, let i = input_tokens, c >= 0 && c <= i else { return nil }
            return c
        }
    }
    private struct Envelope: Decodable {
        var timestamp: String?
        var type: String?
        var payload: Payload?
        struct Payload: Decodable {
            var type: String?
            var id: String?
            var info: Info?
        }
        struct Info: Decodable {
            var total_token_usage: Counts?
            var last_token_usage: Counts?
        }
    }
    private struct Record: Codable {
        var key: String
        var date: Date
        var input: Int64?
        var output: Int64?
        var cached: Int64?
        var complete: Bool
        var derived: Bool
    }
    private struct FileIndex: Codable {
        var identity: String
        var path: String
        var size: UInt64 = 0
        var offset: UInt64 = 0
        var modified: Date = .distantPast
        var anchor: String = ""
        var sessionID: String?
        var previous: Counts?
        var records: [Record] = []
        var malformed = false
    }
    private struct Index: Codable {
        var version = 1
        var root: String
        var files: [String: FileIndex] = [:]
    }
    private let cacheURL: URL
    private var index: Index?
    private(set) var bytesRead: UInt64 = 0
    init(cacheURL: URL) { self.cacheURL = cacheURL }
    static var defaultRoot: URL {
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? ""
        return URL(fileURLWithPath: configured.isEmpty ? NSHomeDirectory() + "/.codex" : (configured as NSString).expandingTildeInPath)
    }
    static func root(custom: String) -> URL {
        custom.isEmpty ? defaultRoot : URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
    }
    static func validateRoot(_ root: URL) throws {
        var directory: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue,
              fm.isReadableFile(atPath: root.path),
              ["sessions", "archived_sessions"].contains(where: {
                  var d: ObjCBool = false
                  return fm.fileExists(atPath: root.appendingPathComponent($0).path, isDirectory: &d) && d.boolValue
              }) else {
            throw NSError(domain: "CodexQuota.Usage", code: 1, userInfo: [NSLocalizedDescriptionKey: "数据目录不可读或缺少 sessions / archived_sessions，请选择本机 Codex 数据目录。"])
        }
    }
    func read(root: URL, now: Date = Date(), timeZone: TimeZone = .current) -> DailyUsage {
        bytesRead = 0
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        do {
            try Self.validateRoot(root)
            if index?.root != root.path {
                index = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
                if index?.version != 1 || index?.root != root.path { index = Index(root: root.path) }
            }
            var state = index ?? Index(root: root.path)
            var files: [URL] = []
            var inaccessible = false
            let fm = FileManager.default
            for name in ["sessions", "archived_sessions"] {
                let directory = root.appendingPathComponent(name)
                guard fm.fileExists(atPath: directory.path) else { continue }
                guard let iterator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in inaccessible = true; return true }) else {
                    inaccessible = true; continue
                }
                for case let url as URL in iterator where url.pathExtension == "jsonl" {
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values?.isRegularFile == true && values?.isSymbolicLink != true { files.append(url) }
                }
            }
            var live = Set<String>()
            for url in files.sorted(by: { $0.path < $1.path }) {
                do {
                    let attr = try fm.attributesOfItem(atPath: url.path)
                    let identity = "\(attr[.systemNumber] ?? 0):\(attr[.systemFileNumber] ?? 0):\(attr[.creationDate] ?? Date.distantPast)"
                    live.insert(identity)
                    let size = (attr[.size] as? NSNumber)?.uint64Value ?? 0
                    let modified = attr[.modificationDate] as? Date ?? .distantPast
                    var file = state.files[identity] ?? FileIndex(identity: identity, path: url.path)
                    // Renames, truncation and same-size rewrites rebuild numerical state for this file.
                    if file.path != url.path || size < file.size || (size == file.size && modified != file.modified) {
                        file = FileIndex(identity: identity, path: url.path)
                    }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    if file.offset > 0 && (size != file.size || modified != file.modified) {
                        if try anchor(handle, offset: file.offset) != file.anchor {
                            file = FileIndex(identity: identity, path: url.path)
                        }
                    }
                    if file.offset < size {
                        try consume(handle: handle, file: &file, now: now)
                    }
                    file.size = size
                    file.modified = modified
                    file.anchor = try anchor(handle, offset: file.offset)
                    file.records.removeAll { $0.date < now.addingTimeInterval(-3 * 86400) }
                    state.files[identity] = file
                } catch { inaccessible = true }
            }
            // If enumeration failed, retain unseen numerical records but mark the result incomplete.
            if !inaccessible { state.files = state.files.filter { live.contains($0.key) } }
            index = state
            var result = aggregate(state, now: now, zone: timeZone, incomplete: inaccessible)
            do {
                try fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(state).write(to: cacheURL, options: .atomic)
            } catch {
                result.isComplete = false
                result.error = "统计已更新，但索引缓存无法保存。"
            }
            return result
        } catch {
            return .unavailable(at: now, zone: timeZone, error: error.localizedDescription)
        }
    }
    private func anchor(_ handle: FileHandle, offset: UInt64) throws -> String {
        guard offset > 0 else { return "" }
        try handle.seek(toOffset: offset > 256 ? offset - 256 : 0)
        let data = try handle.read(upToCount: Int(min(offset, 256))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func consume(handle: FileHandle, file: inout FileIndex, now: Date) throws {
        try handle.seek(toOffset: file.offset)
        var buffer = Data()
        var discarding = false
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            bytesRead += UInt64(chunk.count)
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                let length = line.count + 1
                buffer.removeSubrange(...newline)
                file.offset += UInt64(length)
                if discarding { discarding = false; continue }
                guard line.range(of: Data("\"token_count\"".utf8)) != nil || line.range(of: Data("\"session_meta\"".utf8)) != nil else { continue }
                guard let event = try? decoder.decode(Envelope.self, from: line) else { file.malformed = true; continue }
                if event.type == "session_meta" { file.sessionID = event.payload?.id; continue }
                guard event.type == "event_msg", event.payload?.type == "token_count" else { continue }
                guard let stamp = event.timestamp, let date = fractional.date(from: stamp) ?? seconds.date(from: stamp) else { file.malformed = true; continue }
                let info = event.payload?.info
                // A null info is a rate-limit notification, not a new usage measurement.
                guard let info else { continue }
                let total = info.total_token_usage
                let previous = file.previous
                if let total, total.valid { file.previous = total }
                else { file.previous = nil }
                if let total, total == previous { continue }
                guard date >= now.addingTimeInterval(-3 * 86400) else { continue }
                let last = info.last_token_usage
                var input: Int64?, output: Int64?, cached: Int64?
                var derived = false, complete = true
                if let total, total.valid, let previous, previous.valid,
                   total.input_tokens! >= previous.input_tokens!, total.output_tokens! >= previous.output_tokens! {
                    input = total.input_tokens! - previous.input_tokens!
                    output = total.output_tokens! - previous.output_tokens!
                    if let t = total.cache, let p = previous.cache, t >= p, t - p <= input! { cached = t - p }
                    // Identical input/output with revised cache counts must not add input a second time.
                    if input == 0 && output == 0 { continue }
                    derived = true
                } else if let last, last.valid {
                    input = last.input_tokens; output = last.output_tokens; cached = last.cache
                    // A first record with an inherited lifetime counter only gives a partial baseline.
                    complete = total?.valid == true && total?.input_tokens == last.input_tokens && total?.output_tokens == last.output_tokens
                } else { complete = false }
                if cached == nil { complete = false }
                let numbers: [Int64?] = [total?.input_tokens, total?.output_tokens, total?.cached_input_tokens,
                                        last?.input_tokens, last?.output_tokens, last?.cached_input_tokens]
                let parts = [stamp] + numbers.map { $0.map { String($0) } ?? "?" }
                // Session IDs can change on forks; replayed numerical events keep timestamp and counters.
                let key = SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
                file.records.append(Record(key: key, date: date, input: input, output: output, cached: cached, complete: complete, derived: derived))
            }
            if buffer.count > 16 * 1024 * 1024 {
                file.offset += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: false)
                discarding = true
                file.malformed = true
            }
        }
        // Incomplete JSON at EOF stays on disk and is reread after the writer finishes its line.
        if discarding { file.offset = 0; file.previous = nil; file.records = [] }
    }
    private func aggregate(_ state: Index, now: Date, zone: TimeZone, incomplete: Bool) -> DailyUsage {
        let day = DailyUsage.dayKey(now, timeZone: zone)
        var records: [String: Record] = [:]
        var complete = !incomplete
        for file in state.files.values {
            if file.malformed { complete = false }
            for record in file.records where record.date <= now && DailyUsage.dayKey(record.date, timeZone: zone) == day {
                if let old = records[record.key], old.derived || !record.derived { continue }
                records[record.key] = record
            }
        }
        var input: Int64 = 0, output: Int64 = 0, cached: Int64 = 0
        var cacheKnown = true, anyKnown = records.isEmpty, overflow = false
        func add(_ a: inout Int64, _ b: Int64) {
            let result = a.addingReportingOverflow(b)
            if result.overflow { overflow = true } else { a = result.partialValue }
        }
        for record in records.values {
            complete = complete && record.complete
            if let i = record.input, let o = record.output { add(&input, i); add(&output, o); anyKnown = true }
            else { complete = false; cacheKnown = false }
            if let c = record.cached { add(&cached, c) } else { cacheKnown = false }
        }
        // Unreadable files can hide cache data; do not present an apparently complete percentage.
        cacheKnown = cacheKnown && !incomplete
        complete = complete && !overflow
        let known = anyKnown && !overflow && !(records.isEmpty && !complete)
        return DailyUsage(day: day, timeZone: zone.identifier,
                          inputTokens: known ? input : nil, outputTokens: known ? output : nil,
                          cachedInputTokens: known && cacheKnown ? cached : nil, updatedAt: now,
                          isComplete: complete, error: complete ? nil : "部分统计 · 有记录缺失或不可读")
    }
}
