import Foundation

// Only initialize and account/rateLimits/read. No inference, resets or credential extraction.
enum CodexClient {
    static func executable() throws -> URL {
        try CodexLocation.executable(custom: UserDefaults.standard.string(forKey: "codexPath") ?? "")
    }

    static func failure(_ message: String) -> NSError { NSError(domain: "CodexQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func fetch(executable: URL? = nil) throws -> Snapshot {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = try executable ?? self.executable()
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw failure("Codex 启动失败：\(error.localizedDescription)。请重新选择有效的应用或可执行文件。") }
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
                    guard let weekly = limits.codex?.weekly else { throw failure("额度读取失败：服务暂未提供每周额度。") }
                    return Snapshot(fetchedAt: Date(), weekly: weekly, error: nil)
                }
            }
        }
    }
}
