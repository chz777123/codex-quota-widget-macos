import Foundation

// Only initialize and account/rateLimits/read. No inference, resets or credential extraction.
enum CodexClient {
    static func executable() throws -> URL {
        let custom = UserDefaults.standard.string(forKey: "codexPath") ?? ""
        let paths = [custom, "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let path = paths.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw failure("找不到 Codex。请安装 Codex，或在设置中选择可执行文件。")
        }
        return URL(fileURLWithPath: path)
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "CodexQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func fetch() throws -> Snapshot {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = try executable()
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "codex_quota_widget", "title": "Codex Quota", "version": "1.0.0"]]])
        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw failure("同步未完成或已超时。请确认 Codex 已登录并检查网络。") }
            buffer.append(chunk)
            guard buffer.count < 4_000_000 else { throw failure("Codex 返回的数据过大。") }
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int else { continue }
                if object["error"] != nil { throw failure("Codex 无法读取额度。请在 Codex 中确认登录状态后重试。") }
                if id == 1 {
                    try send(["method": "initialized", "params": [:]])
                    try send(["method": "account/rateLimits/read", "id": 2])
                } else if id == 2, let result = object["result"] {
                    let data = try JSONSerialization.data(withJSONObject: result)
                    let limits = try JSONDecoder().decode(LimitsResponse.self, from: data)
                    return Snapshot(fetchedAt: Date(), weekly: limits.codex?.weekly, error: limits.codex?.weekly == nil ? "服务暂未提供每周额度" : nil)
                }
            }
        }
    }
}
